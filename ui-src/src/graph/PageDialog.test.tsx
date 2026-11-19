import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { buildIndex } from './graphIndex'
import { normalizeGraph } from './model'
import { PageDialog } from './PageDialog'
import { syntheticGraph } from './synthetic'

// The page window's first render (the Page tab). Its decisions are tested in pageDialogModel.test.ts;
// the other tabs and the keys in the browser (scripts/check-design-rules.mjs opens the window).
const raw = syntheticGraph({ pages: 30, topics: 4, seed: 3 }) as unknown as { pages: Record<string, unknown>[]; source: object }
raw.pages[0] = { ...raw.pages[0], url: 'https://fernbrook.example/x', onenoteUrl: 'onenote:x' }
raw.pages[1] = { ...raw.pages[1], url: '', onenoteUrl: '' }
raw.pages[2] = { ...raw.pages[2], url: '', archived: true }
raw.pages[4] = { ...raw.pages[4], own: false }
const index = buildIndex(normalizeGraph(raw))
const roIndex = buildIndex(normalizeGraph({ ...raw, source: { ...raw.source, readOnly: true, readOnlyReason: 'notebook' } }))
const ids = [...index.pageById.keys()]
const noop = () => {}
const render = (i: number, extra: object = {}, idx = index) => renderToStaticMarkup(<PageDialog index={idx} pageId={ids[i]} anchorId={ids[i]} onNavigate={noop} onClose={noop} {...extra} />)

describe('PageDialog: the first render', () => {
  it('a link page: "Open link" is the primary, OneNote the second', () => {
    const html = render(0)
    expect(html).toMatch(/<a class="btn btn--primary" href="https:\/\/fernbrook.example\/x"[^>]*>Open link<\/a><a class="btn" href="onenote:x">Open in OneNote<\/a>/)
  })

  it('a page without a OneNote link: "Open in OneNote" shows, disabled', () => {
    expect(render(1)).toContain('<button type="button" class="btn btn--primary" disabled="">Open in OneNote</button>')
  })

  it('an archived page offers Restore; Archive and Delete only with the action, never read only', () => {
    expect(render(2, { onRetirePages: noop })).toContain('>Restore</button>')
    expect(render(3, { onRetirePages: noop })).toContain('>Archive</button>')
    expect(render(3)).not.toContain('>Delete</button>')
    expect(render(3, { onRetirePages: noop }, roIndex)).not.toContain('>Delete</button>')
  })

  it('a page the person made: no Archive or Delete, Edit greyed out with the reason (operator, 2026-11-16)', () => {
    const html = render(4, { onRetirePages: noop, onEditPage: async () => {} })
    expect(html).not.toContain('>Delete</button>')
    expect(html).not.toContain('>Archive</button>')
    expect(html).toContain('aria-disabled="true" aria-describedby="kg-dlg-why"')
    expect(html).toContain('You made this page in OneNote')
  })

  it('read only: Edit is shown but does nothing, with the reason', () => {
    const html = render(3, { onEditPage: async () => {} }, roIndex)
    expect(html).toContain('aria-disabled="true" aria-describedby="kg-dlg-why"')
    expect(html).toContain('id="kg-dlg-why"')
  })

  it('opens on the Page tab, names the topic tab, and renders nothing for an unknown page', () => {
    const html = render(3)
    expect(html).toMatch(/id="kg-tab-page"[^>]*aria-selected="true"/)
    expect(html).toMatch(/>Topic: [^<]+</)
    expect(renderToStaticMarkup(<PageDialog index={index} pageId="nope" anchorId="nope" onNavigate={noop} onClose={noop} />)).toBe('')
  })
})
