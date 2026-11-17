import { describe, expect, it } from 'vitest'
import { normalizeActivity, stateLine, waitedFor, waitingItems, type ActivityItem } from './activityModel'

const item = (over: Partial<ActivityItem>): ActivityItem => ({
  inboxId: 'i1', title: 'Item', state: 'added', kind: 'text', requestKind: 'classify', updated: '2026-11-14T08:00:00Z', since: '', reason: '',
  filedAs: '', filedTitle: '', filedType: '', entry: '', canCheck: false, canRemove: false, canUndo: false, ...over,
})

describe('a journal entry in History (one page per day)', () => {
  it('names the day page and keeps the entry for Undo', () => {
    expect(stateLine(item({ entry: 'ra1b2c3d4', filedTitle: '2026-11-17' }))).toBe('An entry in the journal of 2026-11-17.')
    const list = normalizeActivity({ items: [{ inboxId: 'i9', state: 'added', filedAs: 'p201', filedTitle: '2026-11-17', entry: 'ra1b2c3d4' }] })
    expect(list.items[0].entry).toBe('ra1b2c3d4')
    expect(normalizeActivity({ items: [{ inboxId: 'i8' }] }).items[0].entry).toBe('')
  })
})

describe('activity', () => {
  it('takes one item sent as an object (Windows PowerShell) and drops rows without an id', () => {
    const l = normalizeActivity({ items: { inboxId: 'i1', state: 'waiting', canCheck: true }, canChange: true })
    expect(l.items).toHaveLength(1)
    expect(l.items[0]).toMatchObject({ state: 'waiting', canCheck: true, title: 'Untitled item' })
    expect(normalizeActivity({ items: [{ state: 'added' }, null] }).items).toHaveLength(0)
    expect(normalizeActivity({ items: [{ inboxId: 'x', state: 'exploded' }] }).items[0].state).toBe('working')
  })
  it('says what happened in words', () => {
    // after the bold state word ("Added.", "Not added."), never repeating it
    expect(stateLine(item({ state: 'added', filedTitle: 'Zero trust' }))).toBe('Now the page Zero trust.')
    expect(stateLine(item({ state: 'failed', reason: 'Copilot gave no answer' }))).toBe('Copilot gave no answer.')
    expect(stateLine(item({ state: 'failed' }))).toBe('')
    expect(stateLine(item({ state: 'gone' }))).toMatch(/no longer in your wiki/)
  })
  it('says how long an item has waited', () => {
    const now = new Date('2026-11-14T12:00:00Z')
    expect(waitedFor('2026-11-14T11:55:00Z', now)).toBe('for 5 min')
    expect(waitedFor('2026-11-14T09:00:00Z', now)).toBe('for 3 h')
    expect(waitedFor('2026-11-10T12:00:00Z', now)).toBe('for 4 days')
    expect(waitedFor('', now)).toBe('')
  })
  it('lists only waiting items, the longest wait first', () => {
    const l = { canChange: true, vaultId: 'v1', items: [item({ inboxId: 'a', state: 'waiting', since: '2026-11-14T10:00:00Z' }), item({ inboxId: 'b', state: 'added' }), item({ inboxId: 'c', state: 'waiting', since: '2026-11-14T08:00:00Z' })] }
    expect(waitingItems(l).map((i) => i.inboxId)).toEqual(['c', 'a'])
  })
})
