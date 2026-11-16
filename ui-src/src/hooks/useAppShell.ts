// The app shell's state that is not a view's own (App.tsx): the view in the address, Copilot's
// reconnect, Ask's starting choices and the vault's write access.
import { useCallback, useEffect, useRef, useState } from 'react'
import { checkLease, getSettings, reconnectCopilot, type AppStatus, type NotebookSummary } from '../api'
import type { AskChoices } from '../components/AskOptions'
import { fetchGraph } from '../graph'
import { leaseCheckNote, vaultNote } from '../model/attention'
import { findSourceId, graphRefFor } from '../model/notebooks'
import { viewFromHash, viewTitle, VIEWS, type View } from '../model/views'
import type { FindRequest } from '../search/switcherModel'
import type { NotebooksState } from './useServerData'

/** The view named in the address (#/graph), followed on every change; the window's title follows
 *  the view. `goto` changes the address. */
export function useHashView(): { view: View; goto: (v: View) => void } {
  const [view, setView] = useState<View>(() => viewFromHash(window.location.hash))
  useEffect(() => {
    const onHash = () => setView(viewFromHash(window.location.hash))
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])
  useEffect(() => {
    document.title = viewTitle(view)
  }, [view])
  const goto = useCallback((v: View) => {
    window.location.hash = VIEWS[v].hash
  }, [])
  return { view, goto }
}

/** The side bar's refresh on the Copilot note: one reconnect, then the status is read again.
 *  Resolves with '' when connected, else what to say. */
export function useCopilotRetry(refreshStatus: () => Promise<void>): () => Promise<string> {
  return useCallback(async () => {
    try {
      const r = await reconnectCopilot()
      return r.state === 'connected' ? '' : r.message
    } catch (e) {
      return e instanceof Error ? e.message : 'Copilot could not be reached.'
    } finally {
      await refreshStatus()
    }
  }, [refreshStatus])
}

/** Ask's choices; "Include archived pages" starts from the vault's setting (kept in OneNote), per
 *  vault, read again when the active vault changes. */
export function useAskChoices(activeId: string | null) {
  const [choices, setChoices] = useState<AskChoices>({ sources: [], includeArchived: false })
  useEffect(() => {
    let live = true
    getSettings()
      .then((r) => live && setChoices((c) => ({ ...c, includeArchived: r.settings.askIncludeArchived })))
      .catch(() => {})
    return () => {
      live = false
    }
  }, [activeId])
  return [choices, setChoices] as const
}

/**
 * Which graph the knowledge graph view shows and what it is asked to do when it opens: the shown
 * notebook's graph, the cited pages to highlight ("Show on map"), and a FindRequest (a page window
 * to open, a List to search). The Ctrl+K switcher searches the ACTIVE vault.
 */
export function useGraphNavigation(notebooks: NotebooksState, goto: (v: View) => void) {
  const [graphFocus, setGraphFocus] = useState<string[]>([])
  const [findRequest, setFindRequest] = useState<FindRequest | null>(null)
  const shown = notebooks.list.find((n) => n.id === notebooks.shownId)
  const activeEntry = notebooks.list.find((n) => n.id === notebooks.activeId)
  const refKey = JSON.stringify(graphRefFor(shown))
  const loadGraph = useCallback((signal: AbortSignal) => fetchGraph(JSON.parse(refKey), signal), [refKey])
  const findKey = activeEntry?.vault ? JSON.stringify(graphRefFor(activeEntry)) : null
  const loadFind = useCallback((signal: AbortSignal) => fetchGraph(findKey ? JSON.parse(findKey) : {}, signal), [findKey])
  const chooseActive = () => {
    if (notebooks.activeId) notebooks.choose(notebooks.activeId)
  }
  /** The graph with a request to carry out. */
  const showInGraph = (request: FindRequest) => {
    setGraphFocus([])
    setFindRequest(request)
    goto('graph')
  }
  return {
    shown,
    activeEntry,
    refKey,
    loadGraph,
    findKey,
    loadFind,
    graphFocus,
    findRequest,
    requestDone: () => setFindRequest(null),
    /** "Show on map": the active vault's graph, its cited pages highlighted. */
    showCited: (ids: string[]) => {
      chooseActive()
      setGraphFocus(ids)
      goto('graph')
    },
    /** A pick of the quick switcher: the active vault's graph with that request. */
    showFound: (request: FindRequest) => {
      chooseActive()
      showInGraph(request)
    },
    /** A page opened from the home page or History: the knowledge graph of its notebook with the
     *  page window open (the same FindRequest the Ctrl+K switcher uses; operator, 2026-11-14). */
    openPage: (entry: NotebookSummary | undefined, pageId: string) => {
      if (!entry) return
      if (entry.id !== notebooks.shownId) notebooks.choose(entry.id)
      showInGraph({ sourceId: findSourceId(entry), pageId })
    },
    /** A section picked in the side bar: the shown notebook's List, searched on that section. */
    openSection: (query: string) => {
      if (shown) showInGraph({ sourceId: findSourceId(shown), query, list: true })
    },
  }
}

/**
 * Why this window cannot write in its vault ('' when it can; one banner says it), and "Check
 * again": the server tries to take the vault now (it is never taken from a holder that still renews
 * it), then the status is read again; what it found stays under the note until the note goes.
 * When this window becomes the writer (the earlier start let go of the vault), `reloadGraph` reads
 * the map again, so its pages stop showing read only without a click (operator, 2026-11-15).
 */
export function useVaultAccess(status: AppStatus | null, serverDown: boolean, refreshStatus: () => Promise<void>, reloadGraph: () => void) {
  const vaultWhy = status && !serverDown ? vaultNote(status) : ''
  const writerNow = status?.vault?.mode === 'writer'
  const wasWriter = useRef(writerNow)
  useEffect(() => {
    if (writerNow && !wasWriter.current) reloadGraph()
    wasWriter.current = writerNow
  }, [writerNow]) // eslint-disable-line react-hooks/exhaustive-deps
  const [checkResult, setCheckResult] = useState('')
  const checkAgain = async () => {
    try {
      const v = await checkLease()
      setCheckResult(leaseCheckNote(v))
      if (v.mode === 'writer') reloadGraph()
    } catch (e) {
      setCheckResult(e instanceof Error ? `Could not check: ${e.message}` : 'Could not check.')
    }
    await refreshStatus()
  }
  useEffect(() => {
    if (!vaultWhy) setCheckResult('')
  }, [vaultWhy])
  return { vaultWhy, checkResult, checkAgain }
}
