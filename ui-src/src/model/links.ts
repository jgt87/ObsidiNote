// Web links in the interface (operator, 2026-11-13): send the person to the real source, and to
// OneNote as little as possible. A link page opens its original address; an address in an answer is
// clickable. Only http(s) ever becomes a link (no javascript:, file:, onenote: here). Pure.

/** The address when it is an http(s) URL, else ''. */
export function webUrl(value: string | null | undefined): string {
  const v = (value ?? '').trim()
  return /^https?:\/\/[^\s/?#]+/i.test(v) ? v : ''
}

export interface TextPart {
  text: string
  /** Set when this part is a web address. */
  href?: string
}

// An address runs to the next space or bracket; sentence punctuation right after it is not part of it.
const URL_RE = /https?:\/\/[^\s<>"'()[\]{}]+/gi
const TRAILING = /[.,;:!?]+$/

/** Splits text into plain parts and http(s) addresses, in order; joining the texts gives the input back. */
export function splitLinks(text: string): TextPart[] {
  const parts: TextPart[] = []
  let last = 0
  for (const m of text.matchAll(URL_RE)) {
    const start = m.index ?? 0
    const url = m[0].replace(TRAILING, '')
    if (!webUrl(url)) continue
    if (start > last) parts.push({ text: text.slice(last, start) })
    parts.push({ text: url, href: url })
    last = start + url.length
  }
  if (last < text.length) parts.push({ text: text.slice(last) })
  return parts
}
