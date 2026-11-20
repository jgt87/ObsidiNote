// Loads the graph model from the local server. The merge points this at the real route:
// GET /api/graph?vault=<vault id>  or  GET /api/graph?notebook=<notebook id>
// (lib/Server.psm1 adds the route; step 2 builds the model). Every call carries
// X-ObsidiNote: 1, which the server requires.

import type { PageEditRequest } from './editModel'
import { parseMergePlan, parseMergeResult, type MergeAnswer } from './mergeModel'
import { normalizeGraph, type GraphModel } from './model'
import { parsePlan, parseResult, type RetireAction, type RetirePlan, type RetireResult } from './retireModel'

export type GraphSourceRef = { vault: string } | { notebook: string } | Record<string, never>

export const GRAPH_ROUTE = '/api/graph'

export class GraphLoadError extends Error {
  constructor(message: string, readonly status: number) {
    super(message)
  }
}

const NOT_ANSWERING = 'ObsidiNote is not answering. Is it still running?'

/** The request, with ObsidiNote's header. A network failure becomes GraphLoadError status 0 (the
 *  server is gone); with `passAbort`, a cancelled request's AbortError is passed on as it is. */
async function send(url: string, init: RequestInit, fetcher: typeof fetch, passAbort = false): Promise<Response> {
  try {
    return await fetcher(url, { ...init, headers: { 'X-ObsidiNote': '1', ...(init.headers as Record<string, string> | undefined) } })
  } catch (e) {
    if (passAbort && e instanceof DOMException && e.name === 'AbortError') throw e
    throw new GraphLoadError(NOT_ANSWERING, 0)
  }
}

/** The answer's JSON object, or {} when it has none. */
async function answerOf(res: Response): Promise<Record<string, unknown>> {
  const data: unknown = await res.json().catch(() => null)
  return (data && typeof data === 'object' ? data : {}) as Record<string, unknown>
}

/** A refusal with the server's message, or which status it answered. */
function refusal(res: Response, b: Record<string, unknown>): GraphLoadError {
  return new GraphLoadError(b.error ? String(b.error) : `The server answered ${res.status}.`, res.status)
}

const POST_JSON = { method: 'POST', headers: { 'Content-Type': 'application/json' } }

export function graphUrl(ref: GraphSourceRef = {}, route = GRAPH_ROUTE): string {
  const q = new URLSearchParams()
  if ('vault' in ref && ref.vault) q.set('vault', ref.vault)
  else if ('notebook' in ref && ref.notebook) q.set('notebook', ref.notebook)
  const s = q.toString()
  return s ? `${route}?${s}` : route
}

export async function fetchGraph(ref: GraphSourceRef = {}, signal?: AbortSignal, fetcher: typeof fetch = fetch): Promise<GraphModel> {
  const res = await send(graphUrl(ref), { cache: 'no-store', signal }, fetcher, true)
  const body: unknown = await res.json().catch(() => null)
  if (res.status !== 200) {
    const msg = body && typeof body === 'object' && 'error' in body ? String((body as { error: unknown }).error) : `The server answered ${res.status}.`
    throw new GraphLoadError(msg, res.status)
  }
  return normalizeGraph(body)
}

export const PAGE_BODY_ROUTE = '/api/page/body'

/**
 * The page's own text for the page window: GET /api/page/body?page=<id>[&vault=|&notebook=] ->
 * Markdown (bodyText.ts reads it). Read only; built in memory by the server and never stored.
 * Throws GraphLoadError with the server's message (400, 404, 409, 500, 503).
 */
export async function fetchPageBody(page: string, source: { vault?: string; notebook?: string }, signal?: AbortSignal, fetcher: typeof fetch = fetch): Promise<{ markdown: string; truncated: boolean }> {
  const q = new URLSearchParams({ page })
  if (source.vault) q.set('vault', source.vault)
  if (source.notebook) q.set('notebook', source.notebook)
  const res = await send(`${PAGE_BODY_ROUTE}?${q}`, { cache: 'no-store', signal }, fetcher, true)
  const b = await answerOf(res)
  if (res.status !== 200) throw refusal(res, b)
  return { markdown: typeof b.markdown === 'string' ? b.markdown : '', truncated: b.truncated === true }
}

export const PAGE_EDIT_ROUTE = '/api/page/edit'

/**
 * Edit a page of the active vault: POST /api/page/edit with only the changed fields. Resolves with
 * 'edited' or 'unchanged'; throws GraphLoadError with the server's message otherwise (400 what is
 * wrong, 409 read only or another source, 404 not in the index).
 */
export async function editPage(req: PageEditRequest, fetcher: typeof fetch = fetch): Promise<'edited' | 'unchanged'> {
  const b = await postJson(PAGE_EDIT_ROUTE, req, fetcher)
  return b.status === 'unchanged' ? 'unchanged' : 'edited'
}

/** POST a JSON body; the answer's object on 200, else a refusal with the server's message. */
async function postJson(route: string, body: unknown, fetcher: typeof fetch): Promise<Record<string, unknown>> {
  const res = await send(route, { ...POST_JSON, body: JSON.stringify(body) }, fetcher)
  const b = await answerOf(res)
  if (res.status !== 200) throw refusal(res, b)
  return b
}

export const PAGES_TAG_ROUTE = '/api/pages/tag'
export const TAGS_RENAME_ROUTE = '/api/tags/rename'

/**
 * Tags set by hand: POST /api/pages/tag {ids, add, remove, vault} adds and removes tags on pages of
 * the active vault (400 an invalid tag or nothing to do, 404 a page that is not in the vault, 409
 * read only or another vault). Resolves with the number of pages changed.
 */
export async function tagPages(req: { ids: string[]; add: string[]; remove: string[]; vault?: string }, fetcher: typeof fetch = fetch): Promise<number> {
  const b = await postJson(PAGES_TAG_ROUTE, { ids: req.ids, add: req.add, remove: req.remove, ...(req.vault ? { vault: req.vault } : {}) }, fetcher)
  return typeof b.changed === 'number' ? b.changed : 0
}

/** POST /api/tags/rename {from, to, vault}: every page with `from` gets `to` (merged when it has
 *  both); `to` = '' takes the tag off every page. Resolves with the number of pages changed. */
export async function renameTag(req: { from: string; to: string; vault?: string }, fetcher: typeof fetch = fetch): Promise<number> {
  const b = await postJson(TAGS_RENAME_ROUTE, { from: req.from, to: req.to, ...(req.vault ? { vault: req.vault } : {}) }, fetcher)
  return typeof b.changed === 'number' ? b.changed : 0
}

export const RETIRE_ROUTES: Record<RetireAction, string> = { archive: '/api/pages/archive', restore: '/api/pages/restore', delete: '/api/pages/delete' }

export type RetireAnswer = { kind: 'plan'; plan: RetirePlan } | { kind: 'result'; result: RetireResult }

/**
 * Archive, Restore or Delete pages of the active vault: POST /api/pages/<action> {ids, vault,
 * confirm}. Archive and delete without confirm answer 409 needsConfirm with the plan the confirm
 * dialog shows (nothing written); that comes back as kind 'plan'. Throws GraphLoadError with the
 * server's message otherwise (400 nothing that can be done, 409 read only or another vault).
 */
export async function retirePages(action: RetireAction, ids: string[], vault: string, confirm: boolean, fetcher: typeof fetch = fetch): Promise<RetireAnswer> {
  const res = await send(RETIRE_ROUTES[action], { ...POST_JSON, body: JSON.stringify({ ids, ...(vault ? { vault } : {}), ...(confirm ? { confirm: true } : {}) }) }, fetcher)
  const b = await answerOf(res)
  if (res.status === 409 && b.needsConfirm === true) return { kind: 'plan', plan: parsePlan(b.plan) }
  if (res.status !== 200) throw refusal(res, b)
  return { kind: 'result', result: parseResult(b, action) }
}

export const SERIES_MERGE_ROUTE = '/api/series/merge'

/**
 * "Merge duplicates" of a meeting series: POST /api/series/merge {series, vault, confirm}. Without
 * confirm the server answers 409 needsConfirm with the plan the confirm shows (nothing written);
 * that comes back as kind 'plan'. Throws GraphLoadError with the server's message otherwise.
 */
export async function mergeSeries(series: string, vault: string, confirm: boolean, fetcher: typeof fetch = fetch): Promise<MergeAnswer> {
  const res = await send(SERIES_MERGE_ROUTE, { ...POST_JSON, body: JSON.stringify({ series, ...(vault ? { vault } : {}), ...(confirm ? { confirm: true } : {}) }) }, fetcher)
  const b = await answerOf(res)
  if (res.status === 409 && b.needsConfirm === true) return { kind: 'plan', plan: parseMergePlan(b.plan) }
  if (res.status !== 200) throw refusal(res, b)
  return { kind: 'result', result: parseMergeResult(b) }
}

export const LINK_ADD_ROUTE = '/api/link/add'

export type LinkAddStatus = 'linked' | 'already-linked'

/**
 * "Link it": POST /api/link/add {from, to, vault} links page `from` to page `to` in the active vault
 * (the server refuses read-only and other sources with 409). Resolves with the outcome; throws
 * GraphLoadError with the server's message otherwise.
 */
export async function addLink(req: { from: string; to: string; vault?: string }, fetcher: typeof fetch = fetch): Promise<LinkAddStatus> {
  const b = await postJson(LINK_ADD_ROUTE, req.vault ? req : { from: req.from, to: req.to }, fetcher)
  return b.status === 'already-linked' ? 'already-linked' : 'linked'
}
