import type { CliReportV1 } from '../../shared/report-codec';
import {
  splitExitTag,
  type CellTone,
  type ExitSlotColor,
  type ReportDiagnosis,
} from '../../shared/report-diagnosis';

interface Palette {
  readonly bg: string;
  readonly bgSubtle: string;
  readonly bgInset: string;
  readonly fg: string;
  readonly fgMuted: string;
  readonly fgFaint: string;
  readonly rule: string;
  readonly ruleStrong: string;
  readonly ok: string;
  readonly okBg: string;
  readonly diff: string;
  readonly diffBg: string;
  readonly leak: string;
  readonly leakBg: string;
  readonly exCn: readonly [string, string];
  readonly exA: readonly [string, string];
  readonly exB: readonly [string, string];
  readonly exC: readonly [string, string];
  readonly exD: readonly [string, string];
}

const LIGHT_PALETTE: Palette = {
  bg: '#f7f6f1',
  bgSubtle: '#efede6',
  bgInset: '#e7e4dc',
  fg: '#1b1d24',
  fgMuted: '#5b5e68',
  fgFaint: '#858892',
  rule: '#ccc9c0',
  ruleStrong: '#242731',
  ok: '#146c43',
  okBg: '#dcf4e6',
  diff: '#9a5b0c',
  diffBg: '#fae8c8',
  leak: '#b42318',
  leakBg: '#fbdad7',
  exCn: ['#0f766e', '#d6f5f0'],
  exA: ['#1d4ed8', '#dbeafe'],
  exB: ['#c2410c', '#ffedd5'],
  exC: ['#6d28d9', '#ede9fe'],
  exD: ['#be185d', '#fce7f3'],
};

const DARK_PALETTE: Palette = {
  bg: '#16181e',
  bgSubtle: '#1e2129',
  bgInset: '#111318',
  fg: '#eceae3',
  fgMuted: '#a2a5b0',
  fgFaint: '#727684',
  rule: '#323642',
  ruleStrong: '#dcdad2',
  ok: '#56c288',
  okBg: '#193025',
  diff: '#e0a546',
  diffBg: '#302719',
  leak: '#eb6f63',
  leakBg: '#331d1c',
  exCn: ['#2dd4bf', '#133432'],
  exA: ['#60a5fa', '#172554'],
  exB: ['#fb923c', '#431407'],
  exC: ['#a78bfa', '#2e1065'],
  exD: ['#f472b6', '#500724'],
};

function exitColors(color: ExitSlotColor, p: Palette): { fg: string; bg: string; border: string } {
  if (color === 'cn') return { fg: p.exCn[0], bg: p.exCn[1], border: p.exCn[0] };
  if (color === 'a') return { fg: p.exA[0], bg: p.exA[1], border: p.exA[0] };
  if (color === 'b') return { fg: p.exB[0], bg: p.exB[1], border: p.exB[0] };
  if (color === 'c') return { fg: p.exC[0], bg: p.exC[1], border: p.exC[0] };
  if (color === 'd') return { fg: p.exD[0], bg: p.exD[1], border: p.exD[0] };
  return { fg: p.fgMuted, bg: p.bgSubtle, border: p.rule };
}

const FONT_MONO = '"IBM Plex Mono", ui-monospace, "Cascadia Mono", Consolas, monospace';
const FONT_SANS = '"PingFang SC", "Microsoft YaHei", "Noto Sans SC", system-ui, sans-serif';

function toneColors(tone: CellTone, p: Palette): { fg: string; bg: string; border: string } {
  if (tone === 'ok') return { fg: p.ok, bg: p.okBg, border: p.ok };
  if (tone === 'diff') return { fg: p.diff, bg: p.diffBg, border: p.diff };
  if (tone === 'leak') return { fg: p.leak, bg: p.leakBg, border: p.leak };
  return { fg: p.fgMuted, bg: p.bgSubtle, border: p.rule };
}

function truncateText(ctx: CanvasRenderingContext2D, text: string, maxW: number): string {
  if (ctx.measureText(text).width <= maxW) return text;
  let lo = 0;
  let hi = text.length;
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    if (ctx.measureText(`${text.slice(0, mid)}…`).width <= maxW) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return `${text.slice(0, lo)}…`;
}

function wrapLines(ctx: CanvasRenderingContext2D, text: string, maxW: number, maxLines = 2): string[] {
  const lines: string[] = [];
  let current = '';
  for (const ch of text) {
    const next = current + ch;
    if (ctx.measureText(next).width > maxW && current.length > 0) {
      lines.push(current);
      if (lines.length >= maxLines) {
        const last = lines[lines.length - 1] ?? '';
        lines[lines.length - 1] = truncateText(ctx, last + ch, maxW);
        return lines;
      }
      current = ch;
    } else {
      current = next;
    }
  }
  if (current) lines.push(current);
  return lines;
}

export function resolveEffectiveDarkTheme(): boolean {
  const attr = document.documentElement.getAttribute('data-theme');
  if (attr === 'dark') return true;
  if (attr === 'light') return false;
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false;
}

export async function renderReportCardPngBlob(
  report: CliReportV1,
  diag: ReportDiagnosis,
  darkTheme: boolean,
): Promise<Blob> {
  if (document.fonts?.ready) {
    await document.fonts.ready.catch(() => {});
  }

  const p = darkTheme ? DARK_PALETTE : LIGHT_PALETTE;
  const dualStack = Boolean(report.v4 && report.v6);
  const W = 920;
  const PAD = 32;
  const INNER = W - PAD * 2;
  const ROW_H = 44;
  const hasClusters = diag.routeClusters.length > 0;
  const CLUSTER_H = hasClusters
    ? 34 + diag.routeClusters.length * 32 + diag.routeAlarms.slice(0, 3).length * 22 + 12
    : 0;
  const H = 310 + (diag.googleEgress ? 12 : 0) + CLUSTER_H + diag.rows.length * ROW_H + 84;
  const DPR = 2;

  const canvas = document.createElement('canvas');
  canvas.width = W * DPR;
  canvas.height = H * DPR;
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    throw new Error('无法创建 Canvas 2D 上下文');
  }
  ctx.scale(DPR, DPR);
  ctx.textBaseline = 'middle';

  // Background
  ctx.fillStyle = p.bg;
  ctx.fillRect(0, 0, W, H);

  // Outer precision border
  ctx.strokeStyle = p.ruleStrong;
  ctx.lineWidth = 2;
  ctx.strokeRect(PAD, PAD, INNER, H - PAD * 2);

  let y = PAD;

  // 1. Header bar
  const HEAD_H = 54;
  ctx.fillStyle = p.bgSubtle;
  ctx.fillRect(PAD + 1, y + 1, INNER - 2, HEAD_H - 1);

  ctx.fillStyle = p.fg;
  ctx.font = `600 15px ${FONT_MONO}`;
  ctx.fillText('G-ROUTE // GOOGLE 生态送中与分流体检卡', PAD + 20, y + 27);

  const ts = new Date(report.t * 1000).toISOString().replace('T', ' ').slice(0, 16) + ' UTC';
  const metaRight = `${diag.transportLabel}  ·  ${ts}`;
  ctx.fillStyle = p.fgMuted;
  ctx.font = `500 12px ${FONT_MONO}`;
  const metaW = ctx.measureText(metaRight).width;
  ctx.fillText(metaRight, PAD + INNER - 20 - metaW, y + 27);

  y += HEAD_H;
  ctx.strokeStyle = p.ruleStrong;
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(PAD, y + 0.5);
  ctx.lineTo(PAD + INNER, y + 0.5);
  ctx.stroke();

  // 2. Verdict banner
  const VERDICT_H = 114;
  const vTone: CellTone =
    diag.tier === 'drift' ? 'leak' : diag.tier === 'partial' ? 'diff' : 'ok';
  const vc = toneColors(vTone, p);

  // Verdict pill box (0px sharp precision)
  ctx.font = `600 13px ${FONT_MONO}`;
  const codeTxt = `[${diag.tierCode}]`;
  const codeW = ctx.measureText(codeTxt).width + 18;
  ctx.fillStyle = vc.bg;
  ctx.fillRect(PAD + 20, y + 18, codeW, 26);
  ctx.strokeStyle = vc.border;
  ctx.lineWidth = 1;
  ctx.strokeRect(PAD + 20.5, y + 18.5, codeW - 1, 25);
  ctx.fillStyle = vc.fg;
  ctx.fillText(codeTxt, PAD + 29, y + 31);

  // Headline
  ctx.fillStyle = p.fg;
  ctx.font = `600 18px ${FONT_SANS}`;
  const headX = PAD + 20 + codeW + 12;
  ctx.fillText(truncateText(ctx, diag.headline, PAD + INNER - 20 - headX), headX, y + 31);

  // Summary (up to 2 lines)
  ctx.fillStyle = p.fgMuted;
  ctx.font = `400 12.5px ${FONT_SANS}`;
  const sumLines = wrapLines(ctx, diag.summary, INNER - 40, 2);
  sumLines.forEach((line, idx) => {
    ctx.fillText(line, PAD + 20, y + 62 + idx * 18);
  });

  // Badges strip
  let bx = PAD + 20;
  ctx.font = `600 11px ${FONT_MONO}`;
  for (const badge of diag.badges.slice(0, 5)) {
    const bc = toneColors(badge.tone, p);
    const bw = ctx.measureText(badge.text).width + 14;
    if (bx + bw > PAD + INNER - 20) break;
    ctx.fillStyle = bc.bg;
    ctx.fillRect(bx, y + 90, bw, 19);
    ctx.strokeStyle = bc.border;
    ctx.strokeRect(bx + 0.5, y + 90.5, bw - 1, 18);
    ctx.fillStyle = bc.fg;
    ctx.fillText(badge.text, bx + 7, y + 100);
    bx += bw + 8;
  }

  y += VERDICT_H;
  ctx.strokeStyle = p.rule;
  ctx.beginPath();
  ctx.moveTo(PAD, y + 0.5);
  ctx.lineTo(PAD + INNER, y + 0.5);
  ctx.stroke();

  // 3. Egress & Three-way Geo comparison strip
  const GEO_H = diag.googleEgress ? 78 : 66;
  const primary = report.v4 ?? report.v6;
  const colWidths = [INNER * 0.44, INNER * 0.18, INNER * 0.18, INNER * 0.2];
  const egressSub = diag.googleEgress
    ? `Google → ${diag.googleEgress.ip} · ${diag.googleEgress.org} [${diag.googleEgress.kindLabel}]`
    : `${diag.defaultEgress.org} [${diag.defaultEgress.kindLabel}]`;
  const cells = [
    {
      k: diag.googleEgress ? '双出口归属（通用 → Google）' : '出口节点 / ASN',
      v: `${diag.defaultEgress.ip} · AS${diag.defaultEgress.asn ?? '?'}`,
      sub: truncateText(ctx, egressSub, (colWidths[0] ?? 320) - 24),
      tone: 'muted' as CellTone,
    },
    {
      k: '公开库 GeoIP',
      v: diag.publicGeoLabel,
      sub: 'ident.me / 公开库',
      tone: 'muted' as CellTone,
    },
    {
      k: 'Apple 第三方对照',
      v: report.ap ?? '--',
      sub: 'pep/gcc',
      tone: 'muted' as CellTone,
    },
    {
      k: 'Google 实测归属',
      v: diag.googleGeoLabel,
      sub: diag.googleOnlyDrift ? '私有库独立送中' : '6 路真值汇总',
      tone: diag.tier === 'drift' ? ('leak' as CellTone) : diag.tier === 'partial' ? ('diff' as CellTone) : ('ok' as CellTone),
    },
  ];

  let gx = PAD;
  cells.forEach((cell, idx) => {
    const cw = colWidths[idx] ?? 180;
    if (idx > 0) {
      ctx.strokeStyle = p.rule;
      ctx.beginPath();
      ctx.moveTo(gx + 0.5, y);
      ctx.lineTo(gx + 0.5, y + GEO_H);
      ctx.stroke();
    }
    ctx.fillStyle = p.fgFaint;
    ctx.font = `500 10.5px ${FONT_MONO}`;
    ctx.fillText(cell.k, gx + 14, y + 16);

    ctx.fillStyle = cell.tone === 'muted' ? p.fg : toneColors(cell.tone, p).fg;
    ctx.font = `600 13.5px ${FONT_MONO}`;
    ctx.fillText(truncateText(ctx, cell.v, cw - 24), gx + 14, y + 36);

    ctx.fillStyle = p.fgMuted;
    ctx.font = `400 11px ${FONT_SANS}`;
    ctx.fillText(truncateText(ctx, cell.sub, cw - 24), gx + 14, y + 54);
    gx += cw;
  });

  y += GEO_H;
  ctx.strokeStyle = p.ruleStrong;
  ctx.beginPath();
  ctx.moveTo(PAD, y + 0.5);
  ctx.lineTo(PAD + INNER, y + 0.5);
  ctx.stroke();

  // 3.5 Optional 6-Bucket Split-Route Topology Radar
  if (hasClusters) {
    ctx.fillStyle = p.bgSubtle;
    ctx.fillRect(PAD + 1, y + 1, INNER - 2, 33);
    ctx.fillStyle = p.fgMuted;
    ctx.font = `600 11px ${FONT_MONO}`;
    const ovCnt = diag.routeClusters.filter((c) => !c.isCnDirect).length;
    ctx.fillText(`[01] 6 桶分流拓扑雷达 · 自动聚类 (${ovCnt} 路海外出口)`, PAD + 20, y + 17);
    const rttHdrW = ctx.measureText('RTT').width;
    ctx.fillStyle = p.fgFaint;
    ctx.fillText('RTT', PAD + INNER - 20 - rttHdrW, y + 17);
    y += 34;

    for (const cl of diag.routeClusters) {
      ctx.strokeStyle = p.rule;
      ctx.beginPath();
      ctx.moveTo(PAD, y + 0.5);
      ctx.lineTo(PAD + INNER, y + 0.5);
      ctx.stroke();

      const cc = exitColors(cl.slotColor, p);
      ctx.fillStyle = cc.bg;
      ctx.fillRect(PAD + 20, y + 6, 72, 20);
      ctx.strokeStyle = cc.border;
      ctx.strokeRect(PAD + 20.5, y + 6.5, 71, 19);
      ctx.fillStyle = cc.fg;
      ctx.font = `600 10.5px ${FONT_MONO}`;
      const sw = ctx.measureText(cl.slot).width;
      ctx.fillText(cl.slot, PAD + 20 + (72 - sw) / 2, y + 16);

      ctx.fillStyle = p.fg;
      ctx.font = `600 11.5px ${FONT_MONO}`;
      const asnOrg = `${cl.ip} · ${cl.asn ? `AS${cl.asn} ` : ''}${cl.org}`;
      ctx.fillText(truncateText(ctx, asnOrg, 315), PAD + 104, y + 16);

      ctx.fillStyle = p.fgMuted;
      ctx.font = `400 11.5px ${FONT_SANS}`;
      ctx.fillText(truncateText(ctx, cl.buckets.join(' / '), 325), PAD + 432, y + 16);

      const msTxt = cl.avgMs !== null ? `${cl.avgMs} ms` : '--';
      ctx.fillStyle = p.fgFaint;
      ctx.font = `500 11px ${FONT_MONO}`;
      const mw = ctx.measureText(msTxt).width;
      ctx.fillText(msTxt, PAD + INNER - 20 - mw, y + 16);
      y += 32;
    }

    for (const al of diag.routeAlarms.slice(0, 3)) {
      const ac = toneColors(al.tone, p);
      ctx.fillStyle = ac.fg;
      ctx.font = `500 11px ${FONT_SANS}`;
      const line = `${al.tone === 'leak' ? '[!]' : '[i]'} ${al.title}: ${al.detail}`;
      ctx.fillText(truncateText(ctx, line, INNER - 40), PAD + 20, y + 12);
      y += 22;
    }
    y += 12;
    ctx.strokeStyle = p.ruleStrong;
    ctx.beginPath();
    ctx.moveTo(PAD, y + 0.5);
    ctx.lineTo(PAD + INNER, y + 0.5);
    ctx.stroke();
  }

  // 4. Service Matrix Table Header
  const TH_H = 34;
  ctx.fillStyle = p.bgSubtle;
  ctx.fillRect(PAD + 1, y + 1, INNER - 2, TH_H - 1);

  ctx.fillStyle = p.fgMuted;
  ctx.font = `600 11px ${FONT_MONO}`;
  ctx.fillText('GOOGLE 服务维度', PAD + 20, y + 17);
  if (dualStack) {
    ctx.fillText(`IPv4 (${report.v4?.ip ?? ''})`, PAD + 280, y + 17);
    ctx.fillText(`IPv6 (${report.v6?.ip ?? ''})`, PAD + 565, y + 17);
  } else {
    const st = report.v4 ? 'IPv4' : 'IPv6';
    ctx.fillText(`实测结论 · ${st}`, PAD + 280, y + 17);
    ctx.fillText('实测出口与真值细节', PAD + 505, y + 17);
  }

  y += TH_H;

  // 5. Matrix Rows
  for (const row of diag.rows) {
    ctx.strokeStyle = p.rule;
    ctx.beginPath();
    ctx.moveTo(PAD, y + 0.5);
    ctx.lineTo(PAD + INNER, y + 0.5);
    ctx.stroke();

    const midY = y + ROW_H / 2;
    ctx.fillStyle = p.fg;
    ctx.font = `600 13px ${FONT_SANS}`;
    ctx.fillText(row.label, PAD + 20, midY - 7);
    ctx.fillStyle = p.fgFaint;
    ctx.font = `400 10.5px ${FONT_MONO}`;
    ctx.fillText(row.probeHint, PAD + 20, midY + 10);

    const drawCell = (cell: typeof row.v4, xPos: number, maxW: number, showDetailBelow: boolean) => {
      if (!cell) {
        ctx.fillStyle = p.fgFaint;
        ctx.font = `500 12px ${FONT_MONO}`;
        ctx.fillText('--', xPos, midY);
        return;
      }
      const cc = toneColors(cell.tone, p);
      const pfx = cell.tone === 'ok' ? '✓ ' : cell.tone === 'leak' ? '✕ ' : cell.tone === 'diff' ? '! ' : '';
      ctx.font = `600 11.5px ${FONT_MONO}`;
      const bTxt = truncateText(ctx, `${pfx}${cell.badge}`, maxW - 14);
      const bw = ctx.measureText(bTxt).width + 12;
      const by = showDetailBelow ? midY - 16 : midY - 10;
      ctx.fillStyle = cc.bg;
      ctx.fillRect(xPos, by, bw, 20);
      ctx.strokeStyle = cc.border;
      ctx.strokeRect(xPos + 0.5, by + 0.5, bw - 1, 19);
      ctx.fillStyle = cc.fg;
      ctx.fillText(bTxt, xPos + 6, by + 10.5);

      if (showDetailBelow) {
        ctx.fillStyle = p.fgMuted;
        ctx.font = `400 10.5px ${FONT_SANS}`;
        ctx.fillText(truncateText(ctx, cell.detail, maxW), xPos, midY + 12);
      }
    };

    if (dualStack) {
      drawCell(row.v4, PAD + 280, 265, true);
      drawCell(row.v6, PAD + 565, 270, true);
    } else {
      const single = row.v4 ?? row.v6;
      drawCell(single, PAD + 280, 215, false);
      if (single) {
        const tag = splitExitTag(single.exitSlot);
        let cx = PAD + 505;
        if (tag && tag.color !== 'unknown') {
          const ec = exitColors(tag.color, p);
          ctx.font = `600 10.5px ${FONT_MONO}`;
          const tw = ctx.measureText(tag.slot).width + 12;
          ctx.fillStyle = ec.bg;
          ctx.fillRect(cx, midY - 10, tw, 20);
          ctx.strokeStyle = ec.border;
          ctx.strokeRect(cx + 0.5, midY - 9.5, tw - 1, 19);
          ctx.fillStyle = ec.fg;
          ctx.fillText(tag.slot, cx + 6, midY);
          cx += tw + 8;
        }
        const tail = [tag ? tag.rest : single.exitSlot, single.ms !== undefined ? `${single.ms}ms` : '']
          .filter(Boolean)
          .join(' · ');
        ctx.fillStyle = p.fgMuted;
        ctx.font = `500 11.5px ${FONT_MONO}`;
        ctx.fillText(truncateText(ctx, tail || single.detail, PAD + INNER - 20 - cx), cx, midY);
      }
    }

    y += ROW_H;
  }

  // 6. Footer stamp
  ctx.strokeStyle = p.ruleStrong;
  ctx.beginPath();
  ctx.moveTo(PAD, y + 0.5);
  ctx.lineTo(PAD + INNER, y + 0.5);
  ctx.stroke();

  const footY = y + (H - PAD - y) / 2;
  ctx.fillStyle = p.fgMuted;
  ctx.font = `500 11px ${FONT_MONO}`;
  ctx.fillText('G-ROUTE · 无状态零落库 · 不打欺诈分 · 纯本地实测生成', PAD + 20, footY);

  const rightStamp = `IP: ${primary?.ip ?? '--'} · ${diag.tierCode}`;
  const rw = ctx.measureText(rightStamp).width;
  ctx.fillStyle = p.fgFaint;
  ctx.fillText(rightStamp, PAD + INNER - 20 - rw, footY);

  return new Promise<Blob>((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob);
      else reject(new Error('PNG 编码失败'));
    }, 'image/png');
  });
}
