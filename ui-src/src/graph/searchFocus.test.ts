import { describe, expect, it } from 'vitest'
import { focusAfter, searchPick } from './searchFocus'

describe('searchPick', () => {
  it('keeps the chosen result while it is one, else the first; nothing without results', () => {
    expect(searchPick(['p1', 'p2'], 'p2')).toBe('p2')
    expect(searchPick(['p1', 'p2'], 'p9')).toBe('p1')
    expect(searchPick(['p1', 'p2'], null)).toBe('p1')
    expect(searchPick([], 'p1')).toBeNull()
    expect(searchPick(null, 'p1')).toBeNull()
  })
})

describe('focusAfter: the focus goes back to the search result until the search is cleared', () => {
  it('a cleared focus during a search returns to the chosen result', () => {
    expect(focusAfter(null, ['p1', 'p2'], 'p2')).toEqual({ id: 'p2', via: 'pointer' })
    expect(focusAfter(null, ['p1', 'p2'], null)).toEqual({ id: 'p1', via: 'pointer' })
  })

  it('pointing at any page, a result or not, is kept', () => {
    expect(focusAfter({ id: 'p7', via: 'pointer' }, ['p1'], 'p1')).toEqual({ id: 'p7', via: 'pointer' })
    expect(focusAfter({ id: 'p1', via: 'keyboard' }, ['p1'], 'p1')).toEqual({ id: 'p1', via: 'keyboard' })
  })

  it('without a search (or with no results) a cleared focus stays cleared', () => {
    expect(focusAfter(null, null, 'p1')).toBeNull()
    expect(focusAfter(null, [], null)).toBeNull()
  })
})
