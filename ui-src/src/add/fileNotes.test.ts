import { describe, expect, it } from 'vitest'
import { dragIsTakeable, droppedLink, fileLocatedNote, fileLookingNote, readerRemark } from './fileNotes'

describe('file notes', () => {
  it('appends the reader remark as its own sentence, or nothing', () => {
    expect(readerRemark('')).toBe('')
    expect(fileLookingNote('a.docx', readerRemark('Only the first part was kept.')).text).toBe('a.docx is in the box. Only the first part was kept. Looking for it in OneDrive…')
  })

  it('keeps the address only when exactly one synced file matched', () => {
    const found = fileLocatedNote('a.docx', '', { status: 'found', url: 'https://contoso.example/a.docx' })
    expect(found.url).toBe('https://contoso.example/a.docx')
    expect(found.note.text).toContain('the page keeps its link')
    expect(fileLocatedNote('a.docx', '', { status: 'found', url: '' }).url).toBeNull()
    const many = fileLocatedNote('a.docx', '', { status: 'many', url: '' })
    expect(many).toEqual({ note: { text: 'a.docx is in the box (more than one file matched, so no link is kept). Check it, then press Add.', error: false }, url: null })
  })

  it('a failed lookup reads as not found', () => {
    expect(fileLocatedNote('a.docx', '', null)).toEqual(fileLocatedNote('a.docx', '', { status: 'none', url: '' }))
    expect(fileLocatedNote('a.docx', '', null).note.text).toBe('a.docx is in the box. Check it, then press Add.')
  })
})

describe('drops', () => {
  it('takes files and dragged links, nothing else', () => {
    expect(dragIsTakeable(['Files'])).toBe(true)
    expect(dragIsTakeable(['text/uri-list', 'text/plain'])).toBe(true)
    expect(dragIsTakeable(['text/plain'])).toBe(false)
  })

  it('reads the first web address of a link list', () => {
    expect(droppedLink('# comment\r\n  https://contoso.example/x  \nhttps://b.example')).toBe('https://contoso.example/x')
    expect(droppedLink('file:///C:/a.txt')).toBeNull()
    expect(droppedLink('')).toBeNull()
  })
})
