<#
.SYNOPSIS
  G-ROUTE v3 // Google 生态送中与全链路分流体检仪 (Windows PowerShell 5.1 & 7)
  权限契约: 零 UAC 提权 · 零读磁盘配置/代理订阅/SSH/Cookie · 零数据上传 · 零二进制下载
  支持交互全局入口、并行 6 桶分流雷达、白名单只读代理分组发现、零依赖本地离线 SVG 与 PNG 直出。

.EXAMPLE
  irm https://<origin>/ps | iex
  .\check.ps1 -Inspect -Svg
  .\check.ps1 -Quick -Png -Theme dark
  .\check.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [string]$Proxy = "",
  [string]$Controller = "",
  [string]$Secret = "",
  [switch]$Quick,
  [switch]$Inspect,
  [switch]$Svg,
  [string]$SvgPath = "",
  [switch]$Png,
  [string]$PngPath = "",
  [ValidateSet("light", "dark")]
  [string]$Theme = "light",
  [switch]$WithRules,
  [switch]$Ascii,
  [switch]$Compact,
  [switch]$NoMenu,
  [switch]$V4,
  [switch]$V6,
  [switch]$Full,
  [switch]$Json,
  [switch]$NoLink,
  [switch]$DryRun,
  [switch]$Vps,
  [switch]$ProxyMode
)

$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$G_ROUTE_ORIGIN = if ($env:G_ROUTE_ORIGIN) { $env:G_ROUTE_ORIGIN } else { "__G_ROUTE_ORIGIN__" }
if (-not $Controller -and $env:G_ROUTE_CONTROLLER) { $Controller = $env:G_ROUTE_CONTROLLER }
if (-not $Secret -and $env:G_ROUTE_SECRET) { $Secret = $env:G_ROUTE_SECRET }
if (-not $Inspect -and $env:G_ROUTE_INSPECT -eq "1") { $Inspect = $true }
$NoColor = [bool]$env:NO_COLOR

$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
$SocsCookie = "YSC=FSCWhKo2Zgw; SOCS=CAISHAgBEhJnd3NfMjAyNDA1MjctMF9SQzIaAmVuIAEaBgiA_LyaBg"

# ---------------------------------------------------------------------------
# Display Width & Swiss-Industrial Box Drawing Helpers
# ---------------------------------------------------------------------------
$W = if ($Compact) { 66 } else { 96 }
$B = if ($Ascii) {
  @{ TL = "+"; TR = "+"; BL = "+"; BR = "+"; H = "-"; V = "|"; LT = "+"; RT = "+" }
} else {
  @{
    TL = [char]0x250C; TR = [char]0x2510; BL = [char]0x2514; BR = [char]0x2518
    H = [char]0x2500; V = [char]0x2502; LT = [char]0x251C; RT = [char]0x2524
  }
}

function Get-DisplayWidth {
  param([string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return 0 }
  $width = 0
  $i = 0
  $len = $Text.Length
  while ($i -lt $len) {
    $c = [int]$Text[$i]
    if ([char]::IsHighSurrogate($Text[$i]) -and ($i + 1) -lt $len -and [char]::IsLowSurrogate($Text[$i + 1])) {
      $cp = [char]::ConvertToUtf32($Text[$i], $Text[$i + 1])
      $i += 2
      # Regional indicator flags: pair of 2 code points renders as 2 columns total
      if ($cp -ge 0x1F1E6 -and $cp -le 0x1F1FF) {
        if ($i + 1 -lt $len -and [char]::IsHighSurrogate($Text[$i])) {
          $cp2 = [char]::ConvertToUtf32($Text[$i], $Text[$i + 1])
          if ($cp2 -ge 0x1F1E6 -and $cp2 -le 0x1F1FF) { $i += 2 }
        }
        $width += 2
      } else {
        $width += 2
      }
      continue
    }
    $i += 1
    if ($c -eq 0x200D -or ($c -ge 0xFE00 -and $c -le 0xFE0F) -or ($c -ge 0x0300 -and $c -le 0x036F)) {
      continue
    }
    if (
      ($c -ge 0x1100 -and $c -le 0x115F) -or
      ($c -ge 0x2E80 -and $c -le 0x9FFF) -or
      ($c -ge 0xAC00 -and $c -le 0xD7A3) -or
      ($c -ge 0xF900 -and $c -le 0xFAFF) -or
      ($c -ge 0xFE10 -and $c -le 0xFE6F) -or
      ($c -ge 0xFF00 -and $c -le 0xFF60) -or
      ($c -ge 0xFFE0 -and $c -le 0xFFE6) -or
      ($c -ge 0x2600 -and $c -le 0x27BF -and $c -ne 0x2713 -and $c -ne 0x2715)
    ) {
      $width += 2
    } else {
      $width += 1
    }
  }
  return $width
}

function Clip-Display {
  param([string]$Text, [int]$MaxCols)
  if ([string]::IsNullOrEmpty($Text)) { return "" }
  if ((Get-DisplayWidth $Text) -le $MaxCols) { return $Text }
  if ($MaxCols -le 2) { return "" }
  $sb = New-Object System.Text.StringBuilder
  $w = 0
  $i = 0
  $len = $Text.Length
  while ($i -lt $len) {
    $step = 1
    $cw = 1
    $c = [int]$Text[$i]
    if ([char]::IsHighSurrogate($Text[$i]) -and ($i + 1) -lt $len -and [char]::IsLowSurrogate($Text[$i + 1])) {
      $step = 2
      $cw = 2
      $cp = [char]::ConvertToUtf32($Text[$i], $Text[$i + 1])
      if ($cp -ge 0x1F1E6 -and $cp -le 0x1F1FF -and ($i + 3) -lt $len -and [char]::IsHighSurrogate($Text[$i + 2])) {
        $step = 4
      }
    } elseif ($c -eq 0x200D -or ($c -ge 0xFE00 -and $c -le 0xFE0F)) {
      $cw = 0
    } elseif (
      ($c -ge 0x1100 -and $c -le 0x115F) -or ($c -ge 0x2E80 -and $c -le 0x9FFF) -or
      ($c -ge 0xAC00 -and $c -le 0xD7A3) -or ($c -ge 0xF900 -and $c -le 0xFAFF) -or
      ($c -ge 0xFF00 -and $c -le 0xFF60) -or ($c -ge 0x2600 -and $c -le 0x27BF -and $c -ne 0x2713 -and $c -ne 0x2715)
    ) {
      $cw = 2
    }
    if ($w + $cw + 2 -gt $MaxCols) { break }
    [void]$sb.Append($Text.Substring($i, $step))
    $w += $cw
    $i += $step
  }
  [void]$sb.Append("..")
  return $sb.ToString()
}

function Pad-Display {
  param([string]$Text, [int]$Cols)
  $clipped = Clip-Display $Text $Cols
  $w = Get-DisplayWidth $clipped
  if ($w -ge $Cols) { return $clipped }
  return $clipped + (" " * ($Cols - $w))
}

function Write-ColorText {
  param([string]$Text, [string]$Color = "Gray", [switch]$NoNewline)
  if ($NoColor) {
    if ($NoNewline) { Write-Host $Text -NoNewline } else { Write-Host $Text }
  } else {
    if ($NoNewline) { Write-Host $Text -ForegroundColor $Color -NoNewline } else { Write-Host $Text -ForegroundColor $Color }
  }
}

function Write-BoxRule {
  param([string]$Kind = "mid")
  $l = if ($Kind -eq "top") { $B.TL } elseif ($Kind -eq "bot") { $B.BL } else { $B.LT }
  $r = if ($Kind -eq "top") { $B.TR } elseif ($Kind -eq "bot") { $B.BR } else { $B.RT }
  Write-ColorText ($l + ([string]$B.H * ($W - 2)) + $r) "DarkGray"
}

function Write-BoxLine {
  param([string]$Text, [string]$Color = "Gray")
  $inner = $W - 4
  Write-ColorText "$($B.V) " "DarkGray" -NoNewline
  Write-ColorText (Pad-Display $Text $inner) $Color -NoNewline
  Write-ColorText " $($B.V)" "DarkGray"
}

function Write-BoxWrapped {
  param([string]$Prefix, [string]$Text, [string]$PrefixColor = "Gray", [string]$TextColor = "Gray", [int]$Indent = 0)
  $inner = $W - 4
  $pW = Get-DisplayWidth $Prefix
  $firstAvail = [Math]::Max(12, $inner - $pW)
  $contPad = " " * [Math]::Max(0, [Math]::Min($Indent, $inner - 16))
  $contAvail = [Math]::Max(12, $inner - $contPad.Length)

  $tokens = $Text -split ", "
  if ($tokens.Count -le 1 -and (Get-DisplayWidth $Text) -gt $firstAvail) {
    # Wrap long single chain cleanly on " -> " boundaries
    $parts = $Text -split " -> "
    if ($parts.Count -gt 1) {
      $line = ""; $first = $true
      foreach ($pt in $parts) {
        $cand = if ($line -eq "") { $pt } else { "$line -> $pt" }
        $lim = if ($first) { $firstAvail } else { $contAvail }
        if ($line -ne "" -and (Get-DisplayWidth $cand) -gt $lim) {
          if ($first) {
            Write-BoxSegments @(@{ Text = $Prefix; Color = $PrefixColor }, @{ Text = $line; Color = $TextColor })
            $first = $false
          } else {
            Write-BoxLine ($contPad + $line) $TextColor
          }
          $line = "-> $pt"
        } else {
          $line = $cand
        }
      }
      if ($line -ne "") {
        if ($first) {
          Write-BoxSegments @(@{ Text = $Prefix; Color = $PrefixColor }, @{ Text = $line; Color = $TextColor })
        } else {
          Write-BoxLine ($contPad + $line) $TextColor
        }
      }
      return
    }
  }

  $cur = ""; $isFirst = $true
  foreach ($tk in $tokens) {
    $cand = if ($cur -eq "") { $tk } else { "$cur, $tk" }
    $lim = if ($isFirst) { $firstAvail } else { $contAvail }
    if ($cur -ne "" -and (Get-DisplayWidth $cand) -gt $lim) {
      if ($isFirst) {
        Write-BoxSegments @(@{ Text = $Prefix; Color = $PrefixColor }, @{ Text = "$cur,"; Color = $TextColor })
        $isFirst = $false
      } else {
        Write-BoxLine ($contPad + "$cur,") $TextColor
      }
      $cur = $tk
    } else {
      $cur = $cand
    }
  }
  if ($cur -ne "") {
    if ($isFirst) {
      Write-BoxSegments @(@{ Text = $Prefix; Color = $PrefixColor }, @{ Text = $cur; Color = $TextColor })
    } else {
      Write-BoxLine ($contPad + $cur) $TextColor
    }
  }
}

function Get-ExitTermColor {
  param([string]$SlotOrText)
  if (-not $SlotOrText) { return "DarkGray" }
  if ($SlotOrText -match "^(直连|国内)") { return "DarkCyan" }
  if ($SlotOrText -match "^出口 A") { return "Cyan" }
  if ($SlotOrText -match "^出口 B") { return "Yellow" }
  if ($SlotOrText -match "^出口 C") { return "Magenta" }
  if ($SlotOrText -match "^出口 [D-Z]") { return "DarkMagenta" }
  return "DarkGray"
}

function Get-ExitSlotKey {
  param([string]$SlotOrText)
  if (-not $SlotOrText) { return "unk" }
  if ($SlotOrText -match "^(直连|国内)") { return "cn" }
  if ($SlotOrText -match "^出口 A") { return "a" }
  if ($SlotOrText -match "^出口 B") { return "b" }
  if ($SlotOrText -match "^出口 C") { return "c" }
  if ($SlotOrText -match "^出口 [D-Z]") { return "d" }
  return "unk"
}

function Split-ExitDisplay {
  param([string]$Raw)
  if (-not $Raw) { return @{ Slot = ""; Rest = "--"; Key = "unk" } }
  if ($Raw -match "^(直连 CN|出口 [A-Z])\s*(?:[·(]\s*)?(.*)$") {
    $sl = $Matches[1]
    $rs = ($Matches[2] -replace "\)\s*$", "").Trim()
    return @{ Slot = $sl; Rest = $rs; Key = (Get-ExitSlotKey $sl) }
  }
  return @{ Slot = ""; Rest = $Raw; Key = "unk" }
}

function Write-BoxSegments {
  param([object[]]$Segs)
  $inner = $W - 4
  $used = 0
  Write-ColorText "$($B.V) " "DarkGray" -NoNewline
  foreach ($seg in $Segs) {
    $txt = [string]$seg.Text
    $col = if ($seg.Color) { [string]$seg.Color } else { "Gray" }
    $rem = $inner - $used
    if ($rem -le 0) { break }
    $fit = if ($seg.Width) {
      $tw = [Math]::Min([int]$seg.Width, $rem)
      Pad-Display $txt $tw
    } else {
      Clip-Display $txt $rem
    }
    Write-ColorText $fit $col -NoNewline
    $used += (Get-DisplayWidth $fit)
  }
  if ($used -lt $inner) {
    Write-Host (" " * ($inner - $used)) -NoNewline
  }
  Write-ColorText " $($B.V)" "DarkGray"
}

# ---------------------------------------------------------------------------
# Layer 1 Passive Environment Detection (Zero UAC / Zero Disk Config / Zero Port Scan)
# ---------------------------------------------------------------------------
function Resolve-EffectiveProxy {
  if ($Proxy -ne "") { return $Proxy }
  if ($env:HTTPS_PROXY) { return $env:HTTPS_PROXY }
  if ($env:HTTP_PROXY) { return $env:HTTP_PROXY }
  if ($env:ALL_PROXY) { return $env:ALL_PROXY }
  try {
    $reg = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
    if ($reg -and $reg.ProxyEnable -eq 1 -and $reg.ProxyServer) {
      $srv = [string]$reg.ProxyServer
      if ($srv -match "https=([^;]+)") { return "http://$($Matches[1])" }
      if ($srv -match "http=([^;]+)") { return "http://$($Matches[1])" }
      if ($srv -notmatch "^[a-zA-Z0-9+.-]+://") { return "http://$srv" }
      return $srv
    }
  } catch {}
  return ""
}

function Get-PassiveTunNic {
  try {
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
    foreach ($a in $adapters) {
      $n = [string]$a.Name
      $d = [string]$a.InterfaceDescription
      $combo = "$n $d"
      if ($combo -match "(?i)\b(Meta|Mihomo|sing-box|Clash|FlClash|Hiddify|Wintun|CloudflareWARP|WARP|Tailscale|WireGuard|nekobox)\b") {
        if ($n.Length -le 24) { return $n }
        return $Matches[1]
      }
    }
  } catch {}
  return ""
}

$effectiveProxy = Resolve-EffectiveProxy
$hasExplicitProxy = ($effectiveProxy -ne "")
$passiveTunNic = Get-PassiveTunNic

function Show-DryRunAudit {
  Write-BoxRule "top"
  Write-BoxLine "G-ROUTE v3 // -DryRun 零发包安全审计清单 (未发送任何网络请求)" "Cyan"
  Write-BoxRule "mid"
  Write-BoxLine "[权限边界 · 4 个绝不]" "Yellow"
  Write-BoxLine "  1. 绝不申请 UAC / 管理员提权" "Gray"
  Write-BoxLine "  2. 绝不读取磁盘配置文件 (%APPDATA% 订阅、~/.ssh、Cookie) 或扫描进程" "Gray"
  Write-BoxLine "  3. 绝不向任何服务器上传检测结果 (#r= 与 SVG/PNG 均 100% 本地生成)" "Gray"
  Write-BoxLine "  4. 绝不下载二进制文件或执行远程混淆代码" "Gray"
  Write-BoxRule "mid"
  Write-BoxLine "[将发起的只读 HTTPS GET/HEAD 请求 · 6 桶分流雷达 + Google 6 路]" "Yellow"
  Write-BoxLine "  - myip.ipip.net (备选 cip.cc)              国内直连参照与绕行检测" "Gray"
  Write-BoxLine "  - v4/v6.ident.me/json (备选 ipify)         双栈通用海外出口 ASN" "Gray"
  Write-BoxLine "  - redirector.googlevideo.com/report_mapping Google/YT GGC 与实见 IP" "Gray"
  Write-BoxLine "  - www.cloudflare.com/cdn-cgi/trace         Cloudflare 出口 / WARP / colo" "Gray"
  Write-BoxLine "  - chatgpt.com/cdn-cgi/trace                OpenAI 实见出口 / WARP / colo" "Gray"
  Write-BoxLine "  - claude.ai/cdn-cgi/trace               Anthropic 实见出口 / WARP / colo" "Gray"
  Write-BoxLine "  - ipwho.is/<split_ip>                   仅对去重后的新增非 WARP 出口查 ASN" "Gray"
  Write-BoxLine "  - gspe1-ssl.ls.apple.com/pep/gcc           Apple 第三方地域对照" "Gray"
  Write-BoxLine "  - gemini / notebooklm / youtube / play / google / policies  Google 6 路" "Gray"
  Write-BoxRule "mid"
  Write-BoxLine "[当前会话被动识别]" "Yellow"
  Write-BoxLine ("  - IP 脱敏: {0}" -f $(if ($Full) { "关闭 (-Full 完整显示)" } else { "开启 (默认 38.59.*.*)" })) "Gray"
  Write-BoxLine ("  - 显式/系统代理: {0}" -f $(if ($effectiveProxy) { $effectiveProxy } else { "无" })) "Gray"
  Write-BoxLine ("  - 只读虚拟网卡提示: {0}" -f $(if ($passiveTunNic) { $passiveTunNic } else { "未检测到活跃 TUN 网卡" })) "Gray"
  $ctrlHint = if ($Controller) { "$Controller (仅本屏只读，绝不入分享链)" } elseif ($Inspect) { "白名单自动发现 (仅本屏只读，绝不入分享链)" } else { "关闭 (纯黑盒模式，零本机端口/管道探测)" }
  Write-BoxLine ("  - 本地控制 API: {0}" -f $ctrlHint) "Gray"
  Write-BoxRule "bot"
}

# ---------------------------------------------------------------------------
# Global Interactive Entrypoint (Pre-Run 1-Screen Compact Menu — 0 Packets Yet)
# ---------------------------------------------------------------------------
$hasExplicitFlags = (
  $Quick -or $Inspect -or ($Controller -ne "") -or $DryRun -or $Json -or
  $Svg -or ($SvgPath -ne "") -or $Png -or ($PngPath -ne "") -or
  $V4 -or $V6 -or $Full -or $NoLink -or $Vps -or $ProxyMode -or ($Proxy -ne "")
)
$isInteractiveTty = $false
try {
  $isInteractiveTty = (-not [Console]::IsInputRedirected -and $Host.UI -and $Host.UI.RawUI)
} catch {}

if (-not $hasExplicitFlags -and $isInteractiveTty -and -not $NoMenu) {
  while ($true) {
    $envSummary = if ($passiveTunNic) { "检测到活跃虚拟网卡 [$passiveTunNic]" } elseif ($hasExplicitProxy) { "检测到系统代理 [$effectiveProxy]" } else { "未检测到系统代理/TUN" }
    Write-BoxRule "top"
    Write-BoxLine "G-ROUTE v3 // Google 生态送中与全链路分流体检仪" "Cyan"
    Write-BoxLine ("零提权 · 零读磁盘配置 · 零数据上传  |  {0}" -f $envSummary) "DarkGray"
    Write-BoxRule "mid"
    Write-BoxLine "  [1] 极速纯黑盒体检  (默认 · 回车即跑 · 零本地端口/管道探测)" "Green"
    Write-BoxLine "  [2] 深度体检 + 自动透视本机代理分组  (白名单只读查 Mihomo/sing-box)" "Cyan"
    Write-BoxLine "  [3] 纯离线直出模式  (跑完本地生成 SVG 体检卡，不生成网页链接)" "Yellow"
    Write-BoxLine "  [4] 零发包安全审计  (先看全部只读域名与 4 个绝不，不发任何包)" "Gray"
    Write-BoxLine "  [Q] 退出" "DarkGray"
    Write-BoxRule "bot"
    $choice = (Read-Host "请选择 [1-4 / Q] (直接回车执行 1)").Trim().ToUpperInvariant()
    if ($choice -eq "" -or $choice -eq "1") {
      break
    } elseif ($choice -eq "2") {
      $Inspect = $true
      break
    } elseif ($choice -eq "3") {
      $Svg = $true
      $NoLink = $true
      break
    } elseif ($choice -eq "4") {
      Show-DryRunAudit
      Write-Host ""
      continue
    } elseif ($choice -eq "Q") {
      return
    }
  }
}

if ($DryRun) {
  Show-DryRunAudit
  return
}

$curlBin = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
if (-not $curlBin) {
  Write-ColorText "ERROR: 未找到 curl.exe (Windows 10/11 默认内置于 System32)" "Red"
  return
}

$runV4 = $true
$runV6 = $true
if ($V4 -and -not $V6) { $runV6 = $false }
if ($V6 -and -not $V4) { $runV4 = $false }

$detectedTun = $false

# ---------------------------------------------------------------------------
# Parallel curl.exe Batch Runner (WinPS 5.1 & PS 7 Compatible)
# ---------------------------------------------------------------------------
function Format-WinArg {
  param([string]$Arg)
  if ($Arg -notmatch '[\s"]') { return $Arg }
  return '"' + ($Arg -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("groute_" + [Guid]::NewGuid().ToString("N").Substring(0, 10))
[void][IO.Directory]::CreateDirectory($tmpRoot)

function Invoke-CurlBatch {
  param([hashtable[]]$Jobs)
  $procs = @()
  foreach ($j in $Jobs) {
    $id = [string]$j.Id
    $bodyFile = Join-Path $tmpRoot "$id.body"
    $argList = New-Object System.Collections.Generic.List[string]
    $argList.Add("-sS")
    $argList.Add("--max-time")
    $argList.Add($(if ($j.Timeout) { [string]$j.Timeout } else { "8" }))
    $argList.Add("-A")
    $argList.Add($UA)
    if ($hasExplicitProxy) {
      $argList.Add("-x")
      $argList.Add($effectiveProxy)
    }
    if ($j.Args) {
      foreach ($ea in $j.Args) { $argList.Add([string]$ea) }
    }
    $argList.Add("-o")
    $argList.Add($bodyFile)
    $argList.Add("-w")
    $argList.Add("CODE=%{http_code}|TIME=%{time_total}|IP=%{remote_ip}|URL=%{url_effective}")
    $argList.Add([string]$j.Url)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $curlBin
    $psi.Arguments = (($argList | ForEach-Object { Format-WinArg $_ }) -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $procs += @{ Id = $id; Proc = $p; BodyFile = $bodyFile }
  }

  $results = @{}
  foreach ($item in $procs) {
    $p = $item.Proc
    $done = $p.WaitForExit(11000)
    if (-not $done) {
      try { $p.Kill() } catch {}
    }
    $metaStr = ""
    try { $metaStr = $p.StandardOutput.ReadToEnd().Trim() } catch {}
    $exitCode = if ($done) { $p.ExitCode } else { 28 }
    $p.Dispose()

    $httpCode = "000"; $ms = $null; $remoteIp = ""; $effUrl = ""
    if ($metaStr -match "CODE=(\d+)\|TIME=([0-9.]+)\|IP=([^|]*)\|URL=(.*)$") {
      $httpCode = $Matches[1]
      try { $ms = [int][Math]::Round(([double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)) * 1000) } catch {}
      $remoteIp = $Matches[3].Trim()
      $effUrl = $Matches[4].Trim()
    }
    $bodyText = ""
    if (Test-Path $item.BodyFile) {
      try { $bodyText = [IO.File]::ReadAllText($item.BodyFile, [System.Text.Encoding]::UTF8) } catch {}
    }
    $results[$item.Id] = @{
      Code = $exitCode
      Http = $httpCode
      Ms = $ms
      RemoteIp = $remoteIp
      Url = $effUrl
      Text = $bodyText
    }
  }
  return $results
}

function Write-ProgressBar {
  param([int]$Step, [int]$Total, [string]$Msg)
  if ($Json) { return }
  $filled = [int][Math]::Round(($Step / $Total) * 10)
  $bar = ("#" * $filled) + ("." * (10 - $filled))
  Write-Host ("`r[G-ROUTE] [{0}] {1}/{2} {3,-44}" -f $bar, $Step, $Total, $Msg) -NoNewline -ForegroundColor DarkGray
}

function Clear-ProgressBar {
  if (-not $Json) { Write-Host ("`r{0}`r" -f (" " * 76)) -NoNewline }
}

# ---------------------------------------------------------------------------
# Classification & Parsing Utilities
# ---------------------------------------------------------------------------
function Mask-IpAddress {
  param([string]$RawIp)
  if (-not $RawIp) { return "" }
  if ($Full) { return $RawIp }
  if ($RawIp -match ":") {
    $parts = $RawIp -split ":"
    if ($parts.Length -ge 2) { return "$($parts[0]):$($parts[1]):*:*" }
    return $RawIp
  }
  $oct = $RawIp -split "\."
  if ($oct.Length -eq 4) { return "$($oct[0]).$($oct[1]).*.*" }
  return $RawIp
}

function Test-WarpIp {
  param([string]$Ip)
  if (-not $Ip) { return $false }
  $low = $Ip.ToLowerInvariant()
  return ($low -match "^(2a09:bac|104\.28\.|104\.29\.|172\.71\.|162\.158\.|8\.29\.)")
}

function Get-KindFromOrg {
  param([string]$Org, [string]$IdentType = "", [string]$RawIp = "")
  $low = ($Org + "").ToLowerInvariant()
  if ((Test-WarpIp $RawIp) -or $low -match "cloudflare|warp") { return "warp" }
  if ($low -match "amazon|aws|google cloud|microsoft|azure|digitalocean|vultr|choopa|hetzner|ovh|linode|oracle|alibaba|aliyun|tencent|kirino|misaka|xtom|dmit|bandwagon|racknerd|zenlayer|m247|datacamp|leaseweb|scaleway|contabo|upcloud|vps|cloud|datacenter|hosting") {
    return "hosting"
  }
  if ($low -match "cox |comcast|xfinity|verizon|at&t|spectrum|charter|softbank|ntt|kddi|chunghwa|hinet|pccw|hkbn|singtel|starhub|vodafone|telekom|telecom|broadband|fiber|fibre|cable|mobile") {
    return "isp"
  }
  $t = ($IdentType + "").ToLowerInvariant()
  if ($t -in @("hosting", "isp", "business")) { return $t }
  return "unknown"
}

function Format-KindCn {
  param([string]$Kind)
  switch ($Kind) {
    "hosting"  { return "云机房段" }
    "isp"      { return "运营商段" }
    "warp"     { return "WARP 出站" }
    "business" { return "商业网段" }
    default    { return "未归类段" }
  }
}

function Test-RestrictedCountry {
  param([string]$Val)
  if (-not $Val) { return $false }
  return ($Val.Trim().ToLowerInvariant() -in @("chn", "cn", "china", "hkg", "hk", "hong kong", "mac", "mo", "macau", "rus", "ru", "russia", "blr", "by", "belarus"))
}

function Parse-CfTrace {
  param([string]$Text)
  $map = @{}
  foreach ($line in ($Text -split "`r?`n")) {
    if ($line -match "^([a-z0-9_]+)=(.*)$") {
      $map[$Matches[1]] = $Matches[2].Trim()
    }
  }
  return $map
}

function Test-DnsMode {
  param([int]$Ver, [bool]$IsTun, [bool]$HasPx)
  if ($IsTun) { return "tun" }
  if ($HasPx) { return "skip" }
  try {
    $qType = if ($Ver -eq 4) { "A" } else { "AAAA" }
    $recs = Resolve-DnsName -Name "gemini.google.com" -Type $qType -DnsOnly -ErrorAction SilentlyContinue
    $addr = ($recs | Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress
    if (-not $addr) { return "skip" }
    if ($addr -match "^(10\.|127\.|192\.168\.|198\.(18|19)\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.|fc|fd|::1)") {
      return "viadns"
    }
    $nx = Resolve-DnsName -Name "groute-nx-$(Get-Random).gemini.google.com" -Type $qType -DnsOnly -ErrorAction SilentlyContinue
    if ($nx | Where-Object { $_.IPAddress }) { return "viadns" }
    if ($Ver -eq 4) {
      if ($addr -match "^(142\.250\.|142\.251\.|172\.217\.|172\.253\.|216\.58\.|216\.239\.|74\.125\.|64\.233\.|209\.85\.|108\.177\.|192\.178\.|66\.102\.|66\.249\.|34\.|35\.)") { return "native" }
      return "viadns"
    } else {
      if ($addr -match "^(2607:f8b0:|2404:6800:|2a00:1450:|2800:3f0:)") { return "native" }
      return "viadns"
    }
  } catch {
    return "skip"
  }
}

# ---------------------------------------------------------------------------
# Wave 1: Parallel 6-Bucket Split-Route Radar + Dual-Stack Identity
# ---------------------------------------------------------------------------
try {
  Write-ProgressBar 1 4 "并发探测 6 桶分流雷达与双栈出口..."
  $w1Jobs = @(
    @{ Id = "cn";  Url = "https://myip.ipip.net"; Timeout = 4 },
    @{ Id = "ap";  Url = "https://gspe1-ssl.ls.apple.com/pep/gcc"; Args = @("-4"); Timeout = 5 },
    @{ Id = "cf";  Url = "https://www.cloudflare.com/cdn-cgi/trace"; Timeout = 6 },
    @{ Id = "oai"; Url = "https://chatgpt.com/cdn-cgi/trace"; Timeout = 6 },
    @{ Id = "cld"; Url = "https://claude.ai/cdn-cgi/trace"; Timeout = 6 }
  )
  if ($runV4) {
    $w1Jobs += @{ Id = "v4_ident"; Url = "https://v4.ident.me/json"; Args = @("-4"); Timeout = 6 }
    $w1Jobs += @{ Id = "v4_ggc";   Url = "https://redirector.googlevideo.com/report_mapping"; Args = @("-4"); Timeout = 6 }
  }
  if ($runV6) {
    $w1Jobs += @{ Id = "v6_ident"; Url = "https://v6.ident.me/json"; Args = @("-6"); Timeout = 5 }
    $w1Jobs += @{ Id = "v6_ggc";   Url = "https://redirector.googlevideo.com/report_mapping"; Args = @("-6"); Timeout = 5 }
  }
  $w1 = Invoke-CurlBatch -Jobs $w1Jobs

  foreach ($k in $w1.Keys) {
    if ($w1[$k].RemoteIp -match "^(198\.(18|19)\.\d+\.\d+|fc[0-9a-f:]+|fd[0-9a-f:]+)") {
      $detectedTun = $true
    }
  }

  # Parse CN direct bucket
  $cnRaw = $w1["cn"].Text
  $cnMs = $w1["cn"].Ms
  $cnRawIp = ""; $cnNote = ""; $cnDirect = ""; $cnLeak = $false
  if ($cnRaw -match "(\d+\.\d+\.\d+\.\d+)") { $cnRawIp = $Matches[1] }
  if ($cnRaw -match "来自于[：:]\s*([^\r\n]+)") { $cnNote = ($Matches[1].Trim() -replace "\s+", " ") }
  if ($cnRaw -match "中国" -and $cnRaw -notmatch "香港|澳门|台湾") {
    $cnDirect = "CN"
  } elseif ($cnRawIp -and $cnNote) {
    $cnLeak = $true
  }

  $appleRaw = $w1["ap"].Text.Trim().ToUpperInvariant()
  $appleCc = if ($appleRaw -match "^[A-Z]{2}$") { $appleRaw } else { "" }

  # Parse ident.me + fallback ipify if needed
  $fallbackJobs = @()
  $stackBase = @{}
  foreach ($ver in @(4, 6)) {
    if (($ver -eq 4 -and -not $runV4) -or ($ver -eq 6 -and -not $runV6)) { continue }
    $res = $w1["v${ver}_ident"]
    $obj = $null
    if ($res.Code -eq 0 -and $res.Text.Trim().StartsWith("{")) {
      try { $obj = $res.Text | ConvertFrom-Json } catch {}
    }
    $rawIp = if ($obj -and $obj.ip) { [string]$obj.ip } else { "" }
    $stackBase[$ver] = @{ Obj = $obj; RawIp = $rawIp; Ms = $res.Ms }
    if (-not $rawIp) {
      $fallbackJobs += @{ Id = "v${ver}_ipify"; Url = "https://api${ver}.ipify.org?format=json"; Args = @("-$ver"); Timeout = 4 }
    }
  }
  if ($fallbackJobs.Count -gt 0) {
    $fb = Invoke-CurlBatch -Jobs $fallbackJobs
    foreach ($ver in @(4, 6)) {
      if ($fb.ContainsKey("v${ver}_ipify")) {
        $f = $fb["v${ver}_ipify"]
        if ($f.Code -eq 0 -and $f.Text.Trim().StartsWith("{")) {
          try {
            $stackBase[$ver].RawIp = [string]($f.Text | ConvertFrom-Json).ip
            $stackBase[$ver].Ms = $f.Ms
          } catch {}
        }
      }
    }
  }

  $activeVers = @()
  foreach ($ver in @(4, 6)) {
    if ($stackBase.ContainsKey($ver) -and $stackBase[$ver].RawIp) { $activeVers += $ver }
  }
  if ($activeVers.Count -eq 0) {
    Clear-ProgressBar
    Write-ColorText "ERROR: IPv4 与 IPv6 均未能获取出口信息，请检查网络或代理参数 (-Proxy)。" "Red"
    return
  }

  # Parse GGC + Cloudflare + OpenAI + Claude trace buckets
  $ggcParsed = @{}
  foreach ($ver in $activeVers) {
    $gRes = $w1["v${ver}_ggc"]
    $gip = ""; $cdn = ""; $cdnu = $false
    if ($gRes.Code -eq 0 -and $gRes.Text -match "(?m)^(\S+)\s+=>\s+(\S+)(.*)$") {
      $gip = $Matches[1].Trim()
      $cdn = $Matches[2].Trim()
      if ($Matches[3] -match "\[u\]") { $cdnu = $true }
    }
    $ggcParsed[$ver] = @{ Gip = $gip; Cdn = $cdn; Cdnu = $cdnu; Ms = $gRes.Ms }
  }

  $cfMap  = Parse-CfTrace $w1["cf"].Text
  $oaiMap = Parse-CfTrace $w1["oai"].Text
  $cldMap = Parse-CfTrace $w1["cld"].Text

  # Deduplicate newly discovered non-WARP exit IPs for 1-shot ASN lookup
  $knownRawIps = @{}
  foreach ($ver in $activeVers) { $knownRawIps[$stackBase[$ver].RawIp.ToLowerInvariant()] = $true }
  $needAsnIps = New-Object System.Collections.Generic.List[string]
  $candIps = @()
  foreach ($ver in $activeVers) { if ($ggcParsed[$ver].Gip) { $candIps += $ggcParsed[$ver].Gip } }
  if ($cfMap["ip"])  { $candIps += $cfMap["ip"] }
  if ($oaiMap["ip"]) { $candIps += $oaiMap["ip"] }
  if ($cldMap["ip"]) { $candIps += $cldMap["ip"] }
  foreach ($cip in $candIps) {
    $k = $cip.ToLowerInvariant()
    if (-not $knownRawIps.ContainsKey($k) -and -not (Test-WarpIp $cip)) {
      $knownRawIps[$k] = $true
      $needAsnIps.Add($cip)
    }
  }

  # -------------------------------------------------------------------------
  # Wave 2: Parallel Google 6-Way Ground Truth + Deduplicated Split ASN Lookups
  # -------------------------------------------------------------------------
  Write-ProgressBar 2 4 "并发实测 Google 6 路真值与独立出口归属..."
  $w2Jobs = @()
  foreach ($ver in $activeVers) {
    $sf = "-$ver"
    $w2Jobs += @{ Id = "v${ver}_gem";  Url = "https://gemini.google.com/app"; Args = @($sf, "-L"); Timeout = 9 }
    $w2Jobs += @{ Id = "v${ver}_nlm";  Url = "https://notebooklm.google.com/"; Args = @($sf, "-I"); Timeout = 7 }
    $w2Jobs += @{ Id = "v${ver}_yt";   Url = "https://www.youtube.com/premium"; Args = @($sf, "-L", "-H", "Accept-Language: en-US,en;q=0.9", "-H", "Cookie: $SocsCookie"); Timeout = 9 }
    $w2Jobs += @{ Id = "v${ver}_play"; Url = "https://play.google.com/"; Args = @($sf, "-L", "-H", "Accept-Language: en-US,en;q=0.9"); Timeout = 9 }
    $w2Jobs += @{ Id = "v${ver}_sdom"; Url = "https://www.google.com/searchdomaincheck?format=domain"; Args = @($sf); Timeout = 7 }
    $w2Jobs += @{ Id = "v${ver}_srch"; Url = "https://www.google.com/search?q=curl&ie=UTF-8"; Args = @($sf, "-L", "-H", "Accept-Language: en-US,en;q=0.9", "-H", "Sec-Fetch-Dest: document", "-H", "Sec-Fetch-Mode: navigate", "-H", "Sec-Fetch-Site: none"); Timeout = 9 }
    $w2Jobs += @{ Id = "v${ver}_trm";  Url = "https://policies.google.com/terms?hl=en"; Args = @($sf, "-L"); Timeout = 9 }
  }
  $asnIdx = 0
  $asnKeyMap = @{}
  foreach ($nip in $needAsnIps) {
    $aid = "asn_$asnIdx"
    $asnKeyMap[$aid] = $nip.ToLowerInvariant()
    $w2Jobs += @{ Id = $aid; Url = "https://ipwho.is/$nip"; Timeout = 5 }
    $asnIdx += 1
  }

  $w2 = Invoke-CurlBatch -Jobs $w2Jobs
  Write-ProgressBar 3 4 "聚合分流拓扑与诊断结论..."

  foreach ($k in $w2.Keys) {
    if ($w2[$k].RemoteIp -match "^(198\.(18|19)\.\d+\.\d+|fc[0-9a-f:]+|fd[0-9a-f:]+)") {
      $detectedTun = $true
    }
  }

  # Build ASN metadata cache
  $ipMetaCache = @{}
  foreach ($ver in $activeVers) {
    $sb = $stackBase[$ver]
    $rawIp = $sb.RawIp
    $io = $sb.Obj
    $org = if ($io -and $io.aso) { [string]$io.aso } else { "" }
    $asn = if ($io -and $io.asn) { [int]$io.asn } else { $null }
    $cc  = if ($io -and $io.cc)  { ([string]$io.cc).ToUpperInvariant() } else { "" }
    $city = if ($io -and $io.city) { [string]$io.city } else { "" }
    $kind = Get-KindFromOrg -Org $org -IdentType $(if ($io) { [string]$io.type } else { "" }) -RawIp $rawIp
    $ipMetaCache[$rawIp.ToLowerInvariant()] = @{ Asn = $asn; Org = $org; Cc = $cc; City = $city; Kind = $kind }
  }
  foreach ($aid in $asnKeyMap.Keys) {
    $ipKey = $asnKeyMap[$aid]
    $r = $w2[$aid]
    if ($r.Code -eq 0 -and $r.Text.Trim().StartsWith("{")) {
      try {
        $gw = $r.Text | ConvertFrom-Json
        if ($gw.success) {
          $gAsn = if ($gw.connection -and $gw.connection.asn) { [int]$gw.connection.asn } else { $null }
          $gOrg = if ($gw.connection -and $gw.connection.org) { [string]$gw.connection.org } elseif ($gw.connection -and $gw.connection.isp) { [string]$gw.connection.isp } else { "" }
          $gCc  = if ($gw.country_code) { ([string]$gw.country_code).ToUpperInvariant() } else { "" }
          $gKind = Get-KindFromOrg -Org $gOrg -RawIp $ipKey
          $ipMetaCache[$ipKey] = @{ Asn = $gAsn; Org = $gOrg; Cc = $gCc; City = ""; Kind = $gKind }
        }
      } catch {}
    }
  }

  function Get-MetaForIp {
    param([string]$RawIp)
    if (-not $RawIp) { return @{ Asn = $null; Org = ""; Cc = ""; City = ""; Kind = "unknown" } }
    $k = $RawIp.ToLowerInvariant()
    if ($ipMetaCache.ContainsKey($k)) { return $ipMetaCache[$k] }
    if (Test-WarpIp $RawIp) { return @{ Asn = 13335; Org = "Cloudflare WARP"; Cc = ""; City = ""; Kind = "warp" } }
    return @{ Asn = $null; Org = ""; Cc = ""; City = ""; Kind = "unknown" }
  }

  # Assemble v4 / v6 stack objects
  $stackData = @{}
  foreach ($ver in $activeVers) {
    $rawIp = $stackBase[$ver].RawIp
    $meta  = Get-MetaForIp $rawIp
    $ggc   = $ggcParsed[$ver]
    $gipRaw = $ggc.Gip
    $gMeta = if ($gipRaw -and $gipRaw -ne $rawIp) { Get-MetaForIp $gipRaw } else { $null }

    $gemRes = $w2["v${ver}_gem"]
    $gemCc = ""
    if ($gemRes.Code -eq 0) {
      if ($gemRes.Text -match ',2,1,200,"([A-Z]{3})"') { $gemCc = $Matches[1] }
      elseif ($gemRes.Text -match '"countryCode":"([A-Z]{2})"') { $gemCc = $Matches[1] }
    }

    $nlmRes = $w2["v${ver}_nlm"]
    $nlmStatus = "err"
    if ($nlmRes.Code -eq 0) {
      if ($nlmRes.Text -match "(?im)^location:.*location=unsupported") { $nlmStatus = "unavail" }
      elseif ($nlmRes.Text -match "(?im)^location:.*(notebook\.google\.com|accounts\.google\.com)" -or $nlmRes.Http -in @("200", "301", "302")) { $nlmStatus = "ok" }
    }

    $ytRes = $w2["v${ver}_yt"]
    $ytStatus = "err"; $ytGl = ""
    if ($ytRes.Code -eq 0 -and $ytRes.Text.Length -gt 0) {
      if ($ytRes.Text -match '"contentRegion":"([A-Z]{2})"') { $ytGl = $Matches[1] }
      elseif ($ytRes.Text -match '"INNERTUBE_CONTEXT_GL":"([A-Z]{2})"') { $ytGl = $Matches[1] }
      if ($ytRes.Text -match "www\.google\.cn") { $ytStatus = "cn" }
      elseif ($ytRes.Text -match "(?i)Premium is not available in your country") { $ytStatus = "noprem" }
      elseif ($ytRes.Text -match "(?i)ad-free") { $ytStatus = "ok" }
    }

    $playRes = $w2["v${ver}_play"]
    $playCc = ""
    if ($playRes.Code -eq 0 -and $playRes.Text -match '<div class="yVZQTb">([^<(]+)') {
      $playCc = $Matches[1].Trim()
    }

    $sdRes = $w2["v${ver}_sdom"]
    $sdom = ""
    if ($sdRes.Code -eq 0) {
      if ($sdRes.Text -match "(?i)hkredirect") { $sdom = "hkredirect" }
      else {
        $first = ($sdRes.Text -split "`r?`n")[0].Trim()
        if ($first -match "^\.google\.") { $sdom = $first }
      }
    }

    $srRes = $w2["v${ver}_srch"]
    $scap = "err"
    if ($srRes.Code -eq 0 -and $srRes.Http -ne "000") {
      if ($srRes.Http -eq "429" -or $srRes.Text -match "(?i)unusual traffic from|is blocked|unaddressed abuse|/sorry/") { $scap = "captcha" }
      elseif ($srRes.Url -match "(?i)google\.com\.hk|google\.cn") { $scap = "hk" }
      else { $scap = "ok" }
    }

    $trmRes = $w2["v${ver}_trm"]
    $trmCv = ""; $trmEnt = ""
    if ($trmRes.Code -eq 0) {
      if ($trmRes.Text -match "(?i)Country\s+version(?:\s*<[^>]+>)*\s*:\s*(?:<[^>]+>\s*)*([A-Za-z][A-Za-z\s,\.\(\)&'-]{1,42})") {
        $trmCv = $Matches[1].Trim()
      }
      if ($trmRes.Text -match "(Google Ireland Limited|Google LLC|Google Asia Pacific|Google Commerce Limited)") {
        $trmEnt = $Matches[1]
      }
    }

    $dnsMode = Test-DnsMode -Ver $ver -IsTun $detectedTun -HasPx $hasExplicitProxy

    $rttObj = [ordered]@{}
    if ($null -ne $gemRes.Ms)  { $rttObj.gem  = $gemRes.Ms }
    if ($null -ne $nlmRes.Ms)  { $rttObj.nlm  = $nlmRes.Ms }
    if ($null -ne $ytRes.Ms)   { $rttObj.yt   = $ytRes.Ms }
    if ($null -ne $ggc.Ms)     { $rttObj.cdn  = $ggc.Ms }
    if ($null -ne $playRes.Ms) { $rttObj.play = $playRes.Ms }
    if ($null -ne $srRes.Ms)   { $rttObj.srch = $srRes.Ms }

    $obj = [ordered]@{}
    $obj.ip = Mask-IpAddress $rawIp
    if ($gipRaw) { $obj.gip = Mask-IpAddress $gipRaw }
    if ($null -ne $meta.Asn) { $obj.asn = $meta.Asn }
    if ($meta.Org)  { $obj.org  = $meta.Org }
    if ($meta.Cc)   { $obj.cc   = $meta.Cc }
    if ($meta.City) { $obj.city = $meta.City }
    if ($meta.Kind) { $obj.kind = $meta.Kind }
    if ($gMeta) {
      if ($null -ne $gMeta.Asn) { $obj.gasn = $gMeta.Asn }
      if ($gMeta.Org)  { $obj.gorg  = $gMeta.Org }
      if ($gMeta.Kind) { $obj.gkind = $gMeta.Kind }
    }
    if ($gemCc)     { $obj.gem  = $gemCc }
    if ($nlmStatus) { $obj.nlm  = $nlmStatus }
    if ($ytStatus)  { $obj.yt   = $ytStatus }
    if ($ytGl)      { $obj.ytg  = $ytGl }
    if ($ggc.Cdn)   { $obj.cdn  = $ggc.Cdn }
    if ($ggc.Cdnu)  { $obj.cdnu = $true }
    if ($playCc)    { $obj.play = $playCc }
    if ($sdom)      { $obj.sdom = $sdom }
    if ($scap)      { $obj.scap = $scap }
    if ($trmCv)     { $obj.trm  = $trmCv }
    if ($trmEnt)    { $obj.ent  = $trmEnt }
    if ($dnsMode)   { $obj.dns  = $dnsMode }
    if ($rttObj.Count -gt 0) { $obj.rtt = $rttObj }
    $stackData[$ver] = $obj
  }

  $v4Data = if ($stackData.ContainsKey(4)) { $stackData[4] } else { $null }
  $v6Data = if ($stackData.ContainsKey(6)) { $stackData[6] } else { $null }
  $pVer = if ($null -ne $v4Data) { 4 } else { 6 }
  $p = $stackData[$pVer]
  $pRawIp = $stackBase[$pVer].RawIp
  $pGgc = $ggcParsed[$pVer]

  # -------------------------------------------------------------------------
  # Assemble Layer 1 Transport Fingerprint + 6-Bucket Split-Route Topology
  # -------------------------------------------------------------------------
  $splitHit = ($p.ip -and $p.gip -and $p.ip -ne $p.gip)
  $netKind = "direct"
  $netLabel = if ($splitHit) { "直连主机 · 出站分流" } else { "直连出站" }
  if ($detectedTun) {
    $netKind = "tun_fakeip"
    $netLabel = if ($passiveTunNic) { "本机 TUN · Fake-IP ($passiveTunNic)" } else { "本机 TUN · Fake-IP" }
  } elseif ($passiveTunNic -and ($cnDirect -or $splitHit -or $ProxyMode)) {
    $netKind = "tun_realip"
    $netLabel = "本机 TUN · Real-IP ($passiveTunNic)"
  } elseif ($hasExplicitProxy) {
    $netKind = "sysproxy"
    $pxShort = $effectiveProxy -replace "^https?://", ""
    $netLabel = "系统代理 ($pxShort)"
  } elseif ($cnDirect -and $p.cc -and $p.cc -ne "CN") {
    $netKind = "router"
    $netLabel = "上游透明代理 / 旁路由"
  }

  $netObj = [ordered]@{ kind = $netKind; label = $netLabel }
  if ($passiveTunNic) { $netObj.nic = $passiveTunNic }

  $runMode = if ($Vps) { "vps" } elseif ($ProxyMode) { "proxy" } elseif ($netKind -ne "direct") { "proxy" } else { "vps" }

  function Build-TraceBucket {
    param([hashtable]$TraceMap, [object]$Ms)
    $raw = [string]$TraceMap["ip"]
    if (-not $raw) { return $null }
    $m = Get-MetaForIp $raw
    $b = [ordered]@{ ip = (Mask-IpAddress $raw) }
    $loc = if ($TraceMap["loc"]) { $TraceMap["loc"].ToUpperInvariant() } elseif ($m.Cc) { $m.Cc } else { "" }
    if ($loc) { $b.cc = $loc }
    if ($null -ne $m.Asn) { $b.asn = $m.Asn }
    if ($m.Org) { $b.org = $m.Org }
    $wVal = ([string]$TraceMap["warp"]).ToLowerInvariant()
    $effKind = if ($wVal -in @("on", "plus")) { "warp" } else { $m.Kind }
    if ($effKind) { $b.kind = $effKind }
    if ($TraceMap["colo"]) { $b.colo = $TraceMap["colo"].ToUpperInvariant() }
    if ($wVal -in @("on", "off", "plus")) { $b.warp = $wVal }
    if ($null -ne $Ms) { $b.ms = [int]$Ms }
    return $b
  }

  $rtObj = [ordered]@{}
  if ($cnDirect -or ($runMode -eq "proxy" -and $cnRawIp -and $cnNote)) {
    $cnBucket = [ordered]@{}
    if ($cnRawIp) { $cnBucket.ip = Mask-IpAddress $cnRawIp }
    $cnBucket.cc = if ($cnDirect) { "CN" } else { "INTL" }
    if ($cnNote) { $cnBucket.note = if ($cnNote.Length -gt 48) { $cnNote.Substring(0, 48) } else { $cnNote } }
    if ($null -ne $cnMs) { $cnBucket.ms = [int]$cnMs }
    $rtObj.cn = $cnBucket
  } else {
    $cnLeak = $false
  }
  $defBucket = [ordered]@{ ip = $p.ip }
  if ($p.cc)   { $defBucket.cc = $p.cc }
  if ($p.asn)  { $defBucket.asn = $p.asn }
  if ($p.org)  { $defBucket.org = $p.org }
  if ($p.kind) { $defBucket.kind = $p.kind }
  if ($null -ne $stackBase[$pVer].Ms) { $defBucket.ms = [int]$stackBase[$pVer].Ms }
  $rtObj.def = $defBucket

  if ($p.gip) {
    $ggcBucket = [ordered]@{ ip = $p.gip }
    $gM = Get-MetaForIp $pGgc.Gip
    if ($gM.Cc)   { $ggcBucket.cc = $gM.Cc }
    if ($gM.Asn)  { $ggcBucket.asn = $gM.Asn }
    if ($gM.Org)  { $ggcBucket.org = $gM.Org }
    if ($gM.Kind) { $ggcBucket.kind = $gM.Kind }
    if ($p.cdn)   { $ggcBucket.colo = $p.cdn }
    if ($gM.Kind -eq "warp") { $ggcBucket.warp = "on" }
    if ($null -ne $pGgc.Ms) { $ggcBucket.ms = [int]$pGgc.Ms }
    $rtObj.ggc = $ggcBucket
  }

  $cfB  = Build-TraceBucket $cfMap  $w1["cf"].Ms
  $oaiB = Build-TraceBucket $oaiMap $w1["oai"].Ms
  $cldB = Build-TraceBucket $cldMap $w1["cld"].Ms
  if ($cfB)  { $rtObj.cf  = $cfB }
  if ($oaiB) { $rtObj.oai = $oaiB }
  if ($cldB) { $rtObj.cld = $cldB }

  # Cluster 6 buckets into [出口 A/B/C] for CLI / SVG / PNG
  $clusters = New-Object System.Collections.ArrayList
  if ($rtObj.Contains("cn")) {
    $c = $rtObj.cn
    [void]$clusters.Add([ordered]@{
      Slot = if ($cnDirect) { "直连 CN" } else { "国内异常" }
      Tone = if ($cnDirect) { "ok" } else { "leak" }
      Ip = $(if ($c.ip) { $c.ip } else { "--" })
      AsnOrg = $(if ($c.note) { $c.note } else { "国内直连" })
      Buckets = $(if ($cnDirect) { "国内直连 (未绕行代理)" } else { "国内桶落入海外!" })
      AvgMs = $c.ms
      IsCn = [bool]$cnDirect
      Warp = $false
    })
  }
  $groupMap = [ordered]@{}
  $bDefs = @(
    @{ Key = "def"; Label = "通用海外" },
    @{ Key = "ggc"; Label = "Google/YT" },
    @{ Key = "cf";  Label = "Cloudflare" },
    @{ Key = "oai"; Label = "ChatGPT" },
    @{ Key = "cld"; Label = "Claude" }
  )
  foreach ($bd in $bDefs) {
    if (-not $rtObj.Contains($bd.Key)) { continue }
    $bk = $rtObj[$bd.Key]
    if (-not $bk.ip) { continue }
    $gKey = $bk.ip.ToLowerInvariant()
    $tag = $bd.Label
    $extra = @()
    if ($bk.colo) { $extra += $bk.colo }
    if ($bk.warp -in @("on", "plus")) { $extra += "WARP" }
    if ($extra.Count -gt 0) { $tag = "$tag($($extra -join '/'))" }
    if ($groupMap.Contains($gKey)) {
      $groupMap[$gKey].Buckets.Add($tag)
      if ($null -ne $bk.ms) { $groupMap[$gKey].MsList.Add([int]$bk.ms) }
      if ($bk.warp -in @("on", "plus") -or $bk.kind -eq "warp") { $groupMap[$gKey].Warp = $true }
    } else {
      $bl = New-Object System.Collections.Generic.List[string]
      $bl.Add($tag)
      $ml = New-Object System.Collections.Generic.List[int]
      if ($null -ne $bk.ms) { $ml.Add([int]$bk.ms) }
      $groupMap[$gKey] = @{
        Ip = $bk.ip
        Asn = $bk.asn
        Org = $(if ($bk.org) { $bk.org } else { "独立出口" })
        Kind = $(if ($bk.kind) { $bk.kind } else { "unknown" })
        Cc = $(if ($bk.cc) { $bk.cc } else { "" })
        Buckets = $bl
        MsList = $ml
        Warp = ($bk.warp -in @("on", "plus") -or $bk.kind -eq "warp")
      }
    }
  }
  $letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  $slotIdx = 0
  $ipToCluster = @{}
  foreach ($gKey in $groupMap.Keys) {
    $g = $groupMap[$gKey]
    $avg = $null
    if ($g.MsList.Count -gt 0) {
      $sum = 0; foreach ($m in $g.MsList) { $sum += $m }
      $avg = [int][Math]::Round($sum / $g.MsList.Count)
    }
    $asnPart = if ($g.Asn) { "AS$($g.Asn) " } else { "" }
    $ccPart = if ($g.Cc) { " [$($g.Cc)]" } else { "" }
    $slotName = "出口 $($letters[$slotIdx])"
    $shortOrg = ($g.Org -replace "\s+(Communications|Corporation|Corp\.?|Inc\.?|LLC|Ltd\.?|Limited|Co\.?).*$", "").Trim()
    if ($shortOrg -match "Cloudflare") { $shortOrg = "WARP" }
    if (-not $shortOrg) { $shortOrg = $g.Org }
    $clItem = [ordered]@{
      Slot = $slotName
      Tone = if ($g.Warp) { "diff" } elseif ($slotIdx -eq 0) { "muted" } else { "ok" }
      Ip = $g.Ip
      AsnOrg = "$asnPart$($g.Org)$ccPart"
      ShortOrg = $shortOrg
      Buckets = ($g.Buckets -join " / ")
      AvgMs = $avg
      IsCn = $false
      Warp = $g.Warp
    }
    [void]$clusters.Add($clItem)
    $ipToCluster[$gKey] = $clItem
    $slotIdx += 1
  }

  # -------------------------------------------------------------------------
  # Layer 2 Opt-In Whitelist Controller Auto-Discovery & 16-Domain Audit
  # (Runs before finalizing [01]/[02]/JSON when -Inspect or -Controller is set,
  #  enabling anonymized per-service exit slot correlation with ZERO node-name leaks)
  # -------------------------------------------------------------------------
  function Invoke-PipeRequest {
    param([string]$PipeName, [string]$Path, [string]$ApiSecret, [int]$TimeoutMs = 200)
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $PipeName, [System.IO.Pipes.PipeDirection]::InOut)
    try {
      $pipe.Connect($TimeoutMs)
      $authHdr = if ($ApiSecret) { "Authorization: Bearer $ApiSecret`r`n" } else { "" }
      $reqText = "GET $Path HTTP/1.1`r`nHost: localhost`r`n${authHdr}Connection: close`r`n`r`n"
      $reqBytes = [System.Text.Encoding]::ASCII.GetBytes($reqText)
      $pipe.Write($reqBytes, 0, $reqBytes.Length)
      $pipe.Flush()
      $ms = New-Object System.IO.MemoryStream
      $buf = New-Object byte[] 8192
      while (($n = $pipe.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
      $all = $ms.ToArray(); $ms.Dispose()
      $sep = -1
      for ($i = 0; $i -le $all.Length - 4; $i++) {
        if ($all[$i] -eq 13 -and $all[$i + 1] -eq 10 -and $all[$i + 2] -eq 13 -and $all[$i + 3] -eq 10) { $sep = $i; break }
      }
      if ($sep -lt 0) { return @{ Code = "000"; Body = "" } }
      $hdr = [System.Text.Encoding]::ASCII.GetString($all, 0, $sep)
      $code = if ($hdr -match "HTTP/\S+\s+(\d{3})") { $Matches[1] } else { "000" }
      $bodyStart = $sep + 4
      if ($hdr -match "(?im)^Transfer-Encoding:\s*chunked") {
        $out = New-Object System.IO.MemoryStream
        $pos = $bodyStart
        while ($pos -lt $all.Length) {
          $eol = -1
          for ($j = $pos; $j -le $all.Length - 2; $j++) {
            if ($all[$j] -eq 13 -and $all[$j + 1] -eq 10) { $eol = $j; break }
          }
          if ($eol -lt 0) { break }
          $hexLine = [System.Text.Encoding]::ASCII.GetString($all, $pos, $eol - $pos).Trim()
          if ($hexLine -match "^([0-9a-fA-F]+)") { $hexLen = $Matches[1] } else { break }
          $chunkLen = [Convert]::ToInt32($hexLen, 16)
          if ($chunkLen -eq 0) { break }
          $dataPos = $eol + 2
          if ($dataPos + $chunkLen -gt $all.Length) { break }
          $out.Write($all, $dataPos, $chunkLen)
          $pos = $dataPos + $chunkLen + 2
        }
        $body = [System.Text.Encoding]::UTF8.GetString($out.ToArray())
        $out.Dispose()
      } else {
        $body = [System.Text.Encoding]::UTF8.GetString($all, $bodyStart, $all.Length - $bodyStart)
      }
      return @{ Code = $code; Body = $body }
    } catch {
      return @{ Code = "000"; Body = $_.Exception.Message }
    } finally {
      $pipe.Dispose()
    }
  }

  function Invoke-ControllerApi {
    param([string]$Endpoint, [string]$Path, [string]$ApiSecret, [int]$TimeoutMs = 1500)
    if ($Endpoint -match "^\\\\\.\\pipe\\(.+)$" -or $Endpoint -match "^pipe:(.+)$") {
      return Invoke-PipeRequest -PipeName $Matches[1] -Path $Path -ApiSecret $ApiSecret -TimeoutMs $TimeoutMs
    }
    $ctrlBase = $Endpoint.TrimEnd("/")
    $secTimeout = [Math]::Max(1, [int][Math]::Ceiling($TimeoutMs / 1000.0))
    $cArgs = @("-sS", "--noproxy", "*", "--connect-timeout", "1", "--max-time", "$secTimeout", "-w", "`n__HTTP__%{http_code}")
    if ($ApiSecret) { $cArgs += @("-H", "Authorization: Bearer $ApiSecret") }
    $cArgs += "$ctrlBase$Path"
    $raw = (& $curlBin @cArgs 2>$null) -join "`n"
    $code = "000"; $body = $raw
    if ($raw -match "(?s)^(.*)\r?\n__HTTP__(\d{3})\s*$") { $body = $Matches[1]; $code = $Matches[2] }
    return @{ Code = $code; Body = $body }
  }

  function Find-WhitelistController {
    param([string]$ExplicitEndpoint, [string]$ApiSecret)
    if ($ExplicitEndpoint) {
      $v = Invoke-ControllerApi -Endpoint $ExplicitEndpoint -Path "/version" -ApiSecret $ApiSecret -TimeoutMs 1500
      return @{ Endpoint = $ExplicitEndpoint; Label = "显式控制口"; Code = $v.Code; Body = $v.Body }
    }
    $whitelist = @(
      @{ Ep = "\\.\pipe\verge-mihomo";      Label = "Clash Verge Rev" },
      @{ Ep = "\\.\pipe\mihomo-party";      Label = "Mihomo Party" },
      @{ Ep = "\\.\pipe\ClashParty\mihomo"; Label = "Clash Party" },
      @{ Ep = "\\.\pipe\nyanpasu-mihomo";   Label = "Clash Nyanpasu" },
      @{ Ep = "\\.\pipe\mihomo";            Label = "Mihomo IPC" },
      @{ Ep = "http://127.0.0.1:9090";      Label = "Mihomo / sing-box TCP" },
      @{ Ep = "http://127.0.0.1:9097";      Label = "Clash Verge TCP" },
      @{ Ep = "http://127.0.0.1:9095";      Label = "本地控制口 TCP" }
    )
    $authHit = $null
    foreach ($cand in $whitelist) {
      $r = Invoke-ControllerApi -Endpoint $cand.Ep -Path "/version" -ApiSecret $ApiSecret -TimeoutMs 180
      if ($r.Code -eq "200") {
        return @{ Endpoint = $cand.Ep; Label = $cand.Label; Code = "200"; Body = $r.Body }
      }
      if (($r.Code -eq "401" -or $r.Code -eq "403") -and $null -eq $authHit) {
        $authHit = @{ Endpoint = $cand.Ep; Label = $cand.Label; Code = $r.Code; Body = $r.Body }
      }
    }
    if ($null -ne $authHit) { return $authHit }
    return $null
  }

  $script:localRuleRows = New-Object System.Collections.ArrayList
  $script:localRuleAllTargets = New-Object System.Collections.ArrayList
  $script:hostLeafMap = @{}
  $script:localRuleMeta = ""
  $script:localRuleErr = ""
  $script:localRuleWarn = ""
  $script:localRuleOkMsg = ""
  $script:didInspect = $false

  function Collect-LocalControllerAudit {
    param([string]$ExplicitEp, [string]$ApiSecret)
    $script:didInspect = $true
    $script:localRuleRows.Clear()
    $script:localRuleAllTargets.Clear()
    $script:hostLeafMap = @{}
    $script:localRuleMeta = ""
    $script:localRuleErr = ""
    $script:localRuleWarn = ""
    $script:localRuleOkMsg = ""

    $found = Find-WhitelistController -ExplicitEndpoint $ExplicitEp -ApiSecret $ApiSecret
    if ($null -eq $found) {
      $script:localRuleErr = "[INFO] 未在白名单控制口检测到 Mihomo/sing-box (已保底保留上方 6 桶黑盒分流图)"
      return
    }
    if ($found.Code -eq "401" -or $found.Code -eq "403") {
      if ($isInteractiveTty -and -not $ApiSecret) {
        Clear-ProgressBar
        Write-ColorText ("[INFO] 已发现 {0} ({1})，需要控制密钥 (HTTP {2})" -f $found.Endpoint, $found.Label, $found.Code) "Yellow"
        $entered = (Read-Host "请输入该控制口 Secret (直接回车跳过)").Trim()
        if ($entered) {
          $ApiSecret = $entered
          $re = Invoke-ControllerApi -Endpoint $found.Endpoint -Path "/version" -ApiSecret $ApiSecret -TimeoutMs 1500
          $found.Code = $re.Code
          $found.Body = $re.Body
        }
      }
      if ($found.Code -ne "200") {
        $script:localRuleErr = "[INFO] 控制口 $($found.Endpoint) 返回 HTTP $($found.Code)，请传 -Secret 后重试"
        return
      }
    }
    if ($found.Code -ne "200") {
      $script:localRuleErr = "[INFO] 无法连接控制口 $($found.Endpoint) (HTTP=$($found.Code))"
      return
    }

    $coreVer = ""
    try {
      $vj = $found.Body | ConvertFrom-Json
      if ($vj.version) { $coreVer = [string]$vj.version }
    } catch {}
    $script:localRuleMeta = "$($found.Label) · $($found.Endpoint)$(if($coreVer){" · $coreVer"})"

    $targets = @(
      @{ Host = "gemini.google.com";                         Group = "AI核心" },
      @{ Host = "aistudio.google.com";                       Group = "AI核心" },
      @{ Host = "notebooklm.google.com";                     Group = "AI核心" },
      @{ Host = "labs.google";                               Group = "AI核心" },
      @{ Host = "generativelanguage.googleapis.com";         Group = "AI核心" },
      @{ Host = "alkalimakersuite-pa.clients6.google.com";   Group = "AI后端" },
      @{ Host = "oauth2.googleapis.com";                     Group = "AI鉴权" },
      @{ Host = "accounts.google.com";                       Group = "AI鉴权" },
      @{ Host = "www.google.com";                            Group = "Google" },
      @{ Host = "play.google.com";                           Group = "Google" },
      @{ Host = "policies.google.com";                       Group = "Google" },
      @{ Host = "www.youtube.com";                           Group = "YouTube" },
      @{ Host = "redirector.googlevideo.com";                Group = "YouTube" },
      @{ Host = "chatgpt.com";                               Group = "跨AI" },
      @{ Host = "claude.ai";                                 Group = "跨AI" },
      @{ Host = "v4.ident.me";                               Group = "基线" }
    )

    $tls12 = [System.Security.Authentication.SslProtocols]3072
    $useHttpConnect = ($hasExplicitProxy -and -not $detectedTun -and $effectiveProxy -match "^https?://([^:/\s]+):(\d+)")
    $pxHost = if ($useHttpConnect) { $Matches[1] } else { "" }
    $pxPort = if ($useHttpConnect) { [int]$Matches[2] } else { 0 }

    $pending = @()
    $tlsPending = @()
    $sockets = @()
    try {
      foreach ($t in $targets) {
        try {
          $tcp = New-Object System.Net.Sockets.TcpClient
          $ar = if ($useHttpConnect) {
            $tcp.BeginConnect($pxHost, $pxPort, $null, $null)
          } else {
            $tcp.BeginConnect($t.Host, 443, $null, $null)
          }
          $pending += @{ Host = $t.Host; Tcp = $tcp; Ar = $ar }
        } catch {}
      }

      $tcpDeadline = [DateTime]::UtcNow.AddMilliseconds(1800)
      foreach ($pConn in $pending) {
        try {
          $remMs = [Math]::Max(1, [int]($tcpDeadline - [DateTime]::UtcNow).TotalMilliseconds)
          if ($pConn.Ar.AsyncWaitHandle.WaitOne($remMs, $false) -and $pConn.Tcp.Connected) {
            $pConn.Tcp.EndConnect($pConn.Ar)
            $ns = $pConn.Tcp.GetStream()
            $ns.ReadTimeout = 1600; $ns.WriteTimeout = 1600
            if ($useHttpConnect) {
              $req = [System.Text.Encoding]::ASCII.GetBytes("CONNECT $($pConn.Host):443 HTTP/1.1`r`nHost: $($pConn.Host):443`r`n`r`n")
              $ns.Write($req, 0, $req.Length); $ns.Flush()
              $rb = New-Object byte[] 512
              $rn = $ns.Read($rb, 0, $rb.Length)
              if ([System.Text.Encoding]::ASCII.GetString($rb, 0, $rn) -notmatch "HTTP/\S+\s+200") {
                $pConn.Tcp.Close(); continue
              }
            }
            $ssl = New-Object System.Net.Security.SslStream($ns, $false, { $true })
            $ssl.ReadTimeout = 2000; $ssl.WriteTimeout = 2000
            $sar = $ssl.BeginAuthenticateAsClient($pConn.Host, $null, $tls12, $false, $null, $null)
            $tlsPending += @{ Tcp = $pConn.Tcp; Ssl = $ssl; Sar = $sar }
          } else {
            $pConn.Tcp.Close()
          }
        } catch {
          try { $pConn.Tcp.Close() } catch {}
        }
      }

      $tlsDeadline = [DateTime]::UtcNow.AddMilliseconds(2400)
      foreach ($tp in $tlsPending) {
        try {
          $remMs = [Math]::Max(1, [int]($tlsDeadline - [DateTime]::UtcNow).TotalMilliseconds)
          if ($tp.Sar.AsyncWaitHandle.WaitOne($remMs, $false)) {
            $tp.Ssl.EndAuthenticateAsClient($tp.Sar)
            $sockets += @{ Tcp = $tp.Tcp; Ssl = $tp.Ssl }
          } else {
            try { $tp.Ssl.Dispose() } catch {}
            try { $tp.Tcp.Close() } catch {}
          }
        } catch {
          try { $tp.Ssl.Dispose() } catch {}
          try { $tp.Tcp.Close() } catch {}
        }
      }

      Start-Sleep -Milliseconds 250
      $cRes = Invoke-ControllerApi -Endpoint $found.Endpoint -Path "/connections" -ApiSecret $ApiSecret -TimeoutMs 2500
      if ($cRes.Code -ne "200") {
        $script:localRuleErr = "[INFO] 读取 /connections 失败 (HTTP=$($cRes.Code))"
        return
      }
      $conns = @(($cRes.Body | ConvertFrom-Json).connections)

      $aiTopGroups = @{}
      $aiMismatchHosts = @()
      $gemTopGroup = ""

      foreach ($t in $targets) {
        $h = $t.Host
        $hit = $conns | Where-Object { $_.metadata.host -eq $h -or $_.metadata.sniffHost -eq $h } | Select-Object -Last 1
        if ($hit) {
          $rLbl = if ($hit.rulePayload) { "$($hit.rule)($($hit.rulePayload))" } else { "$($hit.rule)" }
          $rawChains = @($hit.chains)
          $leafNode = if ($rawChains.Count -gt 0) { [string]$rawChains[0] } else { "" }
          $cArr = @($hit.chains)
          [Array]::Reverse($cArr)
          $topGrp = if ($cArr.Count -gt 0) { [string]$cArr[0] } else { "" }
          $chainStr = $cArr -join " -> "
          if ($leafNode) { $script:hostLeafMap[$h] = $leafNode }
          if ($h -eq "gemini.google.com") { $gemTopGroup = $topGrp }
          if ($t.Group -in @("AI核心", "AI后端", "AI鉴权") -and $topGrp) {
            $aiTopGroups[$topGrp] = $true
            if ($gemTopGroup -and $topGrp -ne $gemTopGroup) { $aiMismatchHosts += "$h -> $topGrp" }
          }
          $isMismatch = ($t.Group -in @("AI核心", "AI后端", "AI鉴权") -and $gemTopGroup -and $topGrp -ne $gemTopGroup)
          $entry = [ordered]@{ Host = $h; Group = $t.Group; Rule = $rLbl; Chain = $chainStr; Top = $topGrp; Leaf = $leafNode; Hit = $true; Mismatch = $isMismatch }
          [void]$script:localRuleRows.Add($entry)
          [void]$script:localRuleAllTargets.Add($entry)
        } else {
          [void]$script:localRuleAllTargets.Add([ordered]@{ Host = $h; Group = $t.Group; Rule = "(未捕获)"; Chain = "--"; Top = ""; Leaf = ""; Hit = $false; Mismatch = $false })
        }
      }

      if ($aiTopGroups.Count -gt 1) {
        $script:localRuleWarn = "Google AI 链路分裂! gemini.google.com 走 [$gemTopGroup]，但 $($aiMismatchHosts -join '; ')"
      } elseif ($aiTopGroups.Count -eq 1 -and $gemTopGroup) {
        $script:localRuleOkMsg = "Google AI 核心 + API + 鉴权域名全部收敛在同一策略组: $gemTopGroup"
      }
    } catch {
      $script:localRuleErr = "[INFO] 控制 API 解析异常: $($_.Exception.Message)"
    } finally {
      foreach ($s in $sockets) {
        try { $s.Ssl.Dispose() } catch {}
        try { $s.Tcp.Close() } catch {}
      }
    }
  }

  function Write-LocalControllerSection {
    Write-BoxRule "mid"
    Write-BoxLine "[03] 本地只读控制 API · 16 域按策略链聚合审计 (零截断 · 绝不入图/分享链)" "Cyan"
    if ($script:localRuleErr) {
      Write-BoxLine $script:localRuleErr "Yellow"
      return
    }
    if ($script:localRuleMeta) {
      Write-BoxLine ("已自动识别: {0}" -f $script:localRuleMeta) "DarkGray"
    }

    # Build anonymized leaf -> exit slot map strictly for local colored badge alignment
    $leafSlot = @{}
    if ($script:hostLeafMap.ContainsKey("v4.ident.me") -and $script:defCluster) {
      $leafSlot[$script:hostLeafMap["v4.ident.me"]] = $script:defCluster.Slot
    }
    if ($script:hostLeafMap.ContainsKey("chatgpt.com") -and $rtObj.Contains("oai") -and $rtObj.oai.ip) {
      $oc = $ipToCluster[$rtObj.oai.ip.ToLowerInvariant()]
      if ($oc) { $leafSlot[$script:hostLeafMap["chatgpt.com"]] = $oc.Slot }
    }
    if ($script:hostLeafMap.ContainsKey("claude.ai") -and $rtObj.Contains("cld") -and $rtObj.cld.ip) {
      $cc = $ipToCluster[$rtObj.cld.ip.ToLowerInvariant()]
      if ($cc) { $leafSlot[$script:hostLeafMap["claude.ai"]] = $cc.Slot }
    }

    # Group captured targets by full policy chain (zero truncation, anomaly groups floated to top)
    $chainGroups = [ordered]@{}
    $missedHosts = New-Object System.Collections.Generic.List[string]
    foreach ($lr in $script:localRuleAllTargets) {
      if (-not $lr.Hit) {
        $missedHosts.Add($lr.Host)
        continue
      }
      $ck = $lr.Chain
      if (-not $chainGroups.Contains($ck)) {
        $slotTag = ""
        if ($lr.Group -eq "YouTube" -and $script:ggcCluster) {
          $slotTag = $script:ggcCluster.Slot
        } elseif ($lr.Leaf -and $leafSlot.ContainsKey($lr.Leaf)) {
          $slotTag = $leafSlot[$lr.Leaf]
        }
        $chainGroups[$ck] = @{
          Chain = $ck
          Slot = $slotTag
          Count = 0
          HasMismatch = $false
          ByRule = [ordered]@{}
        }
      }
      $cg = $chainGroups[$ck]
      $cg.Count += 1
      if ($lr.Mismatch) { $cg.HasMismatch = $true }
      $ruleDisp = $lr.Rule
      if ($ruleDisp -match "^(Domain|DomainSuffix)\((.+)\)$" -and $Matches[2] -eq $lr.Host) {
        $ruleDisp = $Matches[1]
      }
      if (-not $cg.ByRule.Contains($ruleDisp)) {
        $cg.ByRule[$ruleDisp] = New-Object System.Collections.Generic.List[string]
      }
      $cg.ByRule[$ruleDisp].Add($lr.Host)
    }

    $orderedChains = @($chainGroups.Values | Where-Object { $_.HasMismatch }) + @($chainGroups.Values | Where-Object { -not $_.HasMismatch })
    foreach ($cg in $orderedChains) {
      $slotPrefix = if ($cg.Slot) { "[$($cg.Slot)] " } else { "[链路] " }
      $hdrCol = if ($cg.HasMismatch) { "Yellow" } elseif ($cg.Slot) { Get-ExitTermColor $cg.Slot } else { "Green" }
      $flagTxt = if ($cg.HasMismatch) { " [! 分裂]" } else { "" }
      Write-BoxWrapped -Prefix $slotPrefix -Text "$($cg.Chain) ($($cg.Count) 域)$flagTxt" -PrefixColor $hdrCol -TextColor $(if ($cg.HasMismatch) { "Yellow" } else { "White" }) -Indent 9
      foreach ($rk in $cg.ByRule.Keys) {
        $rLabel = "  - ${rk}: "
        $domList = ($cg.ByRule[$rk] -join ", ")
        Write-BoxWrapped -Prefix $rLabel -Text $domList -PrefixColor "DarkGray" -TextColor $(if ($cg.HasMismatch) { "Yellow" } else { "Gray" }) -Indent ([Math]::Min(26, (Get-DisplayWidth $rLabel)))
      }
    }

    if ($missedHosts.Count -gt 0) {
      Write-BoxWrapped -Prefix "  未捕获: " -Text ($missedHosts -join ", ") -PrefixColor "DarkGray" -TextColor "DarkGray" -Indent 10
    }
    if ($script:localRuleWarn) {
      Write-BoxLine ("[!] {0}" -f $script:localRuleWarn) "Yellow"
    } elseif ($script:localRuleOkMsg) {
      Write-BoxLine ("[OK] {0}" -f $script:localRuleOkMsg) "Green"
    }
  }

  if (($Inspect -or $Controller) -and -not $Json) {
    Write-ProgressBar 3 4 "白名单探测本地控制口并关联服务出口..."
    Collect-LocalControllerAudit -ExplicitEp $Controller -ApiSecret $Secret
  }

  # -------------------------------------------------------------------------
  # Anonymized Per-Service Exit Slot Correlation (ZERO Proxy Node Names!)
  # -------------------------------------------------------------------------
  $script:svcExit = [ordered]@{}
  $script:gemResolvedCluster = $null
  $script:ggcCluster = if ($p.gip -and $ipToCluster.ContainsKey($p.gip.ToLowerInvariant())) { $ipToCluster[$p.gip.ToLowerInvariant()] } else { $null }
  $script:defCluster = if ($p.ip -and $ipToCluster.ContainsKey($p.ip.ToLowerInvariant())) { $ipToCluster[$p.ip.ToLowerInvariant()] } else { $null }

  function Update-ServiceExitAttribution {
    $script:svcExit = [ordered]@{}
    $script:gemResolvedCluster = $null
    $ovTotal = ($clusters | Where-Object { -not $_.IsCn }).Count

    # Map local leaf node -> anonymized exit cluster strictly in memory
    $leafToCl = @{}
    if ($script:hostLeafMap.ContainsKey("v4.ident.me") -and $script:defCluster) {
      $leafToCl[$script:hostLeafMap["v4.ident.me"]] = $script:defCluster
    }
    if ($script:hostLeafMap.ContainsKey("chatgpt.com") -and $rtObj.Contains("oai") -and $rtObj.oai.ip) {
      $oc = $ipToCluster[$rtObj.oai.ip.ToLowerInvariant()]
      if ($oc) { $leafToCl[$script:hostLeafMap["chatgpt.com"]] = $oc }
    }
    if ($script:hostLeafMap.ContainsKey("claude.ai") -and $rtObj.Contains("cld") -and $rtObj.cld.ip) {
      $cc = $ipToCluster[$rtObj.cld.ip.ToLowerInvariant()]
      if ($cc) { $leafToCl[$script:hostLeafMap["claude.ai"]] = $cc }
    }

    function Format-ClusterRef {
      param($Cl)
      if ($null -eq $Cl) { return "" }
      $so = if ($Cl.ShortOrg -and $Cl.ShortOrg -ne "独立出口") {
        if ($Cl.ShortOrg -match "Cloudflare") { "WARP" } else { $Cl.ShortOrg }
      } else { "" }
      if ($so) { return "$($Cl.Slot) · $($Cl.Ip) · $so" }
      return "$($Cl.Slot) · $($Cl.Ip)"
    }

    function Resolve-HostExit {
      param([string]$HostName, [string]$FallbackHost = "")
      if ($ovTotal -le 1 -and $script:defCluster) {
        return @{ Text = (Format-ClusterRef $script:defCluster); Cluster = $script:defCluster }
      }
      $leaf = if ($script:hostLeafMap.ContainsKey($HostName)) { $script:hostLeafMap[$HostName] } elseif ($FallbackHost -and $script:hostLeafMap.ContainsKey($FallbackHost)) { $script:hostLeafMap[$FallbackHost] } else { "" }
      if ($leaf) {
        if ($leafToCl.ContainsKey($leaf)) {
          $cl = $leafToCl[$leaf]
          return @{ Text = (Format-ClusterRef $cl); Cluster = $cl }
        }
        return @{ Text = "独立分流出口 (非已有槽)"; Cluster = $null }
      }
      if (-not $splitHit -and $script:defCluster) {
        return @{ Text = (Format-ClusterRef $script:defCluster); Cluster = $script:defCluster }
      }
      return @{ Text = "多出口分流 (-Inspect 定位)"; Cluster = $null }
    }

    $rGem  = Resolve-HostExit "gemini.google.com"
    $rNlm  = Resolve-HostExit "notebooklm.google.com" "gemini.google.com"
    $rPlay = Resolve-HostExit "play.google.com" "www.google.com"
    $rSrch = Resolve-HostExit "www.google.com"
    $rTrm  = Resolve-HostExit "policies.google.com" "www.google.com"

    $script:gemResolvedCluster = $rGem.Cluster
    $ggcRef = if ($script:ggcCluster) { Format-ClusterRef $script:ggcCluster } elseif ($script:defCluster) { Format-ClusterRef $script:defCluster } else { "--" }
    $ytRef = $ggcRef
    if ($script:hostLeafMap.ContainsKey("www.youtube.com") -and $script:hostLeafMap.ContainsKey("redirector.googlevideo.com") -and $script:hostLeafMap["www.youtube.com"] -ne $script:hostLeafMap["redirector.googlevideo.com"]) {
      $rYt = Resolve-HostExit "www.youtube.com"
      $ytRef = $rYt.Text
    }

    $script:svcExit.gem  = $rGem.Text
    $script:svcExit.nlm  = $rNlm.Text
    $script:svcExit.yt   = $ytRef
    $script:svcExit.cdn  = $ggcRef
    $script:svcExit.play = $rPlay.Text
    $script:svcExit.srch = $rSrch.Text
    $script:svcExit.trm  = $rTrm.Text

    # Enrich [01] cluster bucket labels when Gemini/Google AI resolved to a distinct exit from YouTube GGC
    if ($script:gemResolvedCluster -and $script:ggcCluster -and $script:gemResolvedCluster.Slot -ne $script:ggcCluster.Slot) {
      if ($script:ggcCluster.Buckets -match "^Google/YT") {
        $script:ggcCluster.Buckets = $script:ggcCluster.Buckets -replace "^Google/YT", "YouTube/GGC"
      }
      if ($script:gemResolvedCluster.Buckets -notmatch "Gemini") {
        $script:gemResolvedCluster.Buckets = "Gemini/Search/Play / " + $script:gemResolvedCluster.Buckets
      }
    }

    # Attach anonymized exit slots into primary stack JSON (ZERO proxy node names)
    $p.ex = [ordered]@{}
    foreach ($ek in @("gem", "nlm", "yt", "cdn", "play", "srch", "trm")) {
      if ($script:svcExit[$ek] -and $script:svcExit[$ek] -notmatch "-Inspect") {
        $p.ex[$ek] = $script:svcExit[$ek]
      }
    }
    if ($p.ex.Count -eq 0) { $p.Remove("ex") }
  }

  Update-ServiceExitAttribution

  # -------------------------------------------------------------------------
  # Verdict & 4 Automated Split-Route Alarms
  # -------------------------------------------------------------------------
  function Test-StackDrift {
    param($S)
    if ($null -eq $S) { return $false }
    $hits = 0
    if (Test-RestrictedCountry $S.gem) { $hits += 2 }
    if ($S.nlm -eq "unavail") { $hits += 2 }
    if ($S.yt -eq "cn") { $hits += 2 }
    if ($S.yt -eq "noprem") { $hits += 1 }
    if (Test-RestrictedCountry $S.play) { $hits += 1 }
    if (Test-RestrictedCountry $S.trm) { $hits += 1 }
    if ($S.sdom -eq "hkredirect" -or $S.scap -eq "hk") { $hits += 1 }
    return ($hits -ge 2)
  }

  $d4 = Test-StackDrift $v4Data
  $d6 = Test-StackDrift $v6Data
  $dualConflict = ($null -ne $v4Data -and $null -ne $v6Data -and ($d4 -ne $d6 -or ($v4Data.gem -and $v6Data.gem -and $v4Data.gem -ne $v6Data.gem)))

  $alarms = New-Object System.Collections.Generic.List[string]
  $alarmMsgs = New-Object System.Collections.ArrayList
  if ($cnLeak) {
    $alarms.Add("cn_leak")
    [void]$alarmMsgs.Add(@{ Tone = "Red"; Text = "[!] 国内分流绕行: 国内桶返回 $($rtObj.cn.ip) ($($rtObj.cn.note))，请检查 CN 直连规则" })
  }
  if ($dualConflict) {
    $alarms.Add("stack_split")
    [void]$alarmMsgs.Add(@{ Tone = "Red"; Text = "[!] 双栈冲突: IPv4($($v4Data.gem)) 与 IPv6($($v6Data.gem)) 不一致，Google 优先 IPv6 易偶发报错" })
  }
  $aiIpSet = @{}
  foreach ($ak in @("ggc", "oai", "cld")) {
    if ($rtObj.Contains($ak) -and $rtObj[$ak].ip) { $aiIpSet[$rtObj[$ak].ip.ToLowerInvariant()] = $true }
  }
  if ($aiIpSet.Count -ge 2) {
    $alarms.Add("ai_split")
    [void]$alarmMsgs.Add(@{ Tone = "Yellow"; Text = "[i] 跨 AI 生态分流: YouTube/GGC · ChatGPT · Claude 命中了 $($aiIpSet.Count) 条不同海外出口" })
  }
  $hasWarpBucket = $false
  foreach ($cl in $clusters) { if ($cl.Warp) { $hasWarpBucket = $true } }
  if ($hasWarpBucket) {
    $alarms.Add("warp_egress")
    [void]$alarmMsgs.Add(@{ Tone = "Cyan"; Text = "[i] 检出 Cloudflare WARP 出站: 部分业务经 WARP 转发，有效隔离原始机房段" })
  }

  $effKind = if ($splitHit -and $p.gkind) { $p.gkind } else { $p.kind }
  $vTag = "CLEAN"; $vColor = "Green"
  $vText = if ($effKind -eq "hosting") { "云机房出口全绿可用 · 实测无送中无验证码 (反焦虑认证)" } else { "Google 全家桶全绿可用" }
  if ($dualConflict) {
    $vTag = "STACK_SPLIT"; $vColor = "Yellow"
    $vText = "双栈不对称: IPv4($($v4Data.gem)) vs IPv6($($v6Data.gem))，建议关闭冲突栈"
  } elseif ($d4 -or $d6) {
    $vTag = "CN_DRIFT"; $vColor = "Red"
    $vText = if ($p.cc -and -not (Test-RestrictedCountry $p.cc)) {
      "实锤 Google 私有库送中 (公开库 $($p.cc) / Apple $(if($appleCc){$appleCc}else{'?'})，但 Google 判受限)"
    } else { "Google 生态判定为受限地区 / 送中" }
  } elseif (($v4Data -and $v4Data.scap -eq "captcha") -or ($v6Data -and $v6Data.scap -eq "captcha")) {
    $vTag = "PARTIAL"; $vColor = "Yellow"
    $vText = "AI 核心可用，但 Google Search 触发 /sorry/ 人机验证"
  } elseif ($splitHit -or $slotIdx -ge 2) {
    $vTag = "SPLIT_ROUTE"; $vColor = "Cyan"
    if ($script:gemResolvedCluster -and $script:ggcCluster -and $script:gemResolvedCluster.Slot -ne $script:ggcCluster.Slot) {
      $vText = "跨组分流生效 · 检出 $slotIdx 路海外出口 (Google AI 经 $($script:gemResolvedCluster.ShortOrg) · YT 经 $($script:ggcCluster.ShortOrg))"
    } elseif ($p.gorg) {
      $vText = "跨组分流生效 · 检出 $slotIdx 路海外出口 (Google/YT 经 $($p.gorg) 可用)"
    } else {
      $vText = "跨组分流生效 · 检出 $slotIdx 路海外出口且 Google 全绿可用"
    }
  }

  # Build compact CliReportV1 JSON (100% backward compatible with V1/V2)
  $epoch = [int64][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $report = [ordered]@{
    v = 1
    t = $epoch
    m = $runMode
    os = "windows"
  }
  if ($detectedTun) { $report.tun = $true }
  if ($hasExplicitProxy) { $report.px = $true }
  if ($cnDirect) { $report.cn = $cnDirect }
  if ($appleCc) { $report.ap = $appleCc }
  $report.net = $netObj
  if ($rtObj.Count -gt 0) { $report.rt = $rtObj }
  if ($alarms.Count -gt 0) { $report.al = @($alarms) }
  if ($null -ne $v4Data) { $report.v4 = $v4Data }
  if ($null -ne $v6Data) { $report.v6 = $v6Data }

  $jsonText = $report | ConvertTo-Json -Depth 7 -Compress
  Clear-ProgressBar

  if ($Json) {
    Write-Output $jsonText
    return
  }

  # -------------------------------------------------------------------------
  # Terminal Swiss-Industrial Card Rendering
  # -------------------------------------------------------------------------
  function Format-Cell {
    param([string]$Kind, $S)
    if ($null -eq $S) { return @{ Text = "N/A"; Color = "DarkGray"; Ms = "" } }
    $msTxt = ""
    if ($S.rtt) {
      $mKey = switch ($Kind) { "gem" { "gem" } "nlm" { "nlm" } "yt" { "yt" } "cdn" { "cdn" } "play" { "play" } "search" { "srch" } default { "" } }
      if ($mKey -and $S.rtt.Contains($mKey)) { $msTxt = "$($S.rtt[$mKey])ms" }
    }
    $okPfx = if ($Ascii) { "[OK] " } else { "$([char]0x2713) " }
    $wnPfx = if ($Ascii) { "[!] " } else { "! " }
    $noPfx = if ($Ascii) { "[X] " } else { "$([char]0x2715) " }
    switch ($Kind) {
      "gem" {
        if (-not $S.gem) { return @{ Text = "N/A"; Color = "DarkGray"; Tone = "muted"; Ms = $msTxt } }
        if (Test-RestrictedCountry $S.gem) { return @{ Text = "${noPfx}BLOCKED [$($S.gem)]"; Color = "Red"; Tone = "leak"; Ms = $msTxt } }
        return @{ Text = "${okPfx}OK [$($S.gem)]"; Color = "Green"; Tone = "ok"; Ms = $msTxt }
      }
      "nlm" {
        if ($S.nlm -eq "ok") { return @{ Text = "${okPfx}OK (301)"; Color = "Green"; Tone = "ok"; Ms = $msTxt } }
        if ($S.nlm -eq "unavail") { return @{ Text = "${noPfx}BLOCKED (302)"; Color = "Red"; Tone = "leak"; Ms = $msTxt } }
        return @{ Text = "N/A"; Color = "DarkGray"; Tone = "muted"; Ms = $msTxt }
      }
      "yt" {
        if ($S.yt -eq "ok") { return @{ Text = "${okPfx}OK [$($S.ytg)]"; Color = "Green"; Tone = "ok"; Ms = $msTxt } }
        if ($S.yt -eq "cn") { return @{ Text = "${noPfx}CN_DRIFT"; Color = "Red"; Tone = "leak"; Ms = $msTxt } }
        if ($S.yt -eq "noprem") { return @{ Text = "${noPfx}NO_PREM (GL=$($S.ytg))"; Color = "Red"; Tone = "leak"; Ms = $msTxt } }
        return @{ Text = "N/A"; Color = "DarkGray"; Tone = "muted"; Ms = $msTxt }
      }
      "cdn" {
        if (-not $S.cdn) { return @{ Text = "N/A"; Color = "DarkGray"; Tone = "muted"; Ms = $msTxt } }
        $t = $S.cdn + $(if ($S.cdnu) { " [u]" } else { "" })
        if ($S.ip -and $S.gip -and $S.ip -ne $S.gip) { return @{ Text = "${okPfx}$t"; Color = "Green"; Tone = "ok"; Ms = $msTxt } }
        return @{ Text = "${okPfx}$t"; Color = "Green"; Tone = "ok"; Ms = $msTxt }
      }
      "play" {
        if (-not $S.play) { return @{ Text = "N/A"; Color = "DarkGray"; Tone = "muted"; Ms = $msTxt } }
        if (Test-RestrictedCountry $S.play) { return @{ Text = "${noPfx}$($S.play) [CN]"; Color = "Red"; Tone = "leak"; Ms = $msTxt } }
        return @{ Text = "${okPfx}$($S.play)"; Color = "Green"; Tone = "ok"; Ms = $msTxt }
      }
      "search" {
        if ($S.scap -eq "captcha") { return @{ Text = "${wnPfx}CAPTCHA (/sorry)"; Color = "Yellow"; Tone = "diff"; Ms = $msTxt } }
        if ($S.sdom -eq "hkredirect" -or $S.scap -eq "hk") { return @{ Text = "${noPfx}HK_REDIRECT (.hk)"; Color = "Red"; Tone = "leak"; Ms = $msTxt } }
        if ($S.sdom -or $S.scap -eq "ok") { return @{ Text = "${okPfx}$(if($S.sdom){$S.sdom}else{'OK'}) (Clean)"; Color = "Green"; Tone = "ok"; Ms = $msTxt } }
        return @{ Text = "N/A"; Color = "DarkGray"; Tone = "muted"; Ms = $msTxt }
      }
      "terms" {
        if (-not $S.trm) { return @{ Text = "N/A"; Color = "DarkGray"; Tone = "muted"; Ms = "" } }
        if (Test-RestrictedCountry $S.trm) { return @{ Text = "${noPfx}$($S.trm) [CN]"; Color = "Red"; Tone = "leak"; Ms = "" } }
        if ($S.ent -eq "Google Ireland Limited") { return @{ Text = "${wnPfx}$($S.trm) (EEA)"; Color = "Yellow"; Tone = "diff"; Ms = "" } }
        return @{ Text = "${okPfx}$($S.trm)"; Color = "Green"; Tone = "ok"; Ms = "" }
      }
    }
  }

  $utcTime = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm UTC")
  Write-BoxRule "top"
  $leftTitle = "G-ROUTE v3 // Google 生态体检卡"
  $rightMeta = "[$netLabel] $utcTime"
  $titleW = ($W - 4) - (Get-DisplayWidth $rightMeta) - 1
  if ($titleW -lt 26) {
    Write-BoxLine "$leftTitle" "Cyan"
    Write-BoxLine "$rightMeta" "DarkGray"
  } else {
    Write-BoxSegments @(
      @{ Text = $leftTitle; Width = $titleW; Color = "Cyan" },
      @{ Text = " "; Width = 1 },
      @{ Text = $rightMeta; Color = "DarkGray" }
    )
  }
  Write-BoxRule "mid"
  Write-BoxSegments @(
    @{ Text = "结论  "; Width = 6; Color = "White" },
    @{ Text = "[$vTag] "; Color = $vColor },
    @{ Text = $vText; Color = "White" }
  )
  Write-BoxLine ("三方对照: 公开库={0}  |  Apple={1}  |  Google 实测={2}  |  DNS={3}" -f $(if($p.cc){$p.cc}else{"?"}), $(if($appleCc){$appleCc}else{"?"}), $(if($p.gem){$p.gem}else{"?"}), $(if($p.dns){$p.dns}else{"--"})) "DarkGray"

  # Section [01] 6-Bucket Split-Route Topology Radar
  Write-BoxRule "mid"
  $ovCount = ($clusters | Where-Object { -not $_.IsCn }).Count
  Write-BoxLine ("[01] 6 桶分流拓扑雷达 (自动聚类: {0} 路海外出口{1})" -f $ovCount, $(if ($cnDirect) { " + 国内直连" } else { "" })) "Cyan"
  $sW = 11; $ipW = if ($Compact) { 18 } else { 40 }; $msW = 7
  $bkW = ($W - 4) - $sW - $ipW - $msW - 3
  Write-BoxSegments @(
    @{ Text = "出口槽"; Width = $sW; Color = "White" },
    @{ Text = " "; Width = 1 },
    @{ Text = "出口 IP / 归属"; Width = $ipW; Color = "White" },
    @{ Text = " "; Width = 1 },
    @{ Text = "命中业务桶"; Width = $bkW; Color = "White" },
    @{ Text = " "; Width = 1 },
    @{ Text = "RTT"; Width = $msW; Color = "White" }
  )
  foreach ($cl in $clusters) {
    $cCol = if ($cl.Tone -eq "leak") { "Red" } else { Get-ExitTermColor $cl.Slot }
    $msDisp = if ($null -ne $cl.AvgMs) { "$($cl.AvgMs)ms" } else { "--" }
    $ipOrg = "$($cl.Ip) $($cl.AsnOrg)"
    Write-BoxSegments @(
      @{ Text = "[$($cl.Slot)]"; Width = $sW; Color = $cCol },
      @{ Text = " "; Width = 1 },
      @{ Text = $ipOrg; Width = $ipW; Color = "Gray" },
      @{ Text = " "; Width = 1 },
      @{ Text = $cl.Buckets; Width = $bkW; Color = $cCol },
      @{ Text = " "; Width = 1 },
      @{ Text = $msDisp; Width = $msW; Color = "DarkGray" }
    )
  }
  foreach ($am in $alarmMsgs) {
    Write-BoxLine $am.Text $am.Tone
  }

  # Section [02] Google 6-Way Ground Truth Matrix
  Write-BoxRule "mid"
  $rows = @(
    @{ Key = "gem";    ExKey = "gem";  Name = "Gemini (Boq)" },
    @{ Key = "nlm";    ExKey = "nlm";  Name = "NotebookLM (1-RTT)" },
    @{ Key = "yt";     ExKey = "yt";   Name = "YouTube Premium" },
    @{ Key = "cdn";    ExKey = "cdn";  Name = "YouTube GGC CDN" },
    @{ Key = "play";   ExKey = "play"; Name = "Google Play" },
    @{ Key = "search"; ExKey = "srch"; Name = "Google Search" },
    @{ Key = "terms";  ExKey = "trm";  Name = "Google Terms" }
  )

  if ($null -ne $v4Data -and $null -ne $v6Data) {
    Write-BoxLine "[02] Google 生态 6 路真值矩阵 (IPv4 + IPv6 双栈)" "Cyan"
    $nW = 19; $c4W = [int][Math]::Floor((($W - 4) - $nW - 2) / 2); $c6W = ($W - 4) - $nW - $c4W - 2
    Write-BoxSegments @(
      @{ Text = "服务维度"; Width = $nW; Color = "White" },
      @{ Text = " "; Width = 1 },
      @{ Text = "IPv4 ($($v4Data.ip))"; Width = $c4W; Color = "White" },
      @{ Text = " "; Width = 1 },
      @{ Text = "IPv6 ($($v6Data.ip))"; Width = $c6W; Color = "White" }
    )
    foreach ($r in $rows) {
      $c4 = Format-Cell $r.Key $v4Data
      $c6 = Format-Cell $r.Key $v6Data
      Write-BoxSegments @(
        @{ Text = $r.Name; Width = $nW; Color = "Gray" },
        @{ Text = " "; Width = 1 },
        @{ Text = $c4.Text; Width = $c4W; Color = $c4.Color },
        @{ Text = " "; Width = 1 },
        @{ Text = $c6.Text; Width = $c6W; Color = $c6.Color }
      )
    }
  } else {
    $stTitle = if ($ovCount -gt 1) { "IPv$pVer · 各服务实测出口见右列" } else { "IPv$pVer · 出口 A ($($p.ip))" }
    Write-BoxLine "[02] Google 生态 6 路真值矩阵 ($stTitle)" "Cyan"
    $nW = 19; $vW = if ($Compact) { 21 } else { 24 }; $mW = 7; $ntW = ($W - 4) - $nW - $vW - $mW - 3
    Write-BoxSegments @(
      @{ Text = "服务维度"; Width = $nW; Color = "White" },
      @{ Text = " "; Width = 1 },
      @{ Text = "实测结果"; Width = $vW; Color = "White" },
      @{ Text = " "; Width = 1 },
      @{ Text = "RTT"; Width = $mW; Color = "White" },
      @{ Text = " "; Width = 1 },
      @{ Text = "实测出口 (匿名槽位)"; Width = $ntW; Color = "White" }
    )
    foreach ($r in $rows) {
      $c = Format-Cell $r.Key $p
      $exDisp = if ($script:svcExit.Contains($r.ExKey)) { $script:svcExit[$r.ExKey] } else { "--" }
      $exSp = Split-ExitDisplay $exDisp
      $exCol = Get-ExitTermColor $exSp.Slot
      if ($exSp.Slot) {
        $tagTxt = "[$($exSp.Slot)] "
        $tagW = Get-DisplayWidth $tagTxt
        Write-BoxSegments @(
          @{ Text = $r.Name; Width = $nW; Color = "White" },
          @{ Text = " "; Width = 1 },
          @{ Text = $c.Text; Width = $vW; Color = $c.Color },
          @{ Text = " "; Width = 1 },
          @{ Text = $(if ($c.Ms) { $c.Ms } else { "--" }); Width = $mW; Color = "DarkGray" },
          @{ Text = " "; Width = 1 },
          @{ Text = $tagTxt; Width = $tagW; Color = $exCol },
          @{ Text = $exSp.Rest; Width = ($ntW - $tagW); Color = "Gray" }
        )
      } else {
        Write-BoxSegments @(
          @{ Text = $r.Name; Width = $nW; Color = "White" },
          @{ Text = " "; Width = 1 },
          @{ Text = $c.Text; Width = $vW; Color = $c.Color },
          @{ Text = " "; Width = 1 },
          @{ Text = $(if ($c.Ms) { $c.Ms } else { "--" }); Width = $mW; Color = "DarkGray" },
          @{ Text = " "; Width = 1 },
          @{ Text = $exDisp; Width = $ntW; Color = "Yellow" }
        )
      }
    }
  }

  # Optional Section [03]: Opt-In Local Controller Audit
  if ($script:didInspect) {
    Write-LocalControllerSection
  }

  Write-BoxRule "bot"

  # -------------------------------------------------------------------------
  # Zero-Dependency Offline SVG & Windows Native .NET PNG Exporters
  # -------------------------------------------------------------------------
  function Escape-Xml {
    param([string]$S)
    if ($null -eq $S) { return "" }
    return $S.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace('"', "&quot;").Replace("'", "&#39;")
  }

  function Get-Palette {
    param([string]$Mode)
    if ($Mode -eq "dark") {
      return @{
        Bg = "#16181e"; BgSub = "#1e2129"; BgIns = "#111318"
        Fg = "#eceae3"; FgMut = "#a2a5b0"; FgFnt = "#727684"
        Rule = "#323642"; Strong = "#dcdad2"
        Ok = "#56c288"; OkBg = "#193025"
        Diff = "#e0a546"; DiffBg = "#302719"
        Leak = "#eb6f63"; LeakBg = "#331d1c"
        ExCn = @("#2dd4bf", "#133432"); ExA = @("#60a5fa", "#172554")
        ExB  = @("#fb923c", "#431407"); ExC = @("#a78bfa", "#2e1065")
        ExD  = @("#f472b6", "#500724")
      }
    }
    return @{
      Bg = "#f7f6f1"; BgSub = "#efede6"; BgIns = "#e7e4dc"
      Fg = "#1b1d24"; FgMut = "#5b5e68"; FgFnt = "#858892"
      Rule = "#ccc9c0"; Strong = "#242731"
      Ok = "#146c43"; OkBg = "#dcf4e6"
      Diff = "#9a5b0c"; DiffBg = "#fae8c8"
      Leak = "#b42318"; LeakBg = "#fbdad7"
      ExCn = @("#0f766e", "#d6f5f0"); ExA = @("#1d4ed8", "#dbeafe")
      ExB  = @("#c2410c", "#ffedd5"); ExC = @("#6d28d9", "#ede9fe")
      ExD  = @("#be185d", "#fce7f3")
    }
  }

  function Get-ExitPalPair {
    param($Pal, [string]$Key)
    switch ($Key) {
      "cn" { return $Pal.ExCn }
      "a"  { return $Pal.ExA }
      "b"  { return $Pal.ExB }
      "c"  { return $Pal.ExC }
      "d"  { return $Pal.ExD }
      default { return @($Pal.FgMut, $Pal.BgSub) }
    }
  }

  function Export-LocalSvg {
    param([string]$OutPath)
    if (-not $OutPath) {
      $stamp = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
      $OutPath = Join-Path (Get-Location).Path "g-route-$stamp.svg"
    }
    $pal = Get-Palette $Theme
    $svgW = 920; $pad = 28; $inner = $svgW - $pad * 2
    $includeLocalRules = ($WithRules -and $script:localRuleRows.Count -gt 0)
    $clusterH = 34 + ($clusters.Count * 30) + ($alarmMsgs.Count * 22) + 12
    $matrixH = 34 + ($rows.Count * 34) + 10
    $rulesH = if ($includeLocalRules) { 36 + ($script:localRuleRows.Count * 24) + 16 } else { 0 }
    $svgH = $pad + 52 + 86 + $clusterH + $matrixH + $rulesH + 44 + $pad

    $vCol = if ($vColor -eq "Red") { $pal.Leak } elseif ($vColor -eq "Yellow") { $pal.Diff } else { $pal.Ok }
    $vBg  = if ($vColor -eq "Red") { $pal.LeakBg } elseif ($vColor -eq "Yellow") { $pal.DiffBg } else { $pal.OkBg }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine("<svg xmlns=""http://www.w3.org/2000/svg"" width=""$svgW"" height=""$svgH"" viewBox=""0 0 $svgW $svgH"">")
    [void]$sb.AppendLine("<defs><style>.m{font-family:ui-monospace,'Cascadia Mono','SF Mono',Consolas,'Noto Sans Mono CJK SC','Microsoft YaHei',monospace}.s{font-family:'PingFang SC','Microsoft YaHei','Noto Sans SC',system-ui,sans-serif}</style>")
    [void]$sb.AppendLine("<clipPath id=""cardClip""><rect x=""$($pad + 14)"" y=""0"" width=""$($inner - 28)"" height=""$svgH""/></clipPath></defs>")
    [void]$sb.AppendLine("<rect x=""0"" y=""0"" width=""$svgW"" height=""$svgH"" fill=""$($pal.Bg)""/>")
    [void]$sb.AppendLine("<rect x=""$pad"" y=""$pad"" width=""$inner"" height=""$($svgH - $pad * 2)"" fill=""$($pal.Bg)"" stroke=""$($pal.Strong)"" stroke-width=""2""/>")

    $y = $pad
    # Header
    [void]$sb.AppendLine("<rect x=""$($pad + 1)"" y=""$($y + 1)"" width=""$($inner - 2)"" height=""51"" fill=""$($pal.BgSub)""/>")
    [void]$sb.AppendLine("<text x=""$($pad + 18)"" y=""$($y + 31)"" class=""m"" font-size=""14"" font-weight=""700"" fill=""$($pal.Fg)"">G-ROUTE v3 // GOOGLE 生态送中与分流体检卡</text>")
    [void]$sb.AppendLine("<text x=""$($pad + $inner - 18)"" y=""$($y + 31)"" class=""m"" font-size=""11.5"" text-anchor=""end"" fill=""$($pal.FgMut)"">$(Escape-Xml "$netLabel  ·  $utcTime")</text>")
    $y += 52
    [void]$sb.AppendLine("<line x1=""$pad"" y1=""$y"" x2=""$($pad + $inner)"" y2=""$y"" stroke=""$($pal.Strong)"" stroke-width=""1""/>")

    # Verdict
    $tagW = [Math]::Max(86, ($vTag.Length + 4) * 9)
    [void]$sb.AppendLine("<rect x=""$($pad + 18)"" y=""$($y + 16)"" width=""$tagW"" height=""26"" fill=""$vBg"" stroke=""$vCol"" stroke-width=""1""/>")
    [void]$sb.AppendLine("<text x=""$($pad + 18 + ($tagW / 2))"" y=""$($y + 33)"" class=""m"" font-size=""12"" font-weight=""700"" text-anchor=""middle"" fill=""$vCol"">[$vTag]</text>")
    [void]$sb.AppendLine("<text x=""$($pad + 28 + $tagW)"" y=""$($y + 34)"" class=""s"" font-size=""15"" font-weight=""700"" fill=""$($pal.Fg)"" clip-path=""url(#cardClip)"">$(Escape-Xml (Clip-Display $vText 76))</text>")
    $geoLine = "三方对照: 公开库=$(if($p.cc){$p.cc}else{'?'})  |  Apple=$(if($appleCc){$appleCc}else{'?'})  |  Google 实测=$(if($p.gem){$p.gem}else{'?'})  |  通用出口: $($p.ip) (AS$(if($p.asn){$p.asn}else{'?'}) $($p.org))"
    [void]$sb.AppendLine("<text x=""$($pad + 18)"" y=""$($y + 66)"" class=""m"" font-size=""11.5"" fill=""$($pal.FgMut)"" clip-path=""url(#cardClip)"">$(Escape-Xml (Clip-Display $geoLine 96))</text>")
    $y += 86
    [void]$sb.AppendLine("<line x1=""$pad"" y1=""$y"" x2=""$($pad + $inner)"" y2=""$y"" stroke=""$($pal.Strong)"" stroke-width=""1""/>")

    # Section 01: 6-Bucket Split-Route Radar
    [void]$sb.AppendLine("<rect x=""$($pad + 1)"" y=""$($y + 1)"" width=""$($inner - 2)"" height=""31"" fill=""$($pal.BgSub)""/>")
    [void]$sb.AppendLine("<text x=""$($pad + 18)"" y=""$($y + 21)"" class=""m"" font-size=""11.5"" font-weight=""700"" fill=""$($pal.FgMut)"">[01] 6 桶分流拓扑雷达 · 自动聚类 ($ovCount 路海外出口)</text>")
    [void]$sb.AppendLine("<text x=""$($pad + $inner - 18)"" y=""$($y + 21)"" class=""m"" font-size=""11"" text-anchor=""end"" fill=""$($pal.FgFnt)"">RTT</text>")
    $y += 32
    foreach ($cl in $clusters) {
      [void]$sb.AppendLine("<line x1=""$pad"" y1=""$y"" x2=""$($pad + $inner)"" y2=""$y"" stroke=""$($pal.Rule)"" stroke-width=""1""/>")
      $ep = if ($cl.Tone -eq "leak") { @($pal.Leak, $pal.LeakBg) } else { Get-ExitPalPair $pal (Get-ExitSlotKey $cl.Slot) }
      $sc = $ep[0]; $sbBg = $ep[1]
      [void]$sb.AppendLine("<rect x=""$($pad + 18)"" y=""$($y + 5)"" width=""74"" height=""20"" fill=""$sbBg"" stroke=""$sc"" stroke-width=""1""/>")
      [void]$sb.AppendLine("<text x=""$($pad + 55)"" y=""$($y + 19)"" class=""m"" font-size=""11"" font-weight=""700"" text-anchor=""middle"" fill=""$sc"">$(Escape-Xml $cl.Slot)</text>")
      [void]$sb.AppendLine("<text x=""$($pad + 104)"" y=""$($y + 19)"" class=""m"" font-size=""11.2"" fill=""$($pal.Fg)"">$(Escape-Xml (Clip-Display "$($cl.Ip) · $($cl.AsnOrg)" 49))</text>")
      [void]$sb.AppendLine("<text x=""$($pad + 492)"" y=""$($y + 19)"" class=""s"" font-size=""11.5"" fill=""$($pal.FgMut)"">$(Escape-Xml (Clip-Display $cl.Buckets 38))</text>")
      $msTxt = if ($null -ne $cl.AvgMs) { "$($cl.AvgMs) ms" } else { "--" }
      [void]$sb.AppendLine("<text x=""$($pad + $inner - 18)"" y=""$($y + 19)"" class=""m"" font-size=""11"" text-anchor=""end"" fill=""$($pal.FgFnt)"">$msTxt</text>")
      $y += 30
    }
    foreach ($am in $alarmMsgs) {
      $ac = if ($am.Tone -eq "Red") { $pal.Leak } elseif ($am.Tone -eq "Yellow") { $pal.Diff } else { $pal.Ok }
      [void]$sb.AppendLine("<text x=""$($pad + 18)"" y=""$($y + 15)"" class=""s"" font-size=""11.5"" fill=""$ac"">$(Escape-Xml (Clip-Display $am.Text 92))</text>")
      $y += 22
    }
    $y += 14
    [void]$sb.AppendLine("<line x1=""$pad"" y1=""$y"" x2=""$($pad + $inner)"" y2=""$y"" stroke=""$($pal.Strong)"" stroke-width=""1""/>")

    # Section 02: Google 6-Way Matrix
    [void]$sb.AppendLine("<rect x=""$($pad + 1)"" y=""$($y + 1)"" width=""$($inner - 2)"" height=""31"" fill=""$($pal.BgSub)""/>")
    [void]$sb.AppendLine("<text x=""$($pad + 18)"" y=""$($y + 21)"" class=""m"" font-size=""11.5"" font-weight=""700"" fill=""$($pal.FgMut)"">[02] GOOGLE 生态 6 路真值矩阵</text>")
    if ($null -ne $v4Data -and $null -ne $v6Data) {
      [void]$sb.AppendLine("<text x=""$($pad + 270)"" y=""$($y + 21)"" class=""m"" font-size=""11"" fill=""$($pal.FgMut)"">IPv4 ($(Escape-Xml $v4Data.ip))</text>")
      [void]$sb.AppendLine("<text x=""$($pad + 560)"" y=""$($y + 21)"" class=""m"" font-size=""11"" fill=""$($pal.FgMut)"">IPv6 ($(Escape-Xml $v6Data.ip))</text>")
    } else {
      [void]$sb.AppendLine("<text x=""$($pad + 244)"" y=""$($y + 21)"" class=""m"" font-size=""11"" fill=""$($pal.FgMut)"">实测结论</text>")
      [void]$sb.AppendLine("<text x=""$($pad + 474)"" y=""$($y + 21)"" class=""m"" font-size=""11"" fill=""$($pal.FgMut)"">实测出口 (匿名槽位)</text>")
      [void]$sb.AppendLine("<text x=""$($pad + $inner - 18)"" y=""$($y + 21)"" class=""m"" font-size=""11"" text-anchor=""end"" fill=""$($pal.FgFnt)"">RTT</text>")
    }
    $y += 32

    foreach ($r in $rows) {
      [void]$sb.AppendLine("<line x1=""$pad"" y1=""$y"" x2=""$($pad + $inner)"" y2=""$y"" stroke=""$($pal.Rule)"" stroke-width=""1""/>")
      [void]$sb.AppendLine("<text x=""$($pad + 18)"" y=""$($y + 21)"" class=""s"" font-size=""12.5"" font-weight=""600"" fill=""$($pal.Fg)"">$(Escape-Xml $r.Name)</text>")
      if ($null -ne $v4Data -and $null -ne $v6Data) {
        $c4 = Format-Cell $r.Key $v4Data
        $c6 = Format-Cell $r.Key $v6Data
        $c4Fg = if ($c4.Color -eq "Red") { $pal.Leak } elseif ($c4.Color -eq "Yellow") { $pal.Diff } elseif ($c4.Color -eq "Green") { $pal.Ok } else { $pal.FgMut }
        $c6Fg = if ($c6.Color -eq "Red") { $pal.Leak } elseif ($c6.Color -eq "Yellow") { $pal.Diff } elseif ($c6.Color -eq "Green") { $pal.Ok } else { $pal.FgMut }
        [void]$sb.AppendLine("<text x=""$($pad + 270)"" y=""$($y + 21)"" class=""m"" font-size=""12"" font-weight=""600"" fill=""$c4Fg"">$(Escape-Xml $c4.Text)</text>")
        [void]$sb.AppendLine("<text x=""$($pad + 560)"" y=""$($y + 21)"" class=""m"" font-size=""12"" font-weight=""600"" fill=""$c6Fg"">$(Escape-Xml $c6.Text)</text>")
      } else {
        $c = Format-Cell $r.Key $p
        $cFg = if ($c.Tone -eq "leak") { $pal.Leak } elseif ($c.Tone -eq "diff") { $pal.Diff } elseif ($c.Tone -eq "ok") { $pal.Ok } else { $pal.FgMut }
        $cBg = if ($c.Tone -eq "leak") { $pal.LeakBg } elseif ($c.Tone -eq "diff") { $pal.DiffBg } elseif ($c.Tone -eq "ok") { $pal.OkBg } else { $pal.BgSub }
        $pillW = [Math]::Min(206, [Math]::Max(86, ((Get-DisplayWidth $c.Text) * 8) + 18))
        [void]$sb.AppendLine("<rect x=""$($pad + 244)"" y=""$($y + 6)"" width=""$pillW"" height=""22"" fill=""$cBg"" stroke=""$cFg"" stroke-width=""1""/>")
        [void]$sb.AppendLine("<text x=""$($pad + 252)"" y=""$($y + 21)"" class=""m"" font-size=""11.5"" font-weight=""700"" fill=""$cFg"">$(Escape-Xml $c.Text)</text>")

        $exTxt = if ($script:svcExit.Contains($r.ExKey)) { $script:svcExit[$r.ExKey] } else { "--" }
        $exSp = Split-ExitDisplay $exTxt
        if ($exSp.Slot) {
          $ep = Get-ExitPalPair $pal $exSp.Key
          [void]$sb.AppendLine("<rect x=""$($pad + 474)"" y=""$($y + 7)"" width=""62"" height=""20"" fill=""$($ep[1])"" stroke=""$($ep[0])"" stroke-width=""1""/>")
          [void]$sb.AppendLine("<text x=""$($pad + 505)"" y=""$($y + 21)"" class=""m"" font-size=""10.5"" font-weight=""700"" text-anchor=""middle"" fill=""$($ep[0])"">$(Escape-Xml $exSp.Slot)</text>")
          [void]$sb.AppendLine("<text x=""$($pad + 544)"" y=""$($y + 21)"" class=""m"" font-size=""11.5"" fill=""$($pal.Fg)"">$(Escape-Xml (Clip-Display $exSp.Rest 28))</text>")
        } else {
          [void]$sb.AppendLine("<text x=""$($pad + 474)"" y=""$($y + 21)"" class=""m"" font-size=""11.5"" fill=""$($pal.FgMut)"">$(Escape-Xml (Clip-Display $exTxt 34))</text>")
        }
        $mStr = if ($c.Ms) { $c.Ms } else { "--" }
        [void]$sb.AppendLine("<text x=""$($pad + $inner - 18)"" y=""$($y + 21)"" class=""m"" font-size=""11"" text-anchor=""end"" fill=""$($pal.FgFnt)"">$mStr</text>")
      }
      $y += 34
    }
    $y += 12

    if ($includeLocalRules) {
      [void]$sb.AppendLine("<line x1=""$pad"" y1=""$y"" x2=""$($pad + $inner)"" y2=""$y"" stroke=""$($pal.Strong)"" stroke-width=""1""/>")
      [void]$sb.AppendLine("<rect x=""$($pad + 1)"" y=""$($y + 1)"" width=""$($inner - 2)"" height=""31"" fill=""$($pal.BgSub)""/>")
      [void]$sb.AppendLine("<text x=""$($pad + 18)"" y=""$($y + 21)"" class=""m"" font-size=""11.5"" font-weight=""700"" fill=""$($pal.FgMut)"">[03] 本地控制 API 存档 (-WithRules 已显式启用 · 含本机策略链)</text>")
      $y += 34
      foreach ($lr in $script:localRuleRows) {
        [void]$sb.AppendLine("<text x=""$($pad + 18)"" y=""$($y + 16)"" class=""m"" font-size=""11"" fill=""$($pal.Fg)"">$(Escape-Xml (Clip-Display $lr.Host 32))</text>")
        [void]$sb.AppendLine("<text x=""$($pad + 290)"" y=""$($y + 16)"" class=""m"" font-size=""11"" fill=""$($pal.FgMut)"">$(Escape-Xml (Clip-Display $lr.Rule 24))</text>")
        [void]$sb.AppendLine("<text x=""$($pad + 480)"" y=""$($y + 16)"" class=""s"" font-size=""11"" fill=""$($pal.Ok)"">$(Escape-Xml (Clip-Display $lr.Chain 44))</text>")
        $y += 24
      }
      $y += 14
    }

    # Footer
    [void]$sb.AppendLine("<line x1=""$pad"" y1=""$y"" x2=""$($pad + $inner)"" y2=""$y"" stroke=""$($pal.Strong)"" stroke-width=""1""/>")
    [void]$sb.AppendLine("<text x=""$($pad + 18)"" y=""$($y + 27)"" class=""m"" font-size=""11"" fill=""$($pal.FgMut)"">G-ROUTE · Tier 0 本地离线直出 · 零数据上传 · 不打欺诈分 · $(if($includeLocalRules){'含个人存档策略链'}else{'已隐去本机节点名'})</text>")
    [void]$sb.AppendLine("<text x=""$($pad + $inner - 18)"" y=""$($y + 27)"" class=""m"" font-size=""11"" text-anchor=""end"" fill=""$($pal.FgFnt)"">IP: $(Escape-Xml $p.ip) · $vTag</text>")
    [void]$sb.AppendLine("</svg>")

    [IO.File]::WriteAllText($OutPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-ColorText "[OK] 已本地离线生成矢量 SVG 体检卡: $OutPath" "Green"
  }

  function Export-LocalPng {
    param([string]$OutPath)
    if (-not $OutPath) {
      $stamp = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
      $OutPath = Join-Path (Get-Location).Path "g-route-$stamp.png"
    }
    try {
      Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    } catch {
      Write-ColorText "[INFO] 当前环境缺少 System.Drawing，无法直接导出 PNG，请改用 SVG (-Svg)。" "Yellow"
      return
    }
    $pal = Get-Palette $Theme
    $toColor = { param($hex) [System.Drawing.ColorTranslator]::FromHtml($hex) }
    $pngW = 920; $pad = 28; $inner = $pngW - $pad * 2
    $includeLocalRules = ($WithRules -and $script:localRuleRows.Count -gt 0)
    $clusterH = 34 + ($clusters.Count * 30) + ($alarmMsgs.Count * 22) + 12
    $matrixH = 34 + ($rows.Count * 34) + 10
    $rulesH = if ($includeLocalRules) { 36 + ($script:localRuleRows.Count * 24) + 16 } else { 0 }
    $pngH = $pad + 52 + 86 + $clusterH + $matrixH + $rulesH + 44 + $pad
    $dpr = 2

    $bmp = New-Object System.Drawing.Bitmap(($pngW * $dpr), ($pngH * $dpr))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
      $g.ScaleTransform($dpr, $dpr)
      $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
      $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

      $brBg    = New-Object System.Drawing.SolidBrush(& $toColor $pal.Bg)
      $brSub   = New-Object System.Drawing.SolidBrush(& $toColor $pal.BgSub)
      $brFg    = New-Object System.Drawing.SolidBrush(& $toColor $pal.Fg)
      $brMut   = New-Object System.Drawing.SolidBrush(& $toColor $pal.FgMut)
      $brFnt   = New-Object System.Drawing.SolidBrush(& $toColor $pal.FgFnt)
      $brOk    = New-Object System.Drawing.SolidBrush(& $toColor $pal.Ok)
      $brOkBg  = New-Object System.Drawing.SolidBrush(& $toColor $pal.OkBg)
      $brDiff  = New-Object System.Drawing.SolidBrush(& $toColor $pal.Diff)
      $brDiffBg = New-Object System.Drawing.SolidBrush(& $toColor $pal.DiffBg)
      $brLeak  = New-Object System.Drawing.SolidBrush(& $toColor $pal.Leak)
      $brLeakBg = New-Object System.Drawing.SolidBrush(& $toColor $pal.LeakBg)
      $penStrong2 = New-Object System.Drawing.Pen((& $toColor $pal.Strong), 2)
      $penStrong1 = New-Object System.Drawing.Pen((& $toColor $pal.Strong), 1)
      $penRule    = New-Object System.Drawing.Pen((& $toColor $pal.Rule), 1)

      $fMonoB = New-Object System.Drawing.Font("Consolas", 10.5, [System.Drawing.FontStyle]::Bold)
      $fMono  = New-Object System.Drawing.Font("Consolas", 9.0,  [System.Drawing.FontStyle]::Regular)
      $fMonoS = New-Object System.Drawing.Font("Consolas", 8.2,  [System.Drawing.FontStyle]::Bold)
      $fSansH = New-Object System.Drawing.Font("Microsoft YaHei", 11.5, [System.Drawing.FontStyle]::Bold)
      $fSansB = New-Object System.Drawing.Font("Microsoft YaHei", 9.2,  [System.Drawing.FontStyle]::Bold)
      $fSans  = New-Object System.Drawing.Font("Microsoft YaHei", 8.8,  [System.Drawing.FontStyle]::Regular)

      $sfRight = New-Object System.Drawing.StringFormat
      $sfRight.Alignment = [System.Drawing.StringAlignment]::Far
      $sfCenter = New-Object System.Drawing.StringFormat
      $sfCenter.Alignment = [System.Drawing.StringAlignment]::Center
      $sfCenter.LineAlignment = [System.Drawing.StringAlignment]::Center

      $g.FillRectangle($brBg, 0, 0, $pngW, $pngH)
      $g.DrawRectangle($penStrong2, $pad, $pad, $inner, ($pngH - $pad * 2))

      $y = $pad
      $g.FillRectangle($brSub, ($pad + 1), ($y + 1), ($inner - 2), 51)
      $g.DrawString("G-ROUTE v3 // GOOGLE 生态送中与分流体检卡", $fMonoB, $brFg, ($pad + 16), ($y + 18))
      $g.DrawString("$netLabel · $utcTime", $fMono, $brMut, (New-Object System.Drawing.RectangleF(($pad + 340), ($y + 18), ($inner - 356), 24)), $sfRight)
      $y += 52
      $g.DrawLine($penStrong1, $pad, $y, ($pad + $inner), $y)

      $vBr   = if ($vColor -eq "Red") { $brLeak } elseif ($vColor -eq "Yellow") { $brDiff } else { $brOk }
      $vBrBg = if ($vColor -eq "Red") { $brLeakBg } elseif ($vColor -eq "Yellow") { $brDiffBg } else { $brOkBg }
      $vPen  = New-Object System.Drawing.Pen($vBr.Color, 1)
      $tagW = [Math]::Max(90, ($vTag.Length + 4) * 9)
      $tagRect = New-Object System.Drawing.RectangleF(($pad + 16), ($y + 16), $tagW, 26)
      $g.FillRectangle($vBrBg, $tagRect)
      $g.DrawRectangle($vPen, ($pad + 16), ($y + 16), $tagW, 26)
      $g.DrawString("[$vTag]", $fMonoS, $vBr, $tagRect, $sfCenter)
      $g.DrawString((Clip-Display $vText 76), $fSansH, $brFg, ($pad + 26 + $tagW), ($y + 18))
      $geoLine = "三方对照: 公开库=$(if($p.cc){$p.cc}else{'?'}) | Apple=$(if($appleCc){$appleCc}else{'?'}) | Google=$(if($p.gem){$p.gem}else{'?'}) | 通用: $($p.ip) (AS$(if($p.asn){$p.asn}else{'?'}) $($p.org))"
      $g.DrawString((Clip-Display $geoLine 92), $fMono, $brMut, ($pad + 16), ($y + 54))
      $y += 86
      $g.DrawLine($penStrong1, $pad, $y, ($pad + $inner), $y)

      # 01 Radar
      $g.FillRectangle($brSub, ($pad + 1), ($y + 1), ($inner - 2), 31)
      $g.DrawString("[01] 6 桶分流拓扑雷达 · 自动聚类 ($ovCount 路海外出口)", $fMonoS, $brMut, ($pad + 16), ($y + 9))
      $g.DrawString("RTT", $fMonoS, $brFnt, (New-Object System.Drawing.RectangleF(($pad + $inner - 80), ($y + 9), 64, 18)), $sfRight)
      $y += 32
      foreach ($cl in $clusters) {
        $g.DrawLine($penRule, $pad, $y, ($pad + $inner), $y)
        $ep = if ($cl.Tone -eq "leak") { @($pal.Leak, $pal.LeakBg) } else { Get-ExitPalPair $pal (Get-ExitSlotKey $cl.Slot) }
        $cBr = New-Object System.Drawing.SolidBrush(& $toColor $ep[0])
        $cBg = New-Object System.Drawing.SolidBrush(& $toColor $ep[1])
        $cPen = New-Object System.Drawing.Pen($cBr.Color, 1)
        $sRect = New-Object System.Drawing.RectangleF(($pad + 16), ($y + 5), 74, 20)
        $g.FillRectangle($cBg, $sRect); $g.DrawRectangle($cPen, ($pad + 16), ($y + 5), 74, 20)
        $g.DrawString($cl.Slot, $fMonoS, $cBr, $sRect, $sfCenter)
        $g.DrawString((Clip-Display "$($cl.Ip) · $($cl.AsnOrg)" 49), $fMono, $brFg, ($pad + 100), ($y + 7))
        $g.DrawString((Clip-Display $cl.Buckets 38), $fSans, $brMut, ($pad + 492), ($y + 7))
        $msTxt = if ($null -ne $cl.AvgMs) { "$($cl.AvgMs) ms" } else { "--" }
        $g.DrawString($msTxt, $fMono, $brFnt, (New-Object System.Drawing.RectangleF(($pad + $inner - 86), ($y + 7), 70, 18)), $sfRight)
        $cPen.Dispose(); $cBr.Dispose(); $cBg.Dispose()
        $y += 30
      }
      foreach ($am in $alarmMsgs) {
        $aBr = if ($am.Tone -eq "Red") { $brLeak } elseif ($am.Tone -eq "Yellow") { $brDiff } else { $brOk }
        $g.DrawString((Clip-Display $am.Text 88), $fSans, $aBr, ($pad + 16), ($y + 3))
        $y += 22
      }
      $y += 14
      $g.DrawLine($penStrong1, $pad, $y, ($pad + $inner), $y)

      # 02 Google 6-Way Matrix
      $g.FillRectangle($brSub, ($pad + 1), ($y + 1), ($inner - 2), 31)
      $g.DrawString("[02] GOOGLE 生态 6 路真值矩阵", $fMonoS, $brMut, ($pad + 16), ($y + 9))
      if ($null -ne $v4Data -and $null -ne $v6Data) {
        $g.DrawString("IPv4 ($($v4Data.ip))", $fMonoS, $brMut, ($pad + 270), ($y + 9))
        $g.DrawString("IPv6 ($($v6Data.ip))", $fMonoS, $brMut, ($pad + 560), ($y + 9))
      } else {
        $g.DrawString("实测结论", $fMonoS, $brMut, ($pad + 244), ($y + 9))
        $g.DrawString("实测出口 (匿名槽位)", $fMonoS, $brMut, ($pad + 474), ($y + 9))
        $g.DrawString("RTT", $fMonoS, $brFnt, (New-Object System.Drawing.RectangleF(($pad + $inner - 80), ($y + 9), 64, 18)), $sfRight)
      }
      $y += 32
      foreach ($r in $rows) {
        $g.DrawLine($penRule, $pad, $y, ($pad + $inner), $y)
        $g.DrawString($r.Name, $fSansB, $brFg, ($pad + 16), ($y + 8))
        if ($null -ne $v4Data -and $null -ne $v6Data) {
          $c4 = Format-Cell $r.Key $v4Data; $c6 = Format-Cell $r.Key $v6Data
          $b4 = if ($c4.Color -eq "Red") { $brLeak } elseif ($c4.Color -eq "Yellow") { $brDiff } elseif ($c4.Color -eq "Green") { $brOk } else { $brMut }
          $b6 = if ($c6.Color -eq "Red") { $brLeak } elseif ($c6.Color -eq "Yellow") { $brDiff } elseif ($c6.Color -eq "Green") { $brOk } else { $brMut }
          $g.DrawString($c4.Text, $fMonoS, $b4, ($pad + 270), ($y + 9))
          $g.DrawString($c6.Text, $fMonoS, $b6, ($pad + 560), ($y + 9))
        } else {
          $c = Format-Cell $r.Key $p
          $bC   = if ($c.Tone -eq "leak") { $brLeak } elseif ($c.Tone -eq "diff") { $brDiff } elseif ($c.Tone -eq "ok") { $brOk } else { $brMut }
          $bCBg = if ($c.Tone -eq "leak") { $brLeakBg } elseif ($c.Tone -eq "diff") { $brDiffBg } elseif ($c.Tone -eq "ok") { $brOkBg } else { $brSub }
          $pPen = New-Object System.Drawing.Pen($bC.Color, 1)
          $pillW = [Math]::Min(212, [Math]::Max(86, [int][Math]::Ceiling($g.MeasureString($c.Text, $fMonoS).Width) + 14))
          $pRect = New-Object System.Drawing.RectangleF(($pad + 244), ($y + 6), $pillW, 22)
          $g.FillRectangle($bCBg, $pRect); $g.DrawRectangle($pPen, ($pad + 244), ($y + 6), $pillW, 22)
          $g.DrawString($c.Text, $fMonoS, $bC, ($pad + 251), ($y + 9))
          $pPen.Dispose()

          $exTxt = if ($script:svcExit.Contains($r.ExKey)) { $script:svcExit[$r.ExKey] } else { "--" }
          $exSp = Split-ExitDisplay $exTxt
          if ($exSp.Slot) {
            $ep = Get-ExitPalPair $pal $exSp.Key
            $eBr = New-Object System.Drawing.SolidBrush(& $toColor $ep[0])
            $eBg = New-Object System.Drawing.SolidBrush(& $toColor $ep[1])
            $ePen = New-Object System.Drawing.Pen($eBr.Color, 1)
            $eRect = New-Object System.Drawing.RectangleF(($pad + 474), ($y + 7), 62, 20)
            $g.FillRectangle($eBg, $eRect); $g.DrawRectangle($ePen, ($pad + 474), ($y + 7), 62, 20)
            $g.DrawString($exSp.Slot, $fMonoS, $eBr, $eRect, $sfCenter)
            $g.DrawString((Clip-Display $exSp.Rest 28), $fMono, $brFg, ($pad + 544), ($y + 9))
            $ePen.Dispose(); $eBr.Dispose(); $eBg.Dispose()
          } else {
            $g.DrawString((Clip-Display $exTxt 34), $fMono, $brMut, ($pad + 474), ($y + 9))
          }
          $mStr = if ($c.Ms) { $c.Ms } else { "--" }
          $g.DrawString($mStr, $fMono, $brFnt, (New-Object System.Drawing.RectangleF(($pad + $inner - 86), ($y + 9), 70, 18)), $sfRight)
        }
        $y += 34
      }
      $y += 12

      if ($includeLocalRules) {
        $g.DrawLine($penStrong1, $pad, $y, ($pad + $inner), $y)
        $g.FillRectangle($brSub, ($pad + 1), ($y + 1), ($inner - 2), 31)
        $g.DrawString("[03] 本地控制 API 存档 (-WithRules 已显式启用)", $fMonoS, $brMut, ($pad + 16), ($y + 9))
        $y += 34
        foreach ($lr in $script:localRuleRows) {
          $g.DrawString((Clip-Display $lr.Host 32), $fMono, $brFg, ($pad + 16), ($y + 4))
          $g.DrawString((Clip-Display $lr.Rule 24), $fMono, $brMut, ($pad + 290), ($y + 4))
          $g.DrawString((Clip-Display $lr.Chain 42), $fSans, $brOk, ($pad + 480), ($y + 4))
          $y += 24
        }
        $y += 14
      }

      $g.DrawLine($penStrong1, $pad, $y, ($pad + $inner), $y)
      $g.DrawString("G-ROUTE · Tier 0 本地离线直出 · 零数据上传 · 不打欺诈分", $fMono, $brMut, ($pad + 16), ($y + 14))
      $g.DrawString("IP: $($p.ip) · $vTag", $fMono, $brFnt, (New-Object System.Drawing.RectangleF(($pad + $inner - 240), ($y + 14), 224, 18)), $sfRight)

      $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
      Write-ColorText "[OK] 已本地离线生成 2x 高清 PNG 体检卡: $OutPath" "Green"
      $vPen.Dispose()
    } finally {
      $g.Dispose()
      $bmp.Dispose()
    }
  }

  # -------------------------------------------------------------------------
  # Offline Payload Link + Direct CLI Export Triggers
  # -------------------------------------------------------------------------
  function ConvertTo-GzipBase64Url {
    param([string]$Text)
    $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $ms = New-Object System.IO.MemoryStream
    $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    $gz.Write($rawBytes, 0, $rawBytes.Length)
    $gz.Close()
    $gzBytes = $ms.ToArray()
    $ms.Close()
    $b64 = [Convert]::ToBase64String($gzBytes).Replace("+", "-").Replace("/", "_").TrimEnd("=")
    return "z:$b64"
  }

  if ($Svg -or $SvgPath) { Export-LocalSvg -OutPath $SvgPath }
  if ($Png -or $PngPath) { Export-LocalPng -OutPath $PngPath }

  if (-not $NoLink) {
    $payload = ConvertTo-GzipBase64Url -Text $jsonText
    if ($G_ROUTE_ORIGIN -match "^https?://") {
      Write-ColorText "Web 体检卡 & PNG 导出:" "Cyan"
      Write-Host "$G_ROUTE_ORIGIN/#r=$payload"
    } else {
      Write-ColorText "离线报告码 (粘贴到 G-ROUTE 网页渲染体检卡 / 双卡 Diff):" "Cyan"
      Write-Host "G1:$payload"
    }
  }
  Write-ColorText "注: 100% 本地探测并离线编码，IP 已默认脱敏(-Full 显示完整)，零数据上传。" "DarkGray"

  # -------------------------------------------------------------------------
  # Post-Run Interactive Quick Actions (No Re-Probing Needed!)
  # -------------------------------------------------------------------------
  if ($isInteractiveTty -and -not $NoMenu -and -not $Quick) {
    while ($true) {
      $opts = @("[S] 本地存 SVG", "[P] 本地存 PNG")
      if (-not $script:didInspect) { $opts += "[R] 补查本机代理分组" }
      $opts += "[Enter] 退出"
      Write-Host ""
      $act = (Read-Host ("快捷操作: " + ($opts -join "  "))).Trim().ToUpperInvariant()
      if ($act -eq "" -or $act -eq "Q") { break }
      elseif ($act -eq "S") { Export-LocalSvg -OutPath "" }
      elseif ($act -eq "P") { Export-LocalPng -OutPath "" }
      elseif ($act -eq "R" -and -not $script:didInspect) {
        Collect-LocalControllerAudit -ExplicitEp $Controller -ApiSecret $Secret
        Update-ServiceExitAttribution
        Write-BoxRule "top"
        Write-LocalControllerSection
        Write-BoxRule "bot"
        Write-ColorText "[OK] 已同步更新各 Google 服务匿名出口槽，现在按 S/P 导出 SVG/PNG 即可包含精确出口标注。" "Cyan"
      }
    }
  }
} finally {
  Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
