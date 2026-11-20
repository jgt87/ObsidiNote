// The name a page shows on the map (operator, 2026-11-20: every meeting of a long-titled series showed
// the same "Daily Sync | A & B | Platform Pla…" pill, the date cut off). A meeting of a series shows a
// short series name and its day, which always fits; a series page its short name and "(series)".
// The page's full title stays in the hover card, the page window and what a screen reader hears.
import { formatDay } from '../meetings/meetingsModel'

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
  meetingAt?: string
  seriesPage?: boolean
}

/** The page's name on the map: "Daily Sync · Wed 18 Nov" for a meeting of a series (with its time
 *  when the title has it: a second meeting that day), "Daily Sync (series)" for a series page, else
 *  the title. */
export function pageMapLabel(p: LabelPage, now: Date = new Date()): string {
  const series = (p.series ?? '').trim()
  if (!series) return p.title
  const short = shortSeriesName(series)
  if (p.seriesPage) return `${short} (series)`
  const at = (p.meetingAt ?? '').trim()
  const day = /^\d{4}-\d{2}-\d{2}/.exec(at)?.[0]
  if (!day) return p.title
  const time = /T(\d{2}:\d{2})/.exec(at)?.[1]
  const withTime = time && p.title.includes(time) ? ` ${time}` : ''
  return `${short} · ${formatDay(day, now)}${withTime}`
}
