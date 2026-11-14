import { describe, expect, it } from 'vitest'
import { ALL_LABELS_UP_TO, areaLabelSize, cardPosition, labelMode, placeAreaLabels, placeLabels, type AreaLabelInput } from './view'

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
  it('keeps hubs only when "Labels: hubs only" is on', () => {
    expect(labelMode(10, 4, 1, true)).toBe('hubs')
  })
})

describe('placeLabels with rectangles already taken', () => {
  it('drops a page name that would sit on a topic name', () => {
    const l = { id: 'p', text: 'Page', x: 100, y: 100, px: 11, cls: 'kg-plabel' }
    expect(placeLabels([l])).toHaveLength(1)
    expect(placeLabels([l], [[80, 80, 120, 110]])).toHaveLength(0)
  })
})

describe('placeAreaLabels: topic names touch no other topic', () => {
  const area = (id: string, x: number, y: number, r: number, name = id): AreaLabelInput => ({ id, x, y, r, name, sub: '12 pages · a, b' })
  const hits = (rect: [number, number, number, number], c: AreaLabelInput) => {
    const nx = Math.max(rect[0], Math.min(c.x, rect[2]))
    const ny = Math.max(rect[1], Math.min(c.y, rect[3]))
    return Math.hypot(c.x - nx, c.y - ny) < c.r
  }

  it('puts the name above its area when there is room', () => {
    const [p] = placeAreaLabels([area('a', 200, 200, 80)])
    expect(p.at).toBe('above')
    expect(p.rect[3]).toBeLessThanOrEqual(200 - 80)
  })

  it('moves a name that would lie on the area above it inside or below its own area', () => {
    // b sits right under a: "above b" would cover a.
    const places = placeAreaLabels([area('a', 200, 100, 70), area('b', 200, 260, 80)])
    const b = places.find((p) => p.id === 'b')!
    expect(b.at).not.toBe('above')
    expect(hits(b.rect, area('a', 200, 100, 70))).toBe(false)
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

  it('estimates a wider label for a longer name and drops the second line when asked', () => {
    expect(areaLabelSize('A much longer topic name', '', false).w).toBeGreaterThan(areaLabelSize('Short', '', false).w)
    expect(areaLabelSize('X', 'sub', false).h).toBeLessThan(areaLabelSize('X', 'sub', true).h)
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
