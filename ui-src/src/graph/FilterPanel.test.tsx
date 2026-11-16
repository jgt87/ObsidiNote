import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { FilterButton, type MapShow } from './FilterPanel'
import { emptyFilter } from './filters'
import { buildIndex } from './graphIndex'
import { normalizeGraph } from './model'

// Invented example data only.
const withAll = buildIndex(
  normalizeGraph({
    source: { kind: 'vault' },
    topics: [{ id: 't1', name: 'Methods' }],
    pages: [
      { id: 'a', title: 'A', kind: 'note', topicIds: ['t1'], tags: ['x'] },
      { id: 'b', title: 'B', kind: 'link-web', url: 'https://site.example/b', topicIds: ['t1'] },
      { id: 'c', title: 'C', kind: 'note', topicIds: [], archived: true },
    ],
  }),
)
const notesOnly = buildIndex(normalizeGraph({ source: { kind: 'vault' }, topics: [{ id: 't1', name: 'Methods' }], pages: [{ id: 'a', title: 'A', kind: 'note', topicIds: ['t1'] }] }))
const show: MapShow = { links: true, mentions: false, hubsOnly: false }
const render = (index = withAll, opts: { show?: boolean; staleDays?: number; filter?: ReturnType<typeof emptyFilter> } = {}) =>
  renderToStaticMarkup(<FilterButton index={index} filter={opts.filter ?? emptyFilter()} onChange={() => {}} show={opts.show ? show : undefined} onShow={opts.show ? () => {} : undefined} staleDays={opts.staleDays} />)

describe('FilterButton: which parts the panel holds', () => {
  it('"Show on the map" only with the map\'s choices (graph mode)', () => {
    expect(render(withAll, { show: true })).toContain('Show on the map')
    expect(render(withAll)).not.toContain('Show on the map')
  })
  it('the stale-links box only when there are link pages, with the vault\'s days', () => {
    expect(render(withAll, { staleDays: 30 })).toContain('Link summaries older than 30 days')
    expect(render(withAll)).toContain('Link summaries older than 90 days')
    expect(render(notesOnly)).not.toContain('Link summaries older')
  })
  it('the Tag group only when a page has a tag; the page-state boxes always', () => {
    expect(render(withAll)).toContain('<legend>Tag</legend>')
    expect(render(notesOnly)).not.toContain('<legend>Tag</legend>')
    for (const html of [render(withAll), render(notesOnly)]) {
      expect(html).toContain('Only pages without links')
      expect(html).toContain('Show archived')
    }
  })
  it('the button counts the choices made', () => {
    expect(render()).toMatch(/Filter<\/button>/)
    expect(render(withAll, { filter: { ...emptyFilter(), types: new Set(['note']), unlinkedOnly: true } })).toMatch(/Filter · 2<\/button>/)
  })
})
