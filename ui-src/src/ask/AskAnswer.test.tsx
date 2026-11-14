import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { AskView } from './AskStates'
import type { AskResult } from './types'

// Invented example data only. Rendered to markup on the server side: no browser needed.
const noop = () => {}
const actions = { onFollowUp: noop, onSavePage: noop, onShowOnMap: noop, onSaveOpenQuestion: noop, onUpdateLink: noop }

const answered: AskResult = {
  ok: true,
  status: 'answered',
  conversationId: 'c1',
  turn: 1,
  question: 'What did we decide about the example portal?',
  writes: 0,
  note: 'Asking never changes your notebook.',
  message: 'Answered from 2 pages.',
  path: {
    branchesTotal: 6,
    branchesPicked: 1,
    pagesTotal: 19,
    pagesPicked: 2,
    pagesRead: 2,
    invalidBranches: 0,
    invalidPages: 0,
    steps: [
      { n: 1, kind: 'index', label: 'Index' },
      { n: 2, kind: 'branches', label: 'Projects', branches: [{ path: 'Projects / Example portal', key: 'Projects/Example portal', source: 'Vault', readOnly: false, why: '' }] },
      { n: 3, kind: 'pages', label: '2 pages read', count: 2 },
    ],
    summary: 'Copilot picked 1 of 6 top-level branches, then 2 of 19 pages. Nothing outside these pages was used.',
  },
  answer: {
    confidence: 'high',
    paragraphs: [
      {
        sentences: [
          { text: 'The portal moves to a proxy.', cites: [1], unsupported: false },
          { text: 'Something without a source.', cites: [], unsupported: true },
        ],
      },
    ],
  },
  sources: [
    { n: 1, id: 'p1', key: 'p1', title: 'Example proxy page', path: 'Projects / Example portal', link: 'onenote:#example', updated: '', age: 'today', type: 'note', archived: false, sourceId: 'v1', sourceName: 'Vault', readOnly: false, stale: false, summarizedAge: '' },
    { n: 2, id: 'p2', key: 'p2', title: 'Example link page', path: 'Projects / Example portal', link: 'onenote:#example2', updated: '', age: 'last month', type: 'link-web', archived: false, sourceId: 'v1', sourceName: 'Vault', readOnly: false, stale: true, summarizedAge: '4 months ago' },
  ],
  staleLinks: [{ n: 2, id: 'p2', title: 'Example link page', summarizedAt: '2026-07-01T00:00:00', ageDays: 120, offer: 'update', label: 'Summary is 120 days old. Update it?' }],
  invalidCitations: ['p9'],
  notFound: null,
}

describe('AskView', () => {
  it('renders the path, the answer with citation chips, the sources and the actions', () => {
    const html = renderToStaticMarkup(<AskView state={{ kind: 'result', result: answered }} {...actions} />)
    expect(html).toContain('Path through the central index')
    expect(html).toContain('Copilot picked 1 of 6 top-level branches')
    expect(html).toContain('href="#ask-c1-1-src-1"')
    expect(html).toContain('id="ask-c1-1-src-1"')
    expect(html).toContain('href="onenote:#example"')
    expect(html).toContain('Summary is 120 days old. Update it?')
    expect(html).toContain('(no source)')
    expect(html).toContain('One citation pointed to a page that was not read')
    for (const label of ['Ask a follow-up', 'Save answer as a page', 'Show on map', 'Asking never changes your notebook.']) {
      expect(html).toContain(label)
    }
  })

  it('sends a cited link page to its own address and makes addresses in the answer clickable (2026-11-13)', () => {
    const withUrl: AskResult = {
      ...answered,
      answer: { confidence: 'high', paragraphs: [{ sentences: [{ text: 'See https://kb.example.org/a?id=1. It has the grades.', cites: [2], unsupported: false }] }] },
      sources: [answered.sources[0], { ...answered.sources[1], url: 'https://kb.example.org/a?id=1' }],
    }
    const html = renderToStaticMarkup(<AskView state={{ kind: 'result', result: withUrl }} {...actions} onShowPage={noop} />)
    // the address in the text is a link, without the full stop after it
    expect(html).toContain('<a class="ask-weblink" href="https://kb.example.org/a?id=1" target="_blank" rel="noopener noreferrer">https://kb.example.org/a?id=1</a>.')
    // the citation opens the link itself, not the source list or OneNote
    expect(html).toMatch(/<a class="ask-cite" href="https:\/\/kb\.example\.org\/a\?id=1" target="_blank"/)
    expect(html).not.toContain('href="#ask-c1-1-src-2"')
    // a page that is not a link opens on the map; OneNote stays a small second link
    expect(html).toContain('class="ask-src__page"')
    expect(html).toContain('aria-label="Open &quot;Example proxy page&quot; in OneNote"')
    expect(html).toContain('>Sources<')
    expect(html).not.toContain('open in OneNote)')
  })

  it('renders the not-found state with the Open question offer', () => {
    const nf: AskResult = {
      ...answered,
      status: 'not-found',
      answer: null,
      sources: [],
      staleLinks: [],
      notFound: {
        reason: 'no-branch',
        message: 'Nothing in your wiki answers this yet.',
        askNew: false,
        suggestion: { action: 'save-open-question', label: 'Save as an Open question', pageSpec: { type: 'note', openQuestion: true, origin: 'ask', title: 'q', topics: [], body: {}, links: [], references: [] } },
      },
    }
    const html = renderToStaticMarkup(<AskView state={{ kind: 'result', result: nf }} {...actions} />)
    expect(html).toContain('Nothing in your wiki answers this yet.')
    expect(html).toContain('Save as an Open question')
    expect(html).not.toContain('Save answer as a page')
  })

  it('renders the progress state with the running step marked', () => {
    const html = renderToStaticMarkup(<AskView state={{ kind: 'progress', question: 'q', step: 2 }} {...actions} />)
    expect(html).toContain('Finding branches...')
    expect(html).toContain('aria-current="step"')
    expect(html).toMatch(/aria-current="step"[^>]*>.*Choosing pages\.\.\./)
    expect(html).toContain('Writing the answer...')
  })
})
