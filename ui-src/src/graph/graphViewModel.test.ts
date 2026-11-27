import { describe, expect, it } from 'vitest'
import { emptyFilter } from './filters'
import { buildIndex } from './graphIndex'
import { areaCount, areaWordOf, closeFocus, isSearchSlash, isTypingTarget, listNarrowing, readOnlyBanner, searchKeyAction, toggleTagChoice } from './graphViewModel'
import { normalizeGraph, UNFILED_ID } from './model'

const key = (k: string, mods: Partial<{ ctrlKey: boolean; metaKey: boolean; altKey: boolean }> = {}) => ({ key: k, ctrlKey: false, metaKey: false, altKey: false, ...mods })
const field = { closest: (s: string) => (s.includes('input') ? {} : null) }
const plainElement = { closest: () => null, isContentEditable: false }

describe('"/" focuses the search', () => {
  it('on a bare "/" outside fields and dialogs', () => {
    expect(isSearchSlash(key('/'), plainElement, false)).toBe(true)
    expect(isSearchSlash(key('/'), null, false)).toBe(true)
  })
  it('not with a modifier, not while a dialog is open, not while typing', () => {
    for (const m of [{ ctrlKey: true }, { metaKey: true }, { altKey: true }]) expect(isSearchSlash(key('/', m), plainElement, false)).toBe(false)
    expect(isSearchSlash(key('/'), plainElement, true)).toBe(false)
    expect(isSearchSlash(key('/'), field, false)).toBe(false)
    expect(isSearchSlash(key('/'), { closest: () => null, isContentEditable: true }, false)).toBe(false)
    expect(isSearchSlash(key('?'), plainElement, false)).toBe(false)
  })
  it('knows a typing target', () => {
    expect(isTypingTarget(field)).toBe(true)
    expect(isTypingTarget(plainElement)).toBe(false)
    expect(isTypingTarget(null)).toBe(false)
  })
})

describe('closeFocus: where focus goes when the page window closes', () => {
  const stage = {}
  const body = {}
  const base = { mode: 'graph' as const, openedBy: 'keyboard' as const, last: 'p2', back: stage, stage, body }
  it('opened with a click on the map: nothing stays focused', () => {
    expect(closeFocus({ ...base, openedBy: 'pointer' })).toBe('clear')
  })
  it('opened with the keyboard from the map, the page, or nowhere: back to the map', () => {
    expect(closeFocus(base)).toBe('stage')
    expect(closeFocus({ ...base, back: body })).toBe('stage')
    expect(closeFocus({ ...base, back: null })).toBe('stage')
  })
  it('from anywhere else, or in the List, or with no page shown: back to what had the focus', () => {
    expect(closeFocus({ ...base, back: {} })).toBe('back')
    expect(closeFocus({ ...base, mode: 'list' })).toBe('back')
    expect(closeFocus({ ...base, mode: 'list', openedBy: 'pointer' })).toBe('back')
    expect(closeFocus({ ...base, last: undefined })).toBe('back')
  })
})

describe('searchKeyAction: keys in the search box', () => {
  const m = ['a', 'b', 'c']
  it('Enter opens the focused result, else the first', () => {
    expect(searchKeyAction('Enter', m, 'b', 'x')).toEqual({ kind: 'open', id: 'b' })
    expect(searchKeyAction('Enter', m, 'z', 'x')).toEqual({ kind: 'open', id: 'a' })
    expect(searchKeyAction('Enter', [], null, 'x')).toBeNull()
  })
  it('the arrows step through the results and wrap around', () => {
    expect(searchKeyAction('ArrowDown', m, null, 'x')).toEqual({ kind: 'pick', id: 'a' })
    expect(searchKeyAction('ArrowDown', m, 'c', 'x')).toEqual({ kind: 'pick', id: 'a' })
    expect(searchKeyAction('ArrowUp', m, null, 'x')).toEqual({ kind: 'pick', id: 'c' })
    expect(searchKeyAction('ArrowUp', m, 'a', 'x')).toEqual({ kind: 'pick', id: 'c' })
    expect(searchKeyAction('ArrowUp', m, 'b', 'x')).toEqual({ kind: 'pick', id: 'a' })
    expect(searchKeyAction('ArrowDown', null, null, 'x')).toBeNull()
  })
  it('Esc clears a search; other keys are the field\'s own', () => {
    expect(searchKeyAction('Escape', m, null, 'x')).toEqual({ kind: 'clear' })
    expect(searchKeyAction('Escape', m, null, '')).toBeNull()
    expect(searchKeyAction('a', m, null, 'x')).toBeNull()
  })
})

describe('areaCount: the header\'s count of areas', () => {
  const base = { sources: 4, tags: 2, topics: 6 }
  it('names what the map\'s areas are', () => {
    expect(areaCount({ ...base, mode: 'graph', groupBy: 'topics' })).toEqual({ joiner: ' in ', areas: '6 topics' })
    expect(areaCount({ ...base, mode: 'graph', groupBy: 'sources' })).toEqual({ joiner: ' in ', areas: '4 sources' })
    expect(areaCount({ ...base, mode: 'graph', groupBy: 'tags' })).toEqual({ joiner: ', ', areas: '2 tags' })
  })
  it('the List always counts topics', () => {
    expect(areaCount({ ...base, mode: 'list', groupBy: 'tags' })).toEqual({ joiner: ' in ', areas: '6 topics' })
  })
})

describe('toggleTagChoice: the chips of the Tags grouping', () => {
  const all = ['a', 'b', 'c']
  it('takes a tag out of "every tag", and puts it back to "every tag" again', () => {
    const one = toggleTagChoice(null, all, 'b')
    expect([...(one ?? [])]).toEqual(['a', 'c'])
    expect(toggleTagChoice(one, all, 'b')).toBeNull()
  })
  it('adds a tag to a choice that holds fewer than all', () => {
    expect([...(toggleTagChoice(new Set(['a']), all, 'c') ?? [])]).toEqual(['a', 'c'])
    expect([...(toggleTagChoice(new Set(['a']), all, 'a') ?? [])]).toEqual([])
  })
})

describe('areaWordOf and readOnlyBanner', () => {
  it('names an area by the grouping drawn', () => {
    expect(areaWordOf({ tags: true, sources: true })).toBe('tag')
    expect(areaWordOf({ tags: false, sources: true })).toBe('source')
    expect(areaWordOf({ tags: false, sources: false })).toBe('topic')
  })
  it('a lease uses the app\'s own sentence and offers Check again; other reasons do not', () => {
    const check = () => {}
    expect(readOnlyBanner({ readOnlyReason: 'lease' }, 'general', 'Another PC seems to be writing.', 'Still held.', check)).toEqual({ text: 'Another PC seems to be writing.', onCheck: check, result: 'Still held.' })
    expect(readOnlyBanner({ readOnlyReason: 'lease' }, 'general', undefined, '', check)).toEqual({ text: 'general', onCheck: check, result: '' })
    expect(readOnlyBanner({ readOnlyReason: 'notebook' }, 'A connected notebook.', 'ignored', 'ignored', check)).toEqual({ text: 'A connected notebook.', onCheck: undefined, result: '' })
  })
})

describe('listNarrowing: what narrows the List, by name', () => {
  // Invented example data only.
  const index = buildIndex(normalizeGraph({
    source: { kind: 'vault', id: 'v1', name: 'Test vault', readOnly: false },
    topics: [{ id: 't1', name: 'Methods' }],
    pages: [{ id: 'p1', title: 'Threat modelling', kind: 'note', topicIds: ['t1'] }],
    edges: [],
  }))
  it('names the search, the page focused on and the topics; Unfiled by its name', () => {
    const f = { ...emptyFilter(), topics: new Set(['t1', UNFILED_ID]), focus: { id: 'p1', depth: 1 as const } }
    expect(listNarrowing(f, ' zero ', index)).toEqual(['search “zero”', 'around Threat modelling', 'topic: Methods, Unfiled'])
  })
  it('shows an id the model no longer has as it is, and nothing without a filter or search', () => {
    const f = { ...emptyFilter(), topics: new Set(['gone']), focus: { id: 'p9', depth: 1 as const } }
    expect(listNarrowing(f, '', index)).toEqual(['around p9', 'topic: gone'])
    expect(listNarrowing(emptyFilter(), '', index)).toEqual([])
  })
})
