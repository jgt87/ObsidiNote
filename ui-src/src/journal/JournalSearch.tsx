import { useId, useState } from 'react'
import type { GraphTopic } from '../graph/model'
import { matchingTopics, type JournalFilter } from './journalModel'

/** One field: words find titles and summaries; a topic picked from the suggestions under it narrows
 *  the list to that topic and its subtopics (shown as a removable "Topic:" line). */
export function JournalSearch({ topics, filter, topic, onChange }: { topics: GraphTopic[]; filter: JournalFilter; topic: GraphTopic | undefined; onChange: (f: JournalFilter) => void }) {
  const id = useId()
  const [typed, setTyped] = useState(filter.text)
  const suggestions = filter.topicId ? [] : matchingTopics(topics, typed)
  return (
    <div className="jr__search">
      <label className="jr__label" htmlFor={id}>
        Search by topic or words
      </label>
      <input
        id={id}
        className="field jr__field"
        type="search"
        value={typed}
        placeholder="A topic, a name, a word"
        onChange={(e) => {
          setTyped(e.target.value)
          onChange({ ...filter, text: e.target.value })
        }}
      />
      {suggestions.length > 0 && (
        <div className="jr__suggest" role="group" aria-label="Topics">
          {suggestions.map((t) => (
            <button
              key={t.id}
              type="button"
              className="btn btn--sm"
              onClick={() => {
                setTyped('')
                onChange({ topicId: t.id, text: '' })
              }}
            >
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
    </div>
  )
}
