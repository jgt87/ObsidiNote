import { describe, expect, it } from 'vitest'
import { ALL_LABELS_UP_TO, ALL_LINES_ZOOM, areaLabelSize, cardPosition, labelMode, lineMode, needsSharp, placeAreaLabels, placeLabels, SHARP_AT, SHARP_EVERY_MS, type AreaLabelInput } from './view'

describe('needsSharp: a running zoom-in is drawn again before it turns to coarse pixels', () => {
  it('draws again once the picture is stretched by 15 percent, at most every 60 ms', () => {
    expect(needsSharp(1.1, 500, 100)).toBe(false)
    expect(needsSharp(SHARP_AT, SHARP_EVERY_MS, 100)).toBe(true)
    expect(needsSharp(2, SHARP_EVERY_MS - 1, 100)).toBe(false)
  })
  it('lets a very large map stretch further before the costlier redraw', () => {
    expect(needsSharp(1.3, 500, 1000)).toBe(false)
    expect(needsSharp(1.5, 500, 1000)).toBe(true)
  })
  it('leaves zooming out to the rest: a shrunk picture stays sharp', () => {
    expect(needsSharp(0.4, 500, 100)).toBe(false)
  })
})

describe('labelMode: which pages get a name', () => {
  it('names every page on a small map, hubs only on a big one', () => {
    expect(labelMode(25, 1, 1, false)).toBe('all')
    expect(labelMode(ALL_LABELS_UP_TO, 1, 1, false)).toBe('all')
    expect(labelMode(ALL_LABELS_UP_TO + 1, 1, 1, false)).toBe('hubs')
  })
  it('names every page once zoomed in well past "fit"', () => {
    expect(labelMode(400, 0.6, 0.5, false)).toBe('hubs')
    expect(labelMode(400, 0.9, 0.5, false)).toBe('all')
  })
  // operator, 2026-11-15: "hubs" are the topic areas. With the switch on only their bold names
  // show; no page is named at rest, however small the map or far the zoom (a page shows its name
  // while pointed at, GraphStage).
  it('names no page at rest when "Labels: hubs only" is on', () => {
    expect(labelMode(10, 4, 1, true)).toBe('none')
    expect(labelMode(400, 0.5, 0.5, true)).toBe('none')
  })
})

describe('placeLabels with rectangles already taken', () => {
  it('drops a page name that would sit on a topic name', () => {
    const l = { id: 'p', text: 'Page', x: 100, y: 100, px: 11, cls: 'kg-plabel' }
    expect(placeLabels([l])).toHaveLength(1)
    expect(placeLabels([l], [[80, 80, 120, 110]])).toHaveLength(0)
  })
})

describe('lineMode: zooming in shows every topic line', () => {
  it('shows the resting lines at the fitted zoom and all of them from ALL_LINES_ZOOM on', () => {
    expect(lineMode(1, 1)).toBe('resting')
    expect(lineMode(ALL_LINES_ZOOM * 0.99, 1)).toBe('resting')
    expect(lineMode(ALL_LINES_ZOOM, 1)).toBe('all')
    expect(lineMode(3 * ALL_LINES_ZOOM, 3)).toBe('all')
  })
})

describe('placeAreaLabels: topic names sit on their own topic', () => {
  const area = (id: string, x: number, y: number, r: number, name = id): AreaLabelInput => ({ id, x, y, r, name })
  const hits = (rect: [number, number, number, number], c: AreaLabelInput) => {
    const nx = Math.max(rect[0], Math.min(c.x, rect[2]))
    const ny = Math.max(rect[1], Math.min(c.y, rect[3]))
    return Math.hypot(c.x - nx, c.y - ny) < c.r
  }

  it('centres the name on its own area, inside it, never in the gaps where topic lines run', () => {
    const [p] = placeAreaLabels([area('a', 200, 200, 80)])
    expect(p.at).toBe('center')
    expect((p.rect[0] + p.rect[2]) / 2).toBeCloseTo(200)
    expect((p.rect[1] + p.rect[3]) / 2).toBeCloseTo(200)
    for (const [x, y] of [[p.rect[0], p.rect[1]], [p.rect[2], p.rect[3]]]) expect(Math.hypot(x - 200, y - 200)).toBeLessThan(80)
  })

  it('draws no name at all on an area too small for two letters (never one wider than the area)', () => {
    expect(placeAreaLabels([area('a', 200, 200, 12, 'Networking')])).toEqual([])
    const [p] = placeAreaLabels([area('a', 200, 200, 28, 'Networking')])
    expect(p.rect[2] - p.rect[0]).toBeLessThanOrEqual(28 * 2)
  })
  it('never cuts an emoji in half when it shortens a name', () => {
    const [p] = placeAreaLabels([area('a', 200, 200, 30, 'Ab\u{1F680}\u{1F680}\u{1F680}\u{1F680}\u{1F680} notes')])
    expect(p.text.endsWith('…')).toBe(true)
    expect(/[\uD800-\uDBFF]$/.test(p.text.slice(0, -1))).toBe(false)
  })

  it('never lets two names overlap and keeps every name off other areas on a crowded map', () => {
    const areas = [area('a', 100, 100, 60), area('b', 240, 100, 60), area('c', 170, 230, 60), area('d', 320, 240, 50), area('e', 60, 260, 45)]
    const places = placeAreaLabels(areas)
    expect(places).toHaveLength(areas.length)
    for (const p of places) {
      for (const q of places) {
        if (p === q) continue
        const o = p.rect[0] < q.rect[2] && p.rect[2] > q.rect[0] && p.rect[1] < q.rect[3] && p.rect[3] > q.rect[1]
        expect(o).toBe(false)
      }
      for (const o of areas) if (o.id !== p.id) expect(hits(p.rect, o)).toBe(false)
    }
  })

  it('shortens a name wider than its area so it stays off its neighbours (code review 2026-11-14)', () => {
    const long = 'SharePoint: Finance-Reporting-Archive'
    const areas = [area('s', 200, 200, 40, long), area('n1', 290, 200, 40), area('n2', 110, 200, 40)]
    const places = placeAreaLabels(areas)
    const p = places.find((x) => x.id === 's')!
    expect(p.text.endsWith('…')).toBe(true)
    expect(p.text.length).toBeLessThan(long.length)
    for (const q of places) for (const o of areas) if (o.id !== q.id) expect(hits(q.rect, o)).toBe(false)
  })

  it('leaves out a name only when even a short one would cover another area', () => {
    const places = placeAreaLabels([area('big', 100, 100, 80, 'Security'), area('tiny', 186, 100, 4, 'Networking')])
    expect(places.map((x) => x.id)).toEqual(['big'])
    expect(places[0].text).toBe('Security')
  })

  it('estimates a wider label for a longer name', () => {
    expect(areaLabelSize('A much longer topic name').w).toBeGreaterThan(areaLabelSize('Short').w)
  })
})

describe('cardPosition: the hover card covers as few linked pages as it can', () => {
  const stage = { w: 1000, h: 700 }
  const size = { w: 280, h: 168 }
  it('goes right-below by default', () => {
    expect(cardPosition({ x: 300, y: 300 }, 20, [], stage, size)).toEqual({ left: 320, top: 320 })
  })
  it('goes to another corner when the linked pages lie right-below', () => {
    const near = [{ x: 400, y: 380 }, { x: 450, y: 420 }, { x: 500, y: 360 }]
    const p = cardPosition({ x: 300, y: 300 }, 20, near, stage, size)
    for (const n of near) {
      const inside = n.x > p.left && n.x < p.left + size.w && n.y > p.top && n.y < p.top + size.h
      expect(inside).toBe(false)
    }
  })
  it('stays on the stage', () => {
    const p = cardPosition({ x: 990, y: 690 }, 20, [], stage, size)
    expect(p.left + size.w).toBeLessThanOrEqual(stage.w - 8)
    expect(p.top + size.h).toBeLessThanOrEqual(stage.h - 8)
  })
})
