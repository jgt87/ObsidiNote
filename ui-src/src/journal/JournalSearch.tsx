import { useId, useState } from 'react'
import type { GraphTopic } from '../graph/model'
import { matchingSeries, matchingTopics, type JournalFilter, type MeetingSeries } from './journalModel'

/** One field: words find titles and summaries; a topic picked from the suggestions under it narrows
 *  the list to that topic and its subtopics (shown as a removable "Topic:" line); a meeting series
 *  picked there lists that series' meetings only, with "Ask about these meetings" (2026-11-18). */
export function JournalSearch({ topics, series, filter, topic, onChange, onAskSeries, onOpen }: {
  topics: GraphTopic[]
  series: MeetingSeries[]
  filter: JournalFilter
  topic: GraphTopic | undefined
  onChange: (f: JournalFilter) => void
  onAskSeries: (s: MeetingSeries) => void
  /** Opens a page in the page window: here the series' overview page (2026-11-19). */
  onOpen: (pageId: string) => void
}) {
  const id = useId()
  const [typed, setTyped] = useState(filter.text)
  const picked = filter.series ? series.find((s) => s.key === filter.series) : undefined
  const chosen = Boolean(filter.topicId || filter.series)
  const suggestions = chosen ? [] : matchingTopics(topics, typed)
  const seriesHits = chosen ? [] : matchingSeries(series, typed)
  const pick = (f: JournalFilter) => {
    setTyped('')
    onChange(f)
  }
  return (
    <div className="jr__search">
      <label className="jr__label" htmlFor={id}>
        Search by topic, meeting or words
      </label>
      <input
        id={id}
        className="field jr__field"
        type="search"
        value={typed}
        placeholder="A topic, a meeting, a name, a word"
        onChange={(e) => {
          setTyped(e.target.value)
          onChange({ ...filter, text: e.target.value })
        }}
      />
      {(suggestions.length > 0 || seriesHits.length > 0) && (
        <div className="jr__suggest" role="group" aria-label="Topics and meetings">
          {seriesHits.map((s) => (
            <button key={`s:${s.key}`} type="button" className="btn btn--sm" onClick={() => pick({ topicId: '', text: '', series: s.key })}>
              Meetings: {s.name} ({s.count})
            </button>
          ))}
          {suggestions.map((t) => (
            <button key={t.id} type="button" className="btn btn--sm" onClick={() => pick({ topicId: t.id, text: '' })}>
              Topic: {t.path}
            </button>
          ))}
        </div>
      )}
      {topic && (
        <p className="jr__topic">
          Topic: <b>{topic.path}</b>{' '}
          <button type="button" className="link-btn" onClick={() => onChange({ ...filter, topicId: '' })}>
            Remove
          </button>
        </p>
      )}
      {picked && (
        <div className="jr__series">
          <span>
            Meetings: <b>{picked.name}</b>{' '}
            <button type="button" className="link-btn" onClick={() => onChange({ ...filter, series: '' })}>
              Remove
            </button>
          </span>
          {picked.pageId && (
            <button type="button" className="btn btn--sm" onClick={() => onOpen(picked.pageId)}>
              Open the series page
            </button>
          )}
          <button type="button" className="btn btn--sm" onClick={() => onAskSeries(picked)}>
            Ask about these meetings
          </button>
        </div>
      )}
    </div>
  )
}
