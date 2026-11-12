// The Add result as the server returns it (lib/Ingest.psm1: Invoke-AddRequest, Update-LinkSummary,
// Undo-AddRequest). normalizeAddResult turns Windows PowerShell's one-item lists (sent as a bare
// object) and empty lists (sent as null) back into arrays.
import { asList } from '../api'

export type AddStatus =
  | 'added'
  | 'failed'
  | 'updated'
  | 'unchanged'
  | 'kept'
  | 'needs-confirmation'
  | 'could-not-update'
  | 'ask-instead'

export type ChipKind = 'type' | 'alias' | 'topic' | 'new-topic'

export interface Chip {
  kind: ChipKind
  label: string
  path?: string
}

export interface PlacedPage {
  id: string
  title: string
  type: string
  bucket: string
  section: string
  link: string
  url: string
  /** First topic path, parts joined with "/"; '' when the page is Unfiled. */
  topicPath: string
  alsoUnder: string[]
  /** Vault, section (group parts split), page title. */
  oneNotePath: string[]
  unfiled: boolean
}

export interface ResultLink {
  target: string
  title: string
  link: string
  anchor: string
  strength: number
  why: string
}

export interface PageRef {
  id: string
  title: string
  link: string
}

export interface Dropped {
  what: string
  value: string
  reason: string
}

export interface LinkSummary {
  title: string
  where: string
  kind: string
  summary: string
  keyFacts: string[]
  useFor: string
  sensitivity: string
}

export interface SummaryDiff {
  changed: boolean
  title?: boolean
  kind?: boolean
  where?: boolean
  summary?: boolean
  useFor?: boolean
  sensitivity?: boolean
  factsAdded: string[]
  factsRemoved: string[]
}

export interface ReviewLink {
  target: string
  title: string
  link: string
  reason: string
}

export interface LinkUpdate {
  old: LinkSummary | null
  new: LinkSummary | null
  diff: SummaryDiff | null
  oldAt: string
  newAt: string
  review: ReviewLink[]
}

export interface ConfirmRequest {
  id: string
  question: string
  detail: string
  options: ('replace' | 'keep')[]
  editedText: string
  proposed: LinkSummary
}

export interface UndoRecord {
  id: string
  pageId: string
  targets: string[]
}

export interface Timings {
  totalMs: number
  inboxMs: number
  copilotMs: number
  writeMs: number
  indexMs: number
}

export interface AddResult {
  status: AddStatus
  kind: 'text' | 'link'
  message: string
  text: string
  page: PlacedPage | null
  chips: Chip[]
  links: ResultLink[]
  backlinks: number
  related: PageRef[]
  dropped: Dropped[]
  warnings: string[]
  timings: Timings
  undo: UndoRecord | null
  inbox: { pageId: string; status: string } | null
  update: LinkUpdate | null
  confirm: ConfirmRequest | null
}

export interface UndoResult {
  status: 'undone' | 'failed'
  message: string
  id: string
  backlinks: number
  warnings: string[]
  ms: number
}

type Loose<T> = { [K in keyof T]?: T[K] | null } | null | undefined

function normalizeSummary(s: Loose<LinkSummary>): LinkSummary | null {
  if (!s) return null
  return {
    title: s.title ?? '',
    where: s.where ?? '',
    kind: s.kind ?? '',
    summary: s.summary ?? '',
    keyFacts: asList(s.keyFacts),
    useFor: s.useFor ?? '',
    sensitivity: s.sensitivity ?? '',
  }
}

export function normalizeAddResult(raw: Loose<AddResult>): AddResult {
  const r = raw ?? {}
  const page = r.page ? { ...r.page, alsoUnder: asList(r.page.alsoUnder), oneNotePath: asList(r.page.oneNotePath) } : null
  const u = r.update
  const update: LinkUpdate | null = u
    ? {
        old: normalizeSummary(u.old),
        new: normalizeSummary(u.new),
        diff: u.diff ? { ...u.diff, factsAdded: asList(u.diff.factsAdded), factsRemoved: asList(u.diff.factsRemoved) } : null,
        oldAt: u.oldAt ?? '',
        newAt: u.newAt ?? '',
        review: asList(u.review),
      }
    : null
  const c = r.confirm
  const proposed = c ? normalizeSummary(c.proposed) : null
  return {
    status: r.status ?? 'failed',
    kind: r.kind ?? 'text',
    message: r.message ?? '',
    text: r.text ?? '',
    page,
    chips: asList(r.chips),
    links: asList(r.links),
    backlinks: r.backlinks ?? 0,
    related: asList(r.related),
    dropped: asList(r.dropped),
    warnings: asList(r.warnings),
    timings: r.timings ?? { totalMs: 0, inboxMs: 0, copilotMs: 0, writeMs: 0, indexMs: 0 },
    undo: r.undo ? { ...r.undo, targets: asList(r.undo.targets) } : null,
    inbox: r.inbox ?? null,
    update,
    confirm: c && proposed ? { ...c, options: asList(c.options), proposed } as ConfirmRequest : null,
  }
}
