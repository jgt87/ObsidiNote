import { describe, expect, it } from 'vitest'
import { answerShares, citeChipView, citeTarget, combinedLine, droppedCitationsNote, list, normalizeAskResult, notFoundText, pathChips, sentencesPerSource, sharePercent, sourceAnchor } from './askModel'
import type { AskResult } from './types'

describe('citeTarget: where a citation [n] leads', () => {
  const page = { url: '', link: 'onenote:https://team.example/Wiki.one#Page', readOnly: false }
  it('a link page opens its own address, whatever else it has', () => {
    expect(citeTarget({ ...page, url: 'https://example.com/a' }, true)).toEqual({ kind: 'url', href: 'https://example.com/a' })
  })
  it('a page of the active vault opens its page window when the window can, else OneNote', () => {
    expect(citeTarget(page, true)).toEqual({ kind: 'page' })
    expect(citeTarget(page, false)).toEqual({ kind: 'onenote', href: page.link })
  })
  it('a page of another vault or notebook opens in OneNote; nothing to open gives the list', () => {
    expect(citeTarget({ ...page, readOnly: true }, true)).toEqual({ kind: 'onenote', href: page.link })
    expect(citeTarget({ url: 'javascript:alert(1)', link: 'https://x.example', readOnly: true }, true)).toEqual({ kind: 'list' })
    expect(citeTarget(undefined, true)).toEqual({ kind: 'list' })
  })
})

// Invented example data only.
function result(over: Partial<AskResult> = {}): AskResult {
  return {
    ok: true,
    status: 'answered',
    conversationId: 'c1',
    turn: 1,
    question: 'What did we decide about the example portal?',
    writes: 0,
    note: 'Asking never changes your notebook.',
    message: '',
    path: {
      branchesTotal: 6,
      branchesPicked: 2,
      pagesTotal: 19,
      pagesPicked: 4,
      pagesRead: 4,
      invalidBranches: 0,
      invalidPages: 0,
      steps: [
        { n: 1, kind: 'index', label: 'Index' },
        {
          n: 2,
          kind: 'branches',
          label: 'Security / Networking + Projects',
          branches: [
            { path: 'Security / Networking', key: 'Security/Networking', source: 'Vault', readOnly: false, why: '' },
            { path: 'Recipes', key: 's2.Recipes', source: 'Other notebook', readOnly: true, why: '' },
          ],
        },
        { n: 3, kind: 'pages', label: '4 pages read', count: 4 },
      ],
      summary: 'Copilot picked 2 of 6 top-level branches, then 4 of 19 pages. Nothing outside these pages was used.',
    },
    answer: { paragraphs: [{ sentences: [{ text: 'A.', cites: [1], unsupported: false }] }], confidence: 'high' },
    sources: [],
    unused: [],
    staleLinks: [],
    invalidCitations: [],
    notFound: null,
    ...over,
  }
}

describe('list', () => {
  it('turns one item or null into a list', () => {
    expect(list(null)).toEqual([])
    expect(list(3)).toEqual([3])
    expect(list([1, 2])).toEqual([1, 2])
  })
})

describe('normalizeAskResult', () => {
  it('makes one-item and empty lists from the server into arrays', () => {
    const raw = result({
      sources: { n: 1, title: 'One' } as unknown as AskResult['sources'],
      invalidCitations: null as unknown as string[],
      answer: { paragraphs: { sentences: { text: 'A.', cites: 1, unsupported: false } } as unknown as AskResult['sources'], confidence: 'low' } as unknown as AskResult['answer'],
    })
    const r = normalizeAskResult(raw)
    expect(r.sources).toHaveLength(1)
    expect(r.invalidCitations).toEqual([])
    expect(r.answer?.paragraphs[0].sentences[0].cites).toEqual([1])
    // an older server sends no unused list at all
    expect(normalizeAskResult({ ...raw, unused: undefined as unknown as AskResult['unused'] }).unused).toEqual([])
  })
})

describe('pathChips', () => {
  it('shows Index, each branch (the first numbered 2, then joined by +), then the pages', () => {
    const chips = pathChips(result().path)
    expect(chips.map((c) => [c.n, c.label, c.before])).toEqual([
      [1, 'Index', ''],
      [2, 'Security / Networking', '>'],
      [null, 'Recipes', '+'],
      [3, '4 pages read', '>'],
    ])
    expect(chips[2].note).toBe('Other notebook, read only')
  })
  it('is empty without a path', () => {
    expect(pathChips(null)).toEqual([])
  })
})

describe('wording', () => {
  it('explains each not-found reason', () => {
    expect(notFoundText('no-branch')).toMatch(/No branch/)
    expect(notFoundText('no-valid-citations')).toMatch(/not shown/)
    expect(notFoundText(undefined)).toMatch(/do not answer/)
  })
  it('gives each source row an anchor per conversation and turn', () => {
    expect(sourceAnchor('c1', 2, 3)).toBe('ask-c1-2-src-3')
  })
})

describe('what an answer was made from (D-017)', () => {
  const src = (n: number, path: string) => ({ n, id: `p${n}`, key: `p${n}`, title: `Page ${n}`, path, link: '', updated: '', age: '', type: '', archived: false, sourceId: 'v1', sourceName: '', readOnly: false, stale: false, summarizedAge: '' })
  it('says how many pages from how many topics', () => {
    expect(combinedLine([src(1, 'Security / Networking'), src(2, 'Projects'), src(3, 'Security / Networking')])).toBe('Combined from 3 pages in 2 topics.')
    expect(combinedLine([src(1, 'A'), src(2, 'A')])).toBe('Combined from 2 pages in 1 topic.')
    expect(combinedLine([src(1, 'A')])).toBe('')
  })
  it('counts the sentences that cite each page, once per sentence', () => {
    const m = sentencesPerSource([{ sentences: [{ text: 'a', cites: [1, 2] }, { text: 'b', cites: [1, 1] }] }, { sentences: [{ text: 'c', cites: [2] }] }] as never)
    expect(m.get(1)).toBe(2)
    expect(m.get(2)).toBe(2)
    expect(m.get(3)).toBeUndefined()
  })
})

describe('answerShares: how much of the answer came from each source (2026-11-14)', () => {
  it('splits each cited sentence over its sources by length; uncited sentences do not count', () => {
    const m = answerShares([{ sentences: [{ text: 'aaaaaaaaaa', cites: [1], unsupported: false }, { text: 'bbbbbbbbbb', cites: [1, 2], unsupported: false }, { text: 'no source here', cites: [], unsupported: true }] }] as never)
    expect(m.get(1)).toBeCloseTo(0.75)
    expect(m.get(2)).toBeCloseTo(0.25)
    expect([...m.values()].reduce((a, b) => a + b, 0)).toBeCloseTo(1)
  })
  it('gives nothing for an answer without citations, and shows small shares as at least 1%', () => {
    expect(answerShares([]).size).toBe(0)
    expect(sharePercent(0.004)).toBe(1)
    expect(sharePercent(0)).toBe(0)
    expect(sharePercent(0.756)).toBe(76)
  })
})

describe('citeChipView', () => {
  it('a web address opens in a new tab, OneNote in place, a vault page as a button, else the list', () => {
    expect(citeChipView(1, 'Guide', { kind: 'url', href: 'https://example.com/g' }, 'a1')).toEqual({ tag: 'a', href: 'https://example.com/g', newTab: true, title: 'https://example.com/g', label: 'Source 1: Guide, opens the link' })
    expect(citeChipView(2, 'Notes', { kind: 'onenote', href: 'onenote:#x' }, 'a2')).toEqual({ tag: 'a', href: 'onenote:#x', newTab: false, title: 'Open in OneNote', label: 'Source 2: Notes, opens in OneNote' })
    expect(citeChipView(3, 'Plan', { kind: 'page' }, 'a3')).toEqual({ tag: 'button', title: 'Open Plan', label: 'Source 3: Plan, opens the page' })
    expect(citeChipView(7, undefined, { kind: 'list' }, 'a7')).toEqual({ tag: 'a', href: '#a7', newTab: false, label: 'Source 7: ' })
  })
})

describe('droppedCitationsNote', () => {
  it('says how many citations were left out, in one or many', () => {
    expect(droppedCitationsNote(0)).toBe('')
    expect(droppedCitationsNote(1)).toBe(' One citation pointed to a page that was not read and was left out.')
    expect(droppedCitationsNote(3)).toBe(' 3 citations pointed to a page that was not read and were left out.')
  })
})
