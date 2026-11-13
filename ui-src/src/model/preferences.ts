// UI preferences in browser storage: ONLY the active vault's OneNote notebook id and the colour
// theme. Never content (no titles, text or structure): OneNote is the only store
// (tests/NoContentOnDisk.Tests.ps1 allows storage in this file only, under VAULT_KEY and THEME_KEY).

export const VAULT_KEY = 'obsidinote.activeVault'
export const THEME_KEY = 'obsidinote.theme'

/** system = follow Windows' light/dark setting (the default). */
export type Theme = 'system' | 'light' | 'dark'
export const THEMES: readonly Theme[] = ['system', 'light', 'dark']

export function isTheme(value: unknown): value is Theme {
  return typeof value === 'string' && (THEMES as readonly string[]).includes(value)
}

export function getStoredTheme(): Theme {
  try {
    const v = window.localStorage.getItem(THEME_KEY)
    return isTheme(v) ? v : 'system'
  } catch {
    return 'system'
  }
}

export function persistTheme(theme: Theme): void {
  if (!isTheme(theme)) return
  try {
    if (theme === 'system') window.localStorage.removeItem(THEME_KEY)
    else window.localStorage.setItem(THEME_KEY, theme)
  } catch {
    // Storage off: the choice lasts until the window closes.
  }
}

/** Sets the theme on <html> (tokens.css reads data-theme); system removes it. */
export function applyTheme(theme: Theme, root: { dataset: DOMStringMap } = document.documentElement): void {
  if (theme === 'system') delete root.dataset.theme
  else root.dataset.theme = theme
}

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
