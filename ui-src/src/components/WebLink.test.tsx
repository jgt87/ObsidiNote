import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { opensInDefaultBrowser, WebLink } from './WebLink'

const click = (over: Partial<Parameters<typeof opensInDefaultBrowser>[0]> = {}) => ({ button: 0, ctrlKey: false, shiftKey: false, altKey: false, metaKey: false, defaultPrevented: false, ...over })

describe('WebLink (web addresses open in the default browser, 2026-11-17)', () => {
  it('sends only a plain primary click to the default browser', () => {
    expect(opensInDefaultBrowser(click())).toBe(true)
    expect(opensInDefaultBrowser(click({ ctrlKey: true }))).toBe(false)
    expect(opensInDefaultBrowser(click({ shiftKey: true }))).toBe(false)
    expect(opensInDefaultBrowser(click({ button: 1 }))).toBe(false)
    expect(opensInDefaultBrowser(click({ defaultPrevented: true }))).toBe(false)
  })
  it('stays a real link, so its address can be copied and it still opens when the server cannot', () => {
    const html = renderToStaticMarkup(<WebLink href="https://example.org/a" className="add-a" title="t" label="l">Text</WebLink>)
    expect(html).toBe('<a class="add-a" href="https://example.org/a" target="_blank" rel="noopener noreferrer" title="t" aria-label="l">Text</a>')
  })
})
