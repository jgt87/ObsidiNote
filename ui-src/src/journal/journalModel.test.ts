import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { normalizeGraph } from '../graph/model'
import { seriesCount } from '../model/series'
import { buildJournal, dayLabel, decisionsFor, inTopic, journalCaption, localParts, matchingSeries, matchingTopics, meetingSeries, shortDate } from './journalModel'

// The pages as the server sends them (tests/Journal.Tests.ps1 checks the server against this file).
const fixture = JSON.parse(readFileSync(fileURLToPath(new URL('../../../tests/fixtures/journal-pages.json', import.meta.url)), 'utf8')) as {
  topics: string[]
  pages: { id: string; title: string; kind: string; section: string; created: string; topicIds: string[]; links: { to: string; strength: number; why: string }[]; entries: unknown[] }[]
}

function model() {
  return normalizeGraph({
    source: { kind: 'vault', id: 'v1', name: 'Fixture vault', readOnly: false },
    topics: fixture.topics.map((id) => ({ id, name: id.split('/').pop(), path: id.split('/').join(' / '), parent: id.includes('/') ? id.slice(0, id.lastIndexOf('/')) : null })),
    pages: fixture.pages.map((p) => ({ ...p, links: undefined })),
    edges: fixture.pages.flatMap((p) => p.links.map((l) => ({ from: p.id, to: l.to, strength: l.strength, reason: l.why }))),
  })
}

const titles = (days: ReturnType<typeof buildJournal>) => days.map((d) => `${d.date}: ${d.items.map((i) => `${i.time} ${i.title}`.trim()).join(', ')}`)

describe('the journal without a search', () => {
  it('lists the day pages entry by entry and older journal pages, newest day first', () => {
    const days = buildJournal(model(), { topicId: '', text: '' })
    expect(titles(days)).toEqual([`2026-11-17: 09:30 Supplier call, 11:05 Budget agreed`, `${localParts('2026-11-10T09:00:00.000Z').date}: ${localParts('2026-11-10T09:00:00.000Z').time} Stand-up`])
    expect(days[0].items.map((i) => i.kind)).toEqual(['entry', 'entry'])
    expect(days[0].items[0].pageId).toBe('p201')
  })
  it('lists a meeting page on the day it was added, without a time (D-061)', () => {
    const m = model()
    const other = m.pages.find((p) => p.kind !== 'log' && p.kind !== 'decision')!
    m.pages.push({ ...other, id: 'p299', title: 'Meeting: garden sync', kind: 'meeting', created: '2026-11-17T21:34:00.000Z', archived: false })
    const day = buildJournal(m, { topicId: '', text: '' }).find((d) => d.date === localParts('2026-11-17T21:34:00.000Z').date)!
    const item = day.items.find((i) => i.pageId === 'p299')!
    expect(item.time).toBe('')
    expect(item.kind).toBe('page')
    expect(item.type).toBe('meeting')
    expect(buildJournal(m, { topicId: '', text: '' }).flatMap((d) => d.items).some((i) => i.pageId === other.id)).toBe(false)
  })
  it('shows a meeting of a series at its own start, and lists a series alone (2026-11-18)', () => {
    const m = model()
    const other = m.pages.find((p) => p.kind !== 'log' && p.kind !== 'decision')!
    m.pages.push({ ...other, id: 'm1', title: 'Garden sync · 2026-11-12', kind: 'meeting', series: 'Garden sync | Beds', meetingAt: '2026-11-12T10:00', created: '2026-11-12T21:00:00.000Z', archived: false })
    m.pages.push({ ...other, id: 'm2', title: 'Garden sync · 2026-11-13', kind: 'meeting', series: 'Garden sync Beds', meetingAt: '2026-11-13T10:00', created: '2026-11-13T21:00:00.000Z', archived: false })
    const all = buildJournal(m, { topicId: '', text: '' })
    const m1 = all.find((d) => d.date === '2026-11-12')!.items.find((i) => i.pageId === 'm1')!
    expect(m1.time).toBe('10:00')
    expect(m1.series).toBe('Garden sync | Beds')
    const list = meetingSeries(m)
    expect(list).toEqual([{ key: 'garden sync beds', name: 'Garden sync Beds', count: 2, pageId: '' }])
    expect(matchingSeries(list, 'garden')).toHaveLength(1)
    expect(matchingSeries(list, 'kitchen')).toHaveLength(0)
    const only = buildJournal(m, { topicId: '', text: '', series: 'garden sync beds' })
    expect(only.flatMap((d) => d.items.map((i) => i.pageId))).toEqual(['m2', 'm1'])
    expect(journalCaption({ topicId: '', text: '', series: 'garden sync beds' }, undefined, only, 'Garden sync Beds')).toBe('The meetings of “Garden sync Beds”: 2 meetings, newest day first.')
  })
  it('names the series page, but neither lists nor counts it as a meeting (2026-11-19)', () => {
    const m = model()
    const other = m.pages.find((p) => p.kind !== 'log' && p.kind !== 'decision')!
    m.pages.push({ ...other, id: 'm1', title: 'Garden sync · 2026-11-12', kind: 'meeting', series: 'Garden sync', meetingAt: '2026-11-12T10:00', created: '2026-11-12T21:00:00.000Z', archived: false })
    m.pages.push({ ...other, id: 's1', title: 'Garden sync (series)', kind: 'meeting', series: 'Garden sync', seriesPage: true, meetingAt: '', created: '2026-11-12T21:05:00.000Z', archived: false })
    expect(meetingSeries(m)).toEqual([{ key: 'garden sync', name: 'Garden sync', count: 1, pageId: 's1' }])
    const ids = (f: { topicId: string; text: string; series?: string }) => buildJournal(m, f).flatMap((d) => d.items.map((i) => i.pageId))
    expect(ids({ topicId: '', text: '' })).not.toContain('s1')
    expect(ids({ topicId: '', text: '', series: 'garden sync' })).toEqual(['m1'])
    expect(seriesCount(m.pages, 'Garden sync')).toBe(1)
  })
  it('leaves archived pages out', () => {
    const m = model()
    m.pages.find((p) => p.id === 'p202')!.archived = true
    expect(buildJournal(m, { topicId: '', text: '' }).map((d) => d.date)).toEqual(['2026-11-17'])
  })
})

describe('the journal searched on a topic: everything relevant, all sources, all days', () => {
  it('lists the matching entries and every page of the topic on the day it was made', () => {
    const days = buildJournal(model(), { topicId: 'Projects', text: '' })
    const all = days.flatMap((d) => d.items.map((i) => i.title))
    expect(all).toEqual(['Supplier call', 'Decision: portal vendor', 'Portal plan', 'Stand-up'])
    // The entry about Finance on the same day page is not about the topic.
    expect(all).not.toContain('Budget agreed')
    expect(days.flatMap((d) => d.items).find((i) => i.title === 'Portal plan')?.kind).toBe('page')
  })
  it('finds words in titles and summaries, together with the topic', () => {
    expect(buildJournal(model(), { topicId: '', text: 'budget' }).flatMap((d) => d.items.map((i) => i.title))).toEqual(['Budget agreed'])
    expect(buildJournal(model(), { topicId: 'Finance', text: 'office' }).flatMap((d) => d.items.map((i) => i.title))).toEqual(['Office move'])
    expect(buildJournal(model(), { topicId: 'Finance', text: 'portal' })).toEqual([])
  })
  it('includes subtopics', () => {
    expect(inTopic(['Projects/Portal'], 'Projects')).toBe(true)
    expect(inTopic(['Projects2'], 'Projects')).toBe(false)
  })
})

describe('decisions of a topic', () => {
  it('lists each decision page with the pages it came from', () => {
    const d = decisionsFor(model(), 'Projects')
    expect(d.map((x) => x.page.title)).toEqual(['Decision: portal vendor'])
    expect(d[0].sources.map((s) => s.title)).toEqual(['Portal plan'])
    expect(decisionsFor(model(), 'Finance')).toEqual([])
    expect(decisionsFor(model(), '')).toEqual([])
  })
})

describe('wording and helpers', () => {
  it('suggests topics by words in their path, shortest first', () => {
    const m = model()
    expect(matchingTopics(m.topics, 'proj').map((t) => t.id)).toEqual(['Projects', 'Projects/Portal'])
    expect(matchingTopics(m.topics, '')).toEqual([])
  })
  it('reads local dates and names days', () => {
    expect(localParts('2026-11-17T09:30')).toEqual({ date: '2026-11-17', time: '09:30' })
    expect(localParts('not a date')).toEqual({ date: '', time: '' })
    expect(dayLabel('2026-11-17')).toBe('Tuesday 17 November 2026')
    expect(shortDate('2026-11-07')).toBe('7 Nov 2026')
  })
  it('says what the list shows', () => {
    const m = model()
    const all = buildJournal(m, { topicId: '', text: '' })
    expect(journalCaption({ topicId: '', text: '' }, undefined, all)).toBe('Your journal and meetings: 3 items, newest day first.')
    const t = m.topics.find((x) => x.id === 'Projects')
    expect(journalCaption({ topicId: 'Projects', text: '' }, t, buildJournal(m, { topicId: 'Projects', text: '' }))).toBe('Everything about topic “Projects”, from all sources and all days: 4 items.')
  })
})
