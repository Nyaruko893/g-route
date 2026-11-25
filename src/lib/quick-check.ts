import {
  type BaselineResponse,
  BaselineResponseSchema,
  type IpMetaResponse,
  IpMetaResponseSchema,
} from '../../shared/contracts';
import {
  DOMESTIC_DIRECT_SOURCES,
  DUAL_STACK_ECHO_SOURCES,
  STUN_SERVERS,
} from '../../shared/probes';

export interface EchoStackResult {
  readonly status: 'idle' | 'running' | 'ok' | 'unavailable';
  readonly ip: string | null;
  readonly source: string | null;
  readonly meta: IpMetaResponse | null;
}

export interface DomesticDirectResult {
  readonly status: 'idle' | 'running' | 'ok' | 'unavailable';
  readonly ip: string | null;
  readonly locationLabel: string | null;
  readonly isChinaIp: boolean | null;
  readonly source: string | null;
}

export interface SingleStunResult {
  readonly server: string;
  readonly status: 'idle' | 'running' | 'ok' | 'blocked' | 'unsupported';
  readonly srflxIps: readonly string[];
  readonly primaryMeta: IpMetaResponse | null;
}

export interface DualStunResult {
  readonly cloudflare: SingleStunResult;
  readonly google: SingleStunResult;
}

export interface QuickCheckSummary {
  readonly topologyLabel: string;
  readonly topologyTone: 'ok' | 'diff' | 'leak' | 'wait';
  readonly udpLabel: string;
  readonly udpDetail: string;
  readonly udpTone: 'ok' | 'diff' | 'leak' | 'wait';
  readonly isUdpDomesticLeak: boolean;
  readonly dualStackMismatch: boolean;
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

const ipMetaSessionCache = new Map<string, Promise<IpMetaResponse | null>>();

export function resetQuickCheckCache(): void {
  ipMetaSessionCache.clear();
}

async function fetchIpMeta(ip: string): Promise<IpMetaResponse | null> {
  const key = ip.trim();
  const existing = ipMetaSessionCache.get(key);
  if (existing) return existing;

  const promise = (async (): Promise<IpMetaResponse | null> => {
    try {
      const res = await fetchWithTimeout(
        `/api/ip-meta?ip=${encodeURIComponent(key)}`,
        { cache: 'no-store' },
        5000,
      );
      if (!res.ok) return null;
      const raw: unknown = await res.json();
      const parsed = IpMetaResponseSchema.safeParse(raw);
      return parsed.success ? parsed.data : null;
    } catch {
      return null;
    }
  })();

  ipMetaSessionCache.set(key, promise);
  return promise;
}

export async function fetchBaseline(): Promise<BaselineResponse | null> {
  try {
    const res = await fetchWithTimeout('/api/baseline', { cache: 'no-store' }, 4000);
    if (!res.ok) return null;
    const raw: unknown = await res.json();
    const parsed = BaselineResponseSchema.safeParse(raw);
    return parsed.success ? parsed.data : null;
  } catch {
    return null;
  }
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : null;
}

export async function detectDomesticDirect(): Promise<DomesticDirectResult> {
  let ip: string | null = null;
  let locationLabel: string | null = null;
  let isChinaIp: boolean | null = null;
  let source: string | null = null;

  for (const url of DOMESTIC_DIRECT_SOURCES.ipApis) {
    try {
      const res = await fetchWithTimeout(url, { cache: 'no-store' }, 3000);
      if (!res.ok) continue;
      const raw: unknown = await res.json();
      const obj = asRecord(raw);
      if (!obj) continue;

      if (typeof obj['ip'] === 'string' && obj['ip'].length > 0) {
        ip = obj['ip'].trim();
        const data = asRecord(obj['data']);
        const country = typeof data?.['country'] === 'string' ? data['country'] : '';
        const prov = typeof data?.['prov'] === 'string' ? data['prov'] : '';
        const city = typeof data?.['city'] === 'string' ? data['city'] : '';
        const isp = typeof data?.['isp'] === 'string' ? data['isp'] : '';
        const parts = [country, prov, city, isp].filter((s) => s.length > 0);
        locationLabel = parts.length > 0 ? parts.join(' ') : null;
        if (country) {
          isChinaIp = /中国|CN/i.test(country) && !/香港|澳门|台湾/i.test(`${prov}${city}`);
        }
        source = new URL(url).hostname;
        break;
      }

      const ipInfo = asRecord(obj['ipinfo']);
      const ipData = asRecord(obj['ipdata']);
      if (typeof ipInfo?.['text'] === 'string' && ipInfo['text'].length > 0) {
        ip = ipInfo['text'].trim();
        const cnFlag = ipInfo['cnip'];
        if (typeof cnFlag === 'boolean') isChinaIp = cnFlag;
        const parts = [
          typeof ipData?.['info1'] === 'string' ? ipData['info1'] : '',
          typeof ipData?.['info2'] === 'string' ? ipData['info2'] : '',
          typeof ipData?.['isp'] === 'string' ? ipData['isp'] : '',
        ].filter((s) => s.length > 0);
        locationLabel = parts.length > 0 ? parts.join(' ') : null;
        source = new URL(url).hostname;
        break;
      }
    } catch {
      // Try fallback domestic API
    }
  }

  if (ip && isChinaIp === null) {
    const meta = await fetchIpMeta(ip);
    if (meta?.country) {
      isChinaIp = meta.country === 'CN';
      if (!locationLabel) {
        locationLabel = [meta.country, meta.city, meta.org].filter(Boolean).join(' · ');
      }
    }
  }

  if (!ip) {
    return { status: 'unavailable', ip: null, locationLabel: null, isChinaIp: null, source: null };
  }

  return { status: 'ok', ip, locationLabel, isChinaIp, source };
}

async function probeSingleEchoStack(urls: readonly string[]): Promise<EchoStackResult> {
  for (const url of urls) {
    try {
      const res = await fetchWithTimeout(url, { cache: 'no-store' }, 3200);
      if (!res.ok) continue;
      const raw: unknown = await res.json();
      const record = asRecord(raw);
      if (!record) continue;

      const ip =
        typeof record['ip'] === 'string'
          ? record['ip'].trim()
          : typeof record['address'] === 'string'
            ? record['address'].trim()
            : null;
      if (!ip) continue;

      const workerMeta = await fetchIpMeta(ip);
      const cc =
        typeof record['cc'] === 'string' && record['cc'].length === 2
          ? record['cc'].toUpperCase()
          : null;
      const city =
        typeof record['city'] === 'string' && record['city'].length > 0
          ? record['city']
          : null;
      const asn =
        typeof record['asn'] === 'number' && Number.isInteger(record['asn'])
          ? record['asn']
          : null;
      const aso =
        typeof record['aso'] === 'string' && record['aso'].trim().length > 0
          ? record['aso'].trim()
          : null;
      const version: 4 | 6 = ip.includes(':') ? 6 : 4;

      const mergedMeta: IpMetaResponse | null = workerMeta
        ? {
            ...workerMeta,
            country: workerMeta.country ?? cc,
            city: workerMeta.city ?? city,
            asn: workerMeta.asn ?? asn,
            org: workerMeta.org ?? aso,
            broadcastDrift:
              (workerMeta.country ?? cc) !== null &&
              workerMeta.rirCountry !== null &&
              (workerMeta.country ?? cc) !== workerMeta.rirCountry,
          }
        : cc || asn || aso
          ? {
              ip,
              version,
              country: cc,
              rirCountry: null,
              rir: null,
              city,
              asn,
              org: aso,
              ipKind: 'unknown',
              broadcastDrift: false,
              source: new URL(url).hostname,
              cached: false,
            }
          : null;

      return { status: 'ok', ip, source: new URL(url).hostname, meta: mergedMeta };
    } catch {
      // Try fallback
    }
  }
  return { status: 'unavailable', ip: null, source: null, meta: null };
}

export async function detectDualStack(
  onUpdate: (stack: 'v4' | 'v6', result: EchoStackResult) => void,
): Promise<void> {
  onUpdate('v4', { status: 'running', ip: null, source: null, meta: null });
  onUpdate('v6', { status: 'running', ip: null, source: null, meta: null });
  await Promise.all([
    probeSingleEchoStack(DUAL_STACK_ECHO_SOURCES.v4).then((r) => onUpdate('v4', r)),
    probeSingleEchoStack(DUAL_STACK_ECHO_SOURCES.v6).then((r) => onUpdate('v6', r)),
  ]);
}

async function runSingleStunServer(stunUrl: string): Promise<SingleStunResult> {
  if (typeof RTCPeerConnection === 'undefined') {
    return { server: stunUrl, status: 'unsupported', srflxIps: [], primaryMeta: null };
  }

  const srflx = new Set<string>();
  const srflxIps = await new Promise<readonly string[]>((resolve) => {
    let settled = false;
    let pc: RTCPeerConnection | null = null;
    const finish = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (pc) {
        try {
          pc.close();
        } catch {
          // ignore
        }
      }
      resolve([...srflx]);
    };
    const timer = setTimeout(finish, 3400);
    try {
      pc = new RTCPeerConnection({ iceServers: [{ urls: stunUrl }] });
      pc.createDataChannel('g-route');
      pc.onicecandidate = (ev) => {
        if (!ev.candidate) {
          finish();
          return;
        }
        const parts = ev.candidate.candidate.split(/\s+/);
        const addr = parts[4];
        const typIdx = parts.indexOf('typ');
        const typ = typIdx >= 0 ? parts[typIdx + 1] : undefined;
        if (addr && (typ === 'srflx' || typ === 'prflx')) {
          srflx.add(addr);
        }
      };
      pc.onicegatheringstatechange = () => {
        if (pc?.iceGatheringState === 'complete') finish();
      };
      void pc
        .createOffer()
        .then((offer) => pc?.setLocalDescription(offer))
        .catch(finish);
    } catch {
      finish();
    }
  });

  const primaryIp = srflxIps[0] ?? null;
  const primaryMeta = primaryIp ? await fetchIpMeta(primaryIp) : null;
  return {
    server: stunUrl,
    status: srflxIps.length > 0 ? 'ok' : 'blocked',
    srflxIps,
    primaryMeta,
  };
}

export async function runDualStunProbes(): Promise<DualStunResult> {
  const [cloudflare, google] = await Promise.all([
    runSingleStunServer(STUN_SERVERS.cloudflare),
    runSingleStunServer(STUN_SERVERS.google),
  ]);
  return { cloudflare, google };
}

function sameIpv4Prefix24(a: string, b: string): boolean {
  const pa = a.split('.');
  const pb = b.split('.');
  if (pa.length !== 4 || pb.length !== 4) return a === b;
  return pa[0] === pb[0] && pa[1] === pb[1] && pa[2] === pb[2];
}

export function maskDisplayIp(ip: string | null): string {
  if (!ip) return '--';
  if (ip.includes(':')) {
    const p = ip.split(':');
    return `${p[0] ?? ''}:${p[1] ?? ''}:*:*`;
  }
  const p = ip.split('.');
  if (p.length === 4) return `${p[0]}.${p[1]}.*.*`;
  return ip;
}

export function evaluateQuickCheck(params: {
  readonly baseline: BaselineResponse | null;
  readonly domestic: DomesticDirectResult;
  readonly v4: EchoStackResult;
  readonly v6: EchoStackResult;
  readonly stun: DualStunResult;
}): QuickCheckSummary {
  const { baseline, domestic, v4, v6, stun } = params;

  const loading = v4.status === 'running' || domestic.status === 'running';
  const v4Cc = v4.meta?.country ?? null;
  const v6Cc = v6.meta?.country ?? null;
  const dualStackMismatch =
    v4.status === 'ok' && v6.status === 'ok' && v4Cc !== null && v6Cc !== null && v4Cc !== v6Cc;

  let topologyLabel = '采集中...';
  let topologyTone: QuickCheckSummary['topologyTone'] = 'wait';
  if (!loading) {
    if (dualStackMismatch) {
      topologyLabel = `双栈跨国 (${v4Cc} vs ${v6Cc})`;
      topologyTone = 'leak';
    } else if (domestic.isChinaIp === true && v4.ip && !sameIpv4Prefix24(domestic.ip ?? '', v4.ip)) {
      topologyLabel = '分流路由（CN 直连 + 非 CN 出站）';
      topologyTone = 'ok';
    } else if (domestic.isChinaIp === false && v4.ip) {
      topologyLabel = '单一非 CN 出站';
      topologyTone = 'ok';
    } else {
      topologyLabel = v4.ip ? `出站地区 ${v4Cc ?? ''}`.trim() : '等待探测';
      topologyTone = 'ok';
    }
  }

  const g = stun.google;
  const cf = stun.cloudflare;
  if (g.status === 'idle' || g.status === 'running' || cf.status === 'idle' || cf.status === 'running') {
    return {
      topologyLabel,
      topologyTone,
      udpLabel: 'STUN 探测中...',
      udpDetail: '并行比对 CF 与 Google UDP 反射',
      udpTone: 'wait',
      isUdpDomesticLeak: false,
      dualStackMismatch,
    };
  }

  const gIp = g.srflxIps[0] ?? null;
  const cfIp = cf.srflxIps[0] ?? null;
  if (!gIp && !cfIp) {
    return {
      topologyLabel,
      topologyTone,
      udpLabel: 'UDP 未反射',
      udpDetail: '未返回公网 STUN 反射地址，连接将使用 TCP',
      udpTone: 'ok',
      isUdpDomesticLeak: false,
      dualStackMismatch,
    };
  }

  const httpOverseas = [
    v4.ip,
    v6.ip,
    baseline && !baseline.isLocalDev ? baseline.ip : null,
  ].filter((x): x is string => Boolean(x && x !== '127.0.0.1' && x !== '::1'));

  const isCn = (ip: string | null, meta: IpMetaResponse | null): boolean => {
    if (!ip) return false;
    if (meta?.country === 'CN') return true;
    if (domestic.isChinaIp && domestic.ip && sameIpv4Prefix24(ip, domestic.ip)) return true;
    return false;
  };

  const gIsCn = isCn(gIp, g.primaryMeta);
  const cfIsCn = isCn(cfIp, cf.primaryMeta);

  if ((gIsCn || cfIsCn) && httpOverseas.length > 0 && v4Cc !== 'CN') {
    return {
      topologyLabel,
      topologyTone,
      udpLabel: 'UDP 与 HTTP 出口不一致',
      udpDetail: `${gIsCn ? 'Google STUN' : 'CF STUN'} 反射地址为中国大陆 IP (${maskDisplayIp(gIsCn ? gIp : cfIp)})，与 HTTP 出站路径不一致`,
      udpTone: 'leak',
      isUdpDomesticLeak: true,
      dualStackMismatch,
    };
  }

  const gDiffersHttp =
    gIp !== null && httpOverseas.length > 0 && !httpOverseas.some((h) => sameIpv4Prefix24(h, gIp));
  if (gDiffersHttp) {
    return {
      topologyLabel,
      topologyTone,
      udpLabel: `Google UDP 独立出口 (${g.primaryMeta?.country ?? '非 CN'})`,
      udpDetail: `stun.l.google.com 经 ${maskDisplayIp(gIp)}，与默认 HTTP 出站不同`,
      udpTone: 'diff',
      isUdpDomesticLeak: false,
      dualStackMismatch,
    };
  }

  return {
    topologyLabel,
    topologyTone,
    udpLabel: 'TCP / UDP 出口一致',
    udpDetail: `Google STUN 反射 ${maskDisplayIp(gIp ?? cfIp)}`,
    udpTone: 'ok',
    isUdpDomesticLeak: false,
    dualStackMismatch,
  };
}
