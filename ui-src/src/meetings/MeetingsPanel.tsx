import { addLabel, meetingNote, meetingSubline, rowStateText, runSummary, type Meeting, type RowState } from './meetingsModel'
import { useMeetings } from './useMeetings'
import './meetings.css'

/** "Today's meetings" on the home page (operator, 2026-11-17): Copilot lists today's Teams meetings,
 *  the person ticks the ones to keep, and each becomes a meeting page through the normal Add (it then
 *  shows in History and can be undone there). Nothing is written before "Add". */
export function MeetingsPanel({ onAdded }: { onAdded: () => void }) {
  const m = useMeetings(onAdded)
  const { phase } = m
  return (
    <section className="mt" aria-labelledby="meetings-heading">
      <h2 id="meetings-heading" className="mt__heading">
        Today's meetings
      </h2>
      {phase.kind === 'idle' && (
        <div className="mt__bar">
          <p className="mt__text">Copilot lists your Teams meetings of today. Pick the ones to keep: each becomes a meeting page with its summary, decisions and actions.</p>
          <button type="button" className="btn" onClick={() => void m.fetchDay()}>
            Fetch today's meetings
          </button>
        </div>
      )}
      {phase.kind === 'loading' && (
        <p className="mt__text mt__pad" role="status" aria-busy="true">
          Copilot is listing today's meetings. This can take a minute.
        </p>
      )}
      {phase.kind === 'error' && (
        <div className="mt__bar" role="alert">
          <p className="mt__text">{phase.message}</p>
          <button type="button" className="btn" onClick={() => void m.fetchDay()}>
            Try again
          </button>
        </div>
      )}
      {phase.kind === 'list' && <MeetingList meetings={phase.meetings} m={m} />}
    </section>
  )
}

function MeetingList({ meetings, m }: { meetings: Meeting[]; m: ReturnType<typeof useMeetings> }) {
  if (!meetings.length) {
    return (
      <div className="mt__bar">
        <p className="mt__text">Copilot found no Teams meetings today that it can see.</p>
        <button type="button" className="btn" onClick={() => void m.fetchDay()}>
          Fetch again
        </button>
      </div>
    )
  }
  const states = Object.values(m.rows)
  const summary = m.running ? '' : runSummary(states)
  return (
    <>
      <ul className="mt__list">
        {meetings.map((x, i) => (
          <MeetingRow key={`${i}-${x.title}`} meeting={x} checked={m.picks.has(i)} disabled={m.running || !!m.rows[i]} state={m.rows[i]} onToggle={() => m.toggle(i)} />
        ))}
      </ul>
      <div className="mt__bar mt__foot">
        <button type="button" className="btn" disabled={m.running || !m.picks.size} aria-busy={m.running} onClick={() => void m.addPicked()}>
          {m.running ? 'Adding…' : addLabel(m.picks.size)}
        </button>
        <button type="button" className="btn btn--ghost" disabled={m.running} onClick={() => void m.fetchDay()}>
          Fetch again
        </button>
        {summary && (
          <p className="mt__text" role="status">
            {summary}
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
