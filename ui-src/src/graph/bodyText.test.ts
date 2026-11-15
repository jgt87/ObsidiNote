import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { bodyBlocks, inlineParts, linkTarget, type Block, type Part } from './bodyText'

// What the server really sends: tests/PageBody.Tests.ps1 compares this file with the converter's
// own output for invented pages. A change of the format changes this file, and then this test.
const fixture = JSON.parse(readFileSync(new URL('../../../tests/fixtures/page-body.json', import.meta.url), 'utf8')) as { cases: { name: string; markdown: string }[] }
const body = (name: string): Block[] => {
  const c = fixture.cases.find((x) => x.name === name)
  if (!c) throw new Error(`no fixture case "${name}"`)
  return bodyBlocks(c.markdown)
}
const text = (parts: Part[]) => parts.map((p) => p.text).join('')
const kinds = (blocks: Block[]) => blocks.map((b) => (b.kind === 'heading' ? `h${b.level}` : b.kind))

describe('bodyBlocks: the page text the server sends, as blocks', () => {
  it('reads every case of the shared fixture', () => {
    expect(fixture.cases.map((c) => c.name)).toEqual([
      'headings and styled text',
      'bulleted, numbered and task lists',
      'a table',
      'code',
      'links',
      'outlines: summary, properties and Linked from left out, Your notes kept',
      'an empty page',
    ])
    for (const c of fixture.cases) expect(() => bodyBlocks(c.markdown)).not.toThrow()
  })

  it('headings and styled text; escaped signs and a raw tag stay text', () => {
    const b = body('headings and styled text')
    expect(kinds(b)).toEqual(['h1', 'h2', 'h3', 'para', 'para', 'h2'])
    const styled = (b[3] as { parts: Part[] }).parts
    expect(styled.filter((p) => p.bold).map((p) => p.text)).toEqual(['who'])
    expect(styled.filter((p) => p.italic).map((p) => p.text)).toEqual(['from where'])
    expect(styled.filter((p) => p.strike).map((p) => p.text)).toEqual(['where from'])
    expect(text((b[4] as { parts: Part[] }).parts)).toBe('Plain text keeps its signs: 2 * 3, snake_case, [brackets] & a <tag>.')
  })

  it('lists: nesting, numbers and tasks', () => {
    const b = body('bulleted, numbered and task lists')
    expect(kinds(b)).toEqual(['para', 'list', 'para', 'list', 'para', 'list'])
    const [bullets, numbers, tasks] = b.filter((x) => x.kind === 'list') as Extract<Block, { kind: 'list' }>[]
    expect(bullets.ordered).toBe(false)
    expect(bullets.items.map((i) => [i.depth, text(i.parts)])).toEqual([[0, 'Check the user'], [1, 'with a second factor'], [1, 'on every request'], [0, 'Check the device']])
    expect(numbers.ordered).toBe(true)
    expect(numbers.items.map((i) => text(i.parts))).toEqual(['Plan', 'Roll out', 'Review'])
    expect(tasks.items.map((i) => [i.done, text(i.parts)])).toEqual([[false, 'ask the network team'], [true, 'read the guide']])
  })

  it('a table: the head, the rows, an escaped bar and an empty cell', () => {
    const t = body('a table').find((x) => x.kind === 'table') as Extract<Block, { kind: 'table' }>
    expect(t.head.map(text)).toEqual(['Name', 'Use'])
    expect(t.rows.map((r) => r.map(text))).toEqual([['Proxy', 'checks a|b'], ['vpn', '']])
    expect(t.rows[1][0][0].code).toBe(true)
  })

  it('code keeps its signs as they are', () => {
    const b = body('code') as { parts: Part[] }[]
    expect(b[0].parts.find((p) => p.code)?.text).toBe('proxy --check a_b*c')
    expect(b[2].parts).toEqual([{ text: 'else { stop <now> }', code: true }])
  })

  it('links: pages of the map, addresses that may be opened, and never a script', () => {
    const parts = (body('links') as { parts: Part[] }[]).flatMap((b) => b.parts)
    expect(parts.filter((p) => p.pageId).map((p) => [p.text, p.pageId])).toEqual([
      ['the portal', 'p2'],
      ['Partner portal', 'p2'],
      ['the list', 'n:{44444444-4444-4444-4444-444444444444}{1}{E1}'],
    ])
    expect(parts.filter((p) => p.href).map((p) => p.href)).toEqual([
      'https://example.com/guide?a=1&b=2',
      'http://example.com/a%20%28b%29/c',
      'https://example.com/bare',
      'mailto:someone@example.com',
      'onenote:https://team.example/Elsewhere.one#Other%20page&page-id={99999999-9999-9999-9999-999999999999}&end',
    ])
    expect(text(parts)).toContain('Never a script: click me, a file or data.')
  })

  it('keeps Your notes and the image line; an empty page has no blocks', () => {
    const b = body('outlines: summary, properties and Linked from left out, Your notes kept')
    expect(kinds(b)).toEqual(['para', 'para', 'h2', 'para', 'para'])
    expect((b[1] as { parts: Part[] }).parts).toEqual([{ text: '(An image, drawing or attached file is not shown here.)', italic: true }])
    expect(body('an empty page')).toEqual([])
  })
})

describe('linkTarget and inlineParts: what is never a link', () => {
  it('refuses every address that is not http, https, mailto, onenote or a page of the map', () => {
    for (const bad of ['javascript:alert(1)', 'JAVASCRIPT:alert(1)', 'data:text/html,x', 'file:///c:/x', 'vbscript:x', '//example.com', '/api/x', ' https://example.com', 'obsn:']) {
      expect(linkTarget(bad), bad).toEqual({})
    }
    expect(inlineParts('[click me](javascript:alert(1))')[0]).toEqual({ text: 'click me' })
  })

  it('leaves a lone bracket, a lone backtick and an unfinished link as text', () => {
    expect(text(inlineParts('a [b] c'))).toBe('a [b] c')
    expect(text(inlineParts('a ` b'))).toBe('a ` b')
    expect(inlineParts('[x](https://example.com')).toEqual([{ text: '[x](https://example.com' }])
  })

  it('carries bold into a link label', () => {
    expect(inlineParts('[**the** guide](https://example.com/g)')).toEqual([
      { text: 'the', bold: true, href: 'https://example.com/g' },
      { text: ' guide', href: 'https://example.com/g' },
    ])
  })
})
