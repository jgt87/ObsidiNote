import { describe, expect, it } from 'vitest'
import { duplicateIds, nameKey } from './duplicates'
import type { GraphPage } from './model'

const page = (id: string, title: string, over: Partial<GraphPage> = {}): GraphPage =>
  ({ id, title, aliases: [], archived: false, topicIds: [], bucket: 'Notes', section: 'Notes', tags: [], kind: 'concept', links: 0, linkedFrom: 0, weight: 0, isHub: false, unlinked: true, sourceId: '', origin: '', summary: '', onenoteUrl: '', modified: '', readOnly: false, site: '', url: '', ...over }) as GraphPage

describe('possible duplicates', () => {
  it('compares names without case, accents, punctuation or extra spaces', () => {
    expect(nameKey('  Zero-Trust   Networking! ')).toBe('zero trust networking')
    expect(nameKey('Café plan')).toBe(nameKey('cafe PLAN'))
  })
  it('finds pages that share a title or an alias, and only those', () => {
    const ids = duplicateIds([page('a', 'Zero trust'), page('b', 'zero-trust'), page('c', 'Partner portal'), page('d', 'Portal', { aliases: ['Partner portal'] }), page('e', 'Alone')])
    expect([...ids].sort()).toEqual(['a', 'b', 'c', 'd'])
  })
  it('leaves out archived pages unless shown, day pages and untitled pages', () => {
    const pages = [page('a', 'Plan'), page('b', 'Plan', { archived: true }), page('c', '2026-11-17', { kind: 'log' }), page('d', '2026-11-17', { kind: 'log' }), page('e', 'Untitled page'), page('f', 'Untitled page')]
    expect([...duplicateIds(pages)]).toEqual([])
    expect([...duplicateIds(pages, true)].sort()).toEqual(['a', 'b'])
  })
  it('does not count a page twice for its own alias', () => {
    expect([...duplicateIds([page('a', 'Plan', { aliases: ['plan'] })])]).toEqual([])
  })
})
