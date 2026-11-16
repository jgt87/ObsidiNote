import { useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent, type ReactNode, type RefObject } from 'react'
import { loneLink } from '../model/links'
import type { Intent, Mode } from '../api'
import { useBoxDrop } from '../hooks/useBoxDrop'
import { useFileIntake } from '../hooks/useFileIntake'
import { useIntent } from '../hooks/useIntent'
import { usePasteOrigin } from '../hooks/usePasteOrigin'
import { composerView } from '../model/composerView'
import { intentLine, primaryLabel } from '../model/intentWording'
import { isSendKey, modeForKey } from '../model/keys'
import type { SendBlock } from '../model/attention'
import type { AddTarget } from '../model/notebooks'
import { FileStatus, FromChoice, IntentLine, KeysHelp } from './ComposerParts'
import { PaperclipIcon, WarnIcon } from './icons'
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
  /** Sends the text; the box keeps it until the server has processed it (then `clearKey` changes).
   *  origin: where the text came from ('' = typed), the "From:" choice (model/origins.ts). */
  onSend: (text: string, mode: Mode, intent: Intent | null, origin: string, fileUrl?: string) => void
  busy: boolean
  prefill?: Prefill | null
  /** A line above the buttons, e.g. "Follow-up to ..." with its own cancel. */
  note?: ReactNode
  /** Options under the box (Ask's sources and archived switch). */
  children?: ReactNode
  /** Bumped to empty the box after a result was filed ("Done"). */
  clearKey?: number
  /** Why a send cannot work right now; shown in place of the intent line. */
  block?: SendBlock | null
  /** The control that can fix it ("Connect Copilot again"), next to that line. */
  connect?: ReactNode
}

const FILE_TYPES = '.docx,.docm,.pptx,.xlsx,.xlsm,.pdf,.msg,.eml,.txt,.md,.csv,.tsv,.json,.log,.html,.htm'

/** A file let go beside the box must not make the browser open it in place of the app (the app
 *  window has no Back, and everything in memory would be gone): outside the box a drop does nothing. */
function useNoDropOutside() {
  useEffect(() => {
    const stop = (e: DragEvent) => {
      if (!e.dataTransfer || ![...e.dataTransfer.types].includes('Files')) return
      e.preventDefault()
      if (!(e.target instanceof Element && e.target.closest('.composer'))) e.dataTransfer.dropEffect = 'none'
    }
    window.addEventListener('dragover', stop)
    window.addEventListener('drop', stop)
    return () => {
      window.removeEventListener('dragover', stop)
      window.removeEventListener('drop', stop)
    }
  }, [])
}

/** Ctrl+1 = Add, Ctrl+2 = Ask, anywhere on the page while this view is open. */
function useModeKeys(setMode: (m: Mode) => void, focus: () => void) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const m = modeForKey(e)
      if (!m) return
      e.preventDefault()
      setMode(m)
      focus()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
    // Bound once: setMode is a state setter and focus reads a ref, both the same on every render.
  }, [])
}

/** The box starts at four lines and grows with its text up to about twelve, then scrolls (operator,
 *  2026-11-15: "make the typing area bigger"; CSS min/max-height). Its edge counts in its height. */
function useAutoGrow(area: RefObject<HTMLTextAreaElement | null>, text: string) {
  useEffect(() => {
    const el = area.current
    if (!el) return
    el.style.height = 'auto'
    el.style.height = `${el.scrollHeight + el.offsetHeight - el.clientHeight}px`
  }, [area, text])
}

/** The one input: Auto/Add/Ask, the live intent line, and the primary button that follows it.
 *  The text lives in memory only (never in storage): it is the person's content.
 *  addTarget: set while a read-only notebook is shown (an Add still goes to the active vault). */
export function Composer({ addTarget, onSend, busy, prefill, note, children, clearKey = 0, block = null, connect = null }: Props) {
  const [text, setText] = useState('')
  const [mode, setMode] = useState<Mode>('auto')
  const area = useRef<HTMLTextAreaElement>(null)
  const focus = () => area.current?.focus()
  // One link and nothing else, also as "[title](address)", is that address: read and sent as a link.
  const onlyLink = loneLink(text)
  const sendText = onlyLink ?? text
  const { result, error } = useIntent(sendText, mode)
  const line = intentLine(result, addTarget)
  // Where the text came from (the "From" choice) and the paste it was read from (hooks/usePasteOrigin.ts).
  const pasted = usePasteOrigin(text, setText)

  // A file is something to keep, never a question: its text comes in as an Add, "From: File".
  const files = useFileIntake(busy, (fileText) => {
    setText(fileText)
    setMode('add')
    pasted.fromFile(fileText)
    focus()
  })
  // A link dragged in is the same as a pasted one, so it becomes that address's link page.
  const drop = useBoxDrop(
    (file) => void files.take(file),
    (link) => {
      setText(link)
      files.clearNote()
      focus()
    },
  )
  const picker = useRef<HTMLInputElement>(null)
  const v = composerView({ text, onlyLink, mode, intent: result?.intent, origin: pasted.origin, fileLink: files.link, busy, disableSend: Boolean(block?.disableSend) })

  useNoDropOutside()
  useModeKeys(setMode, focus)
  useAutoGrow(area, text)

  useEffect(() => {
    if (!prefill) return
    setText(prefill.text)
    setMode(prefill.mode)
    pasted.clear() // a prefill (Save answer) is ObsidiNote's own text, not the earlier paste
    focus()
  }, [prefill])

  useEffect(() => {
    if (clearKey) {
      files.reset()
      setText('')
    }
  }, [clearKey])

  function send() {
    if (!v.canSend) return
    files.cancel()
    onSend(sendText, mode, result?.intent ?? null, v.sendOrigin, v.liveFileUrl)
  }

  function onKeyDown(e: ReactKeyboardEvent<HTMLTextAreaElement>) {
    pasted.notePlainPaste(e)
    if (isSendKey({ ...e, isComposing: e.nativeEvent.isComposing })) {
      e.preventDefault()
      send()
    }
  }

  return (
    <section
      className="composer"
      aria-label="Add or ask"
      data-dragging={drop.dragging || undefined}
      onDragOver={drop.onDragOver}
      onDragLeave={drop.onDragLeave}
      onDrop={drop.onDrop}
    >
      {drop.dragging && (
        <p className="composer__drop" aria-hidden="true">
          Drop the file to put its text in the box
        </p>
      )}
      <label htmlFor="composer-text" className="visually-hidden">
        Text, link or question
      </label>
      <textarea
        id="composer-text"
        ref={area}
        className="composer__text"
        rows={4}
        value={text}
        placeholder="Paste a link or text, drop a file, or ask a question"
        onChange={(e) => setText(e.target.value)}
        onKeyDown={onKeyDown}
        onPaste={pasted.onPaste}
        autoFocus
        spellCheck
      />
      <FileStatus linkDropped={v.linkDropped} note={files.note} />
      {v.showFrom && <FromChoice origin={pasted.origin} onChange={pasted.choose} />}
      {note}
      {/* Copilot off or ObsidiNote gone: said on its own line. The reading of the text and its
          "Add instead / Ask instead" stay, since Send still works while only Copilot is reported
          off (code review 2026-11-15: the warning had replaced them). */}
      {block && (
        <p className="composer__intent composer__block" role="status" data-block="">
          <WarnIcon />
          <span>
            <b>{block.text}</b> {connect}
          </span>
        </p>
      )}
      <IntentLine intent={result?.intent} line={line} error={error} onFlip={setMode} />
      {/* design (operator, 2026-11-15: "move the auto/add/ask buttons into the bottom part as well, so all
          buttons are in the same row ... and then the paperclip button next to those buttons"): every
          control of the box in one row under the text, what the text will do on its own line above. */}
      <div className="composer__bottom">
        <ModeSwitch mode={mode} onChange={(m) => { setMode(m); focus() }} />
        <KeysHelp />
        {/* The drop's keyboard and touch path: the same reading, from a file picker. */}
        <button type="button" className="btn btn--icon btn--ghost composer__file-btn" onClick={() => picker.current?.click()} disabled={busy} aria-label="Add a file" title="Add a file: Word, PowerPoint, Excel, PDF, Outlook mail, text or a web page">
          <PaperclipIcon />
        </button>
        <input
          ref={picker}
          type="file"
          className="visually-hidden"
          tabIndex={-1}
          aria-hidden="true"
          accept={FILE_TYPES}
          onChange={(e) => {
            void files.take(e.target.files?.[0])
            e.target.value = ''
          }}
        />
        <button type="button" className="btn btn--primary composer__send" onClick={send} disabled={!v.canSend} aria-busy={busy}>
          {busy ? 'Working…' : primaryLabel(result)}
        </button>
      </div>
      {v.asking && children}
    </section>
  )
}
