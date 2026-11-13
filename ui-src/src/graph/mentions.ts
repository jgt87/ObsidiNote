// "Mentions, not linked": page A mentions page B when B's title or one of its aliases appears in
// A's title or summary as whole words, and neither page links the other. Pure; the map adds these
// edges (kind 'mention') to the model before it is drawn, and "Link it" turns one into a link.
//
// Matching ignores case and accents (NFD, combining marks stripped). A name counts only when it has
// at least 4 characters and one letter, and is not made of generic words only ("Notes", "Index",
// "Untitled page"). Speed: every name goes into one Map by its normalized words; each page's text
// is scanned as word n-grams (1..6 words) against that Map, so there is no all-pairs loop
// (5,000 pages stay well under a frame budget per thousand pages, see mentions.test.ts).

import type { GraphEdge, GraphModel } from './model'

/** Longest name (in words) that can match. */
export const MAX_NAME_WORDS = 6
/** Mentions kept per mentioning page, longest matched name first. */
export const MAX_MENTIONS_PER_PAGE = 5
const MIN_NAME_CHARS = 4

/** Words that do not name anything on their own; a title made only of these is never matched. */
const GENERIC = new Set([
  'note', 'notes', 'index', 'untitled', 'page', 'pages', 'new', 'home', 'readme', 'todo', 'todos',
  'inbox', 'intake', 'misc', 'draft', 'drafts', 'journal', 'meeting', 'meetings', 'summary',
  'overview', 'list', 'item', 'items', 'other', 'unfiled', 'archive', 'links', 'link', 'the', 'and',
  'of', 'a', 'an',
])

const WORD = /[\p{L}\p{N}]+/gu
const LETTER = /\p{L}/u

/** Lower-case words without accents: "Café Zürich" -> ["cafe", "zurich"]. */
export function normalizeWords(text: string): string[] {
  const plain = text.normalize('NFD').replace(/\p{M}+/gu, '').toLowerCase()
  return plain.match(WORD) ?? []
}

/** The Map key of a name, or '' when the name is too short, has no letter or is generic only. */
export function nameKey(name: string): string {
  const words = normalizeWords(name)
  if (!words.length || words.length > MAX_NAME_WORDS) return ''
  const key = words.join(' ')
  if (key.replace(/ /g, '').length < MIN_NAME_CHARS || !LETTER.test(key)) return ''
  if (words.every((w) => GENERIC.has(w))) return ''
  return key
}

function pairKey(a: string, b: string): string {
  return a < b ? `${a}|${b}` : `${b}|${a}`
}

/** Every mention edge of the model (kind 'mention', strength 1), from the mentioning page. */
export function findMentions(model: GraphModel): GraphEdge[] {
  const live = model.pages.filter((p) => !p.archived)
  // Normalized name -> the pages it names.
  const names = new Map<string, string[]>()
  for (const p of live) {
    const keys = new Set([p.title, ...p.aliases].map(nameKey).filter(Boolean))
    for (const k of keys) {
      const list = names.get(k)
      if (list) list.push(p.id)
      else names.set(k, [p.id])
    }
  }
  const linked = new Set<string>()
  for (const e of model.edges) if (e.kind !== 'mention') linked.add(pairKey(e.from, e.to))

  const edges: GraphEdge[] = []
  const done = new Set<string>()
  for (const a of live) {
    // Target id -> length of the longest name of it found in A's text.
    const found = new Map<string, number>()
    for (const text of [a.title, a.summary]) {
      const words = normalizeWords(text)
      for (let i = 0; i < words.length; i++) {
        let key = ''
        for (let n = 1; n <= MAX_NAME_WORDS && i + n <= words.length; n++) {
          key = n === 1 ? words[i] : `${key} ${words[i + n - 1]}`
          const hits = names.get(key)
          if (!hits) continue
          for (const b of hits) {
            if (b === a.id || linked.has(pairKey(a.id, b))) continue
            if ((found.get(b) ?? 0) < key.length) found.set(b, key.length)
          }
        }
      }
    }
    const best = [...found.entries()].sort((x, y) => y[1] - x[1] || (x[0] < y[0] ? -1 : 1)).slice(0, MAX_MENTIONS_PER_PAGE)
    for (const [b] of best) {
      const k = pairKey(a.id, b)
      if (done.has(k)) continue
      done.add(k)
      edges.push({ from: a.id, to: b, strength: 1, kind: 'mention' })
    }
  }
  return edges
}

/** The model with the mention edges added (pairs it already has as a mention are kept once). */
export function withMentions(model: GraphModel): GraphModel {
  const have = new Set(model.edges.filter((e) => e.kind === 'mention').map((e) => pairKey(e.from, e.to)))
  const add = findMentions(model).filter((e) => !have.has(pairKey(e.from, e.to)))
  return add.length ? { ...model, edges: [...model.edges, ...add] } : model
}

/** The mention edge between two pages, in either direction (for the direction of "Link it"). */
export function mentionBetween(model: GraphModel, a: string, b: string): GraphEdge | undefined {
  return model.edges.find((e) => e.kind === 'mention' && ((e.from === a && e.to === b) || (e.from === b && e.to === a)))
}
