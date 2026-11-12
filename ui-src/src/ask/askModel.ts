import type { AskParagraph, AskPath, AskProgressStep, AskResult, AskSource, AskStep } from './types'

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

export const PROGRESS_LABELS: Record<AskProgressStep, string> = {
  1: 'Finding branches...',
  2: 'Choosing pages...',
  3: 'Writing the answer...',
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
