<script lang="ts">
  import { generateRulePatch, type RuleClient } from '../../shared/rules';
  import { copyText } from '../lib/clipboard';
  import { GMS_CHECKLIST_ITEMS, type DeviceEnvironment } from '../lib/quick-check';

  interface Props {
    readonly device: DeviceEnvironment;
    readonly suggested: {
      readonly includeAiBackend: boolean;
      readonly includeAntiGoogleCn: boolean;
      readonly includeGoogleCore: boolean;
      readonly includeGmsFcm: boolean;
    };
    readonly highlightRemedy: boolean;
  }

  const { device, suggested, highlightRemedy }: Props = $props();

  let activeTab = $state<'none' | 'rules' | 'gms'>('none');
  let client = $state<RuleClient>('clash');
  let policyGroup = $state('GoogleAI');
  let overrides = $state<Partial<Record<'aiBackend' | 'antiCn' | 'core' | 'gms', boolean>>>({});
  let copiedPatch = $state(false);
  let gmsChecked = $state<Set<string>>(new Set());

  const includeAiBackend = $derived(overrides.aiBackend ?? suggested.includeAiBackend);
  const includeAntiGoogleCn = $derived(overrides.antiCn ?? suggested.includeAntiGoogleCn);
  const includeGoogleCore = $derived(overrides.core ?? suggested.includeGoogleCore);
  const includeGmsFcm = $derived(overrides.gms ?? suggested.includeGmsFcm);

  const patchCode = $derived(
    generateRulePatch(client, {
      policyGroup,
      includeAiBackend,
      includeAntiGoogleCn,
      includeGoogleCore,
      includeGmsFcm,
    }),
  );

  const accountDrifted = $derived(gmsChecked.has('terms_already_cn_hk'));

  function toggleTab(tab: 'rules' | 'gms'): void {
    activeTab = activeTab === tab ? 'none' : tab;
  }

  function toggleGms(id: string): void {
    const next = new Set(gmsChecked);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    gmsChecked = next;
  }

  async function handleCopyPatch(): Promise<void> {
    const ok = await copyText(patchCode);
    if (ok) {
      copiedPatch = true;
      setTimeout(() => {
        copiedPatch = false;
      }, 1600);
    }
  }
</script>

<section class="drawer-wrap" aria-label="按需排障与规则修复工具抽屉">
  <div class="drawer-bar">
    <div class="drawer-left">
      <span class="mono drawer-kicker">REMEDY TOOLS // 按需排障抽屉</span>
      {#if highlightRemedy}
        <span class="tag tag-leak">[建议展开修复]</span>
      {:else if device.isAndroid}
        <span class="tag tag-diff">[检测到 Android · 可查 GMS]</span>
      {/if}
    </div>

    <div class="drawer-tabs">
      <button
        type="button"
        class={`btn btn-xs ${activeTab === 'rules' ? 'btn-active' : 'btn-subtle'}`}
        onclick={() => toggleTab('rules')}
      >
        {activeTab === 'rules' ? '[-] 收起代理规则补丁' : '[+] 生成代理规则补丁 (Clash / sing-box / Surge / Loon)'}
      </button>
      <button
        type="button"
        class={`btn btn-xs ${activeTab === 'gms' ? 'btn-active' : 'btn-subtle'}`}
        onclick={() => toggleTab('gms')}
      >
        {activeTab === 'gms' ? '[-] 收起手机 GMS 排查' : '[+] 手机 GMS / 跨设备防送中清单'}
      </button>
    </div>
  </div>

  {#if activeTab === 'rules'}
    <div class="drawer-body">
      <div class="rule-toolbar">
        <div class="client-tabs">
          {#each [
            { id: 'clash', label: 'Clash / Mihomo' },
            { id: 'singbox', label: 'sing-box' },
            { id: 'surge', label: 'Surge / Shadowrocket' },
            { id: 'loon', label: 'Loon' },
          ] as item (item.id)}
            <button
              type="button"
              class={`btn btn-xs ${client === item.id ? 'btn-active' : 'btn-subtle'}`}
              onclick={() => (client = item.id as RuleClient)}
            >
              {item.label}
            </button>
          {/each}
        </div>

        <div class="rule-right">
          <label class="grp-label mono">
            策略组:
            <input type="text" class="grp-input mono" bind:value={policyGroup} />
          </label>
          <button type="button" class="btn btn-xs" onclick={handleCopyPatch}>
            {copiedPatch ? '[已复制补丁]' : '[复制补丁]'}
          </button>
        </div>
      </div>

      <div class="scope-row">
        <label class="scope-item">
          <input
            type="checkbox"
            checked={includeAiBackend}
            onchange={(e) => (overrides = { ...overrides, aiBackend: e.currentTarget.checked })}
          />
          <span>AI 隐性后端与 WAA</span>
        </label>
        <label class="scope-item">
          <input
            type="checkbox"
            checked={includeAntiGoogleCn}
            onchange={(e) => (overrides = { ...overrides, antiCn: e.currentTarget.checked })}
          />
          <span>阻断 GoogleCN 直连</span>
        </label>
        <label class="scope-item">
          <input
            type="checkbox"
            checked={includeGoogleCore}
            onchange={(e) => (overrides = { ...overrides, core: e.currentTarget.checked })}
          />
          <span>Google 底座 (accounts/policies/play/search)</span>
        </label>
        <label class="scope-item">
          <input
            type="checkbox"
            checked={includeGmsFcm}
            onchange={(e) => (overrides = { ...overrides, gms: e.currentTarget.checked })}
          />
          <span>安卓 GMS / FCM (mtalk)</span>
        </label>
      </div>

      <pre class="code-box">{patchCode}</pre>
    </div>
  {/if}

  {#if activeTab === 'gms'}
    <div class="drawer-body">
      <div class="gms-note">
        <strong>反焦虑提醒：</strong>保留原版浏览器的 <code>zh-CN</code>、东八区与中文字体是最自然的基线，切勿乱装 Canvas 加噪插件。真正导致账号或独享 VPS IP 送中的，是以下 8 项定位/直连漏网源（{device.platformLabel}{device.romHint ? ` · ${device.romHint}` : ''}）：
      </div>

      <div class="gms-list">
        {#each GMS_CHECKLIST_ITEMS as item (item.id)}
          {@const checked = gmsChecked.has(item.id)}
          <label class={`gms-row ${checked ? 'gms-on' : ''}`}>
            <input type="checkbox" checked={checked} onchange={() => toggleGms(item.id)} />
            <div>
              <div class="gms-title">{item.label}</div>
              <div class="gms-desc">{item.detail}</div>
            </div>
          </label>
        {/each}
      </div>

      <div class="gms-foot">
        {#if accountDrifted}
          <span class="tag tag-leak">[账号已送中]</span>
          <span>须先关闭定位扫描与全端漏网稳定 24~48 小时，再提交</span>
        {:else}
          <span class="mono">官方申诉入口：</span>
        {/if}
        <a href="https://policies.google.com/country-association-form" target="_blank" rel="noopener noreferrer">
          账号归属地修改申请表 ↗
        </a>
        <span>·</span>
        <a href="https://support.google.com/websearch/workflow/9308722" target="_blank" rel="noopener noreferrer">
          VPS IP 位置纠偏反馈 ↗
        </a>
      </div>
    </div>
  {/if}
</section>

<style>
  .drawer-wrap {
    margin-top: var(--space-4);
    border: 1px solid var(--rule);
    background: var(--bg);
  }

  .drawer-bar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.6rem;
    padding: 0.6rem 0.85rem;
    background: var(--bg-subtle);
  }

  .drawer-left {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .drawer-kicker {
    font-size: 11px;
    font-weight: 600;
    color: var(--fg-muted);
  }

  .drawer-tabs {
    display: flex;
    flex-wrap: wrap;
    gap: 0.35rem;
  }

  .btn-xs {
    padding: 0.28rem 0.55rem;
    font-size: 11.5px;
  }

  .drawer-body {
    padding: 0.85rem;
    border-top: 1px solid var(--rule);
    display: flex;
    flex-direction: column;
    gap: 0.7rem;
  }

  .rule-toolbar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.6rem;
  }

  .client-tabs,
  .rule-right {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.35rem;
  }

  .grp-label {
    font-size: 11.5px;
    color: var(--fg-muted);
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
  }

  .grp-input {
    width: 120px;
    padding: 0.24rem 0.45rem;
    border: 1px solid var(--rule-strong);
    background: var(--bg);
    font-size: 12px;
  }

  .scope-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.45rem 1rem;
    padding: 0.5rem 0.65rem;
    border: 1px solid var(--rule);
    background: var(--bg-subtle);
    font-size: 12px;
  }

  .scope-item {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    cursor: pointer;
  }

  .scope-item input {
    accent-color: var(--fg);
  }

  .gms-note {
    font-size: 12.5px;
    color: var(--fg-muted);
    line-height: 1.5;
  }

  .gms-note code {
    font-family: var(--font-mono);
    font-size: 11.5px;
    background: var(--bg-subtle);
    border: 1px solid var(--rule);
    padding: 0 0.22rem;
  }

  .gms-list {
    border: 1px solid var(--rule);
  }

  .gms-row {
    display: flex;
    align-items: flex-start;
    gap: 0.6rem;
    padding: 0.58rem 0.75rem;
    border-bottom: 1px solid var(--rule);
    cursor: pointer;
  }

  .gms-row:last-child {
    border-bottom: none;
  }

  .gms-row:hover {
    background: var(--bg-subtle);
  }

  .gms-on {
    background: var(--diff-bg);
  }

  .gms-row input {
    margin-top: 0.2rem;
    accent-color: var(--fg);
  }

  .gms-title {
    font-size: 13px;
    font-weight: 600;
  }

  .gms-desc {
    font-size: 11.5px;
    color: var(--fg-muted);
    margin-top: 0.15rem;
  }

  .gms-foot {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.45rem;
    font-size: 12px;
    color: var(--fg-muted);
  }
</style>
