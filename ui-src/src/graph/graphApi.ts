// Loads the graph model from the local server. The merge points this at the real route:
// GET /api/graph?vault=<vault id>  or  GET /api/graph?notebook=<notebook id>
// (lib/Server.psm1 adds the route; step 2 builds the model). Every call carries
// X-ObsidiNote: 1, which the server requires.

import { normalizeGraph, type GraphModel } from './model'

export type GraphSourceRef = { vault: string } | { notebook: string } | Record<string, never>

export const GRAPH_ROUTE = '/api/graph'

export class GraphLoadError extends Error {
  constructor(message: string, readonly status: number) {
    super(message)
  }
}

export function graphUrl(ref: GraphSourceRef = {}, route = GRAPH_ROUTE): string {
  const q = new URLSearchParams()
  if ('vault' in ref && ref.vault) q.set('vault', ref.vault)
  else if ('notebook' in ref && ref.notebook) q.set('notebook', ref.notebook)
  const s = q.toString()
  return s ? `${route}?${s}` : route
}

export async function fetchGraph(ref: GraphSourceRef = {}, signal?: AbortSignal, fetcher: typeof fetch = fetch): Promise<GraphModel> {
  let res: Response
  try {
    res = await fetcher(graphUrl(ref), { headers: { 'X-ObsidiNote': '1' }, cache: 'no-store', signal })
  } catch (e) {
    if (e instanceof DOMException && e.name === 'AbortError') throw e
    throw new GraphLoadError('ObsidiNote is not answering. Is it still running?', 0)
  }
  const body: unknown = await res.json().catch(() => null)
  if (res.status !== 200) {
    const msg = body && typeof body === 'object' && 'error' in body ? String((body as { error: unknown }).error) : `The server answered ${res.status}.`
    throw new GraphLoadError(msg, res.status)
  }
  return normalizeGraph(body)
}

export const LINK_ADD_ROUTE = '/api/link/add'

export type LinkAddStatus = 'linked' | 'already-linked'

/**
 * "Link it": POST /api/link/add {from, to, vault} links page `from` to page `to` in the active vault
 * (the server refuses read-only and other sources with 409). Resolves with the outcome; throws
 * GraphLoadError with the server's message otherwise.
 */
export async function addLink(req: { from: string; to: string; vault?: string }, fetcher: typeof fetch = fetch): Promise<LinkAddStatus> {
  let res: Response
  try {
    res = await fetcher(LINK_ADD_ROUTE, {
      method: 'POST',
      headers: { 'X-ObsidiNote': '1', 'Content-Type': 'application/json' },
      body: JSON.stringify(req.vault ? req : { from: req.from, to: req.to }),
    })
  } catch {
    throw new GraphLoadError('ObsidiNote is not answering. Is it still running?', 0)
  }
  const body: unknown = await res.json().catch(() => null)
  const b = (body && typeof body === 'object' ? body : {}) as { status?: unknown; error?: unknown }
  if (res.status !== 200) throw new GraphLoadError(b.error ? String(b.error) : `The server answered ${res.status}.`, res.status)
  return b.status === 'already-linked' ? 'already-linked' : 'linked'
}
