// What ObsidiNote did, from the vault's Intake (GET /api/activity, lib/Activity.psm1; operator
// 2026-11-14): the home page's "Waiting for Copilot" list and the History view. Pure.

export type ActivityState = 'working' | 'waiting' | 'added' | 'updated' | 'failed' | 'gone'

export interface ActivityItem {
  inboxId: string
  /** The Intake item's title: the start of what was added. */
  title: string
  state: ActivityState
  kind: string
  requestKind: string
  updated: string
  /** When the wait for Copilot began (waiting items). */
  since: string
  reason: string
  /** The page it became (id, title, type), when it was filed and is still in the index. */
  filedAs: string
  filedTitle: string
  filedType: string
  canCheck: boolean
  canRemove: boolean
  canUndo: boolean
}

export interface ActivityList {
  items: ActivityItem[]
  canChange: boolean
}

const STATES: ActivityState[] = ['working', 'waiting', 'added', 'updated', 'failed', 'gone']
const str = (v: unknown) => (typeof v === 'string' ? v : '')

/** The server's answer as a list (Windows PowerShell may send one item as an object). */
export function normalizeActivity(raw: unknown): ActivityList {
  const o = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {}
  const list = Array.isArray(o.items) ? o.items : o.items && typeof o.items === 'object' ? [o.items] : []
  const items = list
    .filter((i): i is Record<string, unknown> => !!i && typeof i === 'object' && typeof (i as Record<string, unknown>).inboxId === 'string')
    .map((i) => ({
      inboxId: str(i.inboxId),
      title: str(i.title) || 'Untitled item',
      state: STATES.includes(i.state as ActivityState) ? (i.state as ActivityState) : 'working',
      kind: str(i.kind),
      requestKind: str(i.requestKind),
      updated: str(i.updated),
      since: str(i.since),
      reason: str(i.reason),
      filedAs: str(i.filedAs),
      filedTitle: str(i.filedTitle),
      filedType: str(i.filedType),
      canCheck: i.canCheck === true,
      canRemove: i.canRemove === true,
      canUndo: i.canUndo === true,
    }))
  return { items, canChange: o.canChange === true }
}

/** One word per state, for the list (with an icon or the row's text; never colour alone). */
export const STATE_LABEL: Record<ActivityState, string> = {
  working: 'Stopped',
  waiting: 'Waiting for Copilot',
  added: 'Added',
  updated: 'Updated',
  failed: 'Not added',
  gone: 'Undone',
}

/** What a row says after its state word (STATE_LABEL), without repeating it. */
export function stateLine(i: ActivityItem): string {
  switch (i.state) {
    case 'added':
      return i.filedTitle ? `Now the page ${i.filedTitle}.` : ''
    case 'updated':
      return i.filedTitle ? `The link page ${i.filedTitle}.` : ''
    case 'waiting':
      return 'Copilot is still answering. Check for the answer when it is done.'
    case 'failed':
      return i.reason ? `${i.reason}.` : ''
    case 'gone':
      return 'The page is no longer in your wiki.'
    case 'working':
      return 'It stopped before it was filed (ObsidiNote was closed, or Copilot did not answer).'
  }
}

/** "for 5 min", "for 2 h", "since 12 Nov": how long an item has waited. */
export function waitedFor(sinceIso: string, now: Date = new Date()): string {
  const t = new Date(sinceIso).getTime()
  if (!sinceIso || Number.isNaN(t)) return ''
  const min = Math.max(0, Math.round((now.getTime() - t) / 60_000))
  if (min < 1) return 'just now'
  if (min < 60) return `for ${min} min`
  const h = Math.round(min / 60)
  if (h < 48) return `for ${h} h`
  return `for ${Math.round(h / 24)} days`
}

/** The items the home page shows: waiting ones, oldest first (the longest wait on top). */
export function waitingItems(list: ActivityList): ActivityItem[] {
  return list.items.filter((i) => i.state === 'waiting').sort((a, b) => (a.since || a.updated).localeCompare(b.since || b.updated))
}
