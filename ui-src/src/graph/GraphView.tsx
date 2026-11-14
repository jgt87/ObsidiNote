// The route-level view: loads the model, then shows the graph, or loading / empty / error.
// The merge renders <GraphView load={() => fetchGraph({ vault })} ... /> for the Map nav entry.

import { useCallback, useEffect, useMemo, useState } from 'react'
import { addLink, editPage } from './graphApi'
import { KnowledgeGraph, type KnowledgeGraphProps } from './KnowledgeGraph'
import { mentionBetween, withMentions } from './mentions'
import type { GraphModel } from './model'
import type { PageActions } from './PageDialog'
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

export function GraphView({ load, sourceKey, onAdd, onLinkMention, onEditPage, ...rest }: GraphViewProps) {
  const [state, setState] = useState<State>({ status: 'loading' })
  const [attempt, setAttempt] = useState(0)
  const loaded = state.status === 'ready' ? state.model : null
  // Mentions, not linked: found here from titles, aliases and summaries (the server sends links only).
  const model = useMemo(() => (loaded ? withMentions(loaded) : null), [loaded])

  // After "Link it": read the model again without the loading state, so the map and the open
  // dialog stay and the mention turns into a link in place.
  const refresh = useCallback(async () => {
    const m = await load(new AbortController().signal)
    setState({ status: 'ready', model: m })
  }, [load])

  const writable = !!model && model.source.kind === 'vault' && !model.source.readOnly
  const linkMention = useMemo<PageActions['onLinkMention']>(() => {
    if (onLinkMention) return onLinkMention
    if (!model || !writable) return undefined
    return async (a, b) => {
      // The link goes from the page that mentions to the page it names.
      const m = mentionBetween(model, a.id, b.id)
      const from = m ? m.from : a.id
      const to = m ? m.to : b.id
      await addLink({ from, to, vault: model.source.id })
      await refresh().catch(() => {
        throw new Error('The link was added, but the map could not be read again. Reload the map to see it.')
      })
    }
  }, [onLinkMention, model, writable, refresh])

  // Edit in the page window: save, then read the map again in place (the dialog stays open).
  const editPageFn = useMemo<PageActions['onEditPage']>(() => {
    if (onEditPage) return onEditPage
    if (!writable) return undefined
    return async (req) => {
      await editPage(req)
      await refresh().catch(() => {
        throw new Error('The page was saved, but the map could not be read again. Reload the map to see it.')
      })
    }
  }, [onEditPage, writable, refresh])

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
  if (!model || model.pages.length === 0) {
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
  return <KnowledgeGraph model={model} onLinkMention={linkMention} onEditPage={editPageFn} {...rest} />
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
