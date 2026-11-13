import { describe, expect, it } from 'vitest'
import { ApiError, normalizeSubmitResult } from './api'
import { willAsk } from './hooks/useHomeFlow'

describe('normalizeSubmitResult', () => {
  it('reads an Add answer and repairs its one-item lists', () => {
    const r = normalizeSubmitResult({ intent: 'add', status: 'added', kind: 'text', chips: { kind: 'type', label: 'concept' }, links: null })
    expect(r.intent).toBe('add')
    if (r.intent !== 'add') throw new Error('not add')
    expect(r.chips).toEqual([{ kind: 'type', label: 'concept' }])
    expect(r.links).toEqual([])
  })
  it('reads an Ask answer, and throws the error of a failed one', () => {
    const r = normalizeSubmitResult({ intent: 'ask', ok: true, status: 'answered', sources: { n: 1, title: 'Zero trust' }, staleLinks: null, invalidCitations: null, path: null, answer: null, notFound: null })
    expect(r.intent).toBe('ask')
    if (r.intent !== 'ask') throw new Error('not ask')
    expect(r.sources.length).toBe(1)
    expect(() => normalizeSubmitResult({ intent: 'ask', ok: false, error: 'Ask has no source: no vault is open.' })).toThrow(ApiError)
  })
})

describe('willAsk', () => {
  it('follows the mode, and in Auto the intent rules', () => {
    expect(willAsk('ask', null)).toBe(true)
    expect(willAsk('auto', 'ask')).toBe(true)
    expect(willAsk('auto', 'unclear')).toBe(false)
    expect(willAsk('add', 'ask')).toBe(false)
  })
})
