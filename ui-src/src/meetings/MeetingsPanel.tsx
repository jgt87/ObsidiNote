import { useEffect, useRef } from 'react'
import {
  addLabel,
  emptyText,
  failedDaysText,
  formatDay,
  groupByDay,
  loadingText,
  meetingNote,
  meetingSubline,
  requestHeading,
  rowStateText,
  runSummary,
  type Meeting,
  type MeetingsRequest,
  type RowState,
} from './meetingsModel'
import { useMeetings } from './useMeetings'
import './meetings.css'

/** "Today's meetings" on the home page (operator, 2026-11-17): Copilot lists today's Teams meetings,
 *  the person ticks the ones to keep, and each becomes a meeting page through the normal Add (it then
 *  shows in History and can be undone there). Nothing is written before "Add". Other days, several
 *  days and one series come from the box ("meetings yesterday", "Daily Standup meetings this week";
 *  operator, 2026-11-20): request is what was sent there, listed here one day at a time. */
export function MeetingsPanel({ onAdded, request }: { onAdded: () => void; request?: MeetingsRequest | null }) {
  const m = useMeetings(onAdded)
  const { phase } = m
  const ref = useRef<HTMLElement>(null)
  // Each send from the box lists its days once (key changes per send) and brings the panel in view.
  useEffect(() => {
    if (!request) return
    void m.fetchDays(request)
    ref.current?.scrollIntoView?.({ block: 'nearest', behavior: 'smooth' })
    // m changes every render; the request's key is what starts a fetch.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [request?.key])
  const heading = phase.kind === 'idle' ? requestHeading(null) : requestHeading(phase.req)
  return (
    <section className="mt" aria-labelledby="meetings-heading" ref={ref}>
      <h2 id="meetings-heading" className="mt__heading">
        {heading}
      </h2>
      {phase.kind === 'idle' && (
        <div className="mt__bar">
          <p className="mt__text">
            Copilot lists your Teams meetings of today. Pick the ones to keep: each becomes a meeting page with its summary, decisions and actions. For other days, type in the box above, such as{' '}
            <q>Fetch yesterday</q> or <q>Get Daily Standup this week</q>.
          </p>
          <button type="button" className="btn" onClick={() => void m.fetchDay()}>
            Fetch today’s meetings
          </button>
        </div>
      )}
      {phase.kind === 'loading' && (
        <p className="mt__text mt__pad" role="status" aria-busy="true">
          {loadingText(phase.day, phase.done, phase.total)}
        </p>
      )}
      {phase.kind === 'error' && (
        <div className="mt__bar" role="alert">
          <p className="mt__text">{phase.message}</p>
          <button type="button" className="btn" onClick={() => void m.again()}>
            Try again
          </button>
        </div>
      )}
      {phase.kind === 'list' && <MeetingList req={phase.req} meetings={phase.meetings} failed={phase.failed} m={m} />}
    </section>
  )
}

function MeetingList({ req, meetings, failed, m }: { req: MeetingsRequest; meetings: Meeting[]; failed: { day: string; message: string }[]; m: ReturnType<typeof useMeetings> }) {
  const failedLine = failedDaysText(failed)
  const retry = failed.length ? (
    <button type="button" className="btn btn--ghost" disabled={m.running} onClick={m.retryFailed}>
      {failed.length === 1 ? 'Try that day again' : `Try those ${failed.length} days again`}
    </button>
  ) : null
  if (!meetings.length) {
    return (
      <div className="mt__bar">
        <p className="mt__text">{failedLine || emptyText(req)}</p>
        {retry}
        <button type="button" className="btn" onClick={() => void m.again()}>
          Fetch again
        </button>
      </div>
    )
  }
  const states = Object.values(m.rows)
  const summary = m.running ? '' : runSummary(states)
  // Several days: one sub-heading per day, so a week of a daily meeting reads as five rows by date.
  const groups = req.days.length > 1 ? groupByDay(meetings) : [{ day: '', meetings }]
  return (
    <>
      {groups.map((g) => (
        <div key={g.day || 'one'} className="mt__group">
          {g.day && <h3 className="mt__day">{formatDay(g.day)}</h3>}
          <ul className="mt__list">
            {g.meetings.map((x) => (
              <MeetingRow key={x.key} meeting={x} checked={m.picks.has(x.key)} disabled={m.running || !!m.rows[x.key]} state={m.rows[x.key]} onToggle={() => m.toggle(x.key)} />
            ))}
          </ul>
        </div>
      ))}
      <div className="mt__bar mt__foot">
        <button type="button" className="btn" disabled={m.running || !m.picks.size} aria-busy={m.running} onClick={() => void m.addPicked()}>
          {m.running ? 'Adding…' : addLabel(m.picks.size)}
        </button>
        <button type="button" className="btn btn--ghost" disabled={m.running} onClick={() => void m.again()}>
          Fetch again
        </button>
        {retry}
        {(summary || failedLine) && (
          <p className="mt__text" role="status">
            {[summary, failedLine].filter(Boolean).join(' ')}
          </p>
        )}
      </div>
    </>
  )
}

function MeetingRow({ meeting, checked, disabled, state, onToggle }: { meeting: Meeting; checked: boolean; disabled: boolean; state?: RowState; onToggle: () => void }) {
  const said = state ? rowStateText(state) : meetingNote(meeting)
  const sub = meetingSubline(meeting)
  return (
    <li className="mt__row">
      <label className="mt__pick">
        <input type="checkbox" checked={checked} disabled={disabled} onChange={onToggle} />
        <span className="mt__main">
          <span className="mt__title" title={meeting.title}>
            {meeting.title}
          </span>
          <span className="mt__sub">{sub}</span>
        </span>
      </label>
      {said && (
        <span className="mt__state" role="status">
          {said}
        </span>
      )}
    </li>
  )
}
