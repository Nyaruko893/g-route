import type { BaselineResponse, IpKind, IpMetaResponse } from '../shared/contracts';
import checkShTemplate from '../scripts/check.sh';
import checkPsTemplate from '../scripts/check.ps1';

interface RateLimitBinding {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

interface Env {
  readonly ASSETS: Fetcher;
  readonly RL_BASELINE?: RateLimitBinding;
  readonly RL_IP_META?: RateLimitBinding;
  readonly GITHUB_REPO_URL?: string;
}

const JSON_NO_STORE_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
  'x-content-type-options': 'nosniff',
} as const;

const SAFE_ORIGIN_RE = /^https?:\/\/[a-zA-Z0-9.-]+(?::\d{1,5})?$/;

// Module-level plain-JSON bounded LRU (stores ONLY resolved data, NEVER Promises/Streams per workerd I/O isolation rules)
const LRU_MAX_ENTRIES = 2048;
const POSITIVE_TTL_MS = 12 * 60 * 60 * 1000;
const NEGATIVE_TTL_MS = 5 * 60 * 1000;

interface CacheEntry {
  readonly value: IpMetaResponse;
  readonly expiresAt: number;
}

const metaLru = new Map<string, CacheEntry>();

const UPSTREAM_WINDOW_MS = 60_000;
const UPSTREAM_MAX_PER_WINDOW = 40;
let upstreamWindowStart = 0;
let upstreamCallsInWindow = 0;

function consumeUpstreamBudget(): boolean {
  const now = Date.now();
  if (now - upstreamWindowStart >= UPSTREAM_WINDOW_MS) {
    upstreamWindowStart = now;
    upstreamCallsInWindow = 0;
  }
  if (upstreamCallsInWindow >= UPSTREAM_MAX_PER_WINDOW) {
    return false;
  }
  upstreamCallsInWindow += 1;
  return true;
}

function lruGet(ip: string): IpMetaResponse | null {
  const entry = metaLru.get(ip);
  if (!entry) return null;
  if (Date.now() > entry.expiresAt) {
    metaLru.delete(ip);
    return null;
  }
  metaLru.delete(ip);
  metaLru.set(ip, entry);
  return entry.value;
}

function lruSet(ip: string, value: IpMetaResponse, ttlMs: number): void {
  if (metaLru.has(ip)) {
    metaLru.delete(ip);
  } else if (metaLru.size >= LRU_MAX_ENTRIES) {
    const oldestKey = metaLru.keys().next().value;
    if (oldestKey !== undefined) {
      metaLru.delete(oldestKey);
    }
  }
  metaLru.set(ip, { value, expiresAt: Date.now() + ttlMs });
}

function jsonResponse(payload: unknown, status = 200, extraHeaders?: Record<string, string>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...JSON_NO_STORE_HEADERS,
      ...extraHeaders,
    },
  });
}

function getClientIp(request: Request): { ip: string; isLocalDev: boolean } {
  const cfIp = request.headers.get('cf-connecting-ip');
  const fwd = request.headers.get('x-forwarded-for')?.split(',')[0]?.trim();
  const ip = cfIp ?? fwd ?? '127.0.0.1';
  const hasCfAsn = typeof request.cf?.asn === 'number';
  const isLocalDev = ip === '127.0.0.1' || ip === '::1' || (!cfIp && !hasCfAsn);
  return { ip, isLocalDev };
}

function toRateLimitKey(ip: string): string {
  if (ip.includes(':')) {
    const groups = ip.toLowerCase().split(':').slice(0, 3).join(':');
    return `${groups}::/48`;
  }
  return ip;
}

async function checkRateLimit(
  binding: RateLimitBinding | undefined,
  ip: string,
  isLocalDev: boolean,
): Promise<boolean> {
  if (!binding || isLocalDev) return true;
  try {
    const { success } = await binding.limit({ key: toRateLimitKey(ip) });
    return success;
  } catch {
    return true;
  }
}

function parseIpv4(ip: string): readonly [number, number, number, number] | null {
  const parts = ip.split('.');
  if (parts.length !== 4) return null;
  const nums: number[] = [];
  for (const part of parts) {
    if (!/^\d{1,3}$/.test(part)) return null;
    if (part.length > 1 && part.startsWith('0')) return null;
    const n = Number(part);
    if (!Number.isInteger(n) || n < 0 || n > 255) return null;
    nums.push(n);
  }
  const a = nums[0];
  const b = nums[1];
  const c = nums[2];
  const d = nums[3];
  if (a === undefined || b === undefined || c === undefined || d === undefined) return null;
  return [a, b, c, d];
}

function isPublicIpv4(ip: string): boolean {
  const octets = parseIpv4(ip);
  if (!octets) return false;
  const [a, b] = octets;
  if (a === 0 || a === 10 || a === 127) return false;
  if (a === 100 && b >= 64 && b <= 127) return false;
  if (a === 169 && b === 254) return false;
  if (a === 172 && b >= 16 && b <= 31) return false;
  if (a === 192 && b === 168) return false;
  if (a === 198 && (b === 18 || b === 19)) return false;
  if (a >= 224) return false;
  return true;
}

function isPublicIpv6(ip: string): boolean {
  if (!ip.includes(':') || ip.length > 45) return false;
  if (!/^[0-9a-fA-F:]+$/.test(ip)) return false;
  if (ip.split('::').length - 1 > 1) return false;
  const lower = ip.toLowerCase();
  if (lower === '::' || lower === '::1') return false;
  if (lower.startsWith('fe8') || lower.startsWith('fe9') || lower.startsWith('fea') || lower.startsWith('feb')) {
    return false;
  }
  if (lower.startsWith('fc') || lower.startsWith('fd')) return false;
  if (lower.startsWith('ff')) return false;
  if (lower.startsWith('2001:db8:')) return false;
  return true;
}

function detectPublicIpVersion(ip: string): 4 | 6 | null {
  if (isPublicIpv4(ip)) return 4;
  if (isPublicIpv6(ip)) return 6;
  return null;
}

function classifyIpKind(org: string | null, asn: number | null): IpKind {
  if (!org) return 'unknown';
  const lower = org.toLowerCase();

  if (
    asn === 13335 ||
    /cloudflare|warp|fastly|akamai|cdn77|bunnyway|imperva|incapsula/.test(lower)
  ) {
    return 'cdn_proxy';
  }

  if (
    /kirino|misaka|xtom|frantech|buyvm|sharktech|psychz|cogent|arelion|telia|gtt|zayo|nearoute|akari|kurun|ceranetworks|equinix|multacom|quadranet|serverius|gcore|hyonix|spartan|greencloud|clovux|dedipath|hosthatch|virmach|webhorizon|amazon|aws|google cloud|microsoft|azure|digitalocean|vultr|choopa|hetzner|ovh|linode|oracle|alibaba|aliyun|tencent|datacamp|m247|racknerd|it7|bandwagon|zenlayer|leaseweb|scaleway|contabo|upcloud|kamatera|colocrossing|dmit|host|server|cloud|vps|datacenter|data center/.test(
      lower,
    )
  ) {
    return 'hosting';
  }

  if (
    /telecom|telekom|communications|broadband|comcast|xfinity|verizon|at&t|charter|spectrum|cox |t-mobile|ntt|kddi|softbank|chunghwa|hinet|pccw|hkbn|singtel|starhub|virgin media|british telecom|vodafone|orange|free sas|bell canada|rogers|telus|cable|fiber|fibre|mobile|wireless/.test(
      lower,
    )
  ) {
    return 'isp';
  }

  return 'unknown';
}

async function fetchJsonWithTimeout(url: string, timeoutMs: number): Promise<unknown> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: {
        accept: 'application/json',
        'user-agent': 'g-route-diag/2.0 (stateless-worker)',
      },
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

interface IpWhoRaw {
  success?: boolean;
  country_code?: string;
  city?: string;
  connection?: {
    asn?: number;
    org?: string;
    isp?: string;
  };
}

interface RipeRirRaw {
  data?: {
    rirs?: Array<{
      rir?: string;
      country?: string;
    }>;
  };
}

interface RipeNetInfoRaw {
  data?: {
    asns?: string[];
  };
}

function isObjectRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

async function handleScript(request: Request, env: Env, kind: 'sh' | 'ps'): Promise<Response> {
  const { ip, isLocalDev } = getClientIp(request);
  if (!(await checkRateLimit(env.RL_BASELINE, ip, isLocalDev))) {
    return new Response('# Rate limit exceeded. Retry in 60s.\n', {
      status: 429,
      headers: {
        'content-type': 'text/plain; charset=utf-8',
        'retry-after': '60',
        'x-content-type-options': 'nosniff',
      },
    });
  }

  const url = new URL(request.url);
  const safeOrigin = SAFE_ORIGIN_RE.test(url.origin) ? url.origin : '__G_ROUTE_ORIGIN__';
  const raw = kind === 'sh' ? checkShTemplate : checkPsTemplate;
  const injected = raw.replaceAll('__G_ROUTE_ORIGIN__', safeOrigin);
  // Ensure pure LF for Bash so Windows-hosted builds never emit $'\r' syntax errors on Linux/macOS
  const body = kind === 'sh' ? injected.replace(/\r\n/g, '\n') : injected;

  return new Response(body, {
    status: 200,
    headers: {
      'content-type': 'text/plain; charset=utf-8',
      'cache-control': 'public, max-age=300',
      'x-content-type-options': 'nosniff',
    },
  });
}

async function handleBaseline(request: Request, env: Env): Promise<Response> {
  const { ip, isLocalDev } = getClientIp(request);

  if (!(await checkRateLimit(env.RL_BASELINE, ip, isLocalDev))) {
    return jsonResponse({ error: 'Rate limit exceeded' }, 429, { 'retry-after': '60' });
  }

  const cf = request.cf;
  const country = typeof cf?.country === 'string' && cf.country.length === 2 ? cf.country : null;
  const region = typeof cf?.region === 'string' && cf.region.length > 0 ? cf.region : null;
  const city = typeof cf?.city === 'string' && cf.city.length > 0 ? cf.city : null;
  const asn = typeof cf?.asn === 'number' && Number.isInteger(cf.asn) ? cf.asn : null;
  const asOrganization =
    typeof cf?.asOrganization === 'string' && cf.asOrganization.length > 0 ? cf.asOrganization : null;
  const colo = typeof cf?.colo === 'string' && cf.colo.length > 0 ? cf.colo : null;
  const httpProtocol =
    typeof cf?.httpProtocol === 'string' && cf.httpProtocol.length > 0 ? cf.httpProtocol : null;
  const tlsVersion =
    typeof cf?.tlsVersion === 'string' && cf.tlsVersion.length > 0 ? cf.tlsVersion : null;

  const githubRepoUrl =
    typeof env.GITHUB_REPO_URL === 'string' && /^https:\/\/github\.com\/[a-zA-Z0-9_.-]+\/[a-zA-Z0-9_.-]+\/?$/.test(env.GITHUB_REPO_URL.trim())
      ? env.GITHUB_REPO_URL.trim().replace(/\/$/, '')
      : null;

  const body: BaselineResponse = {
    ip,
    country,
    region,
    city,
    asn,
    asOrganization,
    colo,
    httpProtocol,
    tlsVersion,
    githubRepoUrl,
    isLocalDev,
  };

  return jsonResponse(body);
}

async function handleIpMeta(request: Request, env: Env): Promise<Response> {
  const { ip: callerIp, isLocalDev } = getClientIp(request);

  if (!isLocalDev) {
    const secFetchSite = request.headers.get('sec-fetch-site');
    if (secFetchSite !== 'same-origin') {
      return jsonResponse({ error: 'Same-origin browser request required' }, 403);
    }
  }

  if (!(await checkRateLimit(env.RL_IP_META, callerIp, isLocalDev))) {
    return jsonResponse({ error: 'Rate limit exceeded' }, 429, { 'retry-after': '60' });
  }

  const url = new URL(request.url);
  const queryIp = url.searchParams.get('ip')?.trim() ?? '';
  const version = detectPublicIpVersion(queryIp);

  if (!version) {
    return jsonResponse({ error: 'Invalid or non-public IP address' }, 400);
  }

  const cachedHit = lruGet(queryIp);
  if (cachedHit) {
    return jsonResponse({ ...cachedHit, cached: true });
  }

  const cf = request.cf;
  const cfCountry = typeof cf?.country === 'string' && cf.country.length === 2 ? cf.country.toUpperCase() : null;
  const cfCity = typeof cf?.city === 'string' && cf.city.length > 0 ? cf.city : null;
  const cfAsn = typeof cf?.asn === 'number' && Number.isInteger(cf.asn) ? cf.asn : null;
  const cfOrg = typeof cf?.asOrganization === 'string' && cf.asOrganization.length > 0 ? cf.asOrganization : null;
  const useCfFastPath = !isLocalDev && queryIp === callerIp && (cfCountry !== null || cfAsn !== null);

  if (!consumeUpstreamBudget()) {
    const degraded: IpMetaResponse = {
      ip: queryIp,
      version,
      country: useCfFastPath ? cfCountry : null,
      rirCountry: null,
      rir: null,
      city: useCfFastPath ? cfCity : null,
      asn: useCfFastPath ? cfAsn : null,
      org: useCfFastPath ? cfOrg : null,
      ipKind: useCfFastPath ? classifyIpKind(cfOrg, cfAsn) : 'unknown',
      broadcastDrift: false,
      source: useCfFastPath ? 'request.cf (upstream_throttled)' : 'degraded_rate_limited',
      cached: false,
    };
    return jsonResponse(degraded);
  }

  const encodedIp = encodeURIComponent(queryIp);
  let country: string | null = useCfFastPath ? cfCountry : null;
  let city: string | null = useCfFastPath ? cfCity : null;
  let asn: number | null = useCfFastPath ? cfAsn : null;
  let org: string | null = useCfFastPath ? cfOrg : null;
  const sources: string[] = [];

  if (useCfFastPath) {
    sources.push('request.cf');
  }

  const [ipWhoRaw, ripeRirRaw] = await Promise.all([
    useCfFastPath ? Promise.resolve(null) : fetchJsonWithTimeout(`https://ipwho.is/${encodedIp}`, 3500),
    fetchJsonWithTimeout(`https://stat.ripe.net/data/rir/data.json?resource=${encodedIp}`, 3500),
  ]);

  const who = isObjectRecord(ipWhoRaw) ? (ipWhoRaw as IpWhoRaw) : null;
  const rirData = isObjectRecord(ripeRirRaw) ? (ripeRirRaw as RipeRirRaw) : null;

  if (!useCfFastPath && who?.success) {
    sources.push('ipwho.is');
    if (typeof who.country_code === 'string' && who.country_code.length === 2) {
      country = who.country_code.toUpperCase();
    }
    if (typeof who.city === 'string' && who.city.length > 0) {
      city = who.city;
    }
    if (typeof who.connection?.asn === 'number' && Number.isInteger(who.connection.asn)) {
      asn = who.connection.asn;
    }
    const orgCandidate = who.connection?.org || who.connection?.isp || null;
    if (typeof orgCandidate === 'string' && orgCandidate.trim().length > 0) {
      org = orgCandidate.trim();
    }
  }

  if (asn === null) {
    const ripeNetRaw = await fetchJsonWithTimeout(
      `https://stat.ripe.net/data/network-info/data.json?resource=${encodedIp}`,
      3000,
    );
    const netData = isObjectRecord(ripeNetRaw) ? (ripeNetRaw as RipeNetInfoRaw) : null;
    const firstAsn = netData?.data?.asns?.[0];
    if (firstAsn && /^\d+$/.test(firstAsn)) {
      asn = Number(firstAsn);
      sources.push('RIPEstat-ASN');
    }
  }

  const firstRir = rirData?.data?.rirs?.[0];
  if (firstRir) {
    sources.push('RIPEstat');
  }
  const rir = typeof firstRir?.rir === 'string' && firstRir.rir.length > 0 ? firstRir.rir.toUpperCase() : null;
  const rawRirCountry =
    typeof firstRir?.country === 'string' && firstRir.country.length === 2
      ? firstRir.country.toUpperCase()
      : null;
  const rirCountry = rawRirCountry === 'EU' ? null : rawRirCountry;
  const broadcastDrift = country !== null && rirCountry !== null && country !== rirCountry;

  const result: IpMetaResponse = {
    ip: queryIp,
    version,
    country,
    rirCountry,
    rir,
    city,
    asn,
    org,
    ipKind: classifyIpKind(org, asn),
    broadcastDrift,
    source: sources.length > 0 ? sources.join(' + ') : 'unavailable',
    cached: false,
  };

  lruSet(queryIp, result, sources.length > 0 ? POSITIVE_TTL_MS : NEGATIVE_TTL_MS);
  return jsonResponse(result);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if ((url.pathname === '/sh' || url.pathname === '/check.sh') && request.method === 'GET') {
      return handleScript(request, env, 'sh');
    }

    if ((url.pathname === '/ps' || url.pathname === '/check.ps1') && request.method === 'GET') {
      return handleScript(request, env, 'ps');
    }

    if (url.pathname === '/api/baseline' && request.method === 'GET') {
      return handleBaseline(request, env);
    }

    if (url.pathname === '/api/ip-meta' && request.method === 'GET') {
      return handleIpMeta(request, env);
    }

    if (url.pathname.startsWith('/api/')) {
      return jsonResponse({ error: 'Not found' }, 404);
    }

    return env.ASSETS.fetch(request);
  },
} satisfies ExportedHandler<Env>;
