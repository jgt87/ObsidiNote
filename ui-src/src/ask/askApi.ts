import { normalizeAskResult } from './askModel'
import type { AskPageSpec, AskRequest, AskResult } from './types'

// Ask goes through POST /api/submit with mode ask (lib/Ask.psm1, Invoke-AskRequest). Asking never
// writes: "Save answer as a page" and "Save as an Open question" return a page spec that the Add
// flow writes. Nothing here is kept in storage: questions and answers are the person's content.

const HEADERS: Record<string, string> = { 'X-ObsidiNote': '1', 'Content-Type': 'application/json' }

async function post(body: AskRequest, signal?: AbortSignal): Promise<Record<string, unknown>> {
  const res = await fetch('/api/submit', { method: 'POST', headers: HEADERS, body: JSON.stringify(body), signal, cache: 'no-store' })
  const data: unknown = await res.json().catch(() => null)
  if (!res.ok || !data || typeof data !== 'object') {
    const msg = data && typeof data === 'object' && 'error' in data ? String((data as { error: unknown }).error) : `The server answered ${res.status}.`
    throw new Error(msg)
  }
  const obj = data as Record<string, unknown>
  if (obj.ok === false) throw new Error(String(obj.error ?? 'Ask did not work.'))
  return obj
}

export async function ask(question: string, opts: { sources?: string[]; includeArchived?: boolean } = {}, signal?: AbortSignal): Promise<AskResult> {
  const r = await post({ mode: 'ask', action: 'ask', question, sources: opts.sources ?? [], includeArchived: Boolean(opts.includeArchived) }, signal)
  return normalizeAskResult(r as unknown as AskResult)
}

export async function askFollowUp(conversationId: string, question: string, signal?: AbortSignal): Promise<AskResult> {
  const r = await post({ mode: 'ask', action: 'follow-up', conversationId, question }, signal)
  return normalizeAskResult(r as unknown as AskResult)
}

/** The page spec for "Save answer as a page" (written by the Add flow, not here). */
export async function answerPageSpec(conversationId: string, turn?: number): Promise<AskPageSpec> {
  const r = await post({ mode: 'ask', action: 'save-page', conversationId, turn })
  return r.pageSpec as AskPageSpec
}

/** The page spec for "Save as an Open question" (written by the Add flow, not here). */
export async function openQuestionSpec(question: string, conversationId?: string): Promise<AskPageSpec> {
  const r = await post({ mode: 'ask', action: 'save-open-question', question, conversationId })
  return r.pageSpec as AskPageSpec
}
