// Synthetic graph for the demo page and the tests. Invented example data only (no real
// content). Seeded, so the same options always give the same model.

import type { GraphEdge, GraphModel, GraphPage, GraphTopic, Strength } from './model'

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
const REASONS = ['core concept this implements', 'the check it relies on', 'replaces it', 'same project', 'background reading', 'decided in this meeting', 'owner of this', 'example of the method']

export function syntheticGraph(opts: SyntheticOptions = {}): GraphModel {
  const total = Math.max(0, Math.floor(opts.pages ?? 100))
  const topicCount = Math.max(1, Math.floor(opts.topics ?? 6))
  const unfiled = Math.min(total, Math.max(0, Math.floor(opts.unfiled ?? (total >= 20 ? 2 : 0))))
  const rnd = seeded(opts.seed ?? 7)
  const readOnly = opts.readOnly === true
  const pick = <T,>(list: T[]): T => list[Math.floor(rnd() * list.length)]

  const topics: GraphTopic[] = []
  const weights: number[] = []
  for (let i = 0; i < topicCount; i++) {
    const named = NAMED[i]
    const id = `t${i + 1}`
    const parentIdx = named?.parent
    const parent = parentIdx !== undefined && parentIdx < i ? topics[parentIdx] : null
    const name = named?.name ?? `Topic ${i + 1}`
    topics.push({ id, name, path: parent ? `${parent.path} / ${name}` : name, parent: parent ? parent.id : null, pageCount: 0, subjects: named?.subjects ?? `subject ${i + 1}a, subject ${i + 1}b` })
    weights.push(named?.weight ?? 6 + rnd() * 18)
  }

  // Pages per topic, proportional to the weights; each topic gets at least one.
  const filed = total - unfiled
  const wsum = weights.reduce((a, b) => a + b, 0)
  const counts = weights.map((w) => (filed >= topicCount ? 1 : 0) + Math.floor(((filed - (filed >= topicCount ? topicCount : 0)) * w) / wsum))
  let left = filed - counts.reduce((a, b) => a + b, 0)
  for (let i = 0; left > 0; i = (i + 1) % topicCount, left--) counts[i]++

  const pages: GraphPage[] = []
  const edges: GraphEdge[] = []
  const firstOf: number[] = []
  const day = Date.UTC(2026, 10, 12, 12, 0)
  const addPage = (title: string, topicIds: string[], hub: boolean): GraphPage => {
    const [bucket, kind] = hub ? ['00 Index', 'hub'] : pick(BUCKETS)
    const id = `p${pages.length + 1}`
    const page: GraphPage = {
      id, title, topicIds, bucket, kind, links: 0, isHub: hub, unlinked: false,
      summary: `Example summary for “${title}”: invented text for the demo.`,
      onenoteUrl: `onenote:#example-page-${pages.length + 1}`,
      modified: new Date(day - Math.floor(rnd() * 90) * 86_400_000).toISOString(),
      readOnly,
      // Derived without extra random draws, so the seeded pages stay the same.
      aliases: hub ? [] : pages.length % 7 === 3 ? [`${title.split(' ')[0]} (alias)`] : [],
      site: kind === 'link-web' ? `site${pages.length % 3}.example` : kind === 'link-internal' ? 'team.example' : '',
      archived: !hub && pages.length % 23 === 22,
    }
    pages.push(page)
    return page
  }
  const link = (a: number, b: number, s: Strength, kind: 'link' | 'mention' = 'link') => {
    if (a === b) return
    edges.push({ from: pages[a].id, to: pages[b].id, strength: s, kind, reason: kind === 'link' ? pick(REASONS) : undefined })
  }

  topics.forEach((t, ti) => {
    const first = pages.length
    firstOf.push(first)
    const named = NAMED[ti]
    const n = counts[ti]
    for (let k = 0; k < n; k++) {
      const title = named?.titles[k] ?? `${t.name} page ${k + 1}`
      const extra = k > 2 && rnd() < 0.08 ? [pick(topics).id] : []
      addPage(title, [t.id, ...extra.filter((x) => x !== t.id)], k === 0 && n > 3)
      const loose = (named?.loose ?? ti % 3 === 1) && k === n - 1 && n > 2
      if (k > 0 && !loose) {
        const to = k < 6 ? first : first + Math.floor(rnd() * k)
        link(first + k, to, (1 + Math.floor(rnd() * 3)) as Strength)
        if (rnd() < 0.35) link(first + k, first + Math.floor(rnd() * k), 1)
      }
    }
  })
  for (let k = 0; k < unfiled; k++) addPage(`Unfiled item ${k + 1}`, [], false)

  // Links between topics: hubs to hubs, and a few page-to-page.
  for (let i = 1; i < topics.length; i++) {
    if (counts[i] && counts[i - 1]) link(firstOf[i - 1], firstOf[i], (1 + Math.floor(rnd() * 3)) as Strength)
  }
  const cross = Math.round(filed * 0.18)
  for (let c = 0; c < cross && filed > 1; c++) {
    const a = Math.floor(rnd() * filed)
    const b = Math.floor(rnd() * filed)
    if (pages[a].topicIds[0] !== pages[b].topicIds[0]) link(a, b, rnd() < 0.7 ? 1 : 2)
  }
  // Mentions, not linked (shown only with that filter on).
  const mentions = Math.round(total * 0.06)
  for (let c = 0; c < mentions && total > 1; c++) link(Math.floor(rnd() * total), Math.floor(rnd() * total), 1, 'mention')

  // Drop duplicate pairs, then count links per page.
  const seen = new Set<string>()
  const unique = edges.filter((e) => {
    const k = `${e.kind}:${e.from < e.to ? e.from + '|' + e.to : e.to + '|' + e.from}`
    if (seen.has(k)) return false
    seen.add(k)
    return true
  })
  const byId = new Map(pages.map((p) => [p.id, p]))
  for (const e of unique) {
    if (e.kind === 'mention') continue
    byId.get(e.from)!.links++
    byId.get(e.to)!.links++
  }
  for (const p of pages) {
    p.unlinked = p.links === 0
    if (!p.isHub && p.links >= 12) p.isHub = true
    for (const t of p.topicIds) topics.find((x) => x.id === t)!.pageCount++
  }
  // A parent's count includes its subtopics' pages, as in the index.
  for (const t of [...topics].reverse()) if (t.parent) topics.find((x) => x.id === t.parent)!.pageCount += t.pageCount

  return {
    source: readOnly
      ? { kind: 'notebook', id: 'nb-example', name: 'Team notebook (example)', readOnly: true }
      : { kind: 'vault', id: 'vault-example', name: 'ObsidiNote (example)', readOnly: false },
    topics,
    pages,
    edges: unique,
  }
}
