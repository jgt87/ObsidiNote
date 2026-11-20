import { describe, expect, it } from 'vitest'
import { pageMapLabel, shortSeriesName } from './pageLabel'

const now = new Date(2031, 3, 11)
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

describe('pageMapLabel (operator, 2026-11-20: a series showed the same cut-off name on every meeting)', () => {
  it('shows a meeting of a series by its short series name and day, so each differs', () => {
    const a = pageMapLabel({ title: `${long} · 2031-04-08`, series: long, meetingAt: '2031-04-08T10:00' }, now)
    const b = pageMapLabel({ title: `${long} · 2031-04-09`, series: long, meetingAt: '2031-04-09T10:00' }, now)
    expect(a).toBe('Daily Sync · Tue 8 Apr')
    expect(b).toBe('Daily Sync · Wed 9 Apr')
  })
  it('adds the time when the title has it (a second meeting that day)', () => {
    expect(pageMapLabel({ title: `${long} · 2031-04-08 15:00`, series: long, meetingAt: '2031-04-08T15:00' }, now)).toBe('Daily Sync · Tue 8 Apr 15:00')
  })
  it('shows a series page as its short name and "(series)"', () => {
    expect(pageMapLabel({ title: `${long} (series)`, series: long, seriesPage: true }, now)).toBe('Daily Sync (series)')
  })
  it('keeps the title of any other page, and of a meeting without a day', () => {
    expect(pageMapLabel({ title: 'Pump maintenance' }, now)).toBe('Pump maintenance')
    expect(pageMapLabel({ title: 'Garden sync', series: 'Garden sync', meetingAt: '' }, now)).toBe('Garden sync')
  })
})
