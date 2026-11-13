import { useEffect, useRef, useState } from 'react'
import { exportDoneText, exportMarkdown, type ExportRequest } from './exportApi'
import './ExportButton.css'

type State = { kind: 'idle' } | { kind: 'busy' } | { kind: 'done'; text: string } | { kind: 'error'; text: string }

/** "Export as Markdown": one button for a page, a topic or a whole vault (POST /api/export). The
 *  file goes to the browser's downloads. Success reuses the verb on the button ("Exported", for a
 *  few seconds) and is announced; a failure says why next to the button. */
export function ExportButton({ request, label, className = 'btn', disabled = false }: { request: ExportRequest; label: string; className?: string; disabled?: boolean }) {
  const [state, setState] = useState<State>({ kind: 'idle' })
  const timer = useRef<number | undefined>(undefined)
  useEffect(() => () => window.clearTimeout(timer.current), [])
  const run = () => {
    window.clearTimeout(timer.current)
    setState({ kind: 'busy' })
    exportMarkdown(request)
      .then((name) => {
        setState({ kind: 'done', text: exportDoneText(name) })
        timer.current = window.setTimeout(() => setState({ kind: 'idle' }), 4000)
      })
      .catch((e: unknown) => setState({ kind: 'error', text: e instanceof Error ? e.message : 'The export did not work.' }))
  }
  const busy = state.kind === 'busy'
  const text = busy ? 'Exporting…' : state.kind === 'done' ? 'Exported' : label
  return (
    <span className="export">
      <button type="button" className={className} onClick={run} disabled={disabled || busy} aria-busy={busy} title={state.kind === 'done' ? state.text : undefined}>
        {/* The longest label sits invisibly under the shown one, so the width never changes. */}
        <span className="export__w">
          <span>{text}</span>
          <span aria-hidden="true">{label.length >= 'Exporting…'.length ? label : 'Exporting…'}</span>
        </span>
      </button>
      <span className="visually-hidden" role="status">
        {state.kind === 'done' ? state.text : ''}
      </span>
      {state.kind === 'error' && (
        <span className="export__msg" role="alert">
          {state.text}
        </span>
      )}
    </span>
  )
}
