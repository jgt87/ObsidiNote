import { useCallback, useEffect, useState } from 'react'
import { getActivity } from './api'
import type { ActivityList } from './activityModel'

/** The vault's activity (its Intake), read when shown, when `key` changes (a vault switch, a send)
 *  and on reload(). Session state in memory only. */
export function useActivity(key: string) {
  const [data, setData] = useState<ActivityList | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [tick, setTick] = useState(0)
  const reload = useCallback(() => setTick((t) => t + 1), [])
  useEffect(() => {
    const ctl = new AbortController()
    setLoading(true)
    getActivity(ctl.signal)
      .then((d) => {
        setData(d)
        setError('')
      })
      .catch((e: unknown) => {
        if (ctl.signal.aborted) return
        setError(e instanceof Error ? e.message : 'ObsidiNote did not answer.')
      })
      .finally(() => !ctl.signal.aborted && setLoading(false))
    return () => ctl.abort()
  }, [key, tick])
  return { data, error, loading, reload }
}
