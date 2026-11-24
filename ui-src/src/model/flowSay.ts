// What a screen reader hears when the home view's result area changes. One owner: the two regions
// in HomeView.tsx, mounted empty and kept for the life of the view, so every change is announced
// once (audit 2026-11-24: the result, the "Written to OneNote" line and each notice were live
// regions mounted together with their message, which may not be announced at all). Pure.

import { resultHeading } from '../add/format'
import type { Flow } from '../hooks/useHomeFlow'

/** `status` is said politely, `alert` at once (errors only); '' says nothing. */
export interface Said {
  status: string
  alert: string
}

const polite = (status: string): Said => ({ status, alert: '' })
const urgent = (alert: string): Said => ({ status: '', alert })

/** Statuses where the Add did what was asked; any other one also says why. */
const DONE = new Set(['added', 'updated', 'unchanged', 'kept', 'needs-confirmation'])

function addSaid(flow: Extract<Flow, { kind: 'add' }>): Said {
  if (flow.busy) return polite('Working…')
  const r = flow.result
  const heading = resultHeading(r.status, r.page?.title ?? '')
  return polite(DONE.has(r.status) || !r.message ? heading : `${heading}. ${r.message}`)
}

function askSaid(flow: Extract<Flow, { kind: 'ask' }>): Said {
  const v = flow.view
  if (v.kind === 'progress') return polite(v.step === 3 ? 'Writing the answer from the same pages.' : 'Reading your wiki.')
  if (v.kind === 'error') return urgent(`Not answered: ${v.message}`)
  return polite(v.result.status === 'not-found' ? 'No answer found in your wiki.' : 'The answer is ready.')
}

/** One entry per kind of flow (a table, not a ladder). */
const SAY: { [K in Flow['kind']]: (flow: Extract<Flow, { kind: K }>) => Said } = {
  idle: () => polite(''),
  adding: () => polite('Adding: Copilot reads it, then the page is written to OneNote.'),
  notice: (f) => (f.error ? urgent(f.text) : polite(f.text)),
  add: addSaid,
  ask: askSaid,
}

export function flowSay(flow: Flow): Said {
  return (SAY[flow.kind] as (f: Flow) => Said)(flow)
}
