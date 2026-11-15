// Web links in the interface (operator, 2026-11-13): send the person to the real source, and to
// OneNote as little as possible. A link page opens its original address; an address in an answer is
// clickable. Only http(s) ever becomes a link (no javascript:, file:, onenote: here). Pure.

/** The address when it is an http(s) URL, else ''. */
/**
 * The address when the text is one link and nothing else: a bare address, or one Markdown link
 * "[title](address)"; else null. A link copied from the browser (Edge's "Copy link") arrives as
 * a titled link; kept as Markdown it read as "a link and other text", so it was not taken as a
 * link page and "From" guessed "Web page" for a SharePoint address (operator, 2026-11-15).
 */
export function loneLink(text: string): string | null {
  const t = text.trim()
  if (/^https?:\/\/\S+$/i.test(t)) return t
  const m = /^\[[^\]\n]*\]\((https?:\/\/[^\s()]+(?:\([^\s()]*\)[^\s()]*)*)\)$/i.exec(t)
  return m ? m[1] : null
}

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
