// The knowledge graph view for one loaded model: header (source, counts, read-only marker),
// filter chips, search ("/"), Graph or List, and the page dialog.

import { useLayoutEffect, useMemo, useRef, useState, type RefObject } from 'react'
import { FilterButton, FilterSummary } from './FilterPanel'
import { buildIndex } from './graphIndex'
import { GraphHeading, GraphTools, SourceBanner, TagBar } from './GraphHeader'
import { GraphList } from './GraphList'
import { GraphStage, type Active } from './GraphStage'
import { areaCount, areaWordOf } from './graphViewModel'
import type { GraphModel } from './model'
import { PageDialog, type PageActions } from './PageDialog'
import { useFindRequest, useGraphSearch, usePageDialog, usePageRetire, useSearchKeys } from './useGraphInteraction'
import { useGraphFilter, useMapChoices, useMapLayouts, useTagGrouping, useVisiblePages } from './useGraphView'
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
  // Areas by topic, by where the pages come from, or by hand-set tag (useMapLayouts); the grouping
  // and what the map shows (useMapChoices); which tags make the areas (useTagGrouping).
  const focus = useMemo(() => (focusIds ?? []).filter((id) => index.pageById.has(id)), [focusIds, index])
  const [active, setActive] = useState<Active | null>(() => (focus.length ? { id: focus[0], via: 'keyboard' } : null))
  const { filter, setFilterState, setFilter, focusOn } = useGraphFilter(index, setActive)
  const choices = useMapChoices(model.source.readOnly, setFilterState)
  const { groupBy, filters } = choices
  const tags = useTagGrouping(model)
  const { layout, sourceLayout, tagLayout, mapLayout } = useMapLayouts(model, index, aspect, groupBy, tags.tagChoice)

  // The page window, the search box and its keys, and a quick-switcher request (useGraphInteraction.ts).
  const page = usePageDialog(stageRef, mode, setActive)
  const search = useGraphSearch(index, setActive, !!page.dialog)
  const { liveFilter, shown, allShown, hiddenArchived, matches, listMatches } = useVisiblePages(index, filter, search.query, focus)
  const { onStageActive, onSearchKey } = useSearchKeys({ ...search, matches, active, setActive, open: page.open })
  useFindRequest(request, model, { index, onQuery: search.onQuery, showList: () => setMode('list'), setActive, openRequested: page.openRequested, onRequestDone })

  // A tag picked in the page window or the List: the Tags grouping with that tag alone.
  const showTag = (tag: string) => {
    choices.setGroupBy('tags')
    tags.setTagChoice(new Set([tag]))
    setMode('graph')
    search.onQuery('')
  }
  // Archive / Restore / Delete: the outcome shows in the page window while it is open, else above
  // the map or the List.
  const { dialog } = page
  const { retire, retirePages } = usePageRetire(actions.onRetire, page)

  const count = areaCount({ mode, groupBy, sources: mapLayout.areas.length, tags: tags.groupTags.length, topics: layout.areas.filter((a) => a.topic).length })
  return (
    <div className="kg">
      <div className="kg-head">
        <GraphHeading title={title} source={model.source.name} pages={model.pages.length} areas={count} links={index.linkCount} hiddenArchived={hiddenArchived} />
        <GraphTools
          mode={mode}
          onMode={setMode}
          groupBy={groupBy}
          onGroup={choices.chooseGroup}
          filter={<FilterButton index={index} filter={liveFilter} onChange={setFilter} show={mode === 'graph' ? filters : undefined} onShow={choices.setShow} staleDays={choices.staleDays} />}
          query={search.query}
          onQuery={search.onQuery}
          onSearchKey={onSearchKey}
          searchRef={search.searchRef}
          matches={matches}
        />
      </div>
      <SourceBanner source={model.source} appNote={readOnlyNote} checkResult={checkResult} onCheckAgain={onCheckAgain} />
      <SearchFilters query={search.query} onQuery={search.onQuery} />
      {mode === 'graph' && groupBy === 'tags' && (
        <TagBar tags={tags.groupTags} choice={tags.tagChoice} onToggle={tags.toggleTag} onAll={() => tags.setTagChoice(null)} shownPages={mapLayout.dots.length} allPages={model.pages.length} />
      )}

      <FilterSummary index={index} filter={liveFilter} onChange={setFilter} shown={shown.size} />
      {!dialog && retire.notice}

      {mode === 'graph' ? (
        <GraphStage
          index={index}
          layout={mapLayout}
          areaWord={areaWordOf({ tags: !!tagLayout, sources: !!sourceLayout })}
          filters={filters}
          shown={allShown ? null : shown}
          matches={matches}
          active={active}
          onActive={onStageActive}
          onOpen={page.open}
          onFocusPage={focusOn}
          stageRef={stageRef}
        />
      ) : (
        <GraphList index={index} layout={layout} matches={listMatches} onOpen={page.open} onTagPages={actions.onTagPages} onPickTag={showTag} onRetirePages={retirePages} onUpdateLink={actions.onUpdateLink} />
      )}

      {dialog && (
        <PageDialog
          key="dialog"
          index={index}
          pageId={dialog.pageId}
          anchorId={dialog.anchorId}
          onNavigate={page.navigate}
          onClose={page.close}
          onFocusPage={focusOn}
          onPickTag={(t) => {
            page.close()
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
