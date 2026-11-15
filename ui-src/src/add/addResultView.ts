// Which parts of the Add result screen show for a result: one decision per part, derived from the
// status and the result's fields. Pure (tests: addResultView.test.ts); AddResult.tsx renders it.
import type { AddResult, AddStatus } from './types'
import { isWaitingStatus } from './waiting'

const UPDATE_STATUSES: readonly AddStatus[] = ['updated', 'unchanged', 'kept', 'could-not-update', 'needs-confirmation']
const WRITTEN_STATUSES: readonly AddStatus[] = ['added', 'updated', 'unchanged', 'kept']

export interface AddResultView {
  /** "Written to OneNote" under the heading. */
  written: boolean
  /** The item waits for Copilot: the waiting card, no action row. */
  waiting: boolean
  /** The action row under the heading (Done, Edit links, Undo...). */
  actions: boolean
  /** Edit links and Move in index (each also needs its handler). */
  editPlacement: boolean
  /** Update of a link page (also needs its handler). */
  updateLink: boolean
  /** Undo (also needs its handler). */
  undo: boolean
  failed: boolean
  askInstead: boolean
  /** "Filed under", the OneNote path and the chips. */
  placed: boolean
  /** "What you added" / "The link". */
  text: boolean
  /** The link's new summary under the link. */
  linkSummary: boolean
  /** Old vs new of a link update. */
  update: boolean
  couldNotUpdate: boolean
  /** The links card, and its title. */
  links: boolean
  linksTitle: string
  related: boolean
  confirm: boolean
}

export function addResultView(r: AddResult): AddResultView {
  const s = r.status
  const waiting = isWaitingStatus(s)
  const placed = !!r.page && s !== 'failed'
  const text = !!r.text && s !== 'ask-instead'
  return {
    written: WRITTEN_STATUSES.includes(s),
    waiting,
    actions: s !== 'ask-instead' && !waiting,
    editPlacement: s === 'added',
    updateLink: r.kind === 'link' && !!r.page && s !== 'needs-confirmation',
    undo: s === 'added' && !!r.undo,
    failed: s === 'failed',
    askInstead: s === 'ask-instead',
    placed,
    text,
    linkSummary: r.kind === 'link' && !!r.update?.new && s === 'added',
    update: UPDATE_STATUSES.includes(s) && !!r.update,
    couldNotUpdate: s === 'could-not-update',
    links: s === 'added' || (s === 'updated' && r.links.length > 0),
    linksTitle: s === 'updated' ? 'New links' : 'Links',
    related: r.related.length > 0 && s !== 'failed',
    confirm: s === 'needs-confirmation' && !!r.confirm,
  }
}
