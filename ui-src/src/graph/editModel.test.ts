import { describe, expect, it } from 'vitest'
import { editProblem, editRequest, formFor, linkChoices, parseAliases, parseTopics, typeChoices } from './editModel'
import { buildIndex } from './graphIndex'
import type { GraphModel, GraphPage } from './model'

// Invented example data only.
function page(id: string, title: string, extra: Partial<GraphPage> = {}): GraphPage {
  return {
    id, title, topicIds: [], bucket: 'Notes', kind: 'concept', links: 0, isHub: false, unlinked: true, summary: '',
    onenoteUrl: '', modified: '', readOnly: false, aliases: [], site: '', archived: false, url: '', ...extra,
  }
}

const model: GraphModel = {
  source: { kind: 'vault', id: 'v1', name: 'V', readOnly: false },
  topics: [{ id: 'Security', name: 'Security', path: 'Security', parent: null, pageCount: 1, subjects: '' }, { id: 'Security/Networking', name: 'Networking', path: 'Security / Networking', parent: 'Security', pageCount: 1, subjects: '' }],
  pages: [
    page('p1', 'Zero trust', { topicIds: ['Security/Networking'], aliases: ['ZT'], summary: 'Never trust.' }),
    page('p2', 'Proxy'),
    page('p3', 'Handbook', { kind: 'link-web', bucket: 'Web links', url: 'https://example.org/h' }),
    page('p4', 'Old idea', { archived: true }),
  ],
  edges: [{ from: 'p1', to: 'p2', strength: 2, kind: 'link', reason: 'uses' }],
  types: [
    { type: 'concept', bucket: 'Notes' }, { type: 'note', bucket: 'Notes' }, { type: 'howto', bucket: 'Notes' },
    { type: 'link-web', bucket: 'Web links' }, { type: 'meeting', bucket: 'Meetings' },
  ],
}
const index = buildIndex(model)
const p1 = model.pages[0]

describe('the edit form', () => {
  it('starts from the page as it is', () => {
    const f = formFor(index, p1)
    expect(f).toEqual({ title: 'Zero trust', type: 'concept', topics: 'Security / Networking', aliases: 'ZT', summary: 'Never trust.', url: '', links: [{ target: 'p2', strength: 2, why: 'uses' }] })
  })
  it('offers only the types of the page\'s own section', () => {
    expect(typeChoices(model, p1)).toEqual(['concept', 'note', 'howto'])
    expect(typeChoices(model, model.pages[2])).toEqual(['link-web'])
    expect(typeChoices({ ...model, types: undefined }, p1)).toEqual(['concept'])
  })
  it('offers link targets that are not linked yet, not the page itself, not archived', () => {
    expect(linkChoices(index, p1, formFor(index, p1).links).map((p) => p.id)).toEqual(['p3'])
  })
  it('reads topics per line and aliases per comma, without blanks or doubles', () => {
    expect(parseTopics(' Security / Networking \n\nProjects/ Portal\nSecurity/Networking')).toEqual(['Security/Networking', 'Projects/Portal'])
    expect(parseAliases('ZT, ,Zero trust, ZT')).toEqual(['ZT', 'Zero trust'])
  })
})

describe('the edit request', () => {
  it('carries only what changed', () => {
    const before = formFor(index, p1)
    expect(editRequest(p1, 'v1', before, before)).toBeNull()
    expect(editRequest(p1, 'v1', before, { ...before, title: ' Zero trust ' })).toBeNull()
    expect(editRequest(p1, 'v1', before, { ...before, title: 'Zero-trust networking', aliases: 'ZT, ZTN' })).toEqual({ id: 'p1', vault: 'v1', title: 'Zero-trust networking', aliases: ['ZT', 'ZTN'] })
    expect(editRequest(p1, 'v1', before, { ...before, links: [] })).toEqual({ id: 'p1', vault: 'v1', links: [] })
    expect(editRequest(p1, 'v1', before, { ...before, links: [{ target: 'p2', strength: 3, why: ' uses ' }] })).toEqual({ id: 'p1', vault: 'v1', links: [{ target: 'p2', strength: 3, why: 'uses' }] })
    expect(editRequest(p1, 'v1', before, { ...before, topics: 'Security' })).toEqual({ id: 'p1', vault: 'v1', topics: ['Security'] })
  })
  it('sends an address only for a link page', () => {
    const lp = model.pages[2]
    const before = formFor(index, lp)
    expect(editRequest(lp, 'v1', before, { ...before, url: 'https://example.org/h2' })).toEqual({ id: 'p3', vault: 'v1', url: 'https://example.org/h2' })
    expect(editRequest(p1, 'v1', formFor(index, p1), { ...formFor(index, p1), url: 'https://x.example' })).toBeNull()
  })
  it('names what is wrong before sending', () => {
    const f = formFor(index, p1)
    expect(editProblem(f, false)).toBe('')
    expect(editProblem({ ...f, title: '  ' }, false)).toMatch(/empty/)
    expect(editProblem({ ...f, url: 'javascript:x' }, true)).toMatch(/http/)
    expect(editProblem({ ...f, summary: 'x'.repeat(2001) }, false)).toMatch(/2,000/)
  })
})
