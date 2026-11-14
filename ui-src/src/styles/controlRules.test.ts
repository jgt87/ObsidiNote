// Control height rules that a static check can hold (CommonShared rules/ui.md "One height per bar
// and per control kind"; the rendered check is scripts/check-control-rows.mjs). 2026-11-13: an
// <a class="btn"> rendered 34px next to 32px <button>s because .btn had no box-sizing: the border
// came on top of the height. The same holds for <input class="field"> next to <select class="field">.
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const css = readFileSync(fileURLToPath(new URL('../../../src/styles/tokens.css', import.meta.url)), 'utf8')

function block(selector: string): string {
  const i = css.search(new RegExp(`^${selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*\\{`, 'm'))
  if (i < 0) return ''
  return css.slice(i, css.indexOf('}', i) + 1)
}

describe('controls of one kind have one height whatever their element', () => {
  it('.btn counts its border inside its height (a link styled as a button is as tall as a button)', () => {
    const b = block('.btn')
    expect(b).toMatch(/height:\s*var\(--control-h\)/)
    expect(b).toMatch(/box-sizing:\s*border-box/)
  })
  it('.field counts its border inside its height (an input is as tall as a select)', () => {
    const f = block('.field, select.field')
    expect(f).toMatch(/height:\s*var\(--control-h\)/)
    expect(f).toMatch(/box-sizing:\s*border-box/)
  })
  it('catches a rule without box-sizing (the check itself works)', () => {
    expect('.btn { height: var(--control-h); }').not.toMatch(/box-sizing:\s*border-box/)
    expect(block('.no-such-rule')).toBe('')
  })
})
