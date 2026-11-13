// Which vault is active and how the switcher lists notebooks. Pure (tests: notebooks.test.ts).
import type { NotebookSummary } from '../api'

/** The active vault: the stored choice when it is an open vault, else the server's active one
 *  (the vault on record), else the only open vault; null when none is open, or when several are
 *  and none was chosen (the person picks one: switching vault is a deliberate action). */
export function pickActiveVault(list: NotebookSummary[], storedId: string | null): string | null {
  const vaults = list.filter((n) => n.vault)
  if (storedId && vaults.some((v) => v.id === storedId)) return storedId
  return vaults.find((v) => v.active)?.id ?? (vaults.length === 1 ? vaults[0].id : null)
}

/** What the knowledge graph loads for the shown entry: a vault by its id, else a notebook. */
export function graphRefFor(entry: NotebookSummary | undefined): { vault: string } | { notebook: string } | Record<string, never> {
  if (!entry) return {}
  if (entry.vault && entry.vaultId) return { vault: entry.vaultId }
  return { notebook: entry.id }
}

/** The read-only sources Ask can include besides the active vault: other vaults and notebooks.
 *  The id is what the server takes in sources: a vault id, or a notebook id. */
export function askSourceChoices(list: NotebookSummary[], activeId: string | null): { id: string; label: string }[] {
  return list
    .filter((n) => n.id !== activeId)
    .map((n) => ({ id: n.vault && n.vaultId ? n.vaultId : n.id, label: n.vault ? `${n.name} (vault, read only)` : `${n.name} (read only)` }))
}

export interface SwitcherGroup {
  label: string
  options: { id: string; label: string }[]
}

/** Vaults first (writable), then the other notebooks marked read only; empty groups left out. */
export function switcherGroups(list: NotebookSummary[]): SwitcherGroup[] {
  const groups: SwitcherGroup[] = [
    { label: 'ObsidiNote vaults', options: list.filter((n) => n.vault).map((n) => ({ id: n.id, label: n.name })) },
    { label: 'Other notebooks', options: list.filter((n) => !n.vault).map((n) => ({ id: n.id, label: `${n.name} (read only)` })) },
  ]
  return groups.filter((g) => g.options.length > 0)
}

/** Where an Add goes while another notebook is shown: null when the shown notebook is the active vault. */
export interface AddTarget {
  vaultName: string | null
  shownName: string
}

export function addTargetFor(list: NotebookSummary[], activeId: string | null, shownId: string | null): AddTarget | null {
  const shown = list.find((n) => n.id === shownId)
  if (!shown || shown.id === activeId) return null
  return { vaultName: list.find((n) => n.id === activeId)?.name ?? null, shownName: shown.name }
}
