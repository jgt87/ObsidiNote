import { describe, expect, it } from 'vitest'
import { buildIndex } from './graphIndex'
import { dotMeetsBox, layoutGraph } from './layout'
import { syntheticGraph } from './synthetic'
import { availableTags, byTag, tagAreaId } from './tagView'

// The demo data carries three hand-set tags across its topics (synthetic.ts).
const model = syntheticGraph({ pages: 100, topics: 6 })

describe('byTag: the map grouped by hand-set tags', () => {
  it('offers the tags in use, by name, with their page counts', () => {
    const tags = availableTags(model)
    expect(tags.map((t) => t.name)).toEqual(['follow up', 'key reference', 'licensing'])
    for (const t of tags) expect(t.count).toBe(model.pages.filter((p) => !p.archived && p.tags.includes(t.name)).length)
  })

  it('makes one area per tag and keeps only the pages that carry one', () => {
    const m = byTag(model, null)
    expect(m.topics.map((t) => t.name)).toEqual(['follow up', 'key reference', 'licensing'])
    expect(m.pages.length).toBe(model.pages.filter((p) => p.tags.length > 0).length)
    // Under the rarest of its tags: the demo's "key reference" pages also carry "licensing".
    for (const p of m.pages) expect(p.topicIds[0]).toBe(tagAreaId(p.tags.includes('key reference') ? 'key reference' : p.tags[0]))
    const ids = new Set(m.pages.map((p) => p.id))
    for (const e of m.edges) expect(ids.has(e.from) && ids.has(e.to)).toBe(true)
  })

  it('shows only the chosen tags; a page with other tags too still sits under the chosen one', () => {
    const m = byTag(model, new Set(['key reference']))
    expect(m.topics.map((t) => t.name)).toEqual(['key reference'])
    expect(m.pages.length).toBeGreaterThan(0)
    // The demo's "key reference" pages also carry "licensing", which is not shown here.
    for (const p of m.pages) {
      expect(p.tags).toContain('key reference')
      expect(p.topicIds).toEqual([tagAreaId('key reference')])
    }
  })

  it('gives an empty map, not an error, when no tag is chosen or none exists', () => {
    expect(byTag(model, new Set()).pages).toEqual([])
    const none = byTag({ ...model, pages: model.pages.map((p) => ({ ...p, tags: [] })) }, null)
    expect(none.topics).toEqual([])
    expect(layoutGraph(none, {}, buildIndex(none)).dots).toEqual([])
  })

  it('keeps the pages of one topic together inside a tag area', () => {
    for (const pages of [100, 300, 1000]) {
      const big = syntheticGraph({ pages, topics: 6 })
      const m = byTag(big, null)
      const layout = layoutGraph(m, { aspect: 1.45 }, buildIndex(m))
      const group = new Map(m.pages.map((p) => [p.id, p.group!.id]))
      for (const a of layout.areas) {
        const dots = layout.dots.filter((d) => d.area === a.id)
        const ids = [...new Set(dots.map((d) => group.get(d.id)!))]
        if (ids.length < 2) continue
        const centre = new Map(ids.map((g) => {
          const mine = dots.filter((d) => group.get(d.id) === g)
          return [g, { x: mine.reduce((s, d) => s + d.x, 0) / mine.length, y: mine.reduce((s, d) => s + d.y, 0) / mine.length }]
        }))
        // Most pages are nearer the middle of their own topic's pages than of any other topic's.
        const home = dots.filter((d) => {
          const own = centre.get(group.get(d.id)!)!
          const mine = Math.hypot(d.x - own.x, d.y - own.y)
          return ids.every((g) => g === group.get(d.id) || mine <= Math.hypot(d.x - centre.get(g)!.x, d.y - centre.get(g)!.y))
        })
        expect(home.length / dots.length, `${pages} pages, area ${a.name}`).toBeGreaterThan(0.8)
      }
    }
  })

  it('names the topics inside a tag area on no dot, off the tag name and inside the area, from 100 to 1000 pages', () => {
    let named = 0
    for (const pages of [100, 300, 1000]) {
      const big = syntheticGraph({ pages, topics: 6 })
      const m = byTag(big, null)
      const layout = layoutGraph(m, { aspect: 1.45 }, buildIndex(m))
      for (const a of layout.areas) {
        const dots = layout.dots.filter((d) => d.area === a.id)
        for (const g of a.groups ?? []) {
          named++
          const box: [number, number, number, number] = [g.x - g.w / 2, g.y, g.x + g.w / 2, g.y + g.h]
          expect(dots.filter((d) => dotMeetsBox(d, box)).map((d) => d.id), `${pages} pages, "${g.name}" in ${a.name}`).toEqual([])
          for (const [x, y] of [[box[0], box[1]], [box[2], box[1]], [box[0], box[3]], [box[2], box[3]]]) expect(Math.hypot(x - a.x, y - a.y)).toBeLessThanOrEqual(a.r)
          const offSlot = box[2] <= a.x - a.slot.hw || box[0] >= a.x + a.slot.hw || box[3] <= a.y - a.slot.hh || box[1] >= a.y + a.slot.hh
          expect(offSlot, `"${g.name}" on the name of ${a.name}`).toBe(true)
        }
      }
    }
    expect(named).toBeGreaterThan(3)
  })

  it('names no group in an ordinary topic map', () => {
    const layout = layoutGraph(model, { aspect: 1.45 }, buildIndex(model))
    expect(layout.areas.every((a) => a.groups === undefined)).toBe(true)
  })

  it('lays out like any other grouping: every kept page once, inside its tag area', () => {
    const m = byTag(model, null)
    const layout = layoutGraph(m, { aspect: 1.45 }, buildIndex(m))
    expect(layout.dots).toHaveLength(m.pages.length)
    expect(layout.areas.map((a) => a.name).sort()).toEqual(['follow up', 'key reference', 'licensing'])
    const area = new Map(layout.areas.map((a) => [a.id, a]))
    for (const d of layout.dots) {
      const a = area.get(d.area)!
      expect(Math.hypot(d.x - a.x, d.y - a.y) + d.r).toBeLessThanOrEqual(a.r)
    }
  })
})
