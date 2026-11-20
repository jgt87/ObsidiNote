// "Merge duplicates" of a meeting series in the window (operator, 2026-11-19): the server's plan and
// result (lib/Ingest.psm1 Get-SeriesMergePlan / Invoke-SeriesMerge, POST /api/series/merge) and the
// confirm dialog's wording. Like Archive it always asks first. Pure (tests: mergeModel.test.ts).

import { asList } from '../api'

export interface MergeTitle {
  id: string
  title: string
}

/** The copies of one meeting: the page that stays and the copies that go to the Archive. */
export interface MergeGroup {
  keep: MergeTitle
  extra: MergeTitle[]
}

export interface MergePlan {
  series: string
  groups: MergeGroup[]
}

export interface MergeResult {
  status: 'merged' | 'partial' | 'nothing'
  message: string
  merged: number
  warnings: string[]
}

export type MergeAnswer = { kind: 'plan'; plan: MergePlan } | { kind: 'result'; result: MergeResult }

const text = (v: unknown) => (typeof v === 'string' ? v : '')

function parseTitle(v: unknown): MergeTitle {
  const o = (v && typeof v === 'object' ? v : {}) as Record<string, unknown>
  return { id: text(o.id), title: text(o.title) }
}

/** The 409 answer's plan, read defensively (PS 5.1 sends a list of one as the item). */
export function parseMergePlan(v: unknown): MergePlan {
  const o = (v && typeof v === 'object' ? v : {}) as Record<string, unknown>
  const groups = asList(o.groups as unknown[] | undefined)
    .map((g) => {
      const x = (g && typeof g === 'object' ? g : {}) as Record<string, unknown>
      return { keep: parseTitle(x.keep), extra: asList(x.extra as unknown[] | undefined).map(parseTitle).filter((e) => e.id) }
    })
    .filter((g) => g.keep.id && g.extra.length)
  return { series: text(o.series), groups }
}

export function parseMergeResult(v: Record<string, unknown>): MergeResult {
  const status = v.status === 'partial' || v.status === 'nothing' ? v.status : 'merged'
  return { status, message: text(v.message), merged: typeof v.merged === 'number' ? v.merged : 0, warnings: asList(v.warnings as unknown[] | undefined).filter((w): w is string => typeof w === 'string') }
}

/** The confirm's title, its sentences and its buttons. */
export function mergeWording(plan: MergePlan): { title: string; lines: string[]; confirm: string; busy: string } {
  const copies = plan.groups.reduce((n, g) => n + g.extra.length, 0)
  const meetings = plan.groups.length === 1 ? 'one meeting' : `${plan.groups.length} meetings`
  return {
    title: copies === 1 ? 'Merge the second copy of a meeting?' : `Merge ${copies} copies of ${meetings}?`,
    lines: [
      'Each meeting below keeps one page. The notes and links of its other copy are added to that page, and links to the copy are moved to it.',
      'The copy goes to the Archive; Restore brings it back. Your own notes on it stay with the copy.',
    ],
    confirm: copies === 1 ? 'Merge and archive the copy' : 'Merge and archive the copies',
    busy: 'Merging…',
  }
}

/** What came of it, in one line for the window. */
export function mergeResultLine(r: MergeResult): string {
  if (r.status === 'nothing') return r.message || 'No meeting of this series has a second copy.'
  const head = r.merged === 1 ? 'Merged one copy of a meeting; it is in the Archive.' : `Merged ${r.merged} copies of meetings; they are in the Archive.`
  const warn = r.warnings.length ? ` ${r.warnings.join(' ')}` : ''
  return r.status === 'partial' ? `${head} Some copies could not be merged:${warn}` : head + warn
}
