// Archive, Restore and Delete from the page window and the List: ask the server for the plan, show
// the confirm (RetireDialog), run it, then show what came of it (with Undo after an archive).
// Restore asks nothing: it is the undo of an archive.

import { useCallback, useRef, useState, type ReactNode } from 'react'
import type { RetireAnswer } from './graphApi'
import { RetireDialog } from './RetireDialog'
import { resultLines, type AskingAction, type RetireAction, type RetirePlan, type RetireResult } from './retireModel'

type Run = (action: RetireAction, ids: string[], confirm: boolean) => Promise<RetireAnswer>

interface Pending {
  action: AskingAction
  plan: RetirePlan
  busy: boolean
  error: string
}

interface Note {
  lines: string[]
  /** Pages an Undo would restore (after an archive). */
  undo: string[]
  busy: boolean
}

const messageOf = (e: unknown) => (e instanceof Error && e.message ? e.message : 'ObsidiNote did not answer.')

/** `onDone` hears every result (the caller closes a page window whose page was deleted). */
export function useRetireFlow(run: Run | undefined, onDone?: (r: RetireResult) => void) {
  const [pending, setPending] = useState<Pending | null>(null)
  const [note, setNote] = useState<Note | null>(null)
  const doneRef = useRef(onDone)
  doneRef.current = onDone

  const finish = useCallback((r: RetireResult) => {
    setNote({ lines: resultLines(r), undo: r.action === 'archive' ? r.done.map((d) => d.id) : [], busy: false })
    doneRef.current?.(r)
  }, [])

  const start = useCallback(
    async (action: RetireAction, ids: string[]) => {
      if (!run || !ids.length) return
      setNote(null)
      try {
        const a = await run(action, ids, action === 'restore')
        if (a.kind === 'result') finish(a.result)
        else if (action === 'restore') return
        // A plan with nothing that can be done: say why instead of asking an empty question.
        else if (!a.plan.pages.length) setNote({ lines: [`Nothing was changed: ${a.plan.refused[0]?.reason ?? 'there is nothing to change.'}`], undo: [], busy: false })
        else setPending({ action, plan: a.plan, busy: false, error: '' })
      } catch (e) {
        setNote({ lines: [messageOf(e)], undo: [], busy: false })
      }
    },
    [run, finish],
  )

  const confirm = async () => {
    if (!run || !pending) return
    setPending({ ...pending, busy: true, error: '' })
    try {
      const a = await run(pending.action, pending.plan.pages.map((p) => p.id), true)
      if (a.kind === 'result') {
        setPending(null)
        finish(a.result)
      } else setPending({ ...pending, plan: a.plan, busy: false })
    } catch (e) {
      setPending({ ...pending, busy: false, error: messageOf(e) })
    }
  }

  const undo = async () => {
    if (!run || !note?.undo.length) return
    setNote({ ...note, busy: true })
    try {
      const a = await run('restore', note.undo, true)
      if (a.kind === 'result') finish(a.result)
    } catch (e) {
      setNote({ lines: [messageOf(e)], undo: note.undo, busy: false })
    }
  }

  const dialog: ReactNode = pending && (
    <RetireDialog action={pending.action} plan={pending.plan} busy={pending.busy} error={pending.error} onConfirm={() => void confirm()} onCancel={() => setPending(null)} />
  )
  const notice: ReactNode = note && (
    <div className="kg-retire-note" role="status">
      <p>{note.lines.join(' ')}</p>
      {note.undo.length > 0 && (
        <button type="button" className="btn btn--sm" onClick={() => void undo()} disabled={note.busy} aria-busy={note.busy}>
          Undo
        </button>
      )}
      <button type="button" className="btn btn--sm btn--ghost" onClick={() => setNote(null)}>
        Dismiss
      </button>
    </div>
  )

  return { start, dialog, notice, clearNote: () => setNote(null) }
}
