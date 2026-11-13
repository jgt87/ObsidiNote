import { describe, expect, it } from 'vitest'
import { canGoBack, canGoForward, currentPage, goBack, goForward, HISTORY_MAX, startHistory, visit } from './history'

describe('page dialog history', () => {
  it('starts on the opened page with nowhere to go', () => {
    const h = startHistory('a')
    expect(currentPage(h)).toBe('a')
    expect(canGoBack(h)).toBe(false)
    expect(canGoForward(h)).toBe(false)
  })

  it('goes back and forward through visited pages', () => {
    let h = visit(visit(startHistory('a'), 'b'), 'c')
    expect(currentPage(h)).toBe('c')
    h = goBack(h)
    expect(currentPage(h)).toBe('b')
    h = goBack(h)
    expect(currentPage(h)).toBe('a')
    expect(goBack(h)).toBe(h)
    h = goForward(h)
    expect(currentPage(h)).toBe('b')
    expect(canGoForward(h)).toBe(true)
  })

  it('a new visit after Back drops the pages ahead', () => {
    let h = visit(visit(startHistory('a'), 'b'), 'c')
    h = visit(goBack(goBack(h)), 'd')
    expect(h.pages).toEqual(['a', 'd'])
    expect(canGoForward(h)).toBe(false)
  })

  it('visiting the current page again changes nothing', () => {
    const h = visit(startHistory('a'), 'b')
    expect(visit(h, 'b')).toBe(h)
  })

  it('keeps at most HISTORY_MAX pages, dropping the oldest', () => {
    let h = startHistory('p0')
    for (let i = 1; i < HISTORY_MAX + 10; i++) h = visit(h, `p${i}`)
    expect(h.pages).toHaveLength(HISTORY_MAX)
    expect(h.pages[0]).toBe('p10')
    expect(currentPage(h)).toBe(`p${HISTORY_MAX + 9}`)
  })
})
