import { useEffect, useRef } from 'react'
import type { ConfirmRequest } from './types'

export type ReplaceDecision = 'replace' | 'keep'

/**
 * Asks before a hand-edited link summary is replaced (FEASIBILITY.md, Links: Updating a link's
 * summary). Escape or "Cancel" closes it without a decision; nothing is written until a choice.
 */
export function ConfirmReplaceDialog({
  request,
  open,
  busy = false,
  onDecide,
  onCancel,
}: {
  request: ConfirmRequest
  open: boolean
  busy?: boolean
  onDecide: (decision: ReplaceDecision) => void
  onCancel: () => void
}) {
  const ref = useRef<HTMLDialogElement>(null)

  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (open && !d.open) d.showModal()
    if (!open && d.open) d.close()
  }, [open])

  return (
    <dialog
      ref={ref}
      className="add-dialog"
      aria-labelledby="add-confirm-title"
      onCancel={(e) => {
        e.preventDefault()
        onCancel()
      }}
    >
      <div className="add-dialog__body">
        <h2 id="add-confirm-title" className="add-dialog__title">
          Replace your edited summary?
        </h2>
        <p className="add-dialog__text">{request.question}</p>
        <p className="add-muted">{request.detail}</p>
        <div className="add-dialog__compare">
          <div>
            <h3 className="add-label">Your text on the page</h3>
            <p className="add-dialog__quote">{request.editedText}</p>
          </div>
          <div>
            <h3 className="add-label">New summary</h3>
            <p className="add-dialog__quote">{request.proposed.summary}</p>
          </div>
        </div>
      </div>
      <div className="add-dialog__actions">
        <button type="button" className="btn btn--ghost" onClick={onCancel} disabled={busy}>
          Cancel
        </button>
        {request.options.includes('keep') && (
          <button type="button" className="btn" onClick={() => onDecide('keep')} disabled={busy}>
            Keep my text
          </button>
        )}
        {request.options.includes('replace') && (
          <button type="button" className="btn btn--primary" onClick={() => onDecide('replace')} disabled={busy}>
            Replace summary
          </button>
        )}
      </div>
    </dialog>
  )
}
