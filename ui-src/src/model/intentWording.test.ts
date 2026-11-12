import { describe, expect, it } from 'vitest'
import { EMPTY_HINT, intentLine, primaryLabel } from './intentWording'

describe('intentLine', () => {
  it('says it will ask, with the reason and a flip to Add', () => {
    const line = intentLine({ intent: 'ask', reason: 'it reads as a question (ends with "?")', rule: 2 })
    expect(line.lead).toBe('Will ask your wiki')
    expect(line.text).toBe('it reads as a question (ends with "?").')
    expect(line.flip).toEqual({ label: 'Add it instead', mode: 'add' })
  })
  it('says it will add, with a flip to Ask', () => {
    expect(intentLine({ intent: 'add', reason: 'it is a link on its own', rule: 3 }).flip?.mode).toBe('ask')
  })
  it('says an Add goes to the active vault while a read-only notebook is shown', () => {
    const line = intentLine({ intent: 'add', reason: 'it is a link on its own', rule: 3 }, { vaultName: 'ObsidiNote', shownName: 'Reading notes' })
    expect(line.text).toBe('it is a link on its own. It goes to ObsidiNote, not to Reading notes (read only).')
    expect(intentLine({ intent: 'add', reason: 'x', rule: 3 }, { vaultName: null, shownName: 'Reading notes' }).text).toMatch('No ObsidiNote vault is open')
    expect(intentLine({ intent: 'ask', reason: 'x', rule: 2 }, { vaultName: 'ObsidiNote', shownName: 'Reading notes' }).text).toBe('x.')
  })
  it('explains an unclear input without a flip', () => {
    const line = intentLine({ intent: 'unclear', reason: 'it is short', rule: 4 })
    expect(line.lead).toBe('Not sure yet')
    expect(line.flip).toBeNull()
  })
  it('shows the hint when there is nothing yet', () => {
    expect(intentLine(null).text).toBe(EMPTY_HINT)
    expect(intentLine({ intent: 'empty', reason: '', rule: 0 }).lead).toBe('')
  })
})

describe('primaryLabel', () => {
  it('follows the intent', () => {
    expect(primaryLabel({ intent: 'ask', reason: '', rule: 2 })).toBe('Ask')
    expect(primaryLabel({ intent: 'add', reason: '', rule: 3 })).toBe('Add')
    expect(primaryLabel({ intent: 'unclear', reason: '', rule: 4 })).toBe('Send')
    expect(primaryLabel(null)).toBe('Send')
  })
})
