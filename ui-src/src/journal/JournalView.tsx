import { useMemo, useState } from 'react'
import { Notice } from '../components/Notice'
import type { GraphModel } from '../graph/model'
import { buildJournal, dayLabel, decisionsFor, journalCaption, meetingSeries, type JournalFilter, type MeetingSeries } from './journalModel'
import { JournalDays, JournalDecisions } from './JournalLists'
import { JournalSearch } from './JournalSearch'
import { useJournalModel } from './useJournalModel'
import './journal.css'

export interface JournalViewProps {
  /** The active vault's key (null: no active vault); the model is read again when it changes. */
  vaultKey: string | null
  load: (signal: AbortSignal) => Promise<GraphModel>
  /** Opens a page of the active vault in the page window. */
  onOpen: (pageId: string) => void
  /** Hands a question to Ask (read only) and shows it. */
  onAsk: (question: string) => void
  /** Ask within one meeting series: the box opens limited to that series' meetings (2026-11-18). */
  onAskSeries: (s: MeetingSeries) => void
}

type Tab = 'all' | 'decisions'

/** The Journal (operator, 2026-11-17): your journal one page per day; searched on a topic or words,
 *  everything relevant from all sources and all days, and for a topic its decisions with the pages
 *  they came from. Built from the active vault's map data; read only. */
export function JournalView({ vaultKey, load, onOpen, onAsk, onAskSeries }: JournalViewProps) {
  const { model, error, loading, reload } = useJournalModel(vaultKey, load)
  const [filter, setFilter] = useState<JournalFilter>({ topicId: '', text: '' })
  const [tab, setTab] = useState<Tab>('all')
  const topic = model?.topics.find((t) => t.id === filter.topicId)
  const series = useMemo(() => (model ? meetingSeries(model) : []), [model])
  const seriesName = series.find((s) => s.key === filter.series)?.name ?? ''
  const days = useMemo(() => (model ? buildJournal(model, filter) : []), [model, filter])
  const decisions = useMemo(() => (model && filter.topicId ? decisionsFor(model, filter.topicId) : []), [model, filter.topicId])
  const showDecisions = tab === 'decisions' && Boolean(topic)

  return (
    <div className="page">
      <h1 className="page__title">Journal</h1>
      {model && (
        <JournalSearch
          topics={model.topics}
          series={series}
          filter={filter}
          topic={topic}
          onAskSeries={onAskSeries}
          onChange={(f) => {
            setFilter(f)
            if (!f.topicId) setTab('all')
          }}
        />
      )}
      {topic && <JournalTabs tab={tab} onTab={setTab} />}
      {model && !showDecisions && <p className="jr__caption">{journalCaption(filter, topic, days, seriesName)}</p>}
      <JournalBody
        vaultKey={vaultKey}
        model={model}
        error={error}
        loading={loading}
        onRetry={reload}
        content={
          showDecisions && topic ? (
            <JournalDecisions decisions={decisions} topicPath={topic.path} onOpen={onOpen} onAsk={onAsk} />
          ) : (
            <JournalDays days={days} searching={Boolean(filter.topicId || filter.text.trim() || filter.series)} dayLabel={dayLabel} onOpen={onOpen} />
          )
        }
      />
    </div>
  )
}

function JournalTabs({ tab, onTab }: { tab: Tab; onTab: (t: Tab) => void }) {
  return (
    <div className="seg jr__tabs" role="group" aria-label="Show">
      <button type="button" className="seg__btn" aria-pressed={tab === 'all'} onClick={() => onTab('all')}>
        Everything
      </button>
      <button type="button" className="seg__btn" aria-pressed={tab === 'decisions'} onClick={() => onTab('decisions')}>
        Decisions
      </button>
    </div>
  )
}

/** Loading, error and no-vault states, else the list. */
function JournalBody({ vaultKey, model, error, loading, onRetry, content }: { vaultKey: string | null; model: GraphModel | null; error: string; loading: boolean; onRetry: () => void; content: React.JSX.Element }) {
  if (!vaultKey) return <p className="jr__empty">Open a vault to see its journal.</p>
  if (!model && loading) return <p className="jr__empty" role="status">Reading your vault...</p>
  if (!model && error) {
    return (
      <Notice
        error
        title="The journal could not be read"
        actions={
          <button type="button" className="btn btn--sm" onClick={onRetry}>
            Try again
          </button>
        }
      >
        <p>{error}</p>
      </Notice>
    )
  }
  if (!model) return null
  return content
}
