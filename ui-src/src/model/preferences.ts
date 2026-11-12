// UI preferences in browser storage: ONLY the active vault's OneNote notebook id. Never content
// (no titles, text or structure): OneNote is the only store (tests/NoContentOnDisk.Tests.ps1
// allows storage in this file only, and only under VAULT_KEY).

export const VAULT_KEY = 'obsidinote.activeVault'

/** A OneNote notebook id: {GUID}{n}{Bn}. Anything else read back is ignored. */
const NOTEBOOK_ID = /^\{[0-9A-Fa-f-]{36}\}(\{\d+\}\{[A-Za-z]\d+\})?$/

export function isNotebookId(value: unknown): value is string {
  return typeof value === 'string' && value.length <= 200 && NOTEBOOK_ID.test(value)
}

export function getStoredVaultId(): string | null {
  try {
    const v = window.localStorage.getItem(VAULT_KEY)
    return isNotebookId(v) ? v : null
  } catch {
    return null
  }
}

export function persistVaultId(id: string): void {
  if (!isNotebookId(id)) return
  try {
    window.localStorage.setItem(VAULT_KEY, id)
  } catch {
    // Storage off (private window, policy): the choice lasts until the window closes.
  }
}
