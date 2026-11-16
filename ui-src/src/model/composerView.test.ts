import { describe, expect, it } from 'vitest'
import { composerView, type ComposerViewInput } from './composerView'

const base: ComposerViewInput = { text: 'A note about proxies', onlyLink: null, mode: 'auto', intent: 'add', origin: 'teams', fileLink: null, busy: false, disableSend: false }
const view = (over: Partial<ComposerViewInput> = {}) => composerView({ ...base, ...over })

describe('composerView', () => {
  it('a typed or pasted text to add: "From" shows and goes with the send', () => {
    expect(view()).toMatchObject({ empty: false, showFrom: true, sendOrigin: 'teams', asking: false, canSend: true })
  })

  it('no "From" for an empty box, a link alone, Ask mode or a text read as a question', () => {
    for (const over of [{ text: '  \n' }, { onlyLink: 'https://contoso.example/x' }, { mode: 'ask' as const }, { intent: 'ask' as const }]) {
      expect(view(over)).toMatchObject({ showFrom: false, sendOrigin: '' })
    }
  })

  it('Ask options show in Ask mode, or in Auto when the text reads as a question; not in Add mode', () => {
    expect(view({ mode: 'ask' }).asking).toBe(true)
    expect(view({ mode: 'auto', intent: 'ask' }).asking).toBe(true)
    expect(view({ mode: 'add', intent: 'ask' }).asking).toBe(false)
    expect(view({ mode: 'auto', intent: undefined }).asking).toBe(false)
  })

  it('keeps a dropped file\'s address while "From" is File and the box holds text, and says when it is dropped', () => {
    const fileLink = { url: 'https://contoso.example/a.docx' }
    expect(view({ fileLink, origin: 'file' })).toMatchObject({ liveFileUrl: fileLink.url, linkDropped: false })
    expect(view({ fileLink, origin: 'teams' })).toMatchObject({ liveFileUrl: '', linkDropped: true })
    expect(view({ fileLink, origin: 'file', text: '' })).toMatchObject({ liveFileUrl: '', linkDropped: false })
    expect(view({ fileLink: null, origin: 'file' })).toMatchObject({ liveFileUrl: '', linkDropped: false })
  })

  it('sends only with text, when not busy and when sending can work', () => {
    expect(view({ text: '' }).canSend).toBe(false)
    expect(view({ busy: true }).canSend).toBe(false)
    expect(view({ disableSend: true }).canSend).toBe(false)
  })
})
