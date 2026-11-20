import { describe, expect, it } from 'vitest'
import type { GraphEdge, GraphModel, GraphPage } from './model'
import { pageMapLabel } from './pageLabel'
import { foldIds, foldSeries } from './seriesFold'

const S = 'Garden sync | Tidal beds'
function page(id: string, extra: Partial<GraphPage> = {}): GraphPage {
  return { id, title: id, topic: 't1', archived: false, ...extra } as GraphPage
}
const meeting = (id: string, day: string, extra: Partial<GraphPage> = {}) => page(id, { series: S, meetingAt: `${day}T10:00`, title: `${S} · ${day}`, ...extra })
const edge = (from: string, to: string, strength: 1 | 2 | 3 = 1, kind: 'link' | 'mention' = 'link'): GraphEdge => ({ from, to, strength, kind })
function model(pages: GraphPage[], edges: GraphEdge[]): GraphModel {
  return { source: { id: 'v', name: 'Vault', kind: 'vault' }, topics: [], pages, edges } as unknown as GraphModel
}

describe('foldSeries (operator, 2026-11-20: a series as one dot)', () => {
  const m = model(
    [page('sp', { series: S, seriesPage: true, title: `${S} (series)` }), meeting('m1', '2031-04-07'), meeting('m2', '2031-04-08'), meeting('m3', '2031-04-09'), page('pump')],
    [edge('m1', 'm2'), edge('m2', 'm3'), edge('sp', 'm1'), edge('m1', 'pump', 1), edge('m3', 'pump', 3), edge('pump', 'm2', 2, 'mention')],
  )
  it('keeps the series page as the one dot and leaves its meetings out of the map', () => {
    const f = foldSeries(m)
    expect(f.model.pages.map((p) => p.id)).toEqual(['sp', 'pump'])
    expect([...f.dotOf.entries()]).toEqual([['m1', 'sp'], ['m2', 'sp'], ['m3', 'sp']])
    expect(f.model.pages[0].seriesCount).toBe(3)
    expect(pageMapLabel(f.model.pages[0])).toBe('Garden sync · 3 meetings')
  })
  it('moves the meetings\' links to the dot: once per pair and kind, the strongest, none within the series', () => {
    const f = foldSeries(m)
    expect(f.model.edges).toEqual([edge('sp', 'pump', 3), edge('pump', 'sp', 2, 'mention')])
  })
  it('leaves the model it was given as it is', () => {
    foldSeries(m)
    expect(m.pages).toHaveLength(5)
    expect(m.pages[0].seriesCount).toBeUndefined()
  })
  it('uses the newest meeting as the dot when the series has no page, a single meeting too', () => {
    const f = foldSeries(model([meeting('m1', '2031-04-07'), meeting('m2', '2031-04-08')], [edge('m1', 'm2')]))
    expect(f.model.pages.map((p) => p.id)).toEqual(['m2'])
    expect(f.model.edges).toEqual([])
    const one = foldSeries(model([meeting('m1', '2031-04-07')], []))
    expect(one.model.pages.map((p) => p.id)).toEqual(['m1'])
    expect(pageMapLabel(one.model.pages[0])).toBe('Garden sync · 1 meeting')
    const none = model([page('pump')], [])
    expect(foldSeries(none).model).toBe(none)
  })
  it('does not hide a series behind an archived series page', () => {
    const f = foldSeries(model([page('sp', { series: S, seriesPage: true, archived: true }), meeting('m1', '2031-04-07'), meeting('m2', '2031-04-08')], []))
    expect(f.model.pages.map((p) => p.id)).toEqual(['sp', 'm2'])
  })
  it('keeps two series apart, case and spacing aside within one', () => {
    const f = foldSeries(model([meeting('a1', '2031-04-07'), meeting('a2', '2031-04-08', { series: ' garden SYNC |  Tidal beds ' }), meeting('b1', '2031-04-07', { series: 'Pump review' }), meeting('b2', '2031-04-08', { series: 'Pump review' })], []))
    expect(f.model.pages.map((p) => p.id).sort()).toEqual(['a2', 'b2'])
  })
  it('maps ids of the full model to the map\'s dots', () => {
    const f = foldSeries(m)
    expect(foldIds(['m1', 'm2', 'pump', 'sp'], f.dotOf)).toEqual(['sp', 'pump'])
  })
})
