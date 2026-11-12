import { describe, expect, it } from 'vitest'
import { formatModified, plural } from './format'

// Local times, so the test holds in any time zone.
const now = new Date(2026, 10, 12, 16, 0)

describe('formatModified', () => {
  it('shows today with the time, then yesterday, the weekday, the date', () => {
    expect(formatModified(new Date(2026, 10, 12, 14, 34).toISOString(), now)).toBe('today 14:34')
    expect(formatModified(new Date(2026, 10, 11, 9, 0).toISOString(), now)).toBe('yesterday')
    expect(formatModified(new Date(2026, 10, 9, 9, 0).toISOString(), now)).toBe('Mon')
    expect(formatModified(new Date(2026, 10, 3, 9, 0).toISOString(), now)).toBe('3 Nov')
    expect(formatModified(new Date(2025, 10, 3, 9, 0).toISOString(), now)).toBe('3 Nov 2025')
  })
  it('is empty for an unreadable date', () => {
    expect(formatModified('', now)).toBe('')
    expect(formatModified('not a date', now)).toBe('')
  })
})

describe('plural', () => {
  it('counts', () => {
    expect(plural(1, 'page')).toBe('1 page')
    expect(plural(3, 'page')).toBe('3 pages')
  })
})
