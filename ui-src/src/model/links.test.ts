import { describe, expect, it } from 'vitest'
import { splitLinks, webUrl } from './links'

describe('webUrl', () => {
  it('keeps http(s) addresses only', () => {
    expect(webUrl('https://example.org/a')).toBe('https://example.org/a')
    expect(webUrl(' http://example.org ')).toBe('http://example.org')
    expect(webUrl('onenote:https://example.org/x.one')).toBe('')
    expect(webUrl('javascript:alert(1)')).toBe('')
    expect(webUrl('https://')).toBe('')
    expect(webUrl(undefined)).toBe('')
  })
})

describe('splitLinks', () => {
  it('finds addresses in a sentence and leaves the full stop out', () => {
    const parts = splitLinks('See https://kb.example.org/msh?id=kb_article&sysparm_article=KB1. It has grades.')
    expect(parts).toEqual([
      { text: 'See ' },
      { text: 'https://kb.example.org/msh?id=kb_article&sysparm_article=KB1', href: 'https://kb.example.org/msh?id=kb_article&sysparm_article=KB1' },
      { text: '. It has grades.' },
    ])
  })
  it('handles several addresses, brackets and text without any', () => {
    expect(splitLinks('(https://a.example.org) and http://b.example.org/x,').filter((p) => p.href).map((p) => p.href)).toEqual([
      'https://a.example.org',
      'http://b.example.org/x',
    ])
    expect(splitLinks('no links here')).toEqual([{ text: 'no links here' }])
    expect(splitLinks('')).toEqual([])
  })
  it('gives the input back when the parts are joined', () => {
    const t = 'Go to https://example.org/a?b=c#d; then https://example.org/e.'
    expect(splitLinks(t).map((p) => p.text).join('')).toBe(t)
  })
})
