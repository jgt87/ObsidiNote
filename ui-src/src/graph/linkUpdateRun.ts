// "Update summaries" for many link pages at once (FEASIBILITY.md, Links: "Update stale links" and
// "Update all" for a site): the window runs the normal Update (POST /api/link/update) one page at a
// time, so Copilot gets one request at a time, and can be stopped between pages. Pure parts here
// (tests: linkUpdateRun.test.ts); the loop is in LinkUpdateBar.tsx.

import type { AddStatus } from '../add/types'
import type { GraphPage } from './model'

/** A link page: it has an address that Update can read again. */
export function isLinkPage(p: GraphPage): boolean {
  return !!p.url || p.kind.startsWith('link-')
}

/** The cut-off for "Link summaries older than N days": an ISO time, N days before `now`. */
export function staleCutoff(days: number, now: number): string {
  return new Date(now - days * 86400000).toISOString()
}

/** A link page whose summary was read before the cut-off, or never (no date). */
export function isStale(p: GraphPage, cutoff: string): boolean {
  if (!isLinkPage(p)) return false
  const at = p.summarizedAt ?? ''
  return !at || at < cutoff
}

export type RunOutcome = 'updated' | 'unchanged' | 'decide' | 'waiting' | 'failed'

/** What one Update result means for the run. */
export function outcomeOf(status: AddStatus): RunOutcome {
  switch (status) {
    case 'updated':
    case 'kept':
      return 'updated'
    case 'unchanged':
      return 'unchanged'
    case 'needs-confirmation':
      return 'decide'
    case 'waiting':
      return 'waiting'
    default:
      return 'failed'
  }
}

export interface RunState {
  /** Page ids in the order they are updated. */
  ids: string[]
  /** Outcome per page done so far. */
  done: Record<string, RunOutcome>
  /** The page being updated now, '' when the run is over. */
  current: string
  stopped: boolean
}

export function startRun(ids: string[]): RunState {
  return { ids: [...new Set(ids)], done: {}, current: ids[0] ?? '', stopped: false }
}

/** After one page: record it and move on (or end when stopped or at the last page). */
export function advance(s: RunState, id: string, outcome: RunOutcome): RunState {
  const done = { ...s.done, [id]: outcome }
  const next = s.stopped ? '' : s.ids.find((x) => !(x in done)) ?? ''
  return { ...s, done, current: next }
}

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`

/** The progress line while running, the summary once over. */
export function runLine(s: RunState, title: (id: string) => string): string {
  const n = Object.keys(s.done).length
  if (s.current) return `Updating ${n + 1} of ${s.ids.length}: ${title(s.current)}${s.stopped ? ' (stops after this one)' : ''}`
  const count = (o: RunOutcome) => Object.values(s.done).filter((x) => x === o).length
  const parts = [
    count('updated') && `${count('updated')} updated`,
    count('unchanged') && `${count('unchanged')} unchanged`,
    count('decide') && `${plural(count('decide'), 'needs', 'need')} your decision (open the page and press Update)`,
    count('waiting') && `${plural(count('waiting'), 'waits', 'wait')} for Copilot (see Waiting for Copilot on the home page)`,
    count('failed') && `${count('failed')} could not be updated`,
  ].filter(Boolean)
  const left = s.ids.length - n
  return `${s.stopped && left ? `Stopped after ${plural(n, 'page', 'pages')}. ` : ''}${parts.join(', ') || 'Nothing was updated'}.`
}
