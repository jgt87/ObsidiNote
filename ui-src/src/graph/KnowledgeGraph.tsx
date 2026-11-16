// The knowledge graph view for one loaded model: header (source, counts, read-only marker),
// filter chips, search ("/"), Graph or List, and the page dialog.

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type KeyboardEvent, type RefObject } from 'react'
import { archivedHidden, emptyFilter, pruneFilter, visiblePageIds, type GraphFilter } from './filters'
import { FilterButton, FilterSummary } from './FilterPanel'
import { plural } from './format'
import { buildIndex } from './graphIndex'
import { GraphTools, TagBar } from './GraphHeader'
import { GraphList } from './GraphList'
import { GraphStage, type Active, type Filters } from './GraphStage'
import { areaCount, closeFocus, isSearchSlash, searchKeyAction } from './graphViewModel'
import { focusAfter } from './searchFocus'
import type { GraphModel } from './model'
import type { GroupBy } from './sourceView'
import { PageDialog, type PageActions } from './PageDialog'
import { ReadOnlyBanner } from '../components/ReadOnlyBanner'
import { readOnlyWhy } from './readOnly'
import { availableTags } from './tagView'
import { useGraphSettings, useMapLayouts } from './useGraphView'
import { searchPages } from './view'
import { useRetireFlow } from './useRetireFlow'
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
  /** Why the ACTIVE vault is read only in this window, as the app's status has it (who holds it,
   *  since when); shown instead of the general sentence when this graph is that vault's. */
  readOnlyNote?: string
  /** "Check again" on the read-only banner, and what it found. */
  onCheckAgain?: () => Promise<void> | void
  checkResult?: string
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

export function KnowledgeGraph({ model, title = 'Knowledge graph', initialMode = 'graph', focusIds, request, onRequestDone, readOnlyNote, onCheckAgain, checkResult = '', ...actions }: KnowledgeGraphProps) {
  const index = useMemo(() => buildIndex(model), [model])
  const [mode, setMode] = useState<'graph' | 'list'>(initialMode)
  const stageRef = useRef<HTMLDivElement>(null)
  const aspect = useStageAspect(stageRef, mode)
  // Areas by topic, by where the pages come from, or by hand-set tag (useMapLayouts). Which tags make
  // the areas is chosen with the chips under the bar (null = every tag); session state, like the
  // grouping itself (the vault's "opens on" setting knows Topics and Sources only).
  const [groupBy, setGroupBy] = useState<GroupBy>('topics')
  const [tagChoice, setTagChoice] = useState<ReadonlySet<string> | null>(null)
  const groupTags = useMemo(() => availableTags(model), [model])
  const { layout, sourceLayout, tagLayout, mapLayout } = useMapLayouts(model, index, aspect, groupBy, tagChoice)
  const focus = useMemo(() => (focusIds ?? []).filter((id) => index.pageById.has(id)), [focusIds, index])
  const [filters, setFilters] = useState<Filters>({ links: true, mentions: false, hubsOnly: false })
  const { staleDays, remember } = useGraphSettings(model.source.readOnly, (s) => {
    setGroupBy(s.graphView)
    setFilters((f) => ({ ...f, hubsOnly: s.labelsHubsOnly }))
    if (s.graphShowArchived) setFilterState((f) => ({ ...f, showArchived: true }))
  })
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
      if (!isSearchSlash(e, e.target as HTMLElement | null, !!dialog)) return
      e.preventDefault()
      searchRef.current?.focus()
      searchRef.current?.select()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [dialog])

  // The result the search box has chosen (the first hit, or the one stepped to with the arrows): the
  // map's focus goes back to it when the pointer leaves a dot, until the search is cleared
  // (searchFocus.ts).
  const [pick, setPick] = useState<string | null>(null)
  const onQuery = (q: string) => {
    setQuery(q)
    const hits = q.trim() ? searchPages(index, q) : []
    setPick(hits[0] ?? null)
    setActive(hits.length ? { id: hits[0], via: 'keyboard' } : null)
  }
  const onStageActive = useCallback(
    (next: Active | null) => setActive(focusAfter(next, query.trim() ? matches : null, pick)),
    [query, matches, pick],
  )
  const onSearchKey = (e: KeyboardEvent<HTMLInputElement>) => {
    const a = searchKeyAction(e.key, matches, active?.id ?? null, query)
    if (!a) return
    e.preventDefault()
    if (a.kind === 'open') open(a.id)
    else if (a.kind === 'clear') onQuery('')
    else {
      setPick(a.id)
      setActive({ id: a.id, via: 'keyboard' })
    }
  }

  const openedBy = useRef<'pointer' | 'keyboard'>('keyboard')
  const open = useCallback((id: string, via: 'pointer' | 'keyboard' = 'keyboard') => {
    openedBy.current = via
    returnTo.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    setDialog({ pageId: id, anchorId: id })
  }, [])

  // Quick switcher: only for this model's source (a graph still showing another source waits).
  useEffect(() => {
    if (!request || request.sourceId !== model.source.id) return
    onQuery(request.query ?? '')
    if (request.list) setMode('list')
    if (request.pageId && index.pageById.has(request.pageId)) {
      setActive({ id: request.pageId, via: 'keyboard' })
      returnTo.current = null
      setDialog({ pageId: request.pageId, anchorId: request.pageId })
    }
    onRequestDone?.()
  }, [request, model]) // once per request; again when the asked source's model arrives

  // Where focus goes when the page window closes (graphViewModel.ts closeFocus).
  const close = () => {
    const last = dialog?.pageId
    setDialog(null)
    const back = returnTo.current
    const to = closeFocus({ mode, openedBy: openedBy.current, last, back, stage: stageRef.current, body: document.body })
    if (to === 'clear') {
      setActive(null)
      requestAnimationFrame(() => {
        if (document.activeElement === stageRef.current) stageRef.current?.blur()
        setActive(null)
      })
    } else if (to === 'stage' && last) {
      setActive({ id: last, via: 'keyboard' })
      requestAnimationFrame(() => stageRef.current?.focus())
    } else {
      requestAnimationFrame(() => back?.focus())
    }
  }

  const setShow = (key: keyof Filters, next: boolean) => {
    setFilters((f) => ({ ...f, [key]: next }))
    if (key === 'hubsOnly') remember('labelsHubsOnly', next)
  }
  // A tag picked in the page window or the List: the Tags grouping with that tag alone.
  const showTag = (tag: string) => {
    setGroupBy('tags')
    setTagChoice(new Set([tag]))
    setMode('graph')
    onQuery('')
  }
  const chooseGroup = (g: GroupBy) => {
    setGroupBy(g)
    if (g !== 'tags') remember('graphView', g)
  }
  // Archive / Restore / Delete (useRetireFlow): a deleted page's window closes; the outcome shows
  // in the page window while it is open, else above the map or the List.
  const retire = useRetireFlow(actions.onRetire, (r) => {
    if (r.action === 'delete' && dialog && r.done.some((d) => d.id === dialog.pageId)) setDialog(null)
  })
  const retirePages = actions.onRetire ? retire.start : undefined

  const toggleTag = (name: string) => {
    const next = new Set(tagChoice ?? groupTags.map((t) => t.name))
    if (next.has(name)) next.delete(name)
    else next.add(name)
    setTagChoice(next.size === groupTags.length ? null : next)
  }

  const src = model.source
  const count = areaCount({ mode, groupBy, sources: mapLayout.areas.length, tags: groupTags.length, topics: layout.areas.filter((a) => a.topic).length })
  return (
    <div className="kg">
      <div className="kg-head">
        <div className="kg-head__title">
          {title && <h1 className="kg-title">{title}</h1>}
          <span className="kg-meta">
            {src.name ? `${src.name} · ` : ''}
            {plural(model.pages.length, 'page')}
            {count.joiner}
            {count.areas} · {plural(index.linkCount, 'link')}
            {hiddenArchived > 0 ? ` · ${hiddenArchived} archived hidden` : ''}
          </span>
        </div>
        <GraphTools
          mode={mode}
          onMode={setMode}
          groupBy={groupBy}
          onGroup={chooseGroup}
          filter={<FilterButton index={index} filter={liveFilter} onChange={setFilter} show={mode === 'graph' ? filters : undefined} onShow={setShow} staleDays={staleDays} />}
          query={query}
          onQuery={onQuery}
          onSearchKey={onSearchKey}
          searchRef={searchRef}
          matches={matches}
        />
      </div>
      {src.readOnly && (
        <ReadOnlyBanner text={src.readOnlyReason === 'lease' && readOnlyNote ? readOnlyNote : readOnlyWhy(src)} onCheck={src.readOnlyReason === 'lease' ? onCheckAgain : undefined} result={src.readOnlyReason === 'lease' ? checkResult : ''} />
      )}
      <SearchFilters query={query} onQuery={onQuery} />
      {mode === 'graph' && groupBy === 'tags' && (
        <TagBar tags={groupTags} choice={tagChoice} onToggle={toggleTag} onAll={() => setTagChoice(null)} shownPages={mapLayout.dots.length} allPages={model.pages.length} />
      )}

      <FilterSummary index={index} filter={liveFilter} onChange={setFilter} shown={shown.size} />
      {!dialog && retire.notice}

      {mode === 'graph' ? (
        <GraphStage
          index={index}
          layout={mapLayout}
          areaWord={tagLayout ? 'tag' : sourceLayout ? 'source' : 'topic'}
          filters={filters}
          shown={allShown ? null : shown}
          matches={matches}
          active={active}
          onActive={onStageActive}
          onOpen={open}
          onFocusPage={focusOn}
          stageRef={stageRef}
        />
      ) : (
        <GraphList index={index} layout={layout} matches={listMatches} onOpen={open} onTagPages={actions.onTagPages} onPickTag={showTag} onRetirePages={retirePages} onUpdateLink={actions.onUpdateLink} />
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
          onPickTag={(t) => {
            close()
            showTag(t)
          }}
          {...actions}
          onRetirePages={retirePages}
          notice={retire.notice}
        />
      )}
      {retire.dialog}
    </div>
  )
}
