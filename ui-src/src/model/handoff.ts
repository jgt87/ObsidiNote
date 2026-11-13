// Text handed from one flow to another. Pure (tests: handoff.test.ts).
// Ask never writes: "Save answer as a page" and "Save as an Open question" turn Ask's page spec
// into the text of an Add, which files it like anything else. "Ask about this" on the map fills
// the composer with a question about that page.
import type { AskPageSpec } from '../ask/types'

function asList<T>(v: T[] | T | null | undefined): T[] {
  return v == null ? [] : Array.isArray(v) ? v : [v]
}

/** The Add text for an Ask page spec: title, the question, the answer and the sources it cites. */
export function pageSpecToText(spec: AskPageSpec): string {
  const body = (spec.body ?? {}) as { question?: unknown; paragraphs?: unknown; sources?: unknown }
  const lines: string[] = [spec.openQuestion ? `Open question: ${spec.title}` : spec.title, '']
  if (typeof body.question === 'string' && body.question && body.question !== spec.title) lines.push(`Question: ${body.question}`, '')
  const paras = asList(body.paragraphs as string[] | string | null).filter((p) => typeof p === 'string' && p.trim())
  if (paras.length) lines.push(...paras.flatMap((p) => [p, '']))
  else if (spec.openQuestion) lines.push('Not answered yet: nothing in the wiki answers this.', '')
  const sources = asList(body.sources as { n?: number; title?: string; path?: string }[] | null)
  if (sources.length) {
    lines.push('Sources:')
    for (const s of sources) lines.push(`[${s.n ?? ''}] ${s.title ?? ''}${s.path ? ` (${s.path})` : ''}`)
  }
  for (const r of asList(spec.references)) lines.push(`Also read: ${r.title}${r.source ? ` (${r.source}, read only)` : ''}`)
  return lines.join('\n').replace(/\n{3,}/g, '\n\n').trim()
}

/** The question "Ask about this" puts in the composer for a page of the map. */
export function askAboutText(title: string): string {
  return `What do my notes say about "${title}"?`
}
