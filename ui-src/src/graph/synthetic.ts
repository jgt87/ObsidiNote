// Synthetic graph for the demo page and the tests. Invented example data only (no real
// content). Seeded, so the same options always give the same model.

import type { GraphEdge, GraphModel, GraphPage, GraphSourceArea, GraphTopic, Strength } from './model'
import { applyLinkWeights } from './weights'

export interface SyntheticOptions {
  pages?: number
  /** Number of topics (the first six have names; one of them is a subtopic). */
  topics?: number
  seed?: number
  /** Make it look like a connected notebook (read only). */
  readOnly?: boolean
  /** Pages without a topic (drawn in the Unfiled area). */
  unfiled?: number
}

/** Small deterministic PRNG (mulberry32). */
export function seeded(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const NAMED: { name: string; subjects: string; parent?: number; weight: number; loose?: boolean; titles: string[] }[] = [
  { name: 'Security', subjects: 'zero trust, identity, policies', weight: 22, titles: ['Zero-trust networking', 'Identity-aware proxies', 'Single sign-on', 'Device trust checklist', 'MFA rollout', 'Microsegmentation'] },
  { name: 'Projects', subjects: 'partner portal, intranet, data platform', weight: 20, loose: true, titles: ['Partner portal', 'VPN retirement plan', 'Access review notes', 'Intranet relaunch', 'Data platform'] },
  { name: 'Methods', subjects: 'templates, decisions, reviews', weight: 11, loose: true, titles: ['Decision log template', 'Review cadence', 'Two-way doors'] },
  { name: 'People', subjects: 'contacts and roles', weight: 9, titles: ['Sam (security lead)', 'Alex (portal owner)', 'Robin (data)'] },
  { name: 'Reading notes', subjects: 'articles, books, talks', weight: 28, loose: true, titles: ['Beyond the perimeter', 'Team topologies', 'Working backwards', 'Thinking in systems'] },
  { name: 'Networking', subjects: 'proxies, VPN, segments', parent: 0, weight: 10, titles: ['Proxy placement', 'Split tunnelling', 'Network zones'] },
]
const BUCKETS: [string, string][] = [
  ['Notes', 'concept'], ['Notes', 'note'], ['Web links', 'link-web'], ['Internal links', 'link-internal'],
  ['Sources', 'source'], ['Meetings', 'meeting'], ['Decisions', 'decision'], ['Projects', 'project'],
]
/** Sources of the demo's internal links, and the names of every demo source. */
const DEMO_INTERNAL = ['sharepoint/hr', 'sharepoint/it', 'onedrive', 'teams', 'sharepoint/hr', 'loop']
const DEMO_SOURCES: Record<string, Omit<GraphSourceArea, 'pageCount'>> = {
  'sharepoint/hr': { id: 'sharepoint/hr', name: 'SharePoint: HR', kind: 'm365' },
  'sharepoint/it': { id: 'sharepoint/it', name: 'SharePoint: IT', kind: 'm365' },
  onedrive: { id: 'onedrive', name: 'OneDrive', kind: 'm365' },
  teams: { id: 'teams', name: 'Teams', kind: 'm365' },
  loop: { id: 'loop', name: 'Loop', kind: 'm365' },
  'web/site0.example': { id: 'web/site0.example', name: 'site0.example', kind: 'web' },
  'web/site1.example': { id: 'web/site1.example', name: 'site1.example', kind: 'web' },
  'web/site2.example': { id: 'web/site2.example', name: 'site2.example', kind: 'web' },
  obsidinote: { id: 'obsidinote', name: 'ObsidiNote notes', kind: 'notes' },
  onenote: { id: 'onenote', name: 'OneNote pages', kind: 'notes' },
}
const REASONS = ['core concept this implements', 'the check it relies on', 'replaces it', 'same project', 'background reading', 'decided in this meeting', 'owner of this', 'example of the method']

/** The random draws, in order: every helper below takes from this one generator, so the same seed
 *  gives the same model only while the draws stay in the same order. */
type Rnd = () => number
const pickOf = <T,>(rnd: Rnd, list: T[]): T => list[Math.floor(rnd() * list.length)]

/** The topics: the named ones first (one is a subtopic), then "Topic N"; and each one's weight
 *  (its share of the pages; a random one past the named). */
function makeTopics(count: number, rnd: Rnd): { topics: GraphTopic[]; weights: number[] } {
  const topics: GraphTopic[] = []
  const weights: number[] = []
  for (let i = 0; i < count; i++) {
    const named = NAMED[i]
    const parentIdx = named?.parent
    const parent = parentIdx !== undefined && parentIdx < i ? topics[parentIdx] : null
    const name = named?.name ?? `Topic ${i + 1}`
    topics.push({ id: `t${i + 1}`, name, path: parent ? `${parent.path} / ${name}` : name, parent: parent ? parent.id : null, pageCount: 0, subjects: named?.subjects ?? `subject ${i + 1}a, subject ${i + 1}b` })
    weights.push(named?.weight ?? 6 + rnd() * 18)
  }
  return { topics, weights }
}

/** Pages per topic, proportional to the weights; each topic gets at least one when there are
 *  enough; what rounding leaves goes one by one from the first topic on. */
function pagesPerTopic(weights: number[], filed: number): number[] {
  const topicCount = weights.length
  const wsum = weights.reduce((a, b) => a + b, 0)
  const counts = weights.map((w) => (filed >= topicCount ? 1 : 0) + Math.floor(((filed - (filed >= topicCount ? topicCount : 0)) * w) / wsum))
  let left = filed - counts.reduce((a, b) => a + b, 0)
  for (let i = 0; left > 0; i = (i + 1) % topicCount, left--) counts[i]++
  return counts
}

// Page fields derived from the page's number (n: how many pages came before) and kind, without
// random draws, so the seeded pages stay the same.
const demoTags = (n: number): string[] => (n % 11 === 3 ? ['follow up'] : n % 9 === 4 ? ['licensing'] : n % 31 === 7 ? ['licensing', 'key reference'] : [])
const demoSite = (kind: string, n: number): string => (kind === 'link-web' ? `site${n % 3}.example` : kind === 'link-internal' ? 'team.example' : '')
const demoUrl = (kind: string, n: number): string => (kind === 'link-web' ? `https://site${n % 3}.example/page-${n}` : kind === 'link-internal' ? `https://team.example/sites/demo/page-${n}` : '')
/** As the server would place it (lib/GraphModel.psm1): internal links spread over Microsoft 365
 *  apps, web links by site, files on OneDrive, the rest without an address. */
function demoSourceId(kind: string, n: number, readOnly: boolean): string {
  if (kind === 'link-web') return `web/site${n % 3}.example`
  if (kind === 'link-internal') return DEMO_INTERNAL[n % DEMO_INTERNAL.length]
  if (kind === 'file') return 'onedrive'
  return readOnly ? 'onenote' : 'obsidinote'
}

const DEMO_DAY = Date.UTC(2026, 10, 12, 12, 0)

/** The pages and links being made, with the two ways to add to them. */
interface DemoBuilder {
  pages: GraphPage[]
  edges: GraphEdge[]
  /** A page; a hub sits in 00 Index, any other page gets a random section. Draws: the section
   *  (not for a hub), then the day it changed. */
  addPage: (title: string, topicIds: string[], hub: boolean) => GraphPage
  /** A link (with a random reason) or a mention between pages a and b; none from a page to itself. */
  link: (a: number, b: number, s: Strength, kind?: 'link' | 'mention') => void
}

function demoBuilder(rnd: Rnd, readOnly: boolean): DemoBuilder {
  const pages: GraphPage[] = []
  const edges: GraphEdge[] = []
  const addPage = (title: string, topicIds: string[], hub: boolean): GraphPage => {
    const n = pages.length
    const [bucket, kind] = hub ? ['00 Index', 'hub'] : pickOf(rnd, BUCKETS)
    const page: GraphPage = {
      id: `p${n + 1}`, title, topicIds, bucket, section: bucket, tags: demoTags(n), kind, links: 0, linkedFrom: 0, weight: 0, isHub: false, unlinked: false,
      summary: `Example summary for “${title}”: invented text for the demo.`,
      onenoteUrl: `onenote:#example-page-${n + 1}`,
      modified: new Date(DEMO_DAY - Math.floor(rnd() * 90) * 86_400_000).toISOString(),
      readOnly,
      aliases: hub ? [] : n % 7 === 3 ? [`${title.split(' ')[0]} (alias)`] : [],
      site: demoSite(kind, n),
      archived: !hub && n % 23 === 22,
      url: demoUrl(kind, n),
      sourceId: demoSourceId(kind, n, readOnly),
      origin: '',
    }
    pages.push(page)
    return page
  }
  const link = (a: number, b: number, s: Strength, kind: 'link' | 'mention' = 'link'): void => {
    if (a === b) return
    edges.push({ from: pages[a].id, to: pages[b].id, strength: s, kind, reason: kind === 'link' ? pickOf(rnd, REASONS) : undefined })
  }
  return { pages, edges, addPage, link }
}

/** One topic's n pages (the first a hub when there are more than three), each but the first linked
 *  into the topic (a loose topic's last page left unlinked), a few also under another topic.
 *  Returns the index of its first page. */
function fillTopic(b: DemoBuilder, rnd: Rnd, topics: GraphTopic[], ti: number, n: number): number {
  const t = topics[ti]
  const first = b.pages.length
  const named = NAMED[ti]
  for (let k = 0; k < n; k++) {
    const title = named?.titles[k] ?? `${t.name} page ${k + 1}`
    const extra = k > 2 && rnd() < 0.08 ? [pickOf(rnd, topics).id] : []
    b.addPage(title, [t.id, ...extra.filter((x) => x !== t.id)], k === 0 && n > 3)
    const loose = (named?.loose ?? ti % 3 === 1) && k === n - 1 && n > 2
    if (k > 0 && !loose) {
      const to = k < 6 ? first : first + Math.floor(rnd() * k)
      b.link(first + k, to, (1 + Math.floor(rnd() * 3)) as Strength)
      if (rnd() < 0.35) b.link(first + k, first + Math.floor(rnd() * k), 1)
    }
  }
  return first
}

/** Links between topics: hubs to hubs (each topic to the one before it), then a few page-to-page
 *  across topics, then mentions (shown only with that filter on). */
function crossTopicLinks(b: DemoBuilder, rnd: Rnd, counts: number[], firstOf: number[], filed: number, total: number): void {
  for (let i = 1; i < counts.length; i++) {
    if (counts[i] && counts[i - 1]) b.link(firstOf[i - 1], firstOf[i], (1 + Math.floor(rnd() * 3)) as Strength)
  }
  const cross = Math.round(filed * 0.18)
  for (let c = 0; c < cross && filed > 1; c++) {
    const x = Math.floor(rnd() * filed)
    const y = Math.floor(rnd() * filed)
    if (b.pages[x].topicIds[0] !== b.pages[y].topicIds[0]) b.link(x, y, rnd() < 0.7 ? 1 : 2)
  }
  const mentions = Math.round(total * 0.06)
  for (let c = 0; c < mentions && total > 1; c++) b.link(Math.floor(rnd() * total), Math.floor(rnd() * total), 1, 'mention')
}

/** One edge per kind and pair of pages (the first one made). */
function uniqueEdges(edges: GraphEdge[]): GraphEdge[] {
  const seen = new Set<string>()
  return edges.filter((e) => {
    const k = `${e.kind}:${e.from < e.to ? e.from + '|' + e.to : e.to + '|' + e.from}`
    if (seen.has(k)) return false
    seen.add(k)
    return true
  })
}

/** Each topic's page count; a parent's count includes its subtopics' pages, as in the index. */
function countTopicPages(topics: GraphTopic[], pages: GraphPage[]): void {
  for (const p of pages) for (const t of p.topicIds) topics.find((x) => x.id === t)!.pageCount++
  for (const t of [...topics].reverse()) if (t.parent) topics.find((x) => x.id === t.parent)!.pageCount += t.pageCount
}

export function syntheticGraph(opts: SyntheticOptions = {}): GraphModel {
  const total = Math.max(0, Math.floor(opts.pages ?? 100))
  const topicCount = Math.max(1, Math.floor(opts.topics ?? 6))
  const unfiled = Math.min(total, Math.max(0, Math.floor(opts.unfiled ?? (total >= 20 ? 2 : 0))))
  const rnd = seeded(opts.seed ?? 7)
  const readOnly = opts.readOnly === true

  const { topics, weights } = makeTopics(topicCount, rnd)
  const filed = total - unfiled
  const counts = pagesPerTopic(weights, filed)
  const b = demoBuilder(rnd, readOnly)
  const firstOf = topics.map((_, ti) => fillTopic(b, rnd, topics, ti, counts[ti]))
  for (let k = 0; k < unfiled; k++) b.addPage(`Unfiled item ${k + 1}`, [], false)
  crossTopicLinks(b, rnd, counts, firstOf, filed, total)

  // Drop duplicate pairs, then weigh the pages as normalizeGraph does (weights.ts).
  const pages = b.pages
  const unique = uniqueEdges(b.edges)
  applyLinkWeights(pages, unique)
  countTopicPages(topics, pages)

  return {
    source: readOnly
      ? { kind: 'notebook', id: 'nb-example', name: 'Team notebook (example)', readOnly: true, readOnlyReason: 'notebook' }
      : { kind: 'vault', id: 'vault-example', name: 'ObsidiNote (example)', readOnly: false, readOnlyReason: '' },
    topics,
    pages,
    edges: unique,
    // As the server sends them for the active vault (lib/NotebookStructure.psm1 TypeBucket).
    ...(readOnly ? {} : { types: DEMO_TYPES }),
    sources: Object.values(DEMO_SOURCES)
      .map((s) => ({ ...s, pageCount: pages.filter((p) => p.sourceId === s.id).length }))
      .filter((s) => s.pageCount > 0),
  }
}

const DEMO_TYPES = [
  { type: 'concept', bucket: 'Notes' }, { type: 'note', bucket: 'Notes' }, { type: 'howto', bucket: 'Notes' },
  { type: 'link-internal', bucket: 'Internal links' }, { type: 'link-web', bucket: 'Web links' },
  { type: 'source', bucket: 'Sources' }, { type: 'person', bucket: 'People' },
  { type: 'project', bucket: 'Projects' }, { type: 'project-part', bucket: 'Projects' },
  { type: 'meeting', bucket: 'Meetings' }, { type: 'decision', bucket: 'Decisions' },
  { type: 'log', bucket: 'Journal' }, { type: 'file', bucket: 'Files' },
]
