import { useCallback, useEffect, useRef, useState } from 'react'
import type { GraphModel } from '../graph/model'

/** The active vault's graph model for the Journal: read when the view opens, when `key` changes (a
 *  vault switch) and on reload(). An answer for an older key is dropped. Session state in memory only. */
export function useJournalModel(key: string | null, load: (signal: AbortSignal) => Promise<GraphModel>) {
  const [model, setModel] = useState<GraphModel | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [tick, setTick] = useState(0)
  const reload = useCallback(() => setTick((t) => t + 1), [])
  const loadRef = useRef(load)
  loadRef.current = load
  const shownKey = useRef(key)
  useEffect(() => {
    if (shownKey.current !== key) {
      shownKey.current = key
      setModel(null)
    }
    setError('')
    if (!key) {
      setLoading(false)
      return
    }
    const ctl = new AbortController()
    setLoading(true)
    loadRef.current(ctl.signal)
      .then((m) => !ctl.signal.aborted && setModel(m))
      .catch((e: unknown) => !ctl.signal.aborted && setError(e instanceof Error ? e.message : 'ObsidiNote did not answer.'))
      .finally(() => !ctl.signal.aborted && setLoading(false))
    return () => ctl.abort()
  }, [key, tick])
  return { model, error, loading, reload }
}
