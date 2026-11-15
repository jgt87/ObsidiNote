import { Notice } from '../components/Notice'
import type { WaitingStatus } from './waiting'
import { waitingLabel, waitingNote } from './waiting'

/** An Add that waits for Copilot: what happened, what it means for the item, and "Check for the
 *  answer" (POST /api/add/fetch). The server's message says why for the check's outcomes. */
export function WaitingCard({ status, message, busy, onCheck, onDone }: { status: WaitingStatus; message: string; busy: boolean; onCheck?: () => void; onDone: () => void }) {
  const alert = status === 'mismatch' || status === 'invalid'
  // "waiting" is already the screen's heading: its label is not said a second time.
  const title = status === 'waiting' ? undefined : waitingLabel(status)
  return (
    <Notice
      error={alert}
      title={title}
      actions={
        <>
          {onCheck && (
            <button type="button" className="btn add-waiting__check" onClick={onCheck} disabled={busy} aria-busy={busy}>
              {busy ? 'Checking…' : 'Check for the answer'}
            </button>
          )}
          <button type="button" className="btn" onClick={onDone} disabled={busy}>
            Done
          </button>
        </>
      }
    >
      {message && <p>{message}</p>}
      <p className="add-muted">{waitingNote(status)}</p>
    </Notice>
  )
}
