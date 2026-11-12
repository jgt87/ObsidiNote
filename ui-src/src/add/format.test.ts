import { describe, expect, it } from 'vitest'
import {
  backlinksLine,
  changedFields,
  chipLabel,
  clampStrength,
  formatOneNotePath,
  formatSeconds,
  formatTopicPath,
  placementParts,
  resultHeading,
} from './format'
import { normalizeAddResult, type PlacedPage } from './types'

const page: PlacedPage = {
  id: 'p101',
  title: 'Identity-aware proxies',
  type: 'concept',
  bucket: 'Notes',
  section: 'Notes',
  link: 'onenote:#p101',
  url: '',
  topicPath: 'Security/Networking/Zero trust',
  alsoUnder: ['Projects/Partner portal'],
  oneNotePath: ['ObsidiNote', 'Notes', 'Identity-aware proxies'],
  unfiled: false,
}

describe('placement', () => {
  it('shows the topic path and the title', () => {
    expect(placementParts(page)).toEqual(['Security', 'Networking', 'Zero trust', 'Identity-aware proxies'])
    expect(formatTopicPath('Projects/Partner portal')).toBe('Projects / Partner portal')
    expect(formatOneNotePath(page)).toBe('ObsidiNote › Notes › Identity-aware proxies')
  })
  it('puts a page without topics under Unfiled', () => {
    expect(placementParts({ ...page, topicPath: '', unfiled: true })).toEqual(['Unfiled', 'Identity-aware proxies'])
  })
})

describe('labels', () => {
  it('formats seconds, strength and chips', () => {
    expect(formatSeconds(3240)).toBe('3.2 s')
    expect(formatSeconds(-1)).toBe('')
    expect(clampStrength(7)).toBe(3)
    expect(clampStrength(0)).toBe(1)
    expect(chipLabel({ kind: 'new-topic', label: 'Zero trust' })).toBe('new topic: Zero trust')
    expect(chipLabel({ kind: 'alias', label: 'IAP' })).toBe('alias: IAP')
  })
  it('counts backlinks', () => {
    expect(backlinksLine(3)).toBe('Backlinks added to 3 pages (in their "Linked from" block only)')
    expect(backlinksLine(1)).toBe('Backlinks added to 1 page (in their "Linked from" block only)')
    expect(backlinksLine(0)).toBe('No backlinks were added')
  })
  it('heads each status in sentence case', () => {
    expect(resultHeading('added', 'X')).toBe('Added: X')
    expect(resultHeading('failed', 'X')).toBe('Not added')
  })
})

describe('normalizeAddResult', () => {
  it('turns one-item and empty lists from Windows PowerShell into arrays', () => {
    const r = normalizeAddResult({
      status: 'added',
      chips: { kind: 'type', label: 'note' } as never,
      links: null,
      page: { ...page, alsoUnder: 'Projects' as never, oneNotePath: ['a', 'b'] },
      update: { old: null, new: { title: 'T', keyFacts: 'one' } as never, diff: null, oldAt: '', newAt: '', review: null as never },
    })
    expect(r.chips).toEqual([{ kind: 'type', label: 'note' }])
    expect(r.links).toEqual([])
    expect(r.page?.alsoUnder).toEqual(['Projects'])
    expect(r.update?.new?.keyFacts).toEqual(['one'])
    expect(r.update?.review).toEqual([])
    expect(r.warnings).toEqual([])
  })
  it('fills a missing result as failed', () => {
    expect(normalizeAddResult(null).status).toBe('failed')
  })
})

describe('changedFields', () => {
  it('lists only the fields that changed', () => {
    const base = { title: 'A', where: 'HR', kind: 'page', summary: 's', keyFacts: [], useFor: 'u', sensitivity: '' }
    const rows = changedFields({ old: base, new: { ...base, kind: 'site', where: ' hr ' }, diff: null, oldAt: '', newAt: '', review: [] })
    expect(rows).toEqual([{ label: 'Kind', old: 'page', new: 'site' }])
  })
})
