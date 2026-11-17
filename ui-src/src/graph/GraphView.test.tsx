// The route-level graph view. Rendered to static markup (the project has no DOM test tooling), so
// effects do not run: GraphView itself shows its first state, loading; the error and empty states
// are GraphMessage, tested directly. The loaded map is KnowledgeGraph (KnowledgeGraph.test.tsx), and
// loading, errors and "Try again" in the browser are covered by the rendered checks (demo ?state=).
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import { GraphMessage, GraphSkeleton, GraphView } from './GraphView'

describe('GraphView: the first state is loading', () => {
  it('shows the title and one line of text, busy, and nothing drawn on a map', () => {
    const load = vi.fn(() => new Promise<never>(() => {}))
    const html = renderToStaticMarkup(<GraphView load={load} />)
    expect(html).toContain('aria-busy="true"')
    expect(html).toContain('<h1 class="kg-title">Knowledge graph</h1>')
    expect(html).toContain('<p role="status">Reading the map…</p>')
    expect(html).not.toContain('kg-stage')
    expect(html).not.toContain('<svg')
  })
  it('uses the given title, and none when the app shell shows one', () => {
    const load = () => new Promise<never>(() => {})
    expect(renderToStaticMarkup(<GraphView load={load} title="Vault map" />)).toContain('>Vault map</h1>')
    expect(renderToStaticMarkup(<GraphView load={load} title="" />)).not.toContain('<h1')
  })
})

describe('GraphSkeleton', () => {
  it('is the loading state on its own, with the default title', () => {
    expect(renderToStaticMarkup(<GraphSkeleton />)).toBe('<div class="kg" aria-busy="true"><h1 class="kg-title">Knowledge graph</h1><div class="kg-state"><p role="status">Reading the map…</p></div></div>')
  })
})

describe('GraphMessage: the error and empty states in place of the map', () => {
  it('an error is an alert with its heading, the reason and its action', () => {
    const html = renderToStaticMarkup(
      <GraphMessage title="Knowledge graph" alert heading="The map could not be loaded" text="ObsidiNote is not answering.">
        <button type="button">Try again</button>
      </GraphMessage>,
    )
    expect(html).toContain('<div class="kg-state" role="alert"><h2>The map could not be loaded</h2><p>ObsidiNote is not answering.</p><button type="button">Try again</button></div>')
  })
  it('the empty state is no alert, and leaves the heading out without a title', () => {
    const html = renderToStaticMarkup(<GraphMessage title="" heading="No pages yet" text="Everything you add shows up here." />)
    expect(html).toBe('<div class="kg"><div class="kg-state"><h2>No pages yet</h2><p>Everything you add shows up here.</p></div></div>')
  })
})
