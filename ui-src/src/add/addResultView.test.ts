import { describe, expect, it } from 'vitest'
import { addResultView } from './addResultView'
import { normalizeAddResult, type AddStatus } from './types'

const page = { id: 'p1', title: 'P', type: 'concept', bucket: 'Notes', section: 'Notes', link: '', url: '', topicPath: 'A', alsoUnder: [], oneNotePath: [], unfiled: false }
const summary = { title: '', where: '', kind: '', summary: 's', keyFacts: [], useFor: '', sensitivity: '' }
const view = (status: AddStatus, extra: Record<string, unknown> = {}) => addResultView(normalizeAddResult({ status, ...extra }))

describe('addResultView', () => {
  it('an added page: written, its actions, placement and links', () => {
    const v = view('added', { page, text: 't', undo: { id: 'p1', pageId: '{X}', targets: [] } })
    expect(v).toMatchObject({ written: true, actions: true, editPlacement: true, undo: true, placed: true, text: true, links: true, linksTitle: 'Links' })
  })

  it('Undo needs the undo record', () => {
    expect(view('added', { page }).undo).toBe(false)
  })

  it('a waiting item shows the waiting card and no action row', () => {
    for (const s of ['waiting', 'still-waiting', 'mismatch', 'invalid'] as const) {
      expect(view(s)).toMatchObject({ waiting: true, actions: false, written: false })
    }
  })

  it('ask instead: no action row and no text block', () => {
    expect(view('ask-instead', { text: 't' })).toMatchObject({ askInstead: true, actions: false, text: false })
  })

  it('a failed Add shows no placement and no related pages, even with a page', () => {
    expect(view('failed', { page, related: [{ id: 'p2', title: 'R', link: '' }] })).toMatchObject({ failed: true, placed: false, related: false, written: false })
  })

  it('an update shows old vs new only with the update record', () => {
    expect(view('updated').update).toBe(false)
    expect(view('kept', { update: { old: summary, new: summary } }).update).toBe(true)
    expect(view('added', { update: { old: summary, new: summary } }).update).toBe(false)
  })

  it('an update lists links only when there are new ones, titled "New links"', () => {
    expect(view('updated').links).toBe(false)
    const v = view('updated', { links: [{ target: 'p2', title: 'L', link: '', anchor: '', strength: 1, why: '' }] })
    expect(v).toMatchObject({ links: true, linksTitle: 'New links' })
  })

  it('Update of a link page: a link with a page, not while a decision is asked', () => {
    expect(view('added', { kind: 'link', page }).updateLink).toBe(true)
    expect(view('added', { kind: 'text', page }).updateLink).toBe(false)
    expect(view('needs-confirmation', { kind: 'link', page }).updateLink).toBe(false)
  })

  it('the new link summary shows under a just-added link only', () => {
    expect(view('added', { kind: 'link', update: { new: summary } }).linkSummary).toBe(true)
    expect(view('updated', { kind: 'link', update: { new: summary } }).linkSummary).toBe(false)
  })

  it('the replace question needs its request', () => {
    expect(view('needs-confirmation').confirm).toBe(false)
    expect(view('needs-confirmation', { confirm: { id: 'c', question: 'q', detail: '', options: [], editedText: '', proposed: summary } }).confirm).toBe(true)
  })
})
