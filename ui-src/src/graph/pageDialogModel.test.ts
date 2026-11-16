import { describe, expect, it } from 'vitest'
import { buildIndex } from './graphIndex'
import { normalizeGraph } from './model'
import { dialogKeyAction, dialogKeysHint, nextTab, openButtons, pageLinks, pageMetaLine, tabLabel, twoStepsAway } from './pageDialogModel'
import { syntheticGraph } from './synthetic'

const k = (key: string, mods: Partial<{ altKey: boolean; ctrlKey: boolean; metaKey: boolean; shiftKey: boolean }> = {}) => ({ key, altKey: false, ctrlKey: false, metaKey: false, shiftKey: false, ...mods })

describe('dialogKeyAction: arrow keys in the page window', () => {
  it('Alt+arrows walk Back and Forward, wherever the focus is', () => {
    expect(dialogKeyAction(k('ArrowLeft', { altKey: true }), false, false)).toBe('back')
    expect(dialogKeyAction(k('ArrowRight', { altKey: true }), true, true)).toBe('forward')
  })
  it('Alt with another modifier is not Back/Forward', () => {
    expect(dialogKeyAction(k('ArrowLeft', { altKey: true, shiftKey: true }), false, false)).toBe('step-prev')
    expect(dialogKeyAction(k('ArrowLeft', { altKey: true, ctrlKey: true }), true, false)).toBe('tab-prev')
  })
  it('on a tab, the arrows move between tabs; in a field, they are the field\'s; elsewhere they step through linked pages', () => {
    expect(dialogKeyAction(k('ArrowRight'), true, false)).toBe('tab-next')
    expect(dialogKeyAction(k('ArrowLeft'), false, true)).toBeNull()
    expect(dialogKeyAction(k('ArrowRight'), false, false)).toBe('step-next')
    expect(dialogKeyAction(k('ArrowLeft'), false, false)).toBe('step-prev')
  })
  it('other keys are not the window\'s', () => {
    expect(dialogKeyAction(k('ArrowUp'), false, false)).toBeNull()
    expect(dialogKeyAction(k('Enter'), true, false)).toBeNull()
  })
})

describe('tabs', () => {
  it('wrap round, and name the topic', () => {
    expect(nextTab('page', 1)).toBe('topic')
    expect(nextTab('neighbourhood', 1)).toBe('page')
    expect(nextTab('page', -1)).toBe('neighbourhood')
    expect(tabLabel('topic', 'Security')).toBe('Topic: Security')
    expect(tabLabel('topic', undefined)).toBe('Topic: Unfiled')
    expect(tabLabel('neighbourhood', 'x')).toBe('Neighbourhood')
  })
})

describe('openButtons: one primary, the link page\'s own address first', () => {
  it('a link page: its address is the primary, OneNote second when known', () => {
    expect(openButtons({ url: 'https://a.example', onenoteUrl: 'onenote:x' }, false)).toEqual({ link: { href: 'https://a.example', primary: true }, onenote: { href: 'onenote:x', primary: false } })
    expect(openButtons({ url: 'https://a.example', onenoteUrl: '' }, false).onenote).toBeNull()
  })
  it('another page: OneNote is the primary, shown disabled without a link', () => {
    expect(openButtons({ url: '', onenoteUrl: 'onenote:x' }, false)).toEqual({ link: null, onenote: { href: 'onenote:x', primary: true } })
    expect(openButtons({ url: '', onenoteUrl: '' }, false)).toEqual({ link: null, onenote: { href: '', primary: true } })
  })
  it('while editing nothing here is the primary', () => {
    expect(openButtons({ url: 'https://a.example', onenoteUrl: 'onenote:x' }, true).link?.primary).toBe(false)
    expect(openButtons({ url: '', onenoteUrl: '' }, true).onenote?.primary).toBe(false)
  })
})

describe('pageMetaLine and twoStepsAway', () => {
  const model = normalizeGraph(syntheticGraph({ pages: 40, topics: 5, seed: 3 }))
  const index = buildIndex(model)
  it('says what the page is, its section and its link counts', () => {
    const hub = model.pages.find((p) => p.isHub)!
    expect(pageMetaLine(hub, 2, 7)).toMatch(/^most linked page · .* · 2 links · 7 backlinks$/)
    const plainPage = model.pages.find((p) => !p.isHub)!
    expect(pageMetaLine(plainPage, 1, 0)).toContain('1 link · 0 backlinks')
  })
  it('counts pages two links away, never the page or its own linked pages', () => {
    const p = model.pages.find((x) => (index.neighbours.get(x.id) ?? []).length > 1)!
    const near = new Set(index.neighbours.get(p.id))
    const expected = new Set<string>()
    for (const n of near) for (const m of index.neighbours.get(n) ?? []) if (m !== p.id && !near.has(m)) expected.add(m)
    expect(twoStepsAway(index, p.id)).toBe(expected.size)
    expect(twoStepsAway(index, 'nope')).toBe(0)
  })
})

describe('pageLinks and dialogKeysHint', () => {
  it('lists the links a page makes, those made to it, and only the mentions it is part of', () => {
    const index = buildIndex(normalizeGraph({
      pages: [{ id: 'a' }, { id: 'b' }, { id: 'c' }],
      edges: [{ from: 'a', to: 'b', strength: 2 }, { from: 'c', to: 'a', strength: 1 }, { from: 'b', to: 'a', strength: 1, kind: 'mention' }, { from: 'b', to: 'c', strength: 1, kind: 'mention' }],
    }))
    const l = pageLinks(index, 'a')
    expect(l.out.map((e) => e.to)).toEqual(['b'])
    expect(l.back.map((e) => e.from)).toEqual(['c'])
    expect(l.mentions.map((e) => `${e.from}>${e.to}`)).toEqual(['b>a'])
    expect(pageLinks(index, 'nope')).toEqual({ out: [], back: [], mentions: [] })
  })
  it('names the arrows only when they do something', () => {
    expect(dialogKeysHint(0, false)).toBe('Esc closes')
    expect(dialogKeysHint(3, false)).toBe('Esc closes · ← → previous or next linked page')
    expect(dialogKeysHint(0, true)).toBe('Esc closes · Alt+← → back or forward')
  })
})
