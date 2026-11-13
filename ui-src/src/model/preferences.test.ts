import { describe, expect, it } from 'vitest'
import { applyTheme, isTheme, THEMES } from './preferences'

describe('theme preference', () => {
  it('accepts only the three themes', () => {
    expect(THEMES).toEqual(['system', 'light', 'dark'])
    expect(isTheme('dark')).toBe(true)
    expect(isTheme('Dark')).toBe(false)
    expect(isTheme('<script>')).toBe(false)
    expect(isTheme(null)).toBe(false)
  })
  it('sets data-theme for light and dark, and removes it for system', () => {
    const root = { dataset: {} as DOMStringMap }
    applyTheme('dark', root)
    expect(root.dataset.theme).toBe('dark')
    applyTheme('light', root)
    expect(root.dataset.theme).toBe('light')
    applyTheme('system', root)
    expect(root.dataset.theme).toBeUndefined()
  })
})
