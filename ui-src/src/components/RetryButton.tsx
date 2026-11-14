// The side bar's "Copilot is not connected" note with its refresh button (user, 2026-11-14): one try
// to connect Copilot again (POST /api/copilot/reconnect). While it runs the icon turns and the button
// is locked; a sign-in or failure message shows under the note's text.
import { useState } from 'react'
import { RefreshIcon } from './icons'

interface Props {
  text: string
  /** Resolves to '' when Copilot is connected, else the message to show. */
  onRetry: () => Promise<string>
}

export function RetryButton({ text, onRetry }: Props) {
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState('')
  const run = async () => {
    if (busy) return
    setBusy(true)
    setMsg('')
    try {
      setMsg(await onRetry())
    } finally {
      setBusy(false)
    }
  }
  return (
    <>
      <span className="rail__note-text">
        <span>{text}</span>
        <span role="status">{busy ? 'Connecting to Copilot...' : msg}</span>
      </span>
      <button
        type="button"
        className="btn btn--sm btn--icon rail__retry"
        aria-label="Connect Copilot again"
        title="Connect Copilot again"
        aria-busy={busy}
        disabled={busy}
        onClick={() => void run()}
      >
        <RefreshIcon />
      </button>
    </>
  )
}
