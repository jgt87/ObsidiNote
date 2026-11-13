// Calls of the Add result screen. The routes are planned for the merge (see the step 4 report):
//   POST /api/submit       { text, mode }                  -> AddResult   (mode add, existing route)
//   POST /api/add/undo     { undo }                        -> UndoResult
//   POST /api/link/update  { id, decision?, proposed? }    -> AddResult
// Every call carries X-ObsidiNote: 1, which the server requires.
import { ApiError } from '../api'
import { normalizeAddResult, type AddResult, type LinkSummary, type UndoRecord, type UndoResult } from './types'

async function post<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'X-ObsidiNote': '1', 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    cache: 'no-store',
  })
  const data: unknown = await res.json().catch(() => null)
  if (res.status !== 200) {
    const msg = data && typeof data === 'object' && 'error' in data ? String((data as { error: unknown }).error) : `The server answered ${res.status}.`
    throw new ApiError(msg, res.status)
  }
  return data as T
}

export async function addItem(text: string, mode: 'add' | 'auto' = 'add'): Promise<AddResult> {
  return normalizeAddResult(await post('/api/submit', { text, mode }))
}

export function undoAdd(undo: UndoRecord): Promise<UndoResult> {
  return post<UndoResult>('/api/add/undo', { undo })
}

export async function updateLink(id: string, decision?: 'replace' | 'keep', proposed?: LinkSummary): Promise<AddResult> {
  return normalizeAddResult(await post('/api/link/update', { id, decision: decision ?? '', proposed: proposed ?? null }))
}
