import {
  buildReportFingerprint,
  CliReportV1Schema,
  type CliReportV1,
} from '../../shared/report-codec';

export interface StoredReportEntry {
  readonly id: string;
  readonly label: string;
  readonly isSample: boolean;
  readonly report: CliReportV1;
}

const STORAGE_KEY = 'g-route-session-reports-v1';
const MAX_HISTORY = 12;

function makeDefaultLabel(report: CliReportV1): string {
  if (report.lbl) return report.lbl;
  const p = report.v4 ?? report.v6;
  const ip = p?.ip ?? 'unknown';
  const cc = p?.cc ?? '?';
  const mode = report.m === 'proxy' ? 'PC' : 'VPS';
  return `${mode} · ${ip} (${cc})`;
}

export function loadSessionReports(): StoredReportEntry[] {
  if (typeof sessionStorage === 'undefined') return [];
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    const out: StoredReportEntry[] = [];
    for (const item of parsed) {
      if (!item || typeof item !== 'object') continue;
      const rec = item as Record<string, unknown>;
      const valid = CliReportV1Schema.safeParse(rec['report']);
      if (!valid.success) continue;
      const id =
        typeof rec['id'] === 'string' && rec['id'].length > 0
          ? rec['id']
          : buildReportFingerprint(valid.data);
      const label =
        typeof rec['label'] === 'string' && rec['label'].length > 0
          ? rec['label']
          : makeDefaultLabel(valid.data);
      out.push({
        id,
        label,
        isSample: rec['isSample'] === true,
        report: valid.data,
      });
    }
    return out.slice(0, MAX_HISTORY);
  } catch {
    return [];
  }
}

function saveSessionReports(entries: readonly StoredReportEntry[]): void {
  if (typeof sessionStorage === 'undefined') return;
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(entries.slice(0, MAX_HISTORY)));
  } catch {
    // Ignore quota errors in restricted private browsing
  }
}

export function upsertSessionReport(
  current: readonly StoredReportEntry[],
  report: CliReportV1,
  opts?: { readonly label?: string; readonly isSample?: boolean },
): { readonly entries: StoredReportEntry[]; readonly activeId: string } {
  const id = buildReportFingerprint(report);
  const label = opts?.label ?? makeDefaultLabel(report);
  const entry: StoredReportEntry = {
    id,
    label,
    isSample: opts?.isSample === true,
    report,
  };
  const filtered = current.filter((item) => item.id !== id);
  const next = [entry, ...filtered].slice(0, MAX_HISTORY);
  saveSessionReports(next);
  return { entries: next, activeId: id };
}
