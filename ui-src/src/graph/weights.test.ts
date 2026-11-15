import { describe, expect, it } from 'vitest'
import { dotRadius } from './layout'
import type { GraphEdge, GraphPage, Strength } from './model'
import { applyLinkWeights, hubIds, HUB_MIN_IN, linkWeights } from './weights'

// Invented example data only.
const e = (from: string, to: string, strength: Strength = 1, kind: 'link' | 'mention' = 'link'): GraphEdge => ({ from, to, strength, kind })
const ids = (n: number) => Array.from({ length: n }, (_, i) => `p${i + 1}`)
function page(id: string): GraphPage {
  return {
    id, title: id, topicIds: [], bucket: 'Notes', section: 'Notes', tags: [], kind: 'note', links: 0, linkedFrom: 0, weight: 0, isHub: false, unlinked: true, sourceId: 'obsidinote', origin: '',
    summary: '', onenoteUrl: '', modified: '', readOnly: false, aliases: [], site: '', archived: false, url: '',
  }
}

describe('linkWeights', () => {
  it('counts links to a page fully and its own links half, by strength', () => {
    const w = linkWeights(['a', 'b', 'c'], [e('a', 'b', 3), e('c', 'b', 1)])
    expect(w.get('b')).toEqual({ links: 2, linkedFrom: 2, weight: 4 })
    expect(w.get('a')).toEqual({ links: 1, linkedFrom: 0, weight: 1.5 })
    expect(w.get('c')).toEqual({ links: 1, linkedFrom: 0, weight: 0.5 })
  })

  it('makes a page four others link to heavier than a new page with five links of its own', () => {
    const w = linkWeights(ids(10), [e('p1', 'p2'), e('p1', 'p3'), e('p1', 'p4'), e('p1', 'p5'), e('p1', 'p6'), e('p7', 'p10'), e('p8', 'p10'), e('p9', 'p10'), e('p2', 'p10')])
    expect(w.get('p10')!.weight).toBeGreaterThan(w.get('p1')!.weight)
  })

  it('counts a page that links back once as a neighbour', () => {
    const w = linkWeights(['a', 'b'], [e('a', 'b', 2), e('b', 'a', 2)])
    expect(w.get('a')!.links).toBe(1)
    expect(w.get('b')!.links).toBe(1)
  })

  it('leaves mentions, self-links, repeated links and unknown pages out', () => {
    const w = linkWeights(['a', 'b'], [e('a', 'b', 1, 'mention'), e('a', 'a', 3), e('a', 'x', 3), e('a', 'b', 2), e('a', 'b', 3)])
    expect(w.get('b')).toEqual({ links: 1, linkedFrom: 1, weight: 2 })
  })
})

describe('hubIds', () => {
  it('needs at least HUB_MIN_IN pages linking to it', () => {
    const edges = Array.from({ length: HUB_MIN_IN - 1 }, (_, i) => e(`p${i + 2}`, 'p1', 3))
    expect(hubIds(linkWeights(ids(10), edges)).size).toBe(0)
    edges.push(e('p9', 'p1', 1))
    expect([...hubIds(linkWeights(ids(10), edges))]).toEqual(['p1'])
  })

  it('is relative: about 5% of a big vault, not every page with a few links', () => {
    // 200 pages; 40 of them are linked to by 3 others, 4 by 8 others.
    const all = ids(200)
    const edges: GraphEdge[] = []
    for (let i = 0; i < 40; i++) for (let k = 1; k <= 3; k++) edges.push(e(all[100 + ((i * 3 + k) % 100)], all[i]))
    for (let i = 40; i < 44; i++) for (let k = 1; k <= 8; k++) edges.push(e(all[100 + ((i * 8 + k) % 100)], all[i]))
    const hubs = hubIds(linkWeights(all, edges))
    expect(hubs.size).toBeLessThanOrEqual(10)
    for (let i = 40; i < 44; i++) expect(hubs.has(all[i])).toBe(true)
  })
})

describe('applyLinkWeights and the dot size', () => {
  it('sets the page fields and grows the dot smoothly with the weight', () => {
    const pages = ids(6).map(page)
    applyLinkWeights(pages, [e('p2', 'p1', 3), e('p3', 'p1', 3), e('p4', 'p1', 3), e('p5', 'p1', 3), e('p2', 'p3', 1)])
    const [p1, p2, , , , p6] = pages
    expect(p1).toMatchObject({ links: 4, linkedFrom: 4, weight: 12, isHub: true, unlinked: false })
    expect(p6).toMatchObject({ links: 0, weight: 0, isHub: false, unlinked: true })
    expect(dotRadius(p6)).toBe(3)
    expect(dotRadius(p2)).toBeGreaterThan(3)
    expect(dotRadius(p1)).toBeGreaterThan(dotRadius(p2))
  })

  it('has no jump: one more link changes the radius by less than a pixel', () => {
    const r = (weight: number) => dotRadius({ ...page('x'), weight, links: 1, unlinked: false })
    let prev = r(0.5)
    for (let w = 1; w <= 40; w += 0.5) {
      const r = dotRadius({ ...page('x'), weight: w, links: 1, unlinked: false })
      expect(r - prev).toBeLessThan(1)
      expect(r).toBeLessThanOrEqual(11)
      prev = r
    }
  })
})
