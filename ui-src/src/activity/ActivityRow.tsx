import { useState } from 'react'
import { checkAnswer, undoAdd } from '../add/api'
import { formatModified } from '../model/format'
import { removeIntakeItem } from './api'
import { STATE_LABEL, stateLine, waitedFor, type ActivityItem } from './activityModel'

type Ask = 'undo' | 'remove' | null

/** One thing ObsidiNote did, with the actions that fit it: Check for the answer (waiting), Remove
 *  (an item that never became a page), Undo (an Add's page), Open (the page it became). Undo and
 *  Remove send a page to OneNote's Deleted Pages, so they ask first (AGENTS.md: delete always asks). */
export function ActivityRow({ item, canChange, onChanged, onOpen }: { item: ActivityItem; canChange: boolean; onChanged: () => void; onOpen?: (pageId: string) => void }) {
  const [busy, setBusy] = useState(false)
  const [note, setNote] = useState('')
  const [ask, setAsk] = useState<Ask>(null)

  async function run(work: () => Promise<string>, refresh = true) {
    setBusy(true)
    setNote('')
    try {
      setNote(await work())
      if (refresh) onChanged()
    } catch (e) {
      setNote(e instanceof Error ? e.message : 'ObsidiNote did not answer.')
    } finally {
      setBusy(false)
      setAsk(null)
    }
  }

  const check = () =>
    run(async () => {
      const r = await checkAnswer(item.inboxId)
      if (r.status === 'added' || r.status === 'updated') return r.page ? `${r.status === 'added' ? 'Added' : 'Updated'}: ${r.page.title}` : 'Done.'
      return r.message || 'Still waiting. Try again in a few minutes.'
    })
  const remove = () => run(() => removeIntakeItem(item.inboxId))
  const undo = () =>
    run(async () => {
      const r = await undoAdd({ id: item.filedAs, pageId: '', targets: [] })
      return r.message || (r.status === 'undone' ? 'Undone.' : 'Undo did not work.')
    })

  const when = item.state === 'waiting' ? waitedFor(item.since) : formatModified(item.updated)
  return (
    <li className="act__row" data-state={item.state}>
      <div className="act__main">
        <span className="act__title">{item.title}</span>
        <span className="act__sub">
          <b className="act__state">{STATE_LABEL[item.state]}.</b> {stateLine(item)}
        </span>
        {note && (
          <span className="act__note" role="status">
            {note}
          </span>
        )}
      </div>
      <span className="act__when">{when}</span>
      <div className="act__actions">
        {ask ? (
          <>
            <span className="act__confirm">{ask === 'undo' ? 'Undo this page?' : 'Remove this item?'} It goes to OneNote's Deleted Pages.</span>
            <button type="button" className="btn btn--sm" disabled={busy} onClick={() => setAsk(null)}>
              Keep
            </button>
            <button type="button" className="btn btn--sm btn--danger" disabled={busy} aria-busy={busy} onClick={ask === 'undo' ? undo : remove}>
              {ask === 'undo' ? 'Undo' : 'Remove'}
            </button>
          </>
        ) : (
          <>
            {item.canCheck && canChange && (
              <button type="button" className="btn btn--sm btn--primary" disabled={busy} aria-busy={busy} onClick={check}>
                {busy ? 'Checking…' : 'Check for the answer'}
              </button>
            )}
            {item.filedAs && item.state !== 'gone' && onOpen && (
              <button type="button" className="btn btn--sm" onClick={() => onOpen(item.filedAs)}>
                Open
              </button>
            )}
            {item.canUndo && canChange && (
              <button type="button" className="btn btn--sm btn--ghost" disabled={busy} onClick={() => setAsk('undo')}>
                Undo
              </button>
            )}
            {item.canRemove && canChange && (
              <button type="button" className="btn btn--sm btn--ghost" disabled={busy} onClick={() => setAsk('remove')}>
                Remove
              </button>
            )}
          </>
        )}
      </div>
    </li>
  )
}
