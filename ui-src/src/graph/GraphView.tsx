// The route-level view: loads the model, then shows the graph, or loading / empty / error.
// The merge renders <GraphView load={() => fetchGraph({ vault })} ... /> for the Map nav entry.

import { useCallback, useEffect, useState } from 'react'
import { KnowledgeGraph, type KnowledgeGraphProps } from './KnowledgeGraph'
import type { GraphModel } from './model'
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

export function GraphView({ load, sourceKey, onAdd, ...rest }: GraphViewProps) {
  const [state, setState] = useState<State>({ status: 'loading' })
  const [attempt, setAttempt] = useState(0)

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
  const title = rest.title ?? 'Knowledge graph'

  if (state.status === 'loading') return <GraphSkeleton title={title} />
  if (state.status === 'error') {
    return (
      <div className="kg">
        {title && <h1 className="kg-title">{title}</h1>}
        <div className="kg-state" role="alert">
          <h2>The map could not be loaded</h2>
          <p>{state.message}</p>
          <button type="button" className="btn" onClick={retry}>
            Try again
          </button>
        </div>
      </div>
    )
  }
  if (state.model.pages.length === 0) {
    return (
      <div className="kg">
        {title && <h1 className="kg-title">{title}</h1>}
        <div className="kg-state">
          <h2>No pages yet</h2>
          <p>Everything you add shows up here as a dot, grouped by topic and linked by relevance.</p>
          {onAdd && (
            <button type="button" className="btn btn--primary" onClick={onAdd}>
              Add something
            </button>
          )}
        </div>
      </div>
    )
  }
  return <KnowledgeGraph model={state.model} {...rest} />
}

/** Loading: grey placeholders in the shape of the map (areas only; no fake dots). */
export function GraphSkeleton({ title = 'Knowledge graph' }: { title?: string }) {
  const areas: [number, number, number][] = [
    [26, 34, 15], [58, 28, 13], [82, 46, 9], [28, 74, 10], [60, 70, 16],
  ]
  return (
    <div className="kg" aria-busy="true">
      <div className="kg-head">
        <div className="kg-head__title">
          {title && <h1 className="kg-title">{title}</h1>}
          <span className="kg-skel kg-skel--line" style={{ width: 180 }} />
        </div>
      </div>
      <div className="kg-stage kg-skel-stage">
        {areas.map(([x, y, r], i) => (
          <span key={i} className="kg-skel" style={{ left: `${x - r * 0.69}%`, top: `${y - r}%`, width: `${r * 1.38}%`, height: `${r * 2}%` }} />
        ))}
        <span className="kg-skel-note" role="status">
          Loading the map…
        </span>
      </div>
    </div>
  )
}
