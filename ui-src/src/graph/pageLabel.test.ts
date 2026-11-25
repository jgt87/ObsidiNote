import { describe, expect, it } from 'vitest'
import { pageMapLabel, shortSeriesName } from './pageLabel'

const long = 'Daily Sync | Fernbrook & Tidal | Garden Platform & Pump Studio Governance'

describe('shortSeriesName', () => {
  it('takes the first part of a Teams title split by " | "', () => {
    expect(shortSeriesName(long)).toBe('Daily Sync')
    expect(shortSeriesName('Garden sync')).toBe('Garden sync')
  })
  it('cuts a long name with "…" and keeps a too short first part whole', () => {
    expect(shortSeriesName('Quarterly Garden Platform Governance Review Board')).toBe('Quarterly Garden Platform G…')
    expect(shortSeriesName('QA | Pumps')).toBe('QA | Pumps')
  })
})

describe('pageMapLabel: a series as one dot, not meetings told apart by date (D-077)', () => {
  it('names a series\' one dot by its short name and its number of meetings', () => {
    expect(pageMapLabel({ title: `${long} (series)`, series: long, seriesCount: 6 })).toBe('Daily Sync · 6 meetings')
    expect(pageMapLabel({ title: `${long} · 2031-04-08`, series: long, seriesCount: 1 })).toBe('Daily Sync · 1 meeting')
  })
  it('adds no date: any other page, a meeting included, shows its title', () => {
    expect(pageMapLabel({ title: 'Pump maintenance' })).toBe('Pump maintenance')
    expect(pageMapLabel({ title: `${long} · 2031-04-08`, series: long })).toBe(`${long} · 2031-04-08`)
  })
})
