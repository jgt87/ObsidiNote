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

type CopyLike = SeriesPageLike & { meetingAt?: string }

const dayOf = (at: string) => /^\d{4}-\d{2}-\d{2}/.exec(at)?.[0] ?? ''
const timeOf = (at: string) => /T(\d{2}:\d{2})/.exec(at)?.[1] ?? ''

/** Whether two starts are the same meeting: the same day, and the same time when both have one
 *  (lib/Meetings.psm1 Test-MeetingSameOccurrence: change both together). */
export function sameOccurrence(a: string, b: string): boolean {
  const da = dayOf(a)
  if (!da || da !== dayOf(b)) return false
  const ta = timeOf(a)
  const tb = timeOf(b)
  return !ta || !tb || ta === tb
}

/** How many meeting pages of $series are a second copy of a meeting (2026-11-19, "Merge duplicates"):
 *  pages of one occurrence beyond the first, archived ones and the series page left out. A copy with a
 *  start time is taken first, as the server keeps it (lib/Ingest.psm1 Get-SeriesMergePlan). */
export function seriesCopies(pages: CopyLike[], series: string): number {
  const k = seriesKey(series)
  if (!k) return 0
  const live = pages
    .filter((p) => isSeriesMeeting(p) && !p.archived && seriesKey(p.series ?? '') === k && dayOf(p.meetingAt ?? ''))
    .sort((a, b) => Number(Boolean(timeOf(b.meetingAt ?? ''))) - Number(Boolean(timeOf(a.meetingAt ?? ''))))
  const used = new Set<CopyLike>()
  let copies = 0
  for (const keep of live) {
    if (used.has(keep)) continue
    used.add(keep)
    for (const o of live) {
      if (used.has(o) || !sameOccurrence(keep.meetingAt ?? '', o.meetingAt ?? '')) continue
      used.add(o)
      copies++
    }
  }
  return copies
}

/** The id of $series' overview page (2026-11-19), '' when there is none. */
export function seriesPageId(pages: SeriesPageLike[], series: string): string {
  const k = seriesKey(series)
  if (!k) return ''
  return pages.find((p) => p.seriesPage && !p.archived && p.series && seriesKey(p.series) === k)?.id ?? ''
}
