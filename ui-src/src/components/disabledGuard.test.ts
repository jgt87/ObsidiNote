import { globSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { isBlocked, unavailable } from './disabledGuard'

// Controls that cannot be used carry aria-disabled="true" and stay focusable; the press is ignored by
// the one window-wide guard (disabledGuard.ts). The browser half is the rendered check.
describe('unavailable controls', () => {
  it('marks a control aria-disabled only while it is off', () => {
    expect(unavailable(true)).toEqual({ 'aria-disabled': true })
    expect(unavailable(false)).toEqual({})
  })

  it('blocks nothing that is not an element', () => {
    expect(isBlocked(null)).toBe(false)
  })

  it('no native disabled attribute on an element in the interface (it drops the focus and the tooltip)', () => {
    const root = join(import.meta.dirname, '..')
    const bad: string[] = []
    for (const rel of globSync('**/*.tsx', { cwd: root })) {
      if (rel.endsWith('.test.tsx')) continue
      const text = readFileSync(join(root, rel), 'utf8')
      // A lowercase tag (an element, not a component's own prop) with a disabled attribute.
      for (const m of text.matchAll(/<[a-z][\w-]*\b(?:=>|[^<>])*?\sdisabled(?=[\s=/>])/g)) {
        if ((m[0].match(/\{/g) ?? []).length > (m[0].match(/\}/g) ?? []).length) continue
        bad.push(`${rel}:${text.slice(0, m.index).split('\n').length}`)
      }
    }
    expect(bad).toEqual([])
  })
})
