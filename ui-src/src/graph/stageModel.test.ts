import { describe, expect, it } from 'vitest'
import { buildIndex } from './graphIndex'
import { layoutGraph } from './layout'
import { areaAt, areaBundles, stageAnnouncement, drawnAtRest, edgeClass, focusEdgeClass, focusEdgeList, sharpDots, stageKey, stageLabels, type StageKeyState } from './stageModel'
import { syntheticGraph } from './synthetic'
import { FIT_BOTTOM, fitViewport, labelRect, placeLabels } from './view'

const model = syntheticGraph({ pages: 60, topics: 5, seed: 2 })
const index = buildIndex(model)
const layout = layoutGraph(model, {}, index)
const size = { w: 1200, h: 800 }
const fit = fitViewport(layout.bounds, size.w, size.h, FIT_BOTTOM)
const all = () => true
const linked = layout.dots.find((d) => (index.neighbours.get(d.id) ?? []).length > 1)!

const noMods = { shiftKey: false, altKey: false, ctrlKey: false, metaKey: false }
const key = (k: string, s: Partial<StageKeyState> = {}, mods = {}) =>
  stageKey({ key: k, ...noMods, ...mods }, { activeDot: null, hasActive: false, order: layout.dots, dots: layout.dots, visible: all, canFocusPage: true, ...s })

describe('stageKey: what a key on the map does', () => {
  it('an arrow with nothing active goes to the first page, and is always the map\'s', () => {
    expect(key('ArrowRight')).toEqual({ prevent: true, action: { kind: 'activate', id: layout.dots[0].id } })
    expect(key('ArrowRight', { order: [] })).toEqual({ prevent: true, action: null })
  })

  it('Tab walks the order and leaves the map at either end', () => {
    const [first, second] = layout.dots
    expect(key('Tab', { activeDot: first })).toEqual({ prevent: true, action: { kind: 'activate', id: second.id } })
    expect(key('Tab', { activeDot: first }, { shiftKey: true })).toBeNull()
    expect(key('Tab', { activeDot: first }, { ctrlKey: true })).toBeNull()
  })

  it('Enter opens, F focuses only when the map offers it, Esc leaves only with a page active', () => {
    const d = layout.dots[0]
    expect(key('Enter', { activeDot: d })?.action).toEqual({ kind: 'open', id: d.id })
    expect(key('f', { activeDot: d })?.action).toEqual({ kind: 'focusPage', id: d.id })
    expect(key('F', { activeDot: d, canFocusPage: false })).toBeNull()
    expect(key('f', { activeDot: d }, { ctrlKey: true })).toBeNull()
    expect(key('Escape')).toBeNull()
    expect(key('Escape', { hasActive: true })?.action).toEqual({ kind: 'leave' })
  })

  it('+, = and - zoom, 0 fits, other keys are left alone', () => {
    expect(key('+')?.action).toEqual({ kind: 'zoom', factor: 1.25 })
    expect(key('=')?.action).toEqual({ kind: 'zoom', factor: 1.25 })
    expect(key('-')?.action).toEqual({ kind: 'zoom', factor: 0.8 })
    expect(key('0')?.action).toEqual({ kind: 'fit' })
    expect(key('x')).toBeNull()
  })
})

describe('focus layer', () => {
  it('draws the focused page\'s lines once per pair, only between shown pages', () => {
    const lines = focusEdgeList(index, layout, linked.id, true, true, all)
    expect(lines.length).toBeGreaterThan(0)
    for (const { e } of lines) expect([e.from, e.to]).toContain(linked.id)
    const pairs = lines.map(({ e }) => [e.from, e.to].sort().join('|'))
    expect(new Set(pairs).size).toBe(pairs.length)
    expect(focusEdgeList(index, layout, linked.id, true, true, (id) => id === linked.id)).toEqual([])
    expect(focusEdgeList(index, layout, null, true, true, all)).toEqual([])
  })

  it('sharp dots: the neighbours of the focused page, else up to 400 search results, never the focused dot', () => {
    const near = index.neighbours.get(linked.id) ?? []
    expect(sharpDots(layout, linked.id, [...near, linked.id], null, all).map((d) => d.id)).toEqual(near)
    const ids = layout.dots.map((d) => d.id)
    expect(sharpDots(layout, null, [], ids, all)).toHaveLength(Math.min(400, ids.length))
    expect(sharpDots(layout, null, [], null, all)).toEqual([])
  })

  it('a link to the focused page that it does not return is dashed; its own links and both-way links are solid', () => {
    const seen = { in: 0, out: 0, both: 0 }
    for (const d of layout.dots) {
      const linksTo = new Set((index.out.get(d.id) ?? []).map((e) => e.to))
      const linkedFrom = new Set((index.in.get(d.id) ?? []).map((e) => e.from))
      for (const f of focusEdgeList(index, layout, d.id, true, false, all)) {
        const other = f.e.from === d.id ? f.e.to : f.e.from
        const want = linkedFrom.has(other) && !linksTo.has(other)
        expect(f.incoming, `${d.id} - ${other}`).toBe(want)
        expect(focusEdgeClass(f).includes('kg-edge--in')).toBe(want)
        if (want) seen.in++
        else if (linkedFrom.has(other)) seen.both++
        else seen.out++
      }
    }
    // The demo has all three kinds, so each branch above ran.
    expect(seen.in).toBeGreaterThan(0)
    expect(seen.out).toBeGreaterThan(0)
  })

  it('a mention is never drawn as a link to the page', () => {
    for (const d of layout.dots)
      for (const f of focusEdgeList(index, layout, d.id, false, true, all)) expect(f.incoming).toBe(false)
  })

  it('line classes by kind and strength', () => {
    expect(edgeClass({ from: 'a', to: 'b', kind: 'mention', strength: 1 } as never)).toBe('kg-edge kg-edge--mention')
    expect(edgeClass({ from: 'a', to: 'b', kind: 'link', strength: 3 } as never)).toBe('kg-edge kg-s3')
  })

  it('at rest only lines inside one area, of a kind switched on, between shown pages', () => {
    for (const e of layout.edges) {
      const a = layout.dotById.get(e.edge.from)!
      const b = layout.dotById.get(e.edge.to)!
      const on = e.edge.kind === 'mention' ? 'mentions' : 'links'
      expect(drawnAtRest(e, layout, on === 'links', on === 'mentions', all)).toBe(a.area === b.area)
      expect(drawnAtRest(e, layout, on !== 'links', on !== 'mentions', all)).toBe(false)
      expect(drawnAtRest(e, layout, true, true, (id) => id !== e.edge.to)).toBe(false)
    }
  })
})

describe('stageLabels', () => {
  const base = { layout, index, v: fit, fitK: fit.k, size, shown: null, activeDot: null, sharp: [], matches: null, hubsOnly: false, hoverArea: null }

  it('names every shown area, and hides the one under the pointer and the focused page\'s', () => {
    const r = stageLabels({ ...base, hoverArea: layout.areas[0].id, activeDot: linked })
    expect(r.areaLabels).toHaveLength(layout.areas.length)
    expect([...r.hiddenAreas].sort()).toEqual([...new Set([layout.areas[0].id, linked.area])].sort())
  })

  it('names the focused page first and largest; with hubs only nothing around it', () => {
    const sharp = sharpDots(layout, linked.id, index.neighbours.get(linked.id) ?? [], null, all)
    const r = stageLabels({ ...base, activeDot: linked, sharp })
    expect(r.labels[0]).toMatchObject({ id: linked.id, cls: 'kg-plabel kg-plabel--on', px: 13 })
    expect(stageLabels({ ...base, activeDot: linked, sharp, hubsOnly: true }).labels.map((l) => l.id)).toEqual([linked.id])
  })

  it('gives each topic name the count of its pages drawn: all of them, or the ones the filters show', () => {
    const r = stageLabels(base)
    for (const l of r.areaLabels) expect(l.count).toBe(layout.areas.find((a) => a.id === l.id)!.pageIds.length)
    const shown = new Set(layout.dots.map((d) => d.id).filter((_, i) => i % 2 === 0))
    for (const l of stageLabels({ ...base, shown }).areaLabels) {
      expect(l.count).toBe(layout.areas.find((a) => a.id === l.id)!.pageIds.filter((id) => shown.has(id)).length)
    }
  })

  it('while a page is focused, its linked pages keep their names and a faded topic name under one is hidden', () => {
    const v = { ...fit, k: fit.k * 1.6 }
    let gaveWay = 0
    for (const d of layout.dots) {
      const near = index.neighbours.get(d.id) ?? []
      if (near.length < 2) continue
      const sharp = sharpDots(layout, d.id, near, null, all)
      const r = stageLabels({ ...base, v, activeDot: d, sharp })
      const rects = r.labels.map(labelRect)
      const meets = (a: number[], b: number[]) => a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
      for (const l of r.areaLabels) if (!r.hiddenAreas.has(l.id)) expect(rects.some((x) => meets(x, l.rect)), `${l.text} under a page name`).toBe(false)
      for (const g of r.groupLabels) if (!g.hidden) expect(rects.some((x) => meets(x, g.rect))).toBe(false)
      // At rest the same page names would have given way to the topic names instead.
      const atRest = new Set(placeLabels(r.labels, r.areaLabels.map((l) => l.rect)).map((l) => l.id))
      if (r.labels.some((l) => !atRest.has(l.id))) gaveWay++
    }
    // Some focused page in the demo had a linked page whose name lay on a topic name.
    expect(gaveWay).toBeGreaterThan(0)
  })

  it('names no page at rest with hubs only, and none off screen', () => {
    expect(stageLabels({ ...base, hubsOnly: true }).labels).toEqual([])
    expect(stageLabels({ ...base, v: { ...fit, x: fit.x + 100000 } }).labels).toEqual([])
  })

  it('names each page at most once when zoomed in', () => {
    const { labels } = stageLabels({ ...base, v: { ...fit, k: fit.k * 3 } })
    expect(labels.length).toBeGreaterThan(0)
    expect(new Set(labels.map((l) => l.id)).size).toBe(labels.length)
  })
})

describe('areaBundles and stageAnnouncement', () => {
  const lines = [{ a: 'A', b: 'B' }, { a: 'B', b: 'C' }, { a: 'C', b: 'D' }]
  it('a focused page shows every topic line of its area, while links are shown', () => {
    expect(areaBundles(lines, 'B', true)).toEqual([{ a: 'A', b: 'B' }, { a: 'B', b: 'C' }])
    expect(areaBundles(lines, 'B', false)).toEqual([])
    expect(areaBundles(lines, null, true)).toEqual([])
  })
  it('a screen reader hears the page, where it is, its links and the keys', () => {
    expect(stageAnnouncement('Zero trust', 'Index › Security', 3, true)).toBe('Zero trust, Index › Security, 3 linked pages. Enter opens, F focuses on this page.')
    expect(stageAnnouncement('Alone', 'Index › Unfiled', 1, false)).toBe('Alone, Index › Unfiled, 1 linked page. Enter opens.')
  })
})

describe('areaAt', () => {
  it('finds the area under a screen point, and none outside every area', () => {
    const a = layout.areas[0]
    expect(areaAt(layout.areas, fit, (a.x - fit.x) * fit.k, (a.y - fit.y) * fit.k)).toBe(a.id)
    expect(areaAt(layout.areas, fit, -10000, -10000)).toBeNull()
  })
})
