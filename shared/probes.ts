export const DUAL_STACK_ECHO_SOURCES = {
  v4: [
    'https://v4.ident.me/json',
    'https://api4.ipify.org?format=json',
  ],
  v6: [
    'https://v6.ident.me/json',
    'https://api6.ipify.org?format=json',
  ],
} as const;

/**
 * Domestic China-routed endpoints (matched by geosite:cn / DIRECT in rule-based proxies).
 * Used to distinguish Rule Split-Routing vs Global Proxy in the browser quick-check bar.
 */
export const DOMESTIC_DIRECT_SOURCES = {
  ipApis: [
    'https://qifu-api.baidubce.com/ip/local/geo/v1/district',
    'https://api.vore.top/api/IPdata',
  ],
  rttProbeUrl: 'https://www.baidu.com/favicon.ico',
} as const;

export const STUN_SERVERS = {
  cloudflare: 'stun:stun.cloudflare.com:3478',
  google: 'stun:stun.l.google.com:19302',
} as const;
