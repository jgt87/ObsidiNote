import { useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent, type ReactNode } from 'react'
import type { Intent, Mode } from '../api'
import { useIntent } from '../hooks/useIntent'
import { intentLine, primaryLabel } from '../model/intentWording'
import { isSendKey, modeForKey } from '../model/keys'
import type { AddTarget } from '../model/notebooks'
import { AddIcon, AskIcon, InfoIcon } from './icons'
import { ModeSwitch } from './ModeSwitch'
import './Composer.css'

/** Text put in the box from elsewhere ("Ask about this", a follow-up); key makes a repeat count. */
export interface Prefill {
  text: string
  mode: Mode
  key: number
}

interface Props {
  addTarget: AddTarget | null
  /** Sends the text; the box keeps it until the result says it was used. */
  onSend: (text: string, mode: Mode, intent: Intent | null) => void
  busy: boolean
  prefill?: Prefill | null
  /** A line above the buttons, e.g. "Follow-up to ..." with its own cancel. */
  note?: ReactNode
  /** Options under the box (Ask's sources and archived switch). */
  children?: ReactNode
  /** Bumped to empty the box after a result was filed ("Done"). */
  clearKey?: number
}

/** The one input: Auto/Add/Ask, the live intent line, and the primary button that follows it.
 *  The text lives in memory only (never in storage): it is the person's content.
 *  addTarget: set while a read-only notebook is shown (an Add still goes to the active vault). */
export function Composer({ addTarget, onSend, busy, prefill, note, children, clearKey = 0 }: Props) {
  const [text, setText] = useState('')
  const [mode, setMode] = useState<Mode>('auto')
  const area = useRef<HTMLTextAreaElement>(null)
  const { result, error } = useIntent(text, mode)
  const line = intentLine(result, addTarget)
  const empty = !text.trim()

  // Ctrl+1 = Add, Ctrl+2 = Ask, anywhere on the page while this view is open.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const m = modeForKey(e)
      if (!m) return
      e.preventDefault()
      setMode(m)
      area.current?.focus()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  useEffect(() => {
    if (!prefill) return
    setText(prefill.text)
    setMode(prefill.mode)
    area.current?.focus()
  }, [prefill])

  useEffect(() => {
    if (clearKey) setText('')
  }, [clearKey])

  function send() {
    if (empty || busy) return
    onSend(text, mode, result?.intent ?? null)
  }

  function onKeyDown(e: ReactKeyboardEvent<HTMLTextAreaElement>) {
    if (isSendKey({ ...e, isComposing: e.nativeEvent.isComposing })) {
      e.preventDefault()
      send()
    }
  }

  const LineIcon = result?.intent === 'ask' ? AskIcon : result?.intent === 'add' ? AddIcon : InfoIcon
  return (
    <section className="composer" aria-label="Add or ask">
      <div className="composer__top">
        <ModeSwitch mode={mode} onChange={(m) => { setMode(m); area.current?.focus() }} />
        <div className="composer__help">
          <button type="button" className="btn btn--icon btn--ghost composer__help-btn" aria-label="Keyboard shortcuts" aria-describedby="composer-keys">
            <InfoIcon />
          </button>
          <div id="composer-keys" role="tooltip" className="composer__keys">
            <span><kbd>Ctrl</kbd> <kbd>1</kbd></span><span>Add</span>
            <span><kbd>Ctrl</kbd> <kbd>2</kbd></span><span>Ask</span>
            <span><kbd>Enter</kbd></span><span>Send</span>
            <span><kbd>Shift</kbd> <kbd>Enter</kbd></span><span>New line</span>
          </div>
        </div>
      </div>
      <label htmlFor="composer-text" className="visually-hidden">
        Text, link or question
      </label>
      <textarea
        id="composer-text"
        ref={area}
        className="composer__text"
        rows={3}
        value={text}
        placeholder="Paste a link or text, or ask a question"
        onChange={(e) => setText(e.target.value)}
        onKeyDown={onKeyDown}
        autoFocus
        spellCheck
      />
      {note}
      <div className="composer__bottom">
        <p className="composer__intent" role="status">
          <LineIcon />
          <span>
            {error ? (
              <>Cannot tell yet: {error}</>
            ) : (
              <>
                {line.lead && <b>{line.lead}: </b>}
                {line.text}
              </>
            )}
            {line.flip && !error && (
              <>
                {' '}
                <button type="button" className="link-btn" onClick={() => setMode(line.flip!.mode)}>
                  {line.flip.label}
                </button>
              </>
            )}
          </span>
        </p>
        <button type="button" className="btn btn--primary composer__send" onClick={send} disabled={empty || busy} aria-busy={busy}>
          {busy ? 'Working…' : primaryLabel(result)}
        </button>
      </div>
      {children}
    </section>
  )
}
