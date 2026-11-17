// The Meetings panel's words and choices (operator, 2026-11-17: "build as suggested"): today's Teams
// meetings as Copilot lists them, a tick per meeting, then one Add per ticked meeting. Pure.
import type { SubmitResult } from '../api'

export interface Meeting {
  title: string
  /** As Copilot wrote it ("2031-04-09 10:00"), sent back with the notes question. */
  start: string
  /** hh:mm, or '' when Copilot gave no time. */
  time: string
  attendees: number
  hasTranscript: boolean
  hasRecap: boolean
  hasNotes: boolean
  /** Copilot can read a transcript, recap or notes of it. */
  readable: boolean
}

export type MeetingNotes = { found: true; text: string } | { found: false; message: string }

/** Where one ticked meeting is. Each step is a request of its own, so each is observed. */
export type RowState =
  | { step: 'ready' }
  | { step: 'reading' }
  | { step: 'adding' }
  | { step: 'added'; pageTitle: string }
  | { step: 'waiting' }
  | { step: 'skipped'; message: string }
  | { step: 'failed'; message: string }

/** What Copilot can read of a meeting, in a few words. */
export function readableLabel(m: Meeting): string {
  const parts = [m.hasTranscript && 'transcript', m.hasRecap && 'recap', m.hasNotes && 'notes'].filter(Boolean) as string[]
  if (!parts.length) return 'Nothing Copilot can read'
  const s = parts.join(', ')
  return s.charAt(0).toUpperCase() + s.slice(1)
}

/** The line under a meeting's title: time, what Copilot can read, how many people. */
export function meetingSubline(m: Meeting): string {
  const people = m.attendees === 1 ? '1 person' : m.attendees > 1 ? `${m.attendees} people` : ''
  return [m.time, readableLabel(m), people].filter(Boolean).join(' · ')
}

/** The meetings ticked when the list comes: every one Copilot can read something of. */
export function defaultPicks(meetings: Meeting[]): Set<number> {
  return new Set(meetings.flatMap((m, i) => (m.readable ? [i] : [])))
}

export function addLabel(count: number): string {
  if (count < 1) return 'Add meetings'
  return count === 1 ? 'Add 1 meeting' : `Add ${count} meetings`
}

/** One row's state in words ('' when there is nothing to say yet). */
export function rowStateText(s: RowState): string {
  switch (s.step) {
    case 'ready':
      return ''
    case 'reading':
      return 'Copilot is reading the meeting…'
    case 'adding':
      return 'Adding to your wiki…'
    case 'added':
      return s.pageTitle ? `Added as "${s.pageTitle}"` : 'Added'
    case 'waiting':
      return 'Waiting for Copilot: see "Waiting for Copilot" or History'
    case 'skipped':
      return `Not added: ${s.message}`
    case 'failed':
      return `Not added: ${s.message}`
  }
}

/** The row state an Add's answer leads to. */
export function rowStateFromAdd(r: SubmitResult): RowState {
  if (r.intent !== 'add') return { step: 'failed', message: 'it was taken as a question.' }
  if (r.status === 'added') return { step: 'added', pageTitle: r.page?.title ?? '' }
  if (r.status === 'waiting') return { step: 'waiting' }
  if (r.duplicateOf) return { step: 'skipped', message: 'a page with this title is already in your wiki.' }
  return { step: 'failed', message: r.message || 'Add did not work.' }
}

/** The line under the list once a run ended. */
export function runSummary(states: RowState[]): string {
  const n = (step: RowState['step']) => states.filter((s) => s.step === step).length
  const added = n('added')
  const waiting = n('waiting')
  const not = n('failed') + n('skipped')
  const parts = [added && `${added} added`, waiting && `${waiting} waiting for Copilot`, not && `${not} not added`].filter(Boolean)
  return parts.length ? `${parts.join(', ')}.` : ''
}

/** Today on this computer, yyyy-mm-dd. */
export function todayIso(now: Date = new Date()): string {
  const p = (n: number) => String(n).padStart(2, '0')
  return `${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())}`
}
