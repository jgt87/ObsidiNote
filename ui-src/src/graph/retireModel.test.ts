import { describe, expect, it } from 'vitest'
import { confirmWording, parsePlan, parseResult, refusedLines, resultLines, sectionLabel } from './retireModel'

const page = (id: string, to: string, inbound = 0) => ({ id, title: `Page ${id}`, section: 'Notes', to, inbound })

describe('parsePlan / parseResult: what the server sends', () => {
  it('turns a list of one sent as an object back into a list', () => {
    const p = parsePlan({ pages: { id: 'p1', title: 'One', section: 'Notes', to: 'Archive/Notes', inbound: 2 }, refused: null })
    expect(p.pages).toEqual([{ id: 'p1', title: 'One', section: 'Notes', to: 'Archive/Notes', inbound: 2 }])
    expect(p.refused).toEqual([])
  })
  it('drops a page without an id and keeps refusals with their reason', () => {
    const p = parsePlan({ pages: [{ title: 'x' }], refused: [{ id: 'p9', title: '', reason: 'It is already archived.' }] })
    expect(p.pages).toEqual([])
    expect(refusedLines(p)).toEqual(['A page is left out: It is already archived.'])
  })
  it('reads a partial result with its failures', () => {
    const r = parseResult({ status: 'partial', message: 'Deleted: p3. OneNote keeps deleted pages in its Deleted Pages for 60 days. 1 page(s) could not be changed.', done: { id: 'p3', title: 'p3', to: '' }, failed: [{ id: 'p2', title: 'Two', error: 'OneNote refused' }], warnings: null }, 'delete')
    expect(r.status).toBe('partial')
    expect(r.done).toHaveLength(1)
    expect(resultLines(r)).toEqual([r.message, 'Two: OneNote refused'])
  })
  it('an unknown status is a failure', () => {
    expect(parseResult({ status: 'odd' }, 'archive').status).toBe('failed')
  })
})

describe('confirmWording: the question names the page and what happens', () => {
  it('archive: where it goes and that Restore brings it back', () => {
    const w = confirmWording('archive', { pages: [page('p1', 'Archive/Web links')], refused: [] })
    expect(w.title).toBe('Archive “Page p1”?')
    expect(w.lines[0]).toBe('It moves to Archive / Web links. Its links stay, and Restore puts it back where it was.')
    expect(w.confirm).toBe('Archive')
  })
  it('archive many: every place once, the count on the button', () => {
    const w = confirmWording('archive', { pages: [page('p1', 'Archive/Notes'), page('p2', 'Archive/Notes'), page('p3', 'Archive/Meetings')], refused: [] })
    expect(w.title).toBe('Archive 3 pages?')
    expect(w.lines[0]).toMatch(/^Each moves to the Archive section of its own type \(listed below\)\./)
    expect(w.confirm).toBe('Archive 3 pages')
  })
  it('delete: 60 days in Deleted Pages, the links that point here, archive as the way back', () => {
    const w = confirmWording('delete', { pages: [page('p1', '', 2)], refused: [] })
    expect(w.title).toBe('Delete “Page p1”?')
    expect(w.lines.join(' ')).toMatch(/Deleted Pages, which keeps deleted pages for 60 days/)
    expect(w.lines.join(' ')).toMatch(/2 links from other pages point here; they become plain text “\(deleted: Page p1\)”/)
    expect(w.confirm).toBe('Delete')
  })
  it('delete without inbound links says nothing about links', () => {
    expect(confirmWording('delete', { pages: [page('p1', '')], refused: [] }).lines.join(' ')).not.toMatch(/point here/)
  })
})

describe('sectionLabel', () => {
  it('spaces the path as the side bar does', () => {
    expect(sectionLabel('Archive/Journal')).toBe('Archive / Journal')
    expect(sectionLabel('Notes')).toBe('Notes')
  })
})
