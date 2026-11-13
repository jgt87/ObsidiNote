import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { escapeText, hasStructure, htmlToMarkdown, looksLikeMarkdown, markdownForPaste, type PasteNode } from './pasteMarkdown'
import { PASTE_NODES, body, el, txt } from './pasteVectors'

const fixture = fileURLToPath(new URL('../../../tests/fixtures/paste-markdown.json', import.meta.url))
const VECTORS = JSON.parse(readFileSync(fixture, 'utf8')) as { name: string; markdown: string; markdownText: boolean }[]

describe('looksLikeMarkdown: the same answer as the server\'s Test-MarkdownText on every vector', () => {
  for (const v of VECTORS) {
    it(v.name, () => {
      expect(looksLikeMarkdown(v.markdown)).toBe(v.markdownText)
    })
  }
})

describe('htmlToMarkdown: the shared vectors (their Markdown also goes through MarkdownLines in tests/PasteMarkdown.Tests.ps1)', () => {
  it('has a node builder for every vector and a vector for every builder', () => {
    expect(VECTORS.map((v) => v.name).sort()).toEqual(Object.keys(PASTE_NODES).sort())
  })
  for (const v of VECTORS) {
    it(v.name, () => {
      expect(htmlToMarkdown(PASTE_NODES[v.name]())).toBe(v.markdown)
    })
  }
})

describe('hasStructure', () => {
  it('is false for plain paragraphs, true for a list, a heading, a table, bold, italic or a link', () => {
    expect(hasStructure(body(el('p', {}, txt('One.')), el('p', {}, txt('Two.'))))).toBe(false)
    expect(hasStructure(body(el('ul', {}, el('li', {}, txt('a')))))).toBe(true)
    expect(hasStructure(body(el('h2', {}, txt('a'))))).toBe(true)
    expect(hasStructure(body(el('table', {}, el('tr', {}, el('td', {}, txt('a'))))))).toBe(true)
    expect(hasStructure(body(el('p', {}, el('strong', {}, txt('a')))))).toBe(true)
    expect(hasStructure(body(el('p', {}, el('em', {}, txt('a')))))).toBe(true)
    expect(hasStructure(body(el('p', {}, el('a', { href: 'https://example.com' }, txt('a')))))).toBe(true)
  })
  it('does not count a javascript: link or Google Docs\' normal-weight <b> wrapper', () => {
    expect(hasStructure(body(el('p', {}, el('a', { href: 'javascript:alert(1)' }, txt('a')))))).toBe(false)
    expect(hasStructure(body(el('b', { style: 'font-weight:normal' }, el('p', {}, txt('a')))))).toBe(false)
  })
  it('counts a Word list paragraph', () => {
    expect(hasStructure(body(el('p', { class: 'MsoListParagraph', style: 'mso-list:l0 level1 lfo1' }, txt('a'))))).toBe(true)
  })
})

describe('markdownForPaste', () => {
  const parse = (n: PasteNode) => () => n
  it('gives null for empty HTML or HTML without structure (the browser pastes the plain text)', () => {
    expect(markdownForPaste('', parse(body()))).toBeNull()
    expect(markdownForPaste('<p>x</p>', parse(body(el('p', {}, txt('Just text.')))))).toBeNull()
    expect(markdownForPaste('<p>x</p>', () => null)).toBeNull()
  })
  it('gives null when the only structure is one the server would not convert (italic alone)', () => {
    expect(markdownForPaste('<i>', parse(body(el('p', {}, 'A ', el('i', {}, 'quiet'), ' word.'))))).toBeNull()
  })
  it('gives the Markdown when there is structure', () => {
    expect(markdownForPaste('<ul>', parse(body(el('ul', {}, el('li', {}, txt('a')), el('li', {}, txt('b'))))))).toBe('- a\n- b')
  })
})

describe('escapeText', () => {
  it('escapes Markdown characters, and a backslash only before one of them', () => {
    expect(escapeText('a*b_c`d[e]f~g|h<i')).toBe('a\\*b\\_c\\`d\\[e\\]f\\~g\\|h\\<i')
    expect(escapeText('D:\\Data\\x')).toBe('D:\\Data\\x')
    expect(escapeText('a\\.b')).toBe('a\\\\.b')
  })
})
