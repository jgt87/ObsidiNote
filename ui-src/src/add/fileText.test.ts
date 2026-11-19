import { describe, expect, it } from 'vitest'
import { fileKindOf, MAX_FILE_BYTES, MAX_TEXT_CHARS, readFileText } from './fileText'

// Every fixture is built here from bytes, with invented text only: no binary files, no real data.

const enc = new TextEncoder()

async function compress(data: Uint8Array, format: 'deflate' | 'deflate-raw'): Promise<Uint8Array> {
  const cs = new CompressionStream(format)
  const writer = cs.writable.getWriter()
  writer.write(new Uint8Array(data)).catch(() => {})
  writer.close().catch(() => {})
  const chunks: Uint8Array[] = []
  const reader = cs.readable.getReader()
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    chunks.push(value)
  }
  return join(chunks)
}

function join(chunks: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0))
  let at = 0
  for (const c of chunks) {
    out.set(c, at)
    at += c.length
  }
  return out
}

function le(bytes: number, value: number): number[] {
  const out: number[] = []
  for (let i = 0; i < bytes; i++) out.push((value >>> (8 * i)) & 0xff)
  return out
}

function latin1(s: string): Uint8Array {
  return Uint8Array.from(s, (c) => c.charCodeAt(0) & 0xff)
}

interface ZipFile {
  name: string
  data: string | Uint8Array
  method?: 0 | 8
  flags?: number
  declaredSize?: number
}

/** A minimal ZIP: local headers, central directory, end record (CRC left 0; the reader does not check it). */
async function makeZip(files: ZipFile[], opts: { zip64Locator?: boolean } = {}): Promise<Uint8Array> {
  const locals: Uint8Array[] = []
  const central: Uint8Array[] = []
  let offset = 0
  for (const f of files) {
    const raw = typeof f.data === 'string' ? enc.encode(f.data) : f.data
    const method = f.method ?? 8
    const data = method === 8 ? await compress(raw, 'deflate-raw') : raw
    const name = enc.encode(f.name)
    const size = f.declaredSize ?? raw.length
    const flags = f.flags ?? 0
    const local = Uint8Array.from([
      ...le(4, 0x04034b50), ...le(2, 20), ...le(2, flags), ...le(2, method), ...le(2, 0), ...le(2, 0),
      ...le(4, 0), ...le(4, data.length), ...le(4, size), ...le(2, name.length), ...le(2, 0),
    ])
    locals.push(local, name, data)
    central.push(Uint8Array.from([
      ...le(4, 0x02014b50), ...le(2, 20), ...le(2, 20), ...le(2, flags), ...le(2, method), ...le(2, 0), ...le(2, 0),
      ...le(4, 0), ...le(4, data.length), ...le(4, size), ...le(2, name.length), ...le(2, 0), ...le(2, 0),
      ...le(2, 0), ...le(2, 0), ...le(4, 0), ...le(4, offset),
    ]), name)
    offset += local.length + name.length + data.length
  }
  const cd = join(central)
  const tail: Uint8Array[] = []
  if (opts.zip64Locator) tail.push(Uint8Array.from([...le(4, 0x07064b50), ...le(16, 0)]))
  tail.push(Uint8Array.from([
    ...le(4, 0x06054b50), ...le(2, 0), ...le(2, 0), ...le(2, files.length), ...le(2, files.length),
    ...le(4, cd.length), ...le(4, offset), ...le(2, 0),
  ]))
  return join([...locals, cd, ...tail])
}

const W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'

function docxXml(body: string): string {
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document ${W}><w:body>${body}</w:body></w:document>`
}

/** A one-page PDF; `streams` are [dictionary entries, data] pairs. */
function makePdf(streams: [string, Uint8Array][], extraTrailer = ''): Uint8Array {
  const parts: Uint8Array[] = [latin1('%PDF-1.4\n%âãÏÓ\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n')]
  streams.forEach(([dict, data], i) => {
    parts.push(latin1(`${i + 3} 0 obj\n<< ${dict.replace('{len}', String(data.length))} >>\nstream\n`), data, latin1('\nendstream\nendobj\n'))
  })
  parts.push(latin1(`trailer\n<< /Root 1 0 R ${extraTrailer}>>\n%%EOF\n`))
  return join(parts)
}

function utf16(s: string): Uint8Array {
  const out = new Uint8Array(s.length * 2)
  for (let i = 0; i < s.length; i++) {
    out[2 * i] = s.charCodeAt(i) & 0xff
    out[2 * i + 1] = s.charCodeAt(i) >> 8
  }
  return out
}

/** A minimal OLE compound file (version 3, 512-byte sectors), every stream in the mini stream. */
function makeMsg(streams: { name: string; data: Uint8Array }[]): Uint8Array {
  const SS = 512
  const MSS = 64
  const END = 0xfffffffe
  const FREE = 0xffffffff
  const miniFat: number[] = []
  const miniParts: Uint8Array[] = []
  const starts: number[] = []
  for (const s of streams) {
    const count = Math.max(1, Math.ceil(s.data.length / MSS))
    const first = miniFat.length
    starts.push(first)
    for (let k = 0; k < count; k++) miniFat.push(k === count - 1 ? END : first + k + 1)
    const padded = new Uint8Array(count * MSS)
    padded.set(s.data)
    miniParts.push(padded)
  }
  const mini = join(miniParts)
  const dirSectors = Math.ceil((streams.length + 1) / 4)
  const miniSectors = Math.ceil(mini.length / SS)
  const dirStart = 1
  const miniFatSector = dirStart + dirSectors
  const miniStart = miniFatSector + 1
  const total = miniStart + miniSectors
  const fat = new Array<number>(SS / 4).fill(FREE)
  fat[0] = 0xfffffffd
  for (let k = 0; k < dirSectors; k++) fat[dirStart + k] = k === dirSectors - 1 ? END : dirStart + k + 1
  fat[miniFatSector] = END
  for (let k = 0; k < miniSectors; k++) fat[miniStart + k] = k === miniSectors - 1 ? END : miniStart + k + 1

  const file = new Uint8Array(SS * (total + 1))
  const put = (o: number, bytes: number[]): void => file.set(bytes, o)
  put(0, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])
  put(0x18, [...le(2, 0x3e), ...le(2, 3), ...le(2, 0xfffe), ...le(2, 9), ...le(2, 6)])
  put(0x2c, [...le(4, 1), ...le(4, dirStart), ...le(4, 0), ...le(4, 4096), ...le(4, miniFatSector), ...le(4, 1), ...le(4, END), ...le(4, 0)])
  for (let i = 0; i < 109; i++) put(0x4c + 4 * i, le(4, i === 0 ? 0 : FREE))
  const sector = (n: number): number => (n + 1) * SS
  fat.forEach((v, i) => put(sector(0) + 4 * i, le(4, v)))
  const entry = (i: number, name: string, type: number, child: number, right: number, start: number, size: number): void => {
    const o = sector(dirStart) + 128 * i
    const n = utf16(name)
    file.set(n, o)
    put(o + 64, [...le(2, n.length + 2), type, 1, ...le(4, FREE), ...le(4, right), ...le(4, child)])
    put(o + 116, [...le(4, start), ...le(4, size)])
  }
  entry(0, 'Root Entry', 5, streams.length ? 1 : FREE, FREE, miniStart, mini.length)
  streams.forEach((s, i) => entry(i + 1, s.name, 2, FREE, i + 2 <= streams.length ? i + 2 : FREE, starts[i], s.data.length))
  const mf = new Array<number>(SS / 4).fill(FREE)
  miniFat.forEach((v, i) => (mf[i] = v))
  mf.forEach((v, i) => put(sector(miniFatSector) + 4 * i, le(4, v)))
  file.set(mini, sector(miniStart))
  return file
}

describe('fileKindOf', () => {
  it('knows the kinds by extension, then by media type', () => {
    expect(fileKindOf('Plan.DOCX', '')).toBe('word')
    expect(fileKindOf('deck.pptx', '')).toBe('powerpoint')
    expect(fileKindOf('sums.xlsx', '')).toBe('excel')
    expect(fileKindOf('guide.pdf', '')).toBe('pdf')
    expect(fileKindOf('note.msg', '')).toBe('mail')
    expect(fileKindOf('note.eml', '')).toBe('mail')
    expect(fileKindOf('notes.md', '')).toBe('text')
    expect(fileKindOf('page.htm', '')).toBe('web')
    expect(fileKindOf('pasted', 'application/pdf')).toBe('pdf')
    expect(fileKindOf('photo.png', 'image/png')).toBeNull()
    expect(fileKindOf('old.doc', '')).toBeNull()
  })
})

describe('Word', () => {
  it('reads paragraphs, tabs, breaks and entities from a deflated document part', async () => {
    const xml = docxXml(
      '<w:p><w:pPr><w:pStyle w:val="Heading1"/><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr><w:r><w:t>Tidal gardens</w:t></w:r></w:p>' +
      '<w:p><w:r><w:t xml:space="preserve">Moss </w:t></w:r><w:r><w:t>&amp; kelp</w:t><w:tab/><w:t>grow</w:t><w:br/><w:t>at dusk &#8212; quietly</w:t></w:r></w:p>' +
      '<w:p><w:del><w:r><w:delText>gone</w:delText></w:r></w:del></w:p>',
    )
    const zip = await makeZip([{ name: '[Content_Types].xml', data: '<Types/>' }, { name: 'word/document.xml', data: xml }])
    const r = await readFileText('Garden plan.docx', '', zip)
    expect(r.ok).toBe(true)
    expect(r.kind).toBe('word')
    expect(r.text).toBe('File: Garden plan.docx\n\nTidal gardens\nMoss & kelp\tgrow\nat dusk — quietly')
    expect(r.message).toBe('')
  })

  it('reads a stored (uncompressed) entry too', async () => {
    const zip = await makeZip([{ name: 'word/document.xml', data: docxXml('<w:p><w:r><w:t>Stored lantern</w:t></w:r></w:p>'), method: 0 }])
    expect((await readFileText('a.docx', '', zip)).text).toBe('File: a.docx\n\nStored lantern')
  })

  it('says when a Word file is password protected (a compound file, not a ZIP)', async () => {
    const r = await readFileText('locked.docx', '', makeMsg([]))
    expect(r.ok).toBe(false)
    expect(r.message).toMatch(/password/)
  })
})

describe('PowerPoint', () => {
  it('reads slides in numeric order with a "Slide N" line before each', async () => {
    const slide = (t: string): string => `<p:sld xmlns:a="a" xmlns:p="p"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>${t}</a:t></a:r></a:p><a:p><a:r><a:t>second</a:t></a:r><a:br/><a:r><a:t>line</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>`
    const zip = await makeZip([
      { name: 'ppt/slides/slide10.xml', data: slide('Ten') },
      { name: 'ppt/slides/slide2.xml', data: slide('Two') },
      { name: 'ppt/slides/slide1.xml', data: slide('One') },
      { name: 'ppt/slides/_rels/slide1.xml.rels', data: '<Relationships/>' },
    ])
    const r = await readFileText('deck.pptx', '', zip)
    expect(r.ok).toBe(true)
    expect(r.text).toBe('File: deck.pptx\n\nSlide 1\nOne\nsecond\nline\n\nSlide 2\nTwo\nsecond\nline\n\nSlide 10\nTen\nsecond\nline')
  })
})

describe('Excel', () => {
  const sheet = (rows: string): string => `<worksheet xmlns="x"><sheetData>${rows}</sheetData></worksheet>`

  it('joins cells with " | ", resolves shared and inline strings and keeps empty columns', async () => {
    const shared = '<sst><si><t>Name</t></si><si><r><t>Tide</t></r><r><t> level</t></r><rPh><t>ignored</t></rPh></si><si><t>Kelp &amp; moss</t></si></sst>'
    const rows =
      '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>' +
      '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="C2"><v>4.5</v></c></row>' +
      '<row r="3"><c r="A3" t="inlineStr"><is><t>Inline note</t></is></c><c r="B3" t="b"><v>1</v></c></row>' +
      '<row r="4"><c r="A4"/></row>'
    const zip = await makeZip([
      { name: 'xl/sharedStrings.xml', data: shared },
      { name: 'xl/worksheets/sheet2.xml', data: sheet('<row r="1"><c r="A1" t="inlineStr"><is><t>Second sheet</t></is></c></row>') },
      { name: 'xl/worksheets/sheet1.xml', data: sheet(rows) },
    ])
    const r = await readFileText('tides.xlsx', '', zip)
    expect(r.ok).toBe(true)
    expect(r.text).toBe('File: tides.xlsx\n\nSheet 1\nName | Tide level\nKelp & moss |  | 4.5\nInline note | TRUE\n\nSheet 2\nSecond sheet')
  })

  it('stops a sheet at 2,000 rows and says so', async () => {
    let rows = ''
    for (let i = 1; i <= 2005; i++) rows += `<row r="${i}"><c r="A${i}"><v>${i}</v></c></row>`
    const zip = await makeZip([{ name: 'xl/worksheets/sheet1.xml', data: sheet(rows) }])
    const r = await readFileText('long.xlsx', '', zip)
    expect(r.ok).toBe(true)
    const lines = r.text.split('\n')
    expect(lines).toContain('2000')
    expect(lines).not.toContain('2001')
    expect(lines[lines.length - 1]).toBe('[Cut at 2,000 rows.]')
    expect(r.message).toBe('Sheet 1 was cut at 2,000 rows.')
  })
})

describe('ZIP guards', () => {
  it('refuses a ZIP that declares more than 50 MB unpacked (zip bomb)', async () => {
    const zip = await makeZip([{ name: 'word/document.xml', data: docxXml('<w:p><w:r><w:t>x</w:t></w:r></w:p>'), declaredSize: 0xfffffff0 }])
    const r = await readFileText('bomb.docx', '', zip)
    expect(r.ok).toBe(false)
    expect(r.message).toMatch(/more than 50 MB/)
  })

  it('refuses an entry that inflates past its declared size', async () => {
    const big = 'kelp '.repeat(20000)
    const zip = await makeZip([{ name: 'word/document.xml', data: docxXml(`<w:p><w:r><w:t>${big}</w:t></w:r></w:p>`), declaredSize: 1000 }])
    const r = await readFileText('liar.docx', '', zip)
    expect(r.ok).toBe(false)
    expect(r.message).toMatch(/more than 50 MB/)
  })

  it('refuses encrypted entries and ZIP64 archives with a clear message', async () => {
    const enc1 = await makeZip([{ name: 'word/document.xml', data: 'x', flags: 1 }])
    expect((await readFileText('e.docx', '', enc1)).message).toMatch(/password/)
    const z64 = await makeZip([{ name: 'word/document.xml', data: 'x' }], { zip64Locator: true })
    const r = await readFileText('z.docx', '', z64)
    expect(r.ok).toBe(false)
    expect(r.message).toMatch(/too large inside/)
  })
})

describe('PDF', () => {
  it('reads text from a FlateDecode content stream', async () => {
    const content = enc.encode('BT /F1 12 Tf 72 700 Td (Hello tidal gardens) Tj 0 -14 Td (with \\(quiet\\) shores\\041) Tj ET')
    const data = await compress(content, 'deflate')
    const pdf = makePdf([['/Length {len} /Filter /FlateDecode', data]])
    const r = await readFileText('garden.pdf', 'application/pdf', pdf)
    expect(r.ok).toBe(true)
    expect(r.kind).toBe('pdf')
    expect(r.text).toBe('File: garden.pdf\n\nHello tidal gardens\nwith (quiet) shores!')
  })

  it('reads TJ arrays and quote operators, skips hex strings, and finds streams with an indirect length', async () => {
    const content = latin1('BT [(Lan) 30 (terns) -250 (glow)] TJ T* (softly\\nat) \' <0041> Tj (night) Tj ET')
    const pdf = makePdf([['/Length 9 0 R', content]])
    const r = await readFileText('l.pdf', '', pdf)
    expect(r.ok).toBe(true)
    expect(r.text).toBe('File: l.pdf\n\nLanterns glow\nsoftly\natnight')
  })

  it('treats tokens named like object properties as unknown operators', async () => {
    // The operators are looked up in a Map: "__proto__" or "constructor" in a damaged stream must
    // neither throw nor act like a text operator.
    const content = 'BT (Quarterly figures for the board) Tj __proto__ constructor toString (ignored) hasOwnProperty T* (second line) Tj ET'
    const r = await readFileText('p.pdf', 'application/pdf', makePdf([['/Length {len}', latin1(content)]]))
    expect(r.ok).toBe(true)
    if (r.ok) expect(r.text.endsWith('\nQuarterly figures for the board\nsecond line')).toBe(true)
  })
  it('says a PDF with only an image has no readable text', async () => {
    const img = latin1('ÿØÿà not really a jpeg')
    const page = await compress(enc.encode('q 100 0 0 100 0 0 cm /Im1 Do Q'), 'deflate')
    const pdf = makePdf([
      ['/Type /XObject /Subtype /Image /Width 1 /Height 1 /Filter /DCTDecode /Length {len}', img],
      ['/Length {len} /Filter /FlateDecode', page],
    ])
    const r = await readFileText('scan.pdf', '', pdf)
    expect(r.ok).toBe(false)
    expect(r.message).toBe('This PDF has no text that can be read (it may be a scan or use special fonts). Open it and paste the text instead.')
  })

  it('says an encrypted PDF is protected', async () => {
    const pdf = makePdf([['/Length {len}', latin1('BT (Hello tidal gardens) Tj ET')]], '/Encrypt 9 0 R ')
    expect((await readFileText('p.pdf', '', pdf)).message).toMatch(/password/)
  })
})

describe('Outlook .msg', () => {
  it('reads subject, sender and plain body (UTF-16)', async () => {
    const msg = makeMsg([
      { name: '__substg1.0_0037001F', data: utf16('Tide tables for Friday') },
      { name: '__substg1.0_0C1A001F', data: utf16('Robin Example') },
      { name: '__substg1.0_1000001F', data: utf16(`Hi all,\r\n\r\nThe low tide is at 6. ${'Bring boots. '.repeat(10)}\r\nRobin`) },
    ])
    const r = await readFileText('tides.msg', '', msg)
    expect(r.ok).toBe(true)
    expect(r.kind).toBe('mail')
    expect(r.text.startsWith('File: tides.msg\n\nSubject: Tide tables for Friday\nFrom: Robin Example\n\nHi all,\n\nThe low tide is at 6. Bring boots.')).toBe(true)
    expect(r.text.endsWith('\nRobin')).toBe(true)
  })

  it('falls back to the 8-bit properties', async () => {
    const msg = makeMsg([
      { name: '__substg1.0_0037001E', data: enc.encode('Old style') },
      { name: '__substg1.0_1000001E', data: enc.encode('Body in eight bits') },
    ])
    expect((await readFileText('o.msg', '', msg)).text).toBe('File: o.msg\n\nSubject: Old style\n\nBody in eight bits')
  })

  it('says when there is no plain-text body', async () => {
    const msg = makeMsg([{ name: '__substg1.0_0037001F', data: utf16('Only a subject') }])
    const r = await readFileText('empty.msg', '', msg)
    expect(r.ok).toBe(false)
    expect(r.message).toBe('This Outlook message has no plain-text body that can be read. Open it and copy the text instead.')
  })
})

describe('.eml', () => {
  it('reads decoded headers and the first text/plain part (base64), ignoring attachments', async () => {
    const body = Buffer.from('Grüße from the shore.\nSee you at low tide.', 'utf8').toString('base64')
    const eml = [
      'Subject: =?utf-8?B?VGlkYWwg?=',
      ' =?utf-8?Q?g=C3=A4rdens?=',
      'From: Sam Example <sam@example.invalid>',
      'Date: Mon, 2 Nov 2026 09:00:00 +0000',
      'Content-Type: multipart/mixed; boundary="outer"',
      '',
      '--outer',
      'Content-Type: multipart/alternative; boundary=inner',
      '',
      '--inner',
      'Content-Type: text/plain; charset=utf-8',
      'Content-Transfer-Encoding: base64',
      '',
      body,
      '--inner',
      'Content-Type: text/html; charset=utf-8',
      '',
      '<p>html version</p>',
      '--inner--',
      '--outer',
      'Content-Type: text/plain',
      'Content-Disposition: attachment; filename="x.txt"',
      '',
      'attached',
      '--outer--',
      '',
    ].join('\r\n')
    const r = await readFileText('shore.eml', '', enc.encode(eml))
    expect(r.ok).toBe(true)
    expect(r.text).toBe('File: shore.eml\n\nSubject: Tidal gärdens\nFrom: Sam Example <sam@example.invalid>\nDate: Mon, 2 Nov 2026 09:00:00 +0000\n\nGrüße from the shore.\nSee you at low tide.')
  })

  it('decodes quoted-printable and falls back to the HTML part stripped to text', async () => {
    const eml = [
      'Subject: Plain',
      'Content-Type: multipart/alternative; boundary=b1',
      '',
      '--b1',
      'Content-Type: text/html; charset=iso-8859-1',
      'Content-Transfer-Encoding: quoted-printable',
      '',
      '<html><head><style>p{color:red}</style></head><body><p>Caf=E9 by the =',
      'harbour</p><script>alert(1)</script><p>Two &amp; three</p></body></html>',
      '--b1--',
    ].join('\n')
    const r = await readFileText('h.eml', 'message/rfc822', enc.encode(eml))
    expect(r.ok).toBe(true)
    expect(r.text).toBe('File: h.eml\n\nSubject: Plain\n\nCafé by the harbour\n\nTwo & three')
  })
})

describe('text and web pages', () => {
  it('strips a UTF-8 BOM, trims trailing spaces and collapses long blank runs', async () => {
    const r = await readFileText('n.txt', '', Uint8Array.from([0xef, 0xbb, 0xbf, ...enc.encode('one   \r\n\r\n\r\n\r\n\r\n\r\ntwo\t\n')]))
    expect(r.text).toBe('File: n.txt\n\none\n\n\ntwo')
  })

  it('decodes UTF-16 with a byte order mark', async () => {
    const r = await readFileText('w.csv', '', Uint8Array.from([0xff, 0xfe, ...utf16('a,b\n1,é')]))
    expect(r.text).toBe('File: w.csv\n\na,b\n1,é')
  })

  it('turns HTML into text without scripts or styles', async () => {
    const html = '<!doctype html><html><head><title>T</title><style>body{}</style></head><body><h1>Field&nbsp;guide</h1><script>var x = "<p>no</p>"</script><ul><li>Moss</li><li>Kelp</li></ul><p>A&lt;B</p></body></html>'
    const r = await readFileText('g.html', '', enc.encode(html))
    expect(r.ok).toBe(true)
    expect(r.text).toBe('File: g.html\n\nField guide\n\n- Moss\n- Kelp\n\nA<B')
  })
})

describe('limits and refusals', () => {
  it('refuses files over 10 MB', async () => {
    const r = await readFileText('big.txt', '', new Uint8Array(MAX_FILE_BYTES + 1))
    expect(r).toEqual({ ok: false, kind: 'text', text: '', message: 'This file is larger than 10 MB. Paste the part you want to keep instead.' })
  })

  it('cuts text at 60,000 characters with a final line and a note', async () => {
    const r = await readFileText('long.md', '', enc.encode('x'.repeat(MAX_TEXT_CHARS + 500)))
    expect(r.ok).toBe(true)
    expect(r.text.endsWith('\n\n[Cut at 60,000 characters.]')).toBe(true)
    expect(r.text.length).toBe('File: long.md\n\n'.length + MAX_TEXT_CHARS + '\n\n[Cut at 60,000 characters.]'.length)
    expect(r.message).toBe('Cut at 60,000 characters.')
  })

  it('names what to do for kinds it cannot read', async () => {
    expect((await readFileText('photo.png', 'image/png', new Uint8Array(4))).message).toBe('Image files can’t be read here. Open it and paste the text instead.')
    expect((await readFileText('old.doc', '', new Uint8Array(4))).message).toBe('Old .doc files can’t be read here. Save it as .docx first, or paste the text.')
    expect((await readFileText('old.xls', '', new Uint8Array(4))).message).toMatch(/Save it as \.xlsx/)
    expect((await readFileText('bundle.zip', '', new Uint8Array(4))).message).toMatch(/^Zip files can’t be read here/)
    expect((await readFileText('setup.exe', '', new Uint8Array(4))).ok).toBe(false)
  })

  it('names each kind it cannot read by extension, or by media type when the name has none', async () => {
    const say = async (name: string, mime = '') => (await readFileText(name, mime, new Uint8Array(4))).message
    expect(await say('setup.exe')).toBe('Program files can’t be read here.')
    expect(await say('talk.mp3')).toBe('Audio and video files can’t be read here. Paste a written summary instead.')
    expect(await say('clip', 'video/mp4')).toBe('Audio and video files can’t be read here. Paste a written summary instead.')
    expect(await say('photo', 'image/heic')).toBe('Image files can’t be read here. Open it and paste the text instead.')
    expect(await say('letter.rtf')).toBe('RTF files can’t be read here. Save it as .docx first, or paste the text.')
    expect(await say('deck.pps')).toBe('Old .pps files can’t be read here. Save it as .pptx first, or paste the text.')
    expect(await say('notes.one')).toBe('.one files can’t be read here. Open it and paste the text instead.')
    expect(await say('noext', 'application/x-thing')).toBe('This kind of file can’t be read here. Open it and paste the text instead.')
  })

  it('never throws on damaged files', async () => {
    const junk = Uint8Array.from({ length: 3000 }, (_, i) => (i * 73 + 11) & 0xff)
    for (const name of ['a.docx', 'a.pptx', 'a.xlsx', 'a.pdf', 'a.msg', 'a.eml']) {
      const r = await readFileText(name, '', junk)
      expect(typeof r.message).toBe('string')
      if (!r.ok) expect(r.message.length).toBeGreaterThan(10)
    }
    const r = await readFileText('broken.docx', '', junk)
    expect(r.ok).toBe(false)
    expect(r.message).toBe('This Word document could not be read; it may be damaged. Open it and paste the text instead.')
  })
})
