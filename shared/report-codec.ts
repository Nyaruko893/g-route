import { z } from 'zod';

const MAX_ENCODED_CHARS = 16_384;
const MAX_DECOMPRESSED_BYTES = 32_768;

const optStr = (max = 80) => z.string().max(max).optional();

const EgressKindEnum = z.enum(['isp', 'hosting', 'warp', 'business', 'unknown']);

const RouteBucketV1Schema = z.object({
  ip: optStr(64),
  cc: optStr(16),
  asn: z.number().int().min(0).max(4_294_967_295).optional(),
  org: optStr(96),
  kind: EgressKindEnum.optional(),
  colo: optStr(24),
  warp: z.enum(['on', 'off', 'plus']).optional(),
  ms: z.number().int().min(0).max(60_000).optional(),
  note: optStr(64),
});

export type RouteBucketV1 = z.infer<typeof RouteBucketV1Schema>;

const NetTransportV1Schema = z.object({
  kind: z.enum(['direct', 'sysproxy', 'tun_fakeip', 'tun_realip', 'router']),
  label: optStr(48),
  nic: optStr(48),
});

const RouteTopologyV1Schema = z.object({
  cn: RouteBucketV1Schema.optional(),
  def: RouteBucketV1Schema.optional(),
  ggc: RouteBucketV1Schema.optional(),
  cf: RouteBucketV1Schema.optional(),
  oai: RouteBucketV1Schema.optional(),
  cld: RouteBucketV1Schema.optional(),
});

const StackRttV1Schema = z.object({
  gem: z.number().int().min(0).max(60_000).optional(),
  nlm: z.number().int().min(0).max(60_000).optional(),
  yt: z.number().int().min(0).max(60_000).optional(),
  cdn: z.number().int().min(0).max(60_000).optional(),
  play: z.number().int().min(0).max(60_000).optional(),
  srch: z.number().int().min(0).max(60_000).optional(),
});

const StackExitMapV1Schema = z.object({
  gem: optStr(48),
  nlm: optStr(48),
  yt: optStr(48),
  cdn: optStr(48),
  play: optStr(48),
  srch: optStr(48),
  trm: optStr(48),
});

export const StackProbeV1Schema = z.object({
  ip: optStr(64),
  gip: optStr(64),
  asn: z.number().int().min(0).max(4_294_967_295).optional(),
  org: optStr(96),
  cc: optStr(8),
  city: optStr(64),
  kind: EgressKindEnum.optional(),
  gasn: z.number().int().min(0).max(4_294_967_295).optional(),
  gorg: optStr(96),
  gkind: EgressKindEnum.optional(),
  gem: optStr(16),
  nlm: z.enum(['ok', 'unavail', 'err']).optional(),
  yt: z.enum(['ok', 'cn', 'noprem', 'err']).optional(),
  ytg: optStr(8),
  cdn: optStr(64),
  cdnu: z.boolean().optional(),
  play: optStr(48),
  sdom: optStr(64),
  scap: z.enum(['ok', 'hk', 'captcha', 'err']).optional(),
  trm: optStr(48),
  ent: optStr(64),
  dns: z.enum(['native', 'viadns', 'tun', 'skip']).optional(),
  rtt: StackRttV1Schema.optional(),
  ex: StackExitMapV1Schema.optional(),
});

export type StackProbeV1 = z.infer<typeof StackProbeV1Schema>;

export const CliReportV1Schema = z.object({
  v: z.literal(1),
  t: z.number().int().min(0).max(9_999_999_999),
  m: z.enum(['vps', 'proxy']),
  os: optStr(32),
  tun: z.boolean().optional(),
  px: z.boolean().optional(),
  cn: optStr(48),
  ap: optStr(8),
  net: NetTransportV1Schema.optional(),
  rt: RouteTopologyV1Schema.optional(),
  al: z.array(z.string().max(48)).max(12).optional(),
  att: z.record(z.string(), z.unknown()).optional(),
  v4: StackProbeV1Schema.optional(),
  v6: StackProbeV1Schema.optional(),
  lbl: optStr(64),
});

export type CliReportV1 = z.infer<typeof CliReportV1Schema>;

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 1) {
    binary += String.fromCharCode(bytes[i] ?? 0);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function base64UrlToBytes(b64url: string): Uint8Array {
  const normalized = b64url.replace(/-/g, '+').replace(/_/g, '/').replace(/\s+/g, '');
  if (!/^[A-Za-z0-9+/=]*$/.test(normalized) || normalized.length === 0) {
    throw new Error('报告码包含非法 Base64URL 字符');
  }
  const padLen = (4 - (normalized.length % 4)) % 4;
  const padded = normalized + '='.repeat(padLen);
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    out[i] = binary.charCodeAt(i);
  }
  return out;
}

async function runTransformStream(
  stream: CompressionStream | DecompressionStream,
  input: Uint8Array,
  maxBytes?: number,
): Promise<Uint8Array> {
  const writer = stream.writable.getWriter();
  const reader = stream.readable.getReader();

  // Drive write and read concurrently to avoid browser TransformStream backpressure deadlock
  const writePromise = (async () => {
    await writer.write(new Uint8Array(input));
    await writer.close();
  })();
  writePromise.catch(() => {
    // Error is propagated via reader.read() or the final await writePromise
  });

  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) {
        total += value.byteLength;
        if (maxBytes !== undefined && total > maxBytes) {
          await reader.cancel();
          throw new Error('报告数据体积超过安全上限');
        }
        chunks.push(value);
      }
    }
    await writePromise;
  } finally {
    reader.releaseLock();
  }

  const merged = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return merged;
}

async function gzipBytes(input: Uint8Array): Promise<Uint8Array | null> {
  if (typeof CompressionStream === 'undefined') return null;
  try {
    return await runTransformStream(new CompressionStream('gzip'), input);
  } catch {
    return null;
  }
}

async function gunzipBytes(input: Uint8Array): Promise<Uint8Array> {
  if (typeof DecompressionStream === 'undefined') {
    throw new Error('当前浏览器不支持原生 gzip 解码，请升级浏览器或改粘贴 -j JSON');
  }
  return runTransformStream(new DecompressionStream('gzip'), input, MAX_DECOMPRESSED_BYTES);
}

function stripUndefinedDeep(obj: unknown): unknown {
  if (Array.isArray(obj)) {
    return obj.map(stripUndefinedDeep);
  }
  if (obj && typeof obj === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(obj)) {
      if (v !== undefined && v !== null && v !== '') {
        out[k] = stripUndefinedDeep(v);
      }
    }
    return out;
  }
  return obj;
}

export async function encodeReportPayload(report: CliReportV1): Promise<string> {
  const clean = stripUndefinedDeep(report);
  const json = JSON.stringify(clean);
  const rawBytes = new TextEncoder().encode(json);
  const compressed = await gzipBytes(rawBytes);
  if (compressed && compressed.byteLength < rawBytes.byteLength) {
    return `z:${bytesToBase64Url(compressed)}`;
  }
  return `p:${bytesToBase64Url(rawBytes)}`;
}

function extractHashPayload(rawInput: string): string | null {
  const trimmed = rawInput.trim();
  if (!trimmed) return null;

  // Terminals frequently hard-wrap long #r= or G1: links across lines; join wrapped lines before matching.
  const collapsed = trimmed.replace(/[\r\n\t ]+/g, '');

  // Match #r=z:... or r=z:... anywhere in a URL or pasted snippet
  const hashMatch = collapsed.match(/(?:^|[#?&])r=([zp]:[A-Za-z0-9_-]+)/);
  if (hashMatch?.[1]) {
    return hashMatch[1];
  }

  // Match G1:z:... or G1:p:...
  const g1Match = collapsed.match(/G1:([zp]:[A-Za-z0-9_-]+)/);
  if (g1Match?.[1]) {
    return g1Match[1];
  }

  // Direct z:... or p:...
  const directMatch = collapsed.match(/^([zp]:[A-Za-z0-9_-]+)$/);
  if (directMatch?.[1]) {
    return directMatch[1];
  }

  return null;
}

export async function decodeReportInput(
  rawInput: string,
): Promise<{ readonly ok: true; readonly report: CliReportV1 } | { readonly ok: false; readonly error: string }> {
  const trimmed = rawInput.trim();
  if (!trimmed) {
    return { ok: false, error: '请粘贴 #r= 链接、G1 报告码或 CLI 输出的 JSON' };
  }
  if (trimmed.length > MAX_ENCODED_CHARS) {
    return { ok: false, error: '输入内容超过 16KB 安全上限' };
  }

  let jsonText = '';

  if (trimmed.startsWith('{')) {
    jsonText = trimmed;
  } else {
    const payload = extractHashPayload(trimmed);
    if (!payload) {
      return {
        ok: false,
        error: '未识别到有效的 G-ROUTE 报告码（支持完整 #r= 链接、G1:z:... 或 -j 原始 JSON）',
      };
    }

    const prefix = payload.slice(0, 2);
    const body = payload.slice(2);
    try {
      const bytes = base64UrlToBytes(body);
      const rawBytes = prefix === 'z:' ? await gunzipBytes(bytes) : bytes;
      jsonText = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(rawBytes);
    } catch (err) {
      const detail = err instanceof Error && err.message.trim().length > 0 ? err.message.trim() : '';
      return {
        ok: false,
        error: detail
          ? `报告码解压失败（${detail}），请确认完整复制未丢字或改粘贴 -j JSON`
          : '报告码解压校验失败（可能复制时丢字/变字符或被截断），请重新完整复制或改粘贴 -j JSON',
      };
    }
  }

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(jsonText);
  } catch {
    return { ok: false, error: 'JSON 解析失败，请检查粘贴内容是否完整' };
  }

  const validated = CliReportV1Schema.safeParse(parsedJson);
  if (!validated.success) {
    return {
      ok: false,
      error: `报告数据结构不匹配 (v1): ${validated.error.issues[0]?.message ?? 'invalid schema'}`,
    };
  }

  return { ok: true, report: validated.data };
}

export function buildReportFingerprint(report: CliReportV1): string {
  return [
    report.t,
    report.m,
    report.v4?.ip ?? '-',
    report.v4?.gip ?? '-',
    report.v6?.ip ?? '-',
    report.v4?.gem ?? '-',
    report.v6?.gem ?? '-',
  ].join('|');
}
