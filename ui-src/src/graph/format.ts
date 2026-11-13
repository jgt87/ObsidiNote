// Display helpers for the graph. Pure (tests: model.test.ts).

const dayMonth = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short' })
const dayMonthYear = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })

/** "today", "yesterday", "3 Nov", "3 Nov 2025"; '' when unreadable. */
export function formatDate(iso: string, now: Date = new Date()): string {
  const d = new Date(iso)
  if (!iso || Number.isNaN(d.getTime())) return ''
  const start = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
  const days = Math.round((start(now) - start(d)) / 86_400_000)
  if (days <= 0) return 'today'
  if (days === 1) return 'yesterday'
  return d.getFullYear() === now.getFullYear() ? dayMonth.format(d) : dayMonthYear.format(d)
}

export function plural(n: number, one: string, many = `${one}s`): string {
  return `${n} ${n === 1 ? one : many}`
}
