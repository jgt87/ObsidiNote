import { BusyLabel } from './BusyLabel'
import { useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent, type ReactNode, type RefObject } from 'react'
import { unavailable } from './disabledGuard'
import { loneLink } from '../model/links'
import type { Intent, Mode } from '../api'
import { useBoxDrop } from '../hooks/useBoxDrop'
import { useFileIntake } from '../hooks/useFileIntake'
import { useIntent } from '../hooks/useIntent'
import { usePasteOrigin } from '../hooks/usePasteOrigin'
import { composerView } from '../model/composerView'
import { intentLine, primaryLabel } from '../model/intentWording'
import { isSendKey, modeForKey } from '../model/keys'
import { onFirstView } from '../model/viewChange'
import type { SendBlock } from '../model/attention'
import type { AddTarget } from '../model/notebooks'
import { FileStatus, FromChoice, IntentLine, KeysHelp } from './ComposerParts'
import { Icon } from './icons'
import { ModeSwitch } from './ModeSwitch'
import './Composer.css'

/** Text put in the box from elsewhere ("Ask about this", a follow-up); key makes a repeat count. */
export interface Prefill {
  text: string
  mode: Mode
  key: number
}

/** What the box holds while its view is not shown: the unsent text and mode, and the last prefill
 *  and clear it carried out (so showing the view again does not repeat them). Kept by the home flow,
 *  in memory only (it is the person's content). Audit 2026-11-24: switching to the map and back
 *  lost a draft, because the text lived in the box, which goes when its view goes. */
export interface ComposerDraft {
  text: string
  mode: Mode
  prefillKey: number
  clearKey: number
}

/** The box takes the focus when the window opens; later, the view change places it (App.tsx). */
let openedOnce = false

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
  /** Where the unsent text survives the view going away; read once when the box appears. */
  draft?: ComposerDraft
  onDraft?: (d: ComposerDraft) => void
  /** The id of the visible text that names the box (the view's heading); else a hidden label. */
  labelledBy?: string
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

/** The box starts at four lines and grows with its text up to about twelve, then scrolls (D-044;
 *  CSS min/max-height). Its edge counts in its height. */
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
export function Composer({ addTarget, onSend, busy, prefill, note, children, clearKey = 0, block = null, connect = null, draft, onDraft, labelledBy }: Props) {
  const [text, setText] = useState(() => draft?.text ?? '')
  const [mode, setMode] = useState<Mode>(() => draft?.mode ?? 'auto')
  // The prefill and clear already carried out: coming back to the view must not repeat them over
  // the kept draft (an old "Ask about this" text, or emptying a box typed in since).
  const seen = useRef({ prefill: draft?.prefillKey ?? -1, clear: draft?.clearKey ?? 0 })
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
    if (!prefill || prefill.key === seen.current.prefill) return
    seen.current.prefill = prefill.key
    setText(prefill.text)
    setMode(prefill.mode)
    pasted.clear() // a prefill (Save answer) is ObsidiNote's own text, not the earlier paste
    focus()
  }, [prefill])

  useEffect(() => {
    if (clearKey && clearKey !== seen.current.clear) {
      seen.current.clear = clearKey
      files.reset()
      setText('')
    }
  }, [clearKey])

  useEffect(() => {
    onDraft?.({ text, mode, prefillKey: seen.current.prefill, clearKey: seen.current.clear })
  }, [text, mode, prefill, clearKey]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (openedOnce) return
    openedOnce = true
    // Only when the window opened on this view: reached from another view, the view change puts
    // the focus on the view itself (App.tsx useViewFocus).
    if (onFirstView()) focus()
  }, [])

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
      {!labelledBy && (
        <label htmlFor="composer-text" className="visually-hidden">
          Text, link or question
        </label>
      )}
      {/* Named by the view's visible heading when there is one: the placeholder only says what may go in. */}
      <textarea
        id="composer-text"
        ref={area}
        className="composer__text"
        rows={4}
        value={text}
        placeholder="Paste a link or text, drop a file, or ask a question"
        aria-labelledby={labelledBy}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={onKeyDown}
        onPaste={pasted.onPaste}
        spellCheck
      />
      {/* The file picker sits outside the row of buttons: hidden, it would count as a 1 px control there. */}
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
      <FileStatus linkDropped={v.linkDropped} note={files.note} />
      {v.showFrom && <FromChoice origin={pasted.origin} onChange={pasted.choose} />}
      {note}
      {/* Copilot off or ObsidiNote gone: said on its own line. The reading of the text and its
          "Add instead / Ask instead" stay, since Send still works while only Copilot is reported
          off (code review 2026-11-15: the warning had replaced them). Mounted empty, so it is announced. */}
      <div className="live" role="status">
        {block && (
          <p className="composer__intent composer__block" data-block="">
            <Icon name="warn" />
            <span>
              <b>{block.text}</b> {connect}
            </span>
          </p>
        )}
      </div>
      <IntentLine intent={result?.intent} line={line} error={error} onFlip={setMode} />
      {/* design: D-045: every control of the box in one row under the text, what the text will do on its own line above. */}
      <div className="composer__bottom">
        <ModeSwitch mode={mode} onChange={(m) => { setMode(m); focus() }} />
        <KeysHelp />
        {/* The drop's keyboard and touch path: the same reading, from a file picker. */}
        <button type="button" className="btn btn--icon btn--ghost composer__file-btn" onClick={() => picker.current?.click()} {...unavailable(busy)} aria-label="Add a file" title="Add a file: Word, PowerPoint, Excel, PDF, Outlook mail, text or a web page">
          <Icon name="paperclip" />
        </button>
        <button type="button" className="btn btn--primary composer__send" onClick={send} {...unavailable(!v.canSend)} aria-busy={busy}>
          <BusyLabel label={primaryLabel(result)} busyText="Working…" />
        </button>
      </div>
      {v.asking && children}
    </section>
  )
}
