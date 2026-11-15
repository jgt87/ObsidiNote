// "Update summaries" of the List: the normal link Update, one page at a time (linkUpdateRun.ts holds
// the steps and the wording). Copilot gets one request at a time; Stop ends after the page being
// read. A page that needs a decision or waits for Copilot is counted and named in the summary.

import { useEffect, useRef, useState } from 'react'
import type { AddStatus } from '../add/types'
import { advance, outcomeOf, runLine, startRun } from './linkUpdateRun'

interface Props {
  ids: string[]
  title: (id: string) => string
  update: (id: string) => Promise<AddStatus>
  onClose: () => void
}

export function LinkUpdateBar({ ids, title, update, onClose }: Props) {
  const [s, setS] = useState(() => startRun(ids))
  const updateRef = useRef(update)
  updateRef.current = update
  // One request per page, also when the effect runs twice for the same page (StrictMode in dev).
  const sent = useRef(new Set<string>())

  useEffect(() => {
    const id = s.current
    if (!id || sent.current.has(id)) return
    sent.current.add(id)
    updateRef.current(id).then(
      (st) => setS((x) => advance(x, id, outcomeOf(st))),
      () => setS((x) => advance(x, id, 'failed')),
    )
  }, [s.current])

  return (
    <div className="kg-tbl__run" role="status">
      <span className="kg-tbl__run-line">{runLine(s, title)}</span>
      {s.current ? (
        <button type="button" className="btn btn--sm" disabled={s.stopped} onClick={() => setS((x) => ({ ...x, stopped: true }))}>
          Stop
        </button>
      ) : (
        <button type="button" className="btn btn--sm btn--ghost" onClick={onClose}>
          Close
        </button>
      )}
    </div>
  )
}
