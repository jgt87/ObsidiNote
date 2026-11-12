// The local server's API (lib/Server.psm1). Every call carries X-ObsidiNote: 1, which the server
// requires; the page keeps nothing it reads here in storage.

export type Mode = 'auto' | 'add' | 'ask'
export type Intent = 'add' | 'ask' | 'unclear' | 'empty'

export interface IntentResult {
  intent: Intent
  reason: string
  rule: number
}

export interface SectionNode {
  name: string
  kind: 'section' | 'group'
  pages: number
  children: SectionNode[]
}

export interface RecentPage {
  title: string
  section: string
  modified: string
  link: string
}

/** An open OneNote notebook. vault = an ObsidiNote vault (writable later); others are read only. */
export interface NotebookSummary {
  id: string
  name: string
  vault: boolean
  active: boolean
  location: string
}

export interface NotebookList {
  notebooks: NotebookSummary[]
  message: string
}

export interface NotebookView {
  available: boolean
  notFound?: boolean
  message: string
  notebook: NotebookSummary | null
  sections: SectionNode[]
  totals: { sections: number; pages: number }
  recent: RecentPage[]
}

export type OneNoteState = 'window' | 'background' | 'none'
export type CopilotState = 'connected' | 'no-tab' | 'not-running' | 'skipped'

export interface AppStatus {
  app: string
  version: string
  uiPort: number
  oneNote: { state: OneNoteState; running: boolean; notebookOpen: boolean; notebook: string }
  copilot: { state: CopilotState; port: number }
}

export interface SubmitResult {
  intent: Intent
  message: string
}

const HEADERS: Record<string, string> = { 'X-ObsidiNote': '1' }

export class ApiError extends Error {
  constructor(message: string, readonly status: number) {
    super(message)
  }
}

async function call<T>(path: string, init: RequestInit = {}, okStatuses: number[] = [200]): Promise<T> {
  const res = await fetch(path, { ...init, headers: { ...HEADERS, ...(init.headers ?? {}) }, cache: 'no-store' })
  const body: unknown = await res.json().catch(() => null)
  if (!okStatuses.includes(res.status)) {
    const msg = body && typeof body === 'object' && 'error' in body ? String((body as { error: unknown }).error) : `The server answered ${res.status}.`
    throw new ApiError(msg, res.status)
  }
  return body as T
}

/** Windows PowerShell can hand a one-item or empty list over as an object or null. */
export function asList<T>(value: T[] | T | null | undefined): T[] {
  if (value == null) return []
  return Array.isArray(value) ? value : [value]
}

function normalizeSections(nodes: SectionNode[] | SectionNode | null | undefined): SectionNode[] {
  return asList(nodes).map((n) => ({ ...n, children: normalizeSections(n.children) }))
}

export function getStatus(): Promise<AppStatus> {
  return call<AppStatus>('/api/status')
}

export async function getNotebooks(): Promise<NotebookList> {
  const l = await call<NotebookList>('/api/notebooks')
  return { notebooks: asList(l.notebooks), message: l.message ?? '' }
}

/** One notebook's structure and recent pages; without an id the active vault. */
export async function getNotebook(id?: string | null): Promise<NotebookView> {
  const v = await call<NotebookView>(id ? `/api/notebook?id=${encodeURIComponent(id)}` : '/api/notebook')
  return { ...v, sections: normalizeSections(v.sections), recent: asList(v.recent) }
}

/** Makes an open vault the active one (the start reopens it). Writes no notebook. */
export function setActiveVault(id: string): Promise<{ id: string; name: string }> {
  return call('/api/active-vault', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id }) })
}

function postJson(text: string, mode: Mode, signal?: AbortSignal): RequestInit {
  return { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text, mode }), signal }
}

export function getIntent(text: string, mode: Mode, signal?: AbortSignal): Promise<IntentResult> {
  return call<IntentResult>('/api/intent', postJson(text, mode, signal))
}

/** Step 1: the server answers 501 with what comes next; that is a normal result here. */
export function submit(text: string, mode: Mode): Promise<SubmitResult> {
  return call<SubmitResult>('/api/submit', postJson(text, mode), [200, 501])
}
