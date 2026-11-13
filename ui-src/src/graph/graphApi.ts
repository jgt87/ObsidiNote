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
