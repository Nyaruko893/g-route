<script lang="ts">
  import { onMount } from 'svelte';
  import type { BaselineResponse } from '../shared/contracts';
  import { STUN_SERVERS } from '../shared/probes';
  import {
    decodeReportInput,
    encodeReportPayload,
    type CliReportV1,
  } from '../shared/report-codec';
  import { diagnoseCliReport } from '../shared/report-diagnosis';
  import { SAMPLE_REPORTS } from '../shared/sample-reports';
  import CliLaunchpad from './components/CliLaunchpad.svelte';
  import DiffView from './components/DiffView.svelte';
  import HealthCard from './components/HealthCard.svelte';
  import QuickCheckBar from './components/QuickCheckBar.svelte';
  import RemedyDrawer from './components/RemedyDrawer.svelte';
  import {
    collectDeviceEnvironment,
    detectDomesticDirect,
    detectDualStack,
    evaluateQuickCheck,
    fetchBaseline,
    resetQuickCheckCache,
    runDualStunProbes,
    type DomesticDirectResult,
    type DualStunResult,
    type EchoStackResult,
  } from './lib/quick-check';
  import {
    loadSessionReports,
    upsertSessionReport,
    type StoredReportEntry,
  } from './lib/session-store';

  const device = collectDeviceEnvironment();
  const origin = typeof window !== 'undefined' ? window.location.origin : 'https://g-route.workers.dev';

  let theme = $state<'auto' | 'light' | 'dark'>('auto');
  let quickRunning = $state(false);
  let baseline = $state<BaselineResponse | null>(null);
  let domestic = $state<DomesticDirectResult>({
    status: 'idle',
    ip: null,
    locationLabel: null,
    isChinaIp: null,
    source: null,
  });
  let v4 = $state<EchoStackResult>({ status: 'idle', ip: null, source: null, meta: null });
  let v6 = $state<EchoStackResult>({ status: 'idle', ip: null, source: null, meta: null });
  let stun = $state<DualStunResult>({
    cloudflare: { server: STUN_SERVERS.cloudflare, status: 'idle', srflxIps: [], primaryMeta: null },
    google: { server: STUN_SERVERS.google, status: 'idle', srflxIps: [], primaryMeta: null },
  });

  // Session report state
  let history = $state<StoredReportEntry[]>([]);
  let activeId = $state<string | null>(null);
  let diffMode = $state(false);
  let hashError = $state<string | null>(null);
  let showQuickImport = $state(false);
  let quickImportText = $state('');
  let quickImportError = $state<string | null>(null);

  const quickSummary = $derived(evaluateQuickCheck({ baseline, domestic, v4, v6, stun }));
  const activeEntry = $derived(activeId ? history.find((e) => e.id === activeId) ?? null : null);
  const activeDiag = $derived(activeEntry ? diagnoseCliReport(activeEntry.report) : null);

  // Merge user session entries with sample presets when opening Diff with only 1 report
  const diffCandidates = $derived.by((): readonly StoredReportEntry[] => {
    if (history.length >= 2) return history;
    const seen = new Set(history.map((h) => h.id));
    const extras: StoredReportEntry[] = SAMPLE_REPORTS.map((s) => ({
      id: s.id,
      label: s.report.lbl ?? s.shortName,
      isSample: true,
      report: s.report,
    })).filter((e) => !seen.has(e.id));
    return [...history, ...extras];
  });

  const drawerSuggested = $derived(
    activeDiag
      ? activeDiag.suggestedPatch
      : {
          includeAiBackend: true,
          includeAntiGoogleCn: quickSummary.isUdpDomesticLeak,
          includeGoogleCore: false,
          includeGmsFcm: device.isAndroid,
        },
  );

  const highlightRemedy = $derived(
    Boolean(activeDiag?.suggestGmsDrawer || quickSummary.isUdpDomesticLeak || quickSummary.dualStackMismatch),
  );

  function cycleTheme(): void {
    const next = theme === 'auto' ? 'dark' : theme === 'dark' ? 'light' : 'auto';
    theme = next;
    if (next === 'auto') {
      document.documentElement.removeAttribute('data-theme');
    } else {
      document.documentElement.setAttribute('data-theme', next);
    }
  }

  async function runQuickCheck(): Promise<void> {
    if (quickRunning) return;
    quickRunning = true;
    resetQuickCheckCache();
    domestic = { status: 'running', ip: null, locationLabel: null, isChinaIp: null, source: null };
    stun = {
      cloudflare: { server: STUN_SERVERS.cloudflare, status: 'running', srflxIps: [], primaryMeta: null },
      google: { server: STUN_SERVERS.google, status: 'running', srflxIps: [], primaryMeta: null },
    };

    try {
      await Promise.all([
        fetchBaseline().then((r) => {
          baseline = r;
        }),
        detectDomesticDirect().then((r) => {
          domestic = r;
        }),
        detectDualStack((stack, res) => {
          if (stack === 'v4') v4 = res;
          else v6 = res;
        }),
        runDualStunProbes().then((r) => {
          stun = r;
        }),
      ]);
    } finally {
      quickRunning = false;
    }
  }

  async function syncHashForReport(report: CliReportV1): Promise<void> {
    try {
      const payload = await encodeReportPayload(report);
      window.history.replaceState(null, '', `#r=${payload}`);
    } catch {
      // Ignore history API failures
    }
  }

  function handleImportReport(
    report: CliReportV1,
    meta?: { readonly label?: string; readonly isSample?: boolean },
  ): void {
    hashError = null;
    const res = upsertSessionReport(history, report, meta);
    history = res.entries;
    activeId = res.activeId;
    diffMode = false;
    showQuickImport = false;
    quickImportText = '';
    quickImportError = null;
    void syncHashForReport(report);
  }

  function handleBackHome(): void {
    activeId = null;
    diffMode = false;
    showQuickImport = false;
    hashError = null;
    if (window.location.hash) {
      window.history.replaceState(null, '', window.location.pathname + window.location.search);
    }
  }

  async function handleQuickImportSubmit(): Promise<void> {
    const res = await decodeReportInput(quickImportText);
    if (!res.ok) {
      quickImportError = res.error;
      return;
    }
    handleImportReport(res.report);
  }

  async function loadFromCurrentHash(): Promise<void> {
    const h = window.location.hash;
    if (!h || !h.includes('r=')) return;
    const res = await decodeReportInput(h);
    if (!res.ok) {
      hashError = res.error;
      return;
    }
    hashError = null;
    const up = upsertSessionReport(history, res.report);
    history = up.entries;
    activeId = up.activeId;
    diffMode = false;
  }

  onMount(() => {
    history = loadSessionReports();
    void loadFromCurrentHash();
    void runQuickCheck();

    const onHashChange = () => {
      void loadFromCurrentHash();
    };
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  });
</script>

<div class="shell">
  <header class="masthead">
    <div class="brand-col">
      <div class="brand-kicker mono">G-ROUTE // GOOGLE ECOSYSTEM DIAGNOSTIC INSTRUMENT</div>
      <h1 class="brand-title">Google 生态送中与分流体检仪</h1>
    </div>

    <div class="action-col">
      <button type="button" class="btn btn-subtle" onclick={cycleTheme}>
        主题: {theme === 'auto' ? '自动' : theme === 'dark' ? '深炭' : '纸白'}
      </button>
    </div>
  </header>

  {#if hashError}
    <div class="hash-err mono">[HASH 解析失败] {hashError}</div>
  {/if}

  <main>
    {#if activeEntry && activeDiag}
      <div class="session-strip">
        <div class="session-tabs">
          <span class="mono sess-k">会话报告 ({history.length})</span>
          {#each history as item (item.id)}
            <button
              type="button"
              class={`btn btn-xs ${!diffMode && activeId === item.id ? 'btn-active' : 'btn-subtle'}`}
              onclick={() => {
                activeId = item.id;
                diffMode = false;
                void syncHashForReport(item.report);
              }}
            >
              {item.label}
            </button>
          {/each}
        </div>
        <div class="session-actions">
          <button
            type="button"
            class={`btn btn-xs ${showQuickImport ? 'btn-active' : 'btn-subtle'}`}
            onclick={() => (showQuickImport = !showQuickImport)}
          >
            [+ 导入新报告]
          </button>
          <button
            type="button"
            class={`btn btn-xs ${diffMode ? 'btn-active' : 'btn-subtle'}`}
            onclick={() => (diffMode = !diffMode)}
          >
            {diffMode ? '[返回单卡]' : '[双卡 Diff]'}
          </button>
        </div>
      </div>

      {#if showQuickImport}
        <div class="quick-import">
          <input
            type="text"
            class="qi-input mono"
            placeholder="粘贴另一台 VPS / 修改规则后的 #r= 链接、G1 报告码或 JSON 加入会话对比"
            bind:value={quickImportText}
            onkeydown={(e) => {
              if (e.key === 'Enter') void handleQuickImportSubmit();
            }}
          />
          <button type="button" class="btn btn-xs" onclick={() => void handleQuickImportSubmit()}>
            [解析加入]
          </button>
          {#if quickImportError}
            <div class="qi-err mono">{quickImportError}</div>
          {/if}
        </div>
      {/if}

      {#if diffMode}
        <DiffView
          entries={diffCandidates}
          initialLeftId={activeEntry.id}
          onClose={() => (diffMode = false)}
        />
      {:else}
        <HealthCard
          report={activeEntry.report}
          diag={activeDiag}
          {origin}
          isSample={activeEntry.isSample}
          canDiff={diffCandidates.length >= 2}
          onOpenDiff={() => (diffMode = true)}
          onBackHome={handleBackHome}
        />
      {/if}
    {:else}
      <QuickCheckBar
        {domestic}
        {v4}
        {v6}
        {stun}
        summary={quickSummary}
        running={quickRunning}
        onRerun={() => void runQuickCheck()}
      />

      <CliLaunchpad
        {origin}
        githubRepoUrl={baseline?.githubRepoUrl ?? null}
        onImportReport={handleImportReport}
      />
    {/if}

    <RemedyDrawer {device} suggested={drawerSuggested} {highlightRemedy} />
  </main>

  <footer class="foot mono">
    <span>G-ROUTE // 永久 $0 · 零落库零日志 · #r= 数据永不离开本地浏览器 · 不打欺诈分</span>
    <span>Cloudflare Workers Static Assets · Svelte 5</span>
  </footer>
</div>

<style>
  .shell {
    max-width: var(--max-width);
    margin: 0 auto;
    padding: var(--space-4) var(--space-4) var(--space-6);
  }

  .masthead {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: flex-end;
    gap: var(--space-3);
    padding-bottom: var(--space-3);
    margin-bottom: var(--space-4);
    border-bottom: 2px solid var(--rule-strong);
  }

  .brand-kicker {
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.06em;
    color: var(--fg-muted);
    margin-bottom: 0.15rem;
  }

  .brand-title {
    margin: 0;
    font-size: clamp(1.25rem, 2.2vw, 1.55rem);
    font-weight: 600;
    letter-spacing: -0.02em;
    line-height: 1.25;
  }

  .action-col {
    display: flex;
    align-items: center;
    gap: 0.4rem;
  }

  .hash-err {
    margin-bottom: var(--space-3);
    padding: 0.5rem 0.75rem;
    border: 1px solid var(--leak);
    background: var(--leak-bg);
    color: var(--leak);
    font-size: 12px;
  }

  .session-strip {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
    padding: 0.45rem 0.65rem;
    margin-bottom: var(--space-3);
    border: 1px solid var(--rule);
    background: var(--bg-subtle);
  }

  .session-tabs,
  .session-actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.3rem;
  }

  .sess-k {
    font-size: 11px;
    font-weight: 600;
    color: var(--fg-muted);
    margin-right: 0.25rem;
  }

  .btn-xs {
    padding: 0.24rem 0.5rem;
    font-size: 11px;
  }

  .quick-import {
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
    padding: 0.55rem 0.65rem;
    margin-bottom: var(--space-3);
    border: 1px solid var(--rule-strong);
    background: var(--bg-inset);
  }

  .qi-input {
    flex: 1;
    min-width: 220px;
    padding: 0.35rem 0.55rem;
    border: 1px solid var(--rule);
    background: var(--bg);
    font-size: 12px;
  }

  .qi-err {
    width: 100%;
    font-size: 11.5px;
    color: var(--leak);
  }

  .foot {
    margin-top: var(--space-5);
    padding-top: var(--space-3);
    border-top: 1px solid var(--rule);
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    gap: 0.5rem;
    font-size: 11px;
    color: var(--fg-muted);
  }

  @media (max-width: 720px) {
    .shell {
      padding: var(--space-3) var(--space-3) var(--space-5);
    }
  }
</style>
