import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { BusyLabel } from './BusyLabel'
import { Notice, ViewOpening } from './Notice'

// D-084: an error there when a view opens is a status; one that arrives later an alert.
describe('Notice role', () => {
  it('is a status for an error drawn when the view opens', () => {
    const html = renderToStaticMarkup(
      <ViewOpening>
        <Notice error title="Could not read the notebook" />
      </ViewOpening>,
    )
    expect(html).toContain('role="status"')
    expect(html).not.toContain('role="alert"')
  })
  it('is an alert for an error outside a view opening (it arrived later)', () => {
    expect(renderToStaticMarkup(<Notice error title="It did not work" />)).toContain('role="alert"')
  })
  it('is a status for a message that is not an error', () => {
    expect(renderToStaticMarkup(<Notice title="Done" />)).toContain('role="status"')
  })
})

describe('BusyLabel', () => {
  it('holds the label and the ring with the busy text in one cell, so the button keeps its width', () => {
    const html = renderToStaticMarkup(<BusyLabel label="Save" busyText="Saving…" />)
    expect(html).toBe('<span class="busy-label"><span class="busy-label__idle">Save</span><span class="busy-label__busy"><span class="spinner" aria-hidden="true"></span>Saving…</span></span>')
  })
  it('keeps the label beside the ring without a busy text', () => {
    expect(renderToStaticMarkup(<BusyLabel label="Undo" />)).toContain('</span>Undo</span></span>')
  })
})
