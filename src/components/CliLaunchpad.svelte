<script lang="ts">
  import { decodeReportInput, type CliReportV1 } from '../../shared/report-codec';
  import { SAMPLE_REPORTS, type SamplePreset } from '../../shared/sample-reports';
  import { copyText } from '../lib/clipboard';

  interface Props {
    readonly origin: string;
    readonly githubRepoUrl: string | null;
    readonly onImportReport: (
      report: CliReportV1,
      meta?: { readonly label?: string; readonly isSample?: boolean },
    ) => void;
  }

  const { origin, githubRepoUrl, onImportReport }: Props = $props();

  let osTab = $state<'unix' | 'win'>('unix');
  let cmdMode = $state<'fast' | 'audit' | 'controller' | 'dryrun'>('fast');
  let copiedCmd = $state(false);
  let pasteValue = $state('');
  let parseError = $state<string | null>(null);
  let decoding = $state(false);

  // Source code & SHA-256 audit drawer
  let trustPanel = $state<'none' | 'source' | 'contract'>('none');
  let sourceLoading = $state(false);
  let sourceText = $state<string | null>(null);
  let sourceSha256 = $state<string | null>(null);
  let sourceError = $state<string | null>(null);
  let loadedScriptPath = $state<string | null>(null);
  let copiedSha = $state(false);

  const scriptPath = $derived(osTab === 'unix' ? '/sh' : '/ps');

  const cliCommand = $derived.by(() => {
    if (osTab === 'unix') {
      if (cmdMode === 'audit') {
        return `curl -sL ${origin}/sh -o g-route.sh && less g-route.sh && bash g-route.sh --svg --no-link`;
      }
      if (cmdMode === 'controller') {
        return `bash <(curl -sL ${origin}/sh) --inspect`;
      }
      if (cmdMode === 'dryrun') {
        return `bash <(curl -sL ${origin}/sh) --dry-run`;
      }
      return `bash <(curl -sL ${origin}/sh)`;
    }

    if (cmdMode === 'audit') {
      return `iwr ${origin}/ps -OutFile g-route.ps1; notepad g-route.ps1; .\\g-route.ps1 -Svg -NoLink`;
    }
    if (cmdMode === 'controller') {
      return `$env:G_ROUTE_INSPECT='1'; irm ${origin}/ps | iex`;
    }
    if (cmdMode === 'dryrun') {
      return `iwr ${origin}/ps -OutFile g-route.ps1; .\\g-route.ps1 -DryRun`;
    }
    return `irm ${origin}/ps | iex`;
  });

  const modeHint = $derived.by(() => {
    if (cmdMode === 'audit') {
      return '纯离线无网页闭环：先落盘逐行审阅，跑完直接本地生成高清 SVG 体检卡（Windows 还可加 -Png 直出本地 PNG），不生成网页链接。';
    }
    if (cmdMode === 'controller') {
      return osTab === 'win'
        ? '白名单自动发现本机 Clash Verge Rev / Mihomo Party / sing-box 管道或端口（免背管道名，遇 401 现场提示密钥）；仅本屏只读审计 15 域规则一致性，绝不写入 #r= 或默认 SVG。'
        : '白名单自动发现 Unix Socket（Verge / Mihomo Party）或 127.0.0.1:9090/9097；仅本屏只读审计 15 域规则一致性，绝不写入 #r= 或默认 SVG。';
    }
    if (cmdMode === 'dryrun') {
      return '零发包安全审计：打印全部 6 桶分流雷达与 Google 6 路只读域名、权限边界后立即退出，不发出任何数据包。';
    }
    return osTab === 'unix'
      ? '无参数直跑会展示 1 屏交互入口（回车即跑纯黑盒，跑完可按 S 存本地 SVG / 按 R 补查代理分组）；脚本自动化可加 --quick / --svg / -j。'
      : '无参数直跑会展示 1 屏交互入口（回车即跑纯黑盒，跑完可按 S 存 SVG / P 存本地 PNG / R 补查代理分组）；直通参数可用 -Quick / -Inspect / -Svg / -Png。';
  });

  const sourceLineCount = $derived(sourceText ? sourceText.split('\n').length : 0);

  async function computeSha256Hex(text: string): Promise<string> {
    if (typeof crypto === 'undefined' || !crypto.subtle) {
      return '(当前非安全上下文，无法调用 WebCrypto)';
    }
    const bytes = new TextEncoder().encode(text);
    const hashBuf = await crypto.subtle.digest('SHA-256', bytes);
    return Array.from(new Uint8Array(hashBuf))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }

  async function fetchCurrentScriptSource(path: string): Promise<void> {
    sourceLoading = true;
    sourceError = null;
    try {
      const res = await fetch(path, { cache: 'no-store' });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const text = await res.text();
      if (text.trimStart().startsWith('<!doctype') || text.trimStart().startsWith('<html')) {
        throw new Error('当前预览服务未挂载 Worker 路由，请用 pnpm run preview (wrangler dev) 或部署后查看实时脚本');
      }
      sourceText = text;
      sourceSha256 = await computeSha256Hex(text);
      loadedScriptPath = path;
    } catch (err) {
      sourceText = null;
      sourceSha256 = null;
      sourceError = err instanceof Error ? err.message : '拉取脚本源码失败';
    } finally {
      sourceLoading = false;
    }
  }

  $effect(() => {
    if (trustPanel === 'source' && loadedScriptPath !== scriptPath && !sourceLoading) {
      void fetchCurrentScriptSource(scriptPath);
    }
  });

  function toggleTrustPanel(next: 'source' | 'contract'): void {
    trustPanel = trustPanel === next ? 'none' : next;
  }

  async function handleCopyCmd(): Promise<void> {
    const ok = await copyText(cliCommand);
    if (ok) {
      copiedCmd = true;
      setTimeout(() => {
        copiedCmd = false;
      }, 1600);
    }
  }

  async function handleCopySha(): Promise<void> {
    if (!sourceSha256) return;
    const ok = await copyText(sourceSha256);
    if (ok) {
      copiedSha = true;
      setTimeout(() => {
        copiedSha = false;
      }, 1600);
    }
  }

  async function handleDecode(rawText?: string): Promise<void> {
    const input = (rawText ?? pasteValue).trim();
    if (!input) {
      parseError = '请先粘贴 CLI 输出的 #r= 链接、G1 报告码或 -j 原始 JSON';
      return;
    }
    decoding = true;
    parseError = null;
    try {
      const res = await decodeReportInput(input);
      if (!res.ok) {
        parseError = res.error;
        return;
      }
      pasteValue = '';
      onImportReport(res.report);
    } finally {
      decoding = false;
    }
  }

  function handleSelectSample(preset: SamplePreset): void {
    parseError = null;
    onImportReport(preset.report, { label: preset.report.lbl ?? preset.shortName, isSample: true });
  }
</script>

<section class="launch-grid" aria-label="CLI 深度体检启动台">
  <div class="launch-main">
    <div class="panel-head">
      <div>
        <div class="mono kicker">STEP 01 // 真值 CLI 一键体检（绕过浏览器 CORS 限制）</div>
        <h2 class="panel-title">在 VPS 或本机终端运行，6 路实测 Google 真实归属与双出口分流</h2>
      </div>
      <div class="tabs" role="tablist">
        <button
          type="button"
          class={`btn btn-sm ${osTab === 'unix' ? 'btn-active' : 'btn-subtle'}`}
          onclick={() => (osTab = 'unix')}
        >
          Linux / macOS / VPS
        </button>
        <button
          type="button"
          class={`btn btn-sm ${osTab === 'win' ? 'btn-active' : 'btn-subtle'}`}
          onclick={() => (osTab = 'win')}
        >
          Windows PowerShell
        </button>
      </div>
    </div>

    <div class="mode-row">
      {#each [
        { id: 'fast', label: '交互全局入口' },
        { id: 'controller', label: '+ 自动透视代理分组' },
        { id: 'audit', label: '纯离线直出 SVG (免网页)' },
        { id: 'dryrun', label: '零发包审计 (--dry-run)' },
      ] as m (m.id)}
        <button
          type="button"
          class={`btn btn-xs ${cmdMode === m.id ? 'btn-active' : 'btn-subtle'}`}
          onclick={() => (cmdMode = m.id as 'fast' | 'audit' | 'controller' | 'dryrun')}
        >
          {m.label}
        </button>
      {/each}
    </div>

    <div class="cmd-strip">
      <code class="cmd-text mono">{cliCommand}</code>
      <button type="button" class="btn" onclick={handleCopyCmd}>
        {copiedCmd ? '[已复制]' : '[复制命令]'}
      </button>
    </div>

    <div class="flag-line mono">{modeHint}</div>

    <div class="trust-bar">
      <div class="trust-summary mono">
        <span class="tag tag-ok">[零越权契约]</span>
        <span>不提权 · 不读磁盘配置/订阅 · 不上传结果 · 全程明文可审</span>
      </div>
      <div class="trust-actions">
        <button
          type="button"
          class={`btn btn-xs ${trustPanel === 'source' ? 'btn-active' : 'btn-subtle'}`}
          onclick={() => toggleTrustPanel('source')}
        >
          {trustPanel === 'source' ? '[-] 收起源码' : '[审阅源码 + SHA-256]'}
        </button>
        <button
          type="button"
          class={`btn btn-xs ${trustPanel === 'contract' ? 'btn-active' : 'btn-subtle'}`}
          onclick={() => toggleTrustPanel('contract')}
        >
          {trustPanel === 'contract' ? '[-] 收起清单' : '[联网清单与边界]'}
        </button>
        {#if githubRepoUrl}
          <a href={githubRepoUrl} target="_blank" rel="noopener noreferrer" class="btn btn-xs btn-subtle link-btn">
            [GitHub 源码 ↗]
          </a>
        {/if}
      </div>
    </div>

    {#if trustPanel === 'source'}
      <div class="audit-drawer">
        <div class="audit-head mono">
          <span>当前文件: {scriptPath} ({sourceLineCount} 行)</span>
          {#if sourceSha256}
            <span class="sha-wrap">
              SHA-256: <code>{sourceSha256.slice(0, 16)}…{sourceSha256.slice(-8)}</code>
              <button type="button" class="btn btn-xs btn-subtle" onclick={handleCopySha}>
                {copiedSha ? '[已复制]' : '[复制完整哈希]'}
              </button>
            </span>
          {/if}
          <a href={scriptPath} target="_blank" rel="noopener noreferrer">[新标签打开原文件 ↗]</a>
        </div>
        {#if sourceLoading}
          <div class="audit-msg mono">正在读取 {scriptPath} 明文源码并计算 SHA-256...</div>
        {:else if sourceError}
          <div class="audit-err mono">[INFO] {sourceError}</div>
        {:else if sourceText}
          <pre class="source-pre mono">{sourceText}</pre>
        {/if}
      </div>
    {/if}

    {#if trustPanel === 'contract'}
      <div class="audit-drawer">
        <div class="contract-grid">
          <div>
            <div class="mono contract-h">4 个绝不（默认纯黑盒）</div>
            <ul class="contract-list">
              <li>绝不请求管理员 / UAC / <code>sudo</code> 提权。</li>
              <li>绝不读取磁盘配置（<code>%APPDATA%</code> 代理订阅、<code>~/.ssh</code>、浏览器 Cookie）。</li>
              <li>绝不向任何后端上传检测数据（<code>#r=</code> 100% 本地离线压缩编码，IP 默认脱敏）。</li>
              <li>绝不下载二进制或执行混淆密文；仅在用户显式传 <code>-Controller</code> 时只读查本机 <code>/connections</code> 且不入分享链。</li>
            </ul>
          </div>
          <div>
            <div class="mono contract-h">全部只读 HTTPS 请求目标</div>
            <ul class="contract-list mono">
              <li>v4/v6.ident.me (备选 ipify) · 通用海外出口 ASN</li>
              <li>myip.ipip.net · 国内直连参照与绕行检测</li>
              <li>redirector.googlevideo.com · GGC 边缘与 Google 实见 IP</li>
              <li>cloudflare.com / chatgpt.com / claude.ai (/cdn-cgi/trace) · 跨 AI 分流与 WARP</li>
              <li>ipwho.is · 仅对去重后的新增非 WARP 出口查一次 ASN</li>
              <li>gspe1-ssl.ls.apple.com/pep/gcc · Apple 第三方对照</li>
              <li>gemini / notebooklm / youtube / play / google / policies</li>
            </ul>
          </div>
        </div>
      </div>
    {/if}

    <div class="import-box">
      <div class="import-head">
        <span class="mono kicker">STEP 02 // 离线解码渲染体检卡（或直接打开 CLI 底部生成的 #r= 链接）</span>
      </div>
      <div class="import-row">
        <input
          type="text"
          class="import-input mono"
          placeholder="粘贴 https://.../#r=z:... 、G1:z:... 或 CLI -j 输出的 JSON"
          bind:value={pasteValue}
          onkeydown={(e) => {
            if (e.key === 'Enter') void handleDecode();
          }}
        />
        <button type="button" class="btn" disabled={decoding} onclick={() => void handleDecode()}>
          {decoding ? '[解码中...]' : '[渲染体检卡]'}
        </button>
      </div>
      {#if parseError}
        <div class="err-msg mono">[ERR] {parseError}</div>
      {/if}
    </div>
  </div>

  <aside class="sample-col" aria-label="实测样本预览">
    <div class="sample-head">
      <span class="mono kicker">PREVIEW // 真实脱敏样本</span>
      <div class="sample-sub">点击 1 秒预览体检卡与 PNG 导出效果</div>
    </div>

    <div class="sample-list">
      {#each SAMPLE_REPORTS as item (item.id)}
        <button
          type="button"
          class="sample-card"
          onclick={() => handleSelectSample(item)}
        >
          <div class="sample-top">
            <span class={`tag tag-${item.tone}`}>[{item.tag}]</span>
            <span class="mono sample-arrow">查看体检卡 →</span>
          </div>
          <div class="sample-name">{item.shortName}</div>
          <div class="sample-meta mono">
            {item.report.v4?.ip ?? '--'} · AS{item.report.v4?.asn ?? '?'}
            {#if item.report.v4?.gip && item.report.v4.gip !== item.report.v4.ip}
              → {item.report.v4.gip}
            {/if}
            {#if item.report.v6}
              · 双栈 v4+v6
            {/if}
          </div>
        </button>
      {/each}
    </div>
  </aside>
</section>

<style>
  .launch-grid {
    display: grid;
    grid-template-columns: minmax(0, 1.75fr) minmax(255px, 1fr);
    border: 2px solid var(--rule-strong);
    background: var(--bg);
  }

  .launch-main {
    padding: var(--space-4);
    border-right: 1px solid var(--rule-strong);
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    min-width: 0;
  }

  .panel-head {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: flex-start;
    gap: 0.6rem;
  }

  .kicker {
    font-size: 11px;
    font-weight: 600;
    color: var(--fg-muted);
    letter-spacing: 0.03em;
  }

  .panel-title {
    margin: 0.25rem 0 0;
    font-size: 16px;
    font-weight: 600;
    line-height: 1.35;
  }

  .tabs,
  .mode-row,
  .trust-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.3rem;
  }

  .btn-sm {
    padding: 0.28rem 0.55rem;
    font-size: 11.5px;
  }

  .btn-xs {
    padding: 0.22rem 0.48rem;
    font-size: 11px;
  }

  .link-btn {
    text-decoration: none;
  }

  .cmd-strip {
    display: flex;
    align-items: stretch;
    border: 1px solid var(--rule-strong);
    background: var(--bg-inset);
  }

  .cmd-text {
    flex: 1;
    padding: 0.68rem 0.85rem;
    font-size: 12.5px;
    font-weight: 600;
    overflow-x: auto;
    white-space: nowrap;
    color: var(--fg);
  }

  .cmd-strip .btn {
    border: none;
    border-left: 1px solid var(--rule-strong);
    padding: 0 0.9rem;
    flex-shrink: 0;
  }

  .flag-line {
    font-size: 11px;
    color: var(--fg-muted);
    line-height: 1.45;
  }

  .trust-bar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.45rem;
    padding: 0.5rem 0.65rem;
    background: var(--bg-subtle);
    border: 1px solid var(--rule);
  }

  .trust-summary {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.45rem;
    font-size: 11px;
    color: var(--fg-muted);
  }

  .audit-drawer {
    border: 1px solid var(--rule-strong);
    background: var(--bg-inset);
  }

  .audit-head {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.45rem;
    padding: 0.45rem 0.65rem;
    background: var(--bg-subtle);
    border-bottom: 1px solid var(--rule);
    font-size: 11px;
    color: var(--fg-muted);
  }

  .sha-wrap {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
  }

  .sha-wrap code {
    color: var(--fg);
    font-weight: 600;
  }

  .audit-msg,
  .audit-err {
    padding: 0.65rem;
    font-size: 11.5px;
    color: var(--fg-muted);
  }

  .audit-err {
    color: var(--diff);
  }

  .source-pre {
    margin: 0;
    padding: 0.65rem;
    max-height: 300px;
    overflow: auto;
    font-size: 11px;
    line-height: 1.45;
    white-space: pre;
    color: var(--fg);
  }

  .contract-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.85rem;
    padding: 0.7rem;
  }

  .contract-h {
    font-size: 11px;
    font-weight: 600;
    color: var(--fg);
    margin-bottom: 0.35rem;
  }

  .contract-list {
    margin: 0;
    padding-left: 1.1rem;
    font-size: 11.5px;
    color: var(--fg-muted);
    line-height: 1.55;
  }

  .contract-list code {
    font-family: var(--font-mono);
    font-size: 10.5px;
    background: var(--bg);
    border: 1px solid var(--rule);
    padding: 0 0.2rem;
  }

  .import-box {
    margin-top: 0.1rem;
    padding-top: 0.75rem;
    border-top: 1px dashed var(--rule);
    display: flex;
    flex-direction: column;
    gap: 0.45rem;
  }

  .import-row {
    display: flex;
    gap: 0.4rem;
  }

  .import-input {
    flex: 1;
    min-width: 0;
    padding: 0.45rem 0.65rem;
    border: 1px solid var(--rule-strong);
    background: var(--bg);
    font-size: 12px;
  }

  .err-msg {
    font-size: 11.5px;
    color: var(--leak);
  }

  .sample-col {
    background: var(--bg-subtle);
    display: flex;
    flex-direction: column;
  }

  .sample-head {
    padding: var(--space-3) var(--space-4);
    border-bottom: 1px solid var(--rule);
  }

  .sample-sub {
    font-size: 12px;
    color: var(--fg-muted);
    margin-top: 0.15rem;
  }

  .sample-list {
    display: flex;
    flex-direction: column;
    flex: 1;
  }

  .sample-card {
    text-align: left;
    padding: 0.85rem var(--space-4);
    border: none;
    border-bottom: 1px solid var(--rule);
    background: transparent;
    cursor: pointer;
    display: flex;
    flex-direction: column;
    gap: 0.3rem;
  }

  .sample-card:last-child {
    border-bottom: none;
  }

  .sample-card:hover {
    background: var(--bg);
  }

  .sample-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
  }

  .sample-arrow {
    font-size: 11px;
    color: var(--fg-muted);
  }

  .sample-card:hover .sample-arrow {
    color: var(--fg);
  }

  .sample-name {
    font-size: 13.5px;
    font-weight: 600;
    color: var(--fg);
  }

  .sample-meta {
    font-size: 11px;
    color: var(--fg-muted);
  }

  @media (max-width: 860px) {
    .launch-grid {
      grid-template-columns: 1fr;
    }

    .launch-main {
      border-right: none;
      border-bottom: 1px solid var(--rule-strong);
    }

    .contract-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 560px) {
    .import-row {
      flex-direction: column;
    }
  }
</style>
