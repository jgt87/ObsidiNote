// The route-level view: loads the model, then shows the graph, or loading / empty / error.
// The merge renders <GraphView load={() => fetchGraph({ vault })} ... /> for the Map nav entry.

import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { KnowledgeGraph, type KnowledgeGraphProps } from './KnowledgeGraph'
import { withMentions } from './mentions'
import type { GraphModel } from './model'
import { useGraphWrites } from './useGraphWrites'
import './graph.css'

type State = { status: 'loading' } | { status: 'ready'; model: GraphModel } | { status: 'error'; message: string }

export interface GraphViewProps extends Omit<KnowledgeGraphProps, 'model'> {
  /** Loads the model, e.g. (signal) => fetchGraph({ vault: id }, signal). */
  load: (signal: AbortSignal) => Promise<GraphModel>
  /** Change it to reload (e.g. the vault or notebook id). */
  sourceKey?: string
  /** Shown in the empty state as the way to add pages (e.g. a button to Add). */
  onAdd?: () => void
}

export function GraphView({ load, sourceKey, onAdd, onLinkMention, onEditPage, onTagPages, loadBody, onRetire, onUpdateLink, onMergeSeries, ...rest }: GraphViewProps) {
  const { state, refresh, retry } = useGraphLoad(load, sourceKey)
  const loaded = state.status === 'ready' ? state.model : null
  // Mentions, not linked: found here from titles, aliases and summaries (the server sends links only).
  const model = useMemo(() => (loaded ? withMentions(loaded) : null), [loaded])
  const writes = useGraphWrites(model, refresh, { onLinkMention, onEditPage, onTagPages, loadBody, onRetire, onUpdateLink, onMergeSeries })
  const title = rest.title ?? 'Knowledge graph'

  if (state.status === 'loading') return <GraphSkeleton title={title} />
  if (state.status === 'error') {
    return (
      <GraphMessage title={title} alert heading="The map could not be loaded" text={state.message}>
        <button type="button" className="btn" onClick={retry} aria-label="Try again: load the map">
          Try again
        </button>
      </GraphMessage>
    )
  }
  if (!model || model.pages.length === 0) {
    return (
      <GraphMessage title={title} heading="No pages yet" text="Everything you add shows up here as a dot, grouped by topic and linked by relevance.">
        {onAdd && (
          <button type="button" className="btn btn--primary" onClick={onAdd}>
            Add something
          </button>
        )}
      </GraphMessage>
    )
  }
  return <KnowledgeGraph model={model} {...writes} {...rest} />
}

/**
 * The model: loaded when the view opens and again when `load`, `sourceKey` or a retry asks for it
 * (an answer for an earlier request is dropped); `refresh` reads it again WITHOUT the loading state,
 * so the map and an open page window stay while a write shows up in place.
 */
function useGraphLoad(load: (signal: AbortSignal) => Promise<GraphModel>, sourceKey: string | undefined) {
  const [state, setState] = useState<State>({ status: 'loading' })
  const [attempt, setAttempt] = useState(0)
  const refresh = useCallback(async () => {
    const m = await load(new AbortController().signal)
    setState({ status: 'ready', model: m })
  }, [load])
  useEffect(() => {
    const ctl = new AbortController()
    setState({ status: 'loading' })
    load(ctl.signal).then(
      (model) => {
        if (!ctl.signal.aborted) setState({ status: 'ready', model })
      },
      (e: unknown) => {
        if (ctl.signal.aborted) return
        setState({ status: 'error', message: e instanceof Error && e.message ? e.message : 'The map could not be loaded.' })
      },
    )
    return () => ctl.abort()
  }, [load, sourceKey, attempt])
  const retry = useCallback(() => setAttempt((n) => n + 1), [])
  return { state, refresh, retry }
}

/** The view's title and one message in place of the map (an error is an alert), with its action.
 *  Exported for its test (GraphView.test.tsx). */
export function GraphMessage({ title, heading, text, alert = false, children }: { title: string; heading: string; text: string; alert?: boolean; children?: ReactNode }) {
  return (
    <div className="kg">
      {title && <h1 className="kg-title">{title}</h1>}
      <div className="kg-state" role={alert ? 'alert' : undefined}>
        <h2>{heading}</h2>
        <p>{text}</p>
        {children}
      </div>
    </div>
  )
}

/** Loading: the title and one line of text, nothing drawn on the map. design: no placeholder areas;
 *  grey blobs before the data arrives looked like topics of an empty vault (user, 2026-11-13: "when
 *  there's no data then there shouldn't be anything here"). Every mark on the map is content. */
export function GraphSkeleton({ title = 'Knowledge graph' }: { title?: string }) {
  return (
    <div className="kg" aria-busy="true">
      {title && <h1 className="kg-title">{title}</h1>}
      <div className="kg-state">
        <p role="status">Reading the map…</p>
      </div>
    </div>
  )
}
