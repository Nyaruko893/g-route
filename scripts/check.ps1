<#
.SYNOPSIS
  G-ROUTE // Google 生态送中与分流体检仪 (Windows PowerShell 5.1 & 7)
  权限契约：零 UAC 提权 · 零读磁盘配置/代理订阅/SSH/Cookie · 零数据上传 · 零二进制下载
  支持直接运行或 irm https://<origin>/ps | iex；零第三方依赖，100% 本地探测并离线编码 #r= 链接。

.EXAMPLE
  .\check.ps1
  .\check.ps1 -DryRun
  .\check.ps1 -Controller "http://127.0.0.1:9090" -Secret "your-secret"
  .\check.ps1 -Proxy "http://127.0.0.1:7890" -Full -V4
#>
[CmdletBinding()]
param(
  [string]$Proxy = "",
  [string]$Controller = "",
  [string]$Secret = "",
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

$G_ROUTE_ORIGIN = if ($env:G_ROUTE_ORIGIN) { $env:G_ROUTE_ORIGIN } else { "__G_ROUTE_ORIGIN__" }
if (-not $Controller -and $env:G_ROUTE_CONTROLLER) { $Controller = $env:G_ROUTE_CONTROLLER }
if (-not $Secret -and $env:G_ROUTE_SECRET) { $Secret = $env:G_ROUTE_SECRET }

$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
$SocsCookie = "YSC=FSCWhKo2Zgw; SOCS=CAISHAgBEhJnd3NfMjAyNDA1MjctMF9SQzIaAmVuIAEaBgiA_LyaBg"

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

$effectiveProxy = Resolve-EffectiveProxy

if ($DryRun) {
  Write-Host ("=" * 72) -ForegroundColor DarkGray
  Write-Host "G-ROUTE // -DryRun 零发包安全审计清单 (未发送任何网络请求)" -ForegroundColor Cyan
  Write-Host ("=" * 72) -ForegroundColor DarkGray
  Write-Host "[权限边界 · 4 个绝不]" -ForegroundColor Yellow
  Write-Host "  1. 绝不申请 UAC / 管理员提权"
  Write-Host "  2. 绝不读取磁盘配置文件 (%APPDATA% 代理订阅、~/.ssh、浏览器 Cookie)"
  Write-Host "  3. 绝不向任何服务器上传检测结果 (#r= 链接 100% 本地离线压缩编码)"
  Write-Host "  4. 绝不下载二进制文件或执行远程混淆代码"
  Write-Host "`n[将发起的只读 HTTPS GET/HEAD 请求]" -ForegroundColor Yellow
  Write-Host "  - https://myip.ipip.net                               (国内直连分流参照)"
  Write-Host "  - https://gspe1-ssl.ls.apple.com/pep/gcc              (Apple 第三方地域对照)"
  Write-Host "  - https://v4.ident.me/json / https://v6.ident.me/json (双栈出口 ASN，备选 ipify)"
  Write-Host "  - https://redirector.googlevideo.com/report_mapping   (YouTube GGC 边缘与 Google 实见 IP)"
  Write-Host "  - https://ipwho.is/<google_exit_ip>                   (仅当 Google 实见 IP ≠ 通用 IP 且非 WARP 时查询)"
  Write-Host "  - https://gemini.google.com/app                       (Gemini Boq 3 位国码)"
  Write-Host "  - https://notebooklm.google.com/                      (NotebookLM 1-RTT 301/302 头)"
  Write-Host "  - https://www.youtube.com/premium                     (YouTube 送中与半隐身判据)"
  Write-Host "  - https://play.google.com/                            (Google Play 归属国)"
  Write-Host "  - https://www.google.com/searchdomaincheck?format=domain (Search 域与 hkredirect)"
  Write-Host "  - https://www.google.com/search?q=curl&ie=UTF-8       (Search 验证码 / .com.hk 跳转)"
  Write-Host "  - https://policies.google.com/terms?hl=en             (Terms 条款辖区与 EEA 实体)"
  Write-Host "`n[当前会话配置]" -ForegroundColor Yellow
  Write-Host ("  - IP 脱敏: {0}" -f $(if ($Full) { "关闭 (-Full 完整显示)" } else { "开启 (默认 38.59.*.*)" }))
  Write-Host ("  - 显式/系统代理: {0}" -f $(if ($effectiveProxy) { $effectiveProxy } else { "无 (直连或由 TUN 接管)" }))
  Write-Host ("  - 本地控制 API: {0}" -f $(if ($Controller) { "$Controller (仅本屏只读查询 /connections，绝不写入 #r=)" } else { "未开启 (纯黑盒模式；仅显式传 -Controller 时启用)" }))
  Write-Host ("=" * 72) -ForegroundColor DarkGray
  return
}

$curlBin = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
if (-not $curlBin) {
  Write-Host "ERROR: 未找到 curl.exe（Windows 10/11 默认内置于 System32）" -ForegroundColor Red
  return
}

$runV4 = $true
$runV6 = $true
if ($V4 -and -not $V6) { $runV6 = $false }
if ($V6 -and -not $V4) { $runV4 = $false }

$hasExplicitProxy = ($effectiveProxy -ne "")
$detectedTun = $false

$baseArgs = @("-sS", "--max-time", "9", "-A", $UA)
if ($hasExplicitProxy) { $baseArgs += @("-x", $effectiveProxy) }

function Invoke-CurlRaw {
  param([string[]]$ExtraArgs)
  $all = $baseArgs + $ExtraArgs
  $out = & $curlBin @all 2>$null
  return @{
    Code = $LASTEXITCODE
    Text = ($out -join "`n")
  }
}

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
  param([string]$Org, [string]$IdentType, [string]$RawIp = "")
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
      if ($addr -match "^(142\.250\.|142\.251\.|172\.217\.|172\.253\.|216\.58\.|216\.239\.|74\.125\.|64\.233\.|209\.85\.|108\.177\.|192\.178\.|66\.102\.|66\.249\.|34\.|35\.)") {
        return "native"
      }
      return "viadns"
    } else {
      if ($addr -match "^(2607:f8b0:|2404:6800:|2a00:1450:|2800:3f0:)") { return "native" }
      return "viadns"
    }
  } catch {
    return "skip"
  }
}

function Write-ProgressLine {
  param([string]$Msg)
  if (-not $Json) {
    Write-Host ("`r[G-ROUTE] {0,-58}" -f $Msg) -NoNewline -ForegroundColor DarkGray
  }
}

Write-ProgressLine "探测国内分流基线与 Apple 第三方对照..."
$cnRaw = (Invoke-CurlRaw @("--max-time", "4", "https://myip.ipip.net")).Text
$cnDirect = ""
if ($cnRaw -match "中国" -and $cnRaw -notmatch "香港|澳门|台湾") {
  $cnDirect = "CN"
}

$appleRaw = (Invoke-CurlRaw @("-4", "--max-time", "5", "https://gspe1-ssl.ls.apple.com/pep/gcc")).Text.Trim().ToUpperInvariant()
$appleCc = if ($appleRaw -match "^[A-Z]{2}$") { $appleRaw } else { "" }

function Invoke-StackProbe {
  param([int]$Ver)
  $sflag = "-$Ver"
  Write-ProgressLine "IPv${Ver}: 探测出口身份与 YouTube GGC 边缘..."

  $identRes = Invoke-CurlRaw @($sflag, "--max-time", "6", "https://v$Ver.ident.me/json")
  $identObj = $null
  if ($identRes.Code -eq 0 -and $identRes.Text.Trim().StartsWith("{")) {
    try { $identObj = $identRes.Text | ConvertFrom-Json } catch {}
  }
  $rawIp = if ($identObj -and $identObj.ip) { [string]$identObj.ip } else { "" }
  if (-not $rawIp) {
    $ipifyRes = Invoke-CurlRaw @($sflag, "--max-time", "5", "https://api$Ver.ipify.org?format=json")
    if ($ipifyRes.Code -eq 0 -and $ipifyRes.Text.Trim().StartsWith("{")) {
      try { $rawIp = [string]($ipifyRes.Text | ConvertFrom-Json).ip } catch {}
    }
  }
  if (-not $rawIp) { return $null }

  $org = if ($identObj -and $identObj.aso) { [string]$identObj.aso } else { "" }
  $asn = if ($identObj -and $identObj.asn) { [int]$identObj.asn } else { $null }
  $cc = if ($identObj -and $identObj.cc) { ([string]$identObj.cc).ToUpperInvariant() } else { "" }
  $city = if ($identObj -and $identObj.city) { [string]$identObj.city } else { "" }
  $kind = Get-KindFromOrg -Org $org -IdentType $(if ($identObj) { [string]$identObj.type } else { "" }) -RawIp $rawIp

  # 1. YouTube GGC CDN + Google-seen IP + dual-egress ASN lookup when gip != ip
  $rmapRes = Invoke-CurlRaw @($sflag, "--max-time", "6", "https://redirector.googlevideo.com/report_mapping")
  $gipRaw = ""; $cdn = ""; $cdnu = $false
  $gasn = $null; $gorg = ""; $gkind = ""
  if ($rmapRes.Code -eq 0 -and $rmapRes.Text -match "(?m)^(\S+)\s+=>\s+(\S+)(.*)$") {
    $gipRaw = $Matches[1].Trim()
    $cdn = $Matches[2].Trim()
    if ($Matches[3] -match "\[u\]") { $cdnu = $true }
  }

  if ($gipRaw -and $gipRaw -ne $rawIp) {
    if (Test-WarpIp $gipRaw) {
      $gasn = 13335
      $gorg = "Cloudflare WARP"
      $gkind = "warp"
    } else {
      $gwhoRes = Invoke-CurlRaw @("--max-time", "4", "https://ipwho.is/$gipRaw")
      if ($gwhoRes.Code -eq 0 -and $gwhoRes.Text.Trim().StartsWith("{")) {
        try {
          $gw = $gwhoRes.Text | ConvertFrom-Json
          if ($gw.success -and $gw.connection) {
            if ($gw.connection.asn) { $gasn = [int]$gw.connection.asn }
            $gorg = if ($gw.connection.org) { [string]$gw.connection.org } elseif ($gw.connection.isp) { [string]$gw.connection.isp } else { "" }
            $gkind = Get-KindFromOrg -Org $gorg -IdentType "" -RawIp $gipRaw
          }
        } catch {}
      }
    }
  }

  # 2. Gemini Boq + TUN Fake-IP detection
  Write-ProgressLine "IPv${Ver}: 探测 Gemini / NotebookLM..."
  $tmpGem = [IO.Path]::GetTempFileName()
  $gemCc = ""
  try {
    $gemMeta = Invoke-CurlRaw @($sflag, "-L", "--max-time", "9", "-o", $tmpGem, "-w", "IP=%{remote_ip}", "https://gemini.google.com/app")
    if ($gemMeta.Code -eq 0) {
      if ($gemMeta.Text -match "IP=(198\.(18|19)\.\d+\.\d+|fc[0-9a-f:]+|fd[0-9a-f:]+)") {
        $script:detectedTun = $true
      }
      $gemHtml = [IO.File]::ReadAllText($tmpGem)
      if ($gemHtml -match ',2,1,200,"([A-Z]{3})"') { $gemCc = $Matches[1] }
      elseif ($gemHtml -match '"countryCode":"([A-Z]{2})"') { $gemCc = $Matches[1] }
    }
  } finally {
    Remove-Item $tmpGem -Force -ErrorAction SilentlyContinue
  }

  # 3. NotebookLM 1-RTT header check
  $nlmHdr = Invoke-CurlRaw @($sflag, "--max-time", "7", "-I", "https://notebooklm.google.com/")
  $nlmStatus = "err"
  if ($nlmHdr.Code -eq 0) {
    if ($nlmHdr.Text -match "(?im)^location:.*location=unsupported") {
      $nlmStatus = "unavail"
    } elseif ($nlmHdr.Text -match "(?im)^location:.*(notebook\.google\.com|accounts\.google\.com)" -or $nlmHdr.Text -match "(?m)^HTTP/\S+\s+(200|301|302)") {
      $nlmStatus = "ok"
    }
  }

  # 4. YouTube Premium strict 3-tier
  Write-ProgressLine "IPv${Ver}: 探测 YouTube Premium 与 Google Play..."
  $ytRes = Invoke-CurlRaw @($sflag, "-L", "--max-time", "9", "-H", "Accept-Language: en-US,en;q=0.9", "-H", "Cookie: $SocsCookie", "https://www.youtube.com/premium")
  $ytStatus = "err"
  $ytGl = ""
  if ($ytRes.Code -eq 0 -and $ytRes.Text.Length -gt 0) {
    if ($ytRes.Text -match '"contentRegion":"([A-Z]{2})"') { $ytGl = $Matches[1] }
    elseif ($ytRes.Text -match '"INNERTUBE_CONTEXT_GL":"([A-Z]{2})"') { $ytGl = $Matches[1] }
    if ($ytRes.Text -match "www\.google\.cn") { $ytStatus = "cn" }
    elseif ($ytRes.Text -match "(?i)Premium is not available in your country") { $ytStatus = "noprem" }
    elseif ($ytRes.Text -match "(?i)ad-free") { $ytStatus = "ok" }
  }

  # 5. Google Play Store
  $playRes = Invoke-CurlRaw @($sflag, "-L", "--max-time", "9", "-H", "Accept-Language: en-US,en;q=0.9", "https://play.google.com/")
  $playCc = ""
  if ($playRes.Code -eq 0 -and $playRes.Text -match '<div class="yVZQTb">([^<(]+)') {
    $playCc = $Matches[1].Trim()
  }

  # 6. Google Search + Terms
  Write-ProgressLine "IPv${Ver}: 探测 Google Search 与 Terms 辖区..."
  $sdRes = Invoke-CurlRaw @($sflag, "--max-time", "7", "https://www.google.com/searchdomaincheck?format=domain")
  $sdom = ""
  if ($sdRes.Code -eq 0) {
    if ($sdRes.Text -match "(?i)hkredirect") { $sdom = "hkredirect" }
    else {
      $first = ($sdRes.Text -split "`r?`n")[0].Trim()
      if ($first -match "^\.google\.") { $sdom = $first }
    }
  }

  $srRes = Invoke-CurlRaw @(
    $sflag, "-L", "--max-time", "9",
    "-H", "Accept-Language: en-US,en;q=0.9",
    "-H", "Sec-Fetch-Dest: document",
    "-H", "Sec-Fetch-Mode: navigate",
    "-H", "Sec-Fetch-Site: none",
    "-w", "`n__CODE__%{http_code}__URL__%{url_effective}",
    "https://www.google.com/search?q=curl&ie=UTF-8"
  )
  $scap = "err"
  if ($srRes.Code -eq 0 -and $srRes.Text -match "__CODE__(\d+)__URL__(.*)$") {
    $srCode = $Matches[1]
    $srUrl = $Matches[2].Trim()
    if ($srCode -eq "429" -or $srRes.Text -match "(?i)unusual traffic from|is blocked|unaddressed abuse|/sorry/") {
      $scap = "captcha"
    } elseif ($srUrl -match "(?i)google\.com\.hk|google\.cn") {
      $scap = "hk"
    } elseif ($srCode -ne "000") {
      $scap = "ok"
    }
  }

  $trmRes = Invoke-CurlRaw @($sflag, "-L", "--max-time", "9", "https://policies.google.com/terms?hl=en")
  $trmCv = ""; $trmEnt = ""
  if ($trmRes.Code -eq 0) {
    if ($trmRes.Text -match "(?i)Country\s+version(?:\s*<[^>]+>)*\s*:\s*(?:<[^>]+>\s*)*([A-Za-z][A-Za-z\s,\.\(\)&'-]{1,42})") {
      $trmCv = $Matches[1].Trim()
    }
    if ($trmRes.Text -match "(Google Ireland Limited|Google LLC|Google Asia Pacific|Google Commerce Limited)") {
      $trmEnt = $Matches[1]
    }
  }

  $dnsMode = Test-DnsMode -Ver $Ver -IsTun $script:detectedTun -HasPx $hasExplicitProxy

  $obj = [ordered]@{}
  $mIp = Mask-IpAddress $rawIp
  $mGip = Mask-IpAddress $gipRaw
  if ($mIp) { $obj.ip = $mIp }
  if ($mGip) { $obj.gip = $mGip }
  if ($null -ne $asn) { $obj.asn = $asn }
  if ($org) { $obj.org = $org }
  if ($cc) { $obj.cc = $cc }
  if ($city) { $obj.city = $city }
  if ($kind) { $obj.kind = $kind }
  if ($null -ne $gasn) { $obj.gasn = $gasn }
  if ($gorg) { $obj.gorg = $gorg }
  if ($gkind) { $obj.gkind = $gkind }
  if ($gemCc) { $obj.gem = $gemCc }
  if ($nlmStatus) { $obj.nlm = $nlmStatus }
  if ($ytStatus) { $obj.yt = $ytStatus }
  if ($ytGl) { $obj.ytg = $ytGl }
  if ($cdn) { $obj.cdn = $cdn }
  if ($cdnu) { $obj.cdnu = $true }
  if ($playCc) { $obj.play = $playCc }
  if ($sdom) { $obj.sdom = $sdom }
  if ($scap) { $obj.scap = $scap }
  if ($trmCv) { $obj.trm = $trmCv }
  if ($trmEnt) { $obj.ent = $trmEnt }
  if ($dnsMode) { $obj.dns = $dnsMode }
  return $obj
}

$v4Data = if ($runV4) { Invoke-StackProbe -Ver 4 } else { $null }
$v6Data = if ($runV6) { Invoke-StackProbe -Ver 6 } else { $null }
if (-not $Json) { Write-Host ("`r{0}`r" -f (" " * 70)) -NoNewline }

if ($null -eq $v4Data -and $null -eq $v6Data) {
  Write-Host "ERROR: IPv4 与 IPv6 均未能获取出口信息，请检查网络或代理参数 (-Proxy)。" -ForegroundColor Red
  return
}

$runMode = if ($Vps) { "vps" } elseif ($ProxyMode) { "proxy" } elseif ($detectedTun -or $hasExplicitProxy -or $cnDirect) { "proxy" } else { "vps" }
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
if ($null -ne $v4Data) { $report.v4 = $v4Data }
if ($null -ne $v6Data) { $report.v6 = $v6Data }

$jsonText = $report | ConvertTo-Json -Depth 6 -Compress

if ($Json) {
  Write-Output $jsonText
  return
}

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
$p = if ($null -ne $v4Data) { $v4Data } else { $v6Data }
$splitHit = ($p.ip -and $p.gip -and $p.ip -ne $p.gip)
$effKind = if ($splitHit -and $p.gkind) { $p.gkind } else { $p.kind }

$vTag = "[CLEAN]"
$vColor = "Green"
$vText = if ($effKind -eq "hosting") { "云机房出口全绿可用 · 实测无送中无验证码 (反焦虑认证)" } else { "Google 全家桶全绿可用" }

if ($null -ne $v4Data -and $null -ne $v6Data -and ($d4 -ne $d6 -or $v4Data.gem -ne $v6Data.gem)) {
  $vTag = "[STACK_SPLIT]"; $vColor = "Yellow"
  $vText = "双栈不对称: IPv4($($v4Data.gem)) vs IPv6($($v6Data.gem))，建议关闭冲突栈"
} elseif ($d4 -or $d6) {
  $vTag = "[CN_DRIFT]"; $vColor = "Red"
  $vText = if ($p.cc -and -not (Test-RestrictedCountry $p.cc)) {
    "实锤 Google 私有库送中 (公开库 $($p.cc) / Apple $(if($appleCc){$appleCc}else{'?'})，但 Google 判受限)"
  } else { "Google 生态判定为受限地区 / 送中" }
} elseif (($v4Data -and $v4Data.scap -eq "captcha") -or ($v6Data -and $v6Data.scap -eq "captcha")) {
  $vTag = "[PARTIAL]"; $vColor = "Yellow"
  $vText = "AI 核心可用，但 Google Search 触发 /sorry/ 人机验证"
} elseif ($splitHit) {
  $vTag = "[SPLIT_ROUTE]"; $vColor = "Cyan"
  $vText = if ($p.gorg) {
    "跨组分流生效 · Google 经 $($p.gorg) ($(Format-KindCn $p.gkind)) 干净可用"
  } else {
    "跨组分流生效 · 通用海外 ($($p.ip)) 与 Google ($($p.gip)) 已拆分且可用"
  }
}

function Format-Cell {
  param([string]$Kind, $S)
  if ($null -eq $S) { return @{ Text = "N/A"; Color = "DarkGray" } }
  switch ($Kind) {
    "gem" {
      if (-not $S.gem) { return @{ Text = "N/A"; Color = "DarkGray" } }
      if (Test-RestrictedCountry $S.gem) { return @{ Text = "BLOCKED [$($S.gem)]"; Color = "Red" } }
      return @{ Text = "OK [$($S.gem)]"; Color = "Green" }
    }
    "nlm" {
      if ($S.nlm -eq "ok") { return @{ Text = "OK (301)"; Color = "Green" } }
      if ($S.nlm -eq "unavail") { return @{ Text = "BLOCKED (302)"; Color = "Red" } }
      return @{ Text = "N/A"; Color = "DarkGray" }
    }
    "yt" {
      if ($S.yt -eq "ok") { return @{ Text = "OK [$($S.ytg)]"; Color = "Green" } }
      if ($S.yt -eq "cn") { return @{ Text = "CN_DRIFT"; Color = "Red" } }
      if ($S.yt -eq "noprem") { return @{ Text = "NO_PREM (GL=$($S.ytg))"; Color = "Red" } }
      return @{ Text = "N/A"; Color = "DarkGray" }
    }
    "cdn" {
      if (-not $S.cdn) { return @{ Text = "N/A"; Color = "DarkGray" } }
      $t = $S.cdn + $(if ($S.cdnu) { " [u]" } else { "" })
      if ($S.ip -and $S.gip -and $S.ip -ne $S.gip) { return @{ Text = "$t (Split)"; Color = "Yellow" } }
      return @{ Text = $t; Color = "Cyan" }
    }
    "play" {
      if (-not $S.play) { return @{ Text = "N/A"; Color = "DarkGray" } }
      if (Test-RestrictedCountry $S.play) { return @{ Text = "$($S.play) [CN]"; Color = "Red" } }
      return @{ Text = "$($S.play)"; Color = "Green" }
    }
    "search" {
      if ($S.scap -eq "captcha") { return @{ Text = "CAPTCHA (/sorry)"; Color = "Yellow" } }
      if ($S.sdom -eq "hkredirect" -or $S.scap -eq "hk") { return @{ Text = "HK_REDIRECT (.hk)"; Color = "Red" } }
      if ($S.sdom -or $S.scap -eq "ok") { return @{ Text = "$(if($S.sdom){$S.sdom}else{'OK'}) (Clean)"; Color = "Green" } }
      return @{ Text = "N/A"; Color = "DarkGray" }
    }
    "terms" {
      if (-not $S.trm) { return @{ Text = "N/A"; Color = "DarkGray" } }
      if (Test-RestrictedCountry $S.trm) { return @{ Text = "$($S.trm) [CN]"; Color = "Red" } }
      if ($S.ent -eq "Google Ireland Limited") { return @{ Text = "$($S.trm) (EEA)"; Color = "Yellow" } }
      return @{ Text = "$($S.trm)"; Color = "Green" }
    }
  }
}

$line = "=" * 72
$dash = "-" * 72
$modeLabel = if ($runMode -eq "proxy") { if ($detectedTun) { "代理/分流·TUN" } else { "代理/分流出站" } } elseif ($splitHit) { "直连主机·出站分流" } else { "直连出站" }
$utcTime = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm UTC")

Write-Host $line -ForegroundColor DarkGray
Write-Host ("G-ROUTE // Google 生态送中与分流体检卡   [{0}] {1}" -f $modeLabel, $utcTime) -ForegroundColor Cyan
Write-Host $line -ForegroundColor DarkGray
Write-Host "结论: " -NoNewline
Write-Host "$vTag " -NoNewline -ForegroundColor $vColor
Write-Host $vText
Write-Host ("通用出口: {0} | AS{1} {2} [{3}] ({4})" -f $(if($p.ip){$p.ip}else{"N/A"}), $(if($p.asn){$p.asn}else{"?"}), $(if($p.org){$p.org}else{"Unknown"}), (Format-KindCn $p.kind), $(if($p.dns){$p.dns}else{"--"}))
if ($splitHit) {
  Write-Host ("Google出口: {0} | AS{1} {2} [{3}]" -f $p.gip, $(if($p.gasn){$p.gasn}else{"?"}), $(if($p.gorg){$p.gorg}else{"独立分流出口"}), (Format-KindCn $p.gkind)) -ForegroundColor Yellow
}
Write-Host ("三方对照: 公开库={0}  |  Apple={1}  |  Google 实测={2}" -f $(if($p.cc){$p.cc}else{"?"}), $(if($appleCc){$appleCc}else{"?"}), $(if($p.gem){$p.gem}else{"?"}))
Write-Host $dash -ForegroundColor DarkGray

$rows = @(
  @{ Key = "gem";    Name = "Gemini (Boq)";       Note = "gemini.google.com/app" },
  @{ Key = "nlm";    Name = "NotebookLM (1-RTT)"; Note = "301=支持 / 302=封锁" },
  @{ Key = "yt";     Name = "YouTube Premium";    Note = "含半隐身送中判据" },
  @{ Key = "cdn";    Name = "YouTube GGC CDN";    Note = "Google 实见 $(if($p.gip){$p.gip}else{'?'})" },
  @{ Key = "play";   Name = "Google Play";        Note = "play.google.com" },
  @{ Key = "search"; Name = "Google Search";      Note = "域检查 + /sorry 实测" },
  @{ Key = "terms";  Name = "Google Terms";       Note = "$(if($p.ent){$p.ent}else{'?'})" }
)

if ($null -ne $v4Data -and $null -ne $v6Data) {
  Write-Host ("服务维度             {0,-24} {1,-24}" -f "IPv4 ($($v4Data.ip))", "IPv6 ($($v6Data.ip))") -ForegroundColor White
  Write-Host $dash -ForegroundColor DarkGray
  foreach ($r in $rows) {
    $c4 = Format-Cell -Kind $r.Key -S $v4Data
    $c6 = Format-Cell -Kind $r.Key -S $v6Data
    Write-Host ("{0,-20} " -f $r.Name) -NoNewline
    Write-Host ("{0,-24} " -f $c4.Text) -NoNewline -ForegroundColor $c4.Color
    Write-Host ("{0,-24}" -f $c6.Text) -ForegroundColor $c6.Color
  }
} else {
  $stLabel = if ($null -ne $v4Data) { "IPv4 检测结果" } else { "IPv6 检测结果" }
  Write-Host ("服务维度             {0}              补充说明" -f $stLabel) -ForegroundColor White
  Write-Host $dash -ForegroundColor DarkGray
  foreach ($r in $rows) {
    $c = Format-Cell -Kind $r.Key -S $p
    Write-Host ("{0,-20} " -f $r.Name) -NoNewline
    Write-Host ("{0,-26} " -f $c.Text) -NoNewline -ForegroundColor $c.Color
    Write-Host $r.Note -ForegroundColor DarkGray
  }
}

# Optional Opt-In Local Proxy Controller API (strictly read-only, strictly local display, NEVER in #r=)
# Supports HTTP (http://127.0.0.1:9090) AND Windows Named Pipe (\\.\pipe\verge-mihomo / \\.\pipe\mihomo-party)
function Invoke-ControllerConnections {
  param([string]$Endpoint, [string]$ApiSecret)
  if ($Endpoint -match "^\\\\\.\\pipe\\(.+)$" -or $Endpoint -match "^pipe:(.+)$") {
    $pipeName = $Matches[1]
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
    try {
      $pipe.Connect(1500)
      $authHdr = if ($ApiSecret) { "Authorization: Bearer $ApiSecret`r`n" } else { "" }
      $reqText = "GET /connections HTTP/1.1`r`nHost: localhost`r`n${authHdr}Connection: close`r`n`r`n"
      $reqBytes = [System.Text.Encoding]::ASCII.GetBytes($reqText)
      $pipe.Write($reqBytes, 0, $reqBytes.Length)
      $pipe.Flush()
      $ms = New-Object System.IO.MemoryStream
      $buf = New-Object byte[] 8192
      while (($n = $pipe.Read($buf, 0, $buf.Length)) -gt 0) {
        $ms.Write($buf, 0, $n)
      }
      $all = $ms.ToArray()
      $ms.Dispose()
      $sep = -1
      for ($i = 0; $i -le $all.Length - 4; $i++) {
        if ($all[$i] -eq 13 -and $all[$i + 1] -eq 10 -and $all[$i + 2] -eq 13 -and $all[$i + 3] -eq 10) {
          $sep = $i; break
        }
      }
      if ($sep -lt 0) { return @{ Code = "000"; Body = "empty response" } }
      $hdr = [System.Text.Encoding]::ASCII.GetString($all, 0, $sep)
      $code = if ($hdr -match "HTTP/\S+\s+(\d{3})") { $Matches[1] } else { "000" }
      $bodyStart = $sep + 4
      if ($hdr -match "(?im)^Transfer-Encoding:\s*chunked") {
        # De-chunk strictly at UTF-8 byte offsets (Mihomo node names often contain CJK/emoji)
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

  $ctrlBase = $Endpoint.TrimEnd("/")
  $ctrlArgs = @("-sS", "--noproxy", "*", "--max-time", "3", "-w", "`n__HTTP__%{http_code}")
  if ($ApiSecret) { $ctrlArgs += @("-H", "Authorization: Bearer $ApiSecret") }
  $ctrlArgs += "$ctrlBase/connections"
  $ctrlOut = (& $curlBin @ctrlArgs 2>$null) -join "`n"
  $ctrlCode = "000"
  $ctrlBody = $ctrlOut
  if ($ctrlOut -match "(?s)^(.*)\r?\n__HTTP__(\d{3})\s*$") {
    $ctrlBody = $Matches[1]
    $ctrlCode = $Matches[2]
  }
  return @{ Code = $ctrlCode; Body = $ctrlBody }
}

if ($Controller) {
  Write-Host $dash -ForegroundColor DarkGray
  Write-Host "[本地只读控制 API · 仅本屏展示，绝不写入 #r= 分享链]" -ForegroundColor Cyan
  $targets = @(
    "v4.ident.me",
    "www.google.com",
    "gemini.google.com",
    "aistudio.google.com",
    "notebooklm.google.com",
    "www.youtube.com",
    "redirector.googlevideo.com",
    "play.google.com"
  )
  # Explicit TLS 1.2 (3072) so Windows PowerShell 5.1 (.NET 4.x) never falls back to TLS 1.0
  $tls12 = [System.Security.Authentication.SslProtocols]3072
  $useHttpConnect = ($hasExplicitProxy -and -not $detectedTun -and $effectiveProxy -match "^https?://([^:/\s]+):(\d+)")
  $pxHost = if ($useHttpConnect) { $Matches[1] } else { "" }
  $pxPort = if ($useHttpConnect) { [int]$Matches[2] } else { 0 }

  $pending = @()
  $sockets = @()
  try {
    foreach ($hostName in $targets) {
      try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar = if ($useHttpConnect) {
          $tcp.BeginConnect($pxHost, $pxPort, $null, $null)
        } else {
          $tcp.BeginConnect($hostName, 443, $null, $null)
        }
        $pending += @{ Host = $hostName; Tcp = $tcp; Ar = $ar }
      } catch {}
    }

    foreach ($pConn in $pending) {
      try {
        if ($pConn.Ar.AsyncWaitHandle.WaitOne(1800, $false) -and $pConn.Tcp.Connected) {
          $pConn.Tcp.EndConnect($pConn.Ar)
          $netStream = $pConn.Tcp.GetStream()
          $netStream.ReadTimeout = 1800
          $netStream.WriteTimeout = 1800
          if ($useHttpConnect) {
            $connReq = [System.Text.Encoding]::ASCII.GetBytes("CONNECT $($pConn.Host):443 HTTP/1.1`r`nHost: $($pConn.Host):443`r`n`r`n")
            $netStream.Write($connReq, 0, $connReq.Length)
            $netStream.Flush()
            $respBuf = New-Object byte[] 1024
            $readN = $netStream.Read($respBuf, 0, $respBuf.Length)
            $respStr = [System.Text.Encoding]::ASCII.GetString($respBuf, 0, $readN)
            if ($respStr -notmatch "HTTP/\S+\s+200") {
              $pConn.Tcp.Close()
              continue
            }
          }
          $ssl = New-Object System.Net.Security.SslStream($netStream, $false, { $true })
          $ssl.ReadTimeout = 1800
          $ssl.WriteTimeout = 1800
          $ssl.AuthenticateAsClient($pConn.Host, $null, $tls12, $false)
          $sockets += @{ Tcp = $pConn.Tcp; Ssl = $ssl }
        } else {
          $pConn.Tcp.Close()
        }
      } catch {
        try { $pConn.Tcp.Close() } catch {}
      }
    }

    Start-Sleep -Milliseconds 250
    $ctrlRes = Invoke-ControllerConnections -Endpoint $Controller -ApiSecret $Secret
    $ctrlCode = $ctrlRes.Code
    $ctrlBody = $ctrlRes.Body

    if ($ctrlCode -eq "401" -or $ctrlCode -eq "403") {
      Write-Host "[INFO] 控制端 $Controller 已连通，但返回 HTTP $ctrlCode（需要密钥）。请设置 `$env:G_ROUTE_SECRET='你的密钥' 后重试。" -ForegroundColor Yellow
    } elseif ($ctrlCode -ne "200") {
      Write-Host "[INFO] 无法连接 $Controller（HTTP=$ctrlCode）：Clash Verge Rev 可传 \\.\pipe\verge-mihomo，Mihomo Party 可传 \\.\pipe\mihomo-party，或在客户端开启 TCP 外部控制端口。" -ForegroundColor Yellow
    } else {
      $ctrlResp = $ctrlBody | ConvertFrom-Json
      $conns = @($ctrlResp.connections)
      Write-Host ("{0,-28} {1,-30} {2}" -f "探测域名", "命中规则", "策略链 (策略组 -> 落地节点)") -ForegroundColor White
      foreach ($hostName in $targets) {
        $hit = $conns | Where-Object { $_.metadata.host -eq $hostName -or $_.metadata.sniffHost -eq $hostName } | Select-Object -Last 1
        if ($hit) {
          $rLbl = if ($hit.rulePayload) { "$($hit.rule)($($hit.rulePayload))" } else { "$($hit.rule)" }
          if ($rLbl.Length -gt 28) { $rLbl = $rLbl.Substring(0, 27) + "~" }
          $chainArr = @($hit.chains)
          [Array]::Reverse($chainArr)
          $chainStr = $chainArr -join " -> "
          Write-Host ("{0,-28} {1,-30} {2}" -f $hostName, $rLbl, $chainStr) -ForegroundColor Green
        } else {
          Write-Host ("{0,-28} {1,-30} {2}" -f $hostName, "(未在活跃连接捕获)", "--") -ForegroundColor DarkGray
        }
      }
    }
  } catch {
    Write-Host "[INFO] 解析 $Controller/connections 失败：$($_.Exception.Message)，已保留纯黑盒体检结果。" -ForegroundColor Yellow
  } finally {
    foreach ($s in $sockets) {
      try { $s.Ssl.Dispose() } catch {}
      try { $s.Tcp.Close() } catch {}
    }
  }
}

Write-Host $line -ForegroundColor DarkGray

if (-not $NoLink) {
  $payload = ConvertTo-GzipBase64Url -Text $jsonText
  if ($G_ROUTE_ORIGIN -match "^https?://") {
    Write-Host "Web 体检卡 & PNG 导出:" -ForegroundColor Cyan
    Write-Host "$G_ROUTE_ORIGIN/#r=$payload"
  } else {
    Write-Host "离线报告码 (粘贴到 G-ROUTE 网页渲染体检卡 / 导出 PNG):" -ForegroundColor Cyan
    Write-Host "G1:$payload"
  }
}
Write-Host "注: 100% 本地探测并离线编码，IP 已默认脱敏(-Full 显示完整)，未向任何服务器上传数据。" -ForegroundColor DarkGray
