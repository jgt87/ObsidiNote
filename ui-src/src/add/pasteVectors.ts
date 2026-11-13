// Test vectors for pasteMarkdown: invented pasted HTML, built as DOM-like nodes (no DOM library in
// the tests). The expected Markdown and its MarkdownLines reading live in
// tests/fixtures/paste-markdown.json, shared with tests/PasteMarkdown.Tests.ps1; the names match.
// Only tests import this file.
import type { PasteNode } from './pasteMarkdown'

type Child = PasteNode | string

export function txt(text: string): PasteNode {
  return { nodeType: 3, nodeName: '#text', childNodes: [], textContent: text }
}

export function comment(text: string): PasteNode {
  return { nodeType: 8, nodeName: '#comment', childNodes: [], textContent: text }
}

export function el(name: string, attrs: Record<string, string> = {}, ...children: Child[]): PasteNode {
  const childNodes = children.map((c) => (typeof c === 'string' ? txt(c) : c))
  return {
    nodeType: 1,
    nodeName: name.toUpperCase(),
    childNodes,
    get textContent() {
      return childNodes.map((c) => (c.nodeType === 8 ? '' : c.textContent ?? '')).join('')
    },
    getAttribute: (k: string) => (k in attrs ? attrs[k] : null),
  }
}

export function body(...children: Child[]): PasteNode {
  return el('body', {}, ...children)
}

const NBSP = ' '

/** A Word list paragraph: the bullet text sits in a span Word marks mso-list:Ignore. */
function wordItem(list: number, level: number, mark: string, text: string): PasteNode {
  return el('p', { class: 'MsoListParagraphCxSpMiddle', style: `margin-left:.5in;mso-list:l${list} level${level} lfo1` },
    el('span', { style: 'mso-list:Ignore' }, mark, el('span', {}, NBSP + NBSP + NBSP)), text)
}

export const PASTE_NODES: Record<string, () => PasteNode> = {
  'heading, paragraph, bold and italic': () =>
    body(el('h1', {}, 'Plan'), el('p', {}, 'Text with ', el('strong', {}, 'bold'), ' and ', el('em', {}, 'italic'), '.')),
  'nested bullet and numbered lists': () =>
    body(
      el('ul', {}, el('li', {}, 'One', el('ul', {}, el('li', {}, 'One a'), el('li', {}, 'One b'))), el('li', {}, 'Two')),
      '\n',
      el('ol', {}, el('li', {}, 'First'), el('li', {}, 'Second', el('ol', {}, el('li', {}, 'Inner')))),
    ),
  'table with a header row, an escaped pipe and a short row': () =>
    body(el('table', {},
      el('thead', {}, el('tr', {}, el('th', {}, 'Name'), el('th', {}, 'Note'))),
      el('tbody', {}, el('tr', {}, el('td', {}, 'A|B'), el('td', {}, el('strong', {}, 'yes'))), el('tr', {}, el('td', {}, el('p', {}, 'C')))),
    )),
  'links: http(s) and mailto kept, others as text': () =>
    body(el('p', {}, 'See ', el('a', { href: 'https://example.com/a b' }, 'the docs'), ', ',
      el('a', { href: 'mailto:someone@example.com' }, 'mail'), ' and ', el('a', { href: 'javascript:void(0)' }, 'script'), '.')),
  'inline code, strikethrough, code block and quote': () =>
    body(
      el('p', {}, 'Run ', el('code', {}, 'npm test'), ' not ', el('del', {}, 'old')),
      el('pre', {}, 'line 1\n  line 2\n'),
      el('blockquote', {}, el('p', {}, 'Quoted')),
    ),
  'script, style, comments and Office junk dropped, image marked': () =>
    body(
      el('style', {}, 'p { color: red }'),
      comment('[if gte mso 9]><xml>junk</xml><![endif]'),
      el('script', {}, 'alert(1)'),
      el('meta', { charset: 'utf-8' }),
      el('p', { class: 'MsoNormal' }, 'Kept', el('o:p', {}, NBSP)),
      el('p', { class: 'MsoNormal' }, el('o:p', {}, NBSP)),
      el('p', {}, 'Before ', el('img', { src: 'x.png', alt: 'chart' }), ' after'),
    ),
  'Word list paragraphs and a Google Docs bold wrapper': () =>
    body(
      wordItem(0, 1, '·', 'Alpha'),
      '\n',
      wordItem(0, 2, 'o', 'Beta'),
      el('p', { class: 'MsoNormal' }, 'Steps:'),
      wordItem(1, 1, '1.', 'Gamma'),
      wordItem(1, 1, '2.', 'Delta'),
      el('b', { style: 'font-weight:normal', id: 'docs-internal-guid-x' },
        el('p', {}, el('span', { style: 'font-weight:700' }, 'Bold'), el('span', { style: 'font-weight:400' }, ' plain'))),
    ),
  'line breaks, collapsed spaces and escaped line starts': () =>
    body(el('p', {}, '# not a heading', el('br'), '1. not a list', el('br'), '\n  a*b   with lots\n of   space  ')),
  'bold italic and spaces outside the markers': () =>
    body(el('p', {}, el('strong', {}, el('em', {}, 'both')), ' and ', el('b', {}, 'bold '), 'next')),
  'italic only: the server would not read it as Markdown': () => body(el('p', {}, 'A ', el('i', {}, 'quiet'), ' word.')),
}
