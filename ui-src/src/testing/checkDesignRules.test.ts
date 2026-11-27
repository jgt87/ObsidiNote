import { describe, expect, it } from 'vitest'
import { answer, askAnswerFixture, bodyShownRight, citationsRight, composerRowRight, readFailedRight, RULES } from '../../scripts/check-design-rules.mjs'

// The rendered design check (scripts/check-design-rules.mjs) runs in headless Edge and is not part
// of vitest; this file pins its pure parts: the stub API it answers the app with, and the verdicts
// it gives over the values it measures. Importing the script must start nothing (no Edge, no rules).

describe('check-design-rules: the stub API', () => {
  it('answers the routes the app reads at start, and nothing else', () => {
    expect(answer('/api/status')).toMatchObject({ app: 'ObsidiNote', copilot: { state: 'connected' } })
    expect(answer('/api/notebooks')).toMatchObject({ mode: 'writer' })
    expect(answer('/api/intent')).toMatchObject({ intent: 'add' })
    expect(answer('/api/no-such-route')).toBeNull()
  })

  it('uses invented data only: example hosts and a placeholder vault id', () => {
    const text = JSON.stringify([answer('/api/status'), answer('/api/notebooks'), answer('/api/submit'), answer('/api/activity')])
    const hosts = [...text.matchAll(/https?:\/\/([^/"]+)/g)].map((m) => m[1])
    expect(hosts.length).toBeGreaterThan(0)
    expect(hosts.every((h) => h.endsWith('.example') || h === 'example.com')).toBe(true)
    expect(text).toContain('{11111111-1111-1111-1111-111111111111}')
  })

  it('runs every rule as a function, and importing it ran none', () => {
    expect(RULES.length).toBeGreaterThan(20)
    expect(RULES.every((r) => typeof r === 'function')).toBe(true)
  })
})

describe('check-design-rules: verdicts', () => {
  const body = { shown: true, headings: 3, lists: 3, table: true, pageLinks: 1, web: ['https://example.com', 'mailto:a@b.example', 'onenote:x'], html: false, scroll: false }

  it('the page text: accepts the demo page as it should show', () => {
    expect(bodyShownRight(body)).toBe(true)
  })

  it('the page text: refuses another address scheme, live HTML, sideways scroll and a missing table', () => {
    expect(bodyShownRight({ ...body, web: ['javascript:alert(1)'] })).toBe(false)
    expect(bodyShownRight({ ...body, html: true })).toBe(false)
    expect(bodyShownRight({ ...body, scroll: true })).toBe(false)
    expect(bodyShownRight({ ...body, table: false })).toBe(false)
    expect(bodyShownRight({ ...body, pageLinks: 2 })).toBe(false)
    expect(bodyShownRight({ shown: false })).toBe(false)
  })

  it('a failed read: an alert with exactly one retry, the links kept', () => {
    const err = { text: 'This page could not be read.', role: 'alert', retry: ['Try again'], links: 2 }
    expect(readFailedRight(err)).toBe(true)
    expect(readFailedRight({ ...err, role: 'status' })).toBe(false)
    expect(readFailedRight({ ...err, retry: [] })).toBe(false)
    expect(readFailedRight({ ...err, retry: ['Try again', 'Retry'] })).toBe(false)
    expect(readFailedRight({ ...err, links: 0 })).toBe(false)
  })

  it('the box: three controls on one line within 2 px, the paperclip named', () => {
    expect(composerRowRight({ n: 3, spread: 2, clip: 'Add a file' })).toBe(true)
    expect(composerRowRight({ n: 3, spread: 3, clip: 'Add a file' })).toBe(false)
    expect(composerRowRight({ n: 2, spread: 0, clip: 'Add a file' })).toBe(false)
    expect(composerRowRight({ n: 3, spread: 0, clip: null })).toBe(false)
  })

  it('citations: a button for the vault page, the address for the link page', () => {
    expect(citationsRight([{ tag: 'BUTTON' }, { tag: 'A', href: 'https://example.com/guide' }])).toBe(true)
    expect(citationsRight([{ tag: 'A', href: 'onenote:x' }, { tag: 'A', href: 'https://example.com/guide' }])).toBe(false)
    expect(citationsRight([{ tag: 'BUTTON' }])).toBe(false)
  })
})

describe('check-design-rules: the Ask fixture', () => {
  it('cites a vault page without an address first and another page by its address second', () => {
    const pages = [{ id: 'p1', title: 'With address', url: 'https://example.com/a' }, { id: 'p2', title: 'Vault page' }, { id: 'p3', title: 'Third' }]
    const { answer: a, target } = askAnswerFixture(pages)
    expect(target.id).toBe('p2')
    expect(a.sources.map((s) => [s.n, s.id, s.url])).toEqual([[1, 'p2', ''], [2, 'p1', 'https://example.com/guide']])
    expect(a.answer.paragraphs[0].sentences.map((s) => s.cites)).toEqual([[1], [2]])
  })
})
