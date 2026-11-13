import type { NotebooksState } from '../hooks/useServerData'
import { switcherGroups } from '../model/notebooks'

/** The notebook switcher at the top of the rail: vaults first, other notebooks read only, and
 *  which vault is active. A native select: keyboard, screen readers and touch work as usual. */
export function NotebookSwitcher({ notebooks, onNewVault }: { notebooks: NotebooksState; onNewVault: () => void }) {
  const { list, activeId, shownId } = notebooks
  const active = list.find((n) => n.id === activeId)
  const shown = list.find((n) => n.id === shownId)
  const newVault = (
    <button type="button" className="btn btn--sm switcher__new" onClick={onNewVault}>
      New ObsidiNote vault
    </button>
  )
  if (!list.length) {
    return (
      <div className="switcher">
        <p className="rail__label">Notebook</p>
        <p className="rail__muted">{notebooks.error || notebooks.message || 'Looking for your notebooks...'}</p>
        {newVault}
      </div>
    )
  }
  return (
    <div className="switcher">
      <label htmlFor="notebook-switcher" className="rail__label">
        Notebook
      </label>
      <select id="notebook-switcher" className="field switcher__select" value={shownId ?? ''} onChange={(e) => notebooks.choose(e.target.value)}>
        {switcherGroups(list).map((g) => (
          <optgroup key={g.label} label={g.label}>
            {g.options.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </optgroup>
        ))}
      </select>
      <p className="switcher__note" role="status">
        {shown && !shown.vault ? (
          <>Read only. Adds go to {active ? <b>{active.name}</b> : 'no vault (none is open)'}.</>
        ) : active ? (
          <>
            Active vault{active.location ? ` · ${active.location}` : ''}
            {notebooks.mode === 'readonly' && ' · read only: another ObsidiNote is writing here'}
          </>
        ) : list.some((n) => n.vault) ? (
          'Choose the vault to work in.'
        ) : (
          'No ObsidiNote vault is open.'
        )}
      </p>
      {newVault}
      {notebooks.error && (
        <p className="switcher__note" role="alert">
          {notebooks.error}
        </p>
      )}
    </div>
  )
}
