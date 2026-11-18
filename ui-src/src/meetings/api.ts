// Calls of the Meetings panel (lib/Server.psm1; both read only, both ask Copilot):
//   POST /api/meetings/day   { day? }                          -> { day, meetings }
//   POST /api/meetings/notes { title, start, time, day }       -> { found, text, ... } | { found: false, message }
// A meeting's notes are then filed through the normal Add (api.ts submit, origin "meeting").
import { ApiError, asList, request } from '../api'
import type { Meeting, MeetingNotes } from './meetingsModel'

const HEADERS = { 'X-ObsidiNote': '1', 'Content-Type': 'application/json' }

async function post(path: string, body: unknown, signal?: AbortSignal): Promise<Record<string, unknown>> {
  const res = await request(path, { method: 'POST', headers: HEADERS, body: JSON.stringify(body), cache: 'no-store', signal })
  const data: unknown = await res.json().catch(() => null)
  if (res.status !== 200) {
    const msg = data && typeof data === 'object' && 'error' in data ? String((data as { error: unknown }).error) : `The server answered ${res.status}.`
    throw new ApiError(msg, res.status)
  }
  return (data && typeof data === 'object' ? data : {}) as Record<string, unknown>
}

const text = (v: unknown): string => (typeof v === 'string' ? v : '')

/** The Teams meetings of one day (today when day is ''), as Copilot lists them. */
export async function getMeetingsOfDay(day: string, signal?: AbortSignal): Promise<{ day: string; meetings: Meeting[] }> {
  const r = await post('/api/meetings/day', day ? { day } : {}, signal)
  const meetings = asList(r.meetings as Meeting[] | Meeting | null).map((m) => ({
    title: text(m.title),
    start: text(m.start),
    time: text(m.time),
    attendees: typeof m.attendees === 'number' ? m.attendees : 0,
    hasTranscript: m.hasTranscript === true,
    hasRecap: m.hasRecap === true,
    hasNotes: m.hasNotes === true,
    readable: m.readable === true,
    series: text(m.series),
    earlier: typeof m.earlier === 'number' ? m.earlier : 0,
    inWiki: m.inWiki === true,
    waiting: m.waiting === true,
  }))
  return { day: text(r.day) || day, meetings }
}

/** One meeting's notes as the text an Add files. */
export async function getMeetingNotes(m: Meeting, day: string, signal?: AbortSignal): Promise<MeetingNotes> {
  const r = await post('/api/meetings/notes', { title: m.title, start: m.start, time: m.time, day }, signal)
  return r.found === true ? { found: true, text: text(r.text) } : { found: false, message: text(r.message) || 'Copilot could not read this meeting.' }
}
