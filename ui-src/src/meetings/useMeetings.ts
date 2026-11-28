// The Meetings panel's state: the list of one or more days (asked once per request, one day at a
// time: kit P10 found a list of several days comes back empty), the ticks, and a run that adds the
// ticked meetings one after the other: notes (POST /api/meetings/notes), then the normal Add
// (POST /api/submit with origin "meeting"). Session state only, in memory.
import { useRef, useState } from 'react'
import { ApiError, submit } from '../api'
import { getMeetingNotes, getMeetingsOfDay } from './api'
import { defaultPicks, listOutcome, rowStateFromAdd, todayRequest, type Meeting, type MeetingsRequest, type RowState } from './meetingsModel'

export interface FailedDay {
  day: string
  message: string
}

type Phase =
  | { kind: 'idle' }
  | { kind: 'loading'; req: MeetingsRequest; day: string; done: number; total: number }
  | { kind: 'error'; req: MeetingsRequest; message: string }
  | { kind: 'list'; req: MeetingsRequest; meetings: Meeting[]; failed: FailedDay[] }

const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e))
// No Copilot (503) or no server: the other days would fail the same way.
const stopsOtherDays = (e: unknown) => e instanceof ApiError && (e.status === 503 || e.status === 0)

/** Asks days[i] and adds its meetings to found, or the day to failed. A failure that every later day
 *  would share fails those days too and answers false: ask no further. */
async function askDay(days: string[], i: number, series: string, found: Meeting[], failed: FailedDay[]): Promise<boolean> {
  try {
    found.push(...(await getMeetingsOfDay(days[i], series)).meetings)
    return true
  } catch (e) {
    failed.push({ day: days[i], message: errorText(e) })
    if (!stopsOtherDays(e)) return true
    for (const d of days.slice(i + 1)) failed.push({ day: d, message: errorText(e) })
    return false
  }
}

export function useMeetings(onAdded: () => void) {
  const [phase, setPhase] = useState<Phase>({ kind: 'idle' })
  const [picks, setPicks] = useState<Set<string>>(new Set())
  const [rows, setRows] = useState<Record<string, RowState>>({})
  const [running, setRunning] = useState(false)
  // Each fetch counts: a late answer of an earlier fetch is dropped, and its remaining days are not
  // asked (code rule: apply an async result only while its request is the current one).
  const fetchRun = useRef(0)

  /** Lists the days of req, one after the other. keep: meetings already listed (a retry of the days
   *  that failed adds to them). */
  const fetchDays = async (req: MeetingsRequest, days: string[] = req.days, keep: Meeting[] = []) => {
    if (running) return
    const run = ++fetchRun.current
    if (!keep.length) setRows({})
    const found: Meeting[] = []
    const failed: FailedDay[] = []
    for (let i = 0; i < days.length; i++) {
      if (run !== fetchRun.current) return
      setPhase({ kind: 'loading', req, day: days[i], done: i, total: days.length })
      if (!(await askDay(days, i, req.series, found, failed))) break
    }
    if (run !== fetchRun.current) return
    const out = listOutcome(keep, found, failed, days.length)
    if (out.kind === 'error') return setPhase({ kind: 'error', req, message: out.message })
    setPhase({ kind: 'list', req, meetings: out.meetings, failed })
    setPicks((p) => new Set([...(keep.length ? p : []), ...defaultPicks(found)]))
  }

  const fetchDay = () => fetchDays(todayRequest())
  const again = () => (phase.kind === 'idle' ? fetchDay() : fetchDays(phase.req))
  const retryFailed = () => {
    if (phase.kind === 'list' && phase.failed.length) void fetchDays(phase.req, phase.failed.map((f) => f.day), phase.meetings)
  }

  const toggle = (key: string) =>
    setPicks((p) => {
      const n = new Set(p)
      if (n.has(key)) n.delete(key)
      else n.add(key)
      return n
    })

  const setRow = (key: string, s: RowState) => setRows((r) => ({ ...r, [key]: s }))

  const addOne = async (m: Meeting) => {
    setRow(m.key, { step: 'reading' })
    try {
      const notes = await getMeetingNotes(m)
      if (!notes.found) return setRow(m.key, { step: 'skipped', message: notes.message })
      setRow(m.key, { step: 'adding' })
      setRow(m.key, rowStateFromAdd(await submit({ text: notes.text, mode: 'add', origin: 'meeting' })))
    } catch (e) {
      setRow(m.key, { step: 'failed', message: errorText(e) })
    }
  }

  const addPicked = async () => {
    if (phase.kind !== 'list' || running) return
    setRunning(true)
    try {
      // Oldest first, so a series' meetings link to the one before as they are filed.
      for (const m of phase.meetings) if (picks.has(m.key)) await addOne(m)
    } finally {
      setRunning(false)
      setPicks(new Set())
      onAdded()
    }
  }

  return { phase, picks, rows, running, fetchDay, fetchDays, again, retryFailed, toggle, addPicked }
}
