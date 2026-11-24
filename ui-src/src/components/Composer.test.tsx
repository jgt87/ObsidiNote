import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { Composer } from './Composer'

// What the box shows before any typing (the first render; the rest is model/composerView.ts and the
// hooks, plus the rendered check scripts/check-design-rules.mjs).
const noop = () => {}

describe('Composer: the first render', () => {
  it('an empty box: Send is disabled, no "From" choice, no Ask options', () => {
    const html = renderToStaticMarkup(<Composer addTarget={null} onSend={noop} busy={false}><i className="ask-options" /></Composer>)
    // aria-disabled, never the native attribute: Send stays in the tab order (components/disabledGuard.ts).
    expect(html).toMatch(/<button type="button" class="btn btn--primary composer__send" aria-disabled="true" aria-busy="false">/)
    expect(html).not.toMatch(/\sdisabled=/)
    expect(html).not.toContain('composer-from')
    expect(html).not.toContain('ask-options')
    expect(html).not.toContain('composer__file-note')
  })

  it('says "Working…" while busy, and the paperclip is unavailable but focusable', () => {
    const html = renderToStaticMarkup(<Composer addTarget={null} onSend={noop} busy />)
    // The ring and "Working…" share the label's cell (BusyLabel), so Send keeps its width.
    expect(html).toMatch(/aria-busy="true"><span class="busy-label">.*<span class="busy-label__busy"><span class="spinner" aria-hidden="true"><\/span>Working…<\/span>/)
    expect(html).toMatch(/composer__file-btn" aria-disabled="true"/)
  })

  it('keeps the live regions mounted while they are empty, and names the box by the heading it is given', () => {
    const html = renderToStaticMarkup(<Composer addTarget={null} onSend={noop} busy={false} labelledBy="home-title" />)
    expect(html.match(/<div class="live" role="(status|alert)"><\/div>/g)?.length).toBe(3)
    expect(html).toContain('aria-labelledby="home-title"')
    expect(html).not.toContain('<label for="composer-text"')
  })

  it('starts from a kept draft (the text survives leaving the view)', () => {
    const html = renderToStaticMarkup(<Composer addTarget={null} onSend={noop} busy={false} draft={{ text: 'half a note', mode: 'add', prefillKey: -1, clearKey: 0 }} />)
    expect(html).toContain('>half a note</textarea>')
  })

  it('says why a send cannot work on its own line, with the control that can fix it, and keeps the intent line', () => {
    const html = renderToStaticMarkup(<Composer addTarget={null} onSend={noop} busy={false} block={{ text: 'Copilot is not connected', disableSend: true, retry: true }} connect={<button type="button">Connect again</button>} />)
    expect(html).toContain('<b>Copilot is not connected</b> <button type="button">Connect again</button>')
    expect(html.match(/class="composer__intent/g)?.length).toBe(2)
  })

  it('shows a note above the buttons', () => {
    expect(renderToStaticMarkup(<Composer addTarget={null} onSend={noop} busy={false} note={<span className="followup">Follow-up</span>} />)).toContain('<span class="followup">Follow-up</span>')
  })
})
