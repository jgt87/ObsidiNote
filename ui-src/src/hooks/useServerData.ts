import { useCallback, useEffect, useRef, useState } from 'react'
import { getNotebook, getNotebooks, getStatus, setActiveVault, type AppStatus, type NotebookSummary, type NotebookView, type VaultMode } from '../api'
import { pickActiveVault } from '../model/notebooks'
import { getStoredVaultId, persistVaultId } from '../model/preferences'

const STATUS_EVERY_MS = 10_000
const NOTEBOOK_EVERY_MS = 60_000

/** /api/status every 10 s; serverDown when the local server stops answering. refresh() reads it now. */
export function useStatus(): { status: AppStatus | null; serverDown: boolean; refresh: () => Promise<void> } {
  const [status, setStatus] = useState<AppStatus | null>(null)
  const [serverDown, setServerDown] = useState(false)
  const alive = useRef(true)
  const refresh = useCallback(
    () =>
      getStatus()
        .then((s) => {
          if (!alive.current) return
          setStatus(s)
          setServerDown(false)
        })
        .catch(() => {
          if (alive.current) setServerDown(true)
        }),
    [],
  )
  useEffect(() => {
    alive.current = true
    void refresh()
    const id = window.setInterval(() => void refresh(), STATUS_EVERY_MS)
    return () => {
      alive.current = false
      window.clearInterval(id)
    }
  }, [refresh])
  return { status, serverDown, refresh }
}

/** Runs $fn at start, every minute and when the window gets focus again. */
function useRefresh(fn: () => void) {
  useEffect(() => {
    fn()
    const id = window.setInterval(fn, NOTEBOOK_EVERY_MS)
    window.addEventListener('focus', fn)
    return () => {
      window.clearInterval(id)
      window.removeEventListener('focus', fn)
    }
  }, [fn])
}

export interface NotebooksState {
  list: NotebookSummary[]
  message: string
  /** The active vault (where Add will write); null when none is open. */
  activeId: string | null
  /** The notebook shown in the rail and in "Recently changed". */
  shownId: string | null
  error: string
  /** writer = Add can write to the active vault; readonly = another ObsidiNote is writing there. */
  mode: VaultMode
  choose: (id: string) => void
  /** A vault the server just made active (a new vault): remember it and show it. */
  adopt: (id: string) => void
}

/** The open notebooks and the choice between them. Choosing a vault makes it the active one (kept
 *  as a UI preference and as the start's notebook record); choosing another notebook only shows
 *  it, read only. */
export function useNotebooks(): NotebooksState {
  const [list, setList] = useState<NotebookSummary[]>([])
  const [message, setMessage] = useState('')
  const [activeId, setActiveId] = useState<string | null>(null)
  const [shownId, setShownId] = useState<string | null>(null)
  const [error, setError] = useState('')
  const [mode, setMode] = useState<VaultMode>('none')
  const synced = useRef<string | null>(null)

  const makeActive = useCallback((id: string) => {
    setActiveId(id)
    persistVaultId(id)
    if (synced.current === id) return
    synced.current = id
    setActiveVault(id)
      .then((r) => setMode(r.mode))
      .catch((e: unknown) => setError(e instanceof Error ? e.message : 'The vault could not be made active.'))
  }, [])

  const load = useCallback(() => {
    getNotebooks()
      .then((l) => {
        setList(l.notebooks)
        setMessage(l.message)
        setMode(l.mode)
        setError('')
        const active = pickActiveVault(l.notebooks, getStoredVaultId())
        const serverActive = l.notebooks.find((n) => n.active)?.id ?? null
        if (active && active !== serverActive) makeActive(active)
        else {
          setActiveId(active)
          synced.current = active
        }
        // Keep showing the chosen notebook while it is open; else the active vault.
        setShownId((cur) => (cur && l.notebooks.some((n) => n.id === cur) ? cur : active ?? l.notebooks[0]?.id ?? null))
      })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : 'ObsidiNote did not answer.'))
  }, [makeActive])
  useRefresh(load)

  const choose = useCallback(
    (id: string) => {
      const n = list.find((x) => x.id === id)
      if (!n) return
      if (n.vault) makeActive(id)
      setShownId(id)
    },
    [list, makeActive],
  )
  const adopt = useCallback(
    (id: string) => {
      persistVaultId(id)
      synced.current = id
      setActiveId(id)
      setShownId(id)
      load()
    },
    [load],
  )
  return { list, message, activeId, shownId, error, mode, choose, adopt }
}

export interface NotebookState {
  data: NotebookView | null
  loading: boolean
  error: string
  reload: () => void
}

/** /api/notebook for the shown notebook, kept in memory only. */
export function useNotebook(id: string | null): NotebookState {
  const [data, setData] = useState<NotebookView | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const reload = useCallback(() => {
    setLoading(true)
    getNotebook(id)
      .then((v) => {
        setData(v)
        setError('')
      })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : 'ObsidiNote did not answer.'))
      .finally(() => setLoading(false))
  }, [id])
  useEffect(() => setData(null), [id])
  useRefresh(reload)
  return { data, loading, error, reload }
}
