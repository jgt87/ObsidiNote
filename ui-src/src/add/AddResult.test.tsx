import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { AddResult } from './AddResult'
import { normalizeAddResult } from './types'

const noop = () => {}

const added = normalizeAddResult({
  status: 'added',
  kind: 'text',
  message: 'Added: Identity-aware proxies',
  text: 'An identity-aware proxy checks who the user is.',
  page: {
    id: 'p101',
    title: 'Identity-aware proxies',
    type: 'concept',
    bucket: 'Notes',
    section: 'Notes',
    link: 'onenote:#p101',
    url: '',
    topicPath: 'Security/Networking/Zero trust',
    alsoUnder: ['Projects/Partner portal'],
    oneNotePath: ['ObsidiNote', 'Notes', 'Identity-aware proxies'],
    unfiled: false,
  },
  chips: [
    { kind: 'type', label: 'concept' },
    { kind: 'alias', label: 'IAP' },
    { kind: 'new-topic', label: 'Zero trust', path: 'Security/Networking/Zero trust' },
  ],
  links: [
    { target: 'p1', title: 'Zero-trust networking', link: 'onenote:#p1', anchor: 'checks who the user is', strength: 3, why: 'core concept' },
    { target: 'p3', title: 'VPN retirement plan', link: 'onenote:#p3', anchor: '', strength: 1, why: 'replaces it' },
  ],
  backlinks: 2,
  related: [{ id: 'p4', title: 'Device trust checklist', link: 'onenote:#p4' }],
  timings: { totalMs: 3240, inboxMs: 0, copilotMs: 0, writeMs: 0, indexMs: 0 },
  undo: { id: 'p101', pageId: '{X}', targets: ['p1', 'p3'] },
})

describe('AddResult', () => {
  it('shows the placement, chips, links with strength and the actions', () => {
    const html = renderToStaticMarkup(<AddResult result={added} onDone={noop} onUndo={noop} onEditLinks={noop} onMoveInIndex={noop} />)
    expect(html).toContain('Added: Identity-aware proxies')
    expect(html).toContain('Written to OneNote · 3.2 s')
    expect(html).toContain('<b>Identity-aware proxies</b>')
    expect(html).toContain('ObsidiNote › Notes › Identity-aware proxies')
    expect(html).toContain('also under Projects / Partner portal')
    expect(html).toContain('new topic: Zero trust')
    expect(html).toContain('aria-label="Strength 3 of 3"')
    expect(html).toContain('anchor: &quot;checks who the user is&quot;')
    expect(html).toContain('Backlinks added to 2 pages')
    expect(html).toContain('Device trust checklist')
    for (const b of ['Edit links', 'Move in index', 'Undo', 'Done']) expect(html).toContain(`>${b}</button>`)
  })
  it('leaves out actions without a callback', () => {
    const html = renderToStaticMarkup(<AddResult result={added} onDone={noop} />)
    expect(html).not.toContain('>Undo</button>')
  })
  it('shows a failure with the Inbox note and no placement', () => {
    const r = normalizeAddResult({ status: 'failed', kind: 'text', message: 'The answer holds no JSON object.', text: 'x', inbox: { pageId: '{I}', status: 'failed' } })
    const html = renderToStaticMarkup(<AddResult result={r} onDone={noop} />)
    expect(html).toContain('role="alert"')
    expect(html).toContain('kept in your Inbox')
    expect(html).not.toContain('Placed in the central index')
  })
  it('shows old vs new for an updated link, and the confirmation for an edited summary', () => {
    const base = { title: 'Contoso handbook', where: 'HR site', kind: 'page', summary: 'Old text.', keyFacts: ['Leave is 25 days'], useFor: '', sensitivity: '' }
    const next = { ...base, kind: 'site', summary: 'New text.', keyFacts: ['Leave is 26 days'] }
    const r = normalizeAddResult({
      status: 'needs-confirmation',
      kind: 'link',
      text: 'https://contoso.sharepoint.com/x',
      update: { old: base, new: next, diff: { changed: true, factsAdded: ['Leave is 26 days'], factsRemoved: ['Leave is 25 days'] }, oldAt: '2026-08-01', newAt: '', review: [] },
      confirm: { id: 'p7', question: 'Replace it?', detail: 'Your notes are not touched.', options: ['replace', 'keep'], editedText: 'My words.', proposed: next },
    })
    const html = renderToStaticMarkup(<AddResult result={r} onDone={noop} onDecide={noop} />)
    expect(html).toContain('What changed')
    expect(html).toContain('<del class="add-old">page</del>')
    expect(html).toContain('Leave is 26 days')
    expect(html).toContain('Replace your edited summary?')
    expect(html).toContain('My words.')
    expect(html).toContain('>Keep my text</button>')
  })
})
