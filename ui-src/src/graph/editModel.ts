// Editing a page in the page window (operator, 2026-11-13: "adjust the title, adjust/replace/update
// links, page details"): the form's state from the graph, the choices it offers, and the request that
// carries only what changed (POST /api/page/edit; the server checks everything again). Pure.

import type { GraphIndex } from './graphIndex'
import type { GraphModel, GraphPage, Strength } from './model'
import { clampStrength } from './model'
import { webUrl } from '../model/links'

export interface EditLink {
  target: string
  strength: Strength
  why: string
}

export interface EditForm {
  title: string
  type: string
  /** One topic path per line, steps joined by " / " as everywhere in the window. */
  topics: string
  /** Comma separated. */
  aliases: string
  summary: string
  /** A link page's address ('' for other pages). */
  url: string
  /** Where a page without an address came from (model/origins.ts; '' = typed). */
  origin: string
  links: EditLink[]
}

export interface PageEditRequest {
  id: string
  vault?: string
  title?: string
  type?: string
  topics?: string[]
  aliases?: string[]
  summary?: string
  url?: string
  links?: EditLink[]
  origin?: string
}

const toLine = (topicId: string) => topicId.split('/').map((s) => s.trim()).filter(Boolean).join(' / ')

/** The form as the page is now. */
export function formFor(index: GraphIndex, page: GraphPage): EditForm {
  return {
    title: page.title,
    type: page.kind,
    // The topic's own display path ("Security / Networking"); its id is the same path with "/" for a
    // vault, but may be anything for other sources.
    topics: page.topicIds.map((id) => index.topicById.get(id)?.path ?? toLine(id)).join('\n'),
    aliases: page.aliases.join(', '),
    summary: page.summary,
    url: page.url,
    origin: page.origin,
    links: (index.out.get(page.id) ?? []).map((e) => ({ target: e.to, strength: e.strength, why: e.reason ?? '' })),
  }
}

/**
 * The types the page may take. A type of another section moves the page there when saved (the
 * server's Edit-Page, operator 2026-11-15); a link page's type follows its address, so it keeps its
 * own; an archived page stays in the Archive until Restore, so it keeps its section's types.
 */
export function typeChoices(model: GraphModel, page: GraphPage): string[] {
  const types = model.types ?? []
  const own = types.find((t) => t.type === page.kind)
  if (!own) return page.kind ? [page.kind] : []
  if (page.kind.startsWith('link-')) return [page.kind]
  if (page.archived) return types.filter((t) => t.bucket === own.bucket).map((t) => t.type)
  return types.filter((t) => !t.type.startsWith('link-')).map((t) => t.type)
}

/** The line under the type when the chosen one lives in another section: where saving moves it. */
export function moveNote(model: GraphModel, page: GraphPage, type: string): string {
  const types = model.types ?? []
  const from = types.find((t) => t.type === page.kind)?.bucket
  const to = types.find((t) => t.type === type)?.bucket
  return from && to && from !== to ? `Saving moves the page to ${to}. Its links and your notes stay.` : ''
}

/** Pages a new link can point to: the source's other pages that are not linked yet, by title. */
export function linkChoices(index: GraphIndex, page: GraphPage, links: EditLink[]): GraphPage[] {
  const taken = new Set(links.map((l) => l.target))
  return index.model.pages
    .filter((p) => p.id !== page.id && !taken.has(p.id) && !p.archived)
    .sort((a, b) => a.title.localeCompare(b.title) || (a.id < b.id ? -1 : 1))
}

export function parseTopics(text: string): string[] {
  const out = new Set<string>()
  for (const line of text.split(/\r?\n/)) {
    const path = line.split('/').map((s) => s.trim()).filter(Boolean).join('/')
    if (path) out.add(path)
  }
  return [...out]
}

export function parseAliases(text: string): string[] {
  const out = new Set<string>()
  for (const a of text.split(',').map((s) => s.trim())) if (a) out.add(a)
  return [...out]
}

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b)
const normLinks = (ls: EditLink[]) => ls.map((l) => ({ target: l.target, strength: clampStrength(l.strength), why: l.why.trim() }))

/** What is wrong with a title ('' = nothing): the one rule for the form and for the title changed
 *  in place (InlineText). */
export function titleProblem(title: string): string {
  const t = title.trim()
  if (!t) return 'The title cannot be empty.'
  if (t.length > 200 || /[\r\n]/.test(t)) return 'The title must be one line of at most 200 characters.'
  return ''
}

/** What is wrong with a summary ('' = nothing). */
export function summaryProblem(summary: string): string {
  return summary.trim().length > 2000 ? 'The summary can be at most 2,000 characters.' : ''
}

/** What is wrong with the form before it is sent ('' = nothing). The server checks again. */
export function editProblem(form: EditForm, isLink: boolean): string {
  const title = titleProblem(form.title)
  if (title) return title
  if (isLink && !webUrl(form.url)) return 'The address must be an http(s) link.'
  if (summaryProblem(form.summary)) return summaryProblem(form.summary)
  if (form.links.some((l) => l.why.length > 300)) return 'A link’s reason can be at most 300 characters.'
  return ''
}

/** The request with only the fields that differ from `before`; null when nothing changed. */
export function editRequest(page: GraphPage, vault: string, before: EditForm, form: EditForm): PageEditRequest | null {
  const req: PageEditRequest = { id: page.id, vault }
  if (form.title.trim() !== before.title.trim()) req.title = form.title.trim()
  if (form.type !== before.type) req.type = form.type
  const topics = parseTopics(form.topics)
  if (!same(topics, parseTopics(before.topics))) req.topics = topics
  const aliases = parseAliases(form.aliases)
  if (!same(aliases, parseAliases(before.aliases))) req.aliases = aliases
  if (form.summary.trim() !== before.summary.trim()) req.summary = form.summary.trim()
  if (page.url && form.url.trim() !== before.url.trim()) req.url = form.url.trim()
  if (!page.url && form.origin !== before.origin) req.origin = form.origin
  const links = normLinks(form.links)
  if (!same(links, normLinks(before.links))) req.links = links
  return Object.keys(req).length > 2 ? req : null
}
