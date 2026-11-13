import { useState, type KeyboardEvent } from 'react'
import { applyTheme, getStoredTheme, persistTheme, THEMES, type Theme } from '../model/preferences'
import './ThemeSwitch.css'

const LABEL: Record<Theme, string> = { system: 'System', light: 'Light', dark: 'Dark' }

/** System / Light / Dark at the bottom of the side bar, a radio group (arrow keys move the choice).
 *  System follows Windows' setting; tokens.css then follows prefers-color-scheme by itself. */
export function ThemeSwitch() {
  const [theme, setTheme] = useState<Theme>(getStoredTheme)
  function choose(t: Theme) {
    setTheme(t)
    applyTheme(t)
    persistTheme(t)
  }
  function onKeyDown(e: KeyboardEvent<HTMLDivElement>) {
    const step = e.key === 'ArrowRight' || e.key === 'ArrowDown' ? 1 : e.key === 'ArrowLeft' || e.key === 'ArrowUp' ? -1 : 0
    if (!step) return
    e.preventDefault()
    const next = THEMES[(THEMES.indexOf(theme) + step + THEMES.length) % THEMES.length]
    choose(next)
    e.currentTarget.querySelector<HTMLButtonElement>(`[data-theme-option="${next}"]`)?.focus()
  }
  return (
    <div className="seg theme-switch" role="radiogroup" aria-label="Colour theme" onKeyDown={onKeyDown}>
      {THEMES.map((t) => (
        <button
          key={t}
          type="button"
          role="radio"
          aria-checked={theme === t}
          tabIndex={theme === t ? 0 : -1}
          data-theme-option={t}
          className="seg__btn theme-switch__btn"
          onClick={() => choose(t)}
        >
          {LABEL[t]}
        </button>
      ))}
    </div>
  )
}
