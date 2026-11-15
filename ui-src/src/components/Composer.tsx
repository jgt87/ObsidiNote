import { useEffect, useRef, useState, type ClipboardEvent as ReactClipboardEvent, type KeyboardEvent as ReactKeyboardEvent, type ReactNode } from 'react'
import { markdownForPaste, type PasteNode } from '../add/pasteMarkdown'
import { originOfPaste, originStillApplies, pasteMark } from '../add/pasteOrigin'
import { MAX_FILE_BYTES, readFileText } from '../add/fileText'
import { locateFile, type LocateResult } from '../api'
import { loneLink } from '../model/links'
import { ORIGINS, TYPED_LABEL } from '../model/origins'
import type { Intent, Mode } from '../api'
import { useIntent } from '../hooks/useIntent'
import { intentLine, primaryLabel } from '../model/intentWording'
import { isSendKey, modeForKey } from '../model/keys'
import type { SendBlock } from '../model/attention'
import type { AddTarget } from '../model/notebooks'
import { AddIcon, AskIcon, FileIcon, InfoIcon, WarnIcon } from './icons'
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

/** The one input: Auto/Add/Ask, the live intent line, and the primary button that follows it.
 *  The text lives in memory only (never in storage): it is the person's content.
 *  addTarget: set while a read-only notebook is shown (an Add still goes to the active vault). */
export function Composer({ addTarget, onSend, busy, prefill, note, children, clearKey = 0, block = null, connect = null }: Props) {
  const [text, setText] = useState('')
  const [mode, setMode] = useState<Mode>('auto')
  const area = useRef<HTMLTextAreaElement>(null)
  // Counts what the box has moved on from (a send, an emptied box, a newer file): a file read or
  // lookup that answers later belongs to an older count and is dropped (code review 2026-11-15).
  const fileRun = useRef(0)
  // One link and nothing else, also as "[title](address)", is that address: read and sent as a link.
  const onlyLink = loneLink(text)
  const sendText = onlyLink ?? text
  const { result, error } = useIntent(sendText, mode)
  const line = intentLine(result, addTarget)
  const empty = !text.trim()
  // Where the text came from: set from a paste (add/pasteOrigin.ts), changeable, '' = typed. A link
  // alone needs none (its address says where it lives), and an Ask files nothing.
  const [origin, setOrigin] = useState('')
  // The pasted text the origin was read from; once it has been in the box and is gone again, so is
  // the origin, and it comes back with the text (Ctrl+Z). "seen" waits for the paste to land (the
  // text changes after the paste event); "from" is the origin that belongs to the mark.
  const markRef = useRef({ mark: '', seen: false, from: '', lost: false })
  const setMark = (mark: string, from = '') => {
    markRef.current = { mark, seen: false, from, lost: false }
  }
  const showFrom = !empty && !onlyLink && mode !== 'ask' && result?.intent !== 'ask'
  useEffect(() => {
    const m = markRef.current
    const still = originStillApplies(text, m.mark)
    if (empty) {
      setOrigin('')
      setMark('')
    } else if (m.mark && still) {
      m.seen = true
      if (m.lost) {
        m.lost = false
        setOrigin(m.from)
      }
    } else if (m.seen && !still && !m.lost) {
      m.lost = true
      setOrigin('')
    }
  }, [empty, text])

  // A file let go beside the box must not make the browser open it in place of the app (the app
  // window has no Back, and everything in memory would be gone): outside the box a drop does nothing.
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
    setOrigin('') // a prefill (Save answer) is ObsidiNote's own text, not the earlier paste
    setMark('')
    area.current?.focus()
  }, [prefill])

  useEffect(() => {
    if (clearKey) {
      fileRun.current++
      setText('')
      setFileNote(null)
      setFileUrl(null)
    }
  }, [clearKey])

  // The box starts small (2 lines) and grows with its text up to about six lines, then scrolls
  // (operator, 2026-11-14), so the result and the lists under it stay in view.
  useEffect(() => {
    const el = area.current
    if (!el) return
    el.style.height = 'auto'
    el.style.height = `${el.scrollHeight}px`
  }, [text])

  // A file dropped on the box, or picked with "Add a file": its text is read here, in memory
  // (add/fileText.ts), and put in the box like a paste; nothing is stored or uploaded as a file.
  const [fileNote, setFileNote] = useState<{ text: string; error: boolean } | null>(null)
  const [dragging, setDragging] = useState(false)
  const picker = useRef<HTMLInputElement>(null)
  async function takeFile(file: File | undefined) {
    if (!file || busy) return
    const run = ++fileRun.current
    if (file.size > MAX_FILE_BYTES) {
      setFileNote({ text: 'This file is larger than 10 MB. Paste the part you want to keep instead.', error: true })
      return
    }
    setFileNote({ text: `Reading ${file.name}…`, error: false })
    const r = await readFileText(file.name, file.type, new Uint8Array(await file.arrayBuffer()))
    if (run !== fileRun.current) return
    if (!r.ok) {
      setFileNote({ text: r.message, error: true })
      return
    }
    setText(r.text)
    setMode('add') // a file is something to keep, never a question
    setOrigin('file')
    setMark(pasteMark(r.text), 'file')
    setFileUrl(null)
    const cut = r.message ? ` ${r.message}` : ''
    setFileNote({ text: `${file.name} is in the box.${cut} Looking for it in OneDrive…`, error: false })
    area.current?.focus()
    // Where the file lives online, when it is in a folder OneDrive syncs here (operator, 2026-11-14):
    // the Add then makes that file's link page and keeps its address.
    let found: LocateResult | null = null
    try {
      found = await locateFile(file.name, file.size, file.lastModified)
    } catch {
      found = null
    }
    // The box was sent or emptied, or another file came, while the lookup ran: this answer is late.
    if (run !== fileRun.current) return
    if (found?.status === 'found' && found.url) {
      setFileUrl({ url: found.url, text: r.text })
      setFileNote({ text: `${file.name} is in your OneDrive or SharePoint: the page keeps its link.${cut} Check the text, then press Add.`, error: false })
    } else {
      const why = found?.status === 'many' ? ' (more than one file matched, so no link is kept)' : ''
      setFileNote({ text: `${file.name} is in the box${why}.${cut} Check it, then press Add.`, error: false })
    }
  }
  // The address of the dropped file, for as long as the box still holds that file's text: the
  // "From" choice is "File" while it does (the mark above), so trimming a paragraph or fixing a
  // typo keeps the link (code review 2026-11-15: any edit dropped it without a word).
  const [fileUrl, setFileUrl] = useState<{ url: string; text: string } | null>(null)
  const liveFileUrl = fileUrl && origin === 'file' && !empty ? fileUrl.url : ''

  // Ask's options (what Ask reads) only when the text will be asked (operator, 2026-11-14).
  const asking = mode === 'ask' || (mode === 'auto' && result?.intent === 'ask')

  function send() {
    if (empty || busy || block?.disableSend) return
    fileRun.current++
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

  const LineIcon = result?.intent === 'ask' ? AskIcon : result?.intent === 'add' ? AddIcon : InfoIcon
  return (
    <section
      className="composer"
      aria-label="Add or ask"
      data-dragging={dragging || undefined}
      onDragOver={(e) => {
        const types = [...e.dataTransfer.types]
        if (!types.includes('Files') && !types.includes('text/uri-list')) return
        e.preventDefault()
        e.dataTransfer.dropEffect = 'copy'
        setDragging(true)
      }}
      onDragLeave={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDragging(false)
      }}
      onDrop={(e) => {
        setDragging(false)
        if (e.dataTransfer.files.length) {
          e.preventDefault()
          void takeFile(e.dataTransfer.files[0])
          return
        }
        // A link dragged from a browser tab (a OneDrive or SharePoint file, a web page): the same as
        // pasting it, so it becomes that address's link page.
        const link = (e.dataTransfer.getData('text/uri-list') || '').split(/\r?\n/).find((l) => /^https?:\/\//i.test(l.trim()))
        if (link) {
          e.preventDefault()
          setText(link.trim())
          setFileNote(null)
          area.current?.focus()
        }
      }}
    >
      {/* Left-aligned, the help next to it: one row of controls for the box (operator, 2026-11-14). */}
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
            <span><kbd>Ctrl</kbd> <kbd>K</kbd></span><span>Find a page or topic</span>
          </div>
        </div>
        {/* The drop's keyboard and touch path: the same reading, from a file picker. */}
        <button type="button" className="btn btn--sm btn--ghost composer__file-btn" onClick={() => picker.current?.click()} disabled={busy}>
          <FileIcon />
          Add a file
        </button>
        <input
          ref={picker}
          type="file"
          className="visually-hidden"
          tabIndex={-1}
          aria-hidden="true"
          accept=".docx,.docm,.pptx,.xlsx,.xlsm,.pdf,.msg,.eml,.txt,.md,.csv,.tsv,.json,.log,.html,.htm"
          onChange={(e) => {
            void takeFile(e.target.files?.[0])
            e.target.value = ''
          }}
        />
      </div>
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
        rows={2}
        value={text}
        placeholder="Paste a link or text, drop a file, or ask a question"
        onChange={(e) => setText(e.target.value)}
        onKeyDown={onKeyDown}
        onPaste={onPaste}
        autoFocus
        spellCheck
      />
      {fileUrl && !liveFileUrl && !empty && (
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
        <div className="composer__from">
          <label htmlFor="composer-from">From</label>
          <select id="composer-from" className="field composer__from-select" value={origin} onChange={(e) => {
              setOrigin(e.target.value)
              setMark('') // chosen by hand: it stays until the box is emptied
            }}>
            <option value="">{TYPED_LABEL}</option>
            {ORIGINS.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </select>
        </div>
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
        <button type="button" className="btn btn--primary composer__send" onClick={send} disabled={empty || busy || Boolean(block?.disableSend)} aria-busy={busy}>
          {busy ? 'Working…' : primaryLabel(result)}
        </button>
      </div>
      {asking && children}
    </section>
  )
}
