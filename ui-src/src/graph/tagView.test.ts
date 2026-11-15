import { describe, expect, it } from 'vitest'
import { buildIndex } from './graphIndex'
import { layoutGraph } from './layout'
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
