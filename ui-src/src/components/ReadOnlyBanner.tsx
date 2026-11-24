import { BusyLabel } from './BusyLabel'
import { unavailable } from './disabledGuard'
import { useState } from 'react'
import { Icon } from './icons'
import './ReadOnlyBanner.css'

/**
 * The one place that says this window (or the notebook shown) cannot be changed, and why
 * (design round 2, 2026-11-15: the reason stood in the side bar, on a badge beside the graph's
 * title and on a badge in the page window, each in other words). On the home and History views
 * the app shell shows it for the active vault; on the knowledge graph the graph shows it for the
 * source it draws. The page window only keeps the line under its disabled Edit.
 */
export function ReadOnlyBanner({ text, onCheck, result = '' }: { text: string; onCheck?: () => Promise<void> | void; result?: string }) {
  const [busy, setBusy] = useState(false)
  const check = async () => {
    if (!onCheck || busy) return
    setBusy(true)
    try {
      await onCheck()
    } finally {
      setBusy(false)
    }
  }
  return (
    <div className="notice ro-banner" role="status">
      <Icon name="lock" />
      <div className="notice__body">
        <p>{text}</p>
        {result && <p className="ro-banner__result">{result}</p>}
      </div>
      {onCheck && (
        <button type="button" className="btn btn--sm" onClick={() => void check()} {...unavailable(busy)} aria-busy={busy}>
          <BusyLabel label="Check again" busyText="Checking…" />
        </button>
      )}
    </div>
  )
}
