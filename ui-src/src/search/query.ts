// Find: the search language of the knowledge graph and the quick switcher. Pure (tests: query.test.ts).
//
// A query is free words plus filters:
//   type:<kind or bucket>   prefix match ("type:meet" = kind "meeting" or bucket "Meetings")
//   topic:<path or name>    the topic and all its subtopics ("topic:security/networking")
//   site:<host>             suffix match on the page's site ("site:example.org" = www.example.org)
//   tag:<name>              a tag set by hand, exactly ("tag:licensing", tag:"follow up")
//   section:<path>          the page's section, exactly ("section:Notes", section:"Journal/2026");
//                           what a section row of the side bar asks for (model/sections.ts)
//   after:<date>            modified on or after YYYY-MM-DD, or from the start of YYYY-MM
//   before:<date>           modified before YYYY-MM-DD, or before the start of YYYY-MM
//   is:archived | is:hub | is:unlinked
// "Quoted phrases" are one word; a filter value can be quoted too (topic:"Security / Networking").
// Anything else with a colon ("x:y", "type:" with no value is ignored) stays a free word.
// Repeating type:, topic: or site: means any of them; after:, before: and is: must all hold.
//
// Matching is case- and accent-insensitive (NFD, combining marks removed). Ranking, best first:
//   0 the title starts with the words, 1 every word starts a word of the title,
//   2 the title contains every word, 3 an alias starts with the words, 3.5 title and aliases
//   contain every word, 4 ... or the topic paths, 5 ... or the summary.
// Aliases count like titles, one step lower. Ties: title (locale order), then id.

import type { GraphIndex } from '../graph/graphIndex'
import type { GraphPage, GraphTopic } from '../graph/model'

export type FilterKey = 'type' | 'topic' | 'site' | 'section' | 'tag' | 'after' | 'before' | 'is'
export type IsValue = 'archived' | 'hub' | 'unlinked'

export interface QueryFilter {
  key: FilterKey
  /** Normalized value (accents removed, lower case; topic paths without spaces round "/"). */
  value: string
  /** The value as typed, for display ("type: Meeting"). */
  label: string
  /** Where the filter sits in the query text: [start, end). */
  start: number
  end: number
}

export interface ParsedQuery {
  /** Normalized free words and phrases. */
  terms: string[]
  filters: QueryFilter[]
}

const FILTER_KEYS: readonly FilterKey[] = ['type', 'topic', 'site', 'section', 'tag', 'after', 'before', 'is']
const IS_VALUES: readonly IsValue[] = ['archived', 'hub', 'unlinked']
const DATE_RE = /^(\d{4})-(\d{2})(?:-(\d{2}))?$/

/** Lower case without accents: "Café Ångström" -> "cafe angstrom". */
export function normalizeText(s: string): string {
  return s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
}

function collapse(s: string): string {
  return s.replace(/\s+/g, ' ').trim()
}

function normalizePath(s: string): string {
  return collapse(normalizeText(s)).replace(/\s*\/\s*/g, '/')
}

function validDate(v: string): boolean {
  const m = DATE_RE.exec(v)
  if (!m) return false
  const month = Number(m[2])
  const day = m[3] === undefined ? 1 : Number(m[3])
  return month >= 1 && month <= 12 && day >= 1 && day <= 31
}

function normalizeSite(v: string): string {
  return normalizeText(v).replace(/^[a-z]+:\/\//, '').replace(/[/?#].*$/, '').replace(/^\.+|\.+$/g, '')
}

interface Token {
  text: string
  quoted: boolean
  /** For key:"value": the key part, else ''. */
  key: string
  start: number
  end: number
}

/** A quoted token starting at `start`: "..." (key '') or key:"..."; without a closing quote it runs
 *  to the end of the input. */
function quotedToken(input: string, start: number, key: string): Token {
  const open = start + (key ? key.length + 1 : 0)
  const close = input.indexOf('"', open + 1)
  const end = close < 0 ? input.length : close + 1
  return { text: input.slice(open + 1, close < 0 ? input.length : close), quoted: true, key, start, end }
}

/** The token that starts at `start` (not a space): quoted, key:"quoted", or up to the next space. */
function tokenAt(input: string, start: number): Token {
  if (input[start] === '"') return quotedToken(input, start, '')
  const keyed = /^([A-Za-z]+):"/.exec(input.slice(start))
  if (keyed) return quotedToken(input, start, keyed[1])
  let end = start
  while (end < input.length && !/\s/.test(input[end])) end++
  return { text: input.slice(start, end), quoted: false, key: '', start, end }
}

function tokenize(input: string): Token[] {
  const tokens: Token[] = []
  let i = 0
  for (;;) {
    while (i < input.length && /\s/.test(input[i])) i++
    if (i >= input.length) return tokens
    const t = tokenAt(input, i)
    tokens.push(t)
    i = t.end
  }
}

/** A filter's value in the form it is compared in: paths without spaces round "/", a bare host,
 *  else lower case without accents. */
function filterValue(key: FilterKey, label: string): string {
  if (key === 'topic' || key === 'section') return normalizePath(label)
  if (key === 'site') return normalizeSite(label)
  return collapse(normalizeText(label))
}

/** Dates must be real months and days, is: one of its words; any other value is accepted. */
function acceptedValue(key: FilterKey, value: string): boolean {
  if (key === 'after' || key === 'before') return validDate(value)
  if (key === 'is') return IS_VALUES.includes(value as IsValue)
  return true
}

/** The filter a key and value make; null when it is not a valid filter (then: a free word);
 *  'empty' for a filter without a value (then: ignored). */
function toFilter(rawKey: string, rawValue: string, start: number, end: number): QueryFilter | null | 'empty' {
  const key = rawKey.toLowerCase() as FilterKey
  if (!FILTER_KEYS.includes(key)) return null
  const label = collapse(rawValue)
  if (!label) return 'empty'
  const value = filterValue(key, label)
  if (!acceptedValue(key, value)) return null
  if (!value) return 'empty'
  return { key, value, label, start, end }
}

/** What one token adds to the query: a filter, a free word (a string), or nothing. A key:"value"
 *  that is no filter stays a word with its key; a quoted phrase is always a word. */
function readToken(t: Token): QueryFilter | string | null {
  if (t.key) {
    const f = toFilter(t.key, t.text, t.start, t.end)
    if (f === 'empty') return null
    return f ?? `${t.key}:${t.text}`
  }
  const colon = t.quoted ? -1 : t.text.indexOf(':')
  if (colon > 0) {
    const f = toFilter(t.text.slice(0, colon), t.text.slice(colon + 1), t.start, t.end)
    if (f === 'empty') return null
    if (f) return f
  }
  return t.text
}

export function parseQuery(input: string): ParsedQuery {
  const terms: string[] = []
  const filters: QueryFilter[] = []
  for (const t of tokenize(input)) {
    const r = readToken(t)
    if (typeof r === 'string') pushTerm(terms, r)
    else if (r) filters.push(r)
  }
  return { terms, filters }
}

function pushTerm(terms: string[], raw: string): void {
  const t = collapse(normalizeText(raw))
  if (t) terms.push(t)
}

export function isEmptyQuery(q: ParsedQuery): boolean {
  return q.terms.length === 0 && q.filters.length === 0
}

/** "type: Meeting" */
export function describeFilter(f: QueryFilter): string {
  return `${f.key}: ${f.label}`
}

/** The query text without one filter (spaces tidied). */
export function withoutFilter(input: string, f: QueryFilter): string {
  return collapse(input.slice(0, f.start) + ' ' + input.slice(f.end))
}

/** The query text without any filter: only the free words stay. */
export function withoutFilters(input: string): string {
  const fs = parseQuery(input).filters
  let out = input
  for (let i = fs.length - 1; i >= 0; i--) out = out.slice(0, fs[i].start) + ' ' + out.slice(fs[i].end)
  return collapse(out)
}

/** The query that shows one topic and its subtopics: topic:Security or topic:"Security / Networking". */
export function topicQuery(path: string): string {
  const p = collapse(path.replace(/"/g, ''))
  return /\s/.test(p) ? `topic:"${p}"` : `topic:${p}`
}

// ---------- matching ----------

interface PreparedPage {
  page: GraphPage
  title: string
  aliases: string[]
  titleAndAliases: string
  topics: string
  summary: string
  kind: string
  bucket: string
  /** The section path, normalized like a topic path ("journal/2026"). */
  section: string
  tags: string[]
  site: string
  date: string
}

interface PreparedTopic {
  topic: GraphTopic
  name: string
  path: string
}

interface Prepared {
  pages: PreparedPage[]
  topics: PreparedTopic[]
  /** Topic id -> its subtopic ids (direct children). */
  children: Map<string, string[]>
}

// Normalized text per model, built once per index (5,000 pages: one pass, then cheap searches).
const prepared = new WeakMap<GraphIndex, Prepared>()

function prepare(index: GraphIndex): Prepared {
  const hit = prepared.get(index)
  if (hit) return hit
  const topics = index.model.topics.map((t) => ({ topic: t, name: collapse(normalizeText(t.name)), path: normalizePath(t.path) }))
  const children = new Map<string, string[]>()
  for (const t of index.model.topics) {
    if (t.parent === null) continue
    const list = children.get(t.parent)
    if (list) list.push(t.id)
    else children.set(t.parent, [t.id])
  }
  const pathOf = new Map(index.model.topics.map((t) => [t.id, collapse(normalizeText(t.path))]))
  const pages = index.model.pages.map((p): PreparedPage => {
    const title = collapse(normalizeText(p.title))
    const aliases = p.aliases.map((a) => collapse(normalizeText(a))).filter(Boolean)
    return {
      page: p,
      title,
      aliases,
      titleAndAliases: [title, ...aliases].join(' | '),
      topics: p.topicIds.map((id) => pathOf.get(id) ?? '').join(' | '),
      summary: collapse(normalizeText(p.summary)),
      kind: collapse(normalizeText(p.kind)),
      bucket: collapse(normalizeText(p.bucket)),
      section: normalizePath(p.section ?? ''), // '' from a server older than the field
      tags: (p.tags ?? []).map((t) => collapse(normalizeText(t))),
      site: normalizeSite(p.site),
      date: /^\d{4}-\d{2}-\d{2}/.test(p.modified) ? p.modified.slice(0, 10) : '',
    }
  })
  const result = { pages, topics, children }
  prepared.set(index, result)
  return result
}

const isWordChar = (c: string | undefined) => c !== undefined && /[\p{L}\p{N}]/u.test(c)

/** True when `term` occurs in `hay` at the start of a word. */
export function startsWord(hay: string, term: string): boolean {
  let at = hay.indexOf(term)
  while (at >= 0) {
    if (at === 0 || !isWordChar(hay[at - 1])) return true
    at = hay.indexOf(term, at + 1)
  }
  return false
}

const allIn = (terms: string[], hay: string) => terms.every((t) => hay.includes(t))

function pageTier(p: PreparedPage, terms: string[]): number | null {
  const phrase = terms.join(' ')
  if (p.title.startsWith(phrase)) return 0
  if (terms.every((t) => startsWord(p.title, t))) return 1
  if (allIn(terms, p.title)) return 2
  if (p.aliases.some((a) => a.startsWith(phrase))) return 3
  if (allIn(terms, p.titleAndAliases)) return 3.5
  const withTopics = `${p.titleAndAliases} | ${p.topics}`
  if (allIn(terms, withTopics)) return 4
  if (allIn(terms, `${withTopics} | ${p.summary}`)) return 5
  return null
}

/** A topic's rank for the words, on the page scale: 0 the name starts with them, 1 every word
 *  starts a word of the name, 2 the name holds every word, 4 the path does; null: no match. */
function topicTier(t: PreparedTopic, terms: string[]): number | null {
  if (t.name.startsWith(terms.join(' '))) return 0
  if (terms.every((w) => startsWord(t.name, w))) return 1
  if (allIn(terms, t.name)) return 2
  if (allIn(terms, t.path)) return 4
  return null
}

function topicIdsFor(prep: Prepared, values: string[]): Set<string> {
  const ids = new Set<string>()
  const stack: string[] = []
  for (const t of prep.topics) {
    if (values.some((v) => t.path.startsWith(v) || t.name.startsWith(v))) stack.push(t.topic.id)
  }
  while (stack.length) {
    const id = stack.pop()!
    if (ids.has(id)) continue
    ids.add(id)
    for (const c of prep.children.get(id) ?? []) stack.push(c)
  }
  return ids
}

const IS_TESTS: Record<IsValue, (p: GraphPage) => boolean> = {
  archived: (p) => p.archived,
  hub: (p) => p.isHub,
  unlinked: (p) => p.unlinked,
}

/** Per key, whether a page passes that key's values: repeated type:, site:, section: and tag: mean
 *  any of them; after:, before: and is: must all hold. topic: is resolved to topic ids first
 *  (filterPredicate). */
const PAGE_TESTS: Record<Exclude<FilterKey, 'topic'>, (p: PreparedPage, values: string[]) => boolean> = {
  type: (p, vs) => vs.some((v) => p.kind.startsWith(v) || p.bucket.startsWith(v)),
  site: (p, vs) => vs.some((v) => p.site === v || p.site.endsWith(`.${v}`)),
  section: (p, vs) => vs.includes(p.section),
  tag: (p, vs) => vs.some((v) => p.tags.includes(v)),
  after: (p, vs) => vs.every((v) => !!p.date && p.date >= v),
  before: (p, vs) => vs.every((v) => !!p.date && p.date < v),
  is: (p, vs) => vs.every((v) => IS_TESTS[v as IsValue](p.page)),
}

/** A predicate for the filters of a query (every key used must pass); null when it has none. */
function filterPredicate(prep: Prepared, filters: QueryFilter[]): ((p: PreparedPage) => boolean) | null {
  if (!filters.length) return null
  const byKey = new Map<FilterKey, string[]>()
  for (const f of filters) byKey.set(f.key, [...(byKey.get(f.key) ?? []), f.value])
  const tests: ((p: PreparedPage) => boolean)[] = []
  for (const [key, values] of byKey) {
    if (key === 'topic') {
      const ids = topicIdsFor(prep, values)
      tests.push((p) => p.page.topicIds.some((id) => ids.has(id)))
    } else {
      const test = PAGE_TESTS[key]
      tests.push((p) => test(p, values))
    }
  }
  return (p) => tests.every((t) => t(p))
}

export interface RankedPage {
  id: string
  tier: number
}

const collator = new Intl.Collator(undefined, { sensitivity: 'base', numeric: true })

interface Hit {
  id: string
  tier: number
  /** What ties are ordered by: a page's title, a topic's path. */
  name: string
}

/** Best first: the lower tier, then the name in locale order, then the id. */
function bestFirst(hits: Hit[]): { id: string; tier: number }[] {
  hits.sort((a, b) => a.tier - b.tier || collator.compare(a.name, b.name) || (a.id < b.id ? -1 : 1))
  return hits.map((h) => ({ id: h.id, tier: h.tier }))
}

/** A page's tier for the query; null when it does not match. Filters alone match at tier 0. */
function pageHit(p: PreparedPage, q: ParsedQuery, keep: ((p: PreparedPage) => boolean) | null): number | null {
  if (keep && !keep(p)) return null
  return q.terms.length ? pageTier(p, q.terms) : 0
}

/** Pages that match, best first. An empty query matches nothing; filters alone match by title order. */
export function rankPages(index: GraphIndex, q: ParsedQuery): RankedPage[] {
  if (isEmptyQuery(q)) return []
  const prep = prepare(index)
  const keep = filterPredicate(prep, q.filters)
  const hits: Hit[] = []
  for (const p of prep.pages) {
    const tier = pageHit(p, q, keep)
    if (tier !== null) hits.push({ id: p.page.id, tier, name: p.page.title })
  }
  return bestFirst(hits)
}

export interface RankedTopic {
  id: string
  tier: number
}

/** Topics whose name or path holds the free words (none when the query has filters). */
export function rankTopics(index: GraphIndex, q: ParsedQuery): RankedTopic[] {
  if (!q.terms.length || q.filters.length) return []
  const prep = prepare(index)
  const hits: Hit[] = []
  for (const t of prep.topics) {
    const tier = topicTier(t, q.terms)
    if (tier !== null) hits.push({ id: t.topic.id, tier, name: t.topic.path })
  }
  return bestFirst(hits)
}

export type FindItem = { kind: 'topic'; id: string } | { kind: 'page'; id: string }

/** The quick switcher's list: topics and pages in one ranking (a topic before a page of the same
 *  rank), at most `limit`; `total` = every match. */
export function findAll(index: GraphIndex, input: string, limit = 50): { items: FindItem[]; total: number } {
  const q = parseQuery(input)
  const topics = rankTopics(index, q)
  const pages = rankPages(index, q)
  const items: FindItem[] = []
  let ti = 0
  let pi = 0
  while (items.length < limit && (ti < topics.length || pi < pages.length)) {
    if (ti < topics.length && (pi >= pages.length || topics[ti].tier <= pages[pi].tier)) items.push({ kind: 'topic', id: topics[ti++].id })
    else items.push({ kind: 'page', id: pages[pi++].id })
  }
  return { items, total: topics.length + pages.length }
}
