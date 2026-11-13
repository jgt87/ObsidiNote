import type { WaitingStatus } from './waiting'
import { waitingLabel, waitingNote } from './waiting'

/** An Add that waits for Copilot: what happened, what it means for the item, and "Check for the
 *  answer" (POST /api/add/fetch). The server's message says why for the check's outcomes. */
export function WaitingCard({ status, message, busy, onCheck }: { status: WaitingStatus; message: string; busy: boolean; onCheck?: () => void }) {
  const alert = status === 'mismatch' || status === 'invalid'
  return (
    <section className={alert ? 'add-card add-card--alert' : 'add-card'} role={alert ? 'alert' : 'status'}>
      <p className="add-label">{waitingLabel(status)}</p>
      {message && <p className="add-text">{message}</p>}
      <p className="add-muted">{waitingNote(status)}</p>
      {onCheck && (
        <div className="add-waiting__actions">
          <button type="button" className="btn btn--primary add-waiting__check" onClick={onCheck} disabled={busy} aria-busy={busy}>
            {busy ? 'Checking…' : 'Check for the answer'}
          </button>
        </div>
      )}
    </section>
  )
}
