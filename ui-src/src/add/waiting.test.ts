import { describe, expect, it } from 'vitest'
import { normalizeAddResult } from './types'
import { isWaitingStatus, waitingLabel, waitingNote } from './waiting'
import { resultHeading } from './format'

describe('waiting for Copilot', () => {
  it('knows which statuses wait in the Intake', () => {
    for (const s of ['waiting', 'still-waiting', 'mismatch', 'invalid'] as const) expect(isWaitingStatus(s)).toBe(true)
    for (const s of ['added', 'failed', 'ask-instead'] as const) expect(isWaitingStatus(s)).toBe(false)
  })
  it('says what each outcome means for the item', () => {
    expect(waitingNote('waiting')).toContain('waits in your Intake')
    expect(waitingNote('still-waiting')).toContain('Try again later')
    expect(waitingNote('mismatch')).toContain('Nothing was written')
    expect(waitingNote('invalid')).toContain('Nothing was written')
    expect(waitingLabel('mismatch')).toBe('Answer not for this item')
  })
  it('gives each status a heading', () => {
    expect(resultHeading('waiting', '')).toBe('Waiting for Copilot')
    expect(resultHeading('still-waiting', '')).toBe('Not added yet')
    expect(resultHeading('invalid', '')).toBe('Not added yet')
  })
  it('keeps the Intake item id and reference, empty when absent', () => {
    const r = normalizeAddResult({ status: 'waiting', kind: 'link', inboxId: '{I}', ref: 'rabc12345' })
    expect(r.inboxId).toBe('{I}')
    expect(r.ref).toBe('rabc12345')
    expect(normalizeAddResult({ status: 'added' }).inboxId).toBe('')
  })
})
