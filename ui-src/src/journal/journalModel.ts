// The Journal (operator, 2026-11-17): one page per day, and a topic search across everything.
// - Without a search it lists the journal itself: the entries of each day page, newest day first,
//   plus journal pages written before day pages existed (one page per entry), each as one item.
// - With a topic (its subtopics included) or words, it lists everything relevant across all sources
//   and all days: the entries of day pages that match, and every other page that matches, on the day
//   it was made.
// - For a topic, the Decisions tab lists its decision pages, each with the pages it was derived from
//   (the pages it links to and the pages that link to it), newest first.
// Built from the knowledge graph's model (GET /api/graph of the active vault): no request of its own.
// Pure (tests: journalModel.test.ts, on tests/fixtures/journal-pages.json).
import type { GraphModel, GraphPage, GraphTopic } from '../graph/model'

export interface JournalFilter {
  /** A topic id (path); its subtopics are included. '' = none. */
  topicId: string
  /** Words to find in titles, summaries and entries. '' = none. */
  text: string
}

export interface JournalItem {
  /** Unique within the list: the page id, or page id + entry ref for an entry. */
  key: string
  /** The page to open: the day page for an entry. */
  pageId: string
  /** "HH:mm", or '' when the time is not known. */
  time: string
  title: string
  summary: string
  /** 'entry' (of a day page), 'journal' (a journal page of its own), 'page' (anything else). */
  kind: 'entry' | 'journal' | 'page'
  /** The page's type ("concept", "decision", ...) for an item that is a page. */
  type: string
  topicIds: string[]
}

export interface JournalDay {
  /** "yyyy-mm-dd", local. */
  date: string
  items: JournalItem[]
}

export interface DecisionItem {
  page: GraphPage
  date: string
  /** The pages the decision came from: linked either way, decisions themselves left out, oldest first. */
  sources: GraphPage[]
}

const pad = (n: number) => String(n).padStart(2, '0')

/** "yyyy-mm-dd" and "HH:mm" of an ISO date in local time; '' parts when it cannot be read. An entry's
 *  `at` has no zone and is local already. */
export function localParts(iso: string): { date: string; time: string } {
  if (!iso) return { date: '', time: '' }
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return { date: '', time: '' }
  return { date: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`, time: `${pad(d.getHours())}:${pad(d.getMinutes())}` }
}

const DATE_TITLE = /^\d{4}-\d{2}-\d{2}$/

/** A page of the journal: Copilot's type "log". A day page also has entries. */
const isJournal = (p: GraphPage) => p.kind === 'log'

/** Whether $ids touch the topic $topicId or one of its subtopics. */
export function inTopic(ids: string[], topicId: string): boolean {
  if (!topicId) return true
  return ids.some((t) => t === topicId || t.startsWith(`${topicId}/`))
}

function hasWords(text: string, words: string[]): boolean {
  if (!words.length) return true
  const t = text.toLowerCase()
  return words.every((w) => t.includes(w))
}

const wordsOf = (text: string) => text.toLowerCase().split(/\s+/).filter(Boolean)

/** The day a page belongs to: a day page's own date title, else the date it was made (or changed). */
function pageDay(p: GraphPage): { date: string; time: string } {
  if (isJournal(p) && p.entries?.length && DATE_TITLE.test(p.title)) return { date: p.title, time: '' }
  return localParts(p.created || p.modified)
}

/** The journal, or everything relevant to a topic or words, grouped by day: newest day first, each
 *  day's items in the order they were written. Archived pages are left out. */
export function buildJournal(model: GraphModel, filter: JournalFilter): JournalDay[] {
  const words = wordsOf(filter.text)
  const searching = Boolean(filter.topicId || words.length)
  const items: (JournalItem & { date: string })[] = []
  for (const p of model.pages) {
    if (p.archived) continue
    if (isJournal(p) && p.entries?.length) {
      for (const e of p.entries) {
        if (!inTopic(e.topicIds, filter.topicId) || !hasWords(`${e.title} ${e.summary}`, words)) continue
        const at = localParts(e.at)
        items.push({ key: `${p.id}#${e.ref}`, pageId: p.id, date: at.date, time: at.time, title: e.title, summary: e.summary, kind: 'entry', type: p.kind, topicIds: e.topicIds })
      }
      continue
    }
    if (!searching && !isJournal(p)) continue
    if (!inTopic(p.topicIds, filter.topicId) || !hasWords(`${p.title} ${p.summary} ${p.aliases.join(' ')}`, words)) continue
    const day = pageDay(p)
    if (!day.date) continue
    items.push({ key: p.id, pageId: p.id, date: day.date, time: day.time, title: p.title, summary: p.summary, kind: isJournal(p) ? 'journal' : 'page', type: p.kind, topicIds: p.topicIds })
  }
  const byDay = new Map<string, JournalItem[]>()
  for (const { date, ...item } of items) {
    const list = byDay.get(date) ?? []
    list.push(item)
    byDay.set(date, list)
  }
  return [...byDay.entries()]
    .sort((a, b) => (a[0] < b[0] ? 1 : a[0] > b[0] ? -1 : 0))
    .map(([date, list]) => ({ date, items: list.sort((a, b) => (a.time < b.time ? -1 : a.time > b.time ? 1 : 0)) }))
}

/** A topic's decision pages with the pages each was derived from, newest first. */
export function decisionsFor(model: GraphModel, topicId: string): DecisionItem[] {
  if (!topicId) return []
  const byId = new Map(model.pages.map((p) => [p.id, p]))
  const out: DecisionItem[] = []
  for (const p of model.pages) {
    if (p.archived || p.kind !== 'decision' || !inTopic(p.topicIds, topicId)) continue
    const linked = new Set<string>()
    for (const e of model.edges) {
      if (e.kind === 'mention') continue
      if (e.from === p.id) linked.add(e.to)
      else if (e.to === p.id) linked.add(e.from)
    }
    const sources = [...linked]
      .map((id) => byId.get(id))
      .filter((s): s is GraphPage => Boolean(s && !s.archived && s.kind !== 'decision'))
      .sort((a, b) => (pageDay(a).date < pageDay(b).date ? -1 : pageDay(a).date > pageDay(b).date ? 1 : 0))
    out.push({ page: p, date: pageDay(p).date, sources })
  }
  return out.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0))
}

/** Topics whose path holds every word typed, shortest path first, at most $max. */
export function matchingTopics(topics: GraphTopic[], text: string, max = 8): GraphTopic[] {
  const words = wordsOf(text)
  if (!words.length) return []
  return topics
    .filter((t) => hasWords(`${t.path} ${t.id}`, words))
    .sort((a, b) => a.id.split('/').length - b.id.split('/').length || a.path.localeCompare(b.path))
    .slice(0, max)
}

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']

/** "Tuesday 17 November 2026" for a "yyyy-mm-dd" day (English, as the rest of the window; built by
 *  hand: the browser's date formatting differs between machines). */
export function dayLabel(date: string): string {
  const [y, m, d] = date.split('-').map(Number)
  if (!y || !m || !d) return date
  const day = new Date(y, m - 1, d)
  return `${WEEKDAYS[day.getDay()]} ${d} ${MONTHS[m - 1]} ${y}`
}

/** "16 Nov 2026" for a "yyyy-mm-dd" day: the date column of the Decisions list. */
export function shortDate(date: string): string {
  const [y, m, d] = date.split('-').map(Number)
  if (!y || !m || !d) return date
  return `${d} ${MONTHS[m - 1].slice(0, 3)} ${y}`
}

/** The line under the search: what the list shows. */
export function journalCaption(filter: JournalFilter, topic: GraphTopic | undefined, days: JournalDay[]): string {
  const n = days.reduce((s, d) => s + d.items.length, 0)
  const what = n === 1 ? '1 item' : `${n} items`
  if (!filter.topicId && !filter.text.trim()) return `Your journal: ${what}, one page per day, newest first.`
  const about = [topic ? `topic "${topic.path}"` : '', filter.text.trim() ? `"${filter.text.trim()}"` : ''].filter(Boolean).join(' and ')
  return `Everything about ${about}, from all sources and all days: ${what}.`
}
