// Dates and counts for display. Pure (tests: format.test.ts).

const time = new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
const weekday = new Intl.DateTimeFormat('en-GB', { weekday: 'short' })
const dayMonth = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short' })
const dayMonthYear = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })

function startOfDay(d: Date): number {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

/** "today 14:34", "yesterday", "Mon" (this week), "3 Nov", "3 Nov 2025"; '' when unreadable. */
export function formatModified(iso: string, now: Date = new Date()): string {
  const d = new Date(iso)
  if (!iso || Number.isNaN(d.getTime())) return ''
  const days = Math.round((startOfDay(now) - startOfDay(d)) / 86_400_000)
  if (days <= 0) return `today ${time.format(d)}`
  if (days === 1) return 'yesterday'
  if (days < 7) return weekday.format(d)
  return d.getFullYear() === now.getFullYear() ? dayMonth.format(d) : dayMonthYear.format(d)
}

export function plural(n: number, one: string, many = `${one}s`): string {
  return `${n} ${n === 1 ? one : many}`
}
