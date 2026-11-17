// The Meetings panel's state: the day's list (asked once per click), the ticks, and a run that adds
// the ticked meetings one after the other: notes (POST /api/meetings/notes), then the normal Add
// (POST /api/submit with origin "meeting"). Session state only, in memory.
import { useRef, useState } from 'react'
import { submit } from '../api'
import { getMeetingNotes, getMeetingsOfDay } from './api'
import { defaultPicks, rowStateFromAdd, todayIso, type Meeting, type RowState } from './meetingsModel'

type Phase = { kind: 'idle' } | { kind: 'loading' } | { kind: 'error'; message: string } | { kind: 'list'; day: string; meetings: Meeting[] }

const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e))

export function useMeetings(onAdded: () => void) {
  const [phase, setPhase] = useState<Phase>({ kind: 'idle' })
  const [picks, setPicks] = useState<Set<number>>(new Set())
  const [rows, setRows] = useState<Record<number, RowState>>({})
  const [running, setRunning] = useState(false)
  // Each fetch counts: a late answer of an earlier fetch is dropped (code rule: apply an async result
  // only while its request is the current one).
  const fetchRun = useRef(0)

  const fetchDay = async () => {
    const run = ++fetchRun.current
    setPhase({ kind: 'loading' })
    setRows({})
    try {
      const r = await getMeetingsOfDay(todayIso())
      if (run !== fetchRun.current) return
      setPhase({ kind: 'list', day: r.day, meetings: r.meetings })
      setPicks(defaultPicks(r.meetings))
    } catch (e) {
      if (run === fetchRun.current) setPhase({ kind: 'error', message: errorText(e) })
    }
  }

  const toggle = (i: number) =>
    setPicks((p) => {
      const n = new Set(p)
      if (n.has(i)) n.delete(i)
      else n.add(i)
      return n
    })

  const setRow = (i: number, s: RowState) => setRows((r) => ({ ...r, [i]: s }))

  const addOne = async (m: Meeting, i: number, day: string) => {
    setRow(i, { step: 'reading' })
    try {
      const notes = await getMeetingNotes(m, day)
      if (!notes.found) return setRow(i, { step: 'skipped', message: notes.message })
      setRow(i, { step: 'adding' })
      setRow(i, rowStateFromAdd(await submit({ text: notes.text, mode: 'add', origin: 'meeting' })))
    } catch (e) {
      setRow(i, { step: 'failed', message: errorText(e) })
    }
  }

  const addPicked = async () => {
    if (phase.kind !== 'list' || running) return
    setRunning(true)
    try {
      for (const i of [...picks].sort((a, b) => a - b)) await addOne(phase.meetings[i], i, phase.day)
    } finally {
      setRunning(false)
      setPicks(new Set())
      onAdded()
    }
  }

  return { phase, picks, rows, running, fetchDay, toggle, addPicked }
}
