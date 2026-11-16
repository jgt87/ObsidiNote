import { useEffect, useRef, useState, type ClipboardEvent as ReactClipboardEvent, type KeyboardEvent as ReactKeyboardEvent } from 'react'
import { markdownForPaste, type PasteNode } from '../add/pasteMarkdown'
import { followMark, newMark, originOfPaste, pasteMark } from '../add/pasteOrigin'
import { isPlainPasteKey } from '../model/keys'

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

/**
 * Where the box's text came from, the "From" choice ('' = typed; model/origins.ts): read from a
 * paste's HTML (add/pasteOrigin.ts), set to "File" for a file's text, or chosen by hand. The paste
 * it was read from is remembered: when that text leaves the box, so does the origin, and it comes
 * back with it (followMark). A paste from a web page, Word or a mail comes in as Markdown with its
 * structure (headings, lists, tables, bold, links), which the server turns into OneNote formatting;
 * Ctrl+Shift+V pastes plain.
 */
export function usePasteOrigin(text: string, setText: (t: string) => void) {
  const [origin, setOrigin] = useState('')
  const markRef = useRef(newMark())
  const plainPasteAt = useRef(0)
  const setMark = (mark: string, from = '') => {
    markRef.current = newMark(mark, from)
  }

  useEffect(() => {
    const next = followMark(markRef.current, text)
    markRef.current = next.mark
    if (next.origin !== undefined) setOrigin(next.origin)
  }, [text])

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

  return {
    origin,
    onPaste,
    /** On every key in the box: Ctrl+Shift+V makes the next paste plain. */
    notePlainPaste: (e: ReactKeyboardEvent<HTMLTextAreaElement>) => {
      if (isPlainPasteKey(e)) plainPasteAt.current = Date.now()
    },
    /** Chosen by hand: it stays until the box is emptied. */
    choose: (o: string) => {
      setOrigin(o)
      setMark('')
    },
    /** A file's text is in the box: "File", for as long as that text is. */
    fromFile: (fileText: string) => {
      setOrigin('file')
      setMark(pasteMark(fileText), 'file')
    },
    /** ObsidiNote's own text (a prefill such as Save answer), not the earlier paste. */
    clear: () => {
      setOrigin('')
      setMark('')
    },
  }
}
