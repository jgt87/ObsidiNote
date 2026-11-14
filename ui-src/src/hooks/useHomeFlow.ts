import { useCallback, useRef, useState } from 'react'
import { addItem, checkAnswer, undoAdd, updateLink } from '../add/api'
import type { ReplaceDecision } from '../add/ConfirmReplaceDialog'
import type { AddResult } from '../add/types'
import { ApiError, submit, type Intent, type Mode } from '../api'
import { answerPageSpec, askFollowUp, openQuestionSpec, ask } from '../ask/askApi'
import type { AskViewState } from '../ask/AskStates'
import type { AskResult } from '../ask/types'
import type { AskChoices } from '../components/AskOptions'
import type { Prefill } from '../components/Composer'
import { pageSpecToText } from '../model/handoff'

/** What the home view shows under the box. Session state in memory only (it is content). */
export type Flow =
  | { kind: 'idle' }
  | { kind: 'adding'; text: string }
  | { kind: 'add'; result: AddResult; busy: boolean }
  | { kind: 'ask'; view: AskViewState }
  | { kind: 'notice'; text: string; error: boolean }

function message(e: unknown): string {
  if (e instanceof ApiError || e instanceof Error) return e.message
  return 'ObsidiNote did not answer.'
}

/** Ask is what will run: the Ask mode, or Auto when the intent rules read a question. */
export function willAsk(mode: Mode, intent: Intent | null): boolean {
  return mode === 'ask' || (mode === 'auto' && intent === 'ask')
}

export function useHomeFlow(choices: AskChoices, onShowOnMap: (pageIds: string[]) => void) {
  const [flow, setFlow] = useState<Flow>({ kind: 'idle' })
  const [prefill, setPrefill] = useState<Prefill | null>(null)
  const [followUp, setFollowUp] = useState<{ conversationId: string; question: string } | null>(null)
  const [clearKey, setClearKey] = useState(0)
  const n = useRef(0)
  const busy = flow.kind === 'adding' || (flow.kind === 'ask' && flow.view.kind === 'progress') || (flow.kind === 'add' && flow.busy)

  const showAsk = (r: AskResult) => setFlow({ kind: 'ask', view: { kind: 'result', result: r } })
  const showAdd = (r: AddResult) => setFlow({ kind: 'add', result: r, busy: false })
  const fail = (question: string, e: unknown, asking: boolean) =>
    setFlow(asking ? { kind: 'ask', view: { kind: 'error', question, message: message(e) } } : { kind: 'notice', text: `Not sent: ${message(e)} Your text stays in the box.`, error: true })

  const addText = useCallback((text: string) => {
    setFlow({ kind: 'adding', text })
    addItem(text, 'add').then(showAdd, (e: unknown) => fail(text, e, false))
  }, [])

  const askNew = useCallback((question: string) => {
    setFlow({ kind: 'ask', view: { kind: 'progress', question, step: 1 } })
    ask(question, choices).then(showAsk, (e: unknown) => fail(question, e, true))
  }, [choices])

  // The box empties once the server has processed what was sent (any answer, also failed or
  // waiting: the text is then on the result and in the Intake). It keeps the text only when the
  // call itself failed, so nothing was sent (operator, 2026-11-13). "Ask it" / "Add anyway" reuse
  // the result's own text, never the box.
  const cleared = () => setClearKey((k) => k + 1)

  const send = useCallback((text: string, mode: Mode, intent: Intent | null) => {
    if (followUp && mode !== 'add') {
      const conv = followUp.conversationId
      setFollowUp(null)
      setFlow({ kind: 'ask', view: { kind: 'progress', question: text, step: 3 } })
      askFollowUp(conv, text).then((r) => { showAsk(r); cleared() }, (e: unknown) => fail(text, e, true))
      return
    }
    const asking = willAsk(mode, intent)
    setFlow(asking ? { kind: 'ask', view: { kind: 'progress', question: text, step: 1 } } : { kind: 'adding', text })
    submit({ text, mode, sources: choices.sources, includeArchived: choices.includeArchived }).then(
      (r) => { if (r.intent === 'ask') showAsk(r); else showAdd(r); cleared() },
      (e: unknown) => fail(text, e, asking),
    )
  }, [choices, followUp])

  const withAddBusy = (p: Promise<AddResult>) => {
    setFlow((f) => (f.kind === 'add' ? { ...f, busy: true } : f))
    p.then(showAdd, (e: unknown) => setFlow({ kind: 'notice', text: message(e), error: true }))
  }

  const add = {
    onDone: () => { setFlow({ kind: 'idle' }); setClearKey((k) => k + 1) },
    onUndo: (r: AddResult) => {
      if (!r.undo) return
      setFlow({ kind: 'add', result: r, busy: true })
      undoAdd(r.undo).then(
        (u) => setFlow({ kind: 'notice', text: u.status === 'undone' ? u.message : `Undo did not work: ${u.message}`, error: u.status !== 'undone' }),
        (e: unknown) => setFlow({ kind: 'notice', text: `Undo did not work: ${message(e)}`, error: true }),
      )
    },
    onUpdateLink: (r: AddResult) => { if (r.page) withAddBusy(updateLink(r.page.id)) },
    // An error of the call itself (server gone, 409 not waiting) keeps the waiting result on screen.
    onCheckAnswer: (r: AddResult) => {
      if (!r.inboxId) return
      setFlow({ kind: 'add', result: r, busy: true })
      checkAnswer(r.inboxId).then(showAdd, (e: unknown) =>
        setFlow({ kind: 'add', result: { ...r, status: 'still-waiting', message: `The check did not work: ${message(e)}` }, busy: false }),
      )
    },
    onDecide: (r: AddResult, d: ReplaceDecision) => { if (r.confirm) withAddBusy(updateLink(r.confirm.id, d, r.confirm.proposed)) },
    onAsk: (r: AddResult) => askNew(r.text),
    onAddAnyway: (r: AddResult) => addText(r.text),
  }

  const askActions = (r: AskResult) => ({
    onFollowUp: () => { setFollowUp({ conversationId: r.conversationId, question: r.question }); setPrefill({ text: '', mode: 'ask', key: ++n.current }) },
    onSavePage: () => { setFlow({ kind: 'adding', text: r.question }); answerPageSpec(r.conversationId).then((s) => addText(pageSpecToText(s)), (e: unknown) => fail(r.question, e, false)) },
    onShowOnMap: () => onShowOnMap(r.sources.filter((s) => !s.readOnly).map((s) => s.id)),
    onShowPage: (id: string) => onShowOnMap([id]),
    onUpdateLink: (id: string) => withAddBusy(updateLink(id)),
    onSaveOpenQuestion: () => { setFlow({ kind: 'adding', text: r.question }); openQuestionSpec(r.question, r.conversationId).then((s) => addText(pageSpecToText(s)), (e: unknown) => fail(r.question, e, false)) },
    onAskAsNew: () => askNew(r.question),
  })

  const askAbout = useCallback((text: string) => { setFollowUp(null); setPrefill({ text, mode: 'ask', key: ++n.current }) }, [])

  return { flow, busy, send, prefill, followUp, cancelFollowUp: () => setFollowUp(null), clearKey, add, askActions, askAbout }
}
