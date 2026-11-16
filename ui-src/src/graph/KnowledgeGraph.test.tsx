// The knowledge graph view's first render: what it shows for a model and its props. Rendered to
// static markup (the project has no DOM test tooling), so effects do not run: the stage keeps the
// aspect it takes from the window's size, and pointer, keys and dialogs are covered by the
// rendered checks (scripts/check-design-rules.mjs) instead.
import { renderToStaticMarkup } from 'react-dom/server'
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest'
import { KnowledgeGraph, type KnowledgeGraphProps } from './KnowledgeGraph'
import { normalizeGraph, type GraphModel } from './model'

// Invented example data only.
function model(source: Record<string, unknown> = {}): GraphModel {
  return normalizeGraph({
    source: { kind: 'vault', id: 'v1', name: 'Test vault', readOnly: false, ...source },
    topics: [
      { id: 't1', name: 'Methods' },
      { id: 't2', name: 'Security' },
    ],
    pages: [
      { id: 'p1', title: 'Zero-trust networking', kind: 'note', topicIds: ['t2'], tags: ['review'] },
      { id: 'p2', title: 'Threat modelling', kind: 'note', topicIds: ['t1', 't2'] },
      { id: 'p3', title: 'Partner portal', kind: 'link-web', url: 'https://portal.example/home', topicIds: ['t1'] },
      { id: 'p4', title: 'Old plan', kind: 'note', topicIds: ['t1'], archived: true },
    ],
    edges: [
      { from: 'p1', to: 'p2', strength: 3 },
      { from: 'p3', to: 'p2', strength: 1 },
    ],
  })
}

const render = (props: Partial<KnowledgeGraphProps> = {}) => renderToStaticMarkup(<KnowledgeGraph model={model()} {...props} />)
const text = (html: string) => html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ')

beforeAll(() => {
  // The stage takes its first aspect from the window's size; nothing else of the window is read.
  vi.stubGlobal('window', { innerWidth: 1440, innerHeight: 900 })
})
afterAll(() => {
  vi.unstubAllGlobals()
})

describe('KnowledgeGraph: the heading', () => {
  it('names the source and counts every page, the topics and links; says how many archived pages are hidden', () => {
    const t = text(render())
    expect(t).toContain('Knowledge graph')
    expect(t).toContain('Test vault · 4 pages in 2 topics · 2 links · 1 archived hidden')
  })
  it('leaves the heading out when the app shell shows one', () => {
    expect(render({ title: '' })).not.toContain('<h1')
  })
})

describe('KnowledgeGraph: the map or the List', () => {
  it('starts on the map: the stage, with a dot per shown page and no table', () => {
    const html = render()
    expect(html).toContain('class="kg-stage"')
    expect(html.match(/<circle[^>]*class="kg-dot[^"]*"[^>]*data-id=|<circle[^>]*data-id="p\d"[^>]*class="kg-dot/g)?.length).toBe(3)
    expect(html).not.toContain('kg-tbl__table')
  })
  it('starts on the List when asked: the table with every shown page, and no stage', () => {
    const html = render({ initialMode: 'list' })
    expect(html).toContain('kg-tbl__table')
    expect(html).not.toContain('class="kg-stage"')
    for (const title of ['Zero-trust networking', 'Threat modelling', 'Partner portal']) expect(html).toContain(title)
    expect(html).not.toContain('Old plan')
  })
  it('offers the map\'s "Show on the map" choices in the Filter panel only on the map', () => {
    expect(render()).toContain('Show on the map')
    expect(render({ initialMode: 'list' })).not.toContain('Show on the map')
  })
})

describe('KnowledgeGraph: pages shown first ("Show on map" from an Ask answer)', () => {
  it('focuses the first page that exists, as the keyboard would: its card is open', () => {
    const html = render({ focusIds: ['gone', 'p3', 'p1'] })
    expect(html).toContain('kg-card')
    expect(text(html.slice(html.indexOf('kg-card')))).toContain('Partner portal')
  })
  it('opens no card without pages to show first, or when none of them exists', () => {
    expect(render()).not.toContain('kg-card')
    expect(render({ focusIds: ['gone'] })).not.toContain('kg-card')
  })
})

describe('KnowledgeGraph: read only', () => {
  const banner = (html: string) => {
    const at = html.indexOf('ro-banner')
    return at < 0 ? null : text(html.slice(at, html.indexOf('</div></div>', at)))
  }
  it('no banner for a source that can be written', () => {
    expect(banner(render())).toBeNull()
  })
  it('a connected notebook says it is only read, with no "Check again"', () => {
    const b = banner(render({ model: model({ kind: 'notebook', readOnly: true, readOnlyReason: 'notebook' }), onCheckAgain: () => {} }))
    expect(b).toContain('This is a connected notebook: ObsidiNote reads it and never writes in it.')
    expect(b).not.toContain('Check again')
  })
  it('a vault held elsewhere uses the app\'s own sentence, offers "Check again" and shows what it found', () => {
    const b = banner(render({ model: model({ readOnly: true, readOnlyReason: 'lease' }), readOnlyNote: 'Held by an earlier start on this PC.', onCheckAgain: () => {}, checkResult: 'Still held.' }))
    expect(b).toContain('Held by an earlier start on this PC.')
    expect(b).toContain('Still held.')
    expect(b).toContain('Check again')
  })
})
