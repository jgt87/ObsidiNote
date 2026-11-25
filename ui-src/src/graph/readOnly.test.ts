import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { normalizeGraph } from './model'
import { OWN_PAGE_WHY, pageReadOnlyWhy, readOnlyWhy } from './readOnly'

// What the server sends per page (tests/GraphModel.Tests.ps1 compares its output with this file).
const fixture = JSON.parse(readFileSync(new URL('../../../tests/fixtures/graph-pages.json', import.meta.url), 'utf8')) as { pages: { id: string; source: string; own: boolean }[] }

describe('pageReadOnlyWhy: a page the person made is listed, never changed (D-056)', () => {
  const vault = { kind: 'vault' as const, readOnly: false, readOnlyReason: '' as const }
  it('reads own from what the server sends, for every kind of page in the fixture', () => {
    const m = normalizeGraph({ source: vault, pages: fixture.pages.map((p) => ({ id: p.id, title: p.id, own: p.own })) })
    expect(m.pages.map((p) => `${p.id}:${p.own}`)).toEqual(fixture.pages.map((p) => `${p.id}:${p.own}`))
    expect(fixture.pages.some((p) => p.source === 'vault-user' && !p.own)).toBe(true)
  })
  it("gives the reason for a page the person made, and the source's reason first", () => {
    expect(pageReadOnlyWhy({ readOnly: false, own: false }, vault)).toBe(OWN_PAGE_WHY)
    expect(pageReadOnlyWhy({ readOnly: false, own: true }, vault)).toBe('')
    expect(pageReadOnlyWhy({ readOnly: true, own: false }, { kind: 'notebook', readOnly: true, readOnlyReason: 'notebook' })).toMatch(/connected notebook/)
  })
  it("treats a page as ObsidiNote's own when an older server does not say", () => {
    expect(normalizeGraph({ source: vault, pages: [{ id: 'p1', title: 'x' }] }).pages[0].own).toBe(true)
  })
})

describe('readOnlyWhy: why a page cannot be changed here', () => {
  it('says nothing for a source that can be changed', () => {
    expect(readOnlyWhy({ kind: 'vault', readOnly: false, readOnlyReason: '' })).toBe('')
  })
  it('names each reason the server gives, with what to do', () => {
    expect(readOnlyWhy({ kind: 'vault', readOnly: true, readOnlyReason: 'lease' })).toMatch(/may show as read only.*seems to hold/)
    expect(readOnlyWhy({ kind: 'vault', readOnly: true, readOnlyReason: 'not-active' })).toMatch(/not the active vault/)
    expect(readOnlyWhy({ kind: 'notebook', readOnly: true, readOnlyReason: 'notebook' })).toMatch(/never writes/)
  })
  it('still says something sensible when an older server gives no reason', () => {
    expect(readOnlyWhy({ kind: 'notebook', readOnly: true, readOnlyReason: '' })).toMatch(/connected notebook/)
    expect(readOnlyWhy({ kind: 'vault', readOnly: true, readOnlyReason: '' })).toMatch(/read only/)
  })
})
