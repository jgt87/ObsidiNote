import { describe, expect, it } from 'vitest'
import { lastRun } from './lastRun'

describe('lastRun: Try again repeats the request that failed', () => {
  it('runs the same call with the same arguments again', () => {
    const sent: string[] = []
    const r = lastRun()
    const followUp = (conversation: string, text: string) => () => sent.push(`follow-up ${conversation}: ${text}`)
    r.run(followUp('c1', 'and the second one?'))
    r.again()
    expect(sent).toEqual(['follow-up c1: and the second one?', 'follow-up c1: and the second one?'])
  })
  it('repeats the latest request, not an earlier one', () => {
    const sent: string[] = []
    const r = lastRun()
    r.run(() => sent.push('first'))
    r.run(() => sent.push('second'))
    r.again()
    expect(sent).toEqual(['first', 'second', 'second'])
  })
  it('does nothing when nothing ran yet', () => {
    expect(() => lastRun().again()).not.toThrow()
  })
})
