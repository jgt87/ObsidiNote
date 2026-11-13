import { describe, expect, it } from 'vitest'
import { isFindKey, isSendKey, modeForKey } from './keys'

const base = { key: '', ctrlKey: false, metaKey: false, altKey: false, shiftKey: false }

describe('modeForKey', () => {
  it('maps Ctrl+1 to Add and Ctrl+2 to Ask', () => {
    expect(modeForKey({ ...base, key: '1', code: 'Digit1', ctrlKey: true })).toBe('add')
    expect(modeForKey({ ...base, key: '2', code: 'Digit2', ctrlKey: true })).toBe('ask')
    expect(modeForKey({ ...base, key: '&', code: 'Digit1', ctrlKey: true })).toBe('add')
  })
  it('ignores plain digits and other chords', () => {
    expect(modeForKey({ ...base, key: '1', code: 'Digit1' })).toBeNull()
    expect(modeForKey({ ...base, key: '1', code: 'Digit1', ctrlKey: true, shiftKey: true })).toBeNull()
    expect(modeForKey({ ...base, key: '3', code: 'Digit3', ctrlKey: true })).toBeNull()
  })
})

describe('isSendKey', () => {
  it('sends on Enter, not on Shift+Enter or during composition', () => {
    expect(isSendKey({ ...base, key: 'Enter' })).toBe(true)
    expect(isSendKey({ ...base, key: 'Enter', shiftKey: true })).toBe(false)
    expect(isSendKey({ ...base, key: 'Enter', isComposing: true })).toBe(false)
  })
})

describe('isFindKey', () => {
  it('opens the quick switcher on Ctrl+K or Cmd+K only', () => {
    expect(isFindKey({ ...base, key: 'k', code: 'KeyK', ctrlKey: true })).toBe(true)
    expect(isFindKey({ ...base, key: 'K', code: 'KeyK', metaKey: true })).toBe(true)
    expect(isFindKey({ ...base, key: 'k', code: 'KeyK' })).toBe(false)
    expect(isFindKey({ ...base, key: 'K', code: 'KeyK', ctrlKey: true, shiftKey: true })).toBe(false)
    expect(isFindKey({ ...base, key: 'k', code: 'KeyK', ctrlKey: true, altKey: true })).toBe(false)
    expect(isFindKey({ ...base, key: 'j', code: 'KeyJ', ctrlKey: true })).toBe(false)
  })
})
