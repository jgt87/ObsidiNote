import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { buildIndex } from '../graph/graphIndex'
import { normalizeGraph } from '../graph/model'
import { findAll } from '../search/query'
import { sectionQuery } from './sections'

// The graph pages as the server really sends them: tests/GraphModel.Tests.ps1 builds these through
// the real function and compares with this same file, so the shapes here are not invented on this
// side (lesson 2026-11-15: this test first passed on buckets like "Journal / 2026" that the server
// never sends, and nested sections opened an empty List).
const fixture = JSON.parse(readFileSync(fileURLToPath(new URL('../../../tests/fixtures/graph-pages.json', import.meta.url)), 'utf8')) as {
  pages: { id: string; section: string; bucket: string; kind: string }[]
}

describe('sectionQuery: a section of the side bar as a search of the List', () => {
  it('asks for the section path exactly, with its group in front', () => {
    expect(sectionQuery(['Web links'])).toBe('section:"Web links"')
    expect(sectionQuery(['Journal', '2026'])).toBe('section:"Journal/2026"')
    expect(sectionQuery(['Notes 2'])).toBe('section:"Notes 2"')
  })

  it('gives no query for the sections of a vault whose pages are not in the graph', () => {
    expect(sectionQuery(['00 Index'])).toBeNull()
    expect(sectionQuery(['01 Intake'])).toBeNull()
    expect(sectionQuery(['Archive'])).toBeNull()
    expect(sectionQuery(['Archive', 'Notes'])).toBeNull()
    expect(sectionQuery([])).toBeNull()
  })

  it('opens every section of a connected notebook, whatever it is called', () => {
    expect(sectionQuery(['00 Admin'], false)).toBe('section:"00 Admin"')
    expect(sectionQuery(['Archive'], false)).toBe('section:"Archive"')
    expect(sectionQuery(['Group', 'Section'], false)).toBe('section:"Group/Section"')
  })

  it('never breaks the quotes of the search language', () => {
    expect(sectionQuery(['My "special" notes'])).toBe('section:"My special notes"')
  })

  it('the fixture holds the cases that went wrong: a rollover, a year, a section in a group', () => {
    const sections = fixture.pages.map((p) => p.section)
    for (const s of ['Notes', 'Notes 2', 'Journal/2026', 'Journal/2025', 'Group/Section']) expect(sections).toContain(s)
  })

  // The window sends this query to the real search: for every section the server sends, it must
  // find that section's pages and only those ("Notes" never lists the pages of "Notes 2").
  it('finds exactly the pages of each section the server sends', () => {
    const model = normalizeGraph({
      source: { id: 'v', name: 'V', kind: 'vault', readOnly: false },
      topics: [],
      edges: [],
      pages: fixture.pages.map((p) => ({ ...p, title: `Page ${p.id}`, topicIds: [] })),
    })
    const index = buildIndex(model)
    expect(model.pages).toHaveLength(fixture.pages.length)
    for (const section of new Set(fixture.pages.map((p) => p.section).filter(Boolean))) {
      const query = sectionQuery(section.split('/'), false)!
      const found = findAll(index, query).items.filter((i) => i.kind === 'page').map((i) => i.id).sort()
      const expected = fixture.pages.filter((p) => p.section === section).map((p) => p.id).sort()
      expect(found, query).toEqual(expected)
    }
  })
})
