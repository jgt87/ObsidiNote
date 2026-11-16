// The vault's settings, kept in OneNote by the server (lib/VaultSettings.psm1, operator 2026-11-14).
// The defaults are pinned to the server's table by tests/fixtures/vault-settings.json: change all
// three together. The theme is not one of them: it stays per PC (model/preferences.ts). Pure.

export type GraphView = 'topics' | 'sources'

export interface VaultSettings {
  /** Company addresses that count as internal links (host, *.domain or .domain). */
  internalHosts: string[]
  /** The knowledge graph's areas when it opens. */
  graphView: GraphView
  /** "Labels: hubs only" when the graph opens. */
  labelsHubsOnly: boolean
  /** How many related pages Add links a new page to. */
  relatedCount: number
  /** After how many days a cited link page offers Update in Ask. */
  linkStaleDays: number
  /** Ask's "Include archived pages" when the window opens. */
  askIncludeArchived: boolean
  /** The graph's Filter "Show archived" when it opens. */
  graphShowArchived: boolean
  /** Pages Ask may read for one answer (more pages: each read more briefly). */
  askMaxPages: number
}

export const SETTING_DEFAULTS: VaultSettings = {
  internalHosts: [],
  graphView: 'topics',
  labelsHubsOnly: false,
  relatedCount: 3,
  linkStaleDays: 90,
  askIncludeArchived: false,
  graphShowArchived: false,
  askMaxPages: 20,
}

/** The whole-number settings and their ranges (the server's table; refused outside them). */
export const NUMBER_RANGES = { relatedCount: { min: 1, max: 10 }, linkStaleDays: { min: 7, max: 730 }, askMaxPages: { min: 1, max: 50 } } as const
export type NumberKey = keyof typeof NUMBER_RANGES

const HOST = /^(\*\.|\.)?[a-z0-9-]+(\.[a-z0-9-]+)*$/i

function num(v: unknown, key: NumberKey): number {
  const r = NUMBER_RANGES[key]
  return typeof v === 'number' && Number.isInteger(v) && v >= r.min && v <= r.max ? v : SETTING_DEFAULTS[key]
}

/** Whatever the server sent, as valid settings (a wrong value falls back to its default). */
export function normalizeSettings(raw: unknown): VaultSettings {
  const o = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {}
  const hosts = Array.isArray(o.internalHosts) ? o.internalHosts : o.internalHosts == null ? [] : [o.internalHosts]
  return {
    internalHosts: hosts.filter((h): h is string => typeof h === 'string' && HOST.test(h)),
    graphView: o.graphView === 'sources' ? 'sources' : 'topics',
    labelsHubsOnly: o.labelsHubsOnly === true,
    relatedCount: num(o.relatedCount, 'relatedCount'),
    linkStaleDays: num(o.linkStaleDays, 'linkStaleDays'),
    askIncludeArchived: o.askIncludeArchived === true,
    graphShowArchived: o.graphShowArchived === true,
    askMaxPages: num(o.askMaxPages, 'askMaxPages'),
  }
}

/** A number field's text as a valid value, or null (empty, not whole, out of range). */
export function parseNumber(text: string, key: NumberKey): number | null {
  const t = text.trim()
  if (!/^\d+$/.test(t)) return null
  const n = Number(t)
  const r = NUMBER_RANGES[key]
  return n >= r.min && n <= r.max ? n : null
}

/** A number field's text when the field is left: a whole number outside the range moves to the
 *  nearest end (12 -> 10), so the box never keeps a value the setting cannot take; text without a
 *  whole number goes back to `fallback`. */
export function settleNumber(text: string, key: NumberKey, fallback: number): number {
  const t = text.trim()
  if (!/^\d+$/.test(t)) return fallback
  const r = NUMBER_RANGES[key]
  return Math.min(r.max, Math.max(r.min, Number(t)))
}

/** The keys whose value differs between two settings (what Save sends, one call each). */
export function changedKeys(before: VaultSettings, after: VaultSettings): (keyof VaultSettings)[] {
  return (Object.keys(SETTING_DEFAULTS) as (keyof VaultSettings)[]).filter((k) => JSON.stringify(before[k]) !== JSON.stringify(after[k]))
}

/** The text of the "Company addresses" field (one per line, commas too) as host rules, plus the
 *  entries that are not a host. Lower case, no duplicates, scheme and path dropped. */
export function parseHosts(text: string): { hosts: string[]; bad: string[] } {
  const hosts = new Set<string>()
  const bad: string[] = []
  for (const part of text.split(/[\n,;]+/)) {
    let h = part.trim().toLowerCase()
    if (!h) continue
    h = h.replace(/^[a-z]+:\/\//, '').replace(/[/?#].*$/, '')
    if (!HOST.test(h) || h.length > 253) bad.push(part.trim())
    else hosts.add(h)
  }
  return { hosts: [...hosts], bad }
}
