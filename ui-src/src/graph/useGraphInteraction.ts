// The knowledge graph's page window, search box and quick-switcher request (KnowledgeGraph.tsx).
// What a key does and where focus goes are decided in graphViewModel.ts; here they are applied.
import { useCallback, useEffect, useRef, useState, type KeyboardEvent, type RefObject } from 'react'
import type { Active } from './GraphStage'
import type { GraphIndex } from './graphIndex'
import { closeFocus, isSearchSlash, searchKeyAction } from './graphViewModel'
import type { GraphModel } from './model'
import type { PageActions } from './PageDialog'
import { focusAfter } from './searchFocus'
import { useRetireFlow } from './useRetireFlow'
import { searchPages } from './view'
import type { FindRequest } from '../search/switcherModel'

export interface PageDialogState {
  pageId: string
  anchorId: string
}

/**
 * The page window: which page it shows (and the page it opened on), opening it from the map, the
 * List or a request, and where focus goes when it closes (graphViewModel.ts closeFocus): back to
 * the dot for the keyboard, nowhere for a pointer, else to what had focus before.
 */
export function usePageDialog(stageRef: RefObject<HTMLDivElement | null>, mode: 'graph' | 'list', setActive: (a: Active | null) => void) {
  const [dialog, setDialog] = useState<PageDialogState | null>(null)
  const returnTo = useRef<HTMLElement | null>(null)
  const openedBy = useRef<'pointer' | 'keyboard'>('keyboard')
  const open = useCallback((id: string, via: 'pointer' | 'keyboard' = 'keyboard') => {
    openedBy.current = via
    returnTo.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    setDialog({ pageId: id, anchorId: id })
  }, [])
  /** A page asked for from outside (the quick switcher): nothing to return focus to. */
  const openRequested = (id: string) => {
    returnTo.current = null
    setDialog({ pageId: id, anchorId: id })
  }
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
  const navigate = (id: string) => setDialog((d) => (d ? { ...d, pageId: id } : d))
  return { dialog, setDialog, open, openRequested, close, navigate }
}

/**
 * The search box: its text, and the result it has chosen (the first hit, or the one stepped to with
 * the arrows). The map's focus goes back to that result when the pointer leaves a dot, until the
 * search is cleared (searchFocus.ts). "/" focuses the box anywhere on the page, unless the person is
 * typing or a dialog is open.
 */
export function useGraphSearch(index: GraphIndex, setActive: (a: Active | null) => void, dialogOpen: boolean) {
  const [query, setQuery] = useState('')
  const [pick, setPick] = useState<string | null>(null)
  const searchRef = useRef<HTMLInputElement>(null)
  useEffect(() => {
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (!isSearchSlash(e, e.target as HTMLElement | null, dialogOpen)) return
      e.preventDefault()
      searchRef.current?.focus()
      searchRef.current?.select()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [dialogOpen])
  const onQuery = (q: string) => {
    setQuery(q)
    const hits = q.trim() ? searchPages(index, q) : []
    setPick(hits[0] ?? null)
    setActive(hits.length ? { id: hits[0], via: 'keyboard' } : null)
  }
  return { query, onQuery, pick, setPick, searchRef }
}

export interface SearchKeysInput {
  query: string
  /** The search's results among the pages shown; null without a search. */
  matches: string[] | null
  pick: string | null
  setPick: (id: string | null) => void
  active: Active | null
  setActive: (a: Active | null) => void
  open: (id: string) => void
  onQuery: (q: string) => void
}

/** The search box's keys (graphViewModel.ts searchKeyAction: Enter opens, Esc clears, arrows step
 *  through the results), and the map's focus while a search runs (searchFocus.ts focusAfter). */
export function useSearchKeys({ query, matches, pick, setPick, active, setActive, open, onQuery }: SearchKeysInput) {
  const onStageActive = useCallback((next: Active | null) => setActive(focusAfter(next, query.trim() ? matches : null, pick)), [query, matches, pick]) // eslint-disable-line react-hooks/exhaustive-deps
  const onSearchKey = (e: KeyboardEvent<HTMLInputElement>) => {
    // While an input method is composing, every key (Enter picks the word) belongs to it.
    if (e.nativeEvent.isComposing) return
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
  return { onStageActive, onSearchKey }
}

/** Archive / Restore / Delete from the page window or the List (useRetireFlow): a deleted page's
 *  window closes. `retirePages` is undefined when the source cannot retire pages. */
export function usePageRetire(onRetire: PageActions['onRetire'], page: { dialog: PageDialogState | null; setDialog: (d: PageDialogState | null) => void }) {
  const retire = useRetireFlow(onRetire, (r) => {
    if (r.action === 'delete' && page.dialog && r.done.some((d) => d.id === page.dialog!.pageId)) page.setDialog(null)
  })
  return { retire, retirePages: onRetire ? retire.start : undefined }
}

export interface FindRequestTargets {
  index: GraphIndex
  onQuery: (q: string) => void
  showList: () => void
  setActive: (a: Active | null) => void
  openRequested: (id: string) => void
  onRequestDone?: () => void
}

/** A quick-switcher pick (or a page or section from the home page): applied once, and only to this
 *  model's source (a graph still showing another source waits for the asked source's model). */
export function useFindRequest(request: FindRequest | null | undefined, model: GraphModel, t: FindRequestTargets) {
  useEffect(() => {
    if (!request || request.sourceId !== model.source.id) return
    t.onQuery(request.query ?? '')
    if (request.list) t.showList()
    if (request.pageId && t.index.pageById.has(request.pageId)) {
      t.setActive({ id: request.pageId, via: 'keyboard' })
      t.openRequested(request.pageId)
    }
    t.onRequestDone?.()
  }, [request, model]) // eslint-disable-line react-hooks/exhaustive-deps
}
