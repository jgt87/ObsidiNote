import { useEffect, useRef, useState } from 'react'
import { setUpVault, type NewVaultResult } from '../api'
import './NewVaultDialog.css'

/** "Set up this notebook": the confirm step before ObsidiNote writes its sections
 *  into an empty notebook it does not own yet (user, 2026-11-13). Nothing is written until the
 *  person presses "Set it up". */
export function SetUpVaultDialog({ id, name, onClose, onDone }: { id: string; name: string; onClose: () => void; onDone: (r: NewVaultResult) => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  const close = useRef(onClose)
  close.current = onClose
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    const d = ref.current
    if (d && !d.open) d.showModal()
  }, [])

  async function go() {
    if (busy) return
    setBusy(true)
    setError('')
    try {
      onDone(await setUpVault(id, true))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'ObsidiNote did not answer.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <dialog ref={ref} className="nv" aria-labelledby="su-title" aria-describedby="su-desc" onCancel={(e) => { e.preventDefault(); if (!busy) close.current() }}>
      <div className="nv__body">
        <h2 id="su-title" className="nv__title">
          Set up ObsidiNote in {name}?
        </h2>
        <p id="su-desc" className="nv__text">
          This notebook is empty. ObsidiNote adds its sections to it (00 Index, 01 Inbox and one section per page type) and makes it your active vault. You can undo it in OneNote by deleting those sections.
        </p>
        {error && (
          <p className="nv__error" role="alert">
            {error}
          </p>
        )}
      </div>
      <div className="nv__actions">
        <button type="button" className="btn btn--ghost" onClick={() => close.current()} disabled={busy}>
          Cancel
        </button>
        <button type="button" className="btn btn--primary" onClick={() => void go()} disabled={busy} aria-busy={busy} autoFocus>
          {busy ? 'Setting it up…' : 'Set it up'}
        </button>
      </div>
    </dialog>
  )
}
