import { describe, expect, it } from 'vitest'
import type { AppStatus } from '../api'
import { attentionNotes } from './attention'

function status(over: Partial<AppStatus['oneNote']> = {}, copilot: AppStatus['copilot']['state'] = 'connected'): AppStatus {
  return {
    app: 'ObsidiNote',
    version: 'v0.0.0',
    uiPort: 8767,
    oneNote: { state: 'window', running: true, notebookOpen: true, notebook: 'ObsidiNote', ...over },
    copilot: { state: copilot, port: 9334 },
  }
}

describe('attentionNotes', () => {
  it('shows nothing when all is well', () => {
    expect(attentionNotes(status(), false)).toEqual([])
  })
  it('names a OneNote that is not running, or a notebook that is not open', () => {
    expect(attentionNotes(status({ running: false, notebookOpen: false, state: 'none' }), false).map((n) => n.id)).toEqual(['onenote'])
    expect(attentionNotes(status({ notebookOpen: false }), false)[0].text).toMatch('No ObsidiNote vault is open in OneNote.')
  })
  it('names Copilot when it is off or gone', () => {
    expect(attentionNotes(status({}, 'skipped'), false).map((n) => n.id)).toEqual(['copilot'])
    expect(attentionNotes(status({}, 'not-running'), false)[0].text).toMatch('Edge window is closed')
  })
  it('offers the refresh button when Copilot is gone, not when it was turned off for this start', () => {
    expect(attentionNotes(status({}, 'not-running'), false)[0].retry).toBe(true)
    expect(attentionNotes(status({}, 'no-tab'), false)[0].retry).toBe(true)
    expect(attentionNotes(status({}, 'skipped'), false)[0].retry).toBe(false)
    expect(attentionNotes(status({ running: false, notebookOpen: false, state: 'none' }), false)[0].retry).toBeUndefined()
  })
  it('says when the server does not answer', () => {
    expect(attentionNotes(null, true).map((n) => n.id)).toEqual(['server'])
  })
})
