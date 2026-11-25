<script lang="ts">
  import { encodeReportPayload, type CliReportV1 } from '../../shared/report-codec';
  import {
    buildReportMarkdown,
    splitExitTag,
    type CellTone,
    type ExitSlotColor,
    type ReportDiagnosis,
  } from '../../shared/report-diagnosis';
  import { renderReportCardPngBlob, resolveEffectiveDarkTheme } from '../lib/card-export';
  import { copyText } from '../lib/clipboard';

  interface Props {
    readonly report: CliReportV1;
    readonly diag: ReportDiagnosis;
    readonly origin: string;
    readonly isSample: boolean;
    readonly canDiff: boolean;
    readonly onOpenDiff: () => void;
    readonly onBackHome: () => void;
  }

  const { report, diag, origin, isSample, canDiff, onOpenDiff, onBackHome }: Props = $props();

  let exportBusy = $state(false);
  let copyImgBusy = $state(false);
  let feedback = $state<string | null>(null);

  const dualStack = $derived(Boolean(report.v4 && report.v6));
  const primary = $derived(report.v4 ?? report.v6);
  const formattedTime = $derived(
    new Date(report.t * 1000).toISOString().replace('T', ' ').slice(0, 16) + ' UTC',
  );

  function flash(msg: string): void {
    feedback = msg;
    setTimeout(() => {
      if (feedback === msg) feedback = null;
    }, 2200);
  }

  function toneClass(tone: CellTone): string {
    if (tone === 'ok') return 'tag tag-ok';
    if (tone === 'diff') return 'tag tag-diff';
    if (tone === 'leak') return 'tag tag-leak';
    return 'tag tag-wait';
  }

  function exitClass(color: ExitSlotColor): string {
    if (color === 'cn') return 'exit-pill exit-cn';
    if (color === 'a') return 'exit-pill exit-a';
    if (color === 'b') return 'exit-pill exit-b';
    if (color === 'c') return 'exit-pill exit-c';
    if (color === 'd') return 'exit-pill exit-d';
    return 'exit-pill exit-unk';
  }

  function safetyPrefix(tone: CellTone): string {
    if (tone === 'ok') return '✓ ';
    if (tone === 'leak') return '✕ ';
    if (tone === 'diff') return '! ';
    return '';
  }

  function tierTagClass(): string {
    if (diag.tier === 'drift') return 'tag tag-leak';
    if (diag.tier === 'partial') return 'tag tag-diff';
    return 'tag tag-ok';
  }

  async function handleExportPng(): Promise<void> {
    if (exportBusy) return;
    exportBusy = true;
    try {
      const blob = await renderReportCardPngBlob(report, diag, resolveEffectiveDarkTheme());
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      const safeIp = (primary?.ip ?? 'node').replace(/[^a-zA-Z0-9.-]/g, '_');
      a.href = url;
      a.download = `g-route-${diag.tierCode.toLowerCase()}-${safeIp}.png`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      flash('已导出 2x 高清 PNG 体检卡');
    } catch {
      flash('PNG 导出失败');
    } finally {
      exportBusy = false;
    }
  }

  async function handleCopyPng(): Promise<void> {
    if (copyImgBusy || typeof ClipboardItem === 'undefined' || !navigator.clipboard?.write) {
      await handleExportPng();
      return;
    }
    copyImgBusy = true;
    try {
      const blob = await renderReportCardPngBlob(report, diag, resolveEffectiveDarkTheme());
      await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
      flash('已复制高清 PNG 到剪贴板');
    } catch {
      await handleExportPng();
    } finally {
      copyImgBusy = false;
    }
  }

  async function handleCopyShareLink(): Promise<void> {
    const payload = await encodeReportPayload(report);
    const ok = await copyText(`${origin}/#r=${payload}`);
    flash(ok ? '已复制离线 #r= 分享链接' : '复制失败');
  }

  async function handleCopyMarkdown(): Promise<void> {
    const md = buildReportMarkdown(report, diag);
    const ok = await copyText(md);
    flash(ok ? '已复制脱敏 Markdown 摘要' : '复制失败');
  }
</script>

<article class="card" aria-label="Google 生态体检卡">
  <header class="card-head">
    <div class="head-left">
      <span class="mono head-brand">G-ROUTE // GOOGLE 生态体检卡</span>
      {#if isSample}
        <span class="tag tag-diff">[示例样本]</span>
      {/if}
      <span class="mono head-meta">
        {diag.transportLabel}
        {#if report.os}
          · {report.os}
        {/if}
        · {formattedTime}
      </span>
    </div>

    <div class="head-actions">
      <button type="button" class="btn btn-xs" disabled={exportBusy} onclick={handleExportPng}>
        {exportBusy ? '[生成中...]' : '[导出 PNG]'}
      </button>
      <button type="button" class="btn btn-subtle btn-xs" disabled={copyImgBusy} onclick={handleCopyPng}>
        [复制图片]
      </button>
      <button type="button" class="btn btn-subtle btn-xs" onclick={handleCopyShareLink}>
        [复制 #r= 链接]
      </button>
      <button type="button" class="btn btn-subtle btn-xs" onclick={handleCopyMarkdown}>
        [复制 MD]
      </button>
      {#if canDiff}
        <button type="button" class="btn btn-subtle btn-xs" onclick={onOpenDiff}>
          [双卡 Diff]
        </button>
      {/if}
      <button type="button" class="btn btn-subtle btn-xs" onclick={onBackHome}>
        [返回启动台]
      </button>
    </div>
  </header>

  {#if feedback}
    <div class="toast mono">[OK] {feedback}</div>
  {/if}

  <div class="verdict-band">
    <div class="verdict-top">
      <span class={`${tierTagClass()} tier-pill`}>[{diag.tierCode}]</span>
      <h2 class="verdict-headline">{diag.headline}</h2>
    </div>
    <p class="verdict-summary">{diag.summary}</p>
    <div class="badge-row">
      {#each diag.badges as b (b.text)}
        <span class={toneClass(b.tone)}>{b.text}</span>
      {/each}
    </div>
  </div>

  <div class="geo-strip">
    <div class="geo-cell geo-wide">
      <div class="geo-k mono">
        {diag.googleEgress ? '双出口归属（通用出口 → Google 实见出口）' : '出口节点 / ASN 归属'}
      </div>
      <div class="geo-v mono">
        {diag.defaultEgress.ip}
        {#if diag.defaultEgress.asn}
          <span class="geo-asn">· AS{diag.defaultEgress.asn}</span>
        {/if}
        <span class="kind-pill">[{diag.defaultEgress.kindLabel}]</span>
      </div>
      <div class="geo-sub">{diag.defaultEgress.org}</div>
      {#if diag.googleEgress}
        <div class="geo-split-row mono">
          <span class="split-callout">Google 实见 → {diag.googleEgress.ip}</span>
          {#if diag.googleEgress.asn}
            <span class="geo-asn">· AS{diag.googleEgress.asn}</span>
          {/if}
          <span>{diag.googleEgress.org} [{diag.googleEgress.kindLabel}]</span>
        </div>
      {/if}
    </div>

    <div class="geo-cell">
      <div class="geo-k mono">公开库 GeoIP</div>
      <div class="geo-v mono">{diag.publicGeoLabel}</div>
      <div class="geo-sub">ident.me / 外部库</div>
    </div>

    <div class="geo-cell">
      <div class="geo-k mono">Apple 第三方对照</div>
      <div class="geo-v mono">{report.ap ?? '--'}</div>
      <div class="geo-sub">gspe1-ssl / pep/gcc</div>
    </div>

    <div class="geo-cell">
      <div class="geo-k mono">Google 实测归属</div>
      <div
        class={`geo-v mono ${diag.tier === 'drift' ? 'txt-leak' : diag.tier === 'partial' ? 'txt-diff' : 'txt-ok'}`}
      >
        {diag.googleGeoLabel}
      </div>
      <div class="geo-sub">{diag.googleOnlyDrift ? '仅 Google 私有库送中' : '6 路真值汇总'}</div>
    </div>
  </div>

  {#if diag.routeClusters.length > 0}
    <section class="radar-band" aria-label="6 桶分流拓扑雷达">
      <div class="radar-head mono">
        <span>[01] 6 桶分流拓扑雷达 · 自动出口聚类</span>
        <span>共检出 {diag.routeClusters.filter((c) => !c.isCnDirect).length} 路海外出口</span>
      </div>
      <div class="table-wrap">
        <table class="radar-table">
          <thead>
            <tr>
              <th style="width: 14%">出口槽</th>
              <th style="width: 34%">出口 IP / ASN 归属</th>
              <th style="width: 40%">命中业务桶</th>
              <th style="width: 12%; text-align: right">平均 RTT</th>
            </tr>
          </thead>
          <tbody>
            {#each diag.routeClusters as cl (cl.slot + cl.ip)}
              <tr>
                <td><span class={`mono ${exitClass(cl.slotColor)}`}>{cl.slot}</span></td>
                <td>
                  <div class="mono radar-ip">
                    {cl.ip}
                    {#if cl.asn}
                      <span class="geo-asn">· AS{cl.asn}</span>
                    {/if}
                  </div>
                  <div class="radar-org">{cl.org} [{cl.kindLabel}]</div>
                </td>
                <td class="radar-buckets">{cl.buckets.join(' / ')}</td>
                <td class="mono radar-ms">{cl.avgMs !== null ? `${cl.avgMs} ms` : '--'}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
      {#if diag.routeAlarms.length > 0}
        <div class="alarm-list">
          {#each diag.routeAlarms as al (al.id)}
            <div class="alarm-item">
              <span class={toneClass(al.tone)}>
                {al.tone === 'leak' ? '[告警]' : al.tone === 'diff' ? '[提示]' : '[分流]'}
              </span>
              <strong>{al.title}</strong>
              <span class="alarm-detail">{al.detail}</span>
            </div>
          {/each}
        </div>
      {/if}
    </section>
  {/if}

  <div class="table-wrap">
    <table class="svc-table">
      <thead>
        <tr>
          <th style="width: 28%">Google 服务维度</th>
          {#if dualStack}
            <th style="width: 36%">IPv4 ({report.v4?.ip ?? ''})</th>
            <th style="width: 36%">IPv6 ({report.v6?.ip ?? ''})</th>
          {:else}
            <th style="width: 28%">
              实测结论 ({report.v4 ? 'IPv4' : 'IPv6'})
            </th>
            <th style="width: 44%">实测出口与真值细节</th>
          {/if}
        </tr>
      </thead>
      <tbody>
        {#each diag.rows as row (row.id)}
          <tr>
            <td>
              <div class="svc-name">{row.label}</div>
              <div class="svc-hint mono">{row.probeHint}</div>
            </td>

            {#if dualStack}
              <td>
                {#if row.v4}
                  <div class="cell-stack">
                    <span class={toneClass(row.v4.tone)}>{safetyPrefix(row.v4.tone)}{row.v4.badge}</span>
                    <span class="cell-detail">
                      {row.v4.detail}{#if row.v4.ms !== undefined} · {row.v4.ms}ms{/if}
                    </span>
                  </div>
                {:else}
                  <span class="mono muted">--</span>
                {/if}
              </td>
              <td>
                {#if row.v6}
                  <div class="cell-stack">
                    <span class={toneClass(row.v6.tone)}>{safetyPrefix(row.v6.tone)}{row.v6.badge}</span>
                    <span class="cell-detail">
                      {row.v6.detail}{#if row.v6.ms !== undefined} · {row.v6.ms}ms{/if}
                    </span>
                  </div>
                {:else}
                  <span class="mono muted">--</span>
                {/if}
              </td>
            {:else}
              {@const single = row.v4 ?? row.v6}
              {@const exTag = splitExitTag(single?.exitSlot)}
              <td>
                {#if single}
                  <span class={toneClass(single.tone)}>{safetyPrefix(single.tone)}{single.badge}</span>
                {:else}
                  <span class="mono muted">--</span>
                {/if}
              </td>
              <td class="cell-detail-single">
                {#if exTag}
                  <span class={`mono ${exitClass(exTag.color)}`}>{exTag.slot}</span>
                  {#if exTag.rest}
                    <span class="mono exit-rest">{exTag.rest}</span>
                  {/if}
                {/if}
                <span class="detail-sub">{single?.detail ?? '--'}</span>
                {#if single?.ms !== undefined}
                  <span class="mono rtt-chip">{single.ms} ms</span>
                {/if}
              </td>
            {/if}
          </tr>
        {/each}
      </tbody>
    </table>
  </div>

  <div class="rx-band">
    <div class="rx-head mono">PRESCRIPTION // 针对性结论与建议</div>
    {#each diag.prescriptions as item (item.id)}
      <div class="rx-row">
        <div class="rx-title-line">
          <span class={toneClass(item.tone)}>
            {item.tone === 'leak' ? '[需处理]' : item.tone === 'diff' ? '[留意]' : '[健康]'}
          </span>
          <strong>{item.title}</strong>
        </div>
        <div class="rx-body">
          {item.body}
          {#if item.actionUrl && item.actionLabel}
            <a href={item.actionUrl} target="_blank" rel="noopener noreferrer" class="rx-link mono">
              [{item.actionLabel} ↗]
            </a>
          {/if}
        </div>
      </div>
    {/each}
  </div>
</article>

<style>
  .card {
    border: 2px solid var(--rule-strong);
    background: var(--bg);
  }

  .card-head {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.6rem;
    padding: 0.6rem 0.9rem;
    background: var(--bg-subtle);
    border-bottom: 1px solid var(--rule-strong);
  }

  .head-left {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.55rem;
  }

  .head-brand {
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.04em;
  }

  .head-meta {
    font-size: 11px;
    color: var(--fg-muted);
  }

  .head-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.3rem;
  }

  .btn-xs {
    padding: 0.25rem 0.52rem;
    font-size: 11px;
  }

  .toast {
    padding: 0.35rem 0.9rem;
    background: var(--ok-bg);
    color: var(--ok);
    border-bottom: 1px solid var(--rule);
    font-size: 11.5px;
    font-weight: 600;
  }

  .verdict-band {
    padding: 1rem 0.95rem 0.9rem;
    border-bottom: 1px solid var(--rule);
    display: flex;
    flex-direction: column;
    gap: 0.45rem;
  }

  .verdict-top {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.6rem;
  }

  .tier-pill {
    font-size: 12px;
    padding: 0.14rem 0.48rem;
  }

  .verdict-headline {
    margin: 0;
    font-size: clamp(1rem, 1.8vw, 1.25rem);
    font-weight: 600;
    line-height: 1.3;
  }

  .verdict-summary {
    margin: 0;
    font-size: 13px;
    color: var(--fg-muted);
    line-height: 1.5;
  }

  .badge-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.35rem;
    margin-top: 0.15rem;
  }

  .geo-strip {
    display: grid;
    grid-template-columns: 2fr 1fr 1fr 1fr;
    border-bottom: 1px solid var(--rule-strong);
  }

  .geo-cell {
    padding: 0.65rem 0.9rem;
    border-right: 1px solid var(--rule);
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
    min-width: 0;
  }

  .geo-cell:last-child {
    border-right: none;
  }

  .geo-k {
    font-size: 10.5px;
    color: var(--fg-faint);
    font-weight: 600;
  }

  .geo-v {
    font-size: 14px;
    font-weight: 600;
    word-break: break-all;
  }

  .geo-asn {
    color: var(--fg-muted);
    font-weight: 500;
    font-size: 12.5px;
  }

  .geo-sub {
    font-size: 11.5px;
    color: var(--fg-muted);
  }

  .kind-pill {
    font-size: 11px;
    font-weight: 500;
    color: var(--fg-muted);
    margin-left: 0.3rem;
  }

  .geo-split-row {
    margin-top: 0.25rem;
    padding-top: 0.25rem;
    border-top: 1px dashed var(--rule);
    font-size: 11.5px;
    color: var(--fg);
    display: flex;
    flex-wrap: wrap;
    gap: 0.3rem;
  }

  .split-callout {
    color: var(--diff);
    font-weight: 600;
  }

  .txt-ok {
    color: var(--ok);
  }

  .txt-diff {
    color: var(--diff);
  }

  .txt-leak {
    color: var(--leak);
  }

  .table-wrap {
    overflow-x: auto;
  }

  .svc-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
  }

  .svc-table th {
    text-align: left;
    padding: 0.45rem 0.9rem;
    background: var(--bg-subtle);
    border-bottom: 1px solid var(--rule);
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 600;
    color: var(--fg-muted);
  }

  .svc-table td {
    padding: 0.58rem 0.9rem;
    border-bottom: 1px solid var(--rule);
    vertical-align: middle;
  }

  .svc-table tbody tr:last-child td {
    border-bottom: none;
  }

  .svc-name {
    font-weight: 600;
    font-size: 13px;
  }

  .svc-hint {
    font-size: 11px;
    color: var(--fg-faint);
  }

  .cell-stack {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 0.22rem;
  }

  .cell-detail {
    font-size: 11.5px;
    color: var(--fg-muted);
  }

  .cell-detail-single {
    font-size: 12.5px;
    color: var(--fg-muted);
  }

  .muted {
    color: var(--fg-faint);
  }

  .rtt-chip {
    margin-left: 0.45rem;
    font-size: 11px;
    color: var(--fg-faint);
  }

  .exit-pill {
    display: inline-block;
    padding: 0.06rem 0.42rem;
    font-size: 11px;
    font-weight: 600;
    border: 1px solid currentColor;
    white-space: nowrap;
  }

  .exit-cn { color: var(--exit-cn); background: var(--exit-cn-bg); }
  .exit-a  { color: var(--exit-a);  background: var(--exit-a-bg); }
  .exit-b  { color: var(--exit-b);  background: var(--exit-b-bg); }
  .exit-c  { color: var(--exit-c);  background: var(--exit-c-bg); }
  .exit-d  { color: var(--exit-d);  background: var(--exit-d-bg); }
  .exit-unk { color: var(--fg-muted); background: var(--bg-subtle); border-color: var(--rule); }

  .exit-rest {
    margin-left: 0.35rem;
    margin-right: 0.5rem;
    font-size: 11.5px;
    font-weight: 600;
    color: var(--fg);
  }

  .detail-sub {
    font-size: 11.5px;
    color: var(--fg-muted);
  }

  .radar-band {
    border-bottom: 1px solid var(--rule-strong);
    background: var(--bg);
  }

  .radar-head {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    gap: 0.5rem;
    padding: 0.42rem 0.9rem;
    background: var(--bg-subtle);
    border-bottom: 1px solid var(--rule);
    font-size: 11px;
    font-weight: 600;
    color: var(--fg-muted);
  }

  .radar-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12.5px;
  }

  .radar-table th {
    text-align: left;
    padding: 0.36rem 0.9rem;
    background: var(--bg-inset);
    border-bottom: 1px solid var(--rule);
    font-family: var(--font-mono);
    font-size: 10.5px;
    font-weight: 600;
    color: var(--fg-faint);
  }

  .radar-table td {
    padding: 0.5rem 0.9rem;
    border-bottom: 1px solid var(--rule);
    vertical-align: middle;
  }

  .radar-table tbody tr:last-child td {
    border-bottom: none;
  }

  .radar-ip {
    font-size: 12px;
    font-weight: 600;
  }

  .radar-org {
    font-size: 11px;
    color: var(--fg-muted);
  }

  .radar-buckets {
    font-size: 12px;
    color: var(--fg);
  }

  .radar-ms {
    text-align: right;
    font-size: 11.5px;
    color: var(--fg-muted);
    white-space: nowrap;
  }

  .alarm-list {
    border-top: 1px dashed var(--rule);
    padding: 0.45rem 0.9rem;
    display: flex;
    flex-direction: column;
    gap: 0.32rem;
    background: var(--bg-inset);
  }

  .alarm-item {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.4rem;
    font-size: 12px;
  }

  .alarm-detail {
    color: var(--fg-muted);
  }

  .rx-band {
    border-top: 1px solid var(--rule-strong);
    background: var(--bg-inset);
  }

  .rx-head {
    padding: 0.42rem 0.9rem;
    font-size: 11px;
    font-weight: 600;
    color: var(--fg-muted);
    border-bottom: 1px solid var(--rule);
  }

  .rx-row {
    padding: 0.65rem 0.9rem;
    border-bottom: 1px solid var(--rule);
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .rx-row:last-child {
    border-bottom: none;
  }

  .rx-title-line {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.45rem;
    font-size: 13px;
  }

  .rx-body {
    font-size: 12.5px;
    color: var(--fg-muted);
    line-height: 1.5;
  }

  .rx-link {
    margin-left: 0.45rem;
    font-size: 11.5px;
    font-weight: 600;
  }

  @media (max-width: 820px) {
    .geo-strip {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .geo-cell {
      border-bottom: 1px solid var(--rule);
    }

    .geo-cell:nth-child(2n) {
      border-right: none;
    }

    .geo-cell:nth-last-child(-n + 2) {
      border-bottom: none;
    }
  }

  @media (max-width: 560px) {
    .geo-strip {
      grid-template-columns: 1fr;
    }

    .geo-cell {
      border-right: none;
      border-bottom: 1px solid var(--rule);
    }

    .geo-cell:last-child {
      border-bottom: none;
    }
  }
</style>
