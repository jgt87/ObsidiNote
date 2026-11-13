import { describe, expect, it } from 'vitest'
import { findMentions, mentionBetween, nameKey, normalizeWords, withMentions } from './mentions'
import type { GraphEdge, GraphModel, GraphPage } from './model'

function page(id: string, title: string, extra: Partial<GraphPage> = {}): GraphPage {
  return {
    id, title, topicIds: [], bucket: 'Notes', kind: 'note', links: 0, isHub: false, unlinked: true, summary: '',
    onenoteUrl: '', modified: '', readOnly: false, aliases: [], site: '', archived: false, ...extra,
  }
}

function model(pages: GraphPage[], edges: GraphEdge[] = []): GraphModel {
  return { source: { kind: 'vault', id: 'v', name: 'V', readOnly: false }, topics: [], pages, edges }
}

const pairs = (es: GraphEdge[]) => es.map((e) => `${e.from}>${e.to}`).sort()

describe('normalizeWords and nameKey', () => {
  it('ignores case and accents and splits on anything but letters and digits', () => {
    expect(normalizeWords('Café-Zürich, ÉTÉ 2026!')).toEqual(['cafe', 'zurich', 'ete', '2026'])
  })
  it('skips short, letterless and generic-only names', () => {
    expect(nameKey('VPN')).toBe('')
    expect(nameKey('2026-11-13')).toBe('')
    expect(nameKey('Notes')).toBe('')
    expect(nameKey('Untitled page')).toBe('')
    expect(nameKey('Meeting notes')).toBe('')
    expect(nameKey('Zero trust')).toBe('zero trust')
    expect(nameKey('one two three four five six seven')).toBe('')
  })
})

describe('findMentions', () => {
  it('finds a title in another page\'s summary as whole words, case- and accent-insensitive', () => {
    const m = model([
      page('a', 'Zero trust'),
      page('b', 'Partner portal', { summary: 'Access follows ZERO TRUST rules.' }),
      page('c', 'Café opening', { summary: 'Plans for the cafe opening.' }),
      page('d', 'Weekly plan', { summary: 'Remember the café Opening!' }),
    ])
    expect(pairs(findMentions(m))).toEqual(['b>a', 'd>c'])
    expect(findMentions(m).every((e) => e.kind === 'mention' && e.strength === 1)).toBe(true)
  })
  it('never matches inside a word', () => {
    const m = model([page('a', 'Proxy'), page('b', 'Notes', { summary: 'Proxyless designs and reproxy tools.' })])
    expect(findMentions(m)).toEqual([])
  })
  it('matches aliases like titles, and finds names in the title too', () => {
    const m = model([
      page('a', 'Identity-aware proxy', { aliases: ['IAP gateway'] }),
      page('b', 'Gateway setup', { summary: 'We put the iap gateway in front.' }),
      page('c', 'Identity-aware proxy rollout'),
    ])
    expect(pairs(findMentions(m))).toEqual(['b>a', 'c>a'])
  })
  it('skips pairs that are linked in either direction, and the page itself', () => {
    const m = model(
      [page('a', 'Zero trust', { summary: 'Zero trust explained.' }), page('b', 'Portal', { summary: 'Zero trust' }), page('c', 'Gateway', { summary: 'zero trust' })],
      [{ from: 'a', to: 'b', strength: 2, kind: 'link' }],
    )
    expect(pairs(findMentions(m))).toEqual(['c>a'])
  })
  it('makes one edge for a pair that mentions each other', () => {
    const m = model([page('a', 'Zero trust', { summary: 'See partner portal.' }), page('b', 'Partner portal', { summary: 'Uses zero trust.' })])
    expect(findMentions(m)).toHaveLength(1)
  })
  it('leaves archived pages out on both sides', () => {
    const m = model([
      page('a', 'Zero trust', { archived: true }),
      page('b', 'Portal', { summary: 'zero trust and gateway rules' }),
      page('c', 'Gateway rules'),
      page('d', 'Old plan', { archived: true, summary: 'gateway rules' }),
    ])
    expect(pairs(findMentions(m))).toEqual(['b>c'])
  })
  it('keeps at most 5 per page, longest name first', () => {
    const names = ['Alpha', 'Bravo team', 'Charlie long name', 'Delta', 'Echo', 'Foxtrot', 'Golf course plan']
    const targets = names.map((n, i) => page(`t${i}`, n))
    const m = model([...targets, page('x', 'Overview', { summary: names.join(', ') })])
    const fromX = findMentions(m).filter((e) => e.from === 'x').map((e) => e.to)
    expect(fromX).toHaveLength(5)
    expect(fromX.slice(0, 3)).toEqual(['t2', 't6', 't1'])
  })
  it('handles 5,000 pages quickly', () => {
    const pages: GraphPage[] = []
    for (let i = 0; i < 5000; i++) pages.push(page(`p${i}`, `Subject ${i} plan`, { summary: `Follows subject ${(i * 7) % 5000} plan and subject ${(i * 13) % 5000} plan closely.` }))
    const t0 = performance.now()
    const es = findMentions(model(pages))
    const ms = performance.now() - t0
    expect(es.length).toBeGreaterThan(4000)
    expect(ms).toBeLessThan(1500)
  })
})

describe('withMentions and mentionBetween', () => {
  it('adds the found mentions once, next to the links, and finds the direction', () => {
    const base = model([page('a', 'Zero trust'), page('b', 'Portal', { summary: 'zero trust' })], [])
    const m = withMentions(base)
    expect(pairs(m.edges)).toEqual(['b>a'])
    expect(withMentions(m).edges).toHaveLength(1)
    expect(mentionBetween(m, 'a', 'b')).toMatchObject({ from: 'b', to: 'a' })
    expect(withMentions(model([page('a', 'Zero trust')]))).toEqual(model([page('a', 'Zero trust')]))
  })
})
