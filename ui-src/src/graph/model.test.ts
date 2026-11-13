import { describe, expect, it } from 'vitest'
import { fetchGraph, graphUrl } from './graphApi'
import { buildIndex, indexPath } from './graphIndex'
import { clampStrength, normalizeGraph } from './model'
import { syntheticGraph } from './synthetic'
import { fitViewport, focusSet, MAX_FIT, nextInDirection, placeLabels, searchPages, stepLinked, zoomAt } from './view'

describe('normalizeGraph', () => {
  it('repairs PowerShell one-item lists and nulls', () => {
    const m = normalizeGraph({
      source: { kind: 'notebook', id: 'n', name: 'Team', readOnly: true },
      topics: { id: 't', name: 'T', path: 'T', parent: null, pageCount: 1, subjects: 's' },
      pages: { id: 'p', title: 'P', topicIds: 't', links: 0 },
      edges: null,
    })
    expect(m.topics).toHaveLength(1)
    expect(m.pages[0].topicIds).toEqual(['t'])
    expect(m.pages[0].readOnly).toBe(true)
    expect(m.edges).toEqual([])
  })

  it('drops edges to unknown pages, self-loops and duplicates; clamps strength', () => {
    const m = normalizeGraph({
      pages: [{ id: 'a' }, { id: 'b' }],
      edges: [
        { from: 'a', to: 'b', strength: 9 },
        { from: 'a', to: 'b', strength: 1 },
        { from: 'a', to: 'a', strength: 2 },
        { from: 'a', to: 'x', strength: 2 },
        { from: 'b', to: 'a', strength: 0, kind: 'mention' },
      ],
    })
    expect(m.edges).toEqual([
      { from: 'a', to: 'b', strength: 3, kind: 'link' },
      { from: 'b', to: 'a', strength: 1, kind: 'mention' },
    ])
    expect(clampStrength('2')).toBe(2)
    expect(clampStrength(undefined)).toBe(1)
  })

  it('removes unknown topic ids and parents', () => {
    const m = normalizeGraph({ topics: [{ id: 't', parent: 'gone' }], pages: [{ id: 'p', topicIds: ['zz', 't'] }] })
    expect(m.topics[0].parent).toBeNull()
    expect(m.pages[0].topicIds).toEqual(['t'])
  })
})

describe('syntheticGraph', () => {
  it('is seeded and has about the asked size', () => {
    const a = syntheticGraph({ pages: 100, topics: 6 })
    expect(a.pages).toHaveLength(100)
    expect(a.topics).toHaveLength(6)
    expect(JSON.stringify(syntheticGraph({ pages: 100, topics: 6 }))).toBe(JSON.stringify(a))
    expect(a.pages.some((p) => p.unlinked)).toBe(true)
    expect(a.pages.some((p) => p.isHub)).toBe(true)
    expect(a.edges.some((e) => e.kind === 'mention')).toBe(true)
    // it survives the server-side normalizer unchanged in size
    expect(normalizeGraph(a).edges).toHaveLength(a.edges.length)
  })
  it('marks a connected notebook read only', () => {
    const m = syntheticGraph({ pages: 10, readOnly: true })
    expect(m.source.readOnly).toBe(true)
    expect(m.pages.every((p) => p.readOnly)).toBe(true)
  })
})

describe('graphApi', () => {
  it('builds the route for a vault or a notebook', () => {
    expect(graphUrl()).toBe('/api/graph')
    expect(graphUrl({ vault: 'v 1' })).toBe('/api/graph?vault=v+1')
    expect(graphUrl({ notebook: 'n' })).toBe('/api/graph?notebook=n')
  })
  it('sends the header and normalizes the answer; turns errors into messages', async () => {
    let seen: RequestInit | undefined
    const ok = (async (_url: string, init?: RequestInit) => {
      seen = init
      return new Response(JSON.stringify({ pages: { id: 'p' } }), { status: 200 })
    }) as unknown as typeof fetch
    const m = await fetchGraph({ vault: 'v' }, undefined, ok)
    expect((seen?.headers as Record<string, string>)['X-ObsidiNote']).toBe('1')
    expect(m.pages).toHaveLength(1)
    const bad = (async () => new Response(JSON.stringify({ error: 'No vault' }), { status: 404 })) as unknown as typeof fetch
    await expect(fetchGraph({}, undefined, bad)).rejects.toThrow('No vault')
    const down = (async () => {
      throw new TypeError('fetch failed')
    }) as unknown as typeof fetch
    await expect(fetchGraph({}, undefined, down)).rejects.toThrow(/not answering/)
  })
})

describe('index and view helpers', () => {
  const m = syntheticGraph({ pages: 100 })
  const index = buildIndex(m)

  it('lists neighbours strongest first and the index path', () => {
    const hub = m.pages.find((p) => p.isHub)!
    const ns = index.neighbours.get(hub.id)!
    expect(ns.length).toBeGreaterThan(0)
    expect(focusSet(index, hub.id).size).toBe(ns.length + 1)
    expect(indexPath(index, 't6')).toBe('Index › Security › Networking')
  })

  it('steps through the linked pages and wraps', () => {
    const hub = m.pages.find((p) => p.isHub)!
    const ns = index.neighbours.get(hub.id)!
    expect(stepLinked(index, hub.id, hub.id, 1)).toBe(ns[0])
    expect(stepLinked(index, hub.id, hub.id, -1)).toBe(ns[ns.length - 1])
    expect(stepLinked(index, hub.id, ns[ns.length - 1], 1)).toBe(hub.id)
    const loose = m.pages.find((p) => p.unlinked)!
    expect(stepLinked(index, loose.id, loose.id, 1)).toBeNull()
  })

  it('searches titles first, then topic paths', () => {
    expect(index.pageById.get(searchPages(index, 'zero')[0])!.title).toBe('Zero-trust networking')
    expect(searchPages(index, 'networking').length).toBeGreaterThan(1)
    expect(searchPages(index, '   ')).toEqual([])
    // Filters alone list every page they hold (src/search/query.ts has the full cases).
    expect(new Set(searchPages(index, 'is:hub'))).toEqual(new Set(m.pages.filter((p) => p.isHub).map((p) => p.id)))
    expect(searchPages(index, 'topic:security').every((id) => index.pageById.get(id)!.topicIds.some((t) => index.topicById.get(t)!.path.startsWith('Security')))).toBe(true)
  })

  it('moves by arrow to the nearest dot in that direction', () => {
    const dots = [
      { id: 'c', area: 'a', x: 0, y: 0, r: 3, hub: false, unlinked: false },
      { id: 'r', area: 'a', x: 10, y: 1, r: 3, hub: false, unlinked: false },
      { id: 'far', area: 'a', x: 40, y: 0, r: 3, hub: false, unlinked: false },
      { id: 'u', area: 'a', x: 0, y: -10, r: 3, hub: false, unlinked: false },
    ]
    expect(nextInDirection(dots, dots[0], 'right')!.id).toBe('r')
    expect(nextInDirection(dots, dots[0], 'up')!.id).toBe('u')
    expect(nextInDirection(dots, dots[0], 'left')).toBeNull()
    expect(nextInDirection(dots, dots[0], 'right', (id) => id !== 'r')!.id).toBe('far')
  })

  it('drops labels that would overlap a label with higher priority', () => {
    const l = (id: string, x: number, y: number) => ({ id, text: 'Some page title', x, y, px: 12, cls: '' })
    const kept = placeLabels([l('focus', 100, 100), l('overlaps', 110, 104), l('clear', 100, 140), l('far', 400, 100)])
    expect(kept.map((k) => k.id)).toEqual(['focus', 'clear', 'far'])
  })

  it('fits and zooms around a point', () => {
    const v = fitViewport({ x: 0, y: 0, w: 800, h: 400 }, 400, 400)
    expect(v.k).toBe(0.5)
    expect(v.y).toBe(-200)
    const z = zoomAt(v, 2, 100, 100, 0.1)
    expect(z.k).toBe(1)
    // the world point under the cursor stays put
    expect(v.x + 100 / v.k).toBeCloseTo(z.x + 100 / z.k)
  })

  it('does not blow a small graph up past MAX_FIT, and centres it', () => {
    const v = fitViewport({ x: 0, y: 0, w: 100, h: 50 }, 1000, 500)
    expect(v.k).toBe(MAX_FIT)
    expect(v.x + 500 / v.k).toBeCloseTo(50)
    expect(v.y + 250 / v.k).toBeCloseTo(25)
  })
})
