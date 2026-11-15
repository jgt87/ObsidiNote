// The knowledge graph by tag (operator, 2026-11-15: "there's a Topics/Sources switch, add tags in
// there ... select from the available tags"). Pure, like sourceView.ts: the same model with its
// areas made from the hand-set tags, so the map's layout, lines, sizes and hover work unchanged.
// Only pages that carry one of the chosen tags are on this map: tags mark a few pages out of
// many, and one area for "everything else" would be most of the picture. A page with several of
// the chosen tags sits in the area of the rarest one it carries and lists the others (the page
// window's "Also under"). The page window, filters and List keep the real topics.
// Inside a tag's area the pages of one topic sit together under that topic's name (`group`,
// layout.ts): a tag exists to relate pages of different topics, so the topics stay visible
// (design round 2, 2026-11-15; no colour per topic: the map has one accent).

import { UNFILED_ID, type GraphModel, type GraphTopic } from './model'
import { tagCounts } from './tags'

/** Area id of a tag (never a topic id: those are paths without this prefix). */
export const tagAreaId = (tag: string): string => `tag:${tag}`

/** The tags the Tags view can show, by name, with their page counts (archived pages left out,
 *  as on the map). */
export function availableTags(model: GraphModel): { name: string; count: number }[] {
  return tagCounts(model.pages, false)
}

/**
 * The model with one area per chosen tag. `chosen` = the tags to show; null = every tag in use.
 * Pages without a chosen tag, and links to them, are left out.
 */
export function byTag(model: GraphModel, chosen: ReadonlySet<string> | null): GraphModel {
  const all = availableTags(model)
  const shown = all.filter((t) => !chosen || chosen.has(t.name))
  const wanted = new Set(shown.map((t) => t.name))
  // A page with several shown tags sits under the rarest of them (fewest pages, then by name), so a
  // small tag whose pages all carry a bigger tag too still gets its own area.
  const size = new Map(shown.map((t) => [t.name, t.count]))
  const rarestFirst = (a: string, b: string) => size.get(a)! - size.get(b)! || (a < b ? -1 : a > b ? 1 : 0)
  const topicName = new Map(model.topics.map((t) => [t.id, t.name]))
  const groupOf = (id: string | undefined) => (id && topicName.has(id) ? { id, name: topicName.get(id)! } : { id: UNFILED_ID, name: 'Unfiled' })
  const pages = model.pages
    .map((p) => ({ ...p, group: groupOf(p.topicIds[0]), topicIds: p.tags.filter((t) => wanted.has(t)).sort(rarestFirst).map(tagAreaId) }))
    .filter((p) => p.topicIds.length > 0)
  const kept = new Set(pages.map((p) => p.id))
  const count = new Map<string, number>()
  for (const p of pages) if (!p.archived) count.set(p.topicIds[0], (count.get(p.topicIds[0]) ?? 0) + 1)
  const topics: GraphTopic[] = shown.map((t) => ({ id: tagAreaId(t.name), name: t.name, path: t.name, parent: null, pageCount: count.get(tagAreaId(t.name)) ?? 0, subjects: 'tag' }))
  const edges = model.edges.filter((e) => kept.has(e.from) && kept.has(e.to))
  return { ...model, topics, pages, edges }
}
