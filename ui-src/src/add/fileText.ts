// A file dropped on the Add box -> its text, read in memory in the browser, so the Add flow can file
// it as a page like pasted text. Pure: bytes in, text out. Nothing is stored or sent from here; the
// file's bytes and text live only in memory until the person submits the text (AGENTS.md: OneNote
// is the only store).
//
// No libraries: Word, PowerPoint and Excel files are ZIP archives of XML (own small ZIP reader,
// deflate through the browser's DecompressionStream); Outlook .msg files are OLE compound files (own
// small reader); PDFs are read best effort (text operators in Flate content streams, no font
// decoding); .eml, text and HTML are plain string work. Every failure is a plain-English message
// for the person, never a throw.

export const MAX_FILE_BYTES = 10 * 1024 * 1024
export const MAX_TEXT_CHARS = 60_000
/** Cap on what a file may unpack to (ZIP entries, PDF streams), against zip bombs. */
const MAX_UNPACKED_BYTES = 50 * 1024 * 1024
const MAX_SHEET_ROWS = 2000
/** A PDF whose text has fewer letters than this is treated as having no readable text. */
const MIN_PDF_LETTERS = 10

export type FileKind = 'word' | 'powerpoint' | 'excel' | 'pdf' | 'mail' | 'text' | 'web'

export interface FileTextResult {
  ok: boolean
  kind: FileKind | null
  /** Text to add: first line "File: <name>", a blank line, then the extracted text. '' when !ok. */
  text: string
  /** Shown to the person when !ok (what happened + what to do), or a note when ok (e.g. "Cut at 60,000 characters."). */
  message: string
}

const LABEL: Record<FileKind, string> = {
  word: 'Word document',
  powerpoint: 'PowerPoint file',
  excel: 'Excel file',
  pdf: 'PDF',
  mail: 'mail message',
  text: 'text file',
  web: 'web page',
}

const BY_EXTENSION: Record<string, FileKind> = {
  docx: 'word', docm: 'word', dotx: 'word',
  pptx: 'powerpoint', pptm: 'powerpoint', ppsx: 'powerpoint',
  xlsx: 'excel', xlsm: 'excel',
  pdf: 'pdf',
  msg: 'mail', eml: 'mail',
  txt: 'text', md: 'text', markdown: 'text', csv: 'text', tsv: 'text', json: 'text', log: 'text',
  html: 'web', htm: 'web',
}

const BY_MIME: Record<string, FileKind> = {
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'word',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'powerpoint',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'excel',
  'application/pdf': 'pdf',
  'application/vnd.ms-outlook': 'mail',
  'message/rfc822': 'mail',
  'text/plain': 'text', 'text/markdown': 'text', 'text/csv': 'text', 'text/tab-separated-values': 'text',
  'application/json': 'text',
  'text/html': 'web',
}

const MSG_TOO_LARGE = 'This file is larger than 10 MB. Paste the part you want to keep instead.'
const MSG_BOMB = 'This file unpacks to more than 50 MB, which is too much to read here. Paste the part you want to keep instead.'
const MSG_PASSWORD = 'This file is protected with a password. Open it, save a copy without the password, or paste the text instead.'
const MSG_ZIP64 = 'This file is too large inside to read here. Open it and paste the part you want to keep instead.'
const MSG_PDF_NO_TEXT = 'This PDF has no text that can be read (it may be a scan or use special fonts). Open it and paste the text instead.'
const MSG_MSG_NO_BODY = 'This Outlook message has no plain-text body that can be read. Open it and copy the text instead.'

/** A failure whose message is meant for the person as it is. */
class FileTextError extends Error {}

function extensionOf(name: string): string {
  const base = name.split(/[\\/]/).pop() ?? ''
  const dot = base.lastIndexOf('.')
  return dot > 0 ? base.slice(dot + 1).toLowerCase() : ''
}

/** The kind of a file by its extension (or, without one, its media type); null when it can't be read. */
export function fileKindOf(name: string, mime: string): FileKind | null {
  const ext = extensionOf(name)
  if (ext) return BY_EXTENSION[ext] ?? null
  return BY_MIME[(mime || '').split(';')[0].trim().toLowerCase()] ?? null
}

function unsupportedMessage(name: string, mime: string): string {
  const ext = extensionOf(name)
  const old: Record<string, string> = { doc: 'docx', xls: 'xlsx', ppt: 'pptx', dot: 'docx', pps: 'pptx' }
  if (old[ext]) return `Old .${ext} files can't be read here. Save it as .${old[ext]} first, or paste the text.`
  const images = ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'heic', 'heif', 'tif', 'tiff', 'ico', 'svg']
  if (images.includes(ext) || mime.startsWith('image/')) return "Image files can't be read here. Open it and paste the text instead."
  if (['zip', '7z', 'rar', 'gz', 'tar', 'cab'].includes(ext)) return "Zip files can't be read here. Unpack it and add one file at a time."
  if (['exe', 'dll', 'msi', 'com', 'scr', 'sys'].includes(ext)) return "Program files can't be read here."
  if (['mp3', 'mp4', 'wav', 'm4a', 'mov', 'avi', 'wmv', 'webm', 'ogg'].includes(ext) || /^(audio|video)\//.test(mime)) {
    return "Audio and video files can't be read here. Paste a written summary instead."
  }
  if (ext === 'rtf') return "RTF files can't be read here. Save it as .docx first, or paste the text."
  return ext
    ? `.${ext} files can't be read here. Open it and paste the text instead.`
    : "This kind of file can't be read here. Open it and paste the text instead."
}

function fail(kind: FileKind | null, message: string): FileTextResult {
  return { ok: false, kind, text: '', message }
}

interface Extracted {
  text: string
  notes: string[]
}

/** Reads a file's text in memory. Never throws: a failure is `{ ok: false, message }`. */
export async function readFileText(name: string, mime: string, bytes: Uint8Array): Promise<FileTextResult> {
  let kind: FileKind | null = null
  try {
    kind = fileKindOf(name ?? '', mime ?? '')
    if (bytes.length > MAX_FILE_BYTES) return fail(kind, MSG_TOO_LARGE)
    if (!kind) return fail(null, unsupportedMessage(name ?? '', (mime ?? '').toLowerCase()))
    if (bytes.length === 0) return fail(kind, `This ${LABEL[kind]} is empty. Pick another file or paste the text instead.`)
    const got = await EXTRACT[kind](bytes)
    let text = tidy(got.text)
    if (!text) return fail(kind, `This ${LABEL[kind]} has no text that can be read. Open it and paste the text instead.`)
    const notes = [...got.notes]
    if (text.length > MAX_TEXT_CHARS) {
      let end = MAX_TEXT_CHARS
      const code = text.charCodeAt(end - 1)
      if (code >= 0xd800 && code <= 0xdbff) end -= 1
      text = `${text.slice(0, end).trimEnd()}\n\n[Cut at 60,000 characters.]`
      notes.push('Cut at 60,000 characters.')
    }
    return { ok: true, kind, text: `File: ${cleanName(name)}\n\n${text}`, message: notes.join(' ') }
  } catch (e) {
    if (e instanceof FileTextError) return fail(kind, e.message)
    const label = kind ? LABEL[kind] : 'file'
    return fail(kind, `This ${label} could not be read; it may be damaged. Open it and paste the text instead.`)
  }
}

function cleanName(name: string): string {
  const base = (name ?? '').split(/[\\/]/).pop() ?? ''
  return base.replace(/[\u0000-\u001f\u007f]+/g, ' ').trim() || 'file'
}

const EXTRACT: Record<FileKind, (b: Uint8Array) => Promise<Extracted>> = {
  word: readDocx,
  powerpoint: readPptx,
  excel: readXlsx,
  pdf: readPdf,
  mail: async (b) => (isCfb(b) ? readMsg(b) : readEml(b)),
  text: async (b) => ({ text: decodeText(b), notes: [] }),
  web: async (b) => ({ text: htmlToText(decodeText(b)), notes: [] }),
}

// ---------------------------------------------------------------- text helpers

/** Line endings to \n, no control characters, no trailing spaces, at most two blank lines in a row. */
function tidy(text: string): string {
  return text
    .replace(/\r\n?/g, '\n')
    .replace(/ /g, ' ')
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '')
    .replace(/[ \t]+$/gm, '')
    .replace(/\n{4,}/g, '\n\n\n')
    .trim()
}

function latin1(bytes: Uint8Array): string {
  let s = ''
  for (let i = 0; i < bytes.length; i += 8192) {
    s += String.fromCharCode(...bytes.subarray(i, i + 8192))
  }
  return s
}

function latin1Bytes(s: string): Uint8Array {
  const out = new Uint8Array(s.length)
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff
  return out
}

function decodeWith(bytes: Uint8Array, charset: string): string {
  try {
    return new TextDecoder(charset || 'utf-8').decode(bytes)
  } catch {
    return new TextDecoder('utf-8').decode(bytes)
  }
}

/** UTF-8 when it is valid, else Windows-1252 (old Windows text). */
function utf8OrAnsi(bytes: Uint8Array): string {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes)
  } catch {
    return decodeWith(bytes, 'windows-1252')
  }
}

/** A text file's bytes -> string, by its byte order mark (UTF-8 / UTF-16), else UTF-8 or Windows-1252. */
function decodeText(bytes: Uint8Array): string {
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) return decodeWith(bytes.subarray(3), 'utf-8')
  if (bytes[0] === 0xff && bytes[1] === 0xfe) return decodeWith(bytes.subarray(2), 'utf-16le')
  if (bytes[0] === 0xfe && bytes[1] === 0xff) return decodeWith(bytes.subarray(2), 'utf-16be')
  return utf8OrAnsi(bytes)
}

const ENTITIES: Record<string, string> = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ndash: '–', mdash: '—',
  hellip: '…', lsquo: '‘', rsquo: '’', ldquo: '“', rdquo: '”', bull: '•',
  middot: '·', copy: '©', reg: '®', trade: '™', euro: '€', laquo: '«',
  raquo: '»', times: '×', divide: '÷', deg: '°', shy: '',
}

function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+\d*);/gi, (all, body: string) => {
    if (body[0] === '#') {
      const code = body[1] === 'x' || body[1] === 'X' ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10)
      return code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff) ? String.fromCodePoint(code) : ''
    }
    return ENTITIES[body.toLowerCase()] ?? all
  })
}

/** HTML -> plain text: no scripts or styles, block tags become line breaks, entities decoded. */
function htmlToText(html: string): string {
  let s = html.replace(/<!--[\s\S]*?-->/g, '')
  s = s.replace(/<(script|style|noscript|template|svg|head|object|iframe)\b[\s\S]*?<\/\1\s*>/gi, ' ')
  s = s.replace(/\s+/g, ' ')
  s = s.replace(/<br\b[^>]*>/gi, '\n')
  s = s.replace(/<li\b[^>]*>/gi, '\n- ')
  s = s.replace(/<\/li\s*>/gi, '')
  s = s.replace(/<\/?(p|div|h[1-6]|ul|ol|tr|table|thead|tbody|tfoot|caption|section|article|header|footer|nav|aside|main|blockquote|pre|hr|dl|dt|dd|figure|figcaption|form|fieldset|address|title|center|details|summary)\b[^>]*>/gi, '\n')
  s = s.replace(/<\/(td|th)\s*>/gi, '\t')
  s = s.replace(/<[^>]*>/g, '')
  s = decodeEntities(s)
  return s
    .split('\n')
    .map((line) => line.replace(/[ \f\v ]+/g, ' ').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
}

interface XmlTextRules {
  text: Set<string>
  para?: Set<string>
  tab?: Set<string>
  br?: Set<string>
  skip?: Set<string>
  /** Compare tag names without their namespace prefix. */
  local?: boolean
}

/** What a tag adds to the text outside skipped elements: a line break at a paragraph's end, a tab,
 *  or a line break for a break element; '' for any other tag. */
function tagText(rules: XmlTextRules, name: string, closing: boolean, selfClosing: boolean): string {
  if (rules.para?.has(name) && (closing || selfClosing)) return '\n'
  if (rules.tab?.has(name) && !closing) return '\t'
  if (rules.br?.has(name) && !closing) return '\n'
  return ''
}

/** Text inside the given XML elements; paragraph ends give line breaks. Pure string work. */
function xmlText(xml: string, rules: XmlTextRules): string {
  const re = /<!\[CDATA\[([\s\S]*?)\]\]>|<[!?][^>]*>|<(\/?)([A-Za-z_][\w:.-]*)[^>]*?(\/?)>|([^<]+)/g
  let out = ''
  let inText = 0
  let skip = 0
  let m: RegExpExecArray | null
  while ((m = re.exec(xml))) {
    const reading = inText > 0 && skip === 0
    if (m[1] !== undefined || m[5] !== undefined) {
      if (reading) out += m[1] !== undefined ? m[1] : decodeEntities(m[5])
      continue
    }
    if (m[3] === undefined) continue
    const closing = m[2] === '/'
    const selfClosing = m[4] === '/'
    const step = selfClosing ? 0 : closing ? -1 : 1
    const name = rules.local ? m[3].replace(/^[^:]*:/, '') : m[3]
    if (rules.skip?.has(name)) skip += step
    else if (rules.text.has(name)) inText = Math.max(0, inText + step)
    else if (skip === 0) out += tagText(rules, name, closing, selfClosing)
  }
  return out
}

// ---------------------------------------------------------------- inflate

async function inflate(data: Uint8Array, format: 'deflate' | 'deflate-raw', limit: number, tolerant = false): Promise<Uint8Array> {
  const ds = new DecompressionStream(format)
  const writer = ds.writable.getWriter()
  writer.write(new Uint8Array(data)).catch(() => {})
  writer.close().catch(() => {})
  const reader = ds.readable.getReader()
  const chunks: Uint8Array[] = []
  let total = 0
  try {
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      total += value.length
      if (total > limit) {
        reader.cancel().catch(() => {})
        throw new FileTextError(MSG_BOMB)
      }
      chunks.push(value)
    }
  } catch (e) {
    if (e instanceof FileTextError || !tolerant || total === 0) throw e
  }
  return concat(chunks, total)
}

function concat(chunks: Uint8Array[], total = chunks.reduce((n, c) => n + c.length, 0)): Uint8Array {
  const out = new Uint8Array(total)
  let at = 0
  for (const c of chunks) {
    out.set(c, at)
    at += c.length
  }
  return out
}

const u16 = (b: Uint8Array, o: number): number => b[o] | (b[o + 1] << 8)
const u32 = (b: Uint8Array, o: number): number => (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0

// ---------------------------------------------------------------- ZIP (Word, PowerPoint, Excel)

interface ZipEntry {
  name: string
  method: number
  compSize: number
  size: number
  localOffset: number
}

interface Zip {
  bytes: Uint8Array
  /** Entries by lower-case name. */
  entries: Map<string, ZipEntry>
  budget: { left: number }
}

/** The end-of-central-directory record: searched backwards over the last 64 KB (its comment). */
function findEndRecord(bytes: Uint8Array): number {
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 22 - 0xffff); i--) {
    if (u32(bytes, i) === 0x06054b50) return i
  }
  throw new Error('not a zip')
}

/** One central-directory entry at `p`, and where the next one starts. Refuses ZIP64 sizes and
 *  encrypted entries with a message the person can act on. */
function readCentralEntry(bytes: Uint8Array, p: number): { entry: ZipEntry; next: number } {
  if (p + 46 > bytes.length || u32(bytes, p) !== 0x02014b50) throw new Error('bad central directory')
  const flags = u16(bytes, p + 8)
  const method = u16(bytes, p + 10)
  const compSize = u32(bytes, p + 20)
  const size = u32(bytes, p + 24)
  const nameLen = u16(bytes, p + 28)
  const extraLen = u16(bytes, p + 30)
  const commentLen = u16(bytes, p + 32)
  const localOffset = u32(bytes, p + 42)
  const name = new TextDecoder('utf-8').decode(bytes.subarray(p + 46, p + 46 + nameLen)).replace(/\\/g, '/')
  if (compSize === 0xffffffff || size === 0xffffffff || localOffset === 0xffffffff) throw new FileTextError(MSG_ZIP64)
  if (flags & 1) throw new FileTextError(MSG_PASSWORD)
  return { entry: { name, method, compSize, size, localOffset }, next: p + 46 + nameLen + extraLen + commentLen }
}

function openZip(bytes: Uint8Array): Zip {
  if (isCfb(bytes)) throw new FileTextError(MSG_PASSWORD)
  const eocd = findEndRecord(bytes)
  if (eocd >= 20 && u32(bytes, eocd - 20) === 0x07064b50) throw new FileTextError(MSG_ZIP64)
  const count = u16(bytes, eocd + 10)
  const cdOffset = u32(bytes, eocd + 16)
  if (count === 0xffff || cdOffset === 0xffffffff) throw new FileTextError(MSG_ZIP64)
  const entries = new Map<string, ZipEntry>()
  let declared = 0
  let p = cdOffset
  for (let i = 0; i < count; i++) {
    const { entry, next } = readCentralEntry(bytes, p)
    declared += entry.size
    if (declared > MAX_UNPACKED_BYTES) throw new FileTextError(MSG_BOMB)
    entries.set(entry.name.toLowerCase(), entry)
    p = next
  }
  return { bytes, entries, budget: { left: MAX_UNPACKED_BYTES } }
}

async function zipRead(zip: Zip, name: string): Promise<Uint8Array | null> {
  const e = zip.entries.get(name.toLowerCase())
  if (!e) return null
  const b = zip.bytes
  const lh = e.localOffset
  if (lh + 30 > b.length || u32(b, lh) !== 0x04034b50) throw new Error('bad local header')
  const start = lh + 30 + u16(b, lh + 26) + u16(b, lh + 28)
  const data = b.subarray(start, start + e.compSize)
  if (data.length < e.compSize) throw new Error('truncated')
  if (e.size > zip.budget.left) throw new FileTextError(MSG_BOMB)
  let out: Uint8Array
  if (e.method === 0) out = data
  else if (e.method === 8) out = await inflate(data, 'deflate-raw', e.size)
  else throw new Error(`zip method ${e.method}`)
  zip.budget.left -= out.length
  return out
}

async function zipText(zip: Zip, name: string): Promise<string | null> {
  const b = await zipRead(zip, name)
  return b ? decodeText(b) : null
}

/** Entries matching `<prefix><n>.xml`, in numeric order. */
function numbered(zip: Zip, re: RegExp): { n: number; name: string }[] {
  const out: { n: number; name: string }[] = []
  for (const e of zip.entries.values()) {
    const m = re.exec(e.name)
    if (m) out.push({ n: Number(m[1]), name: e.name })
  }
  return out.sort((a, b) => a.n - b.n)
}

const WORD_RULES: XmlTextRules = {
  text: new Set(['w:t']),
  para: new Set(['w:p']),
  tab: new Set(['w:tab', 'w:ptab']),
  br: new Set(['w:br', 'w:cr']),
}

async function readDocx(bytes: Uint8Array): Promise<Extracted> {
  const zip = openZip(bytes)
  const xml = await zipText(zip, 'word/document.xml')
  if (xml === null) throw new Error('no document part')
  // Inside a tab-stop definition (w:tabs) a w:tab is not a tab character.
  return { text: xmlText(xml.replace(/<w:tabs\b[\s\S]*?<\/w:tabs>/g, ''), WORD_RULES), notes: [] }
}

const SLIDE_RULES: XmlTextRules = { text: new Set(['a:t']), para: new Set(['a:p']), br: new Set(['a:br']) }

async function readPptx(bytes: Uint8Array): Promise<Extracted> {
  const zip = openZip(bytes)
  const slides = numbered(zip, /^ppt\/slides\/slide(\d+)\.xml$/i)
  if (!slides.length) throw new Error('no slides')
  const parts: string[] = []
  for (const s of slides) {
    const xml = (await zipText(zip, s.name)) ?? ''
    parts.push(`Slide ${s.n}\n${xmlText(xml, SLIDE_RULES).replace(/^\n+|\n+$/g, '')}`)
  }
  return { text: parts.join('\n\n'), notes: [] }
}

const CELL_TEXT: XmlTextRules = { text: new Set(['t']), skip: new Set(['rPh']), local: true }

function columnIndex(ref: string): number {
  const letters = /^([A-Z]+)/i.exec(ref)?.[1]?.toUpperCase()
  if (!letters) return -1
  let n = 0
  for (const ch of letters) n = n * 26 + (ch.charCodeAt(0) - 64)
  return n - 1
}

function attr(attrs: string, name: string): string | null {
  const m = new RegExp(`\\b${name}\\s*=\\s*"([^"]*)"`).exec(attrs)
  return m ? m[1] : null
}

/** The workbook's shared strings, in order (an empty <si/> keeps its place). */
async function readSharedStrings(zip: Zip): Promise<string[]> {
  const shared: string[] = []
  const sst = await zipText(zip, 'xl/sharedStrings.xml')
  if (!sst) return shared
  const si = /<(?:\w+:)?si\b[^>]*?(?:\/>|>([\s\S]*?)<\/(?:\w+:)?si>)/g
  let m: RegExpExecArray | null
  while ((m = si.exec(sst))) shared.push(m[1] ? xmlText(m[1], CELL_TEXT) : '')
  return shared
}

/** A cell's text by its type: shared string, inline string, boolean or plain value; on one line. */
function cellValue(attrs: string, inner: string, shared: string[]): string {
  const type = attr(attrs, 't')
  const v = /<(?:\w+:)?v\b[^>]*>([\s\S]*?)<\/(?:\w+:)?v>/.exec(inner)?.[1]
  let value = ''
  if (type === 's') value = shared[Number(v)] ?? ''
  else if (type === 'inlineStr') value = xmlText(inner, CELL_TEXT)
  else if (type === 'b') value = v === '1' ? 'TRUE' : v === '0' ? 'FALSE' : ''
  else if (v !== undefined) value = decodeEntities(v)
  return value.replace(/\s*\n\s*/g, ' ').trim()
}

/** A row's cells, each in its column (by its reference; empty columns kept), trailing empties cut. */
function rowCells(rowXml: string, shared: string[]): string[] {
  const cells: string[] = []
  const cellRe = /<(?:\w+:)?c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/(?:\w+:)?c>)/g
  let c: RegExpExecArray | null
  while ((c = cellRe.exec(rowXml))) {
    const value = cellValue(c[1], c[2] ?? '', shared)
    const ref = attr(c[1], 'r')
    const col = ref ? columnIndex(ref) : -1
    if (col < 0 || col >= 16384) {
      cells.push(value)
      continue
    }
    while (cells.length < col) cells.push('')
    cells[col] = value
  }
  while (cells.length && !cells[cells.length - 1]) cells.pop()
  return cells
}

/** A sheet's non-empty rows as "a | b | c" lines, at most MAX_SHEET_ROWS; `cut` when there were more. */
function sheetLines(xml: string, shared: string[]): { lines: string[]; cut: boolean } {
  const lines: string[] = []
  const rowRe = /<(?:\w+:)?row\b[^>]*?(?:\/>|>([\s\S]*?)<\/(?:\w+:)?row>)/g
  let r: RegExpExecArray | null
  while ((r = rowRe.exec(xml))) {
    const cells = r[1] ? rowCells(r[1], shared) : []
    if (!cells.length) continue
    if (lines.length >= MAX_SHEET_ROWS) return { lines, cut: true }
    lines.push(cells.join(' | '))
  }
  return { lines, cut: false }
}

async function readXlsx(bytes: Uint8Array): Promise<Extracted> {
  const zip = openZip(bytes)
  const shared = await readSharedStrings(zip)
  const sheets = numbered(zip, /^xl\/worksheets\/sheet(\d+)\.xml$/i)
  if (!sheets.length) throw new Error('no sheets')
  const parts: string[] = []
  const notes: string[] = []
  for (const s of sheets) {
    const { lines, cut } = sheetLines((await zipText(zip, s.name)) ?? '', shared)
    if (cut) {
      lines.push('[Cut at 2,000 rows.]')
      notes.push(`Sheet ${s.n} was cut at 2,000 rows.`)
    }
    parts.push(`Sheet ${s.n}\n${lines.join('\n')}`)
  }
  return { text: parts.join('\n\n'), notes }
}

// ---------------------------------------------------------------- PDF

/** Where a stream's data ends: at its direct /Length when "endstream" follows there, else at the
 *  next "endstream" less the line end before it; -1 when there is none (a truncated file). */
function pdfStreamEnd(s: string, start: number, dict: string): number {
  const len = /\/Length\s+(\d+)(?!\d)(?!\s+\d+\s+R)/.exec(dict)
  if (len) {
    const e = start + Number(len[1])
    if (/^\s*endstream/.test(s.slice(e, e + 20))) return e
  }
  let end = s.indexOf('endstream', start)
  if (end < 0) return -1
  while (end > start && (s[end - 1] === '\n' || s[end - 1] === '\r')) end--
  return end
}

/** Streams that never hold page text: images, fonts, cross-reference and object streams, metadata,
 *  forms, and predictor-coded data. */
const PDF_NOT_TEXT = /\/Subtype\s*\/Image|\/FontFile|\/Length1|\/Type\s*\/(XRef|ObjStm|Metadata|XObject)|\/Predictor/

/** A stream's data as a binary string: as stored, or inflated for a single /FlateDecode; null for
 *  other filters or data that does not inflate. `used`: the bytes it took from the budget. */
async function pdfStreamData(data: Uint8Array, dict: string, budget: number): Promise<{ content: string; used: number } | null> {
  const filters = /\/Filter\s*(\[[^\]]*\]|\/\w+)/.exec(dict)?.[1].match(/\/\w+/g) ?? []
  if (filters.length > 1 || (filters.length === 1 && filters[0] !== '/FlateDecode')) return null
  if (!filters.length) return { content: latin1(data), used: 0 }
  try {
    const out = await inflate(data, 'deflate', budget, true)
    return { content: latin1(out), used: out.length }
  } catch (e) {
    if (e instanceof FileTextError) throw e
    return null
  }
}

/** The text read from a PDF, or a refusal when it has too few letters or too much junk to be
 *  text (a scan, or fonts whose codes are not letters). */
function readablePdfText(pieces: string[]): string {
  const text = pieces.join('\n\n')
  const letters = text.match(/\p{L}/gu)?.length ?? 0
  const junk = text.match(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f�]/g)?.length ?? 0
  if (letters < MIN_PDF_LETTERS || junk > text.length * 0.1) throw new FileTextError(MSG_PDF_NO_TEXT)
  return text
}

async function readPdf(bytes: Uint8Array): Promise<Extracted> {
  const s = latin1(bytes)
  if (!s.startsWith('%PDF') && s.indexOf('%PDF') < 0) throw new Error('not a pdf')
  if (/\/Encrypt\s*(\d+\s+\d+\s+R|<<)/.test(s)) throw new FileTextError(MSG_PASSWORD)
  const pieces: string[] = []
  let budget = MAX_UNPACKED_BYTES
  const re = /stream(\r\n|\n|\r)/g
  let m: RegExpExecArray | null
  while ((m = re.exec(s))) {
    if (s.slice(m.index - 3, m.index) === 'end') continue
    const start = m.index + m[0].length
    const objAt = s.lastIndexOf('obj', m.index)
    const dict = s.slice(objAt < 0 ? Math.max(0, m.index - 2000) : objAt, m.index)
    const end = pdfStreamEnd(s, start, dict)
    if (end < 0) break
    re.lastIndex = end
    if (PDF_NOT_TEXT.test(dict)) continue
    const data = await pdfStreamData(bytes.subarray(start, end), dict, budget)
    if (!data) continue
    budget -= data.used
    if (!/\bBT\b/.test(data.content)) continue
    const text = pdfContentText(data.content)
    if (text.trim()) pieces.push(text)
  }
  return { text: readablePdfText(pieces), notes: [] }
}

const PDF_DELIM = new Set(['(', ')', '<', '>', '[', ']', '{', '}', '/', '%'])
const isPdfSpace = (ch: string): boolean => ch === ' ' || ch === '\n' || ch === '\r' || ch === '\t' || ch === '\f' || ch === '\0'

const PDF_ESCAPES: Record<string, string> = { n: '\n', r: '\r', t: '\t', b: '\b', f: '\f', '(': '(', ')': ')', '\\': '\\' }

/** The escape whose letter `nx` follows a backslash, with the rest of it read from `i` (octal
 *  digits, a line end after a backslash-CR): its text and the index after it. */
function pdfEscape(c: string, nx: string, i: number): [string, number] {
  if (PDF_ESCAPES[nx] !== undefined) return [PDF_ESCAPES[nx], i]
  if (nx >= '0' && nx <= '7') {
    let oct = nx
    while (oct.length < 3 && c[i] >= '0' && c[i] <= '7') oct += c[i++]
    return [String.fromCharCode(parseInt(oct, 8) & 0xff), i]
  }
  // A backslash at a line end continues the string on the next line.
  if (nx === '\r') return ['', c[i] === '\n' ? i + 1 : i]
  return [nx === '\n' ? '' : nx, i]
}

/** A PDF literal string starting at `(`; returns its text and the index after the closing `)`. */
function readPdfString(c: string, at: number): [string, number] {
  let depth = 1
  let i = at + 1
  let out = ''
  while (i < c.length) {
    const ch = c[i]
    if (ch === '\\') {
      const nx = c[i + 1]
      if (nx === undefined) {
        i += 2
        break
      }
      const [text, next] = pdfEscape(c, nx, i + 2)
      out += text
      i = next
      continue
    }
    if (ch === '(') depth++
    else if (ch === ')' && --depth === 0) return [decodePdfText(out), i + 1]
    out += ch
    i++
  }
  return [decodePdfText(out), i]
}

function decodePdfText(s: string): string {
  if (s.charCodeAt(0) === 0xfe && s.charCodeAt(1) === 0xff) return decodeWith(latin1Bytes(s.slice(2)), 'utf-16be')
  return s
}

type PdfOperand = string | number | string[] | null

/** A content stream being read: the text so far, the operands since the last operator, and the
 *  last text matrix's y (a change of it starts a new line). */
interface PdfTextState {
  out: string
  ops: PdfOperand[]
  lastY: number | null
}

function pdfNewline(st: PdfTextState): void {
  if (st.out && !st.out.endsWith('\n')) st.out += '\n'
}

const pdfLastOperand = (st: PdfTextState): PdfOperand | undefined => st.ops[st.ops.length - 1]

function pdfShowString(st: PdfTextState): void {
  const v = pdfLastOperand(st)
  st.out += typeof v === 'string' ? v : ''
}

function pdfNextLineShow(st: PdfTextState): void {
  pdfNewline(st)
  pdfShowString(st)
}

function pdfMoveLine(st: PdfTextState): void {
  const ty = pdfLastOperand(st)
  if (typeof ty === 'number' && ty !== 0) pdfNewline(st)
}

/** The text operators that show text or move to a new line; every other operator only clears the
 *  operands. A Map, so a token such as "__proto__" in a damaged stream finds nothing. */
const PDF_TEXT_OPS = new Map<string, (st: PdfTextState) => void>([
  ['Tj', pdfShowString],
  ["'", pdfNextLineShow],
  ['"', pdfNextLineShow],
  ['TJ', (st) => {
    const arr = pdfLastOperand(st)
    if (Array.isArray(arr)) st.out += arr.join('')
  }],
  ['Td', pdfMoveLine],
  ['TD', pdfMoveLine],
  ['Tm', (st) => {
    const y = pdfLastOperand(st)
    if (typeof y !== 'number') return
    if (st.lastY !== null && y !== st.lastY) pdfNewline(st)
    st.lastY = y
  }],
  ['T*', pdfNewline],
  ['ET', pdfNewline],
])

/** A TJ array starting at `[`: its strings, with a space for a large move to the right (a word
 *  gap); hex strings left out. Returns the parts and the index after the closing `]`. */
function readPdfArray(c: string, at: number): [string[], number] {
  const n = c.length
  const parts: string[] = []
  let i = at + 1
  while (i < n && c[i] !== ']') {
    const a = c[i]
    if (a === '(') {
      const [str, j] = readPdfString(c, i)
      parts.push(str)
      i = j
    } else if (a === '<') {
      const j = c.indexOf('>', i)
      i = j < 0 ? n : j + 1
    } else if (a === '-' || a === '.' || (a >= '0' && a <= '9')) {
      let j = i + 1
      while (j < n && /[0-9.]/.test(c[j])) j++
      // A large move to the right inside TJ is a word gap.
      if (Number(c.slice(i, j)) < -180) parts.push(' ')
      i = j
    } else i++
  }
  return [parts, i + 1]
}

/** After `BI`: the index after the inline image's data, at its `EI` (one that stands alone). */
function skipPdfInlineImage(c: string, i: number): number {
  const n = c.length
  const id = c.indexOf('ID', i)
  let k = id < 0 ? n : id + 2
  for (;;) {
    k = c.indexOf('EI', k)
    if (k < 0) return n
    if (isPdfSpace(c[k - 1] ?? ' ') && (k + 2 >= n || isPdfSpace(c[k + 2]))) return Math.min(n, k + 2)
    k += 2
  }
}

/** The end of a name or an operator token starting at `i`. */
function pdfTokenEnd(c: string, i: number): number {
  while (i < c.length && !isPdfSpace(c[i]) && !PDF_DELIM.has(c[i])) i++
  return i
}

/** A bare token at `i`: a number goes onto the operands; an operator acts (PDF_TEXT_OPS, or `BI`
 *  skips its inline image) and clears them. Returns the index after it. */
function pdfOperator(c: string, i: number, st: PdfTextState): number {
  const j = pdfTokenEnd(c, i)
  const tok = c.slice(i, j)
  if (/^[+-]?(\d+\.?\d*|\.\d+)$/.test(tok)) {
    st.ops.push(Number(tok))
    return j
  }
  let next = j
  if (tok === 'BI') next = skipPdfInlineImage(c, j)
  else PDF_TEXT_OPS.get(tok)?.(st)
  st.ops.length = 0
  return next
}

/** Text shown by a content stream's text operators, with line breaks from line moves. */
function pdfContentText(c: string): string {
  const st: PdfTextState = { out: '', ops: [], lastY: null }
  const n = c.length
  let i = 0
  while (i < n) {
    const ch = c[i]
    if (isPdfSpace(ch)) i++
    else if (ch === '(') {
      const [str, j] = readPdfString(c, i)
      st.ops.push(str)
      i = j
    } else if (ch === '<' && c[i + 1] === '<') i += 2
    else if (ch === '<') {
      // A hex string: glyph ids of an embedded font, not readable without the font. Left out.
      const j = c.indexOf('>', i)
      st.ops.push(null)
      i = j < 0 ? n : j + 1
    } else if (ch === '[') {
      const [parts, j] = readPdfArray(c, i)
      st.ops.push(parts)
      i = j
    } else if (ch === '%') {
      while (i < n && c[i] !== '\n' && c[i] !== '\r') i++
    } else if (ch === '/') {
      i = pdfTokenEnd(c, i + 1)
      st.ops.push(null)
    } else if (PDF_DELIM.has(ch)) i++
    else i = pdfOperator(c, i, st)
  }
  return st.out
}

// ---------------------------------------------------------------- Outlook .msg (OLE compound file)

const CFB_SIGNATURE = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]

function isCfb(b: Uint8Array): boolean {
  return b.length >= 512 && CFB_SIGNATURE.every((x, i) => b[i] === x)
}

interface CfbEntry {
  name: string
  type: number
  left: number
  right: number
  child: number
  start: number
  size: number
}

const END_OF_CHAIN = 0xfffffffe
const NO_STREAM = 0xffffffff

/** The sectors that hold the FAT: up to 109 listed in the header, the rest in the DIFAT chain. */
function cfbFatSectors(b: Uint8Array, ss: number, sector: (n: number) => Uint8Array): number[] {
  const nFat = u32(b, 0x2c)
  const difatStart = u32(b, 0x44)
  const nDifat = u32(b, 0x48)
  const fatSectors: number[] = []
  for (let i = 0; i < 109 && fatSectors.length < nFat; i++) {
    const s = u32(b, 0x4c + 4 * i)
    if (s >= 0xfffffffa) break
    fatSectors.push(s)
  }
  let d = difatStart
  for (let hops = 0; d < 0xfffffffa && fatSectors.length < nFat && hops < nDifat; hops++) {
    const sec = sector(d)
    for (let k = 0; k < ss / 4 - 1 && fatSectors.length < nFat; k++) {
      const s = u32(sec, 4 * k)
      if (s < 0xfffffffa) fatSectors.push(s)
    }
    d = u32(sec, ss - 4)
  }
  return fatSectors
}

/** The directory entries, 128 bytes each. */
function parseCfbDirectory(dir: Uint8Array): CfbEntry[] {
  const entries: CfbEntry[] = []
  for (let o = 0; o + 128 <= dir.length; o += 128) {
    const nameLen = Math.min(64, u16(dir, o + 64))
    entries.push({
      name: decodeWith(dir.subarray(o, o + Math.max(0, nameLen - 2)), 'utf-16le'),
      type: dir[o + 66],
      left: u32(dir, o + 68),
      right: u32(dir, o + 72),
      child: u32(dir, o + 76),
      start: u32(dir, o + 116),
      size: u32(dir, o + 120),
    })
  }
  return entries
}

/** The streams among the root's children (a red-black tree walked by its left/right links, each
 *  entry once), by lower-case name. */
function rootStreams(entries: CfbEntry[], root: CfbEntry, readStream: (e: CfbEntry) => Uint8Array): Map<string, Uint8Array> {
  const out = new Map<string, Uint8Array>()
  const seen = new Set<number>()
  const stack = [root.child]
  while (stack.length) {
    const id = stack.pop() as number
    if (id === NO_STREAM || id >= entries.length || seen.has(id)) continue
    seen.add(id)
    const e = entries[id]
    stack.push(e.left, e.right)
    if (e.type === 2) out.set(e.name.toLowerCase(), readStream(e))
  }
  return out
}

/** The streams directly under the root storage, by lower-case name. */
function readCfbRootStreams(b: Uint8Array): Map<string, Uint8Array> {
  const ss = 1 << u16(b, 0x1e)
  if (ss !== 512 && ss !== 4096) throw new Error('bad sector size')
  const mss = 1 << u16(b, 0x20)
  const dirStart = u32(b, 0x30)
  const cutoff = u32(b, 0x38)
  const miniFatStart = u32(b, 0x3c)
  const sector = (n: number): Uint8Array => {
    const o = (n + 1) * ss
    if (o >= b.length) throw new Error('sector out of range')
    return b.subarray(o, o + ss)
  }
  const fat = concat(cfbFatSectors(b, ss, sector).map(sector))
  const fatAt = (n: number): number => (4 * n + 3 < fat.length ? u32(fat, 4 * n) : END_OF_CHAIN)
  const chain = (start: number, next: (n: number) => number, limit: number): number[] => {
    const out: number[] = []
    for (let s = start; s < 0xfffffffa; s = next(s)) {
      if (out.length > limit) throw new Error('sector loop')
      out.push(s)
    }
    return out
  }
  const maxSectors = Math.ceil(b.length / ss)
  const readFat = (start: number, size?: number): Uint8Array => {
    const data = concat(chain(start, fatAt, maxSectors).map(sector))
    return size === undefined ? data : data.subarray(0, size)
  }
  const entries = parseCfbDirectory(readFat(dirStart))
  const root = entries[0]
  if (!root || root.type !== 5) throw new Error('no root entry')
  if (root.size > MAX_UNPACKED_BYTES) throw new Error('mini stream too large')
  const mini = root.size ? readFat(root.start, root.size) : new Uint8Array(0)
  const miniFat = miniFatStart < 0xfffffffa ? readFat(miniFatStart) : new Uint8Array(0)
  const miniAt = (n: number): number => (4 * n + 3 < miniFat.length ? u32(miniFat, 4 * n) : END_OF_CHAIN)
  const readStream = (e: CfbEntry): Uint8Array => {
    if (e.size > MAX_UNPACKED_BYTES) throw new Error('stream too large')
    if (e.size < cutoff) {
      const parts = chain(e.start, miniAt, Math.ceil(mini.length / mss)).map((s) => mini.subarray(s * mss, (s + 1) * mss))
      return concat(parts).subarray(0, e.size)
    }
    return readFat(e.start, e.size)
  }
  return rootStreams(entries, root, readStream)
}

function msgProperty(streams: Map<string, Uint8Array>, tag: string): string {
  const wide = streams.get(`__substg1.0_${tag}001f`)
  if (wide) return decodeWith(wide, 'utf-16le').replace(/\0+$/, '')
  const narrow = streams.get(`__substg1.0_${tag}001e`)
  if (narrow) return utf8OrAnsi(narrow).replace(/\0+$/, '')
  return ''
}

async function readMsg(bytes: Uint8Array): Promise<Extracted> {
  const streams = readCfbRootStreams(bytes)
  const subject = msgProperty(streams, '0037').trim()
  const from = msgProperty(streams, '0c1a').trim()
  let body = msgProperty(streams, '1000')
  if (!body.trim()) {
    const html = streams.get('__substg1.0_10130102') ?? null
    if (html) body = htmlToText(decodeText(html))
  }
  if (!body.trim()) throw new FileTextError(MSG_MSG_NO_BODY)
  const head = [subject && `Subject: ${subject}`, from && `From: ${from}`].filter(Boolean).join('\n')
  return { text: head ? `${head}\n\n${body}` : body, notes: [] }
}

// ---------------------------------------------------------------- .eml (MIME mail)

interface MimePart {
  headers: Map<string, string>
  body: string
}

/** Header block and body of a MIME part, both as binary (Latin-1) strings. */
function parseMime(raw: string): MimePart {
  const split = /\r?\n\r?\n/.exec(raw)
  const head = split ? raw.slice(0, split.index) : raw
  const body = split ? raw.slice(split.index + split[0].length) : ''
  const headers = new Map<string, string>()
  for (const line of head.replace(/\r?\n[ \t]+/g, ' ').split(/\r?\n/)) {
    const m = /^([!-9;-~]+):[ \t]*(.*)$/.exec(line)
    if (m && !headers.has(m[1].toLowerCase())) headers.set(m[1].toLowerCase(), m[2].trim())
  }
  return { headers, body }
}

function headerParam(value: string, name: string): string {
  const m = new RegExp(`;\\s*${name}\\s*=\\s*(?:"([^"]*)"|([^;\\s]+))`, 'i').exec(value)
  return m ? (m[1] ?? m[2] ?? '') : ''
}

function base64Bytes(s: string): Uint8Array {
  const clean = s.replace(/[^A-Za-z0-9+/]/g, '')
  const usable = clean.slice(0, clean.length - (clean.length % 4 === 1 ? 1 : 0))
  return latin1Bytes(atob(usable + '='.repeat((4 - (usable.length % 4)) % 4)))
}

function quotedPrintableBytes(s: string): Uint8Array {
  return latin1Bytes(s.replace(/=\r?\n/g, '').replace(/=([0-9A-Fa-f]{2})/g, (_, h: string) => String.fromCharCode(parseInt(h, 16))))
}

function partText(part: MimePart): string {
  const cte = (part.headers.get('content-transfer-encoding') ?? '').toLowerCase()
  const charset = headerParam(part.headers.get('content-type') ?? '', 'charset')
  let bytes: Uint8Array
  if (cte === 'base64') bytes = base64Bytes(part.body)
  else if (cte === 'quoted-printable') bytes = quotedPrintableBytes(part.body)
  else bytes = latin1Bytes(part.body)
  return charset ? decodeWith(bytes, charset.toLowerCase()) : utf8OrAnsi(bytes)
}

/** The parts of a multipart body, in order, up to its closing boundary; none without a boundary. */
function multipartChildren(body: string, boundary: string): MimePart[] {
  if (!boundary) return []
  const out: MimePart[] = []
  for (const piece of body.split(`--${boundary}`).slice(1)) {
    if (piece.startsWith('--')) break
    out.push(parseMime(piece.replace(/^[ \t]*\r?\n/, '')))
  }
  return out
}

/** The first text/plain and first text/html part (attachments left out). */
function findTextParts(part: MimePart, found: { plain?: string; html?: string }, depth: number): void {
  if (depth > 10 || (found.plain !== undefined && found.html !== undefined)) return
  const ct = part.headers.get('content-type') ?? 'text/plain'
  const type = ct.split(';')[0].trim().toLowerCase() || 'text/plain'
  if (depth > 0 && /^\s*attachment/i.test(part.headers.get('content-disposition') ?? '')) return
  if (type.startsWith('multipart/')) {
    for (const child of multipartChildren(part.body, headerParam(ct, 'boundary'))) findTextParts(child, found, depth + 1)
    return
  }
  if (type === 'message/rfc822') {
    findTextParts(parseMime(part.body), found, depth + 1)
    return
  }
  if (type === 'text/plain' && found.plain === undefined) found.plain = partText(part)
  else if (type === 'text/html' && found.html === undefined) found.html = partText(part)
}

/** A header value: raw 8-bit bytes as UTF-8 when valid, RFC 2047 encoded words decoded. */
function decodeHeader(value: string): string {
  const word = /=\?([^?\s]+)\?([BbQq])\?([^?\s]*)\?=/g
  const joined = value.replace(/(=\?[^?\s]+\?[BbQq]\?[^?\s]*\?=)\s+(?==\?)/g, '$1')
  const raw = utf8OrAnsi(latin1Bytes(joined))
  return raw.replace(word, (all, charset: string, enc: string, text: string) => {
    try {
      const bytes = enc.toUpperCase() === 'B'
        ? base64Bytes(text)
        : latin1Bytes(text.replace(/_/g, ' ').replace(/=([0-9A-Fa-f]{2})/g, (_, h: string) => String.fromCharCode(parseInt(h, 16))))
      return decodeWith(bytes, charset.replace(/\*.*$/, '').toLowerCase())
    } catch {
      return all
    }
  })
}

async function readEml(bytes: Uint8Array): Promise<Extracted> {
  let raw = latin1(bytes)
  if (raw.startsWith('ï»¿')) raw = raw.slice(3)
  const top = parseMime(raw)
  const found: { plain?: string; html?: string } = {}
  findTextParts(top, found, 0)
  const body = found.plain?.trim() ? found.plain : found.html !== undefined ? htmlToText(found.html) : ''
  const head = (['subject', 'from', 'date'] as const)
    .map((h) => {
      const v = top.headers.get(h)
      return v ? `${h[0].toUpperCase()}${h.slice(1)}: ${decodeHeader(v).trim()}` : ''
    })
    .filter(Boolean)
    .join('\n')
  if (!body.trim()) {
    return { text: '', notes: [] }
  }
  return { text: head ? `${head}\n\n${body}` : body, notes: [] }
}
