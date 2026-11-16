import { describe, expect, it } from 'vitest'
import { VIEW_ORDER, VIEWS, viewFromHash, viewTitle } from './views'

describe('views', () => {
  it('reads the view from the address; anything unknown is home', () => {
    for (const v of VIEW_ORDER) expect(viewFromHash(VIEWS[v].hash)).toBe(v)
    expect(viewFromHash('')).toBe('home')
    expect(viewFromHash('#/nothing')).toBe('home')
  })
  it('names the window after the view, the app alone at home', () => {
    expect(viewTitle('home')).toBe('ObsidiNote')
    expect(viewTitle('graph')).toBe('Knowledge graph - ObsidiNote')
    expect(viewTitle('history')).toBe('History - ObsidiNote')
  })
})
