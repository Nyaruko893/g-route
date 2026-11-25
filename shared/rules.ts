export type RuleClient = 'clash' | 'singbox' | 'surge' | 'loon';

interface PatchOptions {
  readonly policyGroup: string;
  readonly includeAiBackend: boolean;
  readonly includeAntiGoogleCn: boolean;
  readonly includeGoogleCore: boolean;
  readonly includeGmsFcm: boolean;
}

interface RuleEntry {
  readonly type: 'DOMAIN' | 'DOMAIN-SUFFIX';
  readonly value: string;
}

const AI_FRONTEND_RULES: readonly RuleEntry[] = [
  { type: 'DOMAIN-SUFFIX', value: 'gemini.google.com' },
  { type: 'DOMAIN', value: 'aistudio.google.com' },
  { type: 'DOMAIN', value: 'makersuite.google.com' },
  { type: 'DOMAIN', value: 'ai.google.dev' },
  { type: 'DOMAIN-SUFFIX', value: 'notebooklm.google.com' },
  { type: 'DOMAIN', value: 'notebook.google.com' },
  { type: 'DOMAIN', value: 'notebook.cloud.google.com' },
  { type: 'DOMAIN-SUFFIX', value: 'labs.google' },
  { type: 'DOMAIN-SUFFIX', value: 'antigravity.google' },
  { type: 'DOMAIN-SUFFIX', value: 'deepmind.google' },
  { type: 'DOMAIN-SUFFIX', value: 'generativeai.google' },
];

const AI_BACKEND_RULES: readonly RuleEntry[] = [
  { type: 'DOMAIN', value: 'generativelanguage.googleapis.com' },
  { type: 'DOMAIN', value: 'geminiweb-pa.clients6.google.com' },
  { type: 'DOMAIN', value: 'robinfrontend-pa.googleapis.com' },
  { type: 'DOMAIN', value: 'alkalimakersuite-pa.clients6.google.com' },
  { type: 'DOMAIN', value: 'alkalicore-pa.clients6.google.com' },
  { type: 'DOMAIN', value: 'webchannel-alkalimakersuite-pa.clients6.google.com' },
  { type: 'DOMAIN', value: 'proactivebackend-pa.googleapis.com' },
  { type: 'DOMAIN', value: 'notebooklm-pa.googleapis.com' },
  { type: 'DOMAIN', value: 'antigravity-pa.googleapis.com' },
  { type: 'DOMAIN', value: 'antigravity.googleapis.com' },
  { type: 'DOMAIN', value: 'antigravity-unleash.goog' },
  { type: 'DOMAIN', value: 'cloudcode-pa.googleapis.com' },
  { type: 'DOMAIN', value: 'daily-cloudcode-pa.sandbox.googleapis.com' },
  { type: 'DOMAIN', value: 'cloudaicompanion.googleapis.com' },
  { type: 'DOMAIN', value: 'waa-pa.clients6.google.com' },
  { type: 'DOMAIN', value: 'jnn-pa.googleapis.com' },
];

const ANTI_GOOGLE_CN_RULES: readonly RuleEntry[] = [
  { type: 'DOMAIN-SUFFIX', value: 'googleapis.cn' },
  { type: 'DOMAIN-SUFFIX', value: 'google.cn' },
  { type: 'DOMAIN', value: 'connectivitycheck.gstatic.com' },
  { type: 'DOMAIN', value: 'dl.google.com' },
  { type: 'DOMAIN', value: 'dl.l.google.com' },
];

const GOOGLE_CORE_RULES: readonly RuleEntry[] = [
  { type: 'DOMAIN', value: 'accounts.google.com' },
  { type: 'DOMAIN', value: 'oauth2.googleapis.com' },
  { type: 'DOMAIN', value: 'policies.google.com' },
  { type: 'DOMAIN', value: 'www.google.com' },
  { type: 'DOMAIN', value: 'play.google.com' },
  { type: 'DOMAIN', value: 'drive.google.com' },
  { type: 'DOMAIN-SUFFIX', value: 'googleusercontent.com' },
];

const GMS_FCM_RULES: readonly RuleEntry[] = [
  { type: 'DOMAIN', value: 'mtalk.google.com' },
  { type: 'DOMAIN', value: 'alt1-mtalk.google.com' },
  { type: 'DOMAIN', value: 'alt2-mtalk.google.com' },
  { type: 'DOMAIN', value: 'alt3-mtalk.google.com' },
  { type: 'DOMAIN', value: 'alt4-mtalk.google.com' },
  { type: 'DOMAIN', value: 'alt5-mtalk.google.com' },
  { type: 'DOMAIN', value: 'alt6-mtalk.google.com' },
  { type: 'DOMAIN', value: 'alt7-mtalk.google.com' },
  { type: 'DOMAIN', value: 'alt8-mtalk.google.com' },
  { type: 'DOMAIN', value: 'android.clients.google.com' },
  { type: 'DOMAIN', value: 'play.googleapis.com' },
  { type: 'DOMAIN-SUFFIX', value: 'xn--ngstr-lra8j.com' },
];

function collectEntries(opts: PatchOptions): readonly RuleEntry[] {
  const seen = new Set<string>();
  const out: RuleEntry[] = [];
  const push = (list: readonly RuleEntry[]) => {
    for (const item of list) {
      const key = `${item.type}:${item.value}`;
      if (!seen.has(key)) {
        seen.add(key);
        out.push(item);
      }
    }
  };

  push(AI_FRONTEND_RULES);
  if (opts.includeAiBackend) push(AI_BACKEND_RULES);
  if (opts.includeAntiGoogleCn) push(ANTI_GOOGLE_CN_RULES);
  if (opts.includeGoogleCore) push(GOOGLE_CORE_RULES);
  if (opts.includeGmsFcm) push(GMS_FCM_RULES);
  return out;
}

export function generateRulePatch(client: RuleClient, opts: PatchOptions): string {
  const group = opts.policyGroup.trim() || 'GoogleAI';
  const entries = collectEntries(opts);

  if (client === 'clash') {
    const lines = [
      '# 请务必置于 GEOSITE,google-cn / GEOIP,CN / MATCH 之前',
      '# 策略组请指向固定地区节点（避免 url-test 跨国跳变或滑向香港）',
      '# 注：刻意未纳入 gvt1/gvt2/googlevideo 大流量 CDN，防止跑光 AI 专组流量',
      'rules:',
      ...entries.map((e) => `  - ${e.type},${e.value},${group}`),
    ];
    return lines.join('\n');
  }

  if (client === 'singbox') {
    const domains = entries.filter((e) => e.type === 'DOMAIN').map((e) => e.value);
    const suffixes = entries.filter((e) => e.type === 'DOMAIN-SUFFIX').map((e) => e.value);
    const ruleObj = {
      domain: domains,
      domain_suffix: suffixes,
      outbound: group,
    };
    return `// 插入 route.rules 顶部（位于 geosite:google-cn / geoip:cn 之前；未含大流量 CDN）\n${JSON.stringify(ruleObj, null, 2)}`;
  }

  if (client === 'loon') {
    const lines = [
      '# Loon [Rule] 顶部（置于 GEOIP,CN 与 FINAL 之前）',
      '# 注：未含 gvt1/gvt2/googlevideo 大流量 CDN',
      ...entries.map((e) => `${e.type},${e.value},${group}`),
    ];
    return lines.join('\n');
  }

  const lines = [
    '# Surge / Shadowrocket [Rule] 顶部（置于 GEOIP,CN 与 FINAL 之前）',
    '# 注：刻意未纳入 gvt1/gvt2/googlevideo 大流量 CDN',
    ...entries.map((e) => `${e.type},${e.value},${group}`),
  ];
  return lines.join('\n');
}
