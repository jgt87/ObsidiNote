// Calls of the activity views: GET /api/activity, POST /api/intake/remove; Undo and "Check for
// the answer" reuse the Add calls (add/api.ts). Every call carries X-ObsidiNote: 1.
import { ApiError, request } from '../api'
import { normalizeActivity, type ActivityList } from './activityModel'

const HEADERS = { 'X-ObsidiNote': '1' }

async function answer(res: Response): Promise<unknown> {
  const data: unknown = await res.json().catch(() => null)
  if (res.status !== 200) {
    const msg = data && typeof data === 'object' && 'error' in data ? String((data as { error: unknown }).error) : `The server answered ${res.status}.`
    throw new ApiError(msg, res.status)
  }
  return data
}

export async function getActivity(signal?: AbortSignal): Promise<ActivityList> {
  return normalizeActivity(await answer(await request('/api/activity', { headers: HEADERS, cache: 'no-store', signal })))
}

/** An Intake item that never became a page goes to OneNote's Deleted Pages. */
export async function removeIntakeItem(inboxId: string, vault = ''): Promise<string> {
  const r = await answer(await request('/api/intake/remove', { method: 'POST', headers: { ...HEADERS, 'Content-Type': 'application/json' }, body: JSON.stringify({ inboxId, ...(vault ? { vault } : {}) }), cache: 'no-store' }))
  return r && typeof r === 'object' && 'message' in r ? String((r as { message: unknown }).message) : 'Removed.'
}
