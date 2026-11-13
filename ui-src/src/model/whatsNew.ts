// What's new after an update (GET /api/whats-new, lib/WhatsNew.psm1): the notice's data and its
// memory. Session state only: whether it was dismissed lives in this module for this run of the
// window (never in storage), so it stays gone when the home view is opened again.

export type NoteKind = 'Added' | 'Changed' | 'Fixed'

export interface WhatsNewNote {
  kind: NoteKind
  text: string
}

export interface WhatsNew {
  version: string
  updated: boolean
  notes: WhatsNewNote[]
}

/** Lines shown before "Show all". */
export const COLLAPSED_COUNT = 3

const KINDS: readonly NoteKind[] = ['Added', 'Changed', 'Fixed']

/** The server's answer as WhatsNew; anything unexpected becomes "not updated". Windows PowerShell
 *  can hand a one-item list over as an object. */
export function normalizeWhatsNew(raw: unknown): WhatsNew {
  if (!raw || typeof raw !== 'object') return { version: '', updated: false, notes: [] }
  const r = raw as Record<string, unknown>
  const list = r.notes == null ? [] : Array.isArray(r.notes) ? r.notes : [r.notes]
  const notes = list.flatMap((n): WhatsNewNote[] => {
    if (!n || typeof n !== 'object') return []
    const { kind, text } = n as Record<string, unknown>
    if (typeof text !== 'string' || !text.trim() || !KINDS.includes(kind as NoteKind)) return []
    return [{ kind: kind as NoteKind, text: text.trim() }]
  })
  return { version: typeof r.version === 'string' ? r.version : '', updated: r.updated === true, notes }
}

/** True when the notice has something to say: an update to a known version. */
export function shouldShow(w: WhatsNew | null, dismissed: boolean): boolean {
  return !!w && w.updated && !!w.version && !dismissed
}

/** The lines to show: the first three until "Show all". */
export function visibleNotes(notes: WhatsNewNote[], expanded: boolean): WhatsNewNote[] {
  return expanded ? notes : notes.slice(0, COLLAPSED_COUNT)
}

export function hiddenCount(notes: WhatsNewNote[], expanded: boolean): number {
  return expanded ? 0 : Math.max(0, notes.length - COLLAPSED_COUNT)
}

// --- this run's memory ----------------------------------------------------------------------

let dismissed = false
let pending: Promise<WhatsNew> | null = null

export function isDismissed(): boolean {
  return dismissed
}

export function dismiss(): void {
  dismissed = true
}

/** Asks the server once per run; a failure counts as "nothing to show" (the notice is optional). */
export function loadWhatsNew(fetchImpl: typeof fetch = fetch): Promise<WhatsNew> {
  if (!pending) {
    pending = fetchImpl('/api/whats-new', { headers: { 'X-ObsidiNote': '1' }, cache: 'no-store' })
      .then((res) => (res.ok ? res.json() : null))
      .then(normalizeWhatsNew)
      .catch(() => normalizeWhatsNew(null))
  }
  return pending
}

/** Tests only: forget this run's answer and dismissal. */
export function resetWhatsNewForTests(): void {
  dismissed = false
  pending = null
}
