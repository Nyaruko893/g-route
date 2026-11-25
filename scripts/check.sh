#!/usr/bin/env bash
# G-ROUTE // Google 生态送中与分流体检脚本 (Linux / macOS / VPS)
# 权限契约：零提权(不需 sudo) · 零读磁盘配置/订阅/SSH · 零数据上传 · 零二进制下载
# 零第三方依赖 (仅需 curl + POSIX grep/sed/awk + base64；可选 gzip)
set -u

G_ROUTE_ORIGIN="${G_ROUTE_ORIGIN:-__G_ROUTE_ORIGIN__}"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
SOCS_COOKIE="YSC=FSCWhKo2Zgw; SOCS=CAISHAgBEhJnd3NfMjAyNDA1MjctMF9SQzIaAmVuIAEaBgiA_LyaBg"

OPT_V4=1
OPT_V6=1
OPT_FULL=0
OPT_JSON=0
OPT_NO_LINK=0
OPT_DRY_RUN=0
OPT_PROXY=""
OPT_MODE=""
OPT_CONTROLLER="${G_ROUTE_CONTROLLER:-}"
OPT_SECRET="${G_ROUTE_SECRET:-}"

usage() {
  cat <<'EOF'
G-ROUTE // Google 生态送中与分流体检仪 (CLI)
用法:
  bash <(curl -sL https://<origin>/sh) [选项]

选项:
  -4                       仅检测 IPv4
  -6                       仅检测 IPv6
  -x <proxy_url>           指定代理 (http:// / https:// / socks5://)
  -f, --full               显示完整 IP（默认自动脱敏如 38.59.*.*）
  -j, --json               仅输出紧凑 JSON (CliReportV1)，不打印终端卡片
  --no-link                不输出底部离线 #r= 网页体检卡链接
  --dry-run                零发包安全审计模式：仅打印将访问的 URL 与权限边界后退出
  --controller <url>       [可选] 显式指定本地 Clash/Mihomo 控制 API (如 http://127.0.0.1:9090)
                           仅在本地终端只读展示实际命中规则与策略链，绝不写入 #r= 链接
  --secret <token>         [可选] 配合 --controller 使用的控制 API 密钥
  --vps / --direct         强制按直连出站模式判定
  --proxy                  强制按代理/分流出站模式判定
  -h, --help               显示帮助
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    -4) OPT_V4=1; OPT_V6=0 ;;
    -6) OPT_V4=0; OPT_V6=1 ;;
    -f|--full) OPT_FULL=1 ;;
    -j|--json) OPT_JSON=1 ;;
    --no-link) OPT_NO_LINK=1 ;;
    --dry-run) OPT_DRY_RUN=1 ;;
    --vps|--direct) OPT_MODE="vps" ;;
    --proxy) OPT_MODE="proxy" ;;
    -x) shift; OPT_PROXY="${1:-}" ;;
    --proxy-url=*) OPT_PROXY="${1#*=}" ;;
    --controller) shift; OPT_CONTROLLER="${1:-}" ;;
    --controller=*) OPT_CONTROLLER="${1#*=}" ;;
    --secret) shift; OPT_SECRET="${1:-}" ;;
    --secret=*) OPT_SECRET="${1#*=}" ;;
    -h|--help) usage ;;
    *) ;;
  esac
  shift
done

if [ "$OPT_DRY_RUN" -eq 1 ]; then
  cat <<EOF
========================================================================
G-ROUTE // --dry-run 零发包安全审计清单 (未发送任何网络请求)
========================================================================
[权限边界 · 4 个绝不]
  1. 绝不申请 root / sudo 提权
  2. 绝不读取磁盘配置文件 (~/.ssh、代理订阅、浏览器 Cookie、环境变量密钥)
  3. 绝不向任何服务器上传检测结果 (#r= 链接 100% 本地离线压缩编码)
  4. 绝不下载二进制文件或执行远程混淆代码

[将发起的只读 HTTPS GET/HEAD 请求]
  - https://myip.ipip.net                               (国内直连分流参照)
  - https://gspe1-ssl.ls.apple.com/pep/gcc              (Apple 第三方地域对照)
  - https://v4.ident.me/json / https://v6.ident.me/json (双栈出口 ASN，备选 ipify)
  - https://redirector.googlevideo.com/report_mapping   (YouTube GGC 边缘与 Google 实见 IP)
  - https://ipwho.is/<google_exit_ip>                   (仅当 Google 实见 IP ≠ 通用 IP 且非 WARP 时查询)
  - https://gemini.google.com/app                       (Gemini Boq 3 位国码)
  - https://notebooklm.google.com/                      (NotebookLM 1-RTT 301/302 头)
  - https://www.youtube.com/premium                     (YouTube 送中与半隐身判据)
  - https://play.google.com/                            (Google Play 归属国)
  - https://www.google.com/searchdomaincheck?format=domain (Search 域与 hkredirect)
  - https://www.google.com/search?q=curl&ie=UTF-8       (Search 验证码 / .com.hk 跳转)
  - https://policies.google.com/terms?hl=en             (Terms 条款辖区与 EEA 实体)

[当前会话配置]
  - IP 脱敏: $( [ "$OPT_FULL" -eq 1 ] && echo "关闭 (-f 完整显示)" || echo "开启 (默认 38.59.*.*)" )
  - 显式代理: ${OPT_PROXY:-无 (按系统默认路由/环境变量)}
  - 本地控制 API: ${OPT_CONTROLLER:-未开启 (纯黑盒模式；仅显式传 --controller 时只读查询 /connections)}
========================================================================
EOF
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  printf 'ERROR: curl is required.\n' >&2
  exit 1
fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RST='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_RED='\033[31m'
  C_GRN='\033[32m'
  C_YLW='\033[33m'
  C_CYN='\033[36m'
  BG_RED='\033[41;97;1m'
  BG_GRN='\033[42;97;1m'
  BG_YLW='\033[43;30;1m'
  BG_CYN='\033[46;30;1m'
else
  C_RST=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GRN=''; C_YLW=''; C_CYN=''
  BG_RED=''; BG_GRN=''; BG_YLW=''; BG_CYN=''
fi

step_msg() {
  if [ "$OPT_JSON" -eq 0 ] && [ -t 2 ]; then
    printf '\r\033[2K%b' "${C_DIM}[G-ROUTE] $1...${C_RST}" >&2
  fi
}

clear_step() {
  if [ "$OPT_JSON" -eq 0 ] && [ -t 2 ]; then
    printf '\r\033[2K' >&2
  fi
}

curl_cmd() {
  if [ -n "$OPT_PROXY" ]; then
    curl -sS --max-time 8 -A "$UA" -x "$OPT_PROXY" "$@" 2>/dev/null
  else
    curl -sS --max-time 8 -A "$UA" "$@" 2>/dev/null
  fi
}

json_esc() {
  printf '%s' "$1" | tr '\r\n\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

json_str() {
  printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

json_num() {
  printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" | head -n 1
}

mask_ip() {
  local raw="$1"
  if [ -z "$raw" ]; then printf ''; return; fi
  if [ "$OPT_FULL" -eq 1 ]; then printf '%s' "$raw"; return; fi
  case "$raw" in
    *:*) printf '%s' "$raw" | awk -F: '{printf "%s:%s:*:*", $1, $2}' ;;
    *.*.*.*) printf '%s' "$raw" | awk -F. '{printf "%s.%s.*.*", $1, $2}' ;;
    *) printf '%s' "$raw" ;;
  esac
}

is_warp_ip() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    2a09:bac*|104.28.*|104.29.*|172.71.*|162.158.*|8.29.*) return 0 ;;
    *) return 1 ;;
  esac
}

classify_kind() {
  local org_low ident_type raw_ip
  org_low=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  ident_type=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
  raw_ip="${3:-}"
  if is_warp_ip "$raw_ip" || printf '%s' "$org_low" | grep -qE 'cloudflare|warp'; then
    printf 'warp'
  elif printf '%s' "$org_low" | grep -qE 'amazon|aws|google cloud|microsoft|azure|digitalocean|vultr|choopa|hetzner|ovh|linode|oracle|alibaba|aliyun|tencent|kirino|misaka|xtom|dmit|bandwagon|racknerd|zenlayer|m247|datacamp|leaseweb|scaleway|contabo|upcloud|vps|cloud|datacenter|hosting'; then
    printf 'hosting'
  elif printf '%s' "$org_low" | grep -qE 'cox |comcast|xfinity|verizon|at&t|spectrum|charter|softbank|ntt|kddi|chunghwa|hinet|pccw|hkbn|singtel|starhub|vodafone|telekom|telecom|broadband|fiber|fibre|cable|mobile'; then
    printf 'isp'
  elif [ "$ident_type" = "hosting" ] || [ "$ident_type" = "isp" ] || [ "$ident_type" = "business" ]; then
    printf '%s' "$ident_type"
  else
    printf 'unknown'
  fi
}

kind_cn() {
  case "$1" in
    hosting) printf '云机房段' ;;
    isp) printf '运营商段' ;;
    warp) printf 'WARP 出站' ;;
    business) printf '商业网段' ;;
    *) printf '未归类段' ;;
  esac
}

resolve_first_ip() {
  local host="$1" ver="$2" ip=""
  if command -v getent >/dev/null 2>&1; then
    if [ "$ver" = "4" ]; then
      ip=$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1}')
    else
      ip=$(getent ahostsv6 "$host" 2>/dev/null | awk 'NR==1{print $1}')
    fi
  fi
  if [ -z "$ip" ] && command -v dig >/dev/null 2>&1; then
    if [ "$ver" = "4" ]; then
      ip=$(dig +short +time=2 +tries=1 A "$host" 2>/dev/null | grep -E '^[0-9]+\.' | head -n 1)
    else
      ip=$(dig +short +time=2 +tries=1 AAAA "$host" 2>/dev/null | grep ':' | head -n 1)
    fi
  fi
  printf '%s' "$ip"
}

check_dns_unlock() {
  local ver="$1" is_tun="$2" has_px="$3"
  if [ "$is_tun" -eq 1 ]; then printf 'tun'; return; fi
  if [ "$has_px" -eq 1 ]; then printf 'skip'; return; fi

  local resolved
  resolved=$(resolve_first_ip "gemini.google.com" "$ver")
  if [ -z "$resolved" ]; then printf 'skip'; return; fi

  case "$resolved" in
    10.*|127.*|192.168.*|198.18.*|198.19.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*|fc*|fd*|::1)
      printf 'viadns'; return ;;
  esac

  local canary="groute-nx-$$-$(date +%S).gemini.google.com"
  local canary_ip
  canary_ip=$(resolve_first_ip "$canary" "$ver")
  if [ -n "$canary_ip" ]; then printf 'viadns'; return; fi

  if [ "$ver" = "4" ]; then
    case "$resolved" in
      142.250.*|142.251.*|172.217.*|172.253.*|216.58.*|216.239.*|74.125.*|64.233.*|209.85.*|108.177.*|192.178.*|66.102.*|66.249.*|34.*|35.*)
        printf 'native' ;;
      *) printf 'viadns' ;;
    esac
  else
    case "$resolved" in
      2607:f8b0:*|2404:6800:*|2a00:1450:*|2800:3f0:*) printf 'native' ;;
      *) printf 'viadns' ;;
    esac
  fi
}

HAS_EXPLICIT_PROXY=0
if [ -n "$OPT_PROXY" ] || [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ] || [ -n "${ALL_PROXY:-}" ] || [ -n "${http_proxy:-}" ] || [ -n "${https_proxy:-}" ]; then
  HAS_EXPLICIT_PROXY=1
fi
DETECTED_TUN=0
OS_NAME=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')
NOW_TS=$(date -u +%s 2>/dev/null || echo 0)

step_msg "探测国内分流基线与 Apple 第三方对照"
CN_RAW=$(curl_cmd --max-time 4 'https://myip.ipip.net' || true)
CN_DIRECT=""
if printf '%s' "$CN_RAW" | grep -q '中国'; then
  if ! printf '%s' "$CN_RAW" | grep -qE '香港|澳门|台湾'; then
    CN_DIRECT="CN"
  fi
fi

APPLE_CC=$(curl_cmd -4 --max-time 5 'https://gspe1-ssl.ls.apple.com/pep/gcc' | tr -cd 'A-Za-z' | tr '[:lower:]' '[:upper:]' || true)
if [ "${#APPLE_CC}" -ne 2 ]; then APPLE_CC=""; fi

V4_OK=0; V4_IP=""; V4_GIP=""; V4_ASN=""; V4_ORG=""; V4_CC=""; V4_CITY=""; V4_KIND="unknown"
V4_GASN=""; V4_GORG=""; V4_GKIND=""
V4_GEM=""; V4_NLM=""; V4_YT=""; V4_YTG=""; V4_CDN=""; V4_CDNU=0; V4_PLAY=""; V4_SDOM=""; V4_SCAP=""; V4_TRM=""; V4_ENT=""; V4_DNS="skip"

V6_OK=0; V6_IP=""; V6_GIP=""; V6_ASN=""; V6_ORG=""; V6_CC=""; V6_CITY=""; V6_KIND="unknown"
V6_GASN=""; V6_GORG=""; V6_GKIND=""
V6_GEM=""; V6_NLM=""; V6_YT=""; V6_YTG=""; V6_CDN=""; V6_CDNU=0; V6_PLAY=""; V6_SDOM=""; V6_SCAP=""; V6_TRM=""; V6_ENT=""; V6_DNS="skip"

probe_stack() {
  local ver="$1"
  local sflag="-$ver"
  local ident_url="https://v${ver}.ident.me/json"

  step_msg "IPv${ver}: 探测出口身份与 YouTube GGC 边缘"
  local ident_raw raw_ip
  ident_raw=$(curl_cmd "$sflag" --max-time 6 "$ident_url" || true)
  raw_ip=$(json_str "$ident_raw" "ip")
  if [ -z "$raw_ip" ]; then
    local ipify_raw
    ipify_raw=$(curl_cmd "$sflag" --max-time 5 "https://api${ver}.ipify.org?format=json" || true)
    raw_ip=$(json_str "$ipify_raw" "ip")
  fi
  if [ -z "$raw_ip" ]; then return 1; fi

  local ip_masked asn org cc city itype kind
  ip_masked=$(mask_ip "$raw_ip")
  asn=$(json_num "$ident_raw" "asn")
  org=$(json_str "$ident_raw" "aso")
  cc=$(json_str "$ident_raw" "cc" | tr '[:lower:]' '[:upper:]')
  city=$(json_str "$ident_raw" "city")
  itype=$(json_str "$ident_raw" "type")
  kind=$(classify_kind "$org" "$itype" "$raw_ip")

  # 1. YouTube GGC CDN + Google-seen IP + dual-egress ASN lookup when gip != ip
  local rmap_line gip_raw gip_masked cdn cdnu gasn gorg gkind
  rmap_line=$(curl_cmd "$sflag" --max-time 6 'https://redirector.googlevideo.com/report_mapping' | grep '=>' | head -n 1 | tr -d '\r' || true)
  gip_raw=""; cdn=""; cdnu=0; gasn=""; gorg=""; gkind=""
  if [ -n "$rmap_line" ]; then
    gip_raw=$(printf '%s' "$rmap_line" | awk '{print $1}')
    cdn=$(printf '%s' "$rmap_line" | awk '{print $3}')
    if printf '%s' "$rmap_line" | grep -q '\[u\]'; then cdnu=1; fi
  fi
  gip_masked=$(mask_ip "$gip_raw")

  if [ -n "$gip_raw" ] && [ "$gip_raw" != "$raw_ip" ]; then
    if is_warp_ip "$gip_raw"; then
      gasn="13335"
      gorg="Cloudflare WARP"
      gkind="warp"
    else
      local gwho
      gwho=$(curl_cmd --max-time 4 "https://ipwho.is/${gip_raw}" || true)
      if [ -n "$gwho" ]; then
        gasn=$(json_num "$gwho" "asn")
        gorg=$(json_str "$gwho" "org")
        if [ -z "$gorg" ]; then gorg=$(json_str "$gwho" "isp"); fi
        gkind=$(classify_kind "$gorg" "" "$gip_raw")
      fi
    fi
  fi

  # 2. Gemini Boq + TUN Fake-IP detection
  step_msg "IPv${ver}: 探测 Gemini / NotebookLM"
  local tmp_gem gem_meta gem_cc
  tmp_gem=$(mktemp)
  gem_meta=$(curl_cmd "$sflag" -L --max-time 9 -o "$tmp_gem" -w 'IP=%{remote_ip}' 'https://gemini.google.com/app' || true)
  case "$gem_meta" in
    *IP=198.18.*|*IP=198.19.*|*IP=fc*|*IP=fd*) DETECTED_TUN=1 ;;
  esac
  gem_cc=$(grep -oE ',2,1,200,"[A-Z]{3}"' "$tmp_gem" 2>/dev/null | head -n 1 | grep -oE '[A-Z]{3}' || true)
  if [ -z "$gem_cc" ]; then
    gem_cc=$(grep -oE '"countryCode":"[A-Z]{2}"' "$tmp_gem" 2>/dev/null | head -n 1 | cut -d'"' -f4 || true)
  fi
  rm -f "$tmp_gem"

  # 3. NotebookLM 1-RTT header check
  local nlm_hdr nlm_loc nlm_status
  nlm_hdr=$(curl_cmd "$sflag" --max-time 7 -I 'https://notebooklm.google.com/' || true)
  nlm_loc=$(printf '%s\n' "$nlm_hdr" | grep -i '^location:' | head -n 1 | tr -d '\r' || true)
  if printf '%s' "$nlm_loc" | grep -qi 'location=unsupported'; then
    nlm_status="unavail"
  elif printf '%s' "$nlm_loc" | grep -qiE 'notebook\.google\.com|accounts\.google\.com' || printf '%s\n' "$nlm_hdr" | head -n 1 | grep -qE ' 200| 301| 302'; then
    nlm_status="ok"
  else
    nlm_status="err"
  fi

  # 4. YouTube Premium strict 3-tier
  step_msg "IPv${ver}: 探测 YouTube Premium 与 Google Play"
  local yt_html yt_status yt_gl
  yt_html=$(curl_cmd "$sflag" -L --max-time 9 -H 'Accept-Language: en-US,en;q=0.9' -H "Cookie: $SOCS_COOKIE" 'https://www.youtube.com/premium' || true)
  yt_gl=""
  if [ -z "$yt_html" ]; then
    yt_status="err"
  else
    yt_gl=$(printf '%s' "$yt_html" | grep -oE '"contentRegion":"[A-Z]{2}"' | head -n 1 | cut -d'"' -f4 || true)
    if [ -z "$yt_gl" ]; then
      yt_gl=$(printf '%s' "$yt_html" | grep -oE '"INNERTUBE_CONTEXT_GL":"[A-Z]{2}"' | head -n 1 | cut -d'"' -f4 || true)
    fi
    if printf '%s' "$yt_html" | grep -q 'www.google.cn'; then yt_status="cn"
    elif printf '%s' "$yt_html" | grep -qi 'Premium is not available in your country'; then yt_status="noprem"
    elif printf '%s' "$yt_html" | grep -qi 'ad-free'; then yt_status="ok"
    else yt_status="err"; fi
  fi

  # 5. Google Play Store
  local play_html play_cc
  play_html=$(curl_cmd "$sflag" -L --max-time 9 -H 'Accept-Language: en-US,en;q=0.9' 'https://play.google.com/' || true)
  play_cc=$(printf '%s' "$play_html" | grep -oE '<div class="yVZQTb">[^<(]+' | head -n 1 | sed -e 's/<div class="yVZQTb">//' -e 's/[[:space:]]*$//' || true)

  # 6. Google Search + Terms (pure POSIX, no perl)
  step_msg "IPv${ver}: 探测 Google Search 与 Terms 辖区"
  local sdom_raw sdom
  sdom_raw=$(curl_cmd "$sflag" --max-time 7 'https://www.google.com/searchdomaincheck?format=domain' || true)
  if printf '%s' "$sdom_raw" | grep -qi 'hkredirect'; then
    sdom="hkredirect"
  else
    sdom=$(printf '%s\n' "$sdom_raw" | head -n 1 | tr -d '\r\n ' || true)
    case "$sdom" in .google.*) ;; *) sdom="" ;; esac
  fi

  local sr_raw sr_meta sr_code sr_url scap
  sr_raw=$(curl_cmd "$sflag" -L --max-time 9 \
    -H 'Accept-Language: en-US,en;q=0.9' \
    -H 'Sec-Fetch-Dest: document' \
    -H 'Sec-Fetch-Mode: navigate' \
    -H 'Sec-Fetch-Site: none' \
    -w '\n__CODE__%{http_code}__URL__%{url_effective}' \
    'https://www.google.com/search?q=curl&ie=UTF-8' || true)
  sr_meta=$(printf '%s\n' "$sr_raw" | tail -n 1)
  sr_code=$(printf '%s' "$sr_meta" | sed -n 's/.*__CODE__\([0-9]*\)__URL__.*/\1/p')
  sr_url=$(printf '%s' "$sr_meta" | sed -n 's/.*__URL__//p')
  if [ -z "$sr_code" ] || [ "$sr_code" = "000" ]; then scap="err"
  elif [ "$sr_code" = "429" ] || printf '%s' "$sr_raw" | grep -qiE 'unusual traffic from|is blocked|unaddressed abuse|/sorry/'; then scap="captcha"
  elif printf '%s' "$sr_url" | grep -qiE 'google\.com\.hk|google\.cn'; then scap="hk"
  else scap="ok"; fi

  local trm_html trm_cv trm_ent
  trm_html=$(curl_cmd "$sflag" -L --max-time 9 'https://policies.google.com/terms?hl=en' || true)
  trm_cv=$(printf '%s' "$trm_html" | grep -oE 'Country version:?</[^>]+>[[:space:]]*[A-Za-z][^<]{1,42}' | head -n 1 | sed -E 's/^[^>]+>[[:space:]]*//; s/[[:space:]]+$//' || true)
  if [ -z "$trm_cv" ]; then
    trm_cv=$(printf '%s' "$trm_html" | grep -oE 'Country version:[[:space:]]*[A-Za-z][A-Za-z ,.&'\''-]{1,40}' | head -n 1 | sed -E 's/^Country version:[[:space:]]*//; s/[[:space:]]+$//' || true)
  fi
  trm_ent=$(printf '%s' "$trm_html" | grep -oE 'Google Ireland Limited|Google LLC|Google Asia Pacific|Google Commerce Limited' | head -n 1 || true)

  local dns_mode
  dns_mode=$(check_dns_unlock "$ver" "$DETECTED_TUN" "$HAS_EXPLICIT_PROXY")

  if [ "$ver" = "4" ]; then
    V4_OK=1; V4_IP="$ip_masked"; V4_GIP="$gip_masked"; V4_ASN="$asn"; V4_ORG="$org"; V4_CC="$cc"; V4_CITY="$city"; V4_KIND="$kind"
    V4_GASN="$gasn"; V4_GORG="$gorg"; V4_GKIND="$gkind"
    V4_GEM="$gem_cc"; V4_NLM="$nlm_status"; V4_YT="$yt_status"; V4_YTG="$yt_gl"; V4_CDN="$cdn"; V4_CDNU="$cdnu"
    V4_PLAY="$play_cc"; V4_SDOM="$sdom"; V4_SCAP="$scap"; V4_TRM="$trm_cv"; V4_ENT="$trm_ent"; V4_DNS="$dns_mode"
  else
    V6_OK=1; V6_IP="$ip_masked"; V6_GIP="$gip_masked"; V6_ASN="$asn"; V6_ORG="$org"; V6_CC="$cc"; V6_CITY="$city"; V6_KIND="$kind"
    V6_GASN="$gasn"; V6_GORG="$gorg"; V6_GKIND="$gkind"
    V6_GEM="$gem_cc"; V6_NLM="$nlm_status"; V6_YT="$yt_status"; V6_YTG="$yt_gl"; V6_CDN="$cdn"; V6_CDNU="$cdnu"
    V6_PLAY="$play_cc"; V6_SDOM="$sdom"; V6_SCAP="$scap"; V6_TRM="$trm_cv"; V6_ENT="$trm_ent"; V6_DNS="$dns_mode"
  fi
  return 0
}

if [ "$OPT_V4" -eq 1 ]; then probe_stack 4 || true; fi
if [ "$OPT_V6" -eq 1 ]; then probe_stack 6 || true; fi
clear_step

if [ "$V4_OK" -eq 0 ] && [ "$V6_OK" -eq 0 ]; then
  printf 'ERROR: IPv4 与 IPv6 均未能获取出口信息，请检查网络或代理参数 (-x)。\n' >&2
  exit 1
fi

if [ -n "$OPT_MODE" ]; then
  RUN_MODE="$OPT_MODE"
elif [ "$DETECTED_TUN" -eq 1 ] || [ "$HAS_EXPLICIT_PROXY" -eq 1 ] || [ -n "$CN_DIRECT" ]; then
  RUN_MODE="proxy"
else
  RUN_MODE="vps"
fi

build_stack_json() {
  local ip="$1" gip="$2" asn="$3" org="$4" cc="$5" city="$6" kind="$7"
  local gasn="$8" gorg="$9" gkind="${10}"
  local gem="${11}" nlm="${12}" yt="${13}" ytg="${14}" cdn="${15}" cdnu="${16}"
  local play="${17}" sdom="${18}" scap="${19}" trm="${20}" ent="${21}" dns="${22}"
  local out="{" sep=""
  add_s() { if [ -n "$2" ]; then out="${out}${sep}\"$1\":\"$(json_esc "$2")\""; sep=","; fi; }
  add_n() { if [ -n "$2" ]; then out="${out}${sep}\"$1\":$2"; sep=","; fi; }
  add_b() { if [ "$2" -eq 1 ]; then out="${out}${sep}\"$1\":true"; sep=","; fi; }
  add_s ip "$ip"; add_s gip "$gip"; add_n asn "$asn"; add_s org "$org"; add_s cc "$cc"; add_s city "$city"; add_s kind "$kind"
  add_n gasn "$gasn"; add_s gorg "$gorg"; add_s gkind "$gkind"
  add_s gem "$gem"; add_s nlm "$nlm"; add_s yt "$yt"; add_s ytg "$ytg"; add_s cdn "$cdn"; add_b cdnu "$cdnu"
  add_s play "$play"; add_s sdom "$sdom"; add_s scap "$scap"; add_s trm "$trm"; add_s ent "$ent"; add_s dns "$dns"
  printf '%s}' "$out"
}

JSON="{\"v\":1,\"t\":${NOW_TS},\"m\":\"${RUN_MODE}\""
if [ -n "$OS_NAME" ]; then JSON="${JSON},\"os\":\"$(json_esc "$OS_NAME")\""; fi
if [ "$DETECTED_TUN" -eq 1 ]; then JSON="${JSON},\"tun\":true"; fi
if [ "$HAS_EXPLICIT_PROXY" -eq 1 ]; then JSON="${JSON},\"px\":true"; fi
if [ -n "$CN_DIRECT" ]; then JSON="${JSON},\"cn\":\"${CN_DIRECT}\""; fi
if [ -n "$APPLE_CC" ]; then JSON="${JSON},\"ap\":\"${APPLE_CC}\""; fi
if [ "$V4_OK" -eq 1 ]; then
  V4_JSON=$(build_stack_json "$V4_IP" "$V4_GIP" "$V4_ASN" "$V4_ORG" "$V4_CC" "$V4_CITY" "$V4_KIND" "$V4_GASN" "$V4_GORG" "$V4_GKIND" "$V4_GEM" "$V4_NLM" "$V4_YT" "$V4_YTG" "$V4_CDN" "$V4_CDNU" "$V4_PLAY" "$V4_SDOM" "$V4_SCAP" "$V4_TRM" "$V4_ENT" "$V4_DNS")
  JSON="${JSON},\"v4\":${V4_JSON}"
fi
if [ "$V6_OK" -eq 1 ]; then
  V6_JSON=$(build_stack_json "$V6_IP" "$V6_GIP" "$V6_ASN" "$V6_ORG" "$V6_CC" "$V6_CITY" "$V6_KIND" "$V6_GASN" "$V6_GORG" "$V6_GKIND" "$V6_GEM" "$V6_NLM" "$V6_YT" "$V6_YTG" "$V6_CDN" "$V6_CDNU" "$V6_PLAY" "$V6_SDOM" "$V6_SCAP" "$V6_TRM" "$V6_ENT" "$V6_DNS")
  JSON="${JSON},\"v6\":${V6_JSON}"
fi
JSON="${JSON}}"

if [ "$OPT_JSON" -eq 1 ]; then
  printf '%s\n' "$JSON"
  exit 0
fi

encode_payload() {
  if command -v gzip >/dev/null 2>&1; then
    printf 'z:%s' "$(printf '%s' "$JSON" | gzip -c -9 | base64 | tr -d '\r\n' | tr '+/' '-_' | tr -d '=')"
  else
    printf 'p:%s' "$(printf '%s' "$JSON" | base64 | tr -d '\r\n' | tr '+/' '-_' | tr -d '=')"
  fi
}

is_cn_or_restricted() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    chn|cn|china|hkg|hk|"hong kong"|mac|mo|macau|rus|ru|russia|blr|by|belarus) return 0 ;;
    *) return 1 ;;
  esac
}

stack_has_drift() {
  local gem="$1" nlm="$2" yt="$3" play="$4" sdom="$5" scap="$6" trm="$7"
  local hits=0
  if is_cn_or_restricted "$gem"; then hits=$((hits + 2)); fi
  if [ "$nlm" = "unavail" ]; then hits=$((hits + 2)); fi
  if [ "$yt" = "cn" ]; then hits=$((hits + 2)); fi
  if [ "$yt" = "noprem" ]; then hits=$((hits + 1)); fi
  if is_cn_or_restricted "$play"; then hits=$((hits + 1)); fi
  if is_cn_or_restricted "$trm"; then hits=$((hits + 1)); fi
  if [ "$sdom" = "hkredirect" ] || [ "$scap" = "hk" ]; then hits=$((hits + 1)); fi
  [ "$hits" -ge 2 ]
}

D4=0; D6=0
if [ "$V4_OK" -eq 1 ] && stack_has_drift "$V4_GEM" "$V4_NLM" "$V4_YT" "$V4_PLAY" "$V4_SDOM" "$V4_SCAP" "$V4_TRM"; then D4=1; fi
if [ "$V6_OK" -eq 1 ] && stack_has_drift "$V6_GEM" "$V6_NLM" "$V6_YT" "$V6_PLAY" "$V6_SDOM" "$V6_SCAP" "$V6_TRM"; then D6=1; fi

P_IP="$V4_IP"; P_GIP="$V4_GIP"; P_ASN="$V4_ASN"; P_ORG="$V4_ORG"; P_CC="$V4_CC"; P_KIND="$V4_KIND"
P_GASN="$V4_GASN"; P_GORG="$V4_GORG"; P_GKIND="$V4_GKIND"; P_GEM="$V4_GEM"; P_DNS="$V4_DNS"
if [ "$V4_OK" -eq 0 ]; then
  P_IP="$V6_IP"; P_GIP="$V6_GIP"; P_ASN="$V6_ASN"; P_ORG="$V6_ORG"; P_CC="$V6_CC"; P_KIND="$V6_KIND"
  P_GASN="$V6_GASN"; P_GORG="$V6_GORG"; P_GKIND="$V6_GKIND"; P_GEM="$V6_GEM"; P_DNS="$V6_DNS"
fi

SPLIT_HIT=0
if [ -n "$P_IP" ] && [ -n "$P_GIP" ] && [ "$P_IP" != "$P_GIP" ]; then SPLIT_HIT=1; fi

EFF_KIND="$P_KIND"
if [ "$SPLIT_HIT" -eq 1 ] && [ -n "$P_GKIND" ]; then EFF_KIND="$P_GKIND"; fi

VERDICT_BADGE="${BG_GRN} CLEAN ${C_RST}"
VERDICT_TEXT="Google 全家桶全绿可用"
if [ "$EFF_KIND" = "hosting" ]; then
  VERDICT_TEXT="云机房出口全绿可用 · 实测无送中无验证码 (反焦虑认证)"
fi

if [ "$V4_OK" -eq 1 ] && [ "$V6_OK" -eq 1 ] && { [ "$D4" -ne "$D6" ] || [ "$V4_GEM" != "$V6_GEM" ]; }; then
  VERDICT_BADGE="${BG_YLW} STACK_SPLIT ${C_RST}"
  VERDICT_TEXT="双栈不对称: IPv4(${V4_GEM:-?}) vs IPv6(${V6_GEM:-?})，建议关闭冲突栈"
elif [ "$D4" -eq 1 ] || [ "$D6" -eq 1 ]; then
  VERDICT_BADGE="${BG_RED} CN_DRIFT ${C_RST}"
  if [ -n "$P_CC" ] && ! is_cn_or_restricted "$P_CC"; then
    VERDICT_TEXT="实锤 Google 私有库送中 (公开库 ${P_CC} / Apple ${APPLE_CC:-?}，但 Google 判受限)"
  else
    VERDICT_TEXT="Google 生态判定为受限地区 / 送中"
  fi
elif [ "$V4_SCAP" = "captcha" ] || [ "$V6_SCAP" = "captcha" ]; then
  VERDICT_BADGE="${BG_YLW} PARTIAL ${C_RST}"
  VERDICT_TEXT="AI 核心可用，但 Google Search 触发 /sorry/ 人机验证"
elif [ "$SPLIT_HIT" -eq 1 ]; then
  VERDICT_BADGE="${BG_CYN} SPLIT_ROUTE ${C_RST}"
  if [ -n "$P_GORG" ]; then
    VERDICT_TEXT="跨组分流生效 · Google 经 ${P_GORG} ($(kind_cn "$P_GKIND")) 干净可用"
  else
    VERDICT_TEXT="跨组分流生效 · 通用海外 (${P_IP}) 与 Google (${P_GIP}) 已拆分且可用"
  fi
fi

fmt_cell_gem() {
  if [ -z "$1" ]; then printf "${C_DIM}%-22s${C_RST}" "N/A"; return; fi
  if is_cn_or_restricted "$1"; then printf "${C_RED}%-22s${C_RST}" "BLOCKED [$1]"; else printf "${C_GRN}%-22s${C_RST}" "OK [$1]"; fi
}
fmt_cell_nlm() {
  case "$1" in
    ok) printf "${C_GRN}%-22s${C_RST}" "OK (301)" ;;
    unavail) printf "${C_RED}%-22s${C_RST}" "BLOCKED (302 unavail)" ;;
    *) printf "${C_DIM}%-22s${C_RST}" "N/A" ;;
  esac
}
fmt_cell_yt() {
  case "$1" in
    ok) printf "${C_GRN}%-22s${C_RST}" "OK [${2:-OK}]" ;;
    cn) printf "${C_RED}%-22s${C_RST}" "CN_DRIFT (google.cn)" ;;
    noprem) printf "${C_RED}%-22s${C_RST}" "NO_PREM (GL=${2:-?})" ;;
    *) printf "${C_DIM}%-22s${C_RST}" "N/A" ;;
  esac
}
fmt_cell_cdn() {
  local c="$1" u="$2" ip="$3" gip="$4"
  if [ -z "$c" ]; then printf "${C_DIM}%-22s${C_RST}" "N/A"; return; fi
  local tag="$c"
  if [ "$u" -eq 1 ]; then tag="${tag} [u]"; fi
  if [ -n "$ip" ] && [ -n "$gip" ] && [ "$ip" != "$gip" ]; then
    printf "${C_YLW}%-22s${C_RST}" "${tag} (Split)"
  else
    printf "${C_CYN}%-22s${C_RST}" "$tag"
  fi
}
fmt_cell_country() {
  if [ -z "$1" ]; then printf "${C_DIM}%-22s${C_RST}" "N/A"; return; fi
  if is_cn_or_restricted "$1"; then printf "${C_RED}%-22s${C_RST}" "$1 [CN]"; else printf "${C_GRN}%-22s${C_RST}" "$1"; fi
}
fmt_cell_search() {
  local sd="$1" sc="$2"
  if [ "$sc" = "captcha" ]; then printf "${C_YLW}%-22s${C_RST}" "CAPTCHA (/sorry)"
  elif [ "$sd" = "hkredirect" ] || [ "$sc" = "hk" ]; then printf "${C_RED}%-22s${C_RST}" "HK_REDIRECT (.com.hk)"
  elif [ -n "$sd" ] || [ "$sc" = "ok" ]; then printf "${C_GRN}%-22s${C_RST}" "${sd:-OK} (Clean)"
  else printf "${C_DIM}%-22s${C_RST}" "N/A"; fi
}
fmt_cell_terms() {
  local cv="$1" ent="$2"
  if [ -z "$cv" ]; then printf "${C_DIM}%-22s${C_RST}" "N/A"; return; fi
  if is_cn_or_restricted "$cv"; then printf "${C_RED}%-22s${C_RST}" "$cv [CN]"
  elif [ "$ent" = "Google Ireland Limited" ]; then printf "${C_YLW}%-22s${C_RST}" "$cv (EEA)"
  else printf "${C_GRN}%-22s${C_RST}" "$cv"; fi
}

UTC_TIME=$(date -u +"%Y-%m-%d %H:%M UTC" 2>/dev/null || echo "")
MODE_LABEL="直连出站"
if [ "$RUN_MODE" = "proxy" ]; then
  if [ "$DETECTED_TUN" -eq 1 ]; then MODE_LABEL="代理/分流·TUN"; else MODE_LABEL="代理/分流出站"; fi
elif [ "$SPLIT_HIT" -eq 1 ]; then
  MODE_LABEL="直连主机·出站分流"
fi
DNS_TAG=""
case "$P_DNS" in
  native) DNS_TAG="Native" ;;
  viadns) DNS_TAG="ViaDNS" ;;
  tun) DNS_TAG="TUN/Fake-IP" ;;
  *) DNS_TAG="--" ;;
esac

LINE="========================================================================"
DASH="------------------------------------------------------------------------"

printf '%s\n' "$LINE"
printf "${C_BOLD}G-ROUTE // Google 生态送中与分流体检卡${C_RST}   [%s] %s\n" "$MODE_LABEL" "$UTC_TIME"
printf '%s\n' "$LINE"
printf '结论: %b %s\n' "$VERDICT_BADGE" "$VERDICT_TEXT"
printf '通用出口: %s | AS%s %s [%s] (%s)\n' "${P_IP:-N/A}" "${P_ASN:-?}" "${P_ORG:-Unknown}" "$(kind_cn "$P_KIND")" "$DNS_TAG"
if [ "$SPLIT_HIT" -eq 1 ]; then
  printf "${C_YLW}Google出口: %s | AS%s %s [%s]${C_RST}\n" "$P_GIP" "${P_GASN:-?}" "${P_GORG:-独立分流出口}" "$(kind_cn "${P_GKIND:-unknown}")"
fi
printf '三方对照: 公开库=%s  |  Apple=%s  |  Google 实测=%s\n' "${P_CC:-?}" "${APPLE_CC:-?}" "${P_GEM:-?}"
printf '%s\n' "$DASH"

if [ "$V4_OK" -eq 1 ] && [ "$V6_OK" -eq 1 ]; then
  printf "${C_BOLD}服务维度             %-22s %-22s${C_RST}\n" "IPv4 (${V4_IP})" "IPv6 (${V6_IP})"
  printf '%s\n' "$DASH"
  printf '%-20s ' "Gemini (Boq)";       fmt_cell_gem "$V4_GEM"; printf ' '; fmt_cell_gem "$V6_GEM"; printf '\n'
  printf '%-20s ' "NotebookLM (1-RTT)"; fmt_cell_nlm "$V4_NLM"; printf ' '; fmt_cell_nlm "$V6_NLM"; printf '\n'
  printf '%-20s ' "YouTube Premium";    fmt_cell_yt "$V4_YT" "$V4_YTG"; printf ' '; fmt_cell_yt "$V6_YT" "$V6_YTG"; printf '\n'
  printf '%-20s ' "YouTube GGC CDN";    fmt_cell_cdn "$V4_CDN" "$V4_CDNU" "$V4_IP" "$V4_GIP"; printf ' '; fmt_cell_cdn "$V6_CDN" "$V6_CDNU" "$V6_IP" "$V6_GIP"; printf '\n'
  printf '%-20s ' "Google Play";        fmt_cell_country "$V4_PLAY"; printf ' '; fmt_cell_country "$V6_PLAY"; printf '\n'
  printf '%-20s ' "Google Search";      fmt_cell_search "$V4_SDOM" "$V4_SCAP"; printf ' '; fmt_cell_search "$V6_SDOM" "$V6_SCAP"; printf '\n'
  printf '%-20s ' "Google Terms";       fmt_cell_terms "$V4_TRM" "$V4_ENT"; printf ' '; fmt_cell_terms "$V6_TRM" "$V6_ENT"; printf '\n'
elif [ "$V4_OK" -eq 1 ]; then
  printf "${C_BOLD}服务维度               IPv4 检测结果               补充说明${C_RST}\n"
  printf '%s\n' "$DASH"
  printf '%-22s ' "Gemini (Boq)";       fmt_cell_gem "$V4_GEM"; printf '     %s\n' "gemini.google.com/app"
  printf '%-22s ' "NotebookLM (1-RTT)"; fmt_cell_nlm "$V4_NLM"; printf '     %s\n' "301=支持 / 302=封锁"
  printf '%-22s ' "YouTube Premium";    fmt_cell_yt "$V4_YT" "$V4_YTG"; printf '     %s\n' "含半隐身送中判据"
  printf '%-22s ' "YouTube GGC CDN";    fmt_cell_cdn "$V4_CDN" "$V4_CDNU" "$V4_IP" "$V4_GIP"; printf '     %s\n' "Google 实见 ${V4_GIP:-?}"
  printf '%-22s ' "Google Play";        fmt_cell_country "$V4_PLAY"; printf '     %s\n' "play.google.com"
  printf '%-22s ' "Google Search";      fmt_cell_search "$V4_SDOM" "$V4_SCAP"; printf '     %s\n' "域检查 + /sorry 实测"
  printf '%-22s ' "Google Terms";       fmt_cell_terms "$V4_TRM" "$V4_ENT"; printf '     %s\n' "${V4_ENT:-?}"
else
  printf "${C_BOLD}服务维度               IPv6 检测结果               补充说明${C_RST}\n"
  printf '%s\n' "$DASH"
  printf '%-22s ' "Gemini (Boq)";       fmt_cell_gem "$V6_GEM"; printf '     %s\n' "gemini.google.com/app"
  printf '%-22s ' "NotebookLM (1-RTT)"; fmt_cell_nlm "$V6_NLM"; printf '     %s\n' "301=支持 / 302=封锁"
  printf '%-22s ' "YouTube Premium";    fmt_cell_yt "$V6_YT" "$V6_YTG"; printf '     %s\n' "含半隐身送中判据"
  printf '%-22s ' "YouTube GGC CDN";    fmt_cell_cdn "$V6_CDN" "$V6_CDNU" "$V6_IP" "$V6_GIP"; printf '     %s\n' "Google 实见 ${V6_GIP:-?}"
  printf '%-22s ' "Google Play";        fmt_cell_country "$V6_PLAY"; printf '     %s\n' "play.google.com"
  printf '%-22s ' "Google Search";      fmt_cell_search "$V6_SDOM" "$V6_SCAP"; printf '     %s\n' "域检查 + /sorry 实测"
  printf '%-22s ' "Google Terms";       fmt_cell_terms "$V6_TRM" "$V6_ENT"; printf '     %s\n' "${V6_ENT:-?}"
fi

# Optional Opt-In Local Proxy Controller API (strictly read-only, strictly local display, NEVER in #r=)
# Supports HTTP (http://127.0.0.1:9090) AND Unix domain socket (/tmp/verge/verge-mihomo.sock)
if [ -n "$OPT_CONTROLLER" ]; then
  CTRL_BASE="${OPT_CONTROLLER%/}"
  printf '%s\n' "$DASH"
  printf "${C_CYN}[本地只读控制 API · 仅本屏展示，绝不写入 #r= 分享链]${C_RST}\n"
  PIDS=""
  for target in "https://v4.ident.me/json" "https://www.google.com/search?q=curl&ie=UTF-8" "https://gemini.google.com/app" "https://aistudio.google.com/" "https://notebooklm.google.com/" "https://www.youtube.com/premium" "https://redirector.googlevideo.com/report_mapping" "https://play.google.com/"; do
    curl_cmd --max-time 4 --limit-rate 50 -o /dev/null "$target" >/dev/null 2>&1 &
    PIDS="$PIDS $!"
  done
  sleep 1
  CTRL_URL="${CTRL_BASE}/connections"
  UNIX_SOCK=""
  case "$CTRL_BASE" in
    /*) UNIX_SOCK="$CTRL_BASE"; CTRL_URL="http://localhost/connections" ;;
    unix:*) UNIX_SOCK="${CTRL_BASE#unix:}"; CTRL_URL="http://localhost/connections" ;;
  esac
  if [ -n "$UNIX_SOCK" ]; then
    if [ -n "$OPT_SECRET" ]; then
      CTRL_RAW=$(curl -sS --unix-socket "$UNIX_SOCK" --max-time 3 -H "Authorization: Bearer ${OPT_SECRET}" -w '\n__HTTP__%{http_code}' "$CTRL_URL" 2>/dev/null || true)
    else
      CTRL_RAW=$(curl -sS --unix-socket "$UNIX_SOCK" --max-time 3 -w '\n__HTTP__%{http_code}' "$CTRL_URL" 2>/dev/null || true)
    fi
  else
    if [ -n "$OPT_SECRET" ]; then
      CTRL_RAW=$(curl -sS --noproxy '*' --max-time 3 -H "Authorization: Bearer ${OPT_SECRET}" -w '\n__HTTP__%{http_code}' "$CTRL_URL" 2>/dev/null || true)
    else
      CTRL_RAW=$(curl -sS --noproxy '*' --max-time 3 -w '\n__HTTP__%{http_code}' "$CTRL_URL" 2>/dev/null || true)
    fi
  fi
  for pid in $PIDS; do kill "$pid" >/dev/null 2>&1 || true; done
  wait >/dev/null 2>&1 || true

  CTRL_CODE=$(printf '%s\n' "$CTRL_RAW" | tail -n 1 | sed -n 's/.*__HTTP__\([0-9]*\).*/\1/p')
  CTRL_JSON=$(printf '%s\n' "$CTRL_RAW" | sed '$d')

  if [ "$CTRL_CODE" = "401" ] || [ "$CTRL_CODE" = "403" ]; then
    printf "${C_YLW}[INFO] 控制端 %s 已连通，但返回 HTTP %s（需要密钥）；请补充 --secret 或 G_ROUTE_SECRET。${C_RST}\n" "$CTRL_BASE" "$CTRL_CODE"
  elif [ "$CTRL_CODE" = "200" ] && printf '%s' "$CTRL_JSON" | grep -q '"connections"'; then
    printf "${C_BOLD}%-28s %-28s %s${C_RST}\n" "探测域名" "命中规则" "策略链 (节点 <- 组)"
    for dom in "v4.ident.me" "www.google.com" "gemini.google.com" "aistudio.google.com" "notebooklm.google.com" "www.youtube.com" "redirector.googlevideo.com" "play.google.com"; do
      chunk=$(printf '%s' "$CTRL_JSON" | sed 's/{"id":/\n{"id":/g' | grep "\"${dom}\"" | tail -n 1 || true)
      if [ -n "$chunk" ]; then
        r_type=$(printf '%s' "$chunk" | sed -n 's/.*"rule":"\([^"]*\)".*/\1/p')
        r_pay=$(printf '%s' "$chunk" | sed -n 's/.*"rulePayload":"\([^"]*\)".*/\1/p')
        chains=$(printf '%s' "$chunk" | sed -n 's/.*"chains":\[\([^]]*\)\].*/\1/p' | tr -d '"' | sed 's/,/ <- /g')
        r_lbl="${r_type:-?}"
        if [ -n "$r_pay" ]; then r_lbl="${r_lbl}(${r_pay})"; fi
        printf '%-28s %-28s %s\n' "$dom" "$r_lbl" "${chains:-?}"
      else
        printf "${C_DIM}%-28s %-28s %s${C_RST}\n" "$dom" "(未在活跃连接捕获)" "--"
      fi
    done
  else
    printf "${C_YLW}[INFO] 无法连接 %s（HTTP=%s）：macOS/Linux Verge 可传 /tmp/verge/verge-mihomo.sock，或传 http://127.0.0.1:9090。${C_RST}\n" "$CTRL_BASE" "${CTRL_CODE:-000}"
  fi
fi

printf '%s\n' "$LINE"

if [ "$OPT_NO_LINK" -eq 0 ]; then
  PAYLOAD=$(encode_payload)
  case "$G_ROUTE_ORIGIN" in
    http://*|https://*)
      printf "${C_CYN}Web 体检卡 & PNG 导出:${C_RST}\n%s/#r=%s\n" "$G_ROUTE_ORIGIN" "$PAYLOAD"
      ;;
    *)
      printf "${C_CYN}离线报告码 (粘贴到 G-ROUTE 网页渲染体检卡 / 导出 PNG):${C_RST}\nG1:%s\n" "$PAYLOAD"
      ;;
  esac
fi
printf "${C_DIM}注: 100%% 本地探测并离线编码，IP 已默认脱敏(-f 显示完整)，未向任何服务器上传数据。${C_RST}\n"
