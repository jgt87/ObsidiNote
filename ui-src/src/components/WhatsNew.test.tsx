import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import type { WhatsNewNote } from '../model/whatsNew'
import { WhatsNew, WhatsNewNotice } from './WhatsNew'

const noop = () => {}
const lines: WhatsNewNote[] = [
  { kind: 'Added', text: 'Find. Look up a page by its title.' },
  { kind: 'Added', text: 'Paste keeps headings, lists and tables.' },
  { kind: 'Changed', text: 'The box is higher.' },
  { kind: 'Fixed', text: 'A crash on start.' },
]

describe('WhatsNewNotice', () => {
  it('says which version, shows 3 lines with their kind, then "Show all"', () => {
    const html = renderToStaticMarkup(<WhatsNewNotice info={{ version: 'v1.2.0', updated: true, notes: lines }} onDismiss={noop} />)
    expect(html).toContain('Updated to v1.2.0')
    expect(html.match(/<li /g)).toHaveLength(3)
    expect(html).toContain('<span class="whats-new__kind">Changed</span>')
    expect(html).not.toContain('A crash on start.')
    expect(html).toContain('Show all (4)')
    expect(html).toContain('>Dismiss</button>')
  })
  it('shows every line and no "Show all" when expanded or with 3 lines or fewer', () => {
    const all = renderToStaticMarkup(<WhatsNewNotice info={{ version: 'v1.2.0', updated: true, notes: lines }} onDismiss={noop} startExpanded />)
    expect(all.match(/<li /g)).toHaveLength(4)
    expect(all).not.toContain('Show all')
    const few = renderToStaticMarkup(<WhatsNewNotice info={{ version: 'v1.2.0', updated: true, notes: lines.slice(0, 2) }} onDismiss={noop} />)
    expect(few).not.toContain('Show all')
  })
  it('says so when the version has no notes', () => {
    const html = renderToStaticMarkup(<WhatsNewNotice info={{ version: 'v1.2.0', updated: true, notes: [] }} onDismiss={noop} />)
    expect(html).toContain('No notes for this version.')
  })
})

describe('WhatsNew', () => {
  it('renders nothing before the server answered (and nothing on an ordinary start)', () => {
    expect(renderToStaticMarkup(<WhatsNew />)).toBe('')
  })
})
