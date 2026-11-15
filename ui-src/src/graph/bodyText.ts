// The page's text for the page window: the Markdown the server makes (GET /api/page/body,
// lib/MarkdownExport.psm1 Get-PageBody) turned into blocks to draw. Pure (tests: bodyText.test.ts,
// on tests/fixtures/page-body.json, which the server's test compares with its own output: change
// both together). Only what the server writes is read: #/##/### headings, paragraphs, "- " and
// "1. " lists (nested by four spaces, "[ ]"/"[x]" tasks), tables, and inside a line **bold**,
// *italic* or _italic_, ~~strike~~, `code`, [text](address) and backslash escapes.
// The text is never treated as HTML: it becomes text nodes. A link is only kept for a page of the
// map (obsn:<id>) or an http, https, mailto or onenote address; anything else stays plain text.

export interface Part {
  text: string
  bold?: boolean
  italic?: boolean
  strike?: boolean
  code?: boolean
  /** A page of the map (the graph's page id). */
  pageId?: string
  /** An address to open: http(s), mailto or onenote only. */
  href?: string
}

export interface ListItem {
  parts: Part[]
  depth: number
  /** A task: true = done, false = open; undefined = a plain item. */
  done?: boolean
}

export type Block =
  | { kind: 'heading'; level: 1 | 2 | 3; parts: Part[] }
  | { kind: 'para'; parts: Part[] }
  | { kind: 'list'; ordered: boolean; items: ListItem[] }
  | { kind: 'table'; head: Part[][]; rows: Part[][][] }

const SAFE = /^(https?:|mailto:|onenote:)/i

/** Where a link leads: a page of the map, an address that may be opened, or nothing (plain text). */
export function linkTarget(dest: string): { pageId?: string; href?: string } {
  if (dest.startsWith('obsn:')) return dest.length > 5 ? { pageId: dest.slice(5) } : {}
  return SAFE.test(dest) ? { href: dest } : {}
}

type Style = Pick<Part, 'bold' | 'italic' | 'strike' | 'pageId' | 'href'>

/** One line of text into styled parts. */
export function inlineParts(text: string, base: Style = {}): Part[] {
  const out: Part[] = []
  let buf = ''
  let style: Style = { ...base }
  const flush = () => {
    if (buf) out.push({ text: buf, ...clean(style) })
    buf = ''
  }
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (c === '\\' && i + 1 < text.length) {
      buf += text[++i]
    } else if (c === '`') {
      const end = text.indexOf('`', i + 1)
      if (end < 0) {
        buf += c
        continue
      }
      flush()
      out.push({ text: text.slice(i + 1, end), code: true, ...clean(style) })
      i = end
    } else if (c === '*' && text[i + 1] === '*') {
      flush()
      style = { ...style, bold: !style.bold }
      i++
    } else if (c === '~' && text[i + 1] === '~') {
      flush()
      style = { ...style, strike: !style.strike }
      i++
    } else if (c === '*' || c === '_') {
      flush()
      style = { ...style, italic: !style.italic }
    } else if (c === '[') {
      const link = readLink(text, i)
      if (!link) {
        buf += c
        continue
      }
      flush()
      out.push(...inlineParts(link.label, { ...style, ...linkTarget(link.dest) }))
      i = link.end
    } else {
      buf += c
    }
  }
  flush()
  return out
}

function clean(s: Style): Style {
  const o: Style = {}
  if (s.bold) o.bold = true
  if (s.italic) o.italic = true
  if (s.strike) o.strike = true
  if (s.pageId) o.pageId = s.pageId
  if (s.href) o.href = s.href
  return o
}

/** "[label](dest)" starting at `at`: the label (still Markdown), the address, and the index of
 *  the closing ")". The server encodes spaces and brackets in the address, so it ends at the
 *  first ")". null when this "[" does not start a link. */
function readLink(text: string, at: number): { label: string; dest: string; end: number } | null {
  let i = at + 1
  for (; i < text.length; i++) {
    if (text[i] === '\\') i++
    else if (text[i] === ']') break
  }
  if (i >= text.length || text[i + 1] !== '(') return null
  const close = text.indexOf(')', i + 2)
  if (close < 0) return null
  return { label: text.slice(at + 1, i), dest: text.slice(i + 2, close), end: close }
}

const LIST = /^( *)(- |\d+\. )(.*)$/
const HEADING = /^(#{1,3}) (.*)$/

/** A table row into its cells (split on "|" that is not escaped). */
function cells(line: string): string[] {
  const out: string[] = []
  let cur = ''
  for (let i = 0; i < line.length; i++) {
    if (line[i] === '\\' && i + 1 < line.length) cur += line[i] + line[++i]
    else if (line[i] === '|') {
      out.push(cur)
      cur = ''
    } else cur += line[i]
  }
  out.push(cur)
  return out.slice(1, -1).map((c) => c.trim())
}

/** The page text as blocks. '' gives no blocks. */
export function bodyBlocks(markdown: string): Block[] {
  const blocks: Block[] = []
  for (const chunk of markdown.replace(/\r\n/g, '\n').split(/\n{2,}/)) {
    const lines = chunk.split('\n').filter((l) => l.trim() !== '')
    if (!lines.length) continue
    const heading = lines.length === 1 ? HEADING.exec(lines[0]) : null
    if (heading) {
      blocks.push({ kind: 'heading', level: heading[1].length as 1 | 2 | 3, parts: inlineParts(heading[2]) })
    } else if (lines.every((l) => LIST.test(l))) {
      const items: ListItem[] = lines.map((l) => {
        const m = LIST.exec(l)!
        const task = /^\[( |x)\] (.*)$/.exec(m[3])
        return { depth: Math.floor(m[1].length / 4), parts: inlineParts(task ? task[2] : m[3]), ...(task ? { done: task[1] === 'x' } : {}) }
      })
      blocks.push({ kind: 'list', ordered: /^\d/.test(LIST.exec(lines[0])![2]), items })
    } else if (lines.length >= 2 && lines.every((l) => l.startsWith('|')) && /^\|( *-{3,} *\|)+$/.test(lines[1])) {
      const rows = lines.filter((_, i) => i !== 1).map((l) => cells(l).map((c) => inlineParts(c)))
      blocks.push({ kind: 'table', head: rows[0], rows: rows.slice(1) })
    } else {
      blocks.push({ kind: 'para', parts: inlineParts(lines.join('\n')) })
    }
  }
  return blocks
}
