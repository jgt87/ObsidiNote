import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { joinLines, normalizeTag, normalizeTags, suggestTags, tagCounts, tagOfQuery, tagQuery } from './tags'

// The same cases the server's tag function is tested against (tests/*.Tests.ps1 reads this file).
const fixture = JSON.parse(readFileSync(fileURLToPath(new URL('../../../tests/fixtures/tags.json', import.meta.url)), 'utf8')) as {
  tags: { in: string; out: string | null }[]
  lists: { in: string[]; out: string[] | null }[]
}

describe('the normal form of a tag (shared fixture with the server)', () => {
  it('gives every case of the fixture its normal form, or refuses it', () => {
    expect(fixture.tags.length).toBeGreaterThan(10)
    for (const c of fixture.tags) {
      const r = normalizeTag(c.in)
      expect(r.ok ? r.tag : null, JSON.stringify(c.in)).toBe(c.out)
    }
  })
  it('does the same for lists: duplicates go, order stays, twelve at most', () => {
    for (const c of fixture.lists) {
      const r = normalizeTags(c.in)
      expect(r.ok ? r.tags : null, JSON.stringify(c.in)).toEqual(c.out)
    }
  })
  it('says why a tag is refused', () => {
    const r = normalizeTag('a:b')
    expect(r.ok).toBe(false)
    expect(!r.ok && r.error).toMatch(/colon/)
  })
})

describe('tags in use', () => {
  const pages = [
    { tags: ['licensing', 'follow up'], archived: false },
    { tags: ['licensing'], archived: false },
    { tags: ['old'], archived: true },
  ]
  it('counts pages per tag, by name', () => {
    expect(tagCounts(pages)).toEqual([{ name: 'follow up', count: 1 }, { name: 'licensing', count: 2 }, { name: 'old', count: 1 }])
    expect(tagCounts(pages, false).map((t) => t.name)).toEqual(['follow up', 'licensing'])
  })
  it('suggests the tags that hold the typed text and are not on the page yet, starting matches first', () => {
    const all = [{ name: 'follow up', count: 1 }, { name: 'licences', count: 3 }, { name: 'licensing', count: 2 }, { name: 'key licence', count: 1 }]
    expect(suggestTags(all, 'lic', [])).toEqual(['licences', 'licensing', 'key licence'])
    expect(suggestTags(all, ' LIC ', ['licensing'])).toEqual(['licences', 'key licence'])
    expect(suggestTags(all, '', ['follow up'])).toEqual(['licences', 'licensing', 'key licence'])
  })
  it('turns a tag into its search query and back', () => {
    expect(tagQuery('licensing')).toBe('tag:licensing')
    expect(tagQuery('follow up')).toBe('tag:"follow up"')
    expect(tagOfQuery('tag:"follow up"')).toBe('follow up')
    expect(tagOfQuery(' tag:Licensing ')).toBe('licensing')
    expect(tagOfQuery('tag:licensing zero')).toBe('')
    expect(tagOfQuery('zero trust')).toBe('')
  })
})

describe('joinLines: the pages of a tag as one group on the map', () => {
  it('joins n pages with n - 1 lines, each to its nearest joined page', () => {
    const pts = [{ id: 'a', x: 0, y: 0 }, { id: 'b', x: 10, y: 0 }, { id: 'c', x: 100, y: 0 }, { id: 'd', x: 110, y: 0 }]
    expect(joinLines(pts)).toEqual([['a', 'b'], ['b', 'c'], ['c', 'd']])
  })
  it('gives the same lines whatever order the pages come in, and none for one page', () => {
    const pts = [{ id: 'c', x: 5, y: 9 }, { id: 'a', x: 0, y: 0 }, { id: 'b', x: 4, y: 1 }]
    expect(joinLines(pts)).toEqual(joinLines([...pts].reverse()))
    expect(joinLines([{ id: 'a', x: 0, y: 0 }])).toEqual([])
    expect(joinLines([])).toEqual([])
  })
})
