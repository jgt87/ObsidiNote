import { describe, expect, it } from 'vitest'
import { normalizeSubmitResult } from '../api'
import {
  addLabel,
  defaultPicks,
  emptyText,
  failedDaysText,
  formatDay,
  groupByDay,
  loadingText,
  meetingNote,
  meetingSubline,
  readableLabel,
  requestHeading,
  rowStateFromAdd,
  rowStateText,
  runSummary,
  todayIso,
  todayRequest,
  type Meeting,
} from './meetingsModel'

let n = 0
const meeting = (over: Partial<Meeting> = {}): Meeting => ({
  key: `2031-04-09#${n++}`,
  day: '2031-04-09',
  title: 'Garden sync',
  start: '2031-04-09 10:00',
  time: '10:00',
  attendees: 4,
  joined: true,
  hasTranscript: false,
  hasRecap: false,
  hasNotes: false,
  readable: false,
  series: 'Garden sync',
  earlier: 0,
  inWiki: false,
  waiting: false,
  ...over,
})

describe('meetings model', () => {
  it('says what Copilot can read of a meeting', () => {
    expect(readableLabel(meeting({ hasTranscript: true, hasNotes: true, readable: true }))).toBe('Transcript, notes')
    expect(readableLabel(meeting())).toBe('Copilot listed no transcript, recap or notes')
  })

  it('writes the line under a meeting, one person or several', () => {
    expect(meetingSubline(meeting({ attendees: 1 }))).toBe('10:00 · Copilot listed no transcript, recap or notes · 1 person')
    expect(meetingSubline(meeting({ attendees: 5, hasTranscript: true, readable: true }))).toBe('10:00 · Transcript · 5 people')
    expect(meetingSubline(meeting({ attendees: 0, time: '' }))).toBe('Copilot listed no transcript, recap or notes')
  })

  it('says when you were invited but did not join (2026-11-20)', () => {
    expect(meetingSubline(meeting({ attendees: 3, joined: false, hasRecap: true, readable: true }))).toBe('10:00 · Recap · you did not join · 3 people')
  })

  it('says when a meeting is part of a series already in the wiki (2026-11-18)', () => {
    expect(meetingSubline(meeting({ attendees: 0, earlier: 1 }))).toBe('10:00 · Copilot listed no transcript, recap or notes · series, 1 earlier in your wiki')
    expect(meetingSubline(meeting({ attendees: 0, earlier: 14 }))).toBe('10:00 · Copilot listed no transcript, recap or notes · series, 14 earlier in your wiki')
  })

  it('reads a re-imported day as updated, and counts it with the added ones', () => {
    const s = rowStateFromAdd(normalizeSubmitResult({ intent: 'add', status: 'updated', page: { title: 'Garden sync · 2031-04-09' } }))
    expect(s).toEqual({ step: 'updated', pageTitle: 'Garden sync · 2031-04-09' })
    expect(rowStateText(s)).toBe('Updated “Garden sync · 2031-04-09”: already in your wiki, its text read again')
    expect(runSummary([s, { step: 'added', pageTitle: '' }])).toBe('2 added.')
  })

  it('ticks the meetings Copilot can read something of', () => {
    const list = [meeting({ readable: true }), meeting(), meeting({ readable: true })]
    expect([...defaultPicks(list)]).toEqual([list[0].key, list[2].key])
  })

  it('does not tick a meeting already in the wiki or still waiting, and says why (2026-11-18)', () => {
    const list = [meeting({ readable: true, inWiki: true }), meeting({ readable: true, waiting: true }), meeting({ readable: true })]
    expect([...defaultPicks(list)]).toEqual([list[2].key])
    expect(meetingNote(list[0])).toBe('In your wiki: Add reads it again')
    expect(meetingNote(list[1])).toBe('Waiting for Copilot from an earlier Add')
    expect(meetingNote(list[2])).toBe('')
  })

  it('reads the same notes again as already up to date', () => {
    const s = rowStateFromAdd(normalizeSubmitResult({ intent: 'add', status: 'unchanged', page: { title: 'Garden sync · 2031-04-09' } }))
    expect(s.step).toBe('unchanged')
    expect(rowStateText(s)).toBe('Already up to date: nothing changed since the last time')
    expect(runSummary([s])).toBe('1 added.')
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

  describe('other days and several days, from the box (2026-11-20)', () => {
    const now = new Date(2031, 3, 11, 9, 0) // Fri 11 Apr 2031

    it('writes a day short, with the year only for another year', () => {
      expect(formatDay('2031-04-08', now)).toBe('Tue 8 Apr')
      expect(formatDay('2030-12-31', now)).toBe('Tue 31 Dec 2030')
      expect(formatDay('not a day', now)).toBe('not a day')
    })

    it('heads the panel with the days and the series', () => {
      expect(requestHeading(null, now)).toBe('Today’s meetings')
      expect(requestHeading(todayRequest(now), now)).toBe('Today’s meetings')
      expect(requestHeading({ days: ['2031-04-10'], series: '', when: 'yesterday' }, now)).toBe('Meetings of Thu 10 Apr')
      expect(requestHeading({ days: ['2031-04-07', '2031-04-08', '2031-04-09', '2031-04-10', '2031-04-11'], series: 'Daily Standup', when: 'this week' }, now)).toBe('Meetings of Mon 7 Apr to Fri 11 Apr · Daily Standup')
    })

    it('says which day it is listing, and how many are left', () => {
      expect(loadingText('2031-04-11', 0, 1, now)).toBe('Copilot is listing today’s meetings. This can take a minute.')
      expect(loadingText('2031-04-10', 0, 1, now)).toBe('Copilot is listing your meetings of Thu 10 Apr. This can take a minute.')
      expect(loadingText('2031-04-08', 1, 5, now)).toBe('Copilot is listing your meetings of Tue 8 Apr (day 2 of 5). Each day takes about a minute.')
    })

    it('says when nothing was found, naming the series', () => {
      expect(emptyText({ days: ['2031-04-11'], series: '', when: 'today' }, now)).toBe('Copilot found no Teams meetings today that it can see.')
      expect(emptyText({ days: ['2031-04-07', '2031-04-08'], series: 'Daily Standup', when: 'x' }, now)).toBe('Copilot found no meetings of “Daily Standup” on those days that it can see.')
    })

    it('groups the meetings by day, in the order of the list', () => {
      const a = meeting({ day: '2031-04-07' })
      const b = meeting({ day: '2031-04-07' })
      const c = meeting({ day: '2031-04-08' })
      expect(groupByDay([a, b, c]).map((g) => [g.day, g.meetings.length])).toEqual([
        ['2031-04-07', 2],
        ['2031-04-08', 1],
      ])
    })

    it('names the days that could not be listed', () => {
      expect(failedDaysText([], now)).toBe('')
      expect(failedDaysText([{ day: '2031-04-08', message: 'Copilot did not answer.' }], now)).toBe('Tue 8 Apr could not be listed: Copilot did not answer.')
      expect(failedDaysText([{ day: '2031-04-08', message: 'x' }, { day: '2031-04-09', message: 'y' }], now)).toBe('2 days could not be listed (Tue 8 Apr, Wed 9 Apr): x')
    })

    it('reads a meetings answer of the box as the days to list', () => {
      expect(normalizeSubmitResult({ intent: 'meetings', days: ['2031-04-10', 'nope'], series: 'Daily Standup', when: 'yesterday' })).toEqual({ intent: 'meetings', days: ['2031-04-10'], series: 'Daily Standup', when: 'yesterday' })
      // PS 5.1 sends a one-item array as the item itself.
      expect(normalizeSubmitResult({ intent: 'meetings', days: '2031-04-10' })).toEqual({ intent: 'meetings', days: ['2031-04-10'], series: '', when: '' })
    })
  })
})
