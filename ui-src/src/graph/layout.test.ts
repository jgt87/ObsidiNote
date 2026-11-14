import { describe, expect, it } from 'vitest'
import { buildIndex } from './graphIndex'
import { AREA_GAP, BUNDLE_SPREAD, bundleEdges, controlPoint, crossesAreas, edgePath, layoutGraph, onePerPair, packAreas, packOrder, RESTING_BUNDLES, restingBundles, spreadEnds, topicOrder } from './layout'
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

describe('placing linked topics next to each other', () => {
  it('packOrder: the strongest links first, a subtopic only after its parent, Unfiled last', () => {
    // 0 root, 1 root, 2 root (child 3), 4 outer; 0-2 strongly linked, 1 loosely to 0.
    const W = [
      [0, 1, 9, 0, 0],
      [1, 0, 0, 0, 0],
      [9, 0, 0, 0, 0],
      [0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0],
    ]
    expect(packOrder([null, null, null, 2, null], W, [false, false, false, false, true])).toEqual([0, 2, 3, 1, 4])
  })

  it('puts two topics with many links between them side by side, so their line is straight', () => {
    // Four topics in tree order A, B, C, D; only A and D are linked (strongly).
    const pages: Record<string, unknown>[] = []
    const edges: Record<string, unknown>[] = []
    for (const t of ['A', 'B', 'C', 'D']) for (let k = 0; k < 8; k++) pages.push({ id: `${t}${k}`, title: `${t} ${k}`, topicIds: [t] })
    for (let k = 0; k < 6; k++) edges.push({ from: `A${k}`, to: `D${k}`, strength: 3 })
    const m = normalizeGraph({ source: {}, topics: ['A', 'B', 'C', 'D'].map((id) => ({ id, name: id, path: id })), pages, edges })
    const l = layoutGraph(m)
    const A = l.areas.find((a) => a.id === 'A')!
    const D = l.areas.find((a) => a.id === 'D')!
    expect(Math.hypot(A.x - D.x, A.y - D.y)).toBeCloseTo(A.r + D.r + AREA_GAP, 0)
    expect(bundleEdges(l).every((b) => b.d.split('C').length === 2)).toBe(true)
  })

  it('keeps the lines shown at rest straight in the demo vaults (ratchet: measured 3 bent of 48)', () => {
    let bent = 0
    for (const opts of [{ pages: 25, topics: 5 }, { pages: 100, topics: 6 }, { pages: 400, topics: 14 }, { pages: 200, topics: 10, seed: 3 }, { pages: 60, topics: 8, seed: 7 }, { pages: 800, topics: 20, seed: 5 }]) {
      bent += restingBundles(bundleEdges(layoutGraph(syntheticGraph(opts)))).filter((b) => b.d.split('C').length > 2).length
    }
    expect(bent).toBeLessThanOrEqual(3)
  })
})

describe('the areas fill the stage shape', () => {
  it('gives bounds close to the stage aspect, so the picture does not float in the middle', () => {
    for (const pages of [30, 100, 1000]) {
      for (const aspect of [1.45, 1.8]) {
        const l = layoutGraph(syntheticGraph({ pages, topics: pages > 300 ? 12 : 6 }), { aspect })
        const ratio = l.bounds.w / l.bounds.h
        // 0.8, was 0.85 (2026-11-14): areas are now placed so that topic lines do not pass other
        // topics (CROSS_PENALTY), which may cost a little width on a very wide stage (1.8: 0.83).
        expect(ratio / aspect).toBeGreaterThan(0.8)
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

  it('draws two pages that link each other as one line, with the stronger strength', () => {
    const drawn = onePerPair([
      { from: 'a', to: 'b', strength: 1, kind: 'link' },
      { from: 'b', to: 'a', strength: 3, kind: 'link' },
      { from: 'a', to: 'b', strength: 1, kind: 'mention' },
      { from: 'a', to: 'c', strength: 2, kind: 'link' },
    ])
    expect(drawn.map((e) => `${e.kind}:${e.from}>${e.to}:${e.strength}`)).toEqual(['link:a>b:3', 'mention:a>b:1', 'link:a>c:2'])
  })

  it('a model with a mutual link lays out one line for it', () => {
    const m = normalizeGraph({
      source: { kind: 'vault' },
      topics: [{ id: 't', name: 'T', path: 'T' }],
      pages: [{ id: 'a', title: 'A', topicIds: ['t'] }, { id: 'b', title: 'B', topicIds: ['t'] }],
      edges: [{ from: 'a', to: 'b', strength: 2 }, { from: 'b', to: 'a', strength: 1 }],
    })
    expect(layoutGraph(m).edges.length).toBe(1)
    expect(m.pages.map((p) => p.links)).toEqual([1, 1])
  })
})

/** The cubic pieces of an SVG path "M x y C ... C ...": [start, c1, c2, end] per piece. */
function curvePoints(d: string): { x: number; y: number }[][] {
  const nums = d.replace(/^M/, '').split(/[C ]/).filter(Boolean).map(Number)
  const pieces: { x: number; y: number }[][] = []
  let x = nums[0]
  let y = nums[1]
  for (let i = 2; i + 5 < nums.length; i += 6) {
    pieces.push([{ x, y }, { x: nums[i], y: nums[i + 1] }, { x: nums[i + 2], y: nums[i + 3] }, { x: nums[i + 4], y: nums[i + 5] }])
    x = nums[i + 4]
    y = nums[i + 5]
  }
  return pieces
}

/** Points along a path of cubic pieces (40 per piece). */
function sampleCurve(d: string): { x: number; y: number }[] {
  const out: { x: number; y: number }[] = []
  for (const [p0, p1, p2, p3] of curvePoints(d)) {
    for (let k = 0; k <= 40; k++) {
      const t = k / 40
      const u = 1 - t
      out.push({
        x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
        y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y,
      })
    }
  }
  return out
}

describe('spreadEnds', () => {
  it('moves close angles apart around their middle and leaves lone ones alone', () => {
    const out = spreadEnds([1, 1.01, 3], 0.2)
    expect(out[0]).toBeCloseTo(0.905)
    expect(out[1]).toBeCloseTo(1.105)
    expect(out[2]).toBe(3)
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
    // The width follows the summed strength (core 3, related 2, loose 1).
    expect(bundles.reduce((s, b) => s + b.weight, 0)).toBe(cross.reduce((s, e) => s + e.edge.strength, 0))
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

  it('starts each line on the side facing the other area, at a right angle, ends spread along the rim', () => {
    const area = new Map(layout.areas.map((a) => [a.id, a]))
    const bundles = bundleEdges(layout)
    for (const b of bundles) {
      const A = area.get(b.a)!
      const B = area.get(b.b)!
      // Facing the other area, unless the line has to bend around one in between.
      if (curvePoints(b.d).length === 1) {
        const facing = Math.atan2(B.y - A.y, B.x - A.x)
        expect(Math.abs(Math.atan2(Math.sin(b.angleA - facing), Math.cos(b.angleA - facing)))).toBeLessThan(Math.PI / 4)
      }
      // cubic path whose first control point lies along the rim normal
      const n = /^M(-?[\d.]+) (-?[\d.]+)C(-?[\d.]+) (-?[\d.]+)/.exec(b.d)!.map(Number)
      const dir = Math.atan2(n[4] - n[2], n[3] - n[1])
      expect(Math.abs(Math.atan2(Math.sin(dir - b.angleA), Math.cos(dir - b.angleA)))).toBeLessThan(0.05)
    }
    // no two ends on one rim closer than BUNDLE_SPREAD (arc length), allowing rounding
    for (const A of layout.areas) {
      const at = bundles.flatMap((b) => (b.a === A.id ? [b.angleA] : b.b === A.id ? [b.angleB] : []))
      for (let i = 0; i < at.length; i++)
        for (let j = i + 1; j < at.length; j++) {
          const d = Math.abs(Math.atan2(Math.sin(at[i] - at[j]), Math.cos(at[i] - at[j])))
          expect(d * A.r).toBeGreaterThan(Math.min(BUNDLE_SPREAD, (Math.PI * 2 * A.r) / at.length) - 0.5)
        }
    }
  })

  it('never passes under a third topic: lines bend around the areas in their way', () => {
    for (const opts of [{ pages: 100, topics: 6 }, { pages: 400, topics: 14 }, { pages: 200, topics: 10, seed: 3 }, { pages: 60, topics: 8, seed: 7 }]) {
      const l = layoutGraph(syntheticGraph(opts))
      let bent = 0
      for (const b of bundleEdges(l)) {
        if (curvePoints(b.d).length > 1) bent++
        for (const p of sampleCurve(b.d)) {
          for (const a of l.areas) {
            if (a.id === b.a || a.id === b.b) continue
            expect(Math.hypot(p.x - a.x, p.y - a.y)).toBeGreaterThan(a.r)
          }
        }
      }
      if (opts.pages === 400) expect(bent).toBeGreaterThan(0) // the case is really exercised
    }
  })

  it('shows only the heaviest lines at rest', () => {
    const all = bundleEdges(layoutGraph(syntheticGraph({ pages: 400, topics: 14 })))
    expect(all.length).toBeGreaterThan(RESTING_BUNDLES)
    const rest = restingBundles(all)
    expect(rest.length).toBe(RESTING_BUNDLES)
    const lightestShown = Math.min(...rest.map((b) => b.weight))
    expect(all.filter((b) => !rest.includes(b)).every((b) => b.weight <= lightestShown)).toBe(true)
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
