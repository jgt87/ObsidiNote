import { useEffect, useRef, useState, type FormEvent } from 'react'
import { ApiError, newVault, type NewVaultResult, type NotebookSummary } from '../api'
import './NewVaultDialog.css'

/** "New ObsidiNote vault": a name, and optionally "inside an existing notebook" (a section group
 *  there). That writes into a notebook ObsidiNote does not own yet, so the server asks first and
 *  this dialog shows that question before anything is written. */
export function NewVaultDialog({ notebooks, onClose, onMade }: { notebooks: NotebookSummary[]; onClose: () => void; onMade: (r: NewVaultResult) => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  const close = useRef(onClose)
  close.current = onClose
  const [name, setName] = useState('')
  const [inside, setInside] = useState(false)
  const [target, setTarget] = useState('')
  const [confirm, setConfirm] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const hosts = notebooks.filter((n) => !n.vault)

  useEffect(() => {
    const d = ref.current
    if (d && !d.open) d.showModal()
  }, [])

  async function make(confirmed: boolean) {
    setBusy(true)
    setError('')
    try {
      const r = await newVault(name.trim(), inside ? target : undefined, confirmed)
      onMade(r)
    } catch (e) {
      if (e instanceof ApiError && e.status === 409 && inside && !confirmed) setConfirm(e.message)
      else setError(e instanceof Error ? e.message : 'ObsidiNote did not answer.')
    } finally {
      setBusy(false)
    }
  }

  function onSubmit(e: FormEvent) {
    e.preventDefault()
    if (!busy) void make(Boolean(confirm))
  }

  const host = hosts.find((h) => h.id === target)
  const valid = /^[A-Za-z0-9][A-Za-z0-9 ._-]{0,59}$/.test(name.trim()) && (!inside || Boolean(target))
  return (
    <dialog ref={ref} className="nv" aria-labelledby="nv-title" aria-describedby="nv-desc" onCancel={(e) => { e.preventDefault(); if (!busy) close.current() }}>
      <form onSubmit={onSubmit}>
        <div className="nv__body">
          <h2 id="nv-title" className="nv__title">
            {confirm ? `Write a vault into ${host?.name ?? 'that notebook'}?` : 'New ObsidiNote vault'}
          </h2>
          {confirm ? (
            <p id="nv-desc" className="nv__text">
              {confirm} The rest of that notebook stays read only.
            </p>
          ) : (
            <>
              <p id="nv-desc" className="nv__muted">
                A vault is a OneNote notebook with ObsidiNote's sections and its own index. It becomes the active vault.
              </p>
              <label className="nv__label" htmlFor="nv-name">
                Name
              </label>
              <input id="nv-name" className="field nv__field" value={name} maxLength={60} onChange={(e) => setName(e.target.value)} autoFocus required />
              {hosts.length > 0 && (
                <label className="nv__check">
                  <input type="checkbox" checked={inside} onChange={(e) => setInside(e.target.checked)} />
                  Inside an existing notebook (as a section group)
                </label>
              )}
              {inside && (
                <select className="field nv__field" aria-label="Notebook to put the vault in" value={target} onChange={(e) => setTarget(e.target.value)}>
                  <option value="">Choose a notebook</option>
                  {hosts.map((h) => (
                    <option key={h.id} value={h.id}>
                      {h.name}
                    </option>
                  ))}
                </select>
              )}
            </>
          )}
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
          <button type="submit" className="btn btn--primary" disabled={busy || !valid} aria-busy={busy}>
            {busy ? 'Making it…' : confirm ? 'Write the vault' : 'Make the vault'}
          </button>
        </div>
      </form>
    </dialog>
  )
}
