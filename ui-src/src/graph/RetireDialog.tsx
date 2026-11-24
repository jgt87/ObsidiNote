// The confirm of Archive and Delete (FEASIBILITY.md "Archive and delete": always asked, for one page
// or many, no "don't ask again"). It shows the server's plan: the pages, where they go, how many
// links point at them, and the pages that are left out with the reason. Wording: retireModel.ts.

import { BusyLabel } from '../components/BusyLabel'
import { useEffect, useRef } from 'react'
import { unavailable } from '../components/disabledGuard'
import { Icon } from '../components/icons'
import { useModal } from '../components/useModal'
import { confirmWording, refusedLines, sectionLabel, type AskingAction, type RetirePlan } from './retireModel'

interface Props {
  action: AskingAction
  plan: RetirePlan
  busy: boolean
  /** The last attempt's failure; the dialog stays open with it. */
  error: string
  onConfirm: () => void
  onCancel: () => void
}

export function RetireDialog({ action, plan, busy, error, onConfirm, onCancel }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  const cancelRef = useRef<HTMLButtonElement>(null)
  const goRef = useRef<HTMLButtonElement>(null)
  const w = confirmWording(action, plan)
  const left = refusedLines(plan)
  const many = plan.pages.length > 1

  // Shown as a modal; closed with the focus back on the button that opened it when it is answered.
  useModal(ref)
  useEffect(() => {
    // Delete cannot be undone here: focus starts on Cancel. Archive can: on the action.
    ;(action === 'delete' ? cancelRef : goRef).current?.focus()
  }, [action])

  return (
    <dialog
      ref={ref}
      className="kg-retire"
      role="alertdialog"
      aria-modal="true"
      aria-labelledby="kg-retire-title"
      aria-describedby="kg-retire-text"
      onCancel={(e) => {
        e.preventDefault()
        if (!busy) onCancel()
      }}
    >
      <div className="kg-retire__body">
        <h2 id="kg-retire-title" className="kg-retire__title">
          {w.title}
        </h2>
        <div id="kg-retire-text">
          {w.lines.map((l) => (
            <p key={l} className="kg-retire__text">
              {l}
            </p>
          ))}
        </div>
        {many && (
          <ul className="kg-retire__list" aria-label="Pages">
            {plan.pages.map((p) => (
              <li key={p.id}>
                <span className="kg-retire__name">{p.title}</span>
                <span className="kg-retire__where">
                  {sectionLabel(p.section)}
                  {p.to ? ` → ${sectionLabel(p.to)}` : ''}
                  {p.inbound ? ` · ${p.inbound === 1 ? '1 link here' : `${p.inbound} links here`}` : ''}
                </span>
              </li>
            ))}
          </ul>
        )}
        {left.length > 0 && (
          <div className="kg-retire__left">
            {left.map((l) => (
              <p key={l}>{l}</p>
            ))}
          </div>
        )}
        {/* Mounted empty and kept, so a failure is announced; the icon says it is one (not the fill alone). */}
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
        <button ref={cancelRef} type="button" className="btn" onClick={onCancel} {...unavailable(busy)}>
          Cancel
        </button>
        <button
          ref={goRef}
          type="button"
          className={action === 'delete' ? 'btn kg-retire__go--delete' : 'btn btn--primary'}
          onClick={onConfirm}
          {...unavailable(busy)}
          aria-busy={busy}
        >
          <BusyLabel label={w.confirm} busyText={w.busy} />
        </button>
      </div>
    </dialog>
  )
}
