// One dot per meeting series on the map (operator, 2026-11-20: "I want a series to show up as one dot
// instead of each meeting in a series to have its own dot"). The map draws a folded copy of the
// model: the meetings of a series are left out and their links go to the series' dot. That dot is the
// series page ("‹series› (series)"); a series without one (or whose page is archived) keeps its
// newest meeting as the dot. The List, the search, the page window and the Journal keep every
// meeting: the series page links to each of them.
import type { GraphEdge, GraphModel, GraphPage } from './model'

export interface SeriesFold {
  /** The model the map draws: one page per series. */
  model: GraphModel
  /** Every folded meeting's id -> the id of its series' dot. */
  dotOf: Map<string, string>
}

// The server's key (lib/Meetings.psm1 Get-MeetingSeriesKey) when it sent one; else the same rule
// here: dates out, letters and digits only, lower case.
const DATES = /\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b/g
export const seriesKeyOf = (p: GraphPage): string =>
  (p.seriesKey ?? '').trim() || (p.series ?? '').replace(DATES, ' ').replace(/[^\p{L}\p{Nd}]+/gu, ' ').trim().toLowerCase()

/** The map's model with each series as one page; `seriesCount` on that page is its meeting count
 *  (the map names the dot by it, pageLabel.ts). Pure. */
export function foldSeries(model: GraphModel): SeriesFold {
  const meetings = new Map<string, GraphPage[]>()
  const seriesPages = new Map<string, GraphPage>()
  for (const p of model.pages) {
    const key = seriesKeyOf(p)
    if (!key) continue
    if (p.seriesPage) {
      if (!seriesPages.has(key) || (seriesPages.get(key)!.archived && !p.archived)) seriesPages.set(key, p)
    } else {
      const list = meetings.get(key) ?? []
      list.push(p)
      meetings.set(key, list)
    }
  }
  const dotOf = new Map<string, string>()
  const counts = new Map<string, number>()
  for (const [key, list] of meetings) {
    const page = seriesPages.get(key)
    const live = list.filter((m) => !m.archived)
    const when = (m: GraphPage) => m.meetingAt || m.created || ''
    const newest = [...(live.length ? live : list)].sort((a, b) => (when(a) < when(b) ? 1 : when(a) > when(b) ? -1 : 0))[0]
    // A series with one meeting is a dot too: named by its series, never by the meeting's date.
    const dot = page && !page.archived ? page : newest
    for (const m of list) if (m.id !== dot.id) dotOf.set(m.id, dot.id)
    counts.set(dot.id, list.length)
  }
  if (!counts.size) return { model, dotOf }
  const pages = model.pages.filter((p) => !dotOf.has(p.id)).map((p) => (counts.has(p.id) ? { ...p, seriesCount: counts.get(p.id)! } : p))
  // Links of a folded meeting go to its series' dot; within one series they fall away; two links
  // between the same pages become one, the strongest.
  const edges = new Map<string, GraphEdge>()
  for (const e of model.edges) {
    const from = dotOf.get(e.from) ?? e.from
    const to = dotOf.get(e.to) ?? e.to
    if (from === to) continue
    const key = `${e.kind}:${from}>${to}`
    const had = edges.get(key)
    if (!had || had.strength < e.strength) edges.set(key, { ...e, from, to })
  }
  return { model: { ...model, pages, edges: [...edges.values()] }, dotOf }
}

/** Ids on the full model as ids on the folded map: a folded meeting becomes its series' dot. */
export function foldIds(ids: Iterable<string>, dotOf: Map<string, string>): string[] {
  const out = new Set<string>()
  for (const id of ids) out.add(dotOf.get(id) ?? id)
  return [...out]
}
