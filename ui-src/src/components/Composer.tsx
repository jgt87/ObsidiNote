import { useEffect, useRef, useState, type ClipboardEvent as ReactClipboardEvent, type DragEvent as ReactDragEvent, type KeyboardEvent as ReactKeyboardEvent, type ReactNode, type RefObject } from 'react'
import { dragIsTakeable, droppedLink } from '../add/fileNotes'
import { markdownForPaste, type PasteNode } from '../add/pasteMarkdown'
import { followMark, newMark, originOfPaste, pasteMark } from '../add/pasteOrigin'
import { loneLink } from '../model/links'
import type { Intent, Mode } from '../api'
import { useFileIntake } from '../hooks/useFileIntake'
import { useIntent } from '../hooks/useIntent'
import { intentLine, primaryLabel } from '../model/intentWording'
import { isSendKey, modeForKey } from '../model/keys'
import type { SendBlock } from '../model/attention'
import type { AddTarget } from '../model/notebooks'
import { FromChoice, IntentLine, KeysHelp } from './ComposerParts'
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

/** The pasted HTML as an inert document (DOMParser runs no scripts and loads no images). */
function parseHtml(html: string): PasteNode | null {
  return new DOMParser().parseFromString(html, 'text/html').body
}

/** Puts text at the cursor as if typed, so Ctrl+Z still undoes the paste; the state follows through
 *  the input event. Without insertText, the text is set directly and the cursor put after it. */
function insertAtCursor(box: HTMLTextAreaElement, text: string, setText: (t: string) => void) {
  box.focus()
  if (document.execCommand?.('insertText', false, text)) return
  const { selectionStart: start, selectionEnd: end, value } = box
  setText(value.slice(0, start) + text + value.slice(end))
  requestAnimationFrame(() => box.setSelectionRange(start + text.length, start + text.length))
}

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
  const empty = !text.trim()
  // Where the text came from: set from a paste (add/pasteOrigin.ts), changeable, '' = typed. A link
  // alone needs none (its address says where it lives), and an Ask files nothing.
  const [origin, setOrigin] = useState('')
  // The paste the origin was read from: when it leaves the box, so does the origin (followMark).
  const markRef = useRef(newMark())
  const setMark = (mark: string, from = '') => {
    markRef.current = newMark(mark, from)
  }
  const showFrom = !empty && !onlyLink && mode !== 'ask' && result?.intent !== 'ask'
  useEffect(() => {
    const next = followMark(markRef.current, text)
    markRef.current = next.mark
    if (next.origin !== undefined) setOrigin(next.origin)
  }, [empty, text])

  // A file is something to keep, never a question: its text comes in as an Add, "From: File".
  const files = useFileIntake(busy, (fileText) => {
    setText(fileText)
    setMode('add')
    setOrigin('file')
    setMark(pasteMark(fileText), 'file')
    focus()
  })
  const [dragging, setDragging] = useState(false)
  const picker = useRef<HTMLInputElement>(null)

  useNoDropOutside()
  useModeKeys(setMode, focus)
  useAutoGrow(area, text)

  useEffect(() => {
    if (!prefill) return
    setText(prefill.text)
    setMode(prefill.mode)
    setOrigin('') // a prefill (Save answer) is ObsidiNote's own text, not the earlier paste
    setMark('')
    focus()
  }, [prefill])

  useEffect(() => {
    if (clearKey) {
      files.reset()
      setText('')
    }
  }, [clearKey])

  // The address of the dropped file, for as long as the box still holds that file's text: the
  // "From" choice is "File" while it does (the mark above), so trimming a paragraph or fixing a
  // typo keeps the link (code review 2026-11-15: any edit dropped it without a word).
  const liveFileUrl = files.link && origin === 'file' && !empty ? files.link.url : ''

  // Ask's options (what Ask reads) only when the text will be asked (operator, 2026-11-14).
  const asking = mode === 'ask' || (mode === 'auto' && result?.intent === 'ask')

  function send() {
    if (empty || busy || block?.disableSend) return
    files.cancel()
    onSend(sendText, mode, result?.intent ?? null, showFrom ? origin : '', liveFileUrl)
  }

  // Paste from a web page, Word or a mail: its structure (headings, lists, tables, bold, links)
  // comes in as Markdown, which the server turns into OneNote formatting. Ctrl+Shift+V pastes plain.
  const plainPasteAt = useRef(0)
  function onPaste(e: ReactClipboardEvent<HTMLTextAreaElement>) {
    const html = e.clipboardData.getData('text/html')
    const from = originOfPaste(html)
    const plain = e.clipboardData.getData('text/plain')
    if (from) {
      setOrigin(from)
      setMark(pasteMark(plain), from)
    }
    if (Date.now() - plainPasteAt.current < 1000) {
      plainPasteAt.current = 0
      return
    }
    const md = markdownForPaste(html, parseHtml)
    if (md == null) return
    if (from) setMark(pasteMark(md), from)
    e.preventDefault()
    insertAtCursor(e.currentTarget, md, setText)
  }

  function onKeyDown(e: ReactKeyboardEvent<HTMLTextAreaElement>) {
    if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.code === 'KeyV') plainPasteAt.current = Date.now()
    if (isSendKey({ ...e, isComposing: e.nativeEvent.isComposing })) {
      e.preventDefault()
      send()
    }
  }

  function onDragOver(e: ReactDragEvent<HTMLElement>) {
    if (!dragIsTakeable([...e.dataTransfer.types])) return
    e.preventDefault()
    e.dataTransfer.dropEffect = 'copy'
    setDragging(true)
  }

  function onDrop(e: ReactDragEvent<HTMLElement>) {
    setDragging(false)
    if (e.dataTransfer.files.length) {
      e.preventDefault()
      void files.take(e.dataTransfer.files[0])
      return
    }
    // A link dragged from a browser tab (a OneDrive or SharePoint file, a web page): the same as
    // pasting it, so it becomes that address's link page.
    const link = droppedLink(e.dataTransfer.getData('text/uri-list') || '')
    if (link) {
      e.preventDefault()
      setText(link)
      files.clearNote()
      focus()
    }
  }

  const fileNote = files.note
  return (
    <section
      className="composer"
      aria-label="Add or ask"
      data-dragging={dragging || undefined}
      onDragOver={onDragOver}
      onDragLeave={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDragging(false)
      }}
      onDrop={onDrop}
    >
      {dragging && (
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
        onPaste={onPaste}
        autoFocus
        spellCheck
      />
      {files.link && !liveFileUrl && !empty && (
        <p className="composer__file-note" role="status">
          The file's link is no longer kept: the text in the box is not the file's any more. Choose "File" under From to keep it.
        </p>
      )}
      {fileNote && (
        <p className={fileNote.error ? 'composer__file-note composer__file-note--error' : 'composer__file-note'} role={fileNote.error ? 'alert' : 'status'}>
          {fileNote.error && <WarnIcon />}
          {fileNote.text}
        </p>
      )}
      {showFrom && (
        <FromChoice
          origin={origin}
          onChange={(o) => {
            setOrigin(o)
            setMark('') // chosen by hand: it stays until the box is emptied
          }}
        />
      )}
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
        <button type="button" className="btn btn--primary composer__send" onClick={send} disabled={empty || busy || Boolean(block?.disableSend)} aria-busy={busy}>
          {busy ? 'Working…' : primaryLabel(result)}
        </button>
      </div>
      {asking && children}
    </section>
  )
}
