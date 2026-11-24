import { describe, expect, it } from 'vitest'
import { flowSay } from './flowSay'
import type { AddResult } from '../add/types'
import type { AskResult } from '../ask/types'

// The home view's result area has one voice (two regions kept for the life of the view).
describe('flowSay: what the home view announces', () => {
  const add = (status: string, message = '') => ({ status, message, page: { title: 'Device trust' } }) as unknown as AddResult

  it('says nothing at rest, the wait while adding, and the result heading after', () => {
    expect(flowSay({ kind: 'idle' })).toEqual({ status: '', alert: '' })
    expect(flowSay({ kind: 'adding', text: 'x' }).status).toMatch(/^Adding/)
    expect(flowSay({ kind: 'add', result: add('added'), busy: false })).toEqual({ status: 'Added: Device trust', alert: '' })
    expect(flowSay({ kind: 'add', result: add('added'), busy: true }).status).toBe('Working…')
  })

  it('adds why when a result did not go as asked', () => {
    expect(flowSay({ kind: 'add', result: add('could-not-update', 'The page could not be read.'), busy: false }).status).toBe('Could not update: Device trust. The page could not be read.')
  })

  it('says errors as an alert, everything else politely', () => {
    expect(flowSay({ kind: 'notice', text: 'Not sent.', error: true })).toEqual({ status: '', alert: 'Not sent.' })
    expect(flowSay({ kind: 'notice', text: 'Undone.', error: false })).toEqual({ status: 'Undone.', alert: '' })
    expect(flowSay({ kind: 'ask', view: { kind: 'error', question: 'q', message: 'Copilot is not connected.' } })).toEqual({ status: '', alert: 'Not answered: Copilot is not connected.' })
    expect(flowSay({ kind: 'ask', view: { kind: 'progress', question: 'q', step: 1 } }).status).toBe('Reading your wiki.')
    expect(flowSay({ kind: 'ask', view: { kind: 'result', result: { status: 'answered' } as unknown as AskResult } }).status).toBe('The answer is ready.')
  })
})
