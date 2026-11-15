// Class names in step between markup and style sheets (code review 2026-11-15: the `.kg-seg` rules
// were deleted while FilterPanel still rendered that class, and three classes were left in CSS
// with no user). Reads the source files; no browser.
//   1 every class a component puts in a className is defined in a style sheet
//   2 every class a style sheet defines is used by some component
// A class built at run time counts as used when its stem is in the source: up to "--"
// ("kg-dot--" + state) or up to a trailing number (`kg-s${strength}`). A block name whose
// elements have rules ("ask-path" with ".ask-path__steps") counts as defined. The shared starter
// sheet (tokens.css) may hold classes this app does not use; the app's own sheets may not.
// Classes that only exist as hooks for scripts or tests go in HOOKS with the reason.
import { readdirSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const SRC = fileURLToPath(new URL('..', import.meta.url))
const TOKENS = fileURLToPath(new URL('../../../src/styles/tokens.css', import.meta.url))

/** Classes used in markup without a rule of their own, each with why. */
const HOOKS: Record<string, string> = {
  'kg-base': 'the map layer the rendered checks and the stage code select',
  'kg-areas': 'excluded from the dimming rule by :not(.kg-areas)',
  'kg-focus-bundles': "the layer of a focused page's topic lines (named in AGENTS.md); its lines carry the style",
}

const walk = (dir: string): string[] => readdirSync(dir, { recursive: true, encoding: 'utf8' }).map((f) => f.replace(/\\/g, '/'))
const files = walk(SRC)
const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
const sheets = [...files.filter((f) => f.endsWith('.css')).map((f) => ({ file: f, text: strip(readFileSync(SRC + f, 'utf8')) })), { file: 'tokens.css', text: strip(readFileSync(TOKENS, 'utf8')) }]
const code = files.filter((f) => /\.tsx?$/.test(f) && !/\.test\./.test(f)).map((f) => ({ file: f, text: readFileSync(SRC + f, 'utf8') }))

/** Class names in the selectors of a style sheet (never in its declarations). */
export function definedClasses(css: string): Set<string> {
  const out = new Set<string>()
  for (const m of css.matchAll(/([^{}]*)\{/g)) {
    if (m[1].trim().startsWith('@')) continue
    for (const c of m[1].matchAll(/\.(-?[_a-zA-Z][\w-]*)/g)) out.add(c[1])
  }
  return out
}

/** Class names written out in the className attributes of a component file, with their line. */
export function usedClasses(source: string): { name: string; line: number }[] {
  const out: { name: string; line: number }[] = []
  for (const m of source.matchAll(/className=(?:"([^"]*)"|\{((?:[^{}]|\{[^{}]*\})*)\})/g)) {
    const line = source.slice(0, m.index).split('\n').length
    // A string that is compared (kind === 'new-topic') is a value, not a class; a name glued to a
    // ${...} part is built at run time and checked by its stem in the other direction.
    const expr = m[2] ?? ''
    const compared = (s: RegExpMatchArray) => /[!=]==\s*$/.test(expr.slice(0, s.index)) || /^\s*[!=]==/.test(expr.slice(s.index! + s[0].length))
    const texts = m[1] !== undefined ? [m[1]] : [...expr.matchAll(/'([^']*)'|"([^"]*)"|`([^`]*)`/g)].filter((s) => !compared(s)).map((s) => (s[1] ?? s[2] ?? s[3]).replace(/\$\{[^}]*\}/g, '\u0000'))
    for (const t of texts) for (const name of t.split(/\s+/)) if (/^-?[_a-zA-Z][\w-]*$/.test(name) && !name.endsWith('--')) out.push({ name, line })
  }
  return out
}

const defined = new Set(sheets.flatMap((s) => [...definedClasses(s.text)]))
const allCode = code.map((c) => c.text).join('\n')

describe('class names: markup and style sheets in step', () => {
  it('every class a component uses is defined in a style sheet', () => {
    const block = (name: string) => [...defined].some((d) => d.startsWith(name + '__'))
    const missing = code.flatMap((c) => usedClasses(c.text).filter((u) => !defined.has(u.name) && !block(u.name) && !(u.name in HOOKS)).map((u) => `${c.file}:${u.line} ${u.name}`))
    expect(missing).toEqual([])
  })

  it('every class a style sheet defines is used by a component', () => {
    const used = (name: string) =>
      new RegExp(`(^|[^\\w-])${name.replace(/[-]/g, '\\-')}([^\\w-]|$)`).test(allCode) ||
      (name.includes('--') && allCode.includes(name.slice(0, name.indexOf('--') + 2))) ||
      (/\d$/.test(name) && allCode.includes(name.replace(/\d+$/, '') + '${'))
    const unused = sheets.filter((s) => s.file !== 'tokens.css').flatMap((s) => [...definedClasses(s.text)].filter((n) => !used(n)).map((n) => `${s.file} .${n}`))
    expect([...new Set(unused)]).toEqual([])
  })

  it('reads enough to mean something (an empty scan is not a pass)', () => {
    expect(defined.size).toBeGreaterThan(200)
    expect(code.reduce((n, c) => n + usedClasses(c.text).length, 0)).toBeGreaterThan(300)
  })

  it('catches a used class without a rule and a rule without a user (the check itself works)', () => {
    expect(usedClasses('<span className="kg-seg" role="group">').map((u) => u.name)).toEqual(['kg-seg'])
    expect(usedClasses("<b className={on ? 'btn btn--primary' : `btn ${extra} seg`} />").map((u) => u.name)).toEqual(['btn', 'btn--primary', 'btn', 'seg'])
    expect(usedClasses("<i className={c.kind === 'new-topic' ? 'chip chip--new' : `kg-s${n}`} />").map((u) => u.name)).toEqual(['chip', 'chip--new'])
    expect([...definedClasses('.a:hover, .b > .c--d { margin: 0.5em; } @media (min-width: 1.5em) { .e { top: .5px; } }')].sort()).toEqual(['a', 'b', 'c--d', 'e'])
  })
})
