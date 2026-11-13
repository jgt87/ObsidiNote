// Keyboard shortcuts of the composer. Pure (tests: keys.test.ts).
import type { Mode } from '../api'

export interface KeyLike {
  key: string
  code?: string
  ctrlKey: boolean
  metaKey: boolean
  altKey: boolean
  shiftKey: boolean
  isComposing?: boolean
}

/** Ctrl+1 = Add, Ctrl+2 = Ask (Cmd on a Mac). Matched on the digit key's code so a keyboard
 *  layout that puts symbols on the digit row still works. */
export function modeForKey(e: KeyLike): Mode | null {
  if (!(e.ctrlKey || e.metaKey) || e.altKey || e.shiftKey) return null
  const digit = e.code?.startsWith('Digit') ? e.code.slice(5) : e.key
  if (digit === '1') return 'add'
  if (digit === '2') return 'ask'
  return null
}

/** Ctrl+K (Cmd+K on a Mac) opens the quick switcher, anywhere in the app, also while typing.
 *  Matched on the key's code too, so it works on layouts where K is elsewhere. */
export function isFindKey(e: KeyLike): boolean {
  if (!(e.ctrlKey || e.metaKey) || e.altKey || e.shiftKey || e.isComposing) return false
  return e.code === 'KeyK' || e.key.toLowerCase() === 'k'
}

/** Enter sends; Shift+Enter adds a line; never during IME composition. */
export function isSendKey(e: KeyLike): boolean {
  return e.key === 'Enter' && !e.shiftKey && !e.altKey && !e.isComposing
}
