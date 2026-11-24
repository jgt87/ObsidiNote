// The confirm of "Merge duplicates" (operator, 2026-11-19): like Archive it always asks first. It
// shows the server's plan: per meeting the page that stays and the copy that goes to the Archive.
// Same look as the Archive confirm (RetireDialog's kg-retire classes). Wording: mergeModel.ts.

import { BusyLabel } from '../components/BusyLabel'
import { useEffect, useRef } from 'react'
import { unavailable } from '../components/disabledGuard'
import { Icon } from '../components/icons'
import { useModal } from '../components/useModal'
import { mergeWording, type MergePlan } from './mergeModel'

interface Props {
  plan: MergePlan
  busy: boolean
  /** The last attempt's failure; the dialog stays open with it. */
  error: string
  onConfirm: () => void
  onCancel: () => void
}

export function MergeDialog({ plan, busy, error, onConfirm, onCancel }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  const goRef = useRef<HTMLButtonElement>(null)
  const w = mergeWording(plan)

  useModal(ref)
  useEffect(() => {
    // Restorable from the Archive, as Archive is: focus starts on the action.
    goRef.current?.focus()
  }, [])

  return (
    <dialog
      ref={ref}
      className="kg-retire"
      role="alertdialog"
      aria-modal="true"
      aria-labelledby="kg-merge-title"
      aria-describedby="kg-merge-text"
      onCancel={(e) => {
        e.preventDefault()
        if (!busy) onCancel()
      }}
    >
      <div className="kg-retire__body">
        <h2 id="kg-merge-title" className="kg-retire__title">
          {w.title}
        </h2>
        <div id="kg-merge-text">
          {w.lines.map((l) => (
            <p key={l} className="kg-retire__text">
              {l}
            </p>
          ))}
        </div>
        <ul className="kg-retire__list" aria-label="Meetings">
          {plan.groups.map((g) => (
            <li key={g.keep.id}>
              <span className="kg-retire__name">{g.keep.title}</span>
              <span className="kg-retire__where">{g.extra.map((x) => `copy “${x.title}” → Archive`).join(' · ')}</span>
            </li>
          ))}
        </ul>
        <div className="live" role="alert">
          {error && (
            <p className="kg-retire__error">
              <Icon name="warn" />
              <span>{error}</span>
            </p>
          )}
        </div>
      </div>
      <div className="kg-retire__actions">
        <button type="button" className="btn" onClick={onCancel} {...unavailable(busy)}>
          Cancel
        </button>
        <button ref={goRef} type="button" className="btn btn--primary" onClick={onConfirm} {...unavailable(busy)} aria-busy={busy}>
          <BusyLabel label={w.confirm} busyText={w.busy} />
        </button>
      </div>
    </dialog>
  )
}
