import { describe, expect, it } from 'vitest'
import { buildIndex } from './graphIndex'
import { bundleEdges, controlPoint, crossesAreas, edgePath, layoutGraph, packAreas, topicOrder } from './layout'
import { normalizeGraph, UNFILED_ID, type GraphModel } from './model'
import { syntheticGraph } from './synthetic'

function checkInvariants(model: GraphModel) {
  const layout = layoutGraph(model)
  const index = buildIndex(model)
  // no overlap of topic areas
  for (let i = 0; i < layout.areas.length; i++) {
    for (let j = i + 1; j < layout.areas.length; j++) {
      const a = layout.areas[i]
      const b = layout.areas[j]
      expect(Math.hypot(a.x - b.x, a.y - b.y)).toBeGreaterThanOrEqual(a.r + b.r)
    }
  }
  // every page drawn once, inside its own (primary topic) area
  expect(layout.dots).toHaveLength(model.pages.length)
  const areaById = new Map(layout.areas.map((a) => [a.id, a]))
  for (const d of layout.dots) {
    const page = index.pageById.get(d.id)!
    expect(d.area).toBe(page.topicIds[0] ?? UNFILED_ID)
    const area = areaById.get(d.area)!
    expect(Math.hypot(d.x - area.x, d.y - area.y) + d.r).toBeLessThanOrEqual(area.r)
  }
  // bounds hold every area
  for (const a of layout.areas) {
    expect(a.x - a.r).toBeGreaterThanOrEqual(layout.bounds.x)
    expect(a.y + a.r).toBeLessThanOrEqual(layout.bounds.y + layout.bounds.h)
  }
  return layout
}

describe('layoutGraph', () => {
  it('is deterministic: the same model gives the same picture', () => {
    const a = layoutGraph(syntheticGraph({ pages: 100 }))
    const b = layoutGraph(syntheticGraph({ pages: 100 }))
    expect(JSON.stringify(b.areas)).toBe(JSON.stringify(a.areas))
    expect(JSON.stringify(b.dots)).toBe(JSON.stringify(a.dots))
    expect(b.edges.map((e) => e.d)).toEqual(a.edges.map((e) => e.d))
  })

  it('does not depend on the order pages and edges arrive in', () => {
    const m = syntheticGraph({ pages: 80 })
    const shuffled: GraphModel = { ...m, pages: [...m.pages].reverse(), edges: [...m.edges].reverse(), topics: [...m.topics].reverse() }
    const a = layoutGraph(m)
    const b = layoutGraph(shuffled)
    expect(b.areas.map((x) => [x.id, x.x, x.y, x.r])).toEqual(a.areas.map((x) => [x.id, x.x, x.y, x.r]))
    const pos = (l: typeof a) => [...l.dots].sort((p, q) => (p.id < q.id ? -1 : 1)).map((d) => [d.id, d.x, d.y])
    expect(pos(b)).toEqual(pos(a))
  })

  it('keeps areas apart and every page inside its area (100 pages, 6 topics)', () => {
    const layout = checkInvariants(syntheticGraph({ pages: 100, topics: 6 }))
    expect(layout.areas.map((a) => a.name)).toContain('Unfiled')
  })

  it('holds the same rules for 1,000 pages and many topics', () => {
    checkInvariants(syntheticGraph({ pages: 1000, topics: 18, seed: 3 }))
  })

  it('holds for tiny and lopsided graphs', () => {
    checkInvariants(syntheticGraph({ pages: 1, topics: 1 }))
    checkInvariants(syntheticGraph({ pages: 3, topics: 6 }))
    checkInvariants(syntheticGraph({ pages: 400, topics: 2, seed: 11 }))
    const empty = layoutGraph(normalizeGraph({}))
    expect(empty.areas).toHaveLength(0)
    expect(empty.bounds.w).toBeGreaterThan(0)
  })

  it('draws hubs bigger and unlinked pages small', () => {
    const m = syntheticGraph({ pages: 100 })
    const layout = layoutGraph(m)
    const hub = m.pages.find((p) => p.isHub)!
    const loose = m.pages.find((p) => p.unlinked)!
    expect(layout.dotById.get(hub.id)!.r).toBeGreaterThan(layout.dotById.get(loose.id)!.r)
    expect(layout.dotById.get(loose.id)!.unlinked).toBe(true)
  })

  it('places a subtopic next to its parent', () => {
    const m = syntheticGraph({ pages: 100 })
    const layout = layoutGraph(m)
    const sub = layout.areas.find((a) => a.topic?.parent)!
    const parent = layout.areas.find((a) => a.id === sub.topic!.parent)!
    const others = layout.areas.filter((a) => a !== sub && a !== parent)
    const gap = (a: typeof sub, b: typeof sub) => Math.hypot(a.x - b.x, a.y - b.y) - a.r - b.r
    // Positions are rounded to 0.1, so two areas both tangent to the subtopic can differ by ~0.1.
    expect(gap(sub, parent)).toBeLessThanOrEqual(Math.min(...others.map((o) => gap(sub, o))) + 0.5)
  })

  it('gives Unfiled only the room its pages need, and puts it at the rim', () => {
    const m = syntheticGraph({ pages: 100, topics: 6 })
    const layout = layoutGraph(m)
    const unfiled = layout.areas.find((a) => a.id === UNFILED_ID)!
    const topics = layout.areas.filter((a) => a.id !== UNFILED_ID)
    expect(unfiled.r).toBeLessThan(Math.min(...topics.map((a) => a.r)))
    // Farther from the picture's centre than the average topic.
    const cx = layout.bounds.x + layout.bounds.w / 2
    const cy = layout.bounds.y + layout.bounds.h / 2
    const dist = (a: { x: number; y: number }) => Math.hypot(a.x - cx, a.y - cy)
    expect(dist(unfiled)).toBeGreaterThan(topics.reduce((s, a) => s + dist(a), 0) / topics.length)
  })

  it('labels areas with name and "N pages · subjects"', () => {
    const layout = layoutGraph(syntheticGraph({ pages: 100 }))
    const sec = layout.areas.find((a) => a.name === 'Security')!
    expect(sec.sub).toMatch(/^\d+ pages · zero trust, identity, policies$/)
  })
})

describe('topicOrder', () => {
  it('walks the tree depth first, siblings by path', () => {
    const t = (id: string, path: string, parent: string | null) => ({ id, name: path, path, parent, pageCount: 0, subjects: '' })
    const order = topicOrder([t('c', 'B / x', 'b'), t('b', 'B', null), t('a', 'A', null), t('d', 'A / y', 'a')])
    expect(order.map((x) => x.id)).toEqual(['a', 'd', 'b', 'c'])
  })
})

describe('packAreas', () => {
  it('never overlaps circles', () => {
    const radii = [120, 40, 90, 60, 60, 200, 30, 30, 75]
    const placed = packAreas(radii, radii.map(() => null), 1.45, 10)
    for (let i = 0; i < placed.length; i++)
      for (let j = i + 1; j < placed.length; j++)
        expect(Math.hypot(placed[i].x - placed[j].x, placed[i].y - placed[j].y)).toBeGreaterThanOrEqual(placed[i].r + placed[j].r + 10 - 1e-6)
  })
})

describe('the areas fill the stage shape', () => {
  it('gives bounds close to the stage aspect, so the picture does not float in the middle', () => {
    for (const pages of [30, 100, 1000]) {
      for (const aspect of [1.45, 1.8]) {
        const l = layoutGraph(syntheticGraph({ pages, topics: pages > 300 ? 12 : 6 }), { aspect })
        const ratio = l.bounds.w / l.bounds.h
        expect(ratio / aspect).toBeGreaterThan(0.85)
        // 1.25, was 1.15 (2026-11-14): the Unfiled area is now only as big as its pages need, so it
        // no longer evens out a picture that a subtopic beside its parent made wide (100 pages:
        // 1.18). Fitting to the stage absorbs the difference as a little space above and below.
        expect(ratio / aspect).toBeLessThan(1.25)
      }
    }
  })
})

describe('edges', () => {
  it('curve: the control point sits perpendicular to the midpoint', () => {
    const [cx, cy] = controlPoint(0, 0, 100, 0)
    expect(cx).toBeCloseTo(50)
    expect(cy).toBeCloseTo(18)
    expect(edgePath(0, 0, 100, 0)).toBe('M0 0Q50 18 100 0')
  })
})

describe('links between topics (bundleEdges)', () => {
  const m = syntheticGraph({ pages: 100, topics: 6 })
  const layout = layoutGraph(m)
  const cross = layout.edges.filter((e) => e.edge.kind !== 'mention' && crossesAreas(layout, e.edge.from, e.edge.to))

  it('draws one line per pair of topics, counting every link between their pages', () => {
    const bundles = bundleEdges(layout)
    expect(cross.length).toBeGreaterThan(0)
    expect(bundles.reduce((s, b) => s + b.count, 0)).toBe(cross.length)
    const keys = bundles.map((b) => `${b.a}|${b.b}`)
    expect(new Set(keys).size).toBe(keys.length)
    for (const b of bundles) expect(b.a < b.b).toBe(true)
  })

  it('runs from rim to rim, not through the areas it joins', () => {
    const area = new Map(layout.areas.map((a) => [a.id, a]))
    for (const b of bundleEdges(layout)) {
      const [, x1, y1] = /^M(-?[\d.]+) (-?[\d.]+)/.exec(b.d)!.map(Number)
      const A = area.get(b.a)!
      expect(Math.abs(Math.hypot(x1 - A.x, y1 - A.y) - A.r)).toBeLessThan(0.2)
    }
  })

  it('counts only links between pages that are shown, and never mentions', () => {
    const one = cross[0].edge
    const shown = new Set(m.pages.map((p) => p.id).filter((id) => id !== one.from))
    const all = bundleEdges(layout).reduce((s, b) => s + b.count, 0)
    const fewer = bundleEdges(layout, shown).reduce((s, b) => s + b.count, 0)
    expect(fewer).toBeLessThan(all)
    const onlyMentions = { ...layout, edges: layout.edges.map((e) => ({ ...e, edge: { ...e.edge, kind: 'mention' as const } })) }
    expect(bundleEdges(onlyMentions)).toEqual([])
  })
})
