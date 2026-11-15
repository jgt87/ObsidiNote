import { describe, expect, it } from 'vitest'
import { readOnlyWhy } from './readOnly'

describe('readOnlyWhy: why a page cannot be changed here', () => {
  it('says nothing for a source that can be changed', () => {
    expect(readOnlyWhy({ kind: 'vault', readOnly: false, readOnlyReason: '' })).toBe('')
  })
  it('names each reason the server gives, with what to do', () => {
    expect(readOnlyWhy({ kind: 'vault', readOnly: true, readOnlyReason: 'lease' })).toMatch(/may show as read only.*seems to hold/)
    expect(readOnlyWhy({ kind: 'vault', readOnly: true, readOnlyReason: 'not-active' })).toMatch(/not the active vault/)
    expect(readOnlyWhy({ kind: 'notebook', readOnly: true, readOnlyReason: 'notebook' })).toMatch(/never writes/)
  })
  it('still says something sensible when an older server gives no reason', () => {
    expect(readOnlyWhy({ kind: 'notebook', readOnly: true, readOnlyReason: '' })).toMatch(/connected notebook/)
    expect(readOnlyWhy({ kind: 'vault', readOnly: true, readOnlyReason: '' })).toMatch(/read only/)
  })
})
