// The local server's API (lib/Server.psm1). Every call carries X-ObsidiNote: 1, which the server
// requires; the page keeps nothing it reads here in storage.
// The Add and Ask result shapes live with their views (src/add, src/ask); this module only routes.
import { normalizeAddResult, type AddResult } from './add/types'
import { normalizeAskResult } from './ask/askModel'
import type { AskResult } from './ask/types'
import { normalizeSettings, type VaultSettings } from './model/vaultSettings'

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
  /** The page's id in the knowledge graph (obsn id, or n:<OneNote id>); '' from an older server. */
  pageId?: string
  /** ObsidiNote's page type ('' for the person's own pages). */
  type?: string
}

/** An entry of the notebook switcher. vault = an ObsidiNote vault (found by its state page; a whole
 *  notebook, or a section group inside one); others are open notebooks, read only. */
export interface NotebookSummary {
  id: string
  name: string
  vault: boolean
  active: boolean
  location: string
  /** The vault's own id (obsn.vaultId); '' for a read-only notebook. */
  vaultId?: string
  kind?: 'notebook' | 'sectiongroup'
  notebookId?: string
  /** Only in a notebook view: an empty notebook (no pages, no section groups) that holds no vault
   *  and can be set up as one in place (POST /api/vault/setup). */
  canSetUp?: boolean
}

/** writer = this ObsidiNote may add to the active vault; readonly = another one is writing there. */
export type VaultMode = 'writer' | 'readonly' | 'none'

export interface NotebookList {
  notebooks: NotebookSummary[]
  message: string
  activeVaultId: string
  mode: VaultMode
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
  copilot: { state: CopilotState; port: number; ready?: boolean }
  /** reason (when mode is not writer): 'other-pc' = an ObsidiNote on another PC holds the writer
   *  lease; 'this-pc' = an earlier run on this PC still holds it; 'not-opened' = the start could not
   *  open a vault. since = when the holder took the lease (ISO, '' unknown); detail = the start's
   *  line for 'not-opened'. Older servers send name, vaultId and mode only. */
  vault?: { name: string; vaultId: string; mode: VaultMode; reason?: string; since?: string; detail?: string }
}

/** What POST /api/submit answers: an Add result or an Ask result, told apart by intent. */
export type SubmitResult = ({ intent: 'add' } & AddResult) | ({ intent: 'ask' } & AskResult)

/** The body of a submit: text and mode, plus Ask's choices (read-only sources, archived pages). */
export interface SubmitRequest {
  text: string
  mode: Mode
  sources?: string[]
  includeArchived?: boolean
  /** Where an Add's text came from (model/origins.ts); left out = typed. */
  origin?: string
  /** A dropped file's OneDrive/SharePoint address (locateFile): the Add makes that file's link page. */
  fileUrl?: string
}

const HEADERS: Record<string, string> = { 'X-ObsidiNote': '1' }

export interface LocateResult {
  status: 'found' | 'none' | 'many' | 'no-sync'
  url: string
}

/** Looks for a dropped file in the folders OneDrive syncs on this PC (name, size, time only; the
 *  browser never says where a dropped file is). */
export function locateFile(name: string, size: number, modified: number): Promise<LocateResult> {
  return call<LocateResult>('/api/file/locate', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name, size, modified }) })
}

export class ApiError extends Error {
  constructor(message: string, readonly status: number) {
    super(message)
  }
}

/** What the person reads when the local server does not answer at all. */
export const NO_ANSWER = 'ObsidiNote did not answer. Check that it is still running: its console window must stay open.'

/** fetch, with a failed connection as a sentence (the browser's own "Failed to fetch" tells the
 *  person nothing; review 2026-11-14). A cancelled call stays a cancelled call. */
export async function request(path: string, init: RequestInit = {}): Promise<Response> {
  try {
    return await fetch(path, init)
  } catch (e) {
    if ((e as { name?: string } | null)?.name === 'AbortError') throw e
    throw new ApiError(NO_ANSWER, 0)
  }
}

async function call<T>(path: string, init: RequestInit = {}, okStatuses: number[] = [200]): Promise<T> {
  const res = await request(path, { ...init, headers: { ...HEADERS, ...(init.headers ?? {}) }, cache: 'no-store' })
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

export interface ReconnectResult {
  state: 'connected' | 'sign-in' | 'failed'
  message: string
}

/** One try to attach to Copilot in ObsidiNote's Edge window again (the side bar's refresh button). */
export function reconnectCopilot(): Promise<ReconnectResult> {
  return call<ReconnectResult>('/api/copilot/reconnect', { method: 'POST' })
}

export async function getNotebooks(): Promise<NotebookList> {
  const l = await call<NotebookList>('/api/notebooks')
  return { notebooks: asList(l.notebooks), message: l.message ?? '', activeVaultId: l.activeVaultId ?? '', mode: l.mode ?? 'none' }
}

/** One notebook's structure and recent pages; without an id the active vault. */
export async function getNotebook(id?: string | null): Promise<NotebookView> {
  const v = await call<NotebookView>(id ? `/api/notebook?id=${encodeURIComponent(id)}` : '/api/notebook')
  return { ...v, sections: normalizeSections(v.sections), recent: asList(v.recent) }
}

/** Makes an open vault the active one: the server takes its writer lease and the start reopens it. */
export function setActiveVault(id: string): Promise<{ id: string; name: string; vaultId: string; mode: VaultMode }> {
  return call('/api/active-vault', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id }) })
}

export interface NewVaultResult {
  id: string
  vaultId: string
  name: string
  kind: 'notebook' | 'sectiongroup'
  mode: VaultMode
  warning: string
}

/** A new vault: its own notebook, or (inNotebook, only with confirm) a section group inside an open
 *  notebook. A 409 with needsConfirm asks for the confirm first (ApiError.status 409). */
export function newVault(name: string, inNotebook?: string, confirm = false): Promise<NewVaultResult> {
  return call('/api/vault/new', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name, inNotebook: inNotebook ?? '', confirm }) })
}

/** Sets up an open, empty notebook as a vault in place and makes it active. The caller has asked
 *  the person first (confirm); without it the server answers 409 needsConfirm and writes nothing. */
export function setUpVault(id: string, confirm: boolean): Promise<NewVaultResult> {
  return call('/api/vault/setup', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id, confirm }) })
}

export interface SettingsAnswer {
  settings: VaultSettings
  /** False in a read-only window or without a vault: the settings are shown, not changed. */
  canChange: boolean
  /** Why nothing can be saved, when the server says so (stored settings that cannot be read). */
  message: string
}

/** The active vault's settings, kept in OneNote (GET /api/settings). */
export async function getSettings(): Promise<SettingsAnswer> {
  const r = await call<{ settings: unknown; canChange: unknown; message?: unknown }>('/api/settings')
  return { settings: normalizeSettings(r.settings), canChange: r.canChange === true, message: typeof r.message === 'string' ? r.message : '' }
}

/** Changes one vault setting in OneNote; the answer is the settings as they are now. */
export async function saveSetting<K extends keyof VaultSettings>(key: K, value: VaultSettings[K]): Promise<SettingsAnswer> {
  const r = await call<{ settings: unknown; canChange: unknown }>('/api/settings', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ key, value }) })
  return { settings: normalizeSettings(r.settings), canChange: r.canChange === true, message: '' }
}

function postJson(text: string, mode: Mode, signal?: AbortSignal): RequestInit {
  return { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text, mode }), signal }
}

export function getIntent(text: string, mode: Mode, signal?: AbortSignal): Promise<IntentResult> {
  return call<IntentResult>('/api/intent', postJson(text, mode, signal))
}

/** Add or Ask by mode and intent (the server decides auto). 503 = Copilot is not connected, 409 = no
 *  active vault: both throw ApiError with the server's message. */
export async function submit(req: SubmitRequest, signal?: AbortSignal): Promise<SubmitResult> {
  // origin and fileUrl go along only when set (2026-11-14: origin was left out here, so "From"
  // never reached the server; api.test.ts now checks the body that is sent).
  const body = {
    text: req.text,
    mode: req.mode,
    sources: req.sources ?? [],
    includeArchived: Boolean(req.includeArchived),
    ...(req.origin ? { origin: req.origin } : {}),
    ...(req.fileUrl ? { fileUrl: req.fileUrl } : {}),
  }
  const raw = await call<Record<string, unknown>>('/api/submit', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal })
  return normalizeSubmitResult(raw)
}

/** Tells an Add answer from an Ask answer and repairs the lists either one holds. */
export function normalizeSubmitResult(raw: Record<string, unknown>): SubmitResult {
  if (raw.intent === 'ask') {
    if (raw.ok === false) throw new ApiError(String(raw.error ?? 'Ask did not work.'), 200)
    return { ...normalizeAskResult(raw as unknown as AskResult), intent: 'ask' }
  }
  return { ...normalizeAddResult(raw as Parameters<typeof normalizeAddResult>[0]), intent: 'add' }
}
