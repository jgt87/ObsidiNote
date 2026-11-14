import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { ORIGINS, originLabel, TYPED_LABEL, validOrigin } from '../model/origins'
import { originOfPaste } from './pasteOrigin'

// Invented snippets in the shape each app puts on the clipboard; no real mail or chat.
describe('originOfPaste', () => {
  it('knows Outlook by its namespace or its reply header block', () => {
    expect(originOfPaste('<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:outlook"><body><p class=MsoNormal>Hi team</p></body></html>')).toBe('outlook')
    expect(originOfPaste('<div id="divRplyFwdMsg"><b>From:</b> Sam</div><p>Text</p>')).toBe('outlook')
    expect(originOfPaste('<div class="elementToProof">Agenda for Monday</div>')).toBe('outlook')
  })
  it('knows Teams by its message markup', () => {
    expect(originOfPaste('<div itemprop="copy-paste-block"><p>Shall we meet at 3?</p></div>')).toBe('teams')
    expect(originOfPaste('<p data-tid="chat-pane-message">ok</p>')).toBe('teams')
  })
  it('knows Word by its namespace or Mso styles, when no mail markers are there', () => {
    expect(originOfPaste('<html xmlns:w="urn:schemas-microsoft-com:office:word"><body><p class=MsoNormal>Plan</p></body></html>')).toBe('word')
    expect(originOfPaste('<p class="MsoListParagraph">Step one</p>')).toBe('word')
  })
  it('calls any other HTML a web page, and plain text nothing', () => {
    expect(originOfPaste('<h1>Field guide</h1><p>Tides and gardens.</p>')).toBe('web')
    expect(originOfPaste('just words, no tags')).toBeNull()
    expect(originOfPaste('')).toBeNull()
    expect(originOfPaste(null)).toBeNull()
  })
})

describe('the origin list', () => {
  it('matches the server (tests/fixtures/origins.json)', () => {
    const want = JSON.parse(readFileSync(new URL('../../../tests/fixtures/origins.json', import.meta.url), 'utf8'))
    expect(ORIGINS).toEqual(want)
  })
  it('accepts only known ids, and labels "none" as typed', () => {
    expect(validOrigin('teams')).toBe('teams')
    expect(validOrigin('myspace')).toBe('')
    expect(validOrigin(3)).toBe('')
    expect(originLabel('')).toBe(TYPED_LABEL)
    expect(originLabel('word')).toBe('Word document')
  })
})
