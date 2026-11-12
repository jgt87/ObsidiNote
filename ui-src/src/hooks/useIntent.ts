import { useEffect, useState } from 'react'
import { getIntent, type IntentResult, type Mode } from '../api'

const DEBOUNCE_MS = 200

/** The server's Add-vs-Ask reading of the text (lib/Intent.psm1), asked 200 ms after typing stops. */
export function useIntent(text: string, mode: Mode): { result: IntentResult | null; error: string } {
  const [result, setResult] = useState<IntentResult | null>(null)
  const [error, setError] = useState('')
  useEffect(() => {
    if (!text.trim() && mode === 'auto') {
      setResult(null)
      setError('')
      return
    }
    const ctl = new AbortController()
    const timer = window.setTimeout(() => {
      getIntent(text, mode, ctl.signal)
        .then((r) => {
          setResult(r)
          setError('')
        })
        .catch((e: unknown) => {
          if (!ctl.signal.aborted) setError(e instanceof Error ? e.message : 'ObsidiNote did not answer.')
        })
    }, DEBOUNCE_MS)
    return () => {
      window.clearTimeout(timer)
      ctl.abort()
    }
  }, [text, mode])
  return { result, error }
}
