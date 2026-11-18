import { MeetingIcon } from '../components/icons'
import { decisionsAskText } from '../model/handoff'
import { shortDate, type DecisionItem, type JournalDay, type JournalItem } from './journalModel'

const KIND_LABEL: Record<JournalItem['kind'], string> = { entry: 'Journal', journal: 'Journal', page: '' }

/** The type column: a meeting always says so, with its icon (journal entries and meetings are mixed
 *  without a search too, 2026-11-18); other types only while searching. */
function TypeCell({ item, searching }: { item: JournalItem; searching: boolean }) {
  if (item.type === 'meeting') {
    return (
      <span className="jr__type jr__type--meeting">
        <MeetingIcon />
        Meeting
      </span>
    )
  }
  return <span className="jr__type">{searching ? KIND_LABEL[item.kind] || item.type : ''}</span>
}

/** The days, newest first; each item is one button that opens its page (an entry opens its day). */
export function JournalDays({ days, searching, dayLabel, onOpen }: { days: JournalDay[]; searching: boolean; dayLabel: (d: string) => string; onOpen: (pageId: string) => void }) {
  if (!days.length) {
    return (
      <p className="jr__empty">
        {searching
          ? 'Nothing found. Try another topic or fewer words.'
          : 'Nothing in your journal yet. What you add that Copilot files as a journal entry (what happened, what you did or decided) goes into that day’s page.'}
      </p>
    )
  }
  return (
    <div className="jr">
      {days.map((d) => (
        <section key={d.date} className="act" aria-label={dayLabel(d.date)}>
          <h2 className="act__heading">{dayLabel(d.date)}</h2>
          <ul className="act__list">
            {d.items.map((i) => (
              <li key={i.key}>
                <button type="button" className="jr__row" onClick={() => onOpen(i.pageId)}>
                  <span className="jr__time">{i.time}</span>
                  <span className="jr__main">
                    <span className="act__title">{i.title}</span>
                    {i.summary && <span className="act__sub">{i.summary}</span>}
                  </span>
                  <TypeCell item={i} searching={searching} />
                </button>
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  )
}

/** A topic's decision pages with the pages each came from, and the way to have Copilot find
 *  decisions that are not a page of their own yet (an Ask: read only, cites its pages). */
export function JournalDecisions({ decisions, topicPath, onOpen, onAsk }: { decisions: DecisionItem[]; topicPath: string; onOpen: (pageId: string) => void; onAsk: (q: string) => void }) {
  return (
    <div className="jr">
      <div className="jr__ask">
        <p className="jr__caption">
          {decisions.length === 1 ? '1 decision page' : `${decisions.length} decision pages`} about this topic, each with the pages it came from. Decisions written inside other pages are not listed here: Copilot can find them.
        </p>
        <button type="button" className="btn" onClick={() => onAsk(decisionsAskText(topicPath))}>
          Find decisions with Copilot
        </button>
      </div>
      {decisions.length > 0 && (
        <section className="act" aria-label="Decisions">
          <ul className="act__list">
            {decisions.map((d) => (
              <li key={d.page.id}>
                <button type="button" className="jr__row jr__row--dated" onClick={() => onOpen(d.page.id)}>
                  <span className="jr__time">{shortDate(d.date)}</span>
                  <span className="jr__main">
                    <span className="act__title">{d.page.title}</span>
                    {d.page.summary && <span className="act__sub">{d.page.summary}</span>}
                  </span>
                  <span className="jr__type" />
                </button>
                <p className="jr__from">
                  {d.sources.length ? 'From: ' : 'No linked pages.'}
                  {d.sources.map((s, n) => (
                    <span key={s.id}>
                      {n > 0 && ', '}
                      <button type="button" className="link-btn" onClick={() => onOpen(s.id)}>
                        {s.title}
                      </button>
                    </span>
                  ))}
                </p>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  )
}
