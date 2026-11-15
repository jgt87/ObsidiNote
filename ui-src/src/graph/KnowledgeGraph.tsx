// The knowledge graph view for one loaded model: header (source, counts, read-only marker),
// filter chips, search ("/"), Graph or List, and the page dialog.

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type KeyboardEvent, type RefObject } from 'react'
import { archivedHidden, emptyFilter, pruneFilter, visiblePageIds, type GraphFilter } from './filters'
import { FilterButton, FilterSummary } from './FilterPanel'
import { plural } from './format'
import { buildIndex } from './graphIndex'
import { GraphList } from './GraphList'
import { GraphStage, type Active, type Filters } from './GraphStage'
import { focusAfter } from './searchFocus'
import { layoutGraph } from './layout'
import type { GraphModel } from './model'
import { bySource, type GroupBy } from './sourceView'
import { PageDialog, type PageActions } from './PageDialog'
import { ReadOnlyBanner } from '../components/ReadOnlyBanner'
import { readOnlyWhy } from './readOnly'
import { availableTags, byTag } from './tagView'
import { searchPages } from './view'
import { useRetireFlow } from './useRetireFlow'
import { SearchFilters } from '../search/SearchFilters'
import { getSettings, saveSetting } from '../api'
import type { VaultSettings } from '../model/vaultSettings'
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
  const layout = useMemo(() => layoutGraph(model, { aspect }, index), [model, index, aspect])
  // Areas by topic, or by where the pages come from (sourceView.ts); only the map's areas change:
  // the page window, filters, search and List keep the topics.
  const [groupBy, setGroupBy] = useState<GroupBy>('topics')
  const sourceLayout = useMemo(() => {
    if (groupBy !== 'sources') return null
    const m = bySource(model)
    return layoutGraph(m, { aspect }, buildIndex(m))
  }, [groupBy, model, aspect])
  // Areas by hand-set tag (tagView.ts): the third grouping. Which tags make the areas is chosen
  // with the chips under the bar (null = every tag); session state, like the grouping itself (the
  // vault's "opens on" setting knows Topics and Sources only).
  const [tagChoice, setTagChoice] = useState<ReadonlySet<string> | null>(null)
  const groupTags = useMemo(() => availableTags(model), [model])
  const tagLayout = useMemo(() => {
    if (groupBy !== 'tags') return null
    const m = byTag(model, tagChoice)
    return layoutGraph(m, { aspect }, buildIndex(m))
  }, [groupBy, model, aspect, tagChoice])
  const mapLayout = tagLayout ?? sourceLayout ?? layout
  const focus = useMemo(() => (focusIds ?? []).filter((id) => index.pageById.has(id)), [focusIds, index])
  const [filters, setFilters] = useState<Filters>({ links: true, mentions: false, hubsOnly: false })
  // The vault's "older than N days" for link summaries (linkStaleDays): the Filter's stale box.
  const [staleDays, setStaleDays] = useState(90)
  // The map opens with the vault's settings (kept in OneNote, model/vaultSettings.ts) and a change
  // made here is saved there, when this window may change them; otherwise it lasts this session.
  const canSave = useRef(false)
  useEffect(() => {
    let live = true
    getSettings()
      .then((s) => {
        if (!live) return
        canSave.current = s.canChange
        setGroupBy(s.settings.graphView)
        setFilters((f) => ({ ...f, hubsOnly: s.settings.labelsHubsOnly }))
        setStaleDays(s.settings.linkStaleDays)
        if (s.settings.graphShowArchived) setFilterState((f) => ({ ...f, showArchived: true }))
      })
      .catch(() => {}) // the defaults stay; the map works without them
    return () => {
      live = false
    }
  }, [])
  const remember = <K extends 'graphView' | 'labelsHubsOnly'>(key: K, value: VaultSettings[K]) => {
    // Only on the active vault's own map: another vault or a connected notebook is read only.
    if (canSave.current && !model.source.readOnly) saveSetting(key, value).catch(() => {})
  }
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
    if (e.key === 'Enter' && matches?.length) {
      e.preventDefault()
      open(active && matches.includes(active.id) ? active.id : matches[0])
    } else if (e.key === 'Escape' && query) {
      e.preventDefault()
      onQuery('')
    } else if (e.key === 'ArrowDown' && matches?.length) {
      e.preventDefault()
      const i = active ? matches.indexOf(active.id) : -1
      const id = matches[(i + 1) % matches.length]
      setPick(id)
      setActive({ id, via: 'keyboard' })
    } else if (e.key === 'ArrowUp' && matches?.length) {
      e.preventDefault()
      const i = active ? matches.indexOf(active.id) : 0
      const id = matches[(i - 1 + matches.length) % matches.length]
      setPick(id)
      setActive({ id, via: 'keyboard' })
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

  const close = () => {
    const last = dialog?.pageId
    setDialog(null)
    const back = returnTo.current
    // Opened with a click: no keyboard focus on the dot afterwards, so no preview card stays behind
    // (it would only close when the pointer passed over another dot; operator, 2026-11-13).
    if (mode === 'graph' && openedBy.current === 'pointer') {
      setActive(null)
      requestAnimationFrame(() => {
        if (document.activeElement === stageRef.current) stageRef.current?.blur()
        setActive(null)
      })
      return
    }
    // Opened with the keyboard: focus returns to the dot, with that page focused.
    if (mode === 'graph' && last && (!back || back === stageRef.current || back === document.body)) {
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
  const tagOn = (name: string) => !tagChoice || tagChoice.has(name)
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
  return (
    <div className="kg">
      <div className="kg-head">
        <div className="kg-head__title">
          {title && <h1 className="kg-title">{title}</h1>}
          <span className="kg-meta">
            {src.name ? `${src.name} · ` : ''}
            {plural(model.pages.length, 'page')}
            {mode === 'graph' && groupBy === 'tags' ? ', ' : ' in '}
            {mode === 'graph' && groupBy === 'sources' ? plural(mapLayout.areas.length, 'source') : mode === 'graph' && groupBy === 'tags' ? plural(groupTags.length, 'tag') : plural(layout.areas.filter((a) => a.topic).length, 'topic')} · {plural(index.linkCount, 'link')}
            {hiddenArchived > 0 ? ` · ${hiddenArchived} archived hidden` : ''}
          </span>
        </div>
        <div className="kg-tools">
          {mode === 'graph' && (
            <>
              <div className="seg seg--sm" role="group" aria-label="Group the map by">
                <button type="button" className="seg__btn" aria-pressed={groupBy === 'topics'} onClick={() => chooseGroup('topics')}>
                  Topics
                </button>
                <button type="button" className="seg__btn" aria-pressed={groupBy === 'sources'} onClick={() => chooseGroup('sources')}>
                  Sources
                </button>
                <button type="button" className="seg__btn" aria-pressed={groupBy === 'tags'} onClick={() => chooseGroup('tags')}>
                  Tags
                </button>
              </div>
            </>
          )}
          <FilterButton index={index} filter={liveFilter} onChange={setFilter} show={mode === 'graph' ? filters : undefined} onShow={setShow} staleDays={staleDays} />
          <label htmlFor="kg-search" className="kg-sr">
            Search pages and topics
          </label>
          {/* design: the search has its own clear button, shown whenever there is text (operator,
              2026-11-15: the browser's own "x" only shows while the pointer is over the field). */}
          <span className="kg-searchbox">
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
            {query && (
              <button
                type="button"
                className="kg-search__clear"
                aria-label="Clear search"
                title="Clear search"
                onClick={() => {
                  onQuery('')
                  searchRef.current?.focus()
                }}
              >
                <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden="true">
                  <path d="M4.5 4.5l7 7M11.5 4.5l-7 7" />
                </svg>
              </button>
            )}
          </span>
          <span id="kg-search-count" className="kg-sr" aria-live="polite">
            {matches ? plural(matches.length, 'match', 'matches') : ''}
          </span>
          <div className="seg seg--sm" role="group" aria-label="View">
            <button type="button" className="seg__btn" aria-pressed={mode === 'graph'} onClick={() => setMode('graph')}>
              Graph
            </button>
            <button type="button" className="seg__btn" aria-pressed={mode === 'list'} onClick={() => setMode('list')}>
              List
            </button>
          </div>
        </div>
      </div>
      {src.readOnly && (
        <ReadOnlyBanner text={src.readOnlyReason === 'lease' && readOnlyNote ? readOnlyNote : readOnlyWhy(src)} onCheck={src.readOnlyReason === 'lease' ? onCheckAgain : undefined} result={src.readOnlyReason === 'lease' ? checkResult : ''} />
      )}
      <SearchFilters query={query} onQuery={onQuery} />
      {mode === 'graph' && groupBy === 'tags' && (
        // The Tags grouping: which tags make the areas. Every tag is on at first; a chip takes one
        // out or puts it back. Only pages that carry a shown tag are on this map.
        <div className="kg-tagbar" role="group" aria-label="Tags shown as areas">
          {groupTags.length === 0 ? (
            <span className="kg-meta">No page has a tag yet. Add one in a page's window, or tick rows in the List and tag them together.</span>
          ) : (
            <>
              <span className="kg-meta">Areas:</span>
              {groupTags.map((t) => (
                <button key={t.name} type="button" className="btn btn--sm" aria-pressed={tagOn(t.name)} onClick={() => toggleTag(t.name)}>
                  <svg className="toggle-mark" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                    <rect x="1" y="1" width="10" height="10" rx="2" />
                    {tagOn(t.name) && <path d="m3.4 6.2 1.9 1.9 3.3-3.8" />}
                  </svg>
                  {t.name} <span className="kg-meta num">{t.count}</span>
                </button>
              ))}
              {tagChoice && (
                <button type="button" className="kg-linkbtn" onClick={() => setTagChoice(null)}>
                  All tags
                </button>
              )}
              <span className="kg-meta">
                {plural(mapLayout.dots.length, 'tagged page')} of {plural(model.pages.length, 'page')} shown
              </span>
            </>
          )}
        </div>
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
