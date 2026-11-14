// The shapes lib/Ask.psm1 (Invoke-AskRequest) returns through /api/submit with mode ask.
// Windows PowerShell may hand a one-item or empty list over as an object or null, so every list
// goes through normalizeAskResult before a component sees it.

export type AskStatus = 'answered' | 'not-found' | 'error' | 'page-spec'
export type Confidence = 'high' | 'medium' | 'low'

export interface AskBranch {
  path: string
  key: string
  source: string
  readOnly: boolean
  why: string
}

export interface AskStep {
  n: number
  kind: 'index' | 'branches' | 'pages'
  label: string
  branches?: AskBranch[]
  count?: number
}

export interface AskPath {
  followUp?: boolean
  branchesTotal: number
  branchesPicked: number
  pagesTotal: number
  pagesPicked: number
  pagesRead: number
  invalidBranches: number
  invalidPages: number
  steps: AskStep[]
  summary: string
}

export interface AskSentence {
  text: string
  /** Source numbers (1-based, the order of the sources list). */
  cites: number[]
  /** True when every citation of this sentence was dropped (it named a page that was not sent). */
  unsupported: boolean
}

export interface AskParagraph {
  sentences: AskSentence[]
}

export interface AskSource {
  n: number
  id: string
  key: string
  title: string
  path: string
  /** onenote: link to the page (secondary: the interface sends people to OneNote as little as possible). */
  link: string
  /** A link page's original http(s) address; opened first when set. */
  url?: string
  updated: string
  age: string
  type: string
  archived: boolean
  sourceId: string
  sourceName: string
  readOnly: boolean
  stale: boolean
  summarizedAge: string
}

export interface AskStaleLink {
  n: number
  id: string
  title: string
  summarizedAt: string
  ageDays: number
  offer: 'update'
  label: string
}

export interface AskPageSpec {
  type: 'note'
  openQuestion: boolean
  origin: 'ask'
  title: string
  topics: string[]
  body: Record<string, unknown>
  links: { target: string; strength: number; why: string }[]
  references: { title: string; link: string; source: string }[]
}

export interface AskNotFound {
  reason: 'no-branch' | 'no-page' | 'not-in-pages' | 'no-valid-citations'
  message: string
  suggestion: { action: 'save-open-question'; label: string; pageSpec: AskPageSpec }
  /** A follow-up found nothing in the earlier pages: asking it as a new question may help. */
  askNew: boolean
}

export interface AskResult {
  ok: boolean
  status: AskStatus
  conversationId: string
  turn: number
  question: string
  writes: number
  note: string
  message: string
  error?: string
  path: AskPath | null
  answer: { paragraphs: AskParagraph[]; confidence: Confidence } | null
  sources: AskSource[]
  staleLinks: AskStaleLink[]
  invalidCitations: string[]
  notFound: AskNotFound | null
}

/** A request to Invoke-AskRequest (the body of POST /api/submit with mode ask). */
export interface AskRequest {
  mode: 'ask'
  action: 'ask' | 'follow-up' | 'save-page' | 'save-open-question'
  question?: string
  /** Read-only vaults or connected notebooks to read besides the active vault (their ids). */
  sources?: string[]
  includeArchived?: boolean
  conversationId?: string
  turn?: number
}

/** The three Copilot steps, as the progress state shows them. */
export type AskProgressStep = 1 | 2 | 3
