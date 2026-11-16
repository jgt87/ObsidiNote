import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { Composer } from './Composer'

// What the box shows before any typing (the first render; the rest is model/composerView.ts and the
// hooks, plus the rendered check scripts/check-design-rules.mjs).
const noop = () => {}

describe('Composer: the first render', () => {
  it('an empty box: Send is disabled, no "From" choice, no Ask options', () => {
    const html = renderToStaticMarkup(<Composer addTarget={null} onSend={noop} busy={false}><i className="ask-options" /></Composer>)
    expect(html).toMatch(/<button type="button" class="btn btn--primary composer__send" disabled="" aria-busy="false">/)
    expect(html).not.toContain('composer-from')
    expect(html).not.toContain('ask-options')
    expect(html).not.toContain('composer__file-note')
  })

  it('says "Working…" while busy, and the paperclip is disabled', () => {
    const html = renderToStaticMarkup(<Composer addTarget={null} onSend={noop} busy />)
    expect(html).toContain('aria-busy="true">Working…</button>')
    expect(html).toMatch(/composer__file-btn" disabled=""/)
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
