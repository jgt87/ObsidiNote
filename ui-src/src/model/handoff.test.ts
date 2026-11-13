import { describe, expect, it } from 'vitest'
import type { AskPageSpec } from '../ask/types'
import { askAboutText, pageSpecToText } from './handoff'

const base: AskPageSpec = { type: 'note', openQuestion: false, origin: 'ask', title: 'How is a request checked?', topics: [], body: {}, links: [], references: [] }

describe('pageSpecToText', () => {
  it('writes the answer with its sources', () => {
    const t = pageSpecToText({ ...base, body: { question: 'How is a request checked?', paragraphs: ['It checks the user and the device [1].'], sources: [{ n: 1, title: 'Zero trust', path: 'Security / Networking' }] } })
    expect(t).toBe('How is a request checked?\n\nIt checks the user and the device [1].\n\nSources:\n[1] Zero trust (Security / Networking)')
  })
  it('marks an open question and keeps one-item lists from the server', () => {
    const t = pageSpecToText({ ...base, openQuestion: true, body: { question: 'Who owns the VPN?', paragraphs: null }, references: { title: 'Notes', link: '', source: 'Household' } as never })
    expect(t).toBe('Open question: How is a request checked?\n\nQuestion: Who owns the VPN?\n\nNot answered yet: nothing in the wiki answers this.\n\nAlso read: Notes (Household, read only)')
  })
})

describe('askAboutText', () => {
  it('asks about the page by its title', () => {
    expect(askAboutText('Zero trust')).toBe('What do my notes say about "Zero trust"?')
  })
})
