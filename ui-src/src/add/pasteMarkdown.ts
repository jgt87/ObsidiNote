// Pasted HTML (a web page, Word, a mail) -> Markdown, so the box keeps the text's structure and the
// server turns it into OneNote headings, lists and tables (lib/MarkdownLines.psm1). Pure: it walks a
// minimal DOM-like interface, so the browser feeds it DOMParser output and the tests build nodes by
// hand. Nothing here is stored; the result only goes into the text box.
//
// Output, in the shapes MarkdownLines reads: "# heading", "- item" / "1. item" (nested by indent),
// "**bold**", "_italic_" (underscores, so bold italic is "**_x_**", not "***x***"), "`code`", "~~strike~~",
// "[text](url)" for http(s)/mailto only, "> quote", fenced code, pipe tables with a separator row.
// Literal Markdown characters in the text are escaped with "\" (MarkdownLines restores them).

export interface PasteNode {
  nodeType: number
  nodeName: string
  childNodes: ArrayLike<PasteNode>
  textContent: string | null
  getAttribute?: (name: string) => string | null
}

const ELEMENT = 1
const TEXT = 3

/** Shown where an image was: images stay out of the text (like the Markdown export). */
export const IMAGE_LEFT_OUT = '_(image left out)_'

const DROP = new Set(['SCRIPT', 'STYLE', 'META', 'LINK', 'TITLE', 'HEAD', 'NOSCRIPT', 'TEMPLATE', 'XML', 'O:P', 'SVG', 'OBJECT', 'IFRAME', 'BUTTON', 'INPUT', 'SELECT', 'TEXTAREA'])
const IMAGES = new Set(['IMG', 'PICTURE', 'V:IMAGEDATA', 'V:SHAPE', 'CANVAS', 'VIDEO'])
const BLOCKS = new Set(['P', 'DIV', 'SECTION', 'ARTICLE', 'MAIN', 'HEADER', 'FOOTER', 'ASIDE', 'NAV', 'FIGURE', 'FIGCAPTION', 'BODY', 'HTML', 'CENTER', 'ADDRESS', 'DL', 'DT', 'DD', 'FORM', 'FIELDSET', 'DETAILS', 'SUMMARY', 'HR'])
const HEADINGS: Record<string, number> = { H1: 1, H2: 2, H3: 3, H4: 4, H5: 5, H6: 6 }
const LINK_SCHEMES = /^(https?:\/\/|mailto:)/i

function name(n: PasteNode): string {
  return n.nodeName.toUpperCase()
}

function attr(n: PasteNode, key: string): string {
  return (n.getAttribute ? n.getAttribute(key) : null) ?? ''
}

function kids(n: PasteNode): PasteNode[] {
  return Array.from(n.childNodes ?? [])
}

function style(n: PasteNode): string {
  return attr(n, 'style').toLowerCase().replace(/\s+/g, '')
}

/** Word's list bullets ("·", "1.") sit in a span marked mso-list:Ignore: they are not text. */
function isMsoJunk(n: PasteNode): boolean {
  return style(n).includes('mso-list:ignore')
}

/** A Word list paragraph: style "mso-list:l0 level2 lfo1". Its level, else 0. */
function msoListLevel(n: PasteNode): number {
  const m = /mso-list:l\d+level(\d+)/.exec(style(n))
  return m ? Number(m[1]) : 0
}

/** The Markdown marker of a Word list paragraph, from its own bullet text: "3." for "3.", "1." for
 *  "a)" or "iv.", "-" for a bullet glyph. */
function msoListMarker(n: PasteNode): string {
  const ignore = findFirst(n, isMsoJunk)
  const mark = (ignore?.textContent ?? '').replace(/[\s ]/g, '')
  const m = /^(\d+|[a-z]{1,4})[.)]$/i.exec(mark)
  if (!m) return '-'
  return /^\d+$/.test(m[1]) ? `${m[1]}.` : '1.'
}

function findFirst(n: PasteNode, test: (x: PasteNode) => boolean): PasteNode | null {
  for (const k of kids(n)) {
    if (k.nodeType !== ELEMENT) continue
    if (test(k)) return k
    const f = findFirst(k, test)
    if (f) return f
  }
  return null
}

function isBoldStyle(n: PasteNode): boolean | null {
  const m = /font-weight:(\w+)/.exec(style(n))
  if (!m) return null
  return m[1] === 'bold' || m[1] === 'bolder' || Number(m[1]) >= 600
}

function isItalicStyle(n: PasteNode): boolean | null {
  const m = /font-style:(\w+)/.exec(style(n))
  if (!m) return null
  return m[1] === 'italic' || m[1] === 'oblique'
}

// --- structure test -------------------------------------------------------------------------

/** True when the HTML holds structure worth keeping: headings, lists, tables, bold or italic, or
 *  links. Plain paragraphs alone are not (the plain text says the same). */
export function hasStructure(root: PasteNode): boolean {
  for (const k of kids(root)) {
    if (k.nodeType !== ELEMENT) continue
    const n = name(k)
    if (DROP.has(n) || isMsoJunk(k)) continue
    if (n in HEADINGS || n === 'UL' || n === 'OL' || n === 'LI' || n === 'TABLE' || n === 'I' || n === 'EM') return true
    if ((n === 'B' || n === 'STRONG') && isBoldStyle(k) !== false && (k.textContent ?? '').trim()) return true
    if (n === 'A' && LINK_SCHEMES.test(attr(k, 'href').trim())) return true
    if (msoListLevel(k) > 0) return true
    if (n === 'SPAN' && (isBoldStyle(k) || isItalicStyle(k)) && (k.textContent ?? '').trim()) return true
    if (hasStructure(k)) return true
  }
  return false
}

// --- inline ---------------------------------------------------------------------------------

interface Marks {
  bold: boolean
  italic: boolean
  strike: boolean
  code: boolean
  link: boolean
}

const NO_MARKS: Marks = { bold: false, italic: false, strike: false, code: false, link: false }

/** Escapes characters MarkdownLines would read as markup. A backslash only before such a character. */
export function escapeText(text: string): string {
  return text.replace(/\\(?=[\\`*_{}[\]()#+\-.!|~<>])/g, '\\\\').replace(/[*_`[\]~|<]/g, (c) => '\\' + c)
}

/** Wraps text in a marker, keeping its outer spaces outside ("** x**" would not read as bold). */
function wrap(text: string, open: string, close = open): string {
  const m = /^(\s*)([\s\S]*?)(\s*)$/.exec(text)!
  if (!m[2]) return text
  return m[1] + open + m[2] + close + m[3]
}

function inline(n: PasteNode, marks: Marks): string {
  if (n.nodeType === TEXT) {
    const t = (n.textContent ?? '').replace(/[\s\u00a0]+/g, ' ')
    return marks.code ? t.replace(/`/g, "'") : escapeText(t)
  }
  if (n.nodeType !== ELEMENT) return ''
  const tag = name(n)
  if (DROP.has(tag) || isMsoJunk(n)) return ''
  if (IMAGES.has(tag)) return ' ' + IMAGE_LEFT_OUT + ' '
  if (tag === 'BR') return '\n'
  const inner = (m: Marks) => kids(n).map((k) => inline(k, m)).join('')
  if (tag === 'A') {
    const href = attr(n, 'href').trim()
    if (marks.link || !LINK_SCHEMES.test(href)) return inner(marks)
    const label = inner({ ...marks, link: true }).replace(/\n/g, ' ')
    const url = href.replace(/ /g, '%20').replace(/\(/g, '%28').replace(/\)/g, '%29')
    const text = label.trim() ? label : escapeText(href)
    return wrap(text, '[', `](${url})`)
  }
  if (tag === 'CODE' || tag === 'KBD' || tag === 'SAMP' || tag === 'TT') {
    if (marks.code) return inner(marks)
    return wrap(inner({ ...marks, code: true }).replace(/\n/g, ' '), '`')
  }
  if (marks.code) return inner(marks)
  let bold = tag === 'B' || tag === 'STRONG'
  if (bold && isBoldStyle(n) === false) bold = false // Google Docs wraps everything in <b style="font-weight:normal">
  const bs = isBoldStyle(n)
  if (bs) bold = true
  const italic = tag === 'I' || tag === 'EM' || tag === 'CITE' || isItalicStyle(n) === true
  const strike = tag === 'S' || tag === 'DEL' || tag === 'STRIKE' || /text-decoration:[^;]*line-through/.test(style(n))
  let out = inner({ ...marks, bold: marks.bold || bold, italic: marks.italic || italic, strike: marks.strike || strike })
  if (strike && !marks.strike) out = wrapLines(out, '~~')
  if (italic && !marks.italic) out = wrapLines(out, '_')
  if (bold && !marks.bold) out = wrapLines(out, '**')
  return out
}

/** Markers never span a line break: each line is wrapped on its own. */
function wrapLines(text: string, marker: string): string {
  return text.split('\n').map((l) => wrap(l, marker)).join('\n')
}

function cleanLine(text: string): string {
  return text.replace(/[ \t]+/g, ' ').trim()
}

/** Inline content of an element as lines (a <br> starts a new line), spaces collapsed. */
function inlineLines(n: PasteNode, marks: Marks = NO_MARKS): string[] {
  return inline(n, marks).split('\n').map(cleanLine)
}

/** Escapes what would make a paragraph line read as a heading, quote or list item. */
function escapeLineStart(line: string): string {
  return line.replace(/^(#{1,6}\s|>|[-+]\s)/, '\\$1').replace(/^(\d+)([.)]\s)/, '$1\\$2')
}

// --- blocks ---------------------------------------------------------------------------------

type Block = string[] // lines of one block; blocks are joined with an empty line

interface Ctx {
  blocks: Block[]
  /** Inline content waiting for its block to end (text directly in a <div> or <body>). */
  pending: PasteNode[]
}

function flushPending(ctx: Ctx) {
  if (!ctx.pending.length) return
  const holder: PasteNode = { nodeType: ELEMENT, nodeName: 'SPAN', childNodes: ctx.pending, textContent: null }
  ctx.pending = []
  const lines = inlineLines(holder).filter((l, i, all) => l || (i > 0 && i < all.length - 1))
  if (lines.some((l) => l)) ctx.blocks.push(lines.map(escapeLineStart))
}

function isBlockish(n: PasteNode): boolean {
  if (n.nodeType !== ELEMENT) return false
  const t = name(n)
  return BLOCKS.has(t) || t in HEADINGS || t === 'UL' || t === 'OL' || t === 'LI' || t === 'TABLE' || t === 'PRE' || t === 'BLOCKQUOTE'
}

function walkBlocks(n: PasteNode, ctx: Ctx) {
  for (const k of kids(n)) {
    if (k.nodeType === ELEMENT && (DROP.has(name(k)) || isMsoJunk(k))) continue
    if (!isBlockish(k)) {
      if (k.nodeType === ELEMENT || k.nodeType === TEXT) ctx.pending.push(k)
      continue
    }
    flushPending(ctx)
    block(k, ctx)
  }
  flushPending(ctx)
}

function block(n: PasteNode, ctx: Ctx) {
  const t = name(n)
  if (t in HEADINGS) {
    const text = inlineLines(n).filter(Boolean).join(' ')
    if (text) ctx.blocks.push(['#'.repeat(HEADINGS[t]) + ' ' + text])
    return
  }
  if (t === 'UL' || t === 'OL') {
    const lines = listLines(n, 0)
    if (lines.length) ctx.blocks.push(lines)
    return
  }
  if (t === 'LI') {
    const lines = itemLines(n, '-', 0)
    if (lines.length) ctx.blocks.push(lines)
    return
  }
  if (t === 'TABLE') {
    const lines = tableLines(n)
    if (lines.length) ctx.blocks.push(lines)
    return
  }
  if (t === 'PRE') {
    const code = (n.textContent ?? '').replace(/\r\n?/g, '\n').replace(/\n+$/, '').replace(/^```/gm, "'''")
    if (code.trim()) ctx.blocks.push(['```', ...code.split('\n'), '```'])
    return
  }
  if (t === 'BLOCKQUOTE') {
    const inner: Ctx = { blocks: [], pending: [] }
    walkBlocks(n, inner)
    const lines = inner.blocks.flat().filter(Boolean).map((l) => '> ' + l.replace(/^>\s?/, ''))
    if (lines.length) ctx.blocks.push(lines)
    return
  }
  if (t === 'HR') return
  if (msoListLevel(n) > 0) {
    // Word: each list item is a paragraph; consecutive ones join into one list block.
    const level = msoListLevel(n) - 1
    const marker = msoListMarker(n)
    const text = inlineLines(n).filter(Boolean).join(' ')
    if (!text) return
    const line = ' '.repeat(level * 3) + marker + ' ' + text
    const last = ctx.blocks[ctx.blocks.length - 1]
    if (last && (last as Block & { mso?: boolean }).mso) last.push(line)
    else ctx.blocks.push(Object.assign([line], { mso: true }))
    return
  }
  walkBlocks(n, ctx)
}

/** A list's items; nested lists are indented under their item by the item's marker width. */
function listLines(list: PasteNode, indent: number): string[] {
  const out: string[] = []
  let number = Number(attr(list, 'start')) || 1
  for (const k of kids(list)) {
    if (k.nodeType !== ELEMENT) continue
    const t = name(k)
    if (t === 'LI') {
      const marker = name(list) === 'OL' ? `${number++}.` : '-'
      out.push(...itemLines(k, marker, indent))
    } else if (t === 'UL' || t === 'OL') {
      out.push(...listLines(k, indent + 2)) // a list straight inside a list (invalid, but pasted)
    }
  }
  return out
}

function itemLines(li: PasteNode, marker: string, indent: number): string[] {
  const textNodes: PasteNode[] = []
  const nested: PasteNode[] = []
  for (const k of kids(li)) {
    const t = k.nodeType === ELEMENT ? name(k) : ''
    if (t === 'UL' || t === 'OL') nested.push(k)
    else textNodes.push(k)
  }
  const holder: PasteNode = { nodeType: ELEMENT, nodeName: 'SPAN', childNodes: textNodes, textContent: null }
  // Paragraphs inside an item (<li><p>..</p></li>) become one line: an item is one line in OneNote.
  const text = blockText(holder)
  const out = [' '.repeat(indent) + marker + ' ' + text]
  for (const l of nested) out.push(...listLines(l, indent + marker.length + 1))
  return out
}

/** Text of mixed inline and block content as one line (list items, table cells). */
function blockText(n: PasteNode): string {
  const parts: string[] = []
  let run: PasteNode[] = []
  const flush = () => {
    if (!run.length) return
    parts.push(...inlineLines({ nodeType: ELEMENT, nodeName: 'SPAN', childNodes: run, textContent: null }))
    run = []
  }
  for (const k of kids(n)) {
    if (k.nodeType === ELEMENT && (DROP.has(name(k)) || isMsoJunk(k))) continue
    if (isBlockish(k) && name(k) !== 'TABLE') {
      flush()
      parts.push(blockText(k))
    } else if (k.nodeType === ELEMENT && name(k) === 'TABLE') {
      flush()
      parts.push(IMAGE_LEFT_OUT.replace('image', 'table'))
    } else run.push(k)
  }
  flush()
  return parts.map(cleanLine).filter(Boolean).join(' ')
}

function rowsOf(table: PasteNode): PasteNode[] {
  const rows: PasteNode[] = []
  const visit = (n: PasteNode) => {
    for (const k of kids(n)) {
      if (k.nodeType !== ELEMENT) continue
      const t = name(k)
      if (t === 'TR') rows.push(k)
      else if (t === 'THEAD' || t === 'TBODY' || t === 'TFOOT') visit(k)
    }
  }
  visit(table)
  return rows
}

function tableLines(table: PasteNode): string[] {
  const rows = rowsOf(table)
    .map((r) => kids(r).filter((c) => c.nodeType === ELEMENT && (name(c) === 'TD' || name(c) === 'TH')).map((c) => blockText(c) || ' '))
    .filter((cells) => cells.length)
  if (!rows.length) return []
  const width = Math.max(...rows.map((r) => r.length))
  const line = (cells: string[]) => '| ' + [...cells, ...Array(width - cells.length).fill(' ')].map((c) => c.trim() || ' ').join(' | ') + ' |'
  return [line(rows[0]), '| ' + Array(width).fill('---').join(' | ') + ' |', ...rows.slice(1).map(line)]
}

/** Pasted HTML's body -> Markdown text. */
export function htmlToMarkdown(root: PasteNode): string {
  const ctx: Ctx = { blocks: [], pending: [] }
  walkBlocks(root, ctx)
  return ctx.blocks
    .map((b) => b.join('\n'))
    .join('\n\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
}

// The server converts a text only when Test-MarkdownText (lib/MarkdownLines.psm1) says it holds
// Markdown; these are its two patterns. Otherwise the text is added as plain lines, and the escapes
// and underscores made here would show. tests/fixtures/paste-markdown.json ("markdownText") pins both
// sides to the same answers.
const MD_BLOCK = /^\s{0,3}(#{1,6}\s+\S|```|~~~|>\s|([-*+]|\d+[.)])\s+\S|\|.*\|\s*$)/m
const MD_INLINE = /\*\*[^*\s][^*]*\*\*|__[^_\s][^_]*__|`[^`\r\n]+`|\[[^\]\r\n]+\]\([^)\s]+\)|~~[^~\s][^~]*~~/

/** True when the server will read the text as Markdown (mirror of Test-MarkdownText). */
export function looksLikeMarkdown(text: string): boolean {
  return MD_BLOCK.test(text) || MD_INLINE.test(text)
}

/** What a paste puts in the box: Markdown when the HTML has structure the server will keep, else
 *  null (the plain text, as the browser pastes it). parse is DOMParser in the browser. */
export function markdownForPaste(html: string, parse: (html: string) => PasteNode | null): string | null {
  if (!html.trim()) return null
  const root = parse(html)
  if (!root || !hasStructure(root)) return null
  const md = htmlToMarkdown(root)
  return md && looksLikeMarkdown(md) ? md : null
}
