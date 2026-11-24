// "Merge duplicates" from a series page's window: ask the server for the plan, show the confirm
// (MergeDialog), run it, then say what came of it. Like Archive it always asks first.

import { useCallback, useState, type ReactNode } from 'react'
import { MergeDialog } from './MergeDialog'
import { mergeResultLine, type MergeAnswer, type MergePlan } from './mergeModel'

type Run = (series: string, confirm: boolean) => Promise<MergeAnswer>

interface Pending {
  series: string
  plan: MergePlan
  busy: boolean
  error: string
}

const messageOf = (e: unknown) => (e instanceof Error && e.message ? e.message : 'ObsidiNote did not answer.')

export function useMergeFlow(run: Run | undefined) {
  const [pending, setPending] = useState<Pending | null>(null)
  const [note, setNote] = useState<string | null>(null)

  const start = useCallback(
    async (series: string) => {
      if (!run || !series) return
      setNote(null)
      try {
        const a = await run(series, false)
        if (a.kind === 'result') setNote(mergeResultLine(a.result))
        // Nothing to merge after all (the map was older than the vault): say so, ask nothing.
        else if (!a.plan.groups.length) setNote('No meeting of this series has a second copy.')
        else setPending({ series, plan: a.plan, busy: false, error: '' })
      } catch (e) {
        setNote(messageOf(e))
      }
    },
    [run],
  )

  const confirm = async () => {
    if (!run || !pending) return
    setPending({ ...pending, busy: true, error: '' })
    try {
      const a = await run(pending.series, true)
      if (a.kind === 'result') {
        setPending(null)
        setNote(mergeResultLine(a.result))
      } else setPending({ ...pending, plan: a.plan, busy: false })
    } catch (e) {
      setPending({ ...pending, busy: false, error: messageOf(e) })
    }
  }

  const dialog: ReactNode = pending && <MergeDialog plan={pending.plan} busy={pending.busy} error={pending.error} onConfirm={() => void confirm()} onCancel={() => setPending(null)} />
  // The region is there empty too, so the result put in it is announced.
  const notice: ReactNode = (
    <div className="live" role="status">
      {note && (
        <div className="kg-retire-note">
          <p>{note}</p>
          <button type="button" className="btn btn--sm btn--ghost" onClick={() => setNote(null)}>
            Dismiss
          </button>
        </div>
      )}
    </div>
  )

  return { start, dialog, notice }
}
