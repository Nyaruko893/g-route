import type { CliReportV1, RouteBucketV1, StackProbeV1 } from './report-codec';

export type VerdictTier = 'clean' | 'split' | 'partial' | 'drift';
export type CellTone = 'ok' | 'diff' | 'leak' | 'muted';
export type ExitSlotColor = 'cn' | 'a' | 'b' | 'c' | 'd' | 'unknown';

function resolveExitSlotColor(slotOrText: string | undefined): ExitSlotColor {
  if (!slotOrText) return 'unknown';
  if (slotOrText.startsWith('直连') || slotOrText.startsWith('国内')) return 'cn';
  if (slotOrText.startsWith('出口 A')) return 'a';
  if (slotOrText.startsWith('出口 B')) return 'b';
  if (slotOrText.startsWith('出口 C')) return 'c';
  if (/^出口 [D-Z]/.test(slotOrText)) return 'd';
  return 'unknown';
}

export function splitExitTag(raw: string | undefined): {
  readonly slot: string;
  readonly rest: string;
  readonly color: ExitSlotColor;
} | null {
  if (!raw) return null;
  const m = raw.match(/^(直连 CN|出口 [A-Z])\s*(?:[·(]\s*)?(.*)$/);
  if (m && m[1]) {
    const rest = (m[2] ?? '').replace(/\)\s*$/, '').trim();
    return { slot: m[1], rest, color: resolveExitSlotColor(m[1]) };
  }
  return { slot: raw, rest: '', color: 'unknown' };
}

interface ServiceCell {
  readonly tone: CellTone;
  readonly badge: string;
  readonly detail: string;
  readonly ms?: number | undefined;
  readonly exitSlot?: string | undefined;
}

export interface RouteExitCluster {
  readonly slot: string;
  readonly slotColor: ExitSlotColor;
  readonly tone: CellTone;
  readonly ip: string;
  readonly asn: number | null;
  readonly org: string;
  readonly kindLabel: string;
  readonly cc: string;
  readonly buckets: readonly string[];
  readonly avgMs: number | null;
  readonly warp: boolean;
  readonly isCnDirect: boolean;
}

export interface RouteAlarm {
  readonly id: string;
  readonly tone: 'leak' | 'diff' | 'ok';
  readonly title: string;
  readonly detail: string;
}

export interface ServiceMatrixRow {
  readonly id: 'gemini' | 'notebooklm' | 'youtube' | 'ggc' | 'play' | 'search' | 'terms';
  readonly label: string;
  readonly probeHint: string;
  readonly v4: ServiceCell | null;
  readonly v6: ServiceCell | null;
}

export interface ReportBadge {
  readonly tone: CellTone;
  readonly text: string;
}

export interface EgressAttribution {
  readonly ip: string;
  readonly asn: number | null;
  readonly org: string;
  readonly kind: 'hosting' | 'isp' | 'warp' | 'business' | 'unknown';
  readonly kindLabel: string;
}

export interface ReportDiagnosis {
  readonly tier: VerdictTier;
  readonly tierCode: string;
  readonly headline: string;
  readonly summary: string;
  readonly badges: readonly ReportBadge[];
  readonly modeLabel: string;
  readonly transportLabel: string;
  readonly defaultEgress: EgressAttribution;
  readonly googleEgress: EgressAttribution | null;
  readonly publicGeoLabel: string;
  readonly appleGeoLabel: string;
  readonly googleGeoLabel: string;
  readonly googleOnlyDrift: boolean;
  readonly hasSplitRoute: boolean;
  readonly hasDualStackAsymmetry: boolean;
  readonly hasEeaNotice: boolean;
  readonly isHostingVerifiedOk: boolean;
  readonly routeClusters: readonly RouteExitCluster[];
  readonly routeAlarms: readonly RouteAlarm[];
  readonly rows: readonly ServiceMatrixRow[];
}

interface DiffRow {
  readonly id: string;
  readonly label: string;
  readonly leftText: string;
  readonly leftTone: CellTone;
  readonly rightText: string;
  readonly rightTone: CellTone;
  readonly changed: boolean;
}

const COUNTRY_NAME_TO_ISO2: Readonly<Record<string, string>> = {
  usa: 'US',
  'united states': 'US',
  us: 'US',
  jpn: 'JP',
  japan: 'JP',
  jp: 'JP',
  chn: 'CN',
  china: 'CN',
  cn: 'CN',
  hkg: 'HK',
  'hong kong': 'HK',
  hk: 'HK',
  mac: 'MO',
  macau: 'MO',
  macao: 'MO',
  mo: 'MO',
  twn: 'TW',
  taiwan: 'TW',
  tw: 'TW',
  sgp: 'SG',
  singapore: 'SG',
  sg: 'SG',
  kor: 'KR',
  'south korea': 'KR',
  korea: 'KR',
  kr: 'KR',
  gbr: 'GB',
  'united kingdom': 'GB',
  uk: 'GB',
  gb: 'GB',
  deu: 'DE',
  germany: 'DE',
  de: 'DE',
  fra: 'FR',
  france: 'FR',
  fr: 'FR',
  nld: 'NL',
  netherlands: 'NL',
  nl: 'NL',
  irl: 'IE',
  ireland: 'IE',
  ie: 'IE',
  che: 'CH',
  switzerland: 'CH',
  ch: 'CH',
  can: 'CA',
  canada: 'CA',
  ca: 'CA',
  aus: 'AU',
  australia: 'AU',
  au: 'AU',
  ind: 'IN',
  india: 'IN',
  in: 'IN',
  rus: 'RU',
  russia: 'RU',
  ru: 'RU',
  blr: 'BY',
  belarus: 'BY',
  by: 'BY',
  ita: 'IT',
  italy: 'IT',
  it: 'IT',
  esp: 'ES',
  spain: 'ES',
  es: 'ES',
  swe: 'SE',
  sweden: 'SE',
  se: 'SE',
  pol: 'PL',
  poland: 'PL',
  pl: 'PL',
  fin: 'FI',
  finland: 'FI',
  fi: 'FI',
  bra: 'BR',
  brazil: 'BR',
  br: 'BR',
  mys: 'MY',
  malaysia: 'MY',
  my: 'MY',
  tha: 'TH',
  thailand: 'TH',
  th: 'TH',
  vnm: 'VN',
  vietnam: 'VN',
  vn: 'VN',
  phl: 'PH',
  philippines: 'PH',
  ph: 'PH',
  tur: 'TR',
  turkey: 'TR',
  tr: 'TR',
  arg: 'AR',
  argentina: 'AR',
  ar: 'AR',
};

const RESTRICTED_GOOGLE_AI = new Set(['CN', 'HK', 'MO', 'RU', 'BY', 'CU', 'IR', 'KP', 'SY']);

const EEA_UK_CH = new Set([
  'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU', 'IE', 'IT',
  'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE', 'IS', 'LI', 'NO',
  'GB', 'CH',
]);

function normalizeCountryCode(raw: string | undefined | null): string | null {
  if (!raw) return null;
  const cleaned = raw.trim().toLowerCase();
  if (!cleaned || cleaned === '?' || cleaned === 'none' || cleaned === 'n/a') return null;
  const mapped = COUNTRY_NAME_TO_ISO2[cleaned];
  if (mapped) return mapped;
  if (/^[a-z]{2}$/.test(cleaned)) return cleaned.toUpperCase();
  return null;
}

function formatSearchDomainCountry(sdom: string | undefined): string | null {
  if (!sdom) return null;
  const lower = sdom.toLowerCase();
  if (lower === 'hkredirect' || lower.endsWith('.hk') || lower.endsWith('.cn')) return 'CN';
  if (lower.endsWith('.co.jp')) return 'JP';
  if (lower.endsWith('.co.uk')) return 'GB';
  if (lower.endsWith('.com.sg')) return 'SG';
  if (lower.endsWith('.com.tw')) return 'TW';
  if (lower.endsWith('.co.kr')) return 'KR';
  if (lower.endsWith('.de')) return 'DE';
  if (lower.endsWith('.fr')) return 'FR';
  if (lower.endsWith('.nl')) return 'NL';
  if (lower.endsWith('.ca')) return 'CA';
  if (lower.endsWith('.com.au')) return 'AU';
  if (lower === '.google.com') return 'US';
  return null;
}

function classifyOrgKind(
  orgRaw: string | undefined,
  asn: number | undefined,
  ipRaw: string | undefined,
  fallbackKind: 'hosting' | 'isp' | 'warp' | 'business' | 'unknown' | undefined,
): 'hosting' | 'isp' | 'warp' | 'business' | 'unknown' {
  const org = (orgRaw ?? '').toLowerCase();
  const ip = (ipRaw ?? '').toLowerCase();

  if (
    fallbackKind === 'warp' ||
    asn === 13335 ||
    /cloudflare|warp/.test(org) ||
    ip.startsWith('2a09:bac') ||
    ip.startsWith('104.28.') ||
    ip.startsWith('104.29.')
  ) {
    return 'warp';
  }
  if (
    /amazon|aws|google cloud|microsoft|azure|digitalocean|vultr|choopa|hetzner|ovh|linode|oracle|alibaba|aliyun|tencent|leaseweb|scaleway|contabo|upcloud|m247|datacamp|zenlayer|equinix|example cloud|vps|cloud|datacenter|data center|hosting|server|compute|colo/.test(
      org,
    )
  ) {
    return 'hosting';
  }
  if (
    /cox |comcast|xfinity|verizon|at&t|spectrum|charter|softbank|ntt|kddi|chunghwa|hinet|pccw|hkbn|singtel|starhub|vodafone|telekom|telecom|broadband|fiber|fibre|cable|mobile/.test(
      org,
    )
  ) {
    return 'isp';
  }
  return fallbackKind ?? 'unknown';
}

function kindToChineseLabel(kind: 'hosting' | 'isp' | 'warp' | 'business' | 'unknown'): string {
  switch (kind) {
    case 'hosting':
      return '数据中心';
    case 'isp':
      return '运营商段';
    case 'warp':
      return 'WARP 出站';
    case 'business':
      return '商业网段';
    default:
      return '未归类段';
  }
}

interface StackHealth {
  readonly hasDrift: boolean;
  readonly isFullCnDrift: boolean;
  readonly hasPartialIssue: boolean;
  readonly hasCaptcha: boolean;
  readonly hasEea: boolean;
  readonly hasIpSplit: boolean;
  readonly hasAiVsGoogleSplit: boolean;
  readonly dominantGoogleCc: string | null;
  readonly geminiCc: string | null;
  readonly coreGoogleCc: string | null;
  readonly driftReasons: readonly string[];
  readonly partialReasons: readonly string[];
}

function evaluateStackHealth(stack: StackProbeV1 | undefined, stackLabel: string): StackHealth {
  if (!stack) {
    return {
      hasDrift: false,
      isFullCnDrift: false,
      hasPartialIssue: false,
      hasCaptcha: false,
      hasEea: false,
      hasIpSplit: false,
      hasAiVsGoogleSplit: false,
      dominantGoogleCc: null,
      geminiCc: null,
      coreGoogleCc: null,
      driftReasons: [],
      partialReasons: [],
    };
  }

  const driftReasons: string[] = [];
  const partialReasons: string[] = [];

  const gemCc = normalizeCountryCode(stack.gem);
  const playCc = normalizeCountryCode(stack.play);
  const trmCc = normalizeCountryCode(stack.trm);
  const sdomCc = formatSearchDomainCountry(stack.sdom);

  let driftHits = 0;

  if (gemCc && RESTRICTED_GOOGLE_AI.has(gemCc)) {
    driftHits += 2;
    driftReasons.push(`${stackLabel} Gemini Boq 判区 ${stack.gem}`);
  }
  if (stack.nlm === 'unavail') {
    driftHits += 2;
    driftReasons.push(`${stackLabel} NotebookLM 返回 302 location=unsupported`);
  }
  if (stack.yt === 'cn') {
    driftHits += 2;
    driftReasons.push(`${stackLabel} YouTube Premium 命中 www.google.cn`);
  } else if (stack.yt === 'noprem') {
    driftHits += 1;
    driftReasons.push(`${stackLabel} YouTube Premium 当前地区不可用`);
  }
  if (playCc && RESTRICTED_GOOGLE_AI.has(playCc)) {
    driftHits += 1;
    driftReasons.push(`${stackLabel} Google Play 判区 ${stack.play}`);
  }
  if (trmCc && RESTRICTED_GOOGLE_AI.has(trmCc)) {
    driftHits += 1;
    driftReasons.push(`${stackLabel} Google Terms 辖区 ${stack.trm}`);
  }
  if (stack.sdom === 'hkredirect' || (stack.sdom && /\.hk$|\.cn$/i.test(stack.sdom))) {
    driftHits += 1;
    driftReasons.push(`${stackLabel} Search 域触发 ${stack.sdom}`);
  }
  if (stack.scap === 'hk') {
    driftHits += 1;
    driftReasons.push(`${stackLabel} Google Search 静默跳转 .com.hk`);
  }

  const hasGeminiCaptcha = stack.gemst === 'captcha';
  const hasGeminiTimeout = stack.gemst === 'timeout';
  const hasOtherCaptcha =
    stack.nlm === 'captcha' || stack.playst === 'captcha' || stack.trmst === 'captcha';
  const hasCaptcha = stack.scap === 'captcha' || hasGeminiCaptcha || hasOtherCaptcha;
  if (hasGeminiCaptcha) {
    partialReasons.push(`${stackLabel} Gemini 触发 /sorry/ 异常流量验证 (429)`);
  }
  if (hasGeminiTimeout) {
    partialReasons.push(`${stackLabel} Gemini 探测超时（可能被限速或链路抖动）`);
  }
  if (stack.nlm === 'captcha') {
    partialReasons.push(`${stackLabel} NotebookLM 触发 /sorry/ 验证`);
  }
  if (stack.playst === 'captcha') {
    partialReasons.push(`${stackLabel} Google Play 触发 /sorry/ 验证`);
  }
  if (stack.trmst === 'captcha') {
    partialReasons.push(`${stackLabel} Google Terms 触发 /sorry/ 验证`);
  }
  if (stack.scap === 'captcha') {
    partialReasons.push(`${stackLabel} Google Search 触发 /sorry/ 异常流量验证`);
  }
  if (stack.scap === 'jswall') {
    partialReasons.push(`${stackLabel} Google Search 无 JS 客户端命中 enablejs 验证墙（非 /sorry）`);
  }

  const hasAnyGoogleResult = Boolean(
    gemCc ||
      stack.nlm === 'ok' ||
      stack.nlm === 'unavail' ||
      stack.yt === 'ok' ||
      stack.yt === 'cn' ||
      stack.yt === 'noprem' ||
      playCc ||
      trmCc ||
      stack.sdom,
  );
  const allProbesFailed = !hasAnyGoogleResult && !hasCaptcha && !hasGeminiTimeout;
  if (allProbesFailed) {
    partialReasons.push(`${stackLabel} Google 服务探测均无有效响应`);
  }

  const coreVotes = [playCc, trmCc, sdomCc].filter((v): v is string => v !== null);
  const coreGoogleCc = coreVotes[0] ?? null;
  const dominantGoogleCc = gemCc ?? coreGoogleCc ?? normalizeCountryCode(stack.ytg);

  const hasAiVsGoogleSplit =
    gemCc !== null && coreGoogleCc !== null && gemCc !== coreGoogleCc;
  if (hasAiVsGoogleSplit) {
    partialReasons.push(
      `${stackLabel} Gemini (${gemCc}) 与 Google 基础服务 (${coreGoogleCc}) 判区不一致`,
    );
  }

  const hasIpSplit = Boolean(stack.ip && stack.gip && stack.ip !== stack.gip);

  const hasEea =
    stack.ent === 'Google Ireland Limited' ||
    (dominantGoogleCc !== null && EEA_UK_CH.has(dominantGoogleCc));

  const isFullCnDrift = driftHits >= 3 || (gemCc === 'CN' && stack.nlm === 'unavail');
  const hasDrift = driftHits >= 2 || gemCc === 'CN' || gemCc === 'HK' || stack.nlm === 'unavail';
  const hasPartialIssue =
    hasCaptcha ||
    hasGeminiTimeout ||
    allProbesFailed ||
    (driftHits === 1 && !hasDrift) ||
    hasAiVsGoogleSplit;

  return {
    hasDrift,
    isFullCnDrift,
    hasPartialIssue,
    hasCaptcha,
    hasEea,
    hasIpSplit,
    hasAiVsGoogleSplit,
    dominantGoogleCc,
    geminiCc: gemCc,
    coreGoogleCc,
    driftReasons,
    partialReasons,
  };
}

function resolveCellExit(
  s: StackProbeV1,
  key: 'gem' | 'nlm' | 'yt' | 'cdn' | 'play' | 'srch' | 'trm',
): string | undefined {
  const explicit = s.ex?.[key];
  if (explicit) return explicit;
  if ((key === 'yt' || key === 'cdn') && s.gip) {
    return s.ip && s.gip !== s.ip ? `分流出口 (${s.gip})` : `出口 A (${s.gip})`;
  }
  if (s.ip && (!s.gip || s.gip === s.ip)) {
    return `出口 A (${s.ip})`;
  }
  return undefined;
}

function buildGeminiCell(s: StackProbeV1): ServiceCell {
  const ms = s.rtt?.gem;
  const exitSlot = resolveCellExit(s, 'gem');
  if (s.gemst === 'captcha') {
    return { tone: 'leak', badge: '拦截 (/sorry)', detail: '触发异常流量验证 (429)', ms, exitSlot };
  }
  if (s.gemst === 'timeout') {
    return { tone: 'diff', badge: '超时 (Timeout)', detail: '未在时限内响应（疑被限速/抖动）', ms, exitSlot };
  }
  if (!s.gem || s.gem === '?') {
    return { tone: 'muted', badge: 'N/A', detail: '未取到 Boq 国码', ms, exitSlot };
  }
  const iso = normalizeCountryCode(s.gem);
  if (iso && RESTRICTED_GOOGLE_AI.has(iso)) {
    return { tone: 'leak', badge: `受限 [${s.gem}]`, detail: 'Boq 判区不支持 Gemini', ms, exitSlot };
  }
  return { tone: 'ok', badge: `可用 [${s.gem}]`, detail: 'Boq 原生国码支持', ms, exitSlot };
}

function buildNotebookCell(s: StackProbeV1): ServiceCell {
  const ms = s.rtt?.nlm;
  const exitSlot = resolveCellExit(s, 'nlm');
  if (s.nlm === 'captcha') {
    return { tone: 'leak', badge: '拦截 (/sorry)', detail: '重定向至 /sorry/ 验证', ms, exitSlot };
  }
  if (s.nlm === 'ok') {
    const codeTag = s.nlmc ? ` (${s.nlmc})` : ' (301)';
    return { tone: 'ok', badge: `支持${codeTag}`, detail: 'notebook.google.com', ms, exitSlot };
  }
  if (s.nlm === 'unavail') {
    return { tone: 'leak', badge: '封锁 (302)', detail: '?location=unsupported', ms, exitSlot };
  }
  return { tone: 'muted', badge: 'N/A', detail: '未响应', ms, exitSlot };
}

function buildYoutubeCell(s: StackProbeV1): ServiceCell {
  const ms = s.rtt?.yt;
  const exitSlot = resolveCellExit(s, 'yt');
  if (s.yt === 'cn') {
    return { tone: 'leak', badge: '受限 [CN]', detail: '命中 www.google.cn', ms, exitSlot };
  }
  if (s.yt === 'noprem') {
    return {
      tone: 'leak',
      badge: '不支持 Premium',
      detail: s.ytg ? `GL=${s.ytg}，页面提示地区不可用` : 'GL 与可用性不一致',
      ms,
      exitSlot,
    };
  }
  if (s.yt === 'ok') {
    return {
      tone: 'ok',
      badge: `可用 [${s.ytg ?? 'OK'}]`,
      detail: 'Premium 地区可用',
      ms,
      exitSlot,
    };
  }
  return { tone: 'muted', badge: 'N/A', detail: '未响应', ms, exitSlot };
}

function buildGgcCell(s: StackProbeV1): ServiceCell {
  const ms = s.rtt?.cdn;
  const exitSlot = resolveCellExit(s, 'cdn');
  if (!s.cdn) {
    return { tone: 'muted', badge: 'N/A', detail: '未返回 report_mapping', ms, exitSlot };
  }
  const isIspCache = s.cdn.includes('-') && !s.cdnu;
  const ipDiff = Boolean(s.ip && s.gip && s.ip !== s.gip);
  const ipHint = ipDiff ? `出口 ${s.gip} ≠ 默认` : s.gip ? `Google 侧 ${s.gip}` : '';
  const cacheHint = isIspCache ? 'ISP 内嵌 GGC' : s.cdnu ? '边缘机房 [u]' : 'Google 边缘';
  return {
    tone: 'ok',
    badge: s.cdn,
    detail: [cacheHint, ipHint].filter(Boolean).join(' · '),
    ms,
    exitSlot,
  };
}

function buildPlayCell(s: StackProbeV1): ServiceCell {
  const ms = s.rtt?.play;
  const exitSlot = resolveCellExit(s, 'play');
  if (s.playst === 'captcha') {
    return { tone: 'leak', badge: '拦截 (/sorry)', detail: '商店页触发 429 / /sorry/', ms, exitSlot };
  }
  if (!s.play || s.play === '?') {
    return { tone: 'muted', badge: 'N/A', detail: '未取到商店地区', ms, exitSlot };
  }
  const iso = normalizeCountryCode(s.play);
  if (iso && RESTRICTED_GOOGLE_AI.has(iso)) {
    return { tone: 'leak', badge: `受限 [${iso}]`, detail: s.play, ms, exitSlot };
  }
  return { tone: 'ok', badge: iso ? `正常 [${iso}]` : s.play, detail: s.play, ms, exitSlot };
}

function buildSearchCell(s: StackProbeV1): ServiceCell {
  const ms = s.rtt?.srch;
  const exitSlot = resolveCellExit(s, 'srch');
  const hkRedirect = s.sdom === 'hkredirect' || (s.sdom && /\.hk$|\.cn$/i.test(s.sdom));
  if (hkRedirect || s.scap === 'hk') {
    return {
      tone: 'leak',
      badge: '重定向 (.com.hk)',
      detail: s.sdom === 'hkredirect' ? '302 pref=hkredirect' : '重定向至香港搜索域',
      ms,
      exitSlot,
    };
  }
  if (s.scap === 'captcha') {
    return {
      tone: 'diff',
      badge: '弹验证码 (/sorry)',
      detail: s.sdom ? `搜索域 ${s.sdom}` : '触发异常流量验证',
      ms,
      exitSlot,
    };
  }
  if (s.scap === 'jswall') {
    return {
      tone: 'diff',
      badge: s.sdom ? `${s.sdom} (JS墙)` : 'JS验证墙',
      detail: '无 JS 客户端命中 enablejs（非 /sorry）',
      ms,
      exitSlot,
    };
  }
  if (s.scap === 'ok') {
    return {
      tone: 'ok',
      badge: s.sdom ?? '无验证码',
      detail: 'SERP 响应正常 · 无 /sorry 拦截',
      ms,
      exitSlot,
    };
  }
  if (s.sdom && (!s.scap || s.scap === 'skipped')) {
    return {
      tone: 'ok',
      badge: `${s.sdom} (域正常)`,
      detail: '默认跳过 /search 页面请求（可通过 --probe-search 启用）',
      ms,
      exitSlot,
    };
  }
  if (s.sdom && s.scap === 'err') {
    return {
      tone: 'diff',
      badge: `${s.sdom} (SERP异常)`,
      detail: '搜索域正常，但主动 SERP 探测未响应',
      ms,
      exitSlot,
    };
  }
  return { tone: 'muted', badge: 'N/A', detail: '未响应', ms, exitSlot };
}

function buildTermsCell(s: StackProbeV1): ServiceCell {
  const exitSlot = resolveCellExit(s, 'trm');
  if (s.trmst === 'captcha') {
    return { tone: 'leak', badge: '拦截 (/sorry)', detail: '条款页触发 429 / /sorry/', exitSlot };
  }
  if (!s.trm || s.trm === '?') {
    return { tone: 'muted', badge: 'N/A', detail: s.ent ?? '未提取到条款国', exitSlot };
  }
  const iso = normalizeCountryCode(s.trm);
  if (iso && RESTRICTED_GOOGLE_AI.has(iso)) {
    return { tone: 'leak', badge: `受限 [${iso}]`, detail: `${s.trm} · ${s.ent ?? ''}`.trim(), exitSlot };
  }
  if (s.ent === 'Google Ireland Limited' || (iso && EEA_UK_CH.has(iso))) {
    return {
      tone: 'diff',
      badge: `EEA [${iso ?? s.trm}]`,
      detail: `${s.ent ?? s.trm}（免费 API 需绑卡）`,
      exitSlot,
    };
  }
  return {
    tone: 'ok',
    badge: iso ? `正常 [${iso}]` : s.trm,
    detail: `${s.trm}${s.ent ? ` · ${s.ent}` : ''}`,
    exitSlot,
  };
}

function clusterRouteExits(
  report: CliReportV1,
  defaultEgress: EgressAttribution,
  googleEgress: EgressAttribution | null,
): readonly RouteExitCluster[] {
  const rt = report.rt;
  if (!rt) return [];

  const clusters: RouteExitCluster[] = [];

  if (rt.cn && (rt.cn.ip || rt.cn.cc || rt.cn.note)) {
    const cnCc = normalizeCountryCode(rt.cn.cc);
    const isRealCn = cnCc === 'CN' || Boolean(rt.cn.note?.includes('中国'));
    if (isRealCn || report.m === 'proxy') {
      clusters.push({
        slot: isRealCn ? '直连 CN' : '国内异常',
        slotColor: 'cn',
        tone: isRealCn ? 'ok' : 'leak',
        ip: rt.cn.ip ?? '--',
        asn: rt.cn.asn ?? null,
        org: rt.cn.note || rt.cn.org || (isRealCn ? '国内直连出口' : '非 CN 出口'),
        kindLabel: isRealCn ? '直连分流' : '路由提醒',
        cc: rt.cn.cc ?? (isRealCn ? 'CN' : '?'),
        buckets: [isRealCn ? '国内直连出口' : '国内参照点落入非 CN 出口'],
        avgMs: rt.cn.ms ?? null,
        warp: false,
        isCnDirect: isRealCn,
      });
    }
  }

  const orderedDefs: readonly { key: 'def' | 'ggc' | 'cf' | 'oai' | 'cld'; label: string }[] = [
    { key: 'def', label: '通用海外' },
    { key: 'ggc', label: 'Google/YT GGC' },
    { key: 'cf', label: 'Cloudflare' },
    { key: 'oai', label: 'OpenAI (ChatGPT)' },
    { key: 'cld', label: 'Anthropic (Claude)' },
  ];

  interface MutableBucketGroup {
    ip: string;
    asn: number | null;
    org: string;
    kind: 'hosting' | 'isp' | 'warp' | 'business' | 'unknown';
    cc: string;
    buckets: string[];
    msList: number[];
    warp: boolean;
  }

  const byKey = new Map<string, MutableBucketGroup>();
  const order: string[] = [];

  for (const item of orderedDefs) {
    const b: RouteBucketV1 | undefined = rt[item.key];
    if (!b || !b.ip) continue;
    const key = b.ip.toLowerCase();
    const warpOn = b.warp === 'on' || b.warp === 'plus';
    const suffixParts: string[] = [];
    if (b.colo) suffixParts.push(b.colo);
    if (warpOn) suffixParts.push('WARP');
    const bucketTag = suffixParts.length > 0 ? `${item.label} (${suffixParts.join('/')})` : item.label;

    const existing = byKey.get(key);
    if (existing) {
      existing.buckets.push(bucketTag);
      if (b.ms !== undefined) existing.msList.push(b.ms);
      if (warpOn) existing.warp = true;
      if (!existing.asn && b.asn) existing.asn = b.asn;
      if ((!existing.org || existing.org === 'Unknown') && b.org) existing.org = b.org;
      if (!existing.cc && b.cc) existing.cc = b.cc;
      if (existing.kind === 'unknown' && b.kind) existing.kind = b.kind;
    } else {
      const sameAsDef = key === defaultEgress.ip.toLowerCase();
      const sameAsGoogle = googleEgress !== null && key === googleEgress.ip.toLowerCase();
      const org = b.org ?? (sameAsDef ? defaultEgress.org : sameAsGoogle ? googleEgress.org : warpOn ? 'Cloudflare WARP' : '独立出口');
      const asn = b.asn ?? (sameAsDef ? defaultEgress.asn : sameAsGoogle ? googleEgress.asn : warpOn ? 13335 : null);
      const kind = classifyOrgKind(
        org,
        asn ?? undefined,
        b.ip,
        b.kind ?? (sameAsDef ? defaultEgress.kind : sameAsGoogle ? googleEgress.kind : warpOn ? 'warp' : undefined),
      );
      byKey.set(key, {
        ip: b.ip,
        asn,
        org,
        kind,
        cc: b.cc ?? (sameAsDef ? (report.v4?.cc ?? report.v6?.cc ?? '') : ''),
        buckets: [bucketTag],
        msList: b.ms !== undefined ? [b.ms] : [],
        warp: warpOn || kind === 'warp',
      });
      order.push(key);
    }
  }

  const slotLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  order.forEach((key, idx) => {
    const g = byKey.get(key);
    if (!g) return;
    const avgMs =
      g.msList.length > 0 ? Math.round(g.msList.reduce((acc, v) => acc + v, 0) / g.msList.length) : null;
    const letter = slotLetters[idx] ?? String(idx + 1);
    const slotName = `出口 ${letter}`;
    clusters.push({
      slot: slotName,
      slotColor: resolveExitSlotColor(slotName),
      tone: g.warp ? 'diff' : idx === 0 ? 'muted' : 'ok',
      ip: g.ip,
      asn: g.asn,
      org: g.org,
      kindLabel: kindToChineseLabel(g.kind),
      cc: g.cc || '?',
      buckets: g.buckets,
      avgMs,
      warp: g.warp,
      isCnDirect: false,
    });
  });

  return clusters;
}

function extractRouteAlarms(
  report: CliReportV1,
  clusters: readonly RouteExitCluster[],
  hasDualStackAsymmetry: boolean,
  hasAiVsGoogleSplit: boolean,
): readonly RouteAlarm[] {
  const alarms: RouteAlarm[] = [];
  const rawSet = new Set(report.al ?? []);
  const rt = report.rt;

  const cnBad = rawSet.has('cn_leak') || clusters.some((c) => c.slot === '国内异常');
  if (cnBad) {
    alarms.push({
      id: 'cn_leak',
      tone: 'leak',
      title: '国内参照探测点经非 CN 出口出站',
      detail: `国内参照探测点返回 ${rt?.cn?.ip ?? '?'} (${rt?.cn?.cc ?? '非CN'})，未走本地直连路由。`,
    });
  }

  if (hasDualStackAsymmetry || rawSet.has('stack_split')) {
    alarms.push({
      id: 'stack_split',
      tone: 'leak',
      title: 'IPv4 / IPv6 双栈地区判定不一致',
      detail: '客户端通常优先尝试 IPv6 (Happy Eyeballs)，双栈判区不一致会导致连接结果不稳定。',
    });
  }

  if (hasAiVsGoogleSplit || rawSet.has('google_region_split')) {
    alarms.push({
      id: 'google_region_split',
      tone: 'diff',
      title: 'Google 服务间归属地不一致',
      detail: 'Gemini 与 Play / Search / Terms 判定国家不同，建议核对分流路由是否一致。',
    });
  }

  const overseasSlots = clusters.filter((c) => !c.isCnDirect);
  const aiIps = new Set(
    [rt?.ggc?.ip, rt?.oai?.ip, rt?.cld?.ip].filter((v): v is string => Boolean(v)),
  );
  if (rawSet.has('ai_split') || aiIps.size >= 2) {
    const parts: string[] = [];
    if (rt?.ggc?.ip) parts.push(`Google/YT=${rt.ggc.ip}`);
    if (rt?.oai?.ip) parts.push(`ChatGPT=${rt.oai.ip}${rt.oai.cc ? `(${rt.oai.cc})` : ''}`);
    if (rt?.cld?.ip) parts.push(`Claude=${rt.cld.ip}${rt.cld.cc ? `(${rt.cld.cc})` : ''}`);
    alarms.push({
      id: 'ai_split',
      tone: 'diff',
      title: `跨 AI 生态走了 ${aiIps.size || overseasSlots.length} 条不同出口`,
      detail: parts.length > 0 ? parts.join(' · ') : 'Gemini / ChatGPT / Claude 命中不同策略出口，请确认是否符合预期。',
    });
  }

  if (rawSet.has('warp_egress') || clusters.some((c) => c.warp)) {
    const warpBuckets = clusters
      .filter((c) => c.warp)
      .flatMap((c) => c.buckets)
      .slice(0, 4);
    alarms.push({
      id: 'warp_egress',
      tone: 'ok',
      title: '检出 Cloudflare WARP 出站分流',
      detail: warpBuckets.length > 0 ? `经 WARP 出站: ${warpBuckets.join('、')}` : '部分海外/Google 流量通过 WARP 转发。',
    });
  }

  return alarms;
}

export function diagnoseCliReport(report: CliReportV1): ReportDiagnosis {
  const v4 = report.v4;
  const v6 = report.v6;
  const primary = v4 ?? v6;

  const h4 = evaluateStackHealth(v4, 'IPv4');
  const h6 = evaluateStackHealth(v6, 'IPv6');

  const hasBothStacks = Boolean(v4 && v6);
  const v4v6CountryMismatch =
    hasBothStacks &&
    h4.dominantGoogleCc !== null &&
    h6.dominantGoogleCc !== null &&
    h4.dominantGoogleCc !== h6.dominantGoogleCc;

  const hasDualStackAsymmetry =
    hasBothStacks &&
    (v4v6CountryMismatch || h4.hasDrift !== h6.hasDrift);

  const primaryPublicCc = normalizeCountryCode(primary?.cc);
  const appleCc = normalizeCountryCode(report.ap);
  const primaryGoogleCc = h4.dominantGoogleCc ?? h6.dominantGoogleCc;

  // Did user's proxy split General Overseas (ident.me) from Google / AI?
  const anyIpSplit = h4.hasIpSplit || h6.hasIpSplit;
  const cleanGoogleOnDiffCountry =
    !h4.hasDrift &&
    !h6.hasDrift &&
    primaryPublicCc !== null &&
    primaryGoogleCc !== null &&
    primaryPublicCc !== primaryGoogleCc;
  const hasSplitRoute =
    anyIpSplit ||
    (report.m === 'proxy' && cleanGoogleOnDiffCountry) ||
    h4.hasAiVsGoogleSplit ||
    h6.hasAiVsGoogleSplit;

  // Google-only CN drift: public GeoIP & Apple say non-CN/HK, yet Google says CN/blocked
  const anyDrift = h4.hasDrift || h6.hasDrift;
  const googleOnlyDrift =
    anyDrift &&
    primaryPublicCc !== null &&
    !RESTRICTED_GOOGLE_AI.has(primaryPublicCc) &&
    (appleCc === null || !RESTRICTED_GOOGLE_AI.has(appleCc));

  const hasEeaNotice = h4.hasEea || h6.hasEea;

  const defaultKind = classifyOrgKind(primary?.org, primary?.asn, primary?.ip, primary?.kind);
  const defaultEgress: EgressAttribution = {
    ip: primary?.ip ?? 'N/A',
    asn: primary?.asn ?? null,
    org: primary?.org ?? 'Unknown',
    kind: defaultKind,
    kindLabel: kindToChineseLabel(defaultKind),
  };

  let googleEgress: EgressAttribution | null = null;
  if (primary?.gip && primary.gip !== primary.ip) {
    const gKind = classifyOrgKind(primary.gorg, primary.gasn, primary.gip, primary.gkind);
    const inferredOrg =
      primary.gorg ?? (gKind === 'warp' ? 'Cloudflare WARP' : '独立分流出口');
    const inferredAsn = primary.gasn ?? (gKind === 'warp' ? 13335 : null);
    googleEgress = {
      ip: primary.gip,
      asn: inferredAsn,
      org: inferredOrg,
      kind: gKind,
      kindLabel: kindToChineseLabel(gKind),
    };
  }

  // Strictly evaluate hosting anti-anxiety badge on the ACTUAL Google egress ASN
  const effectiveGoogleKind = googleEgress ? googleEgress.kind : defaultEgress.kind;
  const isHostingVerifiedOk =
    effectiveGoogleKind === 'hosting' && !anyDrift && !h4.hasCaptcha && !h6.hasCaptcha;

  const modeLabel =
    report.m === 'proxy'
      ? report.tun
        ? '代理/分流出站 · TUN'
        : '代理/分流出站'
      : anyIpSplit
        ? '直连主机 · 出站分流'
        : '直连出站';

  const transportLabel = report.net?.label
    ? report.net.nic && !report.net.label.includes(report.net.nic)
      ? `${report.net.label} (${report.net.nic})`
      : report.net.label
    : modeLabel;

  const routeClusters = clusterRouteExits(report, defaultEgress, googleEgress);
  const routeAlarms = extractRouteAlarms(
    report,
    routeClusters,
    hasDualStackAsymmetry,
    h4.hasAiVsGoogleSplit || h6.hasAiVsGoogleSplit,
  );

  // Determine 4-state verdict tier
  let tier: VerdictTier = 'clean';
  let tierCode = 'CLEAN';
  let headline = 'Google 服务可达，地区判定一致';
  let summary = '6 项探测响应正常，归属地位于支持区域，未触发异常流量验证。';

  if (anyDrift && !hasDualStackAsymmetry) {
    tier = 'drift';
    tierCode = 'CN_DRIFT';
    headline = googleOnlyDrift
      ? `Google 归属地偏移至受限区（公开 GeoIP${appleCc ? ` 与 Apple 为 ${appleCc}` : ` 为 ${primaryPublicCc}`}）`
      : 'Google 判定当前出口位于受限地区';
    summary = [...h4.driftReasons, ...h6.driftReasons].slice(0, 3).join('；') + '。';
  } else if (hasDualStackAsymmetry) {
    tier = 'partial';
    tierCode = 'STACK_SPLIT';
    headline = 'IPv4 与 IPv6 双栈地区判定不一致';
    summary = `IPv4 判区 ${h4.dominantGoogleCc ?? '?'}，IPv6 判区 ${h6.dominantGoogleCc ?? '?'}。客户端通常优先尝试 IPv6，双栈不一致可能导致部分服务判定受限。`;
  } else if (h4.hasAiVsGoogleSplit || h6.hasAiVsGoogleSplit) {
    tier = 'partial';
    tierCode = 'GROUP_SPLIT';
    headline = 'Google AI 与基础服务出口地区不一致';
    summary = [...h4.partialReasons, ...h6.partialReasons].join('；') + '。建议核对相关域名命中的出站路由是否统一。';
  } else if (h4.hasCaptcha || h6.hasCaptcha || h4.hasPartialIssue || h6.hasPartialIssue) {
    tier = 'partial';
    tierCode = 'PARTIAL';
    const gemBlocked = v4?.gemst === 'captcha' || v6?.gemst === 'captcha';
    const gemTimedOut = v4?.gemst === 'timeout' || v6?.gemst === 'timeout';
    headline = gemBlocked
      ? 'Gemini 触发 /sorry/ 异常流量验证 (HTTP 429)'
      : h4.hasCaptcha || h6.hasCaptcha
        ? '检测到 Google /sorry/ 异常流量验证'
        : gemTimedOut
          ? 'Gemini 探测超时（可能被限速或链路抖动）'
          : '检测到局部异常或探测无响应';
    summary = [...h4.partialReasons, ...h6.partialReasons, ...h4.driftReasons, ...h6.driftReasons].join('；') + '。';
  } else if (hasSplitRoute) {
    tier = 'split';
    tierCode = 'SPLIT_ROUTE';
    headline = googleEgress
      ? `多出口分流生效 · Google 经 ${googleEgress.kindLabel} 出口可达`
      : '多出口分流生效 · Google 服务可达';
    summary = googleEgress
      ? `默认出口 (${defaultEgress.ip} · ${defaultEgress.org}) 与 Google 侧出口 (${googleEgress.ip} · ${googleEgress.org}) 已分离，6 项探测均位于支持地区 (${primaryGoogleCc ?? 'OK'})。`
      : `当前为分流出站，默认出口 (${primaryPublicCc ?? '?'}) 与 Google 侧 (${primaryGoogleCc ?? '?'}) 归属地不同且均正常响应。`;
  } else if (isHostingVerifiedOk) {
    headline = '数据中心出口可达 · 服务与归属地正常';
    summary = `当前出口属于 ${defaultEgress.org}（数据中心网段），6 项 Google 服务探测均正常响应，未触发 /sorry 验证。`;
  }

  // Status badges (crisp, scannable)
  const badges: ReportBadge[] = [];
  badges.push({ tone: 'muted', text: transportLabel });
  if (isHostingVerifiedOk) {
    badges.push({ tone: 'ok', text: '数据中心网段' });
  } else if (effectiveGoogleKind === 'warp') {
    badges.push({ tone: 'ok', text: 'WARP 出站' });
  } else if (effectiveGoogleKind === 'isp') {
    badges.push({ tone: 'ok', text: '运营商网段' });
  }
  if (primary?.dns === 'native') {
    badges.push({ tone: 'ok', text: 'Native DNS' });
  } else if (primary?.dns === 'viadns') {
    badges.push({ tone: 'diff', text: 'DNS 转发 (ViaDNS)' });
  }
  if (hasBothStacks) {
    badges.push({
      tone: hasDualStackAsymmetry ? 'leak' : 'ok',
      text: hasDualStackAsymmetry ? 'v4/v6 冲突' : 'v4+v6 双栈一致',
    });
  }
  if (hasEeaNotice) {
    badges.push({ tone: 'diff', text: 'EEA 免费层提醒' });
  }
  if (report.cn) {
    badges.push({ tone: 'muted', text: '国内直连已拆分' });
  }

  // Three-way geo comparison bar
  const publicGeoLabel = primary?.cc
    ? `${primary.cc}${primary.city ? ` · ${primary.city}` : ''}`
    : '未知';
  const appleGeoLabel = report.ap ? `${report.ap} (Apple GCC)` : '未测';
  const googleGeoLabel = primaryGoogleCc
    ? `${primaryGoogleCc}${hasDualStackAsymmetry && h6.dominantGoogleCc ? ` / v6:${h6.dominantGoogleCc}` : ''}`
    : '未知';

  // 7-row service matrix
  const rows: ServiceMatrixRow[] = [
    {
      id: 'gemini',
      label: 'Gemini 网页 / Boq',
      probeHint: 'gemini.google.com/app',
      v4: v4 ? buildGeminiCell(v4) : null,
      v6: v6 ? buildGeminiCell(v6) : null,
    },
    {
      id: 'notebooklm',
      label: 'NotebookLM 1-RTT',
      probeHint: 'notebooklm.google.com',
      v4: v4 ? buildNotebookCell(v4) : null,
      v6: v6 ? buildNotebookCell(v6) : null,
    },
    {
      id: 'youtube',
      label: 'YouTube Premium',
      probeHint: 'youtube.com/premium',
      v4: v4 ? buildYoutubeCell(v4) : null,
      v6: v6 ? buildYoutubeCell(v6) : null,
    },
    {
      id: 'ggc',
      label: 'YouTube GGC 边缘',
      probeHint: 'googlevideo/report_mapping',
      v4: v4 ? buildGgcCell(v4) : null,
      v6: v6 ? buildGgcCell(v6) : null,
    },
    {
      id: 'play',
      label: 'Google Play 商店',
      probeHint: 'play.google.com',
      v4: v4 ? buildPlayCell(v4) : null,
      v6: v6 ? buildPlayCell(v6) : null,
    },
    {
      id: 'search',
      label: 'Google Search',
      probeHint: 'searchdomaincheck + /search',
      v4: v4 ? buildSearchCell(v4) : null,
      v6: v6 ? buildSearchCell(v6) : null,
    },
    {
      id: 'terms',
      label: 'Google 条款辖区',
      probeHint: 'policies.google.com/terms',
      v4: v4 ? buildTermsCell(v4) : null,
      v6: v6 ? buildTermsCell(v6) : null,
    },
  ];

  return {
    tier,
    tierCode,
    headline,
    summary,
    badges,
    modeLabel,
    transportLabel,
    defaultEgress,
    googleEgress,
    publicGeoLabel,
    appleGeoLabel,
    googleGeoLabel,
    googleOnlyDrift,
    hasSplitRoute,
    hasDualStackAsymmetry,
    hasEeaNotice,
    isHostingVerifiedOk,
    routeClusters,
    routeAlarms,
    rows,
  };
}

export function buildDiffRows(left: CliReportV1, right: CliReportV1): readonly DiffRow[] {
  const dl = diagnoseCliReport(left);
  const dr = diagnoseCliReport(right);

  const lPrimary = left.v4 ?? left.v6;
  const rPrimary = right.v4 ?? right.v6;

  const pickCell = (row: ServiceMatrixRow): { text: string; tone: CellTone } => {
    const c4 = row.v4;
    const c6 = row.v6;
    if (c4 && c6 && c4.badge !== c6.badge) {
      return {
        text: `v4:${c4.badge} / v6:${c6.badge}`,
        tone: c4.tone === 'leak' || c6.tone === 'leak' ? 'leak' : 'diff',
      };
    }
    const c = c4 ?? c6;
    return c ? { text: c.badge, tone: c.tone } : { text: '--', tone: 'muted' };
  };

  const rows: DiffRow[] = [
    {
      id: 'verdict',
      label: '综合结论',
      leftText: `${dl.tierCode} · ${dl.headline}`,
      leftTone: dl.tier === 'drift' ? 'leak' : dl.tier === 'partial' ? 'diff' : 'ok',
      rightText: `${dr.tierCode} · ${dr.headline}`,
      rightTone: dr.tier === 'drift' ? 'leak' : dr.tier === 'partial' ? 'diff' : 'ok',
      changed: dl.tier !== dr.tier || dl.googleGeoLabel !== dr.googleGeoLabel,
    },
    {
      id: 'exit',
      label: '通用出口 / ASN',
      leftText: `${lPrimary?.ip ?? '--'} · AS${lPrimary?.asn ?? '?'} (${lPrimary?.cc ?? '?'})`,
      leftTone: 'muted',
      rightText: `${rPrimary?.ip ?? '--'} · AS${rPrimary?.asn ?? '?'} (${rPrimary?.cc ?? '?'})`,
      rightTone: 'muted',
      changed: lPrimary?.ip !== rPrimary?.ip || lPrimary?.asn !== rPrimary?.asn,
    },
    {
      id: 'apple',
      label: 'Apple 第三方对照',
      leftText: dl.appleGeoLabel,
      leftTone: 'muted',
      rightText: dr.appleGeoLabel,
      rightTone: 'muted',
      changed: dl.appleGeoLabel !== dr.appleGeoLabel,
    },
  ];

  for (let i = 0; i < dl.rows.length; i += 1) {
    const lr = dl.rows[i];
    const rr = dr.rows[i];
    if (!lr || !rr) continue;
    const lc = pickCell(lr);
    const rc = pickCell(rr);
    rows.push({
      id: lr.id,
      label: lr.label,
      leftText: lc.text,
      leftTone: lc.tone,
      rightText: rc.text,
      rightTone: rc.tone,
      changed: lc.text !== rc.text || lc.tone !== rc.tone,
    });
  }

  return rows;
}

export function buildReportMarkdown(report: CliReportV1, diag: ReportDiagnosis): string {
  const ts = new Date(report.t * 1000).toISOString().replace('T', ' ').slice(0, 19) + ' UTC';
  const lines = [
    `## G-ROUTE // 网络出口与连通性诊断报告 (${diag.tierCode})`,
    `- **结论**: ${diag.headline}`,
    `- **运行形态**: ${diag.transportLabel}`,
    `- **通用出口**: \`${diag.defaultEgress.ip}\` | AS${diag.defaultEgress.asn ?? '?'} ${diag.defaultEgress.org} (${diag.defaultEgress.kindLabel})`,
    ...(diag.googleEgress
      ? [
          `- **Google 实见出口**: \`${diag.googleEgress.ip}\` | AS${diag.googleEgress.asn ?? '?'} ${diag.googleEgress.org} (${diag.googleEgress.kindLabel})`,
        ]
      : []),
    `- **三方对照**: 公开库 \`${diag.publicGeoLabel}\` / Apple \`${diag.appleGeoLabel}\` / Google 实测 \`${diag.googleGeoLabel}\``,
    `- **时间**: ${ts}`,
  ];

  if (diag.routeClusters.length > 0) {
    lines.push('', '| 出口槽 | 归属与 ASN | 命中业务桶 | 平均 RTT |', '| :--- | :--- | :--- | :--- |');
    for (const c of diag.routeClusters) {
      const asnStr = c.asn ? `AS${c.asn} ` : '';
      const msStr = c.avgMs !== null ? `${c.avgMs} ms` : '--';
      lines.push(`| ${c.slot} | \`${c.ip}\` · ${asnStr}${c.org} (${c.kindLabel}) | ${c.buckets.join(' / ')} | ${msStr} |`);
    }
  }

  lines.push('', '| 服务维度 | IPv4 | IPv6 |', '| :--- | :--- | :--- |');

  for (const row of diag.rows) {
    const v4Txt = row.v4 ? `${row.v4.badge} (${row.v4.detail}${row.v4.ms ? ` · ${row.v4.ms}ms` : ''})` : '--';
    const v6Txt = row.v6 ? `${row.v6.badge} (${row.v6.detail}${row.v6.ms ? ` · ${row.v6.ms}ms` : ''})` : '--';
    lines.push(`| ${row.label} | ${v4Txt} | ${v6Txt} |`);
  }

  if (diag.routeAlarms.length > 0) {
    lines.push('', '### 分流提醒');
    for (const al of diag.routeAlarms) {
      lines.push(`- **${al.title}**: ${al.detail}`);
    }
  }

  return lines.join('\n');
}
