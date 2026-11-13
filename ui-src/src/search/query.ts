// Find: the search language of the knowledge graph and the quick switcher. Pure (tests: query.test.ts).
//
// A query is free words plus filters:
//   type:<kind or bucket>   prefix match ("type:meet" = kind "meeting" or bucket "Meetings")
//   topic:<path or name>    the topic and all its subtopics ("topic:security/networking")
//   site:<host>             suffix match on the page's site ("site:example.org" = www.example.org)
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

export type FilterKey = 'type' | 'topic' | 'site' | 'after' | 'before' | 'is'
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

const FILTER_KEYS: readonly FilterKey[] = ['type', 'topic', 'site', 'after', 'before', 'is']
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

function tokenize(input: string): Token[] {
  const tokens: Token[] = []
  let i = 0
  const n = input.length
  while (i < n) {
    while (i < n && /\s/.test(input[i])) i++
    if (i >= n) break
    const start = i
    if (input[i] === '"') {
      const close = input.indexOf('"', i + 1)
      const end = close < 0 ? n : close + 1
      tokens.push({ text: input.slice(i + 1, close < 0 ? n : close), quoted: true, key: '', start, end })
      i = end
      continue
    }
    const keyed = /^([A-Za-z]+):"/.exec(input.slice(i))
    if (keyed) {
      const open = i + keyed[1].length + 1
      const close = input.indexOf('"', open + 1)
      const end = close < 0 ? n : close + 1
      tokens.push({ text: input.slice(open + 1, close < 0 ? n : close), quoted: true, key: keyed[1], start, end })
      i = end
      continue
    }
    while (i < n && !/\s/.test(input[i])) i++
    tokens.push({ text: input.slice(start, i), quoted: false, key: '', start, end: i })
  }
  return tokens
}

/** The filter a key and value make, or null when it is not a valid filter (then: a free word). */
function toFilter(rawKey: string, rawValue: string, start: number, end: number): QueryFilter | null | 'empty' {
  const key = rawKey.toLowerCase() as FilterKey
  if (!FILTER_KEYS.includes(key)) return null
  const label = collapse(rawValue)
  if (!label) return 'empty'
  let value: string
  if (key === 'topic') value = normalizePath(label)
  else if (key === 'site') value = normalizeSite(label)
  else value = collapse(normalizeText(label))
  if ((key === 'after' || key === 'before') && !validDate(value)) return null
  if (key === 'is' && !IS_VALUES.includes(value as IsValue)) return null
  if (!value) return 'empty'
  return { key, value, label, start, end }
}

export function parseQuery(input: string): ParsedQuery {
  const terms: string[] = []
  const filters: QueryFilter[] = []
  for (const t of tokenize(input)) {
    if (t.key) {
      const f = toFilter(t.key, t.text, t.start, t.end)
      if (f && f !== 'empty') filters.push(f)
      else if (f === null) pushTerm(terms, `${t.key}:${t.text}`)
      continue
    }
    if (!t.quoted) {
      const colon = t.text.indexOf(':')
      if (colon > 0) {
        const f = toFilter(t.text.slice(0, colon), t.text.slice(colon + 1), t.start, t.end)
        if (f === 'empty') continue
        if (f) {
          filters.push(f)
          continue
        }
      }
    }
    pushTerm(terms, t.text)
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

/** A predicate for the filters of a query; null when it has none. */
function filterPredicate(prep: Prepared, filters: QueryFilter[]): ((p: PreparedPage) => boolean) | null {
  if (!filters.length) return null
  const of = (k: FilterKey) => filters.filter((f) => f.key === k).map((f) => f.value)
  const types = of('type')
  const sites = of('site')
  const after = of('after')
  const before = of('before')
  const is = of('is')
  const topicValues = of('topic')
  const topicIds = topicValues.length ? topicIdsFor(prep, topicValues) : null
  return (p) => {
    if (types.length && !types.some((v) => p.kind.startsWith(v) || p.bucket.startsWith(v))) return false
    if (sites.length && !sites.some((v) => p.site === v || p.site.endsWith(`.${v}`))) return false
    if (topicIds && !p.page.topicIds.some((id) => topicIds.has(id))) return false
    if (after.some((v) => !p.date || p.date < v)) return false
    if (before.some((v) => !p.date || p.date >= v)) return false
    for (const v of is) {
      if (v === 'archived' && !p.page.archived) return false
      if (v === 'hub' && !p.page.isHub) return false
      if (v === 'unlinked' && !p.page.unlinked) return false
    }
    return true
  }
}

export interface RankedPage {
  id: string
  tier: number
}

const collator = new Intl.Collator(undefined, { sensitivity: 'base', numeric: true })

/** Pages that match, best first. An empty query matches nothing; filters alone match by title order. */
export function rankPages(index: GraphIndex, q: ParsedQuery): RankedPage[] {
  if (isEmptyQuery(q)) return []
  const prep = prepare(index)
  const keep = filterPredicate(prep, q.filters)
  const hits: { p: PreparedPage; tier: number }[] = []
  for (const p of prep.pages) {
    if (keep && !keep(p)) continue
    const tier = q.terms.length ? pageTier(p, q.terms) : 0
    if (tier !== null) hits.push({ p, tier })
  }
  hits.sort((a, b) => a.tier - b.tier || collator.compare(a.p.page.title, b.p.page.title) || (a.p.page.id < b.p.page.id ? -1 : 1))
  return hits.map((h) => ({ id: h.p.page.id, tier: h.tier }))
}

export interface RankedTopic {
  id: string
  tier: number
}

/** Topics whose name or path holds the free words (none when the query has filters). */
export function rankTopics(index: GraphIndex, q: ParsedQuery): RankedTopic[] {
  if (!q.terms.length || q.filters.length) return []
  const prep = prepare(index)
  const phrase = q.terms.join(' ')
  const hits: { t: PreparedTopic; tier: number }[] = []
  for (const t of prep.topics) {
    let tier: number | null = null
    if (t.name.startsWith(phrase)) tier = 0
    else if (q.terms.every((w) => startsWord(t.name, w))) tier = 1
    else if (allIn(q.terms, t.name)) tier = 2
    else if (allIn(q.terms, t.path)) tier = 4
    if (tier !== null) hits.push({ t, tier })
  }
  hits.sort((a, b) => a.tier - b.tier || collator.compare(a.t.topic.path, b.t.topic.path) || (a.t.topic.id < b.t.topic.id ? -1 : 1))
  return hits.map((h) => ({ id: h.t.topic.id, tier: h.tier }))
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
