import { describe, expect, it } from 'vitest'
import { ApiError, normalizeSubmitResult, submit } from './api'
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

describe('submit: what is sent to the server', () => {
  async function sentBody(req: Parameters<typeof submit>[0]): Promise<Record<string, unknown>> {
    let body = ''
    const real = globalThis.fetch
    globalThis.fetch = (async (_u: unknown, init?: RequestInit) => {
      body = String(init?.body ?? '')
      return new Response(JSON.stringify({ intent: 'add', status: 'added', kind: 'text' }), { status: 200 })
    }) as typeof fetch
    try {
      await submit(req)
    } finally {
      globalThis.fetch = real
    }
    return JSON.parse(body)
  }
  it('sends the "From" choice and a dropped file\'s address (origin was left out until 2026-11-14)', async () => {
    const b = await sentBody({ text: 'x', mode: 'add', origin: 'teams', fileUrl: 'https://fernbrook-my.sharepoint.com/a.docx' })
    expect(b.origin).toBe('teams')
    expect(b.fileUrl).toBe('https://fernbrook-my.sharepoint.com/a.docx')
  })
  it('leaves both out when not set (typed text)', async () => {
    const b = await sentBody({ text: 'x', mode: 'add' })
    expect('origin' in b).toBe(false)
    expect('fileUrl' in b).toBe(false)
    expect('series' in b).toBe(false)
  })
  it('sends the meeting series of an Ask within one series (2026-11-18)', async () => {
    const b = await sentBody({ text: 'What did we decide?', mode: 'ask', series: 'Garden sync' })
    expect(b.series).toBe('Garden sync')
  })
})
