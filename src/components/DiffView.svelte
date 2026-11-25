<script lang="ts">
  import { buildDiffRows, type CellTone } from '../../shared/report-diagnosis';
  import type { StoredReportEntry } from '../lib/session-store';

  interface Props {
    readonly entries: readonly StoredReportEntry[];
    readonly initialLeftId: string;
    readonly onClose: () => void;
  }

  const { entries, initialLeftId, onClose }: Props = $props();

  let leftId = $state('');
  let rightId = $state('');

  $effect(() => {
    if (!leftId || !entries.some((e) => e.id === leftId)) {
      leftId = initialLeftId || entries[0]?.id || '';
    }
    if (!rightId || !entries.some((e) => e.id === rightId) || rightId === leftId) {
      const alt = entries.find((e) => e.id !== leftId);
      rightId = alt?.id ?? entries[0]?.id ?? '';
    }
  });

  const leftEntry = $derived(entries.find((e) => e.id === leftId) ?? entries[0] ?? null);
  const rightEntry = $derived(entries.find((e) => e.id === rightId) ?? entries[1] ?? entries[0] ?? null);

  const diffRows = $derived(
    leftEntry && rightEntry ? buildDiffRows(leftEntry.report, rightEntry.report) : [],
  );

  const diffCount = $derived(diffRows.filter((r) => r.changed).length);

  function toneClass(tone: CellTone): string {
    if (tone === 'ok') return 'txt-ok';
    if (tone === 'diff') return 'txt-diff';
    if (tone === 'leak') return 'txt-leak';
    return 'txt-muted';
  }
</script>

<section class="diff-card" aria-label="报告对比">
  <header class="diff-head">
    <div class="diff-title-col">
      <span class="mono diff-kicker">DIFF // 报告并排对比（检出 {diffCount} 项差异）</span>
      <span class="diff-sub">横向对比两份诊断报告的出口归属与服务可达性差异</span>
    </div>
    <button type="button" class="btn btn-subtle btn-xs" onclick={onClose}>
      [退出对比]
    </button>
  </header>

  <div class="picker-bar">
    <label class="picker">
      <span class="mono picker-lbl">左侧基线 A:</span>
      <select class="select mono" bind:value={leftId}>
        {#each entries as e (e.id)}
          <option value={e.id}>{e.label}</option>
        {/each}
      </select>
    </label>

    <label class="picker">
      <span class="mono picker-lbl">右侧对照 B:</span>
      <select class="select mono" bind:value={rightId}>
        {#each entries as e (e.id)}
          <option value={e.id}>{e.label}</option>
        {/each}
      </select>
    </label>
  </div>

  <div class="table-wrap">
    <table class="diff-table">
      <thead>
        <tr>
          <th style="width: 22%">检测维度</th>
          <th style="width: 39%">A · {leftEntry?.label ?? '--'}</th>
          <th style="width: 39%">B · {rightEntry?.label ?? '--'}</th>
        </tr>
      </thead>
      <tbody>
        {#each diffRows as row (row.id)}
          <tr class={row.changed ? 'row-changed' : ''}>
            <td class="dim-cell">
              <div class="dim-inner">
                <span>{row.label}</span>
                {#if row.changed}
                  <span class="tag tag-diff diff-pill">DIFF</span>
                {/if}
              </div>
            </td>
            <td class={`mono val-cell ${toneClass(row.leftTone)}`}>{row.leftText}</td>
            <td class={`mono val-cell ${toneClass(row.rightTone)}`}>{row.rightText}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</section>

<style>
  .diff-card {
    border: 2px solid var(--rule-strong);
    background: var(--bg);
  }

  .diff-head {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.6rem;
    padding: 0.65rem 0.9rem;
    background: var(--bg-subtle);
    border-bottom: 1px solid var(--rule-strong);
  }

  .diff-title-col {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    gap: 0.6rem;
  }

  .diff-kicker {
    font-size: 12px;
    font-weight: 600;
  }

  .diff-sub {
    font-size: 12px;
    color: var(--fg-muted);
  }

  .btn-xs {
    padding: 0.25rem 0.52rem;
    font-size: 11px;
  }

  .picker-bar {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.8rem;
    padding: 0.65rem 0.9rem;
    background: var(--bg-inset);
    border-bottom: 1px solid var(--rule);
  }

  .picker {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    min-width: 0;
  }

  .picker-lbl {
    font-size: 11.5px;
    color: var(--fg-muted);
    white-space: nowrap;
  }

  .select {
    flex: 1;
    min-width: 0;
    padding: 0.35rem 0.5rem;
    border: 1px solid var(--rule-strong);
    background: var(--bg);
    font-size: 12px;
  }

  .table-wrap {
    overflow-x: auto;
  }

  .diff-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12.5px;
  }

  .diff-table th {
    text-align: left;
    padding: 0.45rem 0.9rem;
    background: var(--bg-subtle);
    border-bottom: 1px solid var(--rule);
    font-family: var(--font-mono);
    font-size: 11px;
    color: var(--fg-muted);
  }

  .diff-table td {
    padding: 0.55rem 0.9rem;
    border-bottom: 1px solid var(--rule);
  }

  .diff-table tbody tr:last-child td {
    border-bottom: none;
  }

  .row-changed {
    background: var(--diff-bg);
  }

  .dim-cell {
    font-weight: 600;
    vertical-align: middle;
  }

  .dim-inner {
    display: flex;
    align-items: center;
    gap: 0.45rem;
  }

  .diff-pill {
    font-size: 10px;
    padding: 0 0.28rem;
  }

  .val-cell {
    font-weight: 500;
    word-break: break-word;
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

  .txt-muted {
    color: var(--fg-muted);
  }

  @media (max-width: 700px) {
    .picker-bar {
      grid-template-columns: 1fr;
    }
  }
</style>
