import { describe, expect, it } from 'vitest'
import { seriesCopies } from '../model/series'
import { mergeResultLine, mergeWording, parseMergePlan, parseMergeResult } from './mergeModel'

describe('merge duplicates: the server\'s plan', () => {
  it('reads groups, also a list of one sent as its item, and drops empty ones', () => {
    const plan = parseMergePlan({ series: 'Garden sync', groups: { keep: { id: 'p1', title: 'A' }, extra: { id: 'p2', title: 'B' } } })
    expect(plan).toEqual({ series: 'Garden sync', groups: [{ keep: { id: 'p1', title: 'A' }, extra: [{ id: 'p2', title: 'B' }] }] })
    expect(parseMergePlan({ groups: [{ keep: { id: 'p1' }, extra: [] }] }).groups).toEqual([])
    expect(parseMergePlan(null)).toEqual({ series: '', groups: [] })
  })
  it('reads the result defensively', () => {
    expect(parseMergeResult({ status: 'merged', message: 'm', merged: 2, warnings: 'one' })).toEqual({ status: 'merged', message: 'm', merged: 2, warnings: ['one'] })
    expect(parseMergeResult({}).status).toBe('merged')
  })
})

describe('merge duplicates: wording', () => {
  const one = { series: 'S', groups: [{ keep: { id: 'p1', title: 'A' }, extra: [{ id: 'p2', title: 'B' }] }] }
  it('names one copy and two copies of two meetings', () => {
    expect(mergeWording(one).title).toBe('Merge the second copy of a meeting?')
    expect(mergeWording(one).confirm).toBe('Merge and archive the copy')
    const two = { series: 'S', groups: [...one.groups, { keep: { id: 'p3', title: 'C' }, extra: [{ id: 'p4', title: 'D' }] }] }
    expect(mergeWording(two).title).toBe('Merge 2 copies of 2 meetings?')
  })
  it('says the copy can be restored and the person\'s notes stay with it', () => {
    expect(mergeWording(one).lines.join(' ')).toMatch(/Restore brings it back\. Your own notes on it stay with the copy\./)
  })
  it('says what came of it', () => {
    expect(mergeResultLine({ status: 'merged', message: '', merged: 1, warnings: [] })).toBe('Merged one copy of a meeting; it is in the Archive.')
    expect(mergeResultLine({ status: 'nothing', message: 'None.', merged: 0, warnings: [] })).toBe('None.')
    expect(mergeResultLine({ status: 'partial', message: '', merged: 1, warnings: ['B was not archived.'] })).toMatch(/could not be merged: B was not archived\.$/)
  })
})

describe('seriesCopies (the server groups the same way: lib/Ingest.psm1 Get-SeriesMergePlan)', () => {
  const m = (meetingAt: string, extra: object = {}) => ({ kind: 'meeting', series: 'Garden sync | Beds', meetingAt, ...extra })
  it('counts a second copy of a day: one without a time joins one with a time', () => {
    expect(seriesCopies([m('2026-11-17T09:00'), m('2026-11-17'), m('2026-11-18T09:00')], 'garden sync beds')).toBe(1)
  })
  it('keeps two meetings of one day at different times apart', () => {
    expect(seriesCopies([m('2026-11-17T09:00'), m('2026-11-17T15:00')], 'Garden sync Beds')).toBe(0)
  })
  it('leaves archived pages, the series page and other series out', () => {
    expect(seriesCopies([m('2026-11-17'), m('2026-11-17', { archived: true }), m('2026-11-17', { seriesPage: true }), m('2026-11-17', { series: 'Other' })], 'Garden sync Beds')).toBe(0)
  })
  it('counts three copies of one day as two', () => {
    expect(seriesCopies([m('2026-11-17'), m('2026-11-17'), m('2026-11-17T09:00')], 'Garden sync Beds')).toBe(2)
  })
})
