import { describe, expect, it } from 'vitest'
import { normalizeSubmitResult } from '../api'
import { addLabel, defaultPicks, meetingSubline, readableLabel, rowStateFromAdd, rowStateText, runSummary, todayIso, type Meeting } from './meetingsModel'

const meeting = (over: Partial<Meeting> = {}): Meeting => ({
  title: 'Garden sync',
  start: '2031-04-09 10:00',
  time: '10:00',
  attendees: 4,
  hasTranscript: false,
  hasRecap: false,
  hasNotes: false,
  readable: false,
  series: 'Garden sync',
  earlier: 0,
  ...over,
})

describe('meetings model', () => {
  it('says what Copilot can read of a meeting', () => {
    expect(readableLabel(meeting({ hasTranscript: true, hasNotes: true, readable: true }))).toBe('Transcript, notes')
    expect(readableLabel(meeting())).toBe('Nothing Copilot can read')
  })

  it('writes the line under a meeting, one person or several', () => {
    expect(meetingSubline(meeting({ attendees: 1 }))).toBe('10:00 · Nothing Copilot can read · 1 person')
    expect(meetingSubline(meeting({ attendees: 5, hasTranscript: true, readable: true }))).toBe('10:00 · Transcript · 5 people')
    expect(meetingSubline(meeting({ attendees: 0, time: '' }))).toBe('Nothing Copilot can read')
  })

  it('says when a meeting is part of a series already in the wiki (2026-11-18)', () => {
    expect(meetingSubline(meeting({ attendees: 0, earlier: 1 }))).toBe('10:00 · Nothing Copilot can read · series, 1 earlier in your wiki')
    expect(meetingSubline(meeting({ attendees: 0, earlier: 14 }))).toBe('10:00 · Nothing Copilot can read · series, 14 earlier in your wiki')
  })

  it('reads a re-imported day as updated, and counts it with the added ones', () => {
    const s = rowStateFromAdd(normalizeSubmitResult({ intent: 'add', status: 'updated', page: { title: 'Garden sync · 2031-04-09' } }))
    expect(s).toEqual({ step: 'updated', pageTitle: 'Garden sync · 2031-04-09' })
    expect(rowStateText(s)).toBe('Updated "Garden sync · 2031-04-09": already in your wiki, its text read again')
    expect(runSummary([s, { step: 'added', pageTitle: '' }])).toBe('2 added.')
  })

  it('ticks the meetings Copilot can read something of', () => {
    const picks = defaultPicks([meeting({ readable: true }), meeting(), meeting({ readable: true })])
    expect([...picks]).toEqual([0, 2])
  })

  it('counts in the Add button', () => {
    expect(addLabel(1)).toBe('Add 1 meeting')
    expect(addLabel(3)).toBe('Add 3 meetings')
    expect(addLabel(0)).toBe('Add meetings')
  })

  it('turns an Add answer into the row state', () => {
    expect(rowStateFromAdd(normalizeSubmitResult({ intent: 'add', status: 'added', page: { title: 'Meeting: Garden sync' } }))).toEqual({ step: 'added', pageTitle: 'Meeting: Garden sync' })
    expect(rowStateFromAdd(normalizeSubmitResult({ intent: 'add', status: 'waiting', inboxId: 'x' })).step).toBe('waiting')
    expect(rowStateFromAdd(normalizeSubmitResult({ intent: 'add', status: 'failed', duplicateOf: 'p1', message: 'dup' })).step).toBe('skipped')
    const f = rowStateFromAdd(normalizeSubmitResult({ intent: 'add', status: 'failed', message: 'Write refused.' }))
    expect(rowStateText(f)).toBe('Not added: Write refused.')
  })

  it('sums up a run', () => {
    expect(runSummary([{ step: 'added', pageTitle: '' }, { step: 'added', pageTitle: '' }, { step: 'waiting' }, { step: 'failed', message: 'x' }])).toBe('2 added, 1 waiting for Copilot, 1 not added.')
    expect(runSummary([{ step: 'ready' }])).toBe('')
  })

  it('writes today as yyyy-mm-dd on this computer', () => {
    expect(todayIso(new Date(2031, 3, 9, 23, 30))).toBe('2031-04-09')
  })
})
