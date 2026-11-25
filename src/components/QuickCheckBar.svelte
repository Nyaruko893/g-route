<script lang="ts">
  import type {
    DomesticDirectResult,
    DualStunResult,
    EchoStackResult,
    QuickCheckSummary,
  } from '../lib/quick-check';
  import { maskDisplayIp } from '../lib/quick-check';

  interface Props {
    readonly domestic: DomesticDirectResult;
    readonly v4: EchoStackResult;
    readonly v6: EchoStackResult;
    readonly stun: DualStunResult;
    readonly summary: QuickCheckSummary;
    readonly running: boolean;
    readonly onRerun: () => void;
  }

  const { domestic, v4, v6, stun, summary, running, onRerun }: Props = $props();

  let revealIp = $state(false);

  function fmtIp(ip: string | null): string {
    if (!ip) return '--';
    return revealIp ? ip : maskDisplayIp(ip);
  }

  function toneClass(tone: 'ok' | 'diff' | 'leak' | 'wait'): string {
    return `tag tag-${tone}`;
  }
</script>

<section class="qbar" aria-label="浏览器网络快照">
  <div class="qbar-head">
    <div class="qbar-title">
      <span class="mono qbar-code">BROWSER SNAPSHOT</span>
      <span class="qbar-desc">当前浏览器网络快照（IPv4/IPv6 双栈 · 分流基线 · WebRTC STUN）</span>
    </div>
    <div class="qbar-actions">
      <button type="button" class="btn btn-subtle btn-xs" onclick={() => (revealIp = !revealIp)}>
        {revealIp ? '[隐藏 IP]' : '[显示完整 IP]'}
      </button>
      <button type="button" class="btn btn-subtle btn-xs" disabled={running} onclick={onRerun}>
        {running ? '[探测中...]' : '[重测]'}
      </button>
    </div>
  </div>

  <div class="qbar-grid">
    <div class="qcell">
      <div class="qcell-top">
        <span class="mono qk">01 分流基线 (国内直连)</span>
        <span class={toneClass(summary.topologyTone)}>
          {domestic.isChinaIp ? '[DIRECT]' : domestic.status === 'running' ? '[WAIT]' : '[GLOBAL]'}
        </span>
      </div>
      <div class="qv mono">
        {#if domestic.status === 'running'}
          探测中...
        {:else if domestic.ip}
          {domestic.isChinaIp ? 'CN · ' : ''}{fmtIp(domestic.ip)}
        {:else}
          未直连 / 不可达
        {/if}
      </div>
      <div class="qs">{domestic.locationLabel ?? summary.topologyLabel}</div>
    </div>

    <div class="qcell">
      <div class="qcell-top">
        <span class="mono qk">02 通用海外 IPv4</span>
        <span class={toneClass(v4.meta?.broadcastDrift ? 'diff' : v4.status === 'ok' ? 'ok' : 'wait')}>
          {v4.status === 'ok' ? `[${v4.meta?.country ?? 'OK'}]` : v4.status === 'running' ? '[WAIT]' : '[N/A]'}
        </span>
      </div>
      <div class="qv mono">
        {#if v4.status === 'running'}
          探测中...
        {:else if v4.ip}
          {fmtIp(v4.ip)}
        {:else}
          不可达
        {/if}
      </div>
      <div class="qs">
        {#if v4.meta}
          AS{v4.meta.asn ?? '?'} {v4.meta.org ?? ''}
        {:else}
          {v4.source ?? '通用海外规则出口'}
        {/if}
      </div>
    </div>

    <div class="qcell">
      <div class="qcell-top">
        <span class="mono qk">03 通用海外 IPv6</span>
        <span class={toneClass(summary.dualStackMismatch ? 'leak' : v6.status === 'ok' ? 'ok' : 'wait')}>
          {summary.dualStackMismatch
            ? '[跨国冲突]'
            : v6.status === 'ok'
              ? `[${v6.meta?.country ?? 'OK'}]`
              : v6.status === 'running'
                ? '[WAIT]'
                : '[未启用]'}
        </span>
      </div>
      <div class="qv mono">
        {#if v6.status === 'running'}
          探测中...
        {:else if v6.ip}
          {fmtIp(v6.ip)}
        {:else}
          仅 IPv4
        {/if}
      </div>
      <div class="qs">
        {#if v6.meta}
          AS{v6.meta.asn ?? '?'} {v6.meta.org ?? ''}
        {:else}
          未检测到 IPv6 出站
        {/if}
      </div>
    </div>

    <div class="qcell">
      <div class="qcell-top">
        <span class="mono qk">04 WebRTC / STUN UDP</span>
        <span class={toneClass(summary.udpTone)}>
          {summary.isUdpDomesticLeak ? '[路径不一致]' : summary.udpTone === 'diff' ? '[独立出口]' : summary.udpTone === 'ok' ? '[一致]' : '[WAIT]'}
        </span>
      </div>
      <div class="qv">
        {summary.udpLabel}
      </div>
      <div class="qs">
        {#if stun.google.srflxIps[0]}
          Google STUN: {fmtIp(stun.google.srflxIps[0])}
        {:else}
          {summary.udpDetail}
        {/if}
      </div>
    </div>
  </div>
</section>

<style>
  .qbar {
    border: 1px solid var(--rule-strong);
    background: var(--bg);
    margin-bottom: var(--space-4);
  }

  .qbar-head {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
    padding: 0.45rem 0.75rem;
    background: var(--bg-subtle);
    border-bottom: 1px solid var(--rule);
  }

  .qbar-title {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    gap: 0.55rem;
  }

  .qbar-code {
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.04em;
    color: var(--fg);
  }

  .qbar-desc {
    font-size: 12px;
    color: var(--fg-muted);
  }

  .qbar-actions {
    display: flex;
    gap: 0.35rem;
  }

  .btn-xs {
    padding: 0.22rem 0.5rem;
    font-size: 11px;
  }

  .qbar-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
  }

  .qcell {
    padding: 0.65rem 0.75rem;
    border-right: 1px solid var(--rule);
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    min-width: 0;
  }

  .qcell:last-child {
    border-right: none;
  }

  .qcell-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.35rem;
  }

  .qk {
    font-size: 11px;
    color: var(--fg-muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .qv {
    font-size: 13.5px;
    font-weight: 600;
    line-height: 1.3;
    word-break: break-all;
  }

  .qs {
    font-size: 11.5px;
    color: var(--fg-muted);
    line-height: 1.35;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  @media (max-width: 900px) {
    .qbar-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .qcell {
      border-bottom: 1px solid var(--rule);
    }

    .qcell:nth-child(2n) {
      border-right: none;
    }

    .qcell:nth-last-child(-n + 2) {
      border-bottom: none;
    }
  }

  @media (max-width: 560px) {
    .qbar-grid {
      grid-template-columns: 1fr;
    }

    .qcell {
      border-right: none;
      border-bottom: 1px solid var(--rule);
    }

    .qcell:last-child {
      border-bottom: none;
    }
  }
</style>
