import { describe, expect, it } from 'vitest'
import { buildIndex } from '../graph/graphIndex'
import { normalizeGraph } from '../graph/model'
import { describeFilter, findAll, normalizeText, parseQuery, rankPages, rankTopics, startsWord, topicQuery, withoutFilter, withoutFilters } from './query'

// Invented example data.
const model = normalizeGraph({
  source: { kind: 'vault', id: 'v1', name: 'Test vault' },
  topics: [
    { id: 't1', name: 'Security', path: 'Security', parent: null },
    { id: 't2', name: 'Networking', path: 'Security / Networking', parent: 't1' },
    { id: 't3', name: 'Zero trust', path: 'Security / Networking / Zero trust', parent: 't2' },
    { id: 't4', name: 'Cooking', path: 'Cooking', parent: null },
    { id: 't5', name: 'Café culture', path: 'Cooking / Café culture', parent: 't4' },
  ],
  pages: [
    { id: 'p1', title: 'Zero-trust networking', topicIds: ['t3'], bucket: 'Notes', kind: 'concept', summary: 'How access works', modified: '2026-03-10T09:00:00Z', isHub: true },
    { id: 'p2', title: 'Network zero day review', topicIds: ['t2'], bucket: 'Meetings', kind: 'meeting', summary: 'Weekly review', modified: '2026-02-28T09:00:00Z' },
    { id: 'p3', title: 'Identity proxies', topicIds: ['t1'], bucket: 'Web links', kind: 'link-web', site: 'www.example.org', aliases: ['ZTNA gateway'], modified: '2025-12-01', unlinked: true },
    { id: 'p4', title: 'Crème brûlée', topicIds: ['t5'], bucket: 'Notes', kind: 'note', summary: 'A dessert with a zero-waste trick', modified: '2026-03-01', archived: true },
    { id: 'p5', title: 'Weekly sync', topicIds: [], bucket: 'Meetings', kind: 'meeting', summary: 'Talks about the café', site: '', modified: '' },
    { id: 'p6', title: 'Example docs', topicIds: ['t4'], bucket: 'Web links', kind: 'link-web', site: 'notexample.org', modified: '2026-04-02' },
  ],
  edges: [],
})
const index = buildIndex(model)
const ids = (q: string) => rankPages(index, parseQuery(q)).map((r) => r.id)

describe('parseQuery', () => {
  it('splits free words, quoted phrases and filters', () => {
    const q = parseQuery('Zero  "trust Net" type:Meeting site:www.Example.org is:hub')
    expect(q.terms).toEqual(['zero', 'trust net'])
    expect(q.filters.map((f) => [f.key, f.value])).toEqual([
      ['type', 'meeting'],
      ['site', 'www.example.org'],
      ['is', 'hub'],
    ])
  })

  it('keeps unknown or invalid key:value text as a free word, ignores an empty filter', () => {
    expect(parseQuery('x:y').terms).toEqual(['x:y'])
    expect(parseQuery('is:pinned').terms).toEqual(['is:pinned'])
    expect(parseQuery('after:2026-13').terms).toEqual(['after:2026-13'])
    expect(parseQuery('after:yesterday').filters).toEqual([])
    const q = parseQuery('type: meeting')
    expect(q.filters).toEqual([])
    expect(q.terms).toEqual(['meeting'])
    expect(parseQuery('https://example.org').terms).toEqual(['https://example.org'])
  })

  it('reads quoted filter values and topic paths', () => {
    const q = parseQuery('topic:"Security / Networking" notes')
    expect(q.filters[0].value).toBe('security/networking')
    expect(describeFilter(q.filters[0])).toBe('topic: Security / Networking')
    expect(q.terms).toEqual(['notes'])
  })

  it('normalizes case and accents', () => {
    expect(normalizeText('Crème BRÛLÉE')).toBe('creme brulee')
    expect(parseQuery('CAFÉ').terms).toEqual(['cafe'])
  })

  it('removes one filter or all of them from the text', () => {
    const text = 'zero type:meeting  site:example.org'
    const q = parseQuery(text)
    expect(withoutFilter(text, q.filters[0])).toBe('zero site:example.org')
    expect(withoutFilters(text)).toBe('zero')
    expect(topicQuery('Security / Networking')).toBe('topic:"Security / Networking"')
    expect(topicQuery('Cooking')).toBe('topic:Cooking')
    expect(parseQuery(topicQuery('Security / Networking')).filters[0].value).toBe('security/networking')
  })

  it('finds word starts', () => {
    expect(startsWord('zero-trust networking', 'trust')).toBe(true)
    expect(startsWord('zero-trust networking', 'rust')).toBe(false)
  })
})

describe('rankPages', () => {
  it('ranks title start > word start > contains > alias > topic path > summary', () => {
    // p1 title starts with "zero"; p2 has "zero" starting a word; p4 only in the summary.
    expect(ids('zero')).toEqual(['p1', 'p2', 'p4'])
    // "net": p2's title starts with it, p1 has it at the start of a word.
    expect(ids('net')).toEqual(['p2', 'p1'])
    expect(ids('ztna')).toEqual(['p3'])
    // Topic path match ranks above a summary match.
    expect(ids('cafe')).toEqual(['p4', 'p5'])
  })

  it('needs every word, anywhere in the fields', () => {
    expect(ids('zero review')).toEqual(['p2'])
    expect(ids('zero nothing')).toEqual([])
    expect(ids('"day review"')).toEqual(['p2'])
  })

  it('is accent-insensitive', () => {
    expect(ids('creme')).toEqual(['p4'])
    expect(ids('BRÛLÉE')).toEqual(['p4'])
  })

  it('filters by type (kind or bucket, prefix)', () => {
    expect(ids('type:meet')).toEqual(['p2', 'p5'])
    expect(ids('type:"web links"')).toEqual(['p6', 'p3'])
    expect(ids('type:meeting type:concept')).toEqual(['p2', 'p5', 'p1'])
  })

  it('filters by topic with its subtopics', () => {
    expect(ids('topic:security')).toEqual(['p3', 'p2', 'p1'])
    expect(ids('topic:"security / networking"')).toEqual(['p2', 'p1'])
    expect(ids('topic:"zero trust"')).toEqual(['p1'])
    expect(ids('topic:cafe')).toEqual(['p4'])
  })

  it('filters by site as a suffix on a dot boundary', () => {
    expect(ids('site:example.org')).toEqual(['p3'])
    expect(ids('site:https://www.example.org/path')).toEqual(['p3'])
    expect(ids('site:notexample.org')).toEqual(['p6'])
  })

  it('filters by date: after = on or after, before = before', () => {
    expect(ids('after:2026-03')).toEqual(['p4', 'p6', 'p1'])
    expect(ids('after:2026-03-02 before:2026-04')).toEqual(['p1'])
    expect(ids('before:2026')).toEqual([]) // not a date: a free word, which no page holds
    expect(ids('before:2026-01')).toEqual(['p3'])
  })

  it('filters by is:', () => {
    expect(ids('is:archived')).toEqual(['p4'])
    expect(ids('is:hub')).toEqual(['p1'])
    expect(ids('is:unlinked')).toEqual(['p3'])
    expect(ids('is:hub is:unlinked')).toEqual([])
  })

  it('combines filters and words', () => {
    expect(ids('review type:meeting')).toEqual(['p2'])
    // type:note also matches the bucket "Notes" of p1.
    expect(ids('zero type:note')).toEqual(['p1', 'p4'])
    expect(ids('')).toEqual([])
    expect(ids('   ')).toEqual([])
  })
})

describe('rankTopics and findAll', () => {
  it('ranks topics by name, then path; none with filters', () => {
    expect(rankTopics(index, parseQuery('net')).map((t) => t.id)).toEqual(['t2', 't3'])
    expect(rankTopics(index, parseQuery('security')).map((t) => t.id)).toEqual(['t1', 't2', 't3'])
    expect(rankTopics(index, parseQuery('security type:note'))).toEqual([])
  })

  it('mixes topics and pages, a topic first at the same rank, and caps the list', () => {
    const r = findAll(index, 'zero')
    expect(r.items[0]).toEqual({ kind: 'topic', id: 't3' })
    expect(r.items[1]).toEqual({ kind: 'page', id: 'p1' })
    expect(r.total).toBe(4)
    const capped = findAll(index, 'zero', 2)
    expect(capped.items.length).toBe(2)
    expect(capped.total).toBe(4)
  })

  it('stays fast at 5,000 pages', () => {
    const pages = Array.from({ length: 5000 }, (_, i) => ({ id: `q${i}`, title: `Page number ${i} about topic ${i % 50}`, topicIds: ['t1'], summary: 'Some longer summary text', modified: '2026-01-01' }))
    const big = buildIndex(normalizeGraph({ source: {}, topics: model.topics, pages, edges: [] }))
    rankPages(big, parseQuery('warm up'))
    const t0 = performance.now()
    for (let i = 0; i < 10; i++) rankPages(big, parseQuery(`about topic ${i}`))
    expect((performance.now() - t0) / 10).toBeLessThan(50)
  })
})
