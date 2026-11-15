import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { ORIGINS, originLabel, TYPED_LABEL, validOrigin } from '../model/origins'
import { followMark, newMark, originOfPaste, originStillApplies, pasteMark } from './pasteOrigin'

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

describe('the From choice follows the pasted text (code review 2026-11-14)', () => {
  it('remembers the first line of a paste', () => {
    expect(pasteMark('\n  Re: budget meeting \nsecond line')).toBe('Re: budget meeting')
  })
  it('applies while the pasted text is in the box, not after it is replaced', () => {
    const mark = pasteMark('Hi team, the release moves to Friday.')
    expect(originStillApplies('Note: Hi team, the release moves to Friday. More.', mark)).toBe(true)
    expect(originStillApplies('My own typed text', mark)).toBe(false)
  })
  it('always applies without a mark (chosen by hand)', () => {
    expect(originStillApplies('anything', '')).toBe(true)
  })
  it('keeps the choice when one line of the paste is edited, as long as another is still there', () => {
    const mark = pasteMark('Hi team, the release moves to Friday.\nPlease update the plan before Thursday noon.\nThanks')
    expect(originStillApplies('The release moves to Friday.\nPlease update the plan before Thursday noon.', mark)).toBe(true)
    expect(originStillApplies('Something else entirely, typed over it', mark)).toBe(false)
  })
  it('gives a short paste no mark, so it never matches text typed over it', () => {
    expect(pasteMark('Hi')).toBe('')
    expect(pasteMark('-\nok')).toBe('')
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

describe('followMark: the From choice follows the pasted text', () => {
  const pasted = 'Quarterly numbers for the partner portal\nSecond line of the mail body'
  const mark = newMark(pasteMark(pasted), 'outlook')

  it('waits until the paste has landed, then keeps the choice while the text is there', () => {
    const r = followMark(mark, pasted)
    expect(r.origin).toBeUndefined()
    expect(r.mark).toMatchObject({ seen: true, lost: false })
  })

  it('drops the choice once the pasted text is gone, and brings it back with the text (Ctrl+Z)', () => {
    const seen = followMark(mark, pasted).mark
    const gone = followMark(seen, 'something else typed over it')
    expect(gone).toEqual({ mark: { ...seen, lost: true }, origin: '' })
    expect(followMark(gone.mark, 'something else typed again').origin).toBeUndefined()
    expect(followMark(gone.mark, pasted)).toEqual({ mark: { ...seen, lost: false }, origin: 'outlook' })
  })

  it('does not drop the choice before the paste has landed', () => {
    expect(followMark(mark, 'text from before the paste')).toEqual({ mark })
  })

  it('an emptied box forgets the mark and the choice', () => {
    expect(followMark(followMark(mark, pasted).mark, '   ')).toEqual({ mark: newMark(), origin: '' })
  })

  it('a choice made by hand (no mark) stays whatever is typed', () => {
    expect(followMark(newMark(), 'anything')).toEqual({ mark: newMark() })
  })
})
