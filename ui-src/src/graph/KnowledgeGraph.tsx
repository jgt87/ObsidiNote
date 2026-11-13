// The knowledge graph view for one loaded model: header (source, counts, read-only marker),
// filter chips, search ("/"), Graph or List, and the page dialog.

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type KeyboardEvent, type RefObject } from 'react'
import { archivedHidden, emptyFilter, pruneFilter, visiblePageIds, type GraphFilter } from './filters'
import { FilterButton, FilterSummary } from './FilterPanel'
import { plural } from './format'
import { buildIndex } from './graphIndex'
import { GraphList } from './GraphList'
import { GraphStage, type Active, type Filters } from './GraphStage'
import { layoutGraph } from './layout'
import type { GraphModel } from './model'
import { LockIcon, PageDialog, type PageActions } from './PageDialog'
import { searchPages } from './view'
import { SearchFilters } from '../search/SearchFilters'
import type { FindRequest } from '../search/switcherModel'
import './graph.css'

export interface KnowledgeGraphProps extends PageActions {
  model: GraphModel
  /** Heading; the app shell may already show one, then pass ''. */
  title?: string
  /** Start in the list view (the accessible fallback). */
  initialMode?: 'graph' | 'list'
  /** Pages to show first ("Show on map" from an Ask answer): highlighted, the first one focused. */
  focusIds?: string[]
  /** A quick-switcher pick (open a page, or set the search); applied once, then onRequestDone. */
  request?: FindRequest | null
  onRequestDone?: () => void
}

/** Width / height of the stage, in steps of 0.1 (the layout only reruns when the shape really changes). */
function useStageAspect(stageRef: RefObject<HTMLDivElement | null>, mode: string): number {
  const [aspect, setAspect] = useState(() => roundAspect(Math.max(1, window.innerWidth - 300), Math.max(1, window.innerHeight - 112)))
  useLayoutEffect(() => {
    const el = stageRef.current
    if (!el) return
    const measure = () => {
      if (el.clientWidth > 0 && el.clientHeight > 0) setAspect(roundAspect(el.clientWidth, el.clientHeight))
    }
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    return () => ro.disconnect()
  }, [stageRef, mode]) // the stage only exists in graph mode
  return aspect
}

function roundAspect(w: number, h: number): number {
  return Math.min(3, Math.max(0.6, Math.round((w / h) * 10) / 10))
}

export function KnowledgeGraph({ model, title = 'Knowledge graph', initialMode = 'graph', focusIds, request, onRequestDone, ...actions }: KnowledgeGraphProps) {
  const index = useMemo(() => buildIndex(model), [model])
  const [mode, setMode] = useState<'graph' | 'list'>(initialMode)
  const stageRef = useRef<HTMLDivElement>(null)
  const aspect = useStageAspect(stageRef, mode)
  const layout = useMemo(() => layoutGraph(model, { aspect }, index), [model, index, aspect])
  const focus = useMemo(() => (focusIds ?? []).filter((id) => index.pageById.has(id)), [focusIds, index])
  const [filters, setFilters] = useState<Filters>({ links: true, mentions: false, hubsOnly: false })
  const [query, setQuery] = useState('')
  const [active, setActive] = useState<Active | null>(() => (focus.length ? { id: focus[0], via: 'keyboard' } : null))
  const [dialog, setDialog] = useState<{ pageId: string; anchorId: string } | null>(null)
  const searchRef = useRef<HTMLInputElement>(null)
  const returnTo = useRef<HTMLElement | null>(null)

  // Filters (filters.ts) hide pages; the search then only finds visible ones. The list gets the
  // same set through `matches`, so map and list always show the same pages.
  const [filter, setFilterState] = useState<GraphFilter>(emptyFilter)
  const liveFilter = useMemo(() => pruneFilter(index, filter), [index, filter])
  const shown = useMemo(() => visiblePageIds(index, liveFilter), [index, liveFilter])
  const allShown = shown.size === model.pages.length
  const hiddenArchived = archivedHidden(index, liveFilter)
  const searchMatches = useMemo(() => (query.trim() ? searchPages(index, query) : focus.length ? focus : null), [index, query, focus])
  const matches = useMemo(() => (searchMatches && !allShown ? searchMatches.filter((id) => shown.has(id)) : searchMatches), [searchMatches, shown, allShown])
  const listMatches = useMemo(() => matches ?? (allShown ? null : [...shown]), [matches, shown, allShown])
  const setFilter = (f: GraphFilter) => {
    setFilterState(f)
    const next = visiblePageIds(index, f)
    setActive((a) => (a && !next.has(a.id) ? null : a))
  }
  const focusOn = useCallback((id: string) => {
    setFilterState((f) => ({ ...f, focus: { id, depth: f.focus?.depth ?? 1 } }))
    setActive({ id, via: 'keyboard' })
  }, [])

  // "/" focuses the search, anywhere on the page, unless the user is typing or a dialog is open.
  useEffect(() => {
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key !== '/' || e.ctrlKey || e.metaKey || e.altKey || dialog) return
      const t = e.target as HTMLElement | null
      if (t && (t.closest('input, textarea, select, [contenteditable="true"]') || t.isContentEditable)) return
      e.preventDefault()
      searchRef.current?.focus()
      searchRef.current?.select()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [dialog])

  const onQuery = (q: string) => {
    setQuery(q)
    const hits = q.trim() ? searchPages(index, q) : []
    setActive(hits.length ? { id: hits[0], via: 'keyboard' } : null)
  }
  const onSearchKey = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && matches?.length) {
      e.preventDefault()
      open(active && matches.includes(active.id) ? active.id : matches[0])
    } else if (e.key === 'Escape' && query) {
      e.preventDefault()
      onQuery('')
    } else if (e.key === 'ArrowDown' && matches?.length) {
      e.preventDefault()
      const i = active ? matches.indexOf(active.id) : -1
      setActive({ id: matches[(i + 1) % matches.length], via: 'keyboard' })
    } else if (e.key === 'ArrowUp' && matches?.length) {
      e.preventDefault()
      const i = active ? matches.indexOf(active.id) : 0
      setActive({ id: matches[(i - 1 + matches.length) % matches.length], via: 'keyboard' })
    }
  }

  const open = useCallback((id: string) => {
    returnTo.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    setDialog({ pageId: id, anchorId: id })
  }, [])

  // Quick switcher: only for this model's source (a graph still showing another source waits).
  useEffect(() => {
    if (!request || request.sourceId !== model.source.id) return
    onQuery(request.query ?? '')
    if (request.pageId && index.pageById.has(request.pageId)) {
      setActive({ id: request.pageId, via: 'keyboard' })
      returnTo.current = null
      setDialog({ pageId: request.pageId, anchorId: request.pageId })
    }
    onRequestDone?.()
  }, [request, model]) // once per request; again when the asked source's model arrives

  const close = () => {
    const last = dialog?.pageId
    setDialog(null)
    const back = returnTo.current
    // Focus returns to the dot: the map gets focus with that page focused.
    if (mode === 'graph' && last && (!back || back === stageRef.current || back === document.body)) {
      setActive({ id: last, via: 'keyboard' })
      requestAnimationFrame(() => stageRef.current?.focus())
    } else {
      requestAnimationFrame(() => back?.focus())
    }
  }

  const chip = (key: keyof Filters, label: string) => (
    <button type="button" className="btn btn--sm" aria-pressed={filters[key]} onClick={() => setFilters((f) => ({ ...f, [key]: !f[key] }))}>
      {label}
    </button>
  )

  const src = model.source
  return (
    <div className="kg">
      <div className="kg-head">
        <div className="kg-head__title">
          {title && <h1 className="kg-title">{title}</h1>}
          <span className="kg-meta">
            {src.name ? `${src.name} · ` : ''}
            {plural(model.pages.length, 'page')} in {plural(layout.areas.filter((a) => a.topic).length, 'topic')} · {plural(index.linkCount, 'link')}
            {hiddenArchived > 0 ? ` · ${hiddenArchived} archived hidden` : ''}
          </span>
          {src.readOnly && (
            <span className="kg-readonly" title={src.kind === 'notebook' ? 'Connected notebook: ObsidiNote never writes here' : 'Not the active vault: ObsidiNote never writes here'}>
              <LockIcon /> read only
            </span>
          )}
        </div>
        <div className="kg-tools">
          {mode === 'graph' && (
            <>
              {chip('links', 'Links')}
              {chip('mentions', 'Mentions, not linked')}
              {chip('hubsOnly', 'Labels: hubs only')}
            </>
          )}
          <FilterButton index={index} filter={liveFilter} onChange={setFilter} />
          <label htmlFor="kg-search" className="kg-sr">
            Search pages and topics
          </label>
          <input
            id="kg-search"
            ref={searchRef}
            className="field kg-search"
            type="search"
            placeholder="Search pages and topics  /"
            value={query}
            onChange={(e) => onQuery(e.target.value)}
            onKeyDown={onSearchKey}
            aria-describedby="kg-search-count"
          />
          <span id="kg-search-count" className="kg-sr" aria-live="polite">
            {matches ? plural(matches.length, 'match', 'matches') : ''}
          </span>
          <div className="kg-seg" role="group" aria-label="View">
            <button type="button" className="btn btn--sm" aria-pressed={mode === 'graph'} onClick={() => setMode('graph')}>
              Graph
            </button>
            <button type="button" className="btn btn--sm" aria-pressed={mode === 'list'} onClick={() => setMode('list')}>
              List
            </button>
          </div>
        </div>
      </div>
      <SearchFilters query={query} onQuery={onQuery} />

      <FilterSummary index={index} filter={liveFilter} onChange={setFilter} shown={shown.size} />

      {mode === 'graph' ? (
        <GraphStage
          index={index}
          layout={layout}
          filters={filters}
          shown={allShown ? null : shown}
          matches={matches}
          active={active}
          onActive={setActive}
          onOpen={open}
          onFocusPage={focusOn}
          stageRef={stageRef}
        />
      ) : (
        <GraphList index={index} layout={layout} matches={listMatches} onOpen={open} />
      )}

      {dialog && (
        <PageDialog
          key="dialog"
          index={index}
          pageId={dialog.pageId}
          anchorId={dialog.anchorId}
          onNavigate={(id) => setDialog((d) => (d ? { ...d, pageId: id } : d))}
          onClose={close}
          onFocusPage={focusOn}
          {...actions}
        />
      )}
    </div>
  )
}
