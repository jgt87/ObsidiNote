// A meeting series (operator, 2026-11-18: a daily meeting is one series of pages). Pure.

/** The comparable form of a series name: letters and digits in lower case, one space between words,
 *  as lib/Meetings.psm1 Get-MeetingSeriesKey ("Daily Sync | Team" and "Daily Sync Team" are one). */
export function seriesKey(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
}

type SeriesPageLike = { id?: string; kind: string; series?: string; archived?: boolean; seriesPage?: boolean }

/** A meeting of a series: a meeting page with a series that is not the series' own overview page. */
export const isSeriesMeeting = (p: SeriesPageLike) => p.kind === 'meeting' && !p.seriesPage && !!p.series

/** How many meeting pages of $series are in $pages (archived ones and the series page left out). */
export function seriesCount(pages: SeriesPageLike[], series: string): number {
  const k = seriesKey(series)
  if (!k) return 0
  return pages.filter((p) => isSeriesMeeting(p) && !p.archived && seriesKey(p.series ?? '') === k).length
}

/** The id of $series' overview page (2026-11-19), '' when there is none. */
export function seriesPageId(pages: SeriesPageLike[], series: string): string {
  const k = seriesKey(series)
  if (!k) return ''
  return pages.find((p) => p.seriesPage && !p.archived && p.series && seriesKey(p.series) === k)?.id ?? ''
}
