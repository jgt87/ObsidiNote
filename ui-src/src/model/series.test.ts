import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { normalizeGraph } from '../graph/model'
import { seriesCount, seriesKey } from './series'

// What the server sends for a meeting page (lib/GraphModel.psm1), pinned by the fixture its own test
// produces (tests/GraphModel.Tests.ps1).
const fixture = JSON.parse(readFileSync(fileURLToPath(new URL('../../../tests/fixtures/graph-pages.json', import.meta.url)), 'utf8')) as {
  pages: { id: string; kind: string; series?: string; meetingAt?: string }[]
}

describe('meeting series', () => {
  it('compares series names by their letters and digits, as the server does', () => {
    expect(seriesKey('Daily Sync | Tidal & Fern')).toBe(seriesKey('Daily Sync Tidal Fern'))
    expect(seriesKey('Garden sync')).toBe('garden sync')
    expect(seriesKey('Garden sync')).not.toBe(seriesKey('Garden sync 2'))
  })
  it('counts a series\' meeting pages, archived ones left out', () => {
    const pages = [
      { kind: 'meeting', series: 'Garden sync | Beds' },
      { kind: 'meeting', series: 'Garden sync Beds' },
      { kind: 'meeting', series: 'Garden sync Beds', archived: true },
      { kind: 'note', series: 'Garden sync Beds' },
      { kind: 'meeting', series: 'Other' },
    ]
    expect(seriesCount(pages, 'garden sync beds')).toBe(2)
    expect(seriesCount(pages, '')).toBe(0)
  })
  it('reads series and meetingAt from what the server sends', () => {
    const want = fixture.pages.find((p) => p.series)!
    const m = normalizeGraph({ source: { kind: 'vault', id: 'v1', name: 'V', readOnly: false }, topics: [], pages: fixture.pages.map((p) => ({ ...p, title: p.id, topicIds: [] })), edges: [] })
    const p = m.pages.find((x) => x.id === want.id)!
    expect(p.series).toBe(want.series)
    expect(p.meetingAt).toBe(want.meetingAt)
    expect(m.pages.find((x) => !fixture.pages.find((f) => f.id === x.id)?.series)?.series).toBe('')
  })
})
