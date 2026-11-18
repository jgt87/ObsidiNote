// A meeting series (operator, 2026-11-18: a daily meeting is one series of pages). Pure.

/** The comparable form of a series name: letters and digits in lower case, one space between words,
 *  as lib/Meetings.psm1 Get-MeetingSeriesKey ("Daily Sync | Team" and "Daily Sync Team" are one). */
export function seriesKey(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
}

/** How many meeting pages of $series are in $pages (archived ones left out). */
export function seriesCount(pages: { kind: string; series?: string; archived?: boolean }[], series: string): number {
  const k = seriesKey(series)
  if (!k) return 0
  return pages.filter((p) => p.kind === 'meeting' && !p.archived && p.series && seriesKey(p.series) === k).length
}
