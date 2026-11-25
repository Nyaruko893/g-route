#!/usr/bin/env bash
# G-ROUTE v3 // Google 生态送中与全链路分流体检仪 (Linux / macOS / VPS)
# 权限契约: 零提权(不需 sudo) · 零读磁盘配置/订阅/SSH · 零数据上传 · 零二进制下载
# 零第三方依赖 (仅需 bash + curl + POSIX awk/sed/grep/base64; 可选 gzip)
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
OPT_QUICK=0
OPT_INSPECT=0
OPT_SVG=0
OPT_SVG_PATH=""
OPT_THEME="light"
OPT_WITH_RULES=0
OPT_ASCII=0
OPT_COMPACT=0
OPT_NO_MENU=0
OPT_PROXY=""
OPT_MODE=""
OPT_CONTROLLER="${G_ROUTE_CONTROLLER:-}"
OPT_SECRET="${G_ROUTE_SECRET:-}"
if [ "${G_ROUTE_INSPECT:-0}" = "1" ]; then OPT_INSPECT=1; fi

HAS_EXPLICIT_FLAGS=0
if [ $# -gt 0 ] || [ -n "$OPT_CONTROLLER" ] || [ "$OPT_INSPECT" -eq 1 ]; then
  HAS_EXPLICIT_FLAGS=1
fi

usage() {
  cat <<'EOF'
G-ROUTE v3 // Google 生态送中与全链路分流体检仪 (CLI)
用法:
  bash <(curl -sL https://<origin>/sh) [选项]

选项:
  --quick                  跳过交互菜单，直接执行极速纯黑盒体检
  --inspect                白名单自动发现本机 Clash/Mihomo/sing-box 控制口 (仅本屏只读，绝不入分享链)
  --controller <url|sock>  显式指定本地控制 API (如 http://127.0.0.1:9090 或 /tmp/verge/verge-mihomo.sock)
  --secret <token>         配合 --inspect / --controller 使用的控制 API 密钥
  --svg [path]             本地 100% 离线生成高清矢量 SVG 体检卡 (不依赖网页)
  --theme <light|dark>     SVG 配色主题 (默认 light)
  --with-rules             允许将本机策略链写入本地 SVG 个人存档 (默认严格隐藏)
  --ascii                  使用纯 ASCII 框线 (兼容老旧终端)
  --compact                64 列窄屏紧凑卡片 (适配手机 SSH 截图)
  --no-menu                关闭启动前与结束后的交互菜单
  -4 / -6                  仅检测 IPv4 / 仅检测 IPv6
  -x <proxy_url>           显式指定代理 (http:// / https:// / socks5://)
  -f, --full               显示完整 IP (默认自动脱敏如 38.59.*.*)
  -j, --json               仅输出紧凑 JSON (CliReportV1)
  --no-link                不输出底部离线 #r= 链接
  --dry-run                零发包安全审计模式: 打印全部只读 URL 与权限边界后退出
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
    -j|--json) OPT_JSON=1; OPT_NO_MENU=1 ;;
    --no-link) OPT_NO_LINK=1 ;;
    --dry-run) OPT_DRY_RUN=1 ;;
    --quick) OPT_QUICK=1 ;;
    --inspect) OPT_INSPECT=1 ;;
    --with-rules) OPT_WITH_RULES=1 ;;
    --ascii) OPT_ASCII=1 ;;
    --compact) OPT_COMPACT=1 ;;
    --no-menu) OPT_NO_MENU=1 ;;
    --vps|--direct) OPT_MODE="vps" ;;
    --proxy) OPT_MODE="proxy" ;;
    --svg)
      OPT_SVG=1
      if [ $# -ge 2 ]; then
        case "${2:-}" in
          -*) ;;
          *) shift; OPT_SVG_PATH="$1" ;;
        esac
      fi
      ;;
    --svg=*) OPT_SVG=1; OPT_SVG_PATH="${1#*=}" ;;
    --theme) shift; OPT_THEME="${1:-light}" ;;
    --theme=*) OPT_THEME="${1#*=}" ;;
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

# ---------------------------------------------------------------------------
# Color & Swiss-Industrial Box Drawing + Portable UTF-8 Display Width Engine
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RST='\033[0m'; C_BOLD='\033[1m'; C_DIM='\033[2m'
  C_RED='\033[31m'; C_GRN='\033[32m'; C_YLW='\033[33m'; C_BLU='\033[94m'; C_MAG='\033[95m'; C_CYN='\033[36m'; C_WHT='\033[97m'
else
  C_RST=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GRN=''; C_YLW=''; C_BLU=''; C_MAG=''; C_CYN=''; C_WHT=''
fi

exit_term_col() {
  case "$1" in
    直连*|国内*) printf '%s' "$C_CYN" ;;
    "出口 A"*) printf '%s' "$C_BLU" ;;
    "出口 B"*) printf '%s' "$C_YLW" ;;
    "出口 C"*) printf '%s' "$C_MAG" ;;
    "出口 "*) printf '%s' "$C_MAG" ;;
    *) printf '%s' "$C_DIM" ;;
  esac
}

BOX_W=96
if [ "$OPT_COMPACT" -eq 1 ]; then BOX_W=66; fi
if [ "$OPT_ASCII" -eq 1 ]; then
  B_TL="+"; B_TR="+"; B_BL="+"; B_BR="+"; B_H="-"; B_V="|"; B_LT="+"; B_RT="+"
else
  B_TL="┌"; B_TR="┐"; B_BL="└"; B_BR="┘"; B_H="─"; B_V="│"; B_LT="├"; B_RT="┤"
fi

# Byte-level UTF-8 display width + pad/clip (100% portable across mawk / gawk / BSD awk)
pad_disp() {
  local text="$1" cols="$2"
  LC_ALL=C awk -v s="$text" -v maxw="$cols" 'BEGIN {
    n = length(s); i = 1; w = 0; out = "";
    # Precompute display width first
    tw = 0; p = 1;
    while (p <= n) {
      b = substr(s, p, 1);
      c = index(" !\"#$%&'\''()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~", b);
      if (c > 0) { tw += 1; p += 1; continue; }
      # Read UTF-8 lead byte value using printf fallback table via char comparisons
      if (b < "\200") { tw += 1; p += 1; }
      else if (b >= "\360") { tw += 2; p += 4; }
      else if (b >= "\340") {
        # 3-byte UTF-8: arrows/box/math (E2) = width 1, CJK/fullwidth (E3..EF) = width 2
        if (b == "\342") { tw += 1; } else { tw += 2; }
        p += 3;
      } else if (b >= "\300") { tw += 1; p += 2; }
      else { p += 1; }
    }
    if (tw <= maxw) {
      printf "%s", s;
      for (k = tw; k < maxw; k++) printf " ";
      exit 0;
    }
    # Clip with ..
    p = 1; w = 0;
    while (p <= n) {
      b = substr(s, p, 1);
      step = 1; cw = 1;
      if (b < "\200") { step = 1; cw = 1; }
      else if (b >= "\360") { step = 4; cw = 2; }
      else if (b >= "\340") { step = 3; cw = (b == "\342") ? 1 : 2; }
      else if (b >= "\300") { step = 2; cw = 1; }
      if (w + cw + 2 > maxw) break;
      out = out substr(s, p, step);
      w += cw; p += step;
    }
    out = out ".."; w += 2;
    printf "%s", out;
    for (k = w; k < maxw; k++) printf " ";
  }'
}

box_rule() {
  local kind="$1" l="$B_LT" r="$B_RT"
  if [ "$kind" = "top" ]; then l="$B_TL"; r="$B_TR"; fi
  if [ "$kind" = "bot" ]; then l="$B_BL"; r="$B_BR"; fi
  local bar
  bar=$(awk -v n="$((BOX_W - 2))" -v ch="$B_H" 'BEGIN { for(i=0;i<n;i++) printf "%s", ch }')
  printf '%b%s%s%s%b\n' "$C_DIM" "$l" "$bar" "$r" "$C_RST"
}

box_line() {
  local text="$1" col="${2:-}"
  local inner=$((BOX_W - 4))
  local padded
  padded=$(pad_disp "$text" "$inner")
  printf '%b%s%b %b%s%b %b%s%b\n' "$C_DIM" "$B_V" "$C_RST" "$col" "$padded" "$C_RST" "$C_DIM" "$B_V" "$C_RST"
}

# ---------------------------------------------------------------------------
# Layer 1 Passive Environment Detection (Zero sudo / Zero Config Read / Zero Port Scan)
# ---------------------------------------------------------------------------
OS_NAME=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')
EFFECTIVE_PROXY="$OPT_PROXY"
if [ -z "$EFFECTIVE_PROXY" ]; then
  EFFECTIVE_PROXY="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-${ALL_PROXY:-${all_proxy:-}}}}}}"
fi
if [ -z "$EFFECTIVE_PROXY" ] && [ "$OS_NAME" = "darwin" ] && command -v scutil >/dev/null 2>&1; then
  SC_OUT=$(scutil --proxy 2>/dev/null || true)
  if printf '%s' "$SC_OUT" | grep -q 'HTTPSEnable : 1'; then
    SC_H=$(printf '%s' "$SC_OUT" | awk '/HTTPSProxy/{print $3; exit}')
    SC_P=$(printf '%s' "$SC_OUT" | awk '/HTTPSPort/{print $3; exit}')
    if [ -n "$SC_H" ] && [ -n "$SC_P" ]; then EFFECTIVE_PROXY="http://${SC_H}:${SC_P}"; fi
  elif printf '%s' "$SC_OUT" | grep -q 'HTTPEnable : 1'; then
    SC_H=$(printf '%s' "$SC_OUT" | awk '/HTTPProxy/{print $3; exit}')
    SC_P=$(printf '%s' "$SC_OUT" | awk '/HTTPPort/{print $3; exit}')
    if [ -n "$SC_H" ] && [ -n "$SC_P" ]; then EFFECTIVE_PROXY="http://${SC_H}:${SC_P}"; fi
  fi
fi

HAS_EXPLICIT_PROXY=0
if [ -n "$EFFECTIVE_PROXY" ]; then HAS_EXPLICIT_PROXY=1; fi

detect_passive_nic() {
  local nic=""
  if command -v ip >/dev/null 2>&1; then
    nic=$(ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep -iE '^(meta|mihomo|sing|clash|utun|tun|wg|warp|tailscale|flclash|hiddify)' | head -n 1 || true)
  elif command -v ifconfig >/dev/null 2>&1; then
    nic=$(ifconfig 2>/dev/null | awk '/^[a-zA-Z0-9_-]+:/{sub(":","",$1); print $1}' | grep -iE '^(utun|tun|wg|meta|mihomo|sing|clash|tailscale)' | head -n 1 || true)
  fi
  printf '%s' "$nic"
}

PASSIVE_TUN_NIC=$(detect_passive_nic)

show_dry_run() {
  box_rule top
  box_line "G-ROUTE v3 // --dry-run 零发包安全审计清单 (未发送任何网络请求)" "$C_CYN"
  box_rule mid
  box_line "[权限边界 · 4 个绝不]" "$C_YLW"
  box_line "  1. 绝不申请 root / sudo 提权" ""
  box_line "  2. 绝不读取磁盘配置文件 (~/.ssh、代理订阅、Cookie) 或扫描进程" ""
  box_line "  3. 绝不向任何服务器上传检测结果 (#r= 与 SVG 均 100% 本地离线生成)" ""
  box_line "  4. 绝不下载二进制文件或执行远程混淆代码" ""
  box_rule mid
  box_line "[将发起的只读 HTTPS GET/HEAD 请求 · 6 桶分流雷达 + Google 6 路]" "$C_YLW"
  box_line "  - myip.ipip.net (备选 cip.cc)              国内直连参照与绕行检测" ""
  box_line "  - v4/v6.ident.me/json (备选 ipify)         双栈通用海外出口 ASN" ""
  box_line "  - redirector.googlevideo.com/report_mapping Google/YT GGC 与实见 IP" ""
  box_line "  - www.cloudflare.com/cdn-cgi/trace         Cloudflare 出口 / WARP / colo" ""
  box_line "  - chatgpt.com/cdn-cgi/trace                OpenAI 实见出口 / WARP / colo" ""
  box_line "  - claude.ai/cdn-cgi/trace               Anthropic 实见出口 / WARP / colo" ""
  box_line "  - ipwho.is/<split_ip>                   仅对去重后的新增非 WARP 出口查 ASN" ""
  box_line "  - gspe1-ssl.ls.apple.com/pep/gcc           Apple 第三方地域对照" ""
  box_line "  - gemini / notebooklm / youtube / play / google / policies  Google 6 路" ""
  box_rule mid
  box_line "[当前会话被动识别]" "$C_YLW"
  box_line "  - IP 脱敏: $( [ "$OPT_FULL" -eq 1 ] && echo '关闭 (-f 完整显示)' || echo '开启 (默认 38.59.*.*)' )" ""
  box_line "  - 显式/系统代理: ${EFFECTIVE_PROXY:-无}" ""
  box_line "  - 只读虚拟网卡提示: ${PASSIVE_TUN_NIC:-未检测到活跃 TUN 网卡}" ""
  if [ -n "$OPT_CONTROLLER" ]; then
    box_line "  - 本地控制 API: ${OPT_CONTROLLER} (仅本屏只读，绝不入分享链)" ""
  elif [ "$OPT_INSPECT" -eq 1 ]; then
    box_line "  - 本地控制 API: 白名单自动发现 (仅本屏只读，绝不入分享链)" ""
  else
    box_line "  - 本地控制 API: 关闭 (纯黑盒模式，零本机端口/Socket 探测)" ""
  fi
  box_rule bot
}

# ---------------------------------------------------------------------------
# Global Interactive Entrypoint (Pre-Run 1-Screen Compact Menu — 0 Packets Yet)
# ---------------------------------------------------------------------------
IS_INTERACTIVE=0
if [ -t 1 ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
  IS_INTERACTIVE=1
fi

if [ "$HAS_EXPLICIT_FLAGS" -eq 0 ] && [ "$IS_INTERACTIVE" -eq 1 ] && [ "$OPT_NO_MENU" -eq 0 ]; then
  while true; do
    ENV_HINT="未检测到系统代理/TUN"
    if [ -n "$PASSIVE_TUN_NIC" ]; then ENV_HINT="检测到活跃虚拟网卡 [${PASSIVE_TUN_NIC}]"
    elif [ "$HAS_EXPLICIT_PROXY" -eq 1 ]; then ENV_HINT="检测到代理 [${EFFECTIVE_PROXY}]"; fi
    box_rule top
    box_line "G-ROUTE v3 // Google 生态送中与全链路分流体检仪" "$C_CYN"
    box_line "零提权 · 零读磁盘配置 · 零数据上传  |  ${ENV_HINT}" "$C_DIM"
    box_rule mid
    box_line "  [1] 极速纯黑盒体检  (默认 · 回车即跑 · 零本地端口/Socket 探测)" "$C_GRN"
    box_line "  [2] 深度体检 + 自动透视本机代理分组  (白名单只读查 Mihomo/sing-box)" "$C_CYN"
    box_line "  [3] 纯离线直出模式  (跑完本地生成 SVG 体检卡，不生成网页链接)" "$C_YLW"
    box_line "  [4] 零发包安全审计  (先看全部只读域名与 4 个绝不，不发任何包)" ""
    box_line "  [Q] 退出" "$C_DIM"
    box_rule bot
    printf '请选择 [1-4 / Q] (直接回车执行 1): ' >/dev/tty
    IFS= read -r MENU_CH </dev/tty || MENU_CH="1"
    MENU_CH=$(printf '%s' "$MENU_CH" | tr '[:lower:]' '[:upper:]' | tr -d ' \r\n')
    case "$MENU_CH" in
      ""|1) break ;;
      2) OPT_INSPECT=1; break ;;
      3) OPT_SVG=1; OPT_NO_LINK=1; break ;;
      4) show_dry_run; printf '\n' ;;
      Q) exit 0 ;;
      *) ;;
    esac
  done
fi

if [ "$OPT_DRY_RUN" -eq 1 ]; then
  show_dry_run
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  printf 'ERROR: curl is required.\n' >&2
  exit 1
fi

TMPDIR_GR=$(mktemp -d 2>/dev/null || mktemp -d -t groute)
trap 'rm -rf "$TMPDIR_GR"' EXIT INT TERM

step_bar() {
  local s="$1" tot="$2" msg="$3"
  if [ "$OPT_JSON" -eq 0 ] && [ -t 2 ]; then
    local filled=$(( (s * 10) / tot ))
    local bar
    bar=$(awk -v f="$filled" 'BEGIN { for(i=0;i<f;i++) printf "#"; for(i=f;i<10;i++) printf "." }')
    printf '\r\033[2K%b[G-ROUTE] [%s] %s/%s %s%b' "$C_DIM" "$bar" "$s" "$tot" "$msg" "$C_RST" >&2
  fi
}

clear_step() {
  if [ "$OPT_JSON" -eq 0 ] && [ -t 2 ]; then printf '\r\033[2K' >&2; fi
}

run_job() {
  local id="$1" tmo="$2" url="$3"
  shift 3
  local body="$TMPDIR_GR/${id}.body"
  local meta="$TMPDIR_GR/${id}.meta"
  (
    if [ -n "$EFFECTIVE_PROXY" ]; then
      curl -sS --max-time "$tmo" -A "$UA" -x "$EFFECTIVE_PROXY" "$@" -o "$body" -w 'CODE=%{http_code}|TIME=%{time_total}|IP=%{remote_ip}|URL=%{url_effective}' "$url" >"$meta" 2>/dev/null
    else
      curl -sS --max-time "$tmo" -A "$UA" "$@" -o "$body" -w 'CODE=%{http_code}|TIME=%{time_total}|IP=%{remote_ip}|URL=%{url_effective}' "$url" >"$meta" 2>/dev/null
    fi
    printf '%s\n' "$?" >"$TMPDIR_GR/${id}.rc"
  ) &
}

job_rc()   { cat "$TMPDIR_GR/$1.rc" 2>/dev/null || echo 1; }
job_body() { cat "$TMPDIR_GR/$1.body" 2>/dev/null || true; }
job_meta() { cat "$TMPDIR_GR/$1.meta" 2>/dev/null || true; }
job_http() { job_meta "$1" | sed -n 's/.*CODE=\([0-9]*\).*/\1/p'; }
job_ip()   { job_meta "$1" | sed -n 's/.*IP=\([^|]*\).*/\1/p'; }
job_url()  { job_meta "$1" | sed -n 's/.*URL=//p'; }
job_ms()   {
  local sec
  sec=$(job_meta "$1" | sed -n 's/.*TIME=\([0-9.]*\).*/\1/p')
  if [ -n "$sec" ]; then awk -v t="$sec" 'BEGIN { printf "%d", (t * 1000) + 0.5 }'; fi
}

json_esc() { printf '%s' "$1" | tr '\r\n\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
json_str() { printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1; }
json_num() { printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" | head -n 1; }
trace_get() { printf '%s\n' "$1" | awk -F= -v k="$2" '$1==k { sub(/^[^=]*=/, ""); gsub(/\r/,""); print; exit }'; }
xml_esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"; }

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
  if is_warp_ip "$raw_ip" || printf '%s' "$org_low" | grep -qE 'cloudflare|warp'; then printf 'warp'
  elif printf '%s' "$org_low" | grep -qE 'amazon|aws|google cloud|microsoft|azure|digitalocean|vultr|choopa|hetzner|ovh|linode|oracle|alibaba|aliyun|tencent|kirino|misaka|xtom|dmit|bandwagon|racknerd|zenlayer|m247|datacamp|leaseweb|scaleway|contabo|upcloud|vps|cloud|datacenter|hosting'; then printf 'hosting'
  elif printf '%s' "$org_low" | grep -qE 'cox |comcast|xfinity|verizon|at&t|spectrum|charter|softbank|ntt|kddi|chunghwa|hinet|pccw|hkbn|singtel|starhub|vodafone|telekom|telecom|broadband|fiber|fibre|cable|mobile'; then printf 'isp'
  elif [ "$ident_type" = "hosting" ] || [ "$ident_type" = "isp" ] || [ "$ident_type" = "business" ]; then printf '%s' "$ident_type"
  else printf 'unknown'; fi
}

kind_cn() {
  case "$1" in
    hosting) printf '云机房段' ;; isp) printf '运营商段' ;; warp) printf 'WARP 出站' ;; business) printf '商业网段' ;; *) printf '未归类段' ;;
  esac
}

is_cn_or_restricted() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    chn|cn|china|hkg|hk|"hong kong"|mac|mo|macau|rus|ru|russia|blr|by|belarus) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_first_ip() {
  local host="$1" ver="$2" ip=""
  if command -v getent >/dev/null 2>&1; then
    if [ "$ver" = "4" ]; then ip=$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1}'); else ip=$(getent ahostsv6 "$host" 2>/dev/null | awk 'NR==1{print $1}'); fi
  fi
  if [ -z "$ip" ] && command -v dig >/dev/null 2>&1; then
    if [ "$ver" = "4" ]; then ip=$(dig +short +time=2 +tries=1 A "$host" 2>/dev/null | grep -E '^[0-9]+\.' | head -n 1); else ip=$(dig +short +time=2 +tries=1 AAAA "$host" 2>/dev/null | grep ':' | head -n 1); fi
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
  if [ -n "$(resolve_first_ip "$canary" "$ver")" ]; then printf 'viadns'; return; fi
  if [ "$ver" = "4" ]; then
    case "$resolved" in
      142.250.*|142.251.*|172.217.*|172.253.*|216.58.*|216.239.*|74.125.*|64.233.*|209.85.*|108.177.*|192.178.*|66.102.*|66.249.*|34.*|35.*) printf 'native' ;;
      *) printf 'viadns' ;;
    esac
  else
    case "$resolved" in
      2607:f8b0:*|2404:6800:*|2a00:1450:*|2800:3f0:*) printf 'native' ;;
      *) printf 'viadns' ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# Wave 1: Parallel 6-Bucket Split-Route Radar + Dual-Stack Identity
# ---------------------------------------------------------------------------
DETECTED_TUN=0
NOW_TS=$(date -u +%s 2>/dev/null || echo 0)

step_bar 1 4 "并发探测 6 桶分流雷达与双栈出口..."
run_job cn  4 'https://myip.ipip.net'
run_job ap  5 'https://gspe1-ssl.ls.apple.com/pep/gcc' -4
run_job cf  6 'https://www.cloudflare.com/cdn-cgi/trace'
run_job oai 6 'https://chatgpt.com/cdn-cgi/trace'
run_job cld 6 'https://claude.ai/cdn-cgi/trace'
if [ "$OPT_V4" -eq 1 ]; then
  run_job v4_ident 6 'https://v4.ident.me/json' -4
  run_job v4_ggc   6 'https://redirector.googlevideo.com/report_mapping' -4
fi
if [ "$OPT_V6" -eq 1 ]; then
  run_job v6_ident 5 'https://v6.ident.me/json' -6
  run_job v6_ggc   5 'https://redirector.googlevideo.com/report_mapping' -6
fi
wait

for f in "$TMPDIR_GR"/*.meta; do
  [ -f "$f" ] || continue
  rip=$(sed -n 's/.*IP=\([^|]*\).*/\1/p' "$f")
  case "$rip" in 198.18.*|198.19.*|fc*|fd*) DETECTED_TUN=1 ;; esac
done

CN_RAW=$(job_body cn); CN_MS=$(job_ms cn)
CN_RAW_IP=$(printf '%s' "$CN_RAW" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
CN_NOTE=$(printf '%s' "$CN_RAW" | sed -n 's/.*来自于[：:][[:space:]]*//p' | tr -d '\r\n' | sed 's/[[:space:]]\+/ /g' | cut -c1-48 || true)
CN_DIRECT=""; CN_LEAK=0
if printf '%s' "$CN_RAW" | grep -q '中国'; then
  if ! printf '%s' "$CN_RAW" | grep -qE '香港|澳门|台湾'; then CN_DIRECT="CN"; fi
elif [ -n "$CN_RAW_IP" ] && [ -n "$CN_NOTE" ]; then
  CN_LEAK=1
fi

APPLE_CC=$(job_body ap | tr -cd 'A-Za-z' | tr '[:lower:]' '[:upper:]')
if [ "${#APPLE_CC}" -ne 2 ]; then APPLE_CC=""; fi

V4_OK=0; V4_RAW_IP=""; V4_IDENT=""; V4_DEF_MS=""
V6_OK=0; V6_RAW_IP=""; V6_IDENT=""; V6_DEF_MS=""
if [ "$OPT_V4" -eq 1 ]; then
  V4_IDENT=$(job_body v4_ident); V4_RAW_IP=$(json_str "$V4_IDENT" "ip"); V4_DEF_MS=$(job_ms v4_ident)
fi
if [ "$OPT_V6" -eq 1 ]; then
  V6_IDENT=$(job_body v6_ident); V6_RAW_IP=$(json_str "$V6_IDENT" "ip"); V6_DEF_MS=$(job_ms v6_ident)
fi

NEED_FB=0
if [ "$OPT_V4" -eq 1 ] && [ -z "$V4_RAW_IP" ]; then run_job v4_fb 4 'https://api4.ipify.org?format=json' -4; NEED_FB=1; fi
if [ "$OPT_V6" -eq 1 ] && [ -z "$V6_RAW_IP" ]; then run_job v6_fb 4 'https://api6.ipify.org?format=json' -6; NEED_FB=1; fi
if [ "$NEED_FB" -eq 1 ]; then
  wait
  if [ -z "$V4_RAW_IP" ] && [ -f "$TMPDIR_GR/v4_fb.body" ]; then V4_RAW_IP=$(json_str "$(job_body v4_fb)" "ip"); V4_DEF_MS=$(job_ms v4_fb); fi
  if [ -z "$V6_RAW_IP" ] && [ -f "$TMPDIR_GR/v6_fb.body" ]; then V6_RAW_IP=$(json_str "$(job_body v6_fb)" "ip"); V6_DEF_MS=$(job_ms v6_fb); fi
fi
if [ -n "$V4_RAW_IP" ]; then V4_OK=1; fi
if [ -n "$V6_RAW_IP" ]; then V6_OK=1; fi

if [ "$V4_OK" -eq 0 ] && [ "$V6_OK" -eq 0 ]; then
  clear_step
  printf 'ERROR: IPv4 与 IPv6 均未能获取出口信息，请检查网络或代理参数 (-x)。\n' >&2
  exit 1
fi

V4_GIP_RAW=""; V4_CDN=""; V4_CDNU=0; V4_CDN_MS=""
if [ "$V4_OK" -eq 1 ]; then
  rm4=$(job_body v4_ggc | grep '=>' | head -n 1 | tr -d '\r' || true)
  V4_CDN_MS=$(job_ms v4_ggc)
  if [ -n "$rm4" ]; then
    V4_GIP_RAW=$(printf '%s' "$rm4" | awk '{print $1}')
    V4_CDN=$(printf '%s' "$rm4" | awk '{print $3}')
    if printf '%s' "$rm4" | grep -q '\[u\]'; then V4_CDNU=1; fi
  fi
fi
V6_GIP_RAW=""; V6_CDN=""; V6_CDNU=0; V6_CDN_MS=""
if [ "$V6_OK" -eq 1 ]; then
  rm6=$(job_body v6_ggc | grep '=>' | head -n 1 | tr -d '\r' || true)
  V6_CDN_MS=$(job_ms v6_ggc)
  if [ -n "$rm6" ]; then
    V6_GIP_RAW=$(printf '%s' "$rm6" | awk '{print $1}')
    V6_CDN=$(printf '%s' "$rm6" | awk '{print $3}')
    if printf '%s' "$rm6" | grep -q '\[u\]'; then V6_CDNU=1; fi
  fi
fi

CF_BODY=$(job_body cf);   CF_IP=$(trace_get "$CF_BODY" ip);   CF_LOC=$(trace_get "$CF_BODY" loc | tr '[:lower:]' '[:upper:]');   CF_COLO=$(trace_get "$CF_BODY" colo | tr '[:lower:]' '[:upper:]');   CF_WARP=$(trace_get "$CF_BODY" warp | tr '[:upper:]' '[:lower:]');   CF_MS=$(job_ms cf)
OAI_BODY=$(job_body oai); OAI_IP=$(trace_get "$OAI_BODY" ip); OAI_LOC=$(trace_get "$OAI_BODY" loc | tr '[:lower:]' '[:upper:]'); OAI_COLO=$(trace_get "$OAI_BODY" colo | tr '[:lower:]' '[:upper:]'); OAI_WARP=$(trace_get "$OAI_BODY" warp | tr '[:upper:]' '[:lower:]'); OAI_MS=$(job_ms oai)
CLD_BODY=$(job_body cld); CLD_IP=$(trace_get "$CLD_BODY" ip); CLD_LOC=$(trace_get "$CLD_BODY" loc | tr '[:lower:]' '[:upper:]'); CLD_COLO=$(trace_get "$CLD_BODY" colo | tr '[:lower:]' '[:upper:]'); CLD_WARP=$(trace_get "$CLD_BODY" warp | tr '[:upper:]' '[:lower:]'); CLD_MS=$(job_ms cld)

# ---------------------------------------------------------------------------
# Wave 2: Parallel Google 6-Way Ground Truth + Deduplicated Split ASN Lookups
# ---------------------------------------------------------------------------
step_bar 2 4 "并发实测 Google 6 路真值与独立出口归属..."
launch_stack_w2() {
  local ver="$1" sf="-$1"
  run_job "v${ver}_gem"  9 'https://gemini.google.com/app' "$sf" -L
  run_job "v${ver}_nlm"  7 'https://notebooklm.google.com/' "$sf" -I
  run_job "v${ver}_yt"   9 'https://www.youtube.com/premium' "$sf" -L -H 'Accept-Language: en-US,en;q=0.9' -H "Cookie: $SOCS_COOKIE"
  run_job "v${ver}_play" 9 'https://play.google.com/' "$sf" -L -H 'Accept-Language: en-US,en;q=0.9'
  run_job "v${ver}_sdom" 7 'https://www.google.com/searchdomaincheck?format=domain' "$sf"
  run_job "v${ver}_srch" 9 'https://www.google.com/search?q=curl&ie=UTF-8' "$sf" -L -H 'Accept-Language: en-US,en;q=0.9' -H 'Sec-Fetch-Dest: document' -H 'Sec-Fetch-Mode: navigate' -H 'Sec-Fetch-Site: none'
  run_job "v${ver}_trm"  9 'https://policies.google.com/terms?hl=en' "$sf" -L
}
if [ "$V4_OK" -eq 1 ]; then launch_stack_w2 4; fi
if [ "$V6_OK" -eq 1 ]; then launch_stack_w2 6; fi

# Deduplicated ASN lookup for any newly discovered non-WARP exit IP
ASN_SEEN="|${V4_RAW_IP}|${V6_RAW_IP}|"
ASN_LIST_FILE="$TMPDIR_GR/asn_map.txt"
: > "$ASN_LIST_FILE"
ASN_IDX=0
for cip in "$V4_GIP_RAW" "$V6_GIP_RAW" "$CF_IP" "$OAI_IP" "$CLD_IP"; do
  [ -n "$cip" ] || continue
  case "$ASN_SEEN" in *"|${cip}|"*) continue ;; esac
  ASN_SEEN="${ASN_SEEN}${cip}|"
  if is_warp_ip "$cip"; then continue; fi
  ASN_IDX=$((ASN_IDX + 1))
  printf 'asn_%s|%s\n' "$ASN_IDX" "$cip" >> "$ASN_LIST_FILE"
  run_job "asn_${ASN_IDX}" 5 "https://ipwho.is/${cip}"
done
wait

for f in "$TMPDIR_GR"/v*_gem.meta; do
  [ -f "$f" ] || continue
  rip=$(sed -n 's/.*IP=\([^|]*\).*/\1/p' "$f")
  case "$rip" in 198.18.*|198.19.*|fc*|fd*) DETECTED_TUN=1 ;; esac
done

step_bar 3 4 "聚合分流拓扑与诊断结论..."

# Store ip metadata cache in simple pipe-delimited file: ip|asn|org|cc|city|kind
META_DB="$TMPDIR_GR/meta.db"
: > "$META_DB"
add_meta_row() {
  printf '%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$(printf '%s' "$3" | tr '|' ' ')" "$4" "$(printf '%s' "$5" | tr '|' ' ')" "$6" >> "$META_DB"
}
if [ "$V4_OK" -eq 1 ]; then
  V4_ASN=$(json_num "$V4_IDENT" "asn"); V4_ORG=$(json_str "$V4_IDENT" "aso"); V4_CC=$(json_str "$V4_IDENT" "cc" | tr '[:lower:]' '[:upper:]'); V4_CITY=$(json_str "$V4_IDENT" "city"); V4_KIND=$(classify_kind "$V4_ORG" "$(json_str "$V4_IDENT" "type")" "$V4_RAW_IP")
  add_meta_row "$V4_RAW_IP" "$V4_ASN" "$V4_ORG" "$V4_CC" "$V4_CITY" "$V4_KIND"
fi
if [ "$V6_OK" -eq 1 ]; then
  V6_ASN=$(json_num "$V6_IDENT" "asn"); V6_ORG=$(json_str "$V6_IDENT" "aso"); V6_CC=$(json_str "$V6_IDENT" "cc" | tr '[:lower:]' '[:upper:]'); V6_CITY=$(json_str "$V6_IDENT" "city"); V6_KIND=$(classify_kind "$V6_ORG" "$(json_str "$V6_IDENT" "type")" "$V6_RAW_IP")
  add_meta_row "$V6_RAW_IP" "$V6_ASN" "$V6_ORG" "$V6_CC" "$V6_CITY" "$V6_KIND"
fi
while IFS='|' read -r aid aip; do
  [ -n "$aid" ] || continue
  ab=$(job_body "$aid")
  if printf '%s' "$ab" | grep -q '"success":true'; then
    aa=$(json_num "$ab" "asn")
    ao=$(json_str "$ab" "org"); if [ -z "$ao" ]; then ao=$(json_str "$ab" "isp"); fi
    ac=$(json_str "$ab" "country_code" | tr '[:lower:]' '[:upper:]')
    ak=$(classify_kind "$ao" "" "$aip")
    add_meta_row "$aip" "$aa" "$ao" "$ac" "" "$ak"
  fi
done < "$ASN_LIST_FILE"

meta_field() {
  local ip="$1" col="$2" val=""
  if [ -n "$ip" ]; then
    val=$(awk -F'|' -v k="$ip" -v c="$col" '$1==k { print $c; exit }' "$META_DB")
  fi
  if [ -z "$val" ] && is_warp_ip "$ip"; then
    case "$col" in 2) val="13335" ;; 3) val="Cloudflare WARP" ;; 6) val="warp" ;; esac
  fi
  printf '%s' "$val"
}

parse_stack_w2() {
  local ver="$1"
  local gem_body gem_cc nlm_body nlm_loc nlm_st yt_body yt_st yt_gl play_cc sdom_raw sdom sr_body sr_code sr_url scap trm_body trm_cv trm_ent dns_m
  gem_body=$(job_body "v${ver}_gem")
  gem_cc=$(printf '%s' "$gem_body" | grep -oE ',2,1,200,"[A-Z]{3}"' | head -n 1 | grep -oE '[A-Z]{3}' || true)
  if [ -z "$gem_cc" ]; then gem_cc=$(printf '%s' "$gem_body" | grep -oE '"countryCode":"[A-Z]{2}"' | head -n 1 | cut -d'"' -f4 || true); fi

  nlm_body=$(job_body "v${ver}_nlm")
  nlm_loc=$(printf '%s\n' "$nlm_body" | grep -i '^location:' | head -n 1 | tr -d '\r' || true)
  local nlm_code; nlm_code=$(job_http "v${ver}_nlm")
  if printf '%s' "$nlm_loc" | grep -qi 'location=unsupported'; then nlm_st="unavail"
  elif printf '%s' "$nlm_loc" | grep -qiE 'notebook\.google\.com|accounts\.google\.com' || [ "$nlm_code" = "200" ] || [ "$nlm_code" = "301" ] || [ "$nlm_code" = "302" ]; then nlm_st="ok"
  else nlm_st="err"; fi

  yt_body=$(job_body "v${ver}_yt"); yt_gl=""
  if [ -z "$yt_body" ]; then yt_st="err"
  else
    yt_gl=$(printf '%s' "$yt_body" | grep -oE '"contentRegion":"[A-Z]{2}"' | head -n 1 | cut -d'"' -f4 || true)
    if [ -z "$yt_gl" ]; then yt_gl=$(printf '%s' "$yt_body" | grep -oE '"INNERTUBE_CONTEXT_GL":"[A-Z]{2}"' | head -n 1 | cut -d'"' -f4 || true); fi
    if printf '%s' "$yt_body" | grep -q 'www.google.cn'; then yt_st="cn"
    elif printf '%s' "$yt_body" | grep -qi 'Premium is not available in your country'; then yt_st="noprem"
    elif printf '%s' "$yt_body" | grep -qi 'ad-free'; then yt_st="ok"
    else yt_st="err"; fi
  fi

  play_cc=$(job_body "v${ver}_play" | grep -oE '<div class="yVZQTb">[^<(]+' | head -n 1 | sed -e 's/<div class="yVZQTb">//' -e 's/[[:space:]]*$//' || true)

  sdom_raw=$(job_body "v${ver}_sdom")
  if printf '%s' "$sdom_raw" | grep -qi 'hkredirect'; then sdom="hkredirect"
  else
    sdom=$(printf '%s\n' "$sdom_raw" | head -n 1 | tr -d '\r\n ' || true)
    case "$sdom" in .google.*) ;; *) sdom="" ;; esac
  fi

  sr_body=$(job_body "v${ver}_srch"); sr_code=$(job_http "v${ver}_srch"); sr_url=$(job_url "v${ver}_srch")
  if [ -z "$sr_code" ] || [ "$sr_code" = "000" ]; then scap="err"
  elif [ "$sr_code" = "429" ] || printf '%s' "$sr_body" | grep -qiE 'unusual traffic from|is blocked|unaddressed abuse|/sorry/'; then scap="captcha"
  elif printf '%s' "$sr_url" | grep -qiE 'google\.com\.hk|google\.cn'; then scap="hk"
  else scap="ok"; fi

  trm_body=$(job_body "v${ver}_trm")
  trm_cv=$(printf '%s' "$trm_body" | grep -oE 'Country version:?</[^>]+>[[:space:]]*[A-Za-z][^<]{1,42}' | head -n 1 | sed -E 's/^[^>]+>[[:space:]]*//; s/[[:space:]]+$//' || true)
  if [ -z "$trm_cv" ]; then trm_cv=$(printf '%s' "$trm_body" | grep -oE 'Country version:[[:space:]]*[A-Za-z][A-Za-z ,.&'\''-]{1,40}' | head -n 1 | sed -E 's/^Country version:[[:space:]]*//; s/[[:space:]]+$//' || true); fi
  trm_ent=$(printf '%s' "$trm_body" | grep -oE 'Google Ireland Limited|Google LLC|Google Asia Pacific|Google Commerce Limited' | head -n 1 || true)

  dns_m=$(check_dns_unlock "$ver" "$DETECTED_TUN" "$HAS_EXPLICIT_PROXY")

  eval "V${ver}_GEM=\"\$gem_cc\"; V${ver}_NLM=\"\$nlm_st\"; V${ver}_YT=\"\$yt_st\"; V${ver}_YTG=\"\$yt_gl\""
  eval "V${ver}_PLAY=\"\$play_cc\"; V${ver}_SDOM=\"\$sdom\"; V${ver}_SCAP=\"\$scap\"; V${ver}_TRM=\"\$trm_cv\"; V${ver}_ENT=\"\$trm_ent\"; V${ver}_DNS=\"\$dns_m\""
  eval "V${ver}_GEM_MS=\"\$(job_ms v${ver}_gem)\"; V${ver}_NLM_MS=\"\$(job_ms v${ver}_nlm)\"; V${ver}_YT_MS=\"\$(job_ms v${ver}_yt)\"; V${ver}_PLAY_MS=\"\$(job_ms v${ver}_play)\"; V${ver}_SRCH_MS=\"\$(job_ms v${ver}_srch)\""
}

V4_IP=""; V4_GIP=""; V4_GASN=""; V4_GORG=""; V4_GKIND=""
V4_GEM=""; V4_NLM=""; V4_YT=""; V4_YTG=""; V4_PLAY=""; V4_SDOM=""; V4_SCAP=""; V4_TRM=""; V4_ENT=""; V4_DNS="skip"
V4_GEM_MS=""; V4_NLM_MS=""; V4_YT_MS=""; V4_PLAY_MS=""; V4_SRCH_MS=""
V6_IP=""; V6_GIP=""; V6_GASN=""; V6_GORG=""; V6_GKIND=""
V6_GEM=""; V6_NLM=""; V6_YT=""; V6_YTG=""; V6_PLAY=""; V6_SDOM=""; V6_SCAP=""; V6_TRM=""; V6_ENT=""; V6_DNS="skip"
V6_GEM_MS=""; V6_NLM_MS=""; V6_YT_MS=""; V6_PLAY_MS=""; V6_SRCH_MS=""

if [ "$V4_OK" -eq 1 ]; then
  V4_IP=$(mask_ip "$V4_RAW_IP"); V4_GIP=$(mask_ip "$V4_GIP_RAW")
  if [ -n "$V4_GIP_RAW" ] && [ "$V4_GIP_RAW" != "$V4_RAW_IP" ]; then
    V4_GASN=$(meta_field "$V4_GIP_RAW" 2); V4_GORG=$(meta_field "$V4_GIP_RAW" 3); V4_GKIND=$(meta_field "$V4_GIP_RAW" 6)
  fi
  parse_stack_w2 4
fi
if [ "$V6_OK" -eq 1 ]; then
  V6_IP=$(mask_ip "$V6_RAW_IP"); V6_GIP=$(mask_ip "$V6_GIP_RAW")
  if [ -n "$V6_GIP_RAW" ] && [ "$V6_GIP_RAW" != "$V6_RAW_IP" ]; then
    V6_GASN=$(meta_field "$V6_GIP_RAW" 2); V6_GORG=$(meta_field "$V6_GIP_RAW" 3); V6_GKIND=$(meta_field "$V6_GIP_RAW" 6)
  fi
  parse_stack_w2 6
fi

# Primary stack aliases
if [ "$V4_OK" -eq 1 ]; then
  P_RAW_IP="$V4_RAW_IP"; P_GIP_RAW="$V4_GIP_RAW"; P_IP="$V4_IP"; P_GIP="$V4_GIP"; P_ASN="$V4_ASN"; P_ORG="$V4_ORG"; P_CC="$V4_CC"; P_KIND="$V4_KIND"
  P_GASN="$V4_GASN"; P_GORG="$V4_GORG"; P_GKIND="$V4_GKIND"; P_GEM="$V4_GEM"; P_DNS="$V4_DNS"; P_CDN="$V4_CDN"; P_DEF_MS="$V4_DEF_MS"; P_CDN_MS="$V4_CDN_MS"
else
  P_RAW_IP="$V6_RAW_IP"; P_GIP_RAW="$V6_GIP_RAW"; P_IP="$V6_IP"; P_GIP="$V6_GIP"; P_ASN="$V6_ASN"; P_ORG="$V6_ORG"; P_CC="$V6_CC"; P_KIND="$V6_KIND"
  P_GASN="$V6_GASN"; P_GORG="$V6_GORG"; P_GKIND="$V6_GKIND"; P_GEM="$V6_GEM"; P_DNS="$V6_DNS"; P_CDN="$V6_CDN"; P_DEF_MS="$V6_DEF_MS"; P_CDN_MS="$V6_CDN_MS"
fi

SPLIT_HIT=0
if [ -n "$P_IP" ] && [ -n "$P_GIP" ] && [ "$P_IP" != "$P_GIP" ]; then SPLIT_HIT=1; fi

# Layer 1 Transport classification
NET_KIND="direct"
NET_LABEL="直连出站"
if [ "$SPLIT_HIT" -eq 1 ]; then NET_LABEL="直连主机 · 出站分流"; fi
if [ "$DETECTED_TUN" -eq 1 ]; then
  NET_KIND="tun_fakeip"
  NET_LABEL="本机 TUN · Fake-IP"
  if [ -n "$PASSIVE_TUN_NIC" ]; then NET_LABEL="${NET_LABEL} (${PASSIVE_TUN_NIC})"; fi
elif [ -n "$PASSIVE_TUN_NIC" ] && { [ -n "$CN_DIRECT" ] || [ "$SPLIT_HIT" -eq 1 ] || [ "$OPT_MODE" = "proxy" ]; }; then
  NET_KIND="tun_realip"
  NET_LABEL="本机 TUN · Real-IP (${PASSIVE_TUN_NIC})"
elif [ "$HAS_EXPLICIT_PROXY" -eq 1 ]; then
  NET_KIND="sysproxy"
  PX_SHORT=$(printf '%s' "$EFFECTIVE_PROXY" | sed -E 's#^https?://##')
  NET_LABEL="系统代理 (${PX_SHORT})"
elif [ -n "$CN_DIRECT" ] && [ -n "$P_CC" ] && [ "$P_CC" != "CN" ]; then
  NET_KIND="router"
  NET_LABEL="上游透明代理 / 旁路由"
fi

if [ -n "$OPT_MODE" ]; then RUN_MODE="$OPT_MODE"
elif [ "$NET_KIND" != "direct" ]; then RUN_MODE="proxy"
else RUN_MODE="vps"; fi

if [ "$RUN_MODE" != "proxy" ] && [ -z "$CN_DIRECT" ]; then CN_LEAK=0; fi

# Build clustered exit rows in $TMPDIR_GR/clusters.txt: slot|tone|ip|asnorg|buckets|avgms|warp|iscn
CLUSTERS_FILE="$TMPDIR_GR/clusters.txt"
: > "$CLUSTERS_FILE"
if [ -n "$CN_DIRECT" ] || { [ "$RUN_MODE" = "proxy" ] && [ -n "$CN_RAW_IP" ] && [ -n "$CN_NOTE" ]; }; then
  CN_IP_M=$(mask_ip "$CN_RAW_IP")
  if [ -n "$CN_DIRECT" ]; then
    printf '直连 CN|ok|%s|%s|国内直连 (未绕行代理)|%s|0|1\n' "${CN_IP_M:---}" "${CN_NOTE:-国内直连}" "${CN_MS}" >> "$CLUSTERS_FILE"
  else
    printf '国内异常|leak|%s|%s|国内桶落入海外!|%s|0|0\n' "${CN_IP_M:---}" "${CN_NOTE:-非CN出口}" "${CN_MS}" >> "$CLUSTERS_FILE"
  fi
fi

# Cluster overseas 5 buckets (def, ggc, cf, oai, cld) via temp raw bucket file
RAW_BUCKETS="$TMPDIR_GR/raw_buckets.txt"
: > "$RAW_BUCKETS"
add_raw_b() {
  local rawip="$1" label="$2" colo="$3" warp="$4" ms="$5" cc_ov="$6"
  [ -n "$rawip" ] || return
  local mip asn org kind cc tag extra=""
  mip=$(mask_ip "$rawip")
  asn=$(meta_field "$rawip" 2); org=$(meta_field "$rawip" 3); kind=$(meta_field "$rawip" 6)
  cc="${cc_ov:-$(meta_field "$rawip" 4)}"
  if [ "$warp" = "on" ] || [ "$warp" = "plus" ]; then kind="warp"; fi
  if [ -n "$colo" ]; then extra="$colo"; fi
  if [ "$warp" = "on" ] || [ "$warp" = "plus" ]; then extra="${extra:+${extra}/}WARP"; fi
  tag="$label"; if [ -n "$extra" ]; then tag="${label}(${extra})"; fi
  local isw=0; if [ "$kind" = "warp" ]; then isw=1; fi
  printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$mip" "$asn" "${org:-独立出口}" "$cc" "$tag" "$ms" "$isw" "$kind" >> "$RAW_BUCKETS"
}

add_raw_b "$P_RAW_IP"  "通用海外"   ""       "off"       "$P_DEF_MS" "$P_CC"
add_raw_b "$P_GIP_RAW" "Google/YT"  "$P_CDN" "$(is_warp_ip "$P_GIP_RAW" && echo on || echo off)" "$P_CDN_MS" ""
add_raw_b "$CF_IP"     "Cloudflare" "$CF_COLO"  "$CF_WARP"  "$CF_MS"  "$CF_LOC"
add_raw_b "$OAI_IP"    "ChatGPT"    "$OAI_COLO" "$OAI_WARP" "$OAI_MS" "$OAI_LOC"
add_raw_b "$CLD_IP"    "Claude"     "$CLD_COLO" "$CLD_WARP" "$CLD_MS" "$CLD_LOC"

awk -F'|' 'BEGIN { letters="ABCDEFGHIJKLMNOPQRSTUVWXYZ"; n=0; }
{
  k=tolower($1);
  if (!(k in idx)) {
    n++; idx[k]=n; order[n]=k;
    ip[k]=$1; asn[k]=$2; org[k]=$3; cc[k]=$4; bkts[k]=$5;
    if ($6 != "") { msum[k]=$6+0; mcnt[k]=1; } else { msum[k]=0; mcnt[k]=0; }
    warp[k]=$7+0;
  } else {
    bkts[k]=bkts[k] " / " $5;
    if ($6 != "") { msum[k]+=$6+0; mcnt[k]++; }
    if ($7+0 == 1) warp[k]=1;
    if (asn[k] == "" && $2 != "") asn[k]=$2;
    if ((org[k] == "" || org[k] == "独立出口") && $3 != "") org[k]=$3;
    if (cc[k] == "" && $4 != "") cc[k]=$4;
  }
}
END {
  for (i=1; i<=n; i++) {
    k=order[i];
    slot="出口 " substr(letters, i, 1);
    tone=(warp[k]==1) ? "diff" : (i==1 ? "muted" : "ok");
    asnp=(asn[k]!="") ? ("AS" asn[k] " ") : "";
    ccp=(cc[k]!="") ? (" [" cc[k] "]") : "";
    avg=(mcnt[k]>0) ? sprintf("%d", (msum[k]/mcnt[k])+0.5) : "";
    printf "%s|%s|%s|%s%s%s|%s|%s|%d|0\n", slot, tone, ip[k], asnp, org[k], ccp, bkts[k], avg, warp[k];
  }
}' "$RAW_BUCKETS" >> "$CLUSTERS_FILE"

OV_SLOTS=$(awk -F'|' '$8==0 && $1!="国内异常" {c++} END{print c+0}' "$CLUSTERS_FILE")
HAS_WARP_BUCKET=$(awk -F'|' '$7==1 {f=1} END{print f+0}' "$CLUSTERS_FILE")

# Drift & Alarms
stack_has_drift() {
  local gem="$1" nlm="$2" yt="$3" play="$4" sdom="$5" scap="$6" trm="$7" hits=0
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
DUAL_CONFLICT=0
if [ "$V4_OK" -eq 1 ] && [ "$V6_OK" -eq 1 ] && { [ "$D4" -ne "$D6" ] || { [ -n "$V4_GEM" ] && [ -n "$V6_GEM" ] && [ "$V4_GEM" != "$V6_GEM" ]; }; }; then DUAL_CONFLICT=1; fi

ALARMS_JSON=""
ALARMS_TXT="$TMPDIR_GR/alarms.txt"
: > "$ALARMS_TXT"
add_alarm() {
  if [ -n "$ALARMS_JSON" ]; then ALARMS_JSON="${ALARMS_JSON},"; fi
  ALARMS_JSON="${ALARMS_JSON}\"$1\""
  printf '%s|%s\n' "$2" "$3" >> "$ALARMS_TXT"
}
if [ "$CN_LEAK" -eq 1 ]; then add_alarm "cn_leak" "leak" "[!] 国内分流绕行: 国内桶返回 $(mask_ip "$CN_RAW_IP") (${CN_NOTE})，请检查 CN 直连规则"; fi
if [ "$DUAL_CONFLICT" -eq 1 ]; then add_alarm "stack_split" "leak" "[!] 双栈冲突: IPv4(${V4_GEM:-?}) 与 IPv6(${V6_GEM:-?}) 不一致，Google 优先 IPv6 易偶发报错"; fi
AI_UNIQUE=$(printf '%s\n%s\n%s\n' "$(mask_ip "$P_GIP_RAW")" "$(mask_ip "$OAI_IP")" "$(mask_ip "$CLD_IP")" | awk 'NF && !a[tolower($0)]++ {c++} END{print c+0}')
if [ "$AI_UNIQUE" -ge 2 ]; then add_alarm "ai_split" "diff" "[i] 跨 AI 生态分流: Google/YT · ChatGPT · Claude 命中了 ${AI_UNIQUE} 条不同海外出口"; fi
if [ "$HAS_WARP_BUCKET" -eq 1 ]; then add_alarm "warp_egress" "ok" "[i] 检出 Cloudflare WARP 出站: 部分业务经 WARP 转发，有效隔离原始机房段"; fi

EFF_KIND="$P_KIND"
if [ "$SPLIT_HIT" -eq 1 ] && [ -n "$P_GKIND" ]; then EFF_KIND="$P_GKIND"; fi
V_TAG="CLEAN"; V_COL="$C_GRN"; V_TONE="ok"
V_TEXT="Google 全家桶全绿可用"
if [ "$EFF_KIND" = "hosting" ]; then V_TEXT="云机房出口全绿可用 · 实测无送中无验证码 (反焦虑认证)"; fi

if [ "$DUAL_CONFLICT" -eq 1 ]; then
  V_TAG="STACK_SPLIT"; V_COL="$C_YLW"; V_TONE="diff"
  V_TEXT="双栈不对称: IPv4(${V4_GEM:-?}) vs IPv6(${V6_GEM:-?})，建议关闭冲突栈"
elif [ "$D4" -eq 1 ] || [ "$D6" -eq 1 ]; then
  V_TAG="CN_DRIFT"; V_COL="$C_RED"; V_TONE="leak"
  if [ -n "$P_CC" ] && ! is_cn_or_restricted "$P_CC"; then
    V_TEXT="实锤 Google 私有库送中 (公开库 ${P_CC} / Apple ${APPLE_CC:-?}，但 Google 判受限)"
  else V_TEXT="Google 生态判定为受限地区 / 送中"; fi
elif [ "$V4_SCAP" = "captcha" ] || [ "$V6_SCAP" = "captcha" ]; then
  V_TAG="PARTIAL"; V_COL="$C_YLW"; V_TONE="diff"
  V_TEXT="AI 核心可用，但 Google Search 触发 /sorry/ 人机验证"
elif [ "$SPLIT_HIT" -eq 1 ] || [ "$OV_SLOTS" -ge 2 ]; then
  V_TAG="SPLIT_ROUTE"; V_COL="$C_CYN"; V_TONE="ok"
  if [ -n "$P_GORG" ]; then V_TEXT="跨组分流生效 · 检出 ${OV_SLOTS} 路海外出口 (Google 经 ${P_GORG} 可用)"
  else V_TEXT="跨组分流生效 · 检出 ${OV_SLOTS} 路海外出口且 Google 全绿可用"; fi
fi

# Compute anonymized per-service exit slot labels (ZERO proxy node names!)
# Uses single-exit exact mapping or black-box GGC exit; enriched further if --inspect captures local leaf nodes.
SVC_EX_GEM=""; SVC_EX_NLM=""; SVC_EX_YT=""; SVC_EX_CDN=""; SVC_EX_PLAY=""; SVC_EX_SRCH=""; SVC_EX_TRM=""
cluster_slot_for_ip() {
  awk -F'|' -v ip="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" 'tolower($3)==ip {
    org=$4; sub(/^AS[0-9]+ /,"",org); sub(/ \[.*$/,"",org);
    sub(/ (Communications|Corporation|Corp\.?|Inc\.?|LLC|Ltd\.?|Limited|Co\.?).*$/,"",org);
    if (org ~ /Cloudflare/) org="WARP";
    if (org != "" && org != "独立出口") printf "%s · %s · %s", $1, $3, org;
    else printf "%s · %s", $1, $3;
    exit
  }' "$CLUSTERS_FILE"
}
compute_svc_exits() {
  local def_ref ggc_ref
  def_ref=$(cluster_slot_for_ip "$P_IP")
  ggc_ref=$(cluster_slot_for_ip "${P_GIP:-$P_IP}")
  [ -z "$def_ref" ] && def_ref="出口 A (${P_IP})"
  [ -z "$ggc_ref" ] && ggc_ref="$def_ref"
  SVC_EX_CDN="$ggc_ref"
  SVC_EX_YT="$ggc_ref"
  if [ "$OV_SLOTS" -le 1 ] || [ "$SPLIT_HIT" -eq 0 ]; then
    SVC_EX_GEM="$def_ref"; SVC_EX_NLM="$def_ref"; SVC_EX_PLAY="$def_ref"; SVC_EX_SRCH="$def_ref"; SVC_EX_TRM="$def_ref"
  else
    SVC_EX_GEM="多出口分流 (--inspect 定位)"
    SVC_EX_NLM="$SVC_EX_GEM"; SVC_EX_PLAY="$SVC_EX_GEM"; SVC_EX_SRCH="$SVC_EX_GEM"; SVC_EX_TRM="$SVC_EX_GEM"
  fi
  if [ -s "$TMPDIR_GR/host_leaf.txt" ]; then
    local oai_mip cld_mip oai_ref cld_ref
    oai_mip=$(mask_ip "$OAI_IP"); cld_mip=$(mask_ip "$CLD_IP")
    oai_ref=$(cluster_slot_for_ip "$oai_mip"); cld_ref=$(cluster_slot_for_ip "$cld_mip")
    local l_def l_oai l_cld
    l_def=$(awk -F'|' '$1=="v4.ident.me"{print $2; exit}' "$TMPDIR_GR/host_leaf.txt")
    l_oai=$(awk -F'|' '$1=="chatgpt.com"{print $2; exit}' "$TMPDIR_GR/host_leaf.txt")
    l_cld=$(awk -F'|' '$1=="claude.ai"{print $2; exit}' "$TMPDIR_GR/host_leaf.txt")
    resolve_leaf_ref() {
      local lf="$1"
      [ -z "$lf" ] && return
      if [ -n "$l_oai" ] && [ "$lf" = "$l_oai" ] && [ -n "$oai_ref" ]; then printf '%s' "$oai_ref"; return; fi
      if [ -n "$l_cld" ] && [ "$lf" = "$l_cld" ] && [ -n "$cld_ref" ]; then printf '%s' "$cld_ref"; return; fi
      if [ -n "$l_def" ] && [ "$lf" = "$l_def" ] && [ -n "$def_ref" ]; then printf '%s' "$def_ref"; return; fi
      printf '独立分流出口 (非已有槽)'
    }
    local lg ln lp ls lt r
    lg=$(awk -F'|' '$1=="gemini.google.com"{print $2; exit}' "$TMPDIR_GR/host_leaf.txt")
    ln=$(awk -F'|' '$1=="notebooklm.google.com"{print $2; exit}' "$TMPDIR_GR/host_leaf.txt")
    lp=$(awk -F'|' '$1=="play.google.com"{print $2; exit}' "$TMPDIR_GR/host_leaf.txt")
    ls=$(awk -F'|' '$1=="www.google.com"{print $2; exit}' "$TMPDIR_GR/host_leaf.txt")
    lt=$(awk -F'|' '$1=="policies.google.com"{print $2; exit}' "$TMPDIR_GR/host_leaf.txt")
    r=$(resolve_leaf_ref "$lg"); [ -n "$r" ] && SVC_EX_GEM="$r"
    r=$(resolve_leaf_ref "${ln:-$lg}"); [ -n "$r" ] && SVC_EX_NLM="$r"
    r=$(resolve_leaf_ref "${lp:-$ls}"); [ -n "$r" ] && SVC_EX_PLAY="$r"
    r=$(resolve_leaf_ref "$ls"); [ -n "$r" ] && SVC_EX_SRCH="$r"
    r=$(resolve_leaf_ref "${lt:-$ls}"); [ -n "$r" ] && SVC_EX_TRM="$r"
  fi
}
: > "$TMPDIR_GR/host_leaf.txt"
compute_svc_exits

# ---------------------------------------------------------------------------
# Assemble Compact Backward-Compatible CliReportV1 JSON
# ---------------------------------------------------------------------------
build_bucket_json() {
  local rawip="$1" cc="$2" colo="$3" warp="$4" ms="$5" note="$6"
  if [ -z "$rawip" ] && [ -z "$note" ]; then printf ''; return; fi
  local out="{" sep="" mip asn org kind
  mip=$(mask_ip "$rawip")
  asn=$(meta_field "$rawip" 2); org=$(meta_field "$rawip" 3); kind=$(meta_field "$rawip" 6)
  if [ "$warp" = "on" ] || [ "$warp" = "plus" ]; then kind="warp"; fi
  if [ -z "$cc" ]; then cc=$(meta_field "$rawip" 4); fi
  [ -n "$mip" ]  && { out="${out}${sep}\"ip\":\"$(json_esc "$mip")\""; sep=","; }
  [ -n "$cc" ]   && { out="${out}${sep}\"cc\":\"$(json_esc "$cc")\""; sep=","; }
  [ -n "$asn" ]  && { out="${out}${sep}\"asn\":${asn}"; sep=","; }
  [ -n "$org" ]  && { out="${out}${sep}\"org\":\"$(json_esc "$org")\""; sep=","; }
  [ -n "$kind" ] && { out="${out}${sep}\"kind\":\"$(json_esc "$kind")\""; sep=","; }
  [ -n "$colo" ] && { out="${out}${sep}\"colo\":\"$(json_esc "$colo")\""; sep=","; }
  case "$warp" in on|off|plus) out="${out}${sep}\"warp\":\"${warp}\""; sep="," ;; esac
  [ -n "$ms" ]   && { out="${out}${sep}\"ms\":${ms}"; sep=","; }
  [ -n "$note" ] && { out="${out}${sep}\"note\":\"$(json_esc "$note")\""; sep=","; }
  printf '%s}' "$out"
}

build_stack_json() {
  local ver="$1"
  eval "local ip=\$V${ver}_IP gip=\$V${ver}_GIP asn=\$V${ver}_ASN org=\$V${ver}_ORG cc=\$V${ver}_CC city=\$V${ver}_CITY kind=\$V${ver}_KIND"
  eval "local gasn=\$V${ver}_GASN gorg=\$V${ver}_GORG gkind=\$V${ver}_GKIND gem=\$V${ver}_GEM nlm=\$V${ver}_NLM yt=\$V${ver}_YT ytg=\$V${ver}_YTG"
  eval "local cdn=\$V${ver}_CDN cdnu=\$V${ver}_CDNU play=\$V${ver}_PLAY sdom=\$V${ver}_SDOM scap=\$V${ver}_SCAP trm=\$V${ver}_TRM ent=\$V${ver}_ENT dns=\$V${ver}_DNS"
  eval "local m_gem=\$V${ver}_GEM_MS m_nlm=\$V${ver}_NLM_MS m_yt=\$V${ver}_YT_MS m_cdn=\$V${ver}_CDN_MS m_play=\$V${ver}_PLAY_MS m_srch=\$V${ver}_SRCH_MS"
  local out="{" sep=""
  add_s() { [ -n "$2" ] && { out="${out}${sep}\"$1\":\"$(json_esc "$2")\""; sep=","; }; }
  add_n() { [ -n "$2" ] && { out="${out}${sep}\"$1\":$2"; sep=","; }; }
  add_s ip "$ip"; add_s gip "$gip"; add_n asn "$asn"; add_s org "$org"; add_s cc "$cc"; add_s city "$city"; add_s kind "$kind"
  add_n gasn "$gasn"; add_s gorg "$gorg"; add_s gkind "$gkind"
  add_s gem "$gem"; add_s nlm "$nlm"; add_s yt "$yt"; add_s ytg "$ytg"; add_s cdn "$cdn"
  if [ "$cdnu" -eq 1 ]; then out="${out}${sep}\"cdnu\":true"; sep=","; fi
  add_s play "$play"; add_s sdom "$sdom"; add_s scap "$scap"; add_s trm "$trm"; add_s ent "$ent"; add_s dns "$dns"
  local rtt="" rsep=""
  [ -n "$m_gem" ]  && { rtt="${rtt}${rsep}\"gem\":${m_gem}"; rsep=","; }
  [ -n "$m_nlm" ]  && { rtt="${rtt}${rsep}\"nlm\":${m_nlm}"; rsep=","; }
  [ -n "$m_yt" ]   && { rtt="${rtt}${rsep}\"yt\":${m_yt}"; rsep=","; }
  [ -n "$m_cdn" ]  && { rtt="${rtt}${rsep}\"cdn\":${m_cdn}"; rsep=","; }
  [ -n "$m_play" ] && { rtt="${rtt}${rsep}\"play\":${m_play}"; rsep=","; }
  [ -n "$m_srch" ] && { rtt="${rtt}${rsep}\"srch\":${m_srch}"; rsep=","; }
  if [ -n "$rtt" ]; then out="${out}${sep}\"rtt\":{${rtt}}"; sep=","; fi
  if [ "$ver" = "$PVER_INIT" ]; then
    local exj="" exsep=""
    add_ex() {
      case "$2" in ""|*--inspect*) return ;; esac
      exj="${exj}${exsep}\"$1\":\"$(json_esc "$2")\""; exsep=","
    }
    add_ex gem "$SVC_EX_GEM"; add_ex nlm "$SVC_EX_NLM"; add_ex yt "$SVC_EX_YT"; add_ex cdn "$SVC_EX_CDN"
    add_ex play "$SVC_EX_PLAY"; add_ex srch "$SVC_EX_SRCH"; add_ex trm "$SVC_EX_TRM"
    if [ -n "$exj" ]; then out="${out}${sep}\"ex\":{${exj}}"; fi
  fi
  printf '%s}' "$out"
}

PVER_INIT=4; [ "$V4_OK" -eq 0 ] && PVER_INIT=6

JSON="{\"v\":1,\"t\":${NOW_TS},\"m\":\"${RUN_MODE}\""
[ -n "$OS_NAME" ] && JSON="${JSON},\"os\":\"$(json_esc "$OS_NAME")\""
[ "$DETECTED_TUN" -eq 1 ] && JSON="${JSON},\"tun\":true"
[ "$HAS_EXPLICIT_PROXY" -eq 1 ] && JSON="${JSON},\"px\":true"
[ -n "$CN_DIRECT" ] && JSON="${JSON},\"cn\":\"${CN_DIRECT}\""
[ -n "$APPLE_CC" ] && JSON="${JSON},\"ap\":\"${APPLE_CC}\""
NET_J="{\"kind\":\"${NET_KIND}\",\"label\":\"$(json_esc "$NET_LABEL")\""
[ -n "$PASSIVE_TUN_NIC" ] && NET_J="${NET_J},\"nic\":\"$(json_esc "$PASSIVE_TUN_NIC")\""
JSON="${JSON},\"net\":${NET_J}}"

RT_J="" RT_SEP=""
add_rt() { [ -n "$2" ] && { RT_J="${RT_J}${RT_SEP}\"$1\":$2"; RT_SEP=","; }; }
if [ -n "$CN_DIRECT" ] || { [ "$RUN_MODE" = "proxy" ] && [ -n "$CN_RAW_IP" ] && [ -n "$CN_NOTE" ]; }; then
  add_rt cn "$(build_bucket_json "$CN_RAW_IP" "$( [ -n "$CN_DIRECT" ] && echo CN || echo INTL )" "" "" "$CN_MS" "$CN_NOTE")"
fi
add_rt def "$(build_bucket_json "$P_RAW_IP" "$P_CC" "" "" "$P_DEF_MS" "")"
[ -n "$P_GIP_RAW" ] && add_rt ggc "$(build_bucket_json "$P_GIP_RAW" "" "$P_CDN" "$(is_warp_ip "$P_GIP_RAW" && echo on || echo '')" "$P_CDN_MS" "")"
[ -n "$CF_IP" ]  && add_rt cf  "$(build_bucket_json "$CF_IP"  "$CF_LOC"  "$CF_COLO"  "$CF_WARP"  "$CF_MS"  "")"
[ -n "$OAI_IP" ] && add_rt oai "$(build_bucket_json "$OAI_IP" "$OAI_LOC" "$OAI_COLO" "$OAI_WARP" "$OAI_MS" "")"
[ -n "$CLD_IP" ] && add_rt cld "$(build_bucket_json "$CLD_IP" "$CLD_LOC" "$CLD_COLO" "$CLD_WARP" "$CLD_MS" "")"
[ -n "$RT_J" ] && JSON="${JSON},\"rt\":{${RT_J}}"
[ -n "$ALARMS_JSON" ] && JSON="${JSON},\"al\":[${ALARMS_JSON}]"
[ "$V4_OK" -eq 1 ] && JSON="${JSON},\"v4\":$(build_stack_json 4)"
[ "$V6_OK" -eq 1 ] && JSON="${JSON},\"v6\":$(build_stack_json 6)"
JSON="${JSON}}"

clear_step
if [ "$OPT_JSON" -eq 1 ]; then
  printf '%s\n' "$JSON"
  exit 0
fi

# ---------------------------------------------------------------------------
# Layer 2 Opt-In Whitelist Controller Auto-Discovery & 15-Domain Audit
# ---------------------------------------------------------------------------
DID_INSPECT=0
LOCAL_RULES_FILE="$TMPDIR_GR/local_rules.txt"
: > "$LOCAL_RULES_FILE"

ctrl_get() {
  local ep="$1" path="$2" sec="$3" tmo="${4:-2}"
  local url="${ep%/}${path}" sock=""
  case "$ep" in
    /*) sock="$ep"; url="http://localhost${path}" ;;
    unix:*) sock="${ep#unix:}"; url="http://localhost${path}" ;;
  esac
  if [ -n "$sock" ]; then
    if [ ! -S "$sock" ]; then printf '\n__HTTP__000\n'; return; fi
    if [ -n "$sec" ]; then curl -sS --unix-socket "$sock" --connect-timeout 1 --max-time "$tmo" -H "Authorization: Bearer ${sec}" -w '\n__HTTP__%{http_code}' "$url" 2>/dev/null || printf '\n__HTTP__000\n'
    else curl -sS --unix-socket "$sock" --connect-timeout 1 --max-time "$tmo" -w '\n__HTTP__%{http_code}' "$url" 2>/dev/null || printf '\n__HTTP__000\n'; fi
  else
    if [ -n "$sec" ]; then curl -sS --noproxy '*' --connect-timeout 1 --max-time "$tmo" -H "Authorization: Bearer ${sec}" -w '\n__HTTP__%{http_code}' "$url" 2>/dev/null || printf '\n__HTTP__000\n'
    else curl -sS --noproxy '*' --connect-timeout 1 --max-time "$tmo" -w '\n__HTTP__%{http_code}' "$url" 2>/dev/null || printf '\n__HTTP__000\n'; fi
  fi
}

run_local_controller_audit() {
  DID_INSPECT=1
  : > "$LOCAL_RULES_FILE"
  box_rule mid
  box_line "[03] 本地只读控制 API · 15 域分流一致性审计 (仅本屏展示，默认绝不入图/分享链)" "$C_CYN"

  local ep="" lbl="" code="000" body="" auth_ep="" auth_lbl=""
  if [ -n "$OPT_CONTROLLER" ]; then
    ep="$OPT_CONTROLLER"; lbl="显式控制口"
    local raw; raw=$(ctrl_get "$ep" "/version" "$OPT_SECRET" 2)
    code=$(printf '%s\n' "$raw" | tail -n 1 | sed -n 's/.*__HTTP__\([0-9]*\).*/\1/p')
    body=$(printf '%s\n' "$raw" | sed '$d')
  else
    for entry in \
      "/tmp/verge/verge-mihomo.sock|Clash Verge Rev" \
      "/tmp/mihomo-party.sock|Mihomo Party" \
      "/tmp/verge-mihomo.sock|Clash Verge" \
      "/tmp/clash-nyanpasu.sock|Clash Nyanpasu" \
      "http://127.0.0.1:9090|Mihomo / sing-box TCP" \
      "http://127.0.0.1:9097|Clash Verge TCP" \
      "http://127.0.0.1:9095|本地控制口 TCP"; do
      local ce="${entry%%|*}" cl="${entry#*|}"
      local raw c
      raw=$(ctrl_get "$ce" "/version" "$OPT_SECRET" 1)
      c=$(printf '%s\n' "$raw" | tail -n 1 | sed -n 's/.*__HTTP__\([0-9]*\).*/\1/p')
      if [ "$c" = "200" ]; then
        ep="$ce"; lbl="$cl"; code="200"; body=$(printf '%s\n' "$raw" | sed '$d'); break
      elif { [ "$c" = "401" ] || [ "$c" = "403" ]; } && [ -z "$auth_ep" ]; then
        auth_ep="$ce"; auth_lbl="$cl"
      fi
    done
    if [ -z "$ep" ] && [ -n "$auth_ep" ]; then ep="$auth_ep"; lbl="$auth_lbl"; code="401"; fi
  fi

  if [ -z "$ep" ]; then
    box_line "[INFO] 未在白名单控制口检测到 Mihomo/sing-box (已保底保留上方 6 桶黑盒分流图)" "$C_YLW"
    return
  fi
  if [ "$code" = "401" ] || [ "$code" = "403" ]; then
    if [ "$IS_INTERACTIVE" -eq 1 ] && [ -z "$OPT_SECRET" ]; then
      box_line "[INFO] 已发现 ${ep} (${lbl})，需要控制密钥 (HTTP ${code})" "$C_YLW"
      printf '请输入该控制口 Secret (直接回车跳过): ' >/dev/tty
      IFS= read -r OPT_SECRET </dev/tty || OPT_SECRET=""
      if [ -n "$OPT_SECRET" ]; then
        local raw2; raw2=$(ctrl_get "$ep" "/version" "$OPT_SECRET" 2)
        code=$(printf '%s\n' "$raw2" | tail -n 1 | sed -n 's/.*__HTTP__\([0-9]*\).*/\1/p')
        body=$(printf '%s\n' "$raw2" | sed '$d')
      fi
    fi
    if [ "$code" != "200" ]; then
      box_line "[INFO] 控制口 ${ep} 返回 HTTP ${code}，请传 --secret 后重试" "$C_YLW"
      return
    fi
  fi
  if [ "$code" != "200" ]; then
    box_line "[INFO] 无法连接控制口 ${ep} (HTTP=${code})" "$C_YLW"
    return
  fi

  local cver; cver=$(json_str "$body" "version")
  box_line "已自动识别: ${lbl} · ${ep}${cver:+ · ${cver}}" "$C_DIM"

  # Launch 15 lightweight probes concurrently so Mihomo/sing-box records active connections
  local pids=""
  for u in \
    "https://gemini.google.com/app" \
    "https://aistudio.google.com/" \
    "https://notebooklm.google.com/" \
    "https://labs.google/" \
    "https://generativelanguage.googleapis.com/" \
    "https://alkalimakersuite-pa.clients6.google.com/" \
    "https://oauth2.googleapis.com/" \
    "https://accounts.google.com/" \
    "https://www.google.com/search?q=curl&ie=UTF-8" \
    "https://play.google.com/" \
    "https://www.youtube.com/premium" \
    "https://redirector.googlevideo.com/report_mapping" \
    "https://chatgpt.com/cdn-cgi/trace" \
    "https://claude.ai/cdn-cgi/trace" \
    "https://v4.ident.me/json"; do
    if [ -n "$EFFECTIVE_PROXY" ]; then
      curl -sS --max-time 4 --limit-rate 50 -A "$UA" -x "$EFFECTIVE_PROXY" -o /dev/null "$u" >/dev/null 2>&1 &
    else
      curl -sS --max-time 4 --limit-rate 50 -A "$UA" -o /dev/null "$u" >/dev/null 2>&1 &
    fi
    pids="$pids $!"
  done
  sleep 1
  local c_raw c_code c_json
  c_raw=$(ctrl_get "$ep" "/connections" "$OPT_SECRET" 3)
  for pid in $pids; do kill "$pid" >/dev/null 2>&1 || true; done
  wait >/dev/null 2>&1 || true

  c_code=$(printf '%s\n' "$c_raw" | tail -n 1 | sed -n 's/.*__HTTP__\([0-9]*\).*/\1/p')
  c_json=$(printf '%s\n' "$c_raw" | sed '$d')
  if [ "$c_code" != "200" ]; then
    box_line "[INFO] 读取 /connections 失败 (HTTP=${c_code})" "$C_YLW"
    return
  fi

  local gem_top="" ai_mismatch=""
  local raw_hits="$TMPDIR_GR/ctrl_hits.txt"
  local missed_list=""
  : > "$raw_hits"
  for dom in \
    gemini.google.com aistudio.google.com notebooklm.google.com labs.google generativelanguage.googleapis.com \
    alkalimakersuite-pa.clients6.google.com oauth2.googleapis.com accounts.google.com \
    www.google.com play.google.com policies.google.com www.youtube.com redirector.googlevideo.com \
    chatgpt.com claude.ai v4.ident.me; do
    local chunk
    chunk=$(printf '%s' "$c_json" | sed 's/{"id":/\n{"id":/g' | grep "\"${dom}\"" | tail -n 1 || true)
    if [ -n "$chunk" ]; then
      local rt rp rlbl ch_raw ch_rev top_g leaf_n mis=0
      rt=$(printf '%s' "$chunk" | sed -n 's/.*"rule":"\([^"]*\)".*/\1/p')
      rp=$(printf '%s' "$chunk" | sed -n 's/.*"rulePayload":"\([^"]*\)".*/\1/p')
      rlbl="${rt:-?}"; [ -n "$rp" ] && rlbl="${rlbl}(${rp})"
      ch_raw=$(printf '%s' "$chunk" | sed -n 's/.*"chains":\[\([^]]*\)\].*/\1/p' | tr -d '"')
      ch_rev=$(printf '%s' "$ch_raw" | awk -F',' '{for(i=NF;i>=1;i--){printf "%s%s", $i, (i>1?" -> ":"")}}')
      leaf_n=$(printf '%s' "$ch_raw" | awk -F',' '{print $1}')
      [ -n "$leaf_n" ] && printf '%s|%s\n' "$dom" "$leaf_n" >> "$TMPDIR_GR/host_leaf.txt"
      top_g=$(printf '%s' "$ch_raw" | awk -F',' '{print $NF}')
      if [ "$dom" = "gemini.google.com" ]; then gem_top="$top_g"; fi
      case "$dom" in
        gemini.google.com|aistudio.google.com|notebooklm.google.com|labs.google|generativelanguage.googleapis.com|alkalimakersuite-pa.clients6.google.com|oauth2.googleapis.com|accounts.google.com)
          if [ -n "$gem_top" ] && [ -n "$top_g" ] && [ "$top_g" != "$gem_top" ]; then
            mis=1
            ai_mismatch="${ai_mismatch:+${ai_mismatch}; }${dom} -> ${top_g}"
          fi ;;
      esac
      printf '%s|%s|%s\n' "$dom" "$rlbl" "$ch_rev" >> "$LOCAL_RULES_FILE"
      local rdisp="$rlbl"
      if [ "$rlbl" = "Domain(${dom})" ]; then rdisp="Domain"; fi
      if [ "$rlbl" = "DomainSuffix(${dom})" ]; then rdisp="DomainSuffix"; fi
      printf '%s|%s|%s|%d\n' "$ch_rev" "$rdisp" "$dom" "$mis" >> "$raw_hits"
    else
      missed_list="${missed_list:+${missed_list}, }${dom}"
    fi
  done

  # Group by full policy chain (zero truncation, auto-wrapped full domain lists)
  local inner_w=$((BOX_W - 4))
  awk -F'|' -v maxw="$inner_w" '
  {
    ch=$1; rl=$2; dm=$3; ms=$4+0;
    if (!(ch in cidx)) { cn++; cidx[ch]=cn; corder[cn]=ch; ccnt[ch]=0; cmis[ch]=0; }
    ccnt[ch]++; if (ms==1) cmis[ch]=1;
    rk=ch "\034" rl;
    if (!(rk in rseen)) { rseen[rk]=1; rlist[ch]=(rlist[ch]=="" ? rl : rlist[ch] "\034" rl); }
    doms[rk]=(doms[rk]=="" ? dm : doms[rk] ", " dm);
  }
  END {
    for (pass=1; pass<=2; pass++) {
      for (i=1; i<=cn; i++) {
        ch=corder[i];
        if ((pass==1 && cmis[ch]==0) || (pass==2 && cmis[ch]==1)) continue;
        hdr=sprintf("[链路] %s (%d 域)%s", ch, ccnt[ch], (cmis[ch]==1 ? " [! 分裂]" : ""));
        printf "H|%d|%s\n", cmis[ch], hdr;
        n=split(rlist[ch], arr, "\034");
        for (j=1; j<=n; j++) {
          rl=arr[j]; rk=ch "\034" rl;
          printf "R|%d|  - %s: %s\n", cmis[ch], rl, doms[rk];
        }
      }
    }
  }' "$raw_hits" | while IFS='|' read -r kind mis line; do
    local col="$C_WHT"
    if [ "$mis" = "1" ]; then col="$C_YLW"; elif [ "$kind" = "R" ]; then col=""; fi
    # Wrap cleanly on comma boundaries if longer than inner box width
    if [ "${#line}" -gt $((inner_w - 4)) ]; then
      printf '%s' "$line" | fold -s -w $((inner_w - 6)) | awk 'NR==1{print; next}{print "      " $0}' | while IFS= read -r wline; do
        box_line "$wline" "$col"
      done
    else
      box_line "$line" "$col"
    fi
  done

  if [ -n "$missed_list" ]; then
    box_line "  未捕获: ${missed_list}" "$C_DIM"
  fi

  if [ -n "$ai_mismatch" ]; then
    box_line "[!] Google AI 链路分裂! gemini.google.com 走 [${gem_top}]，但 ${ai_mismatch}" "$C_YLW"
  elif [ -n "$gem_top" ]; then
    box_line "[OK] Google AI 核心 + API + 鉴权域名全部收敛在同一策略组: ${gem_top}" "$C_GRN"
  fi
}

# ---------------------------------------------------------------------------
# Terminal Swiss-Industrial Card Rendering
# ---------------------------------------------------------------------------
UTC_TIME=$(date -u +"%Y-%m-%d %H:%M UTC" 2>/dev/null || echo "")

cell_text() {
  local kind="$1" v="$2"
  eval "local gem=\$V${v}_GEM nlm=\$V${v}_NLM yt=\$V${v}_YT ytg=\$V${v}_YTG cdn=\$V${v}_CDN cdnu=\$V${v}_CDNU ip=\$V${v}_IP gip=\$V${v}_GIP play=\$V${v}_PLAY sdom=\$V${v}_SDOM scap=\$V${v}_SCAP trm=\$V${v}_TRM ent=\$V${v}_ENT"
  local okp="✓ " wnp="! " nop="✕ "
  if [ "$OPT_ASCII" -eq 1 ]; then okp="[OK] "; wnp="[!] "; nop="[X] "; fi
  case "$kind" in
    gem)    [ -z "$gem" ] && echo "N/A" || { is_cn_or_restricted "$gem" && echo "${nop}BLOCKED [$gem]" || echo "${okp}OK [$gem]"; } ;;
    nlm)    case "$nlm" in ok) echo "${okp}OK (301)" ;; unavail) echo "${nop}BLOCKED (302)" ;; *) echo "N/A" ;; esac ;;
    yt)     case "$yt" in ok) echo "${okp}OK [${ytg:-OK}]" ;; cn) echo "${nop}CN_DRIFT" ;; noprem) echo "${nop}NO_PREM (GL=${ytg:-?})" ;; *) echo "N/A" ;; esac ;;
    cdn)    if [ -z "$cdn" ]; then echo "N/A"; else local t="$cdn"; [ "$cdnu" -eq 1 ] && t="${t} [u]"; echo "${okp}${t}"; fi ;;
    play)   [ -z "$play" ] && echo "N/A" || { is_cn_or_restricted "$play" && echo "${nop}$play [CN]" || echo "${okp}$play"; } ;;
    search) if [ "$scap" = "captcha" ]; then echo "${wnp}CAPTCHA (/sorry)"; elif [ "$sdom" = "hkredirect" ] || [ "$scap" = "hk" ]; then echo "${nop}HK_REDIRECT (.hk)"; elif [ -n "$sdom" ] || [ "$scap" = "ok" ]; then echo "${okp}${sdom:-OK} (Clean)"; else echo "N/A"; fi ;;
    terms)  if [ -z "$trm" ]; then echo "N/A"; elif is_cn_or_restricted "$trm"; then echo "${nop}$trm [CN]"; elif [ "$ent" = "Google Ireland Limited" ]; then echo "${wnp}$trm (EEA)"; else echo "${okp}$trm"; fi ;;
  esac
}

cell_tone() {
  local kind="$1" v="$2"
  eval "local gem=\$V${v}_GEM nlm=\$V${v}_NLM yt=\$V${v}_YT ip=\$V${v}_IP gip=\$V${v}_GIP cdn=\$V${v}_CDN play=\$V${v}_PLAY sdom=\$V${v}_SDOM scap=\$V${v}_SCAP trm=\$V${v}_TRM ent=\$V${v}_ENT"
  case "$kind" in
    gem)    [ -z "$gem" ] && echo "muted" || { is_cn_or_restricted "$gem" && echo "leak" || echo "ok"; } ;;
    nlm)    case "$nlm" in ok) echo "ok" ;; unavail) echo "leak" ;; *) echo "muted" ;; esac ;;
    yt)     case "$yt" in ok) echo "ok" ;; cn|noprem) echo "leak" ;; *) echo "muted" ;; esac ;;
    cdn)    [ -z "$cdn" ] && echo "muted" || { [ -n "$ip" ] && [ -n "$gip" ] && [ "$ip" != "$gip" ] && echo "diff" || echo "ok"; } ;;
    play)   [ -z "$play" ] && echo "muted" || { is_cn_or_restricted "$play" && echo "leak" || echo "ok"; } ;;
    search) if [ "$scap" = "captcha" ]; then echo "diff"; elif [ "$sdom" = "hkredirect" ] || [ "$scap" = "hk" ]; then echo "leak"; elif [ -n "$sdom" ] || [ "$scap" = "ok" ]; then echo "ok"; else echo "muted"; fi ;;
    terms)  if [ -z "$trm" ]; then echo "muted"; elif is_cn_or_restricted "$trm"; then echo "leak"; elif [ "$ent" = "Google Ireland Limited" ]; then echo "diff"; else echo "ok"; fi ;;
  esac
}

tone_col() {
  case "$1" in ok) printf '%s' "$C_GRN" ;; diff) printf '%s' "$C_YLW" ;; leak) printf '%s' "$C_RED" ;; *) printf '%s' "$C_DIM" ;; esac
}

box_rule top
box_line "G-ROUTE v3 // Google 生态送中与分流体检卡  [${NET_LABEL}] ${UTC_TIME}" "$C_CYN"
box_rule mid
box_line "结论  [${V_TAG}] ${V_TEXT}" "$V_COL"
box_line "三方对照: 公开库=${P_CC:-?}  |  Apple=${APPLE_CC:-?}  |  Google 实测=${P_GEM:-?}  |  DNS=${P_DNS:-skip}" "$C_DIM"

# [01] 6-Bucket Split-Route Topology Radar
box_rule mid
box_line "[01] 6 桶分流拓扑雷达 (自动聚类: ${OV_SLOTS} 路海外出口$( [ -n "$CN_DIRECT" ] && echo ' + 国内直连' ))" "$C_CYN"
SW=11; IPW=40; MSW=7
if [ "$OPT_COMPACT" -eq 1 ]; then IPW=18; fi
BKW=$((BOX_W - 4 - SW - IPW - MSW - 3))
printf '%b%s%b %b%s %s %s %s%b %b%s%b\n' \
  "$C_DIM" "$B_V" "$C_RST" "$C_WHT" \
  "$(pad_disp '出口槽' "$SW")" "$(pad_disp '出口 IP / 归属' "$IPW")" "$(pad_disp '命中业务桶' "$BKW")" "$(pad_disp 'RTT' "$MSW")" \
  "$C_RST" "$C_DIM" "$B_V" "$C_RST"

while IFS='|' read -r cl_slot cl_tone cl_ip cl_org cl_bkt cl_ms _w _cn; do
  ccol=$(exit_term_col "$cl_slot")
  if [ "$cl_tone" = "leak" ]; then ccol="$C_RED"; fi
  msd="--"; [ -n "$cl_ms" ] && msd="${cl_ms}ms"
  printf '%b%s%b %b%s%b %s %b%s%b %b%s%b %b%s%b\n' \
    "$C_DIM" "$B_V" "$C_RST" \
    "$ccol" "$(pad_disp "[${cl_slot}]" "$SW")" "$C_RST" \
    "$(pad_disp "${cl_ip} ${cl_org}" "$IPW")" \
    "$ccol" "$(pad_disp "$cl_bkt" "$BKW")" "$C_RST" \
    "$C_DIM" "$(pad_disp "$msd" "$MSW")" "$C_RST" \
    "$C_DIM" "$B_V" "$C_RST"
done < "$CLUSTERS_FILE"

while IFS='|' read -r atone atxt; do
  [ -n "$atxt" ] || continue
  box_line "$atxt" "$(tone_col "$atone")"
done < "$ALARMS_TXT"

# [02] Google 6-Way Ground Truth Matrix
box_rule mid
PVER=4; [ "$V4_OK" -eq 0 ] && PVER=6
if [ "$V4_OK" -eq 1 ] && [ "$V6_OK" -eq 1 ]; then
  box_line "[02] Google 生态 6 路真值矩阵 (IPv4 + IPv6 双栈)" "$C_CYN"
  NW=19; C4W=$(( (BOX_W - 4 - NW - 2) / 2 )); C6W=$(( BOX_W - 4 - NW - C4W - 2 ))
  printf '%b%s%b %b%s %s %s%b %b%s%b\n' \
    "$C_DIM" "$B_V" "$C_RST" "$C_WHT" "$(pad_disp '服务维度' "$NW")" "$(pad_disp "IPv4 (${V4_IP})" "$C4W")" "$(pad_disp "IPv6 (${V6_IP})" "$C6W")" "$C_RST" "$C_DIM" "$B_V" "$C_RST"
  for item in "gem|Gemini (Boq)" "nlm|NotebookLM (1-RTT)" "yt|YouTube Premium" "cdn|YouTube GGC CDN" "play|Google Play" "search|Google Search" "terms|Google Terms"; do
    k="${item%%|*}"; nm="${item#*|}"
    t4=$(cell_text "$k" 4); c4=$(tone_col "$(cell_tone "$k" 4)")
    t6=$(cell_text "$k" 6); c6=$(tone_col "$(cell_tone "$k" 6)")
    printf '%b%s%b %s %b%s%b %b%s%b %b%s%b\n' \
      "$C_DIM" "$B_V" "$C_RST" "$(pad_disp "$nm" "$NW")" \
      "$c4" "$(pad_disp "$t4" "$C4W")" "$C_RST" "$c6" "$(pad_disp "$t6" "$C6W")" "$C_RST" "$C_DIM" "$B_V" "$C_RST"
  done
else
  ST_HDR="IPv${PVER} · 出口 A (${P_IP})"
  [ "$OV_SLOTS" -gt 1 ] && ST_HDR="IPv${PVER} · 各服务实测出口见右列"
  box_line "[02] Google 生态 6 路真值矩阵 (${ST_HDR})" "$C_CYN"
  NW=19; VW=24; [ "$OPT_COMPACT" -eq 1 ] && VW=20; MW=7; NTW=$((BOX_W - 4 - NW - VW - MW - 3))
  printf '%b%s%b %b%s %s %s %s%b %b%s%b\n' \
    "$C_DIM" "$B_V" "$C_RST" "$C_WHT" "$(pad_disp '服务维度' "$NW")" "$(pad_disp '实测结果' "$VW")" "$(pad_disp 'RTT' "$MW")" "$(pad_disp '实测出口 (匿名槽位)' "$NTW")" "$C_RST" "$C_DIM" "$B_V" "$C_RST"
  for item in \
    "gem|Gemini (Boq)|GEM|GEM" \
    "nlm|NotebookLM (1-RTT)|NLM|NLM" \
    "yt|YouTube Premium|YT|YT" \
    "cdn|YouTube GGC CDN|CDN|CDN" \
    "play|Google Play|PLAY|PLAY" \
    "search|Google Search|SRCH|SRCH" \
    "terms|Google Terms||TRM"; do
    k=$(printf '%s' "$item" | cut -d'|' -f1)
    nm=$(printf '%s' "$item" | cut -d'|' -f2)
    mk=$(printf '%s' "$item" | cut -d'|' -f3)
    ek=$(printf '%s' "$item" | cut -d'|' -f4)
    tv=$(cell_text "$k" "$PVER"); cv=$(tone_col "$(cell_tone "$k" "$PVER")")
    eval "exd=\$SVC_EX_${ek}"
    [ -z "$exd" ] && exd="--"
    excol=$(exit_term_col "$exd")
    case "$exd" in 独立*|多出口*) excol="$C_YLW" ;; esac
    msv="--"
    if [ -n "$mk" ]; then
      eval "mraw=\$V${PVER}_${mk}_MS"
      [ -n "$mraw" ] && msv="${mraw}ms"
    fi
    printf '%b%s%b %b%s%b %b%s%b %b%s%b %b%s%b %b%s%b\n' \
      "$C_DIM" "$B_V" "$C_RST" "$C_WHT" "$(pad_disp "$nm" "$NW")" "$C_RST" \
      "$cv" "$(pad_disp "$tv" "$VW")" "$C_RST" \
      "$C_DIM" "$(pad_disp "$msv" "$MW")" "$C_RST" \
      "$excol" "$(pad_disp "$exd" "$NTW")" "$C_RST" \
      "$C_DIM" "$B_V" "$C_RST"
  done
fi

if [ "$OPT_INSPECT" -eq 1 ] || [ -n "$OPT_CONTROLLER" ]; then
  run_local_controller_audit
fi
box_rule bot

# ---------------------------------------------------------------------------
# Zero-Dependency Pure-Text Offline SVG Exporter
# ---------------------------------------------------------------------------
export_local_svg() {
  local out_path="$1"
  if [ -z "$out_path" ]; then
    out_path="./g-route-$(date +%Y%m%d-%H%M%S).svg"
  fi
  local bg="#f7f6f1" bgsub="#efede6" fg="#1b1d24" fgm="#5b5e68" fgf="#858892" rule="#ccc9c0" str="#242731"
  local cok="#146c43" cokb="#dcf4e6" cdiff="#9a5b0c" cdiffb="#fae8c8" cleak="#b42318" cleakb="#fbdad7"
  local excn="#0f766e" excnb="#d6f5f0" exa="#1d4ed8" exab="#dbeafe" exb="#c2410c" exbb="#ffedd5" exc="#6d28d9" excb="#ede9fe" exd_c="#be185d" exdb="#fce7f3"
  if [ "$OPT_THEME" = "dark" ]; then
    bg="#16181e"; bgsub="#1e2129"; fg="#eceae3"; fgm="#a2a5b0"; fgf="#727684"; rule="#323642"; str="#dcdad2"
    cok="#56c288"; cokb="#193025"; cdiff="#e0a546"; cdiffb="#302719"; cleak="#eb6f63"; cleakb="#331d1c"
    excn="#2dd4bf"; excnb="#133432"; exa="#60a5fa"; exab="#172554"; exb="#fb923c"; exbb="#431407"; exc="#a78bfa"; excb="#2e1065"; exd_c="#f472b6"; exdb="#500724"
  fi
  svg_fg() { case "$1" in leak) echo "$cleak" ;; diff) echo "$cdiff" ;; ok) echo "$cok" ;; *) echo "$fgm" ;; esac; }
  svg_bg() { case "$1" in leak) echo "$cleakb" ;; diff) echo "$cdiffb" ;; ok) echo "$cokb" ;; *) echo "$bgsub" ;; esac; }
  svg_ex_fg() { case "$1" in 直连*|国内*) echo "$excn" ;; "出口 A"*) echo "$exa" ;; "出口 B"*) echo "$exb" ;; "出口 C"*) echo "$exc" ;; "出口 "*) echo "$exd_c" ;; *) echo "$fgm" ;; esac; }
  svg_ex_bg() { case "$1" in 直连*|国内*) echo "$excnb" ;; "出口 A"*) echo "$exab" ;; "出口 B"*) echo "$exbb" ;; "出口 C"*) echo "$excb" ;; "出口 "*) echo "$exdb" ;; *) echo "$bgsub" ;; esac; }

  local cl_n al_n lr_n inc_lr=0
  cl_n=$(wc -l < "$CLUSTERS_FILE" | tr -d ' ')
  al_n=$(wc -l < "$ALARMS_TXT" | tr -d ' ')
  lr_n=$(wc -l < "$LOCAL_RULES_FILE" | tr -d ' ')
  if [ "$OPT_WITH_RULES" -eq 1 ] && [ "$lr_n" -gt 0 ]; then inc_lr=1; fi

  local sw=920 pad=28 inner=864
  local cl_h=$((34 + cl_n * 30 + al_n * 22 + 12))
  local mx_h=$((34 + 7 * 34 + 10))
  local lr_h=0; [ "$inc_lr" -eq 1 ] && lr_h=$((36 + lr_n * 24 + 16))
  local sh=$((pad + 52 + 86 + cl_h + mx_h + lr_h + 44 + pad))
  local vfg vbg; vfg=$(svg_fg "$V_TONE"); vbg=$(svg_bg "$V_TONE")
  local y=$pad

  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n' "$sw" "$sh" "$sw" "$sh"
    printf '<defs><style>.m{font-family:ui-monospace,"Cascadia Mono","SF Mono",Consolas,"Noto Sans Mono CJK SC",monospace}.s{font-family:"PingFang SC","Microsoft YaHei","Noto Sans SC",system-ui,sans-serif}</style>'
    printf '<clipPath id="cc"><rect x="%d" y="0" width="%d" height="%d"/></clipPath></defs>\n' "$((pad+14))" "$((inner-28))" "$sh"
    printf '<rect x="0" y="0" width="%d" height="%d" fill="%s"/>\n' "$sw" "$sh" "$bg"
    printf '<rect x="%d" y="%d" width="%d" height="%d" fill="%s" stroke="%s" stroke-width="2"/>\n' "$pad" "$pad" "$inner" "$((sh - pad*2))" "$bg" "$str"

    # Header
    printf '<rect x="%d" y="%d" width="%d" height="51" fill="%s"/>\n' "$((pad+1))" "$((y+1))" "$((inner-2))" "$bgsub"
    printf '<text x="%d" y="%d" class="m" font-size="14" font-weight="700" fill="%s">G-ROUTE v3 // GOOGLE 生态送中与分流体检卡</text>\n' "$((pad+18))" "$((y+31))" "$fg"
    printf '<text x="%d" y="%d" class="m" font-size="11.5" text-anchor="end" fill="%s">%s</text>\n' "$((pad+inner-18))" "$((y+31))" "$fgm" "$(xml_esc "${NET_LABEL}  ·  ${UTC_TIME}")"
    y=$((y + 52))
    printf '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1"/>\n' "$pad" "$y" "$((pad+inner))" "$y" "$str"

    # Verdict
    local tw=$(( (${#V_TAG} + 4) * 9 )); [ "$tw" -lt 86 ] && tw=86
    printf '<rect x="%d" y="%d" width="%d" height="26" fill="%s" stroke="%s" stroke-width="1"/>\n' "$((pad+18))" "$((y+16))" "$tw" "$vbg" "$vfg"
    printf '<text x="%d" y="%d" class="m" font-size="12" font-weight="700" text-anchor="middle" fill="%s">[%s]</text>\n' "$((pad+18 + tw/2))" "$((y+33))" "$vfg" "$V_TAG"
    printf '<text x="%d" y="%d" class="s" font-size="15" font-weight="700" fill="%s" clip-path="url(#cc)">%s</text>\n' "$((pad+28+tw))" "$((y+34))" "$fg" "$(xml_esc "$V_TEXT")"
    printf '<text x="%d" y="%d" class="m" font-size="11.5" fill="%s" clip-path="url(#cc)">%s</text>\n' "$((pad+18))" "$((y+66))" "$fgm" "$(xml_esc "三方对照: 公开库=${P_CC:-?}  |  Apple=${APPLE_CC:-?}  |  Google 实测=${P_GEM:-?}  |  通用出口: ${P_IP} (AS${P_ASN:-?} ${P_ORG:-Unknown})")"
    y=$((y + 86))
    printf '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1"/>\n' "$pad" "$y" "$((pad+inner))" "$y" "$str"

    # [01] 6-Bucket Radar
    printf '<rect x="%d" y="%d" width="%d" height="31" fill="%s"/>\n' "$((pad+1))" "$((y+1))" "$((inner-2))" "$bgsub"
    printf '<text x="%d" y="%d" class="m" font-size="11.5" font-weight="700" fill="%s">[01] 6 桶分流拓扑雷达 · 自动聚类 (%s 路海外出口)</text>\n' "$((pad+18))" "$((y+21))" "$fgm" "$OV_SLOTS"
    printf '<text x="%d" y="%d" class="m" font-size="11" text-anchor="end" fill="%s">RTT</text>\n' "$((pad+inner-18))" "$((y+21))" "$fgf"
    y=$((y + 32))
    while IFS='|' read -r cs ct cip corg cbkt cms _w _cn; do
      printf '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1"/>\n' "$pad" "$y" "$((pad+inner))" "$y" "$rule"
      local sc sbg; sc=$(svg_ex_fg "$cs"); sbg=$(svg_ex_bg "$cs")
      if [ "$ct" = "leak" ]; then sc="$cleak"; sbg="$cleakb"; fi
      printf '<rect x="%d" y="%d" width="74" height="20" fill="%s" stroke="%s" stroke-width="1"/>\n' "$((pad+18))" "$((y+5))" "$sbg" "$sc"
      printf '<text x="%d" y="%d" class="m" font-size="11" font-weight="700" text-anchor="middle" fill="%s">%s</text>\n' "$((pad+55))" "$((y+19))" "$sc" "$(xml_esc "$cs")"
      printf '<text x="%d" y="%d" class="m" font-size="11.2" fill="%s">%s</text>\n' "$((pad+104))" "$((y+19))" "$fg" "$(xml_esc "$(pad_disp "${cip} · ${corg}" 49)")"
      printf '<text x="%d" y="%d" class="s" font-size="11.5" fill="%s">%s</text>\n' "$((pad+492))" "$((y+19))" "$fgm" "$(xml_esc "$(pad_disp "$cbkt" 38)")"
      local mstr="--"; [ -n "$cms" ] && mstr="${cms} ms"
      printf '<text x="%d" y="%d" class="m" font-size="11" text-anchor="end" fill="%s">%s</text>\n' "$((pad+inner-18))" "$((y+19))" "$fgf" "$mstr"
      y=$((y + 30))
    done < "$CLUSTERS_FILE"
    while IFS='|' read -r atone atxt; do
      [ -n "$atxt" ] || continue
      printf '<text x="%d" y="%d" class="s" font-size="11.5" fill="%s" clip-path="url(#cc)">%s</text>\n' "$((pad+18))" "$((y+15))" "$(svg_fg "$atone")" "$(xml_esc "$atxt")"
      y=$((y + 22))
    done < "$ALARMS_TXT"
    y=$((y + 14))
    printf '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1"/>\n' "$pad" "$y" "$((pad+inner))" "$y" "$str"

    # [02] Google 6-Way Matrix
    printf '<rect x="%d" y="%d" width="%d" height="31" fill="%s"/>\n' "$((pad+1))" "$((y+1))" "$((inner-2))" "$bgsub"
    printf '<text x="%d" y="%d" class="m" font-size="11.5" font-weight="700" fill="%s">[02] GOOGLE 生态 6 路真值矩阵</text>\n' "$((pad+18))" "$((y+21))" "$fgm"
    if [ "$V4_OK" -eq 1 ] && [ "$V6_OK" -eq 1 ]; then
      printf '<text x="%d" y="%d" class="m" font-size="11" fill="%s">IPv4 (%s)</text>\n' "$((pad+270))" "$((y+21))" "$fgm" "$(xml_esc "$V4_IP")"
      printf '<text x="%d" y="%d" class="m" font-size="11" fill="%s">IPv6 (%s)</text>\n' "$((pad+560))" "$((y+21))" "$fgm" "$(xml_esc "$V6_IP")"
    else
      printf '<text x="%d" y="%d" class="m" font-size="11" fill="%s">实测结论</text>\n' "$((pad+244))" "$((y+21))" "$fgm"
      printf '<text x="%d" y="%d" class="m" font-size="11" fill="%s">实测出口 (匿名槽位)</text>\n' "$((pad+474))" "$((y+21))" "$fgm"
      printf '<text x="%d" y="%d" class="m" font-size="11" text-anchor="end" fill="%s">RTT</text>\n' "$((pad+inner-18))" "$((y+21))" "$fgf"
    fi
    y=$((y + 32))

    for item in \
      "gem|Gemini (Boq)|GEM|GEM" \
      "nlm|NotebookLM (1-RTT)|NLM|NLM" \
      "yt|YouTube Premium|YT|YT" \
      "cdn|YouTube GGC CDN|CDN|CDN" \
      "play|Google Play|PLAY|PLAY" \
      "search|Google Search|SRCH|SRCH" \
      "terms|Google Terms||TRM"; do
      local k nm mk ek exd
      k=$(printf '%s' "$item" | cut -d'|' -f1); nm=$(printf '%s' "$item" | cut -d'|' -f2)
      mk=$(printf '%s' "$item" | cut -d'|' -f3); ek=$(printf '%s' "$item" | cut -d'|' -f4)
      eval "exd=\$SVC_EX_${ek}"; [ -z "$exd" ] && exd="--"
      printf '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1"/>\n' "$pad" "$y" "$((pad+inner))" "$y" "$rule"
      printf '<text x="%d" y="%d" class="s" font-size="12.5" font-weight="600" fill="%s">%s</text>\n' "$((pad+18))" "$((y+21))" "$fg" "$(xml_esc "$nm")"
      if [ "$V4_OK" -eq 1 ] && [ "$V6_OK" -eq 1 ]; then
        printf '<text x="%d" y="%d" class="m" font-size="12" font-weight="600" fill="%s">%s</text>\n' "$((pad+270))" "$((y+21))" "$(svg_fg "$(cell_tone "$k" 4)")" "$(xml_esc "$(cell_text "$k" 4)")"
        printf '<text x="%d" y="%d" class="m" font-size="12" font-weight="600" fill="%s">%s</text>\n' "$((pad+560))" "$((y+21))" "$(svg_fg "$(cell_tone "$k" 6)")" "$(xml_esc "$(cell_text "$k" 6)")"
      else
        local mstr="--" ctone ctxt cfg cbg
        if [ -n "$mk" ]; then eval "local mr=\$V${PVER}_${mk}_MS"; [ -n "$mr" ] && mstr="${mr}ms"; fi
        ctone=$(cell_tone "$k" "$PVER"); ctxt=$(cell_text "$k" "$PVER")
        cfg=$(svg_fg "$ctone"); cbg=$(svg_bg "$ctone")
        printf '<rect x="%d" y="%d" width="196" height="22" fill="%s" stroke="%s" stroke-width="1"/>\n' "$((pad+244))" "$((y+6))" "$cbg" "$cfg"
        printf '<text x="%d" y="%d" class="m" font-size="11.5" font-weight="700" fill="%s">%s</text>\n' "$((pad+252))" "$((y+21))" "$cfg" "$(xml_esc "$ctxt")"
        case "$exd" in
          "出口 "*)
            local ex_sl ex_rs efg ebg
            ex_sl=$(printf '%s' "$exd" | awk '{print $1 " " $2}')
            ex_rs=$(printf '%s' "$exd" | sed -E 's/^出口 [A-Z][[:space:]]*·?[[:space:]]*//')
            efg=$(svg_ex_fg "$ex_sl"); ebg=$(svg_ex_bg "$ex_sl")
            printf '<rect x="%d" y="%d" width="62" height="20" fill="%s" stroke="%s" stroke-width="1"/>\n' "$((pad+474))" "$((y+7))" "$ebg" "$efg"
            printf '<text x="%d" y="%d" class="m" font-size="10.5" font-weight="700" text-anchor="middle" fill="%s">%s</text>\n' "$((pad+505))" "$((y+21))" "$efg" "$(xml_esc "$ex_sl")"
            printf '<text x="%d" y="%d" class="m" font-size="11.5" fill="%s">%s</text>\n' "$((pad+544))" "$((y+21))" "$fg" "$(xml_esc "$ex_rs")"
            ;;
          *)
            printf '<text x="%d" y="%d" class="m" font-size="11.5" fill="%s">%s</text>\n' "$((pad+474))" "$((y+21))" "$fgm" "$(xml_esc "$exd")"
            ;;
        esac
        printf '<text x="%d" y="%d" class="m" font-size="11" text-anchor="end" fill="%s">%s</text>\n' "$((pad+inner-18))" "$((y+21))" "$fgf" "$mstr"
      fi
      y=$((y + 34))
    done
    y=$((y + 12))

    if [ "$inc_lr" -eq 1 ]; then
      printf '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1"/>\n' "$pad" "$y" "$((pad+inner))" "$y" "$str"
      printf '<rect x="%d" y="%d" width="%d" height="31" fill="%s"/>\n' "$((pad+1))" "$((y+1))" "$((inner-2))" "$bgsub"
      printf '<text x="%d" y="%d" class="m" font-size="11.5" font-weight="700" fill="%s">[03] 本地控制 API 存档 (--with-rules 已显式启用)</text>\n' "$((pad+18))" "$((y+21))" "$fgm"
      y=$((y + 34))
      while IFS='|' read -r lh lr lc; do
        printf '<text x="%d" y="%d" class="m" font-size="11" fill="%s">%s</text>\n' "$((pad+18))" "$((y+16))" "$fg" "$(xml_esc "$lh")"
        printf '<text x="%d" y="%d" class="m" font-size="11" fill="%s">%s</text>\n' "$((pad+290))" "$((y+16))" "$fgm" "$(xml_esc "$lr")"
        printf '<text x="%d" y="%d" class="s" font-size="11" fill="%s">%s</text>\n' "$((pad+480))" "$((y+16))" "$cok" "$(xml_esc "$lc")"
        y=$((y + 24))
      done < "$LOCAL_RULES_FILE"
      y=$((y + 14))
    fi

    printf '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1"/>\n' "$pad" "$y" "$((pad+inner))" "$y" "$str"
    printf '<text x="%d" y="%d" class="m" font-size="11" fill="%s">G-ROUTE · Tier 0 本地离线直出 · 零数据上传 · 不打欺诈分 · %s</text>\n' "$((pad+18))" "$((y+27))" "$fgm" "$( [ "$inc_lr" -eq 1 ] && echo '含个人存档策略链' || echo '已隐去本机节点名' )"
    printf '<text x="%d" y="%d" class="m" font-size="11" text-anchor="end" fill="%s">IP: %s · %s</text>\n' "$((pad+inner-18))" "$((y+27))" "$fgf" "$(xml_esc "$P_IP")" "$V_TAG"
    printf '</svg>\n'
  } > "$out_path"

  printf '%b[OK] 已本地离线生成矢量 SVG 体检卡: %s%b\n' "$C_GRN" "$out_path" "$C_RST"
}

encode_payload() {
  if command -v gzip >/dev/null 2>&1; then
    printf 'z:%s' "$(printf '%s' "$JSON" | gzip -c -9 | base64 | tr -d '\r\n' | tr '+/' '-_' | tr -d '=')"
  else
    printf 'p:%s' "$(printf '%s' "$JSON" | base64 | tr -d '\r\n' | tr '+/' '-_' | tr -d '=')"
  fi
}

if [ "$OPT_SVG" -eq 1 ]; then
  export_local_svg "$OPT_SVG_PATH"
fi

if [ "$OPT_NO_LINK" -eq 0 ]; then
  PAYLOAD=$(encode_payload)
  case "$G_ROUTE_ORIGIN" in
    http://*|https://*)
      printf '%bWeb 体检卡 & PNG 导出:%b\n%s/#r=%s\n' "$C_CYN" "$C_RST" "$G_ROUTE_ORIGIN" "$PAYLOAD" ;;
    *)
      printf '%b离线报告码 (粘贴到 G-ROUTE 网页渲染体检卡 / 双卡 Diff):%b\nG1:%s\n' "$C_CYN" "$C_RST" "$PAYLOAD" ;;
  esac
fi
printf '%b注: 100%% 本地探测并离线编码，IP 已默认脱敏(-f 显示完整)，零数据上传。%b\n' "$C_DIM" "$C_RST"

# ---------------------------------------------------------------------------
# Post-Run Interactive Quick Actions (No Re-Probing Needed!)
# ---------------------------------------------------------------------------
if [ "$IS_INTERACTIVE" -eq 1 ] && [ "$OPT_NO_MENU" -eq 0 ] && [ "$OPT_QUICK" -eq 0 ]; then
  while true; do
    local_opts="[S] 本地存 SVG"
    if [ "$DID_INSPECT" -eq 0 ]; then local_opts="${local_opts}  [R] 补查本机代理分组"; fi
    local_opts="${local_opts}  [Enter] 退出"
    printf '\n快捷操作: %s: ' "$local_opts" >/dev/tty
    IFS= read -r ACT </dev/tty || ACT=""
    ACT=$(printf '%s' "$ACT" | tr '[:lower:]' '[:upper:]' | tr -d ' \r\n')
    case "$ACT" in
      ""|Q) break ;;
      S) export_local_svg "" ;;
      R)
        if [ "$DID_INSPECT" -eq 0 ]; then
          box_rule top
          run_local_controller_audit
          box_rule bot
        fi ;;
      *) ;;
    esac
  done
fi
