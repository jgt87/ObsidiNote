import { webUrl } from '../model/links'
import type { AskParagraph, AskPath, AskResult, AskSource, AskStep } from './types'

/**
 * Where a citation [n] leads (operator, 2026-11-15: open the page or the direct link, whichever is
 * most relevant): a link page's own http(s) address; else a page of the active vault in its page
 * window (when the window can open one); else the page in OneNote; else the source in the list.
 */
export type CiteTarget = { kind: 'url' | 'onenote'; href: string } | { kind: 'page' } | { kind: 'list' }
export function citeTarget(source: Pick<AskSource, 'url' | 'link' | 'readOnly'> | undefined, canOpenPage: boolean): CiteTarget {
  if (!source) return { kind: 'list' }
  const url = webUrl(source.url)
  if (url) return { kind: 'url', href: url }
  if (!source.readOnly && canOpenPage) return { kind: 'page' }
  if (/^onenote:/i.test(source.link ?? '')) return { kind: 'onenote', href: source.link }
  return { kind: 'list' }
}

/** What a citation [n] is: a link (its address, a new tab for a web address) or a button that opens
 *  the page window; its tooltip and its name for a screen reader. `title` is the cited source's
 *  title, undefined when the number names no source read. */
export type CiteChipView =
  | { tag: 'a'; href: string; newTab: boolean; title?: string; label: string }
  | { tag: 'button'; title: string; label: string }
export function citeChipView(n: number, title: string | undefined, go: CiteTarget, anchor: string): CiteChipView {
  const name = `Source ${n}: ${title ?? ''}`
  if (go.kind === 'url') return { tag: 'a', href: go.href, newTab: true, title: go.href, label: `${name}, opens the link` }
  if (go.kind === 'onenote') return { tag: 'a', href: go.href, newTab: false, title: 'Open in OneNote', label: `${name}, opens in OneNote` }
  if (go.kind === 'page' && title !== undefined) return { tag: 'button', title: `Open ${title}`, label: `${name}, opens the page` }
  return { tag: 'a', href: `#${anchor}`, newTab: false, label: name }
}

/** Windows PowerShell can hand a one-item or empty list over as an object or null. */
export function list<T>(value: T[] | T | null | undefined): T[] {
  if (value == null) return []
  return Array.isArray(value) ? value : [value]
}

function normalizePath(p: AskPath | null | undefined): AskPath | null {
  if (!p) return null
  return {
    ...p,
    steps: list(p.steps).map((s: AskStep) => ({ ...s, branches: s.branches == null ? undefined : list(s.branches) })),
  }
}

function normalizeParagraphs(ps: AskParagraph[] | AskParagraph | null | undefined): AskParagraph[] {
  return list(ps).map((p) => ({
    sentences: list(p.sentences).map((s) => ({ text: String(s.text ?? ''), cites: list(s.cites).map(Number), unsupported: Boolean(s.unsupported) })),
  }))
}

/** Makes every list a list, whatever the server's JSON did with one-item or empty lists. */
export function normalizeAskResult(raw: AskResult): AskResult {
  return {
    ...raw,
    path: normalizePath(raw.path),
    answer: raw.answer ? { ...raw.answer, paragraphs: normalizeParagraphs(raw.answer.paragraphs) } : null,
    sources: list(raw.sources),
    unused: list(raw.unused),
    staleLinks: list(raw.staleLinks),
    invalidCitations: list(raw.invalidCitations),
    notFound: raw.notFound
      ? {
          ...raw.notFound,
          suggestion: {
            ...raw.notFound.suggestion,
            pageSpec: {
              ...raw.notFound.suggestion.pageSpec,
              topics: list(raw.notFound.suggestion.pageSpec.topics),
              links: list(raw.notFound.suggestion.pageSpec.links),
              references: list(raw.notFound.suggestion.pageSpec.references),
            },
          },
        }
      : null,
  }
}


/** The anchor id of a source row, the target of its citation chips. */
export function sourceAnchor(conversationId: string, turn: number, n: number): string {
  return `ask-${conversationId || 'x'}-${turn}-src-${n}`
}

/** Path chips: "Index", then each picked branch (the first carries step number 2), then "N pages read". */
export interface PathChip {
  n: number | null
  label: string
  /** The separator shown before this chip: none for the first, '+' between branches, '>' between steps. */
  before: '' | '+' | '>'
  note?: string
}

export function pathChips(path: AskPath | null): PathChip[] {
  if (!path) return []
  const chips: PathChip[] = []
  for (const step of path.steps) {
    const before = chips.length ? '>' : ''
    if (step.kind === 'branches' && step.branches && step.branches.length) {
      step.branches.forEach((b, i) => {
        chips.push({ n: i === 0 ? step.n : null, label: b.path, before: i === 0 ? before : '+', note: b.readOnly ? `${b.source}, read only` : undefined })
      })
    } else {
      chips.push({ n: step.n, label: step.label, before })
    }
  }
  return chips
}

/** "Confidence: high" wording for the answer card. */
export function confidenceLabel(c: string | undefined): string {
  if (c === 'high') return 'The pages answer this directly.'
  if (c === 'medium') return 'The pages answer this in part; some reading between the lines.'
  return 'The pages give only a partial answer.'
}

/** The note after the confidence line when citations to pages that were not read were dropped
 *  (with its leading space), else ''. */
export function droppedCitationsNote(dropped: number): string {
  if (dropped <= 0) return ''
  return ` ${dropped === 1 ? 'One citation pointed' : `${dropped} citations pointed`} to a page that was not read and ${dropped === 1 ? 'was' : 'were'} left out.`
}

/** Where a source comes from, when it is not the active vault. */
export function sourceOrigin(s: AskSource): string {
  return s.readOnly && s.sourceName ? `${s.sourceName} (read only)` : ''
}

export function notFoundText(reason: string | undefined): string {
  switch (reason) {
    case 'no-branch':
      return 'No branch of your index covers this question.'
    case 'no-page':
      return 'The branches that fit hold no page about this.'
    case 'no-valid-citations':
      return 'The answer did not point to any page that was read, so it is not shown.'
    default:
      return 'The pages that were read do not answer it.'
  }
}

/** "Combined from 5 pages in 3 topics": how many cited pages the answer joins, and from how many
 *  topics (their index paths). '' for an answer from one page (operator, 2026-11-14). */
export function combinedLine(sources: AskSource[]): string {
  if (sources.length < 2) return ''
  const topics = new Set(sources.map((s) => s.path || '(no topic)'))
  return `Combined from ${sources.length} pages in ${topics.size} ${topics.size === 1 ? 'topic' : 'topics'}.`
}

/** How many sentences of the answer cite each source number. */
export function sentencesPerSource(paragraphs: AskParagraph[]): Map<number, number> {
  const m = new Map<number, number>()
  for (const p of paragraphs) for (const s of p.sentences) for (const n of new Set(s.cites)) m.set(n, (m.get(n) ?? 0) + 1)
  return m
}

/** What share of the answer came from each source (operator, 2026-11-14: "a bar ... how much of the
 *  answer came from each source"). Each cited sentence's length is split evenly over the sources it
 *  cites; sentences without a source are left out, so the shares of the cited sources add up to 1.
 *  Returns source number -> share (0..1). */
export function answerShares(paragraphs: AskParagraph[]): Map<number, number> {
  const chars = new Map<number, number>()
  let total = 0
  for (const p of paragraphs)
    for (const s of p.sentences) {
      const cites = [...new Set(s.cites)]
      if (!cites.length) continue
      const len = Math.max(1, s.text.trim().length)
      total += len
      for (const n of cites) chars.set(n, (chars.get(n) ?? 0) + len / cites.length)
    }
  const out = new Map<number, number>()
  if (!total) return out
  for (const [n, c] of chars) out.set(n, c / total)
  return out
}

/** A share as a whole percent for the label; a share above 0 never shows as 0%. */
export function sharePercent(share: number): number {
  if (share <= 0) return 0
  return Math.max(1, Math.round(share * 100))
}
