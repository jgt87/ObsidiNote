// The name a page shows on the map. A meeting series is one dot (seriesFold.ts; operator,
// 2026-11-20: "I want the series to show as one dot", not meetings told apart by their date): that
// dot shows a short series name and how many meetings it stands for. Every other page shows its title.
// The page's full title stays in the hover card, the page window and what a screen reader hears.

/** The most of a series name to show on the map before "…". */
export const SERIES_LABEL_MAX = 28

/** A series name short enough for a map label: the first part of a Teams title split by " | "
 *  ("Daily Sync | A & B | Governance" -> "Daily Sync"), cut with "…" past `max` letters. */
export function shortSeriesName(series: string, max: number = SERIES_LABEL_MAX): string {
  const full = series.trim().replace(/\s+/g, ' ')
  const first = full.split(/\s+\|\s+/)[0].trim()
  const name = first.length >= 3 ? first : full
  return name.length > max ? name.slice(0, max - 1).trimEnd() + '…' : name
}

export interface LabelPage {
  title: string
  series?: string
  seriesCount?: number
}

const DATES = /\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b/g

/** The page's name on the map: "Daily Sync · 6 meetings" for a series' one dot, else the title. */
export function pageMapLabel(p: LabelPage): string {
  if (!p.seriesCount) return p.title
  // A meeting without a series (counted by its title): the title without its date and the dot.
  const series = (p.series ?? '').trim() || p.title.replace(DATES, ' ').replace(/[\s\u00b7|:,-]+$/, '').replace(/\s+/g, ' ').trim() || p.title
  return `${shortSeriesName(series)} · ${p.seriesCount} ${p.seriesCount === 1 ? 'meeting' : 'meetings'}`
}
