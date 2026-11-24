import { describe, expect, it } from 'vitest'
import { htmlToMarkdown, type PasteNode } from '../add/pasteMarkdown'
import { citeTarget } from '../ask/askModel'
import { bodyBlocks, inlineParts, linkTarget, type Part } from '../graph/bodyText'
import { openButtons } from '../graph/pageDialogModel'
import { loneLink, splitLinks, webUrl } from '../model/links'
import { parseQuery, topicQuery } from '../search/query'

// The interface's text-to-markup sinks, fed hostile values (the injection check; the static scan of
// the source for sinks built from strings is tests/injection.test.mjs). Every value here comes from
// a page, a paste, an answer or the search box, so each must come back unchanged as data or be
// refused: never a link to a script address, never an extra filter, never a new line of structure.

const HOSTILE = ["'", '"', '<script>alert(1)</script>', '<img src=x onerror=alert(1)>', '$(id)', '../../etc/passwd', '..\\..\\windows', '=1+1', '@SUM(A1)', 'a\r\nb', 'javascript:alert(1)']
const SCRIPT_URLS = [
  'javascript:alert(1)', 'JaVaScRiPt:alert(1)', ' javascript:alert(1)', '\njavascript:alert(1)', 'java\tscript:alert(1)',
  'vbscript:msgbox(1)', 'data:text/html,<script>alert(1)</script>', 'file:///C:/Windows/win.ini', '//evil.example/x',
]

const text = (parts: Part[]) => parts.map((p) => p.text).join('')
const links = (parts: Part[]) => parts.filter((p) => p.href !== undefined || p.pageId !== undefined)
const allParts = (md: string): Part[] => bodyBlocks(md).flatMap((b) => {
  if (b.kind === 'list') return b.items.flatMap((i) => i.parts)
  if (b.kind === 'table') return [...b.head.flat(), ...b.rows.flat(2)]
  return b.parts
})

/** A page's text as the server writes it (lib/MarkdownExport.psm1: \ ` * _ [ ] escaped). */
const serverEscape = (s: string) => s.replace(/([\\`*_[\]])/g, '\\$1')
/** What the server reads back from pasted Markdown: a backslash before punctuation is that
 *  punctuation (lib/MarkdownLines.psm1). */
const serverUnescape = (s: string) => s.replace(/\\([!-/:-@[-`{-~])/g, '$1')

describe('page text (bodyText): hostile text stays text', () => {
  it('each value comes back as the same plain text, with no link', () => {
    for (const v of HOSTILE) {
      const parts = inlineParts(serverEscape(v))
      expect(text(parts), v).toBe(v)
      expect(links(parts), v).toEqual([])
    }
  })

  it('a link to a script, data or file address is no link: its label stays as text', () => {
    for (const u of SCRIPT_URLS) {
      expect(linkTarget(u), u).toEqual({})
      const parts = inlineParts(`[click](${u.replace(/[()]/g, '')})`)
      expect(parts.some((p) => p.href), u).toBe(false)
    }
  })

  it('only http(s), mailto and onenote addresses become links; a page id is kept as data', () => {
    expect(linkTarget('https://kb.example/a')).toEqual({ href: 'https://kb.example/a' })
    expect(linkTarget('mailto:sam@example.com')).toEqual({ href: 'mailto:sam@example.com' })
    expect(linkTarget('onenote:#page')).toEqual({ href: 'onenote:#page' })
    expect(linkTarget('obsn:../../etc')).toEqual({ pageId: '../../etc' })
  })

  it('CR/LF inside a paragraph never starts a heading or a list', () => {
    const blocks = bodyBlocks('Plain line\r\n# not a heading\r\n- not a list')
    expect(blocks.map((b) => b.kind)).toEqual(['para'])
  })
})

/** A tiny DOM for htmlToMarkdown: an element with attributes and children, or a text node. */
const el = (nodeName: string, attrs: Record<string, string>, ...childNodes: PasteNode[]): PasteNode => ({
  nodeType: 1, nodeName, childNodes, textContent: childNodes.map((c) => c.textContent ?? '').join(''), getAttribute: (k) => attrs[k] ?? null,
})
const tx = (s: string): PasteNode => ({ nodeType: 3, nodeName: '#text', childNodes: [], textContent: s })

describe('paste (pasteMarkdown): hostile HTML becomes plain Markdown text', () => {
  it('pasted text with markup characters reads back as the same text, with no link', () => {
    for (const v of HOSTILE.filter((x) => !/[\r\n]/.test(x))) {
      const md = htmlToMarkdown(el('BODY', {}, el('P', {}, tx(v))))
      expect(serverUnescape(md), v).toBe(v)
      expect(md, v).not.toMatch(/(^|[^\\])\]\(/)
    }
  })

  it('line breaks inside pasted text are spaces: they never start a heading or a list', () => {
    const md = htmlToMarkdown(el('BODY', {}, el('P', {}, tx('a\r\n# Heading\r\n- item'))))
    expect(md.split('\n')).toHaveLength(1)
    expect(serverUnescape(md)).toBe('a # Heading - item')
  })

  it('a <script> or <style> element is left out with its content', () => {
    const md = htmlToMarkdown(el('BODY', {}, el('P', {}, tx('before')), el('SCRIPT', {}, tx('alert(1)')), el('STYLE', {}, tx('p{}')), el('P', {}, tx('after'))))
    expect(md).toBe('before\n\nafter')
  })

  it('a link to a script, data or file address keeps only its label', () => {
    for (const u of SCRIPT_URLS) {
      const md = htmlToMarkdown(el('BODY', {}, el('P', {}, el('A', { href: u }, tx('click')))))
      expect(md, u).toBe('click')
    }
  })

  it('an address cannot close its link and open another one, or start a new line', () => {
    const md = htmlToMarkdown(el('BODY', {}, el('P', {}, el('A', { href: 'https://a.example/x) [y](javascript:alert(1)' }, tx('click')))))
    const parts = allParts(md)
    expect(parts.filter((p) => p.href).map((p) => p.href)).toEqual(['https://a.example/x%29%20[y]%28javascript:alert%281%29'])
    const crlf = htmlToMarkdown(el('BODY', {}, el('P', {}, el('A', { href: 'https://a.example/x\r\n# Heading\r\n- item' }, tx('click')))))
    expect(crlf.split('\n')).toHaveLength(1)
    expect(bodyBlocks(crlf).map((b) => b.kind)).toEqual(['para'])
  })
})

describe('web links (links.ts, askModel, page window): only http(s) opens', () => {
  it('a script, data or file address is no web address', () => {
    for (const u of SCRIPT_URLS) {
      expect(webUrl(u), u).toBe('')
      expect(loneLink(u), u).toBeNull()
      expect(splitLinks(`see ${u} now`).filter((p) => p.href), u).toEqual([])
    }
  })

  it('text around addresses comes back unchanged', () => {
    for (const v of HOSTILE) expect(splitLinks(v).map((p) => p.text).join(''), v).toBe(v)
  })

  it('a citation never links to a script address', () => {
    for (const u of SCRIPT_URLS) expect(citeTarget({ url: u, link: u, readOnly: true }, false), u).toEqual({ kind: 'list' })
  })

  it('the page window shows no Open button for a script address in a page\'s fields', () => {
    for (const u of SCRIPT_URLS) {
      const open = openButtons({ url: u, onenoteUrl: u }, false)
      expect(open.link, u).toBeNull()
      expect(open.onenote?.href, u).toBe('')
    }
    expect(openButtons({ url: ' https://a.example/x ', onenoteUrl: 'onenote:#p' }, false).link?.href).toBe('https://a.example/x')
  })
})

describe('search (query.ts): hostile words are words, never filters', () => {
  it('each value is searched for as text', () => {
    for (const v of HOSTILE.filter((x) => !/[\s"]/.test(x) && !x.includes(':'))) {
      expect(parseQuery(v), v).toEqual({ terms: [v.toLowerCase()], filters: [] })
    }
  })

  it('a topic name cannot close its quotes and add a filter', () => {
    const q = parseQuery(topicQuery('Security" type:meeting is:"archived'))
    expect(q.terms).toEqual([])
    expect(q.filters.map((f) => [f.key, f.label])).toEqual([['topic', 'Security type:meeting is:archived']])
  })
})
