// The knowledge graph's map layouts per grouping, the vault's map settings, which pages are shown
// and the Tags grouping's choice, and the map's folded model with its ids. Used by KnowledgeGraph.tsx.
import { useCallback, useEffect, useMemo, useRef, useState, type Dispatch, type SetStateAction } from 'react'
import { getSettings, saveSetting } from '../api'
import type { VaultSettings } from '../model/vaultSettings'
import { archivedHidden, emptyFilter, pruneFilter, visiblePageIds, type GraphFilter } from './filters'
import { buildIndex, type GraphIndex } from './graphIndex'
import type { Active, Filters } from './GraphStage'
import { areaWordOf, toggleTagChoice } from './graphViewModel'
import { layoutGraph } from './layout'
import type { GraphModel } from './model'
import { foldSeries, mapMatchIds, mapShownIds, onMapDot } from './seriesFold'
import { bySource, type GroupBy } from './sourceView'
import { availableTags, byTag } from './tagView'
import { searchPages } from './view'

/**
 * Which pages are shown and which the search finds. Filters (filters.ts) hide pages; the search then
 * only finds visible ones. The List gets the same set through `listMatches`, so map and List always
 * show the same pages. Without a search, the pages to show first (`focus`) are the results.
 */
export function useVisiblePages(index: GraphIndex, filter: GraphFilter, query: string, focus: string[]) {
  const liveFilter = useMemo(() => pruneFilter(index, filter), [index, filter])
  const shown = useMemo(() => visiblePageIds(index, liveFilter), [index, liveFilter])
  const allShown = shown.size === index.model.pages.length
  const hiddenArchived = archivedHidden(index, liveFilter)
  const searchMatches = useMemo(() => (query.trim() ? searchPages(index, query) : focus.length ? focus : null), [index, query, focus])
  const matches = useMemo(() => (searchMatches && !allShown ? searchMatches.filter((id) => shown.has(id)) : searchMatches), [searchMatches, shown, allShown])
  const listMatches = useMemo(() => matches ?? (allShown ? null : [...shown]), [matches, shown, allShown])
  return { liveFilter, shown, allShown, hiddenArchived, matches, listMatches }
}

/**
 * How the map is drawn: the grouping (Topics, Sources or Tags) and what the map shows (links,
 * mentions, names of hubs only). Both start from the vault's settings when the graph opens
 * (useGraphSettings), which may also show archived pages through `setFilter`; the person's later
 * choices of Topics/Sources and hubs-only are saved back to the vault (Tags is session state only).
 */
export function useMapChoices(readOnly: boolean, setFilter: (f: (prev: GraphFilter) => GraphFilter) => void) {
  const [groupBy, setGroupBy] = useState<GroupBy>('topics')
  const [filters, setFilters] = useState<Filters>({ links: true, mentions: false, hubsOnly: false })
  const { staleDays, remember } = useGraphSettings(readOnly, (s) => {
    setGroupBy(s.graphView)
    setFilters((f) => ({ ...f, hubsOnly: s.labelsHubsOnly }))
    if (s.graphShowArchived) setFilter((f) => ({ ...f, showArchived: true }))
  })
  const setShow = (key: keyof Filters, next: boolean) => {
    setFilters((f) => ({ ...f, [key]: next }))
    if (key === 'hubsOnly') remember('labelsHubsOnly', next)
  }
  const chooseGroup = (g: GroupBy) => {
    setGroupBy(g)
    if (g !== 'tags') remember('graphView', g)
  }
  return { groupBy, setGroupBy, filters, staleDays, setShow, chooseGroup }
}

/** The filter's choices (filters.ts). Applying a filter that hides the focused page drops that
 *  focus; "focus on this page" keeps the link steps chosen before (1 by default). */
export function useGraphFilter(index: GraphIndex, setActive: Dispatch<SetStateAction<Active | null>>) {
  const [filter, setFilterState] = useState<GraphFilter>(emptyFilter)
  const setFilter = (f: GraphFilter) => {
    setFilterState(f)
    const next = visiblePageIds(index, f)
    setActive((a) => (a && !next.has(a.id) ? null : a))
  }
  const focusOn = useCallback((id: string) => {
    setFilterState((f) => ({ ...f, focus: { id, depth: f.focus?.depth ?? 1 } }))
    setActive({ id, via: 'keyboard' })
  }, [setActive])
  return { filter, setFilterState, setFilter, focusOn }
}

/** The tags the Tags grouping can show, and which of them it shows (null = every tag; session state,
 *  like the grouping: the vault's "opens on" setting knows Topics and Sources only). */
export function useTagGrouping(model: GraphModel) {
  const [tagChoice, setTagChoice] = useState<ReadonlySet<string> | null>(null)
  const groupTags = useMemo(() => availableTags(model), [model])
  const toggleTag = (name: string) => setTagChoice(toggleTagChoice(tagChoice, groupTags.map((t) => t.name), name))
  return { groupTags, tagChoice, setTagChoice, toggleTag }
}

/**
 * The layouts of the map: by topic always (the List and the counts use it), and by where the pages
 * come from (sourceView.ts) or by hand-set tag (tagView.ts) only while that grouping is chosen.
 * Only the map's areas change: the page window, filters, search and List keep the topics.
 */
export function useMapLayouts(model: GraphModel, index: GraphIndex, aspect: number, groupBy: GroupBy, tagChoice: ReadonlySet<string> | null) {
  const layout = useMemo(() => layoutGraph(model, { aspect }, index), [model, index, aspect])
  const sourceLayout = useMemo(() => {
    if (groupBy !== 'sources') return null
    const m = bySource(model)
    return layoutGraph(m, { aspect }, buildIndex(m))
  }, [groupBy, model, aspect])
  const tagLayout = useMemo(() => {
    if (groupBy !== 'tags') return null
    const m = byTag(model, tagChoice)
    return layoutGraph(m, { aspect }, buildIndex(m))
  }, [groupBy, model, aspect, tagChoice])
  return { layout, sourceLayout, tagLayout, mapLayout: tagLayout ?? sourceLayout ?? layout }
}

/**
 * What the map draws: one dot per meeting series (seriesFold.ts, D-077) laid out by the chosen
 * grouping. `layout` is the topic layout of the WHOLE model, for the List and the header's counts,
 * which keep every meeting; `mapLayout` is the folded map's. `dotOf` is null when nothing is folded.
 */
export function useMapModel(model: GraphModel, index: GraphIndex, aspect: number, groupBy: GroupBy, tagChoice: ReadonlySet<string> | null) {
  const fold = useMemo(() => foldSeries(model), [model])
  const mapModel = fold.model
  const mapIndex = useMemo(() => (mapModel === model ? index : buildIndex(mapModel)), [mapModel, model, index])
  const { layout: mapTopicLayout, sourceLayout, tagLayout, mapLayout } = useMapLayouts(mapModel, mapIndex, aspect, groupBy, tagChoice)
  const layout = useMemo(() => (mapModel === model ? mapTopicLayout : layoutGraph(model, { aspect }, index)), [mapModel, model, mapTopicLayout, aspect, index])
  const dotOf = fold.dotOf.size ? fold.dotOf : null
  return { mapModel, mapIndex, layout, mapLayout, areaWord: areaWordOf({ tags: !!tagLayout, sources: !!sourceLayout }), dotOf }
}

/** The visible pages, the search's matches and the focused page as dots of the folded map. */
export function useMapIds(dotOf: Map<string, string> | null, v: { shown: Set<string>; allShown: boolean; matches: string[] | null; active: Active | null }) {
  const { shown, allShown, matches } = v
  const mapShown = useMemo(() => mapShownIds(shown, allShown, dotOf), [allShown, shown, dotOf])
  const mapMatches = useMemo(() => mapMatchIds(matches, dotOf), [matches, dotOf])
  return { shown: mapShown, matches: mapMatches, active: onMapDot(v.active, dotOf) }
}

/**
 * The map opens with the vault's settings (kept in OneNote, model/vaultSettings.ts): `apply` gets
 * them once. A change made on the map is saved there with `remember`, when this window may change
 * them and the map is the active vault's own (another vault or a connected notebook is read only);
 * otherwise it lasts this session. `staleDays`: the vault's "older than N days" for link summaries
 * (linkStaleDays), the Filter's stale box.
 */
export function useGraphSettings(readOnly: boolean, apply: (s: VaultSettings) => void) {
  const [staleDays, setStaleDays] = useState(90)
  const canSave = useRef(false)
  useEffect(() => {
    let live = true
    getSettings()
      .then((s) => {
        if (!live) return
        canSave.current = s.canChange
        apply(s.settings)
        setStaleDays(s.settings.linkStaleDays)
      })
      .catch(() => {}) // the defaults stay; the map works without them
    return () => {
      live = false
    }
    // Once per view, as before: `apply` only calls state setters.
  }, [])
  const remember = <K extends 'graphView' | 'labelsHubsOnly'>(key: K, value: VaultSettings[K]) => {
    if (canSave.current && !readOnly) saveSetting(key, value).catch(() => {})
  }
  return { staleDays, remember }
}
