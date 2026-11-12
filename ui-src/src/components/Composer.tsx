import { useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from 'react'
import { submit, type Mode } from '../api'
import { useIntent } from '../hooks/useIntent'
import { intentLine, primaryLabel } from '../model/intentWording'
import { isSendKey, modeForKey } from '../model/keys'
import type { AddTarget } from '../model/notebooks'
import { AddIcon, AskIcon, InfoIcon } from './icons'
import { ModeSwitch } from './ModeSwitch'
import './Composer.css'

/** The one input: Auto/Add/Ask, the live intent line, and the primary button that follows it.
 *  The text lives in memory only (never in storage): it is the person's content.
 *  addTarget: set while a read-only notebook is shown (an Add still goes to the active vault). */
export function Composer({ addTarget }: { addTarget: AddTarget | null }) {
  const [text, setText] = useState('')
  const [mode, setMode] = useState<Mode>('auto')
  const [busy, setBusy] = useState(false)
  const [reply, setReply] = useState('')
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

  useEffect(() => setReply(''), [text, mode])

  async function send() {
    if (empty || busy) return
    setBusy(true)
    setReply('')
    try {
      const r = await submit(text, mode)
      setReply(`${r.message}. Your text stays in the box.`)
    } catch (e) {
      setReply(e instanceof Error ? `Not sent: ${e.message}` : 'Not sent: ObsidiNote did not answer.')
    } finally {
      setBusy(false)
    }
  }

  function onKeyDown(e: ReactKeyboardEvent<HTMLTextAreaElement>) {
    if (isSendKey({ ...e, isComposing: e.nativeEvent.isComposing })) {
      e.preventDefault()
      void send()
    }
  }

  const LineIcon = result?.intent === 'ask' ? AskIcon : result?.intent === 'add' ? AddIcon : InfoIcon
  return (
    <>
      <section className="composer" aria-label="Add or ask">
        <div className="composer__top">
          <ModeSwitch mode={mode} onChange={(m) => { setMode(m); area.current?.focus() }} />
          <p className="composer__keys">
            <kbd>Ctrl</kbd> <kbd>1</kbd> Add · <kbd>Ctrl</kbd> <kbd>2</kbd> Ask · <kbd>Enter</kbd> send · <kbd>Shift</kbd> <kbd>Enter</kbd> new line
          </p>
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
          <button type="button" className="btn btn--primary composer__send" onClick={() => void send()} disabled={empty || busy} aria-busy={busy}>
            {primaryLabel(result)}
          </button>
        </div>
      </section>
      <p className="composer__reply" role="status">
        {reply}
      </p>
    </>
  )
}
