// Archive, Restore and Delete in the window: the server's plan and result (lib/Ingest.psm1
// Get-RetirePlan / Invoke-PageRetire, POST /api/pages/archive|restore|delete) and the confirm
// dialog's wording. Pure (tests: retireModel.test.ts). FEASIBILITY.md "Archive and delete": both
// always ask first (no "don't ask again"); Restore is the undo of an archive and asks nothing.

import { asList } from '../api'

export type RetireAction = 'archive' | 'restore' | 'delete'
export type AskingAction = Exclude<RetireAction, 'restore'>

export interface RetirePlanPage {
  id: string
  title: string
  /** The section it is in now ("Notes", "Journal/2026"). */
  section: string
  /** Where it goes ("Archive/Notes"); '' for delete. */
  to: string
  /** How many other pages link to it. */
  inbound: number
}

export interface RetireRefusal {
  id: string
  title: string
  reason: string
}

export interface RetirePlan {
  pages: RetirePlanPage[]
  refused: RetireRefusal[]
}

export interface RetireResult {
  status: 'done' | 'partial' | 'failed'
  message: string
  action: RetireAction
  done: { id: string; title: string; to: string }[]
  refused: RetireRefusal[]
  failed: { id: string; title: string; error: string }[]
  warnings: string[]
}

const str = (v: unknown): string => (typeof v === 'string' ? v : '')
const rec = (v: unknown): Record<string, unknown> => (v && typeof v === 'object' ? (v as Record<string, unknown>) : {})

function refusals(v: unknown): RetireRefusal[] {
  return asList(v as unknown[]).map(rec).map((r) => ({ id: str(r.id), title: str(r.title), reason: str(r.reason) }))
}

/** The plan of a 409 needsConfirm answer (Windows PowerShell sends a list of one as an object). */
export function parsePlan(v: unknown): RetirePlan {
  const p = rec(v)
  const pages = asList(p.pages as unknown[])
    .map(rec)
    .filter((r) => str(r.id))
    .map((r) => ({ id: str(r.id), title: str(r.title) || str(r.id), section: str(r.section), to: str(r.to), inbound: typeof r.inbound === 'number' ? r.inbound : 0 }))
  return { pages, refused: refusals(p.refused) }
}

export function parseResult(v: unknown, action: RetireAction): RetireResult {
  const r = rec(v)
  const status = r.status === 'done' || r.status === 'partial' ? r.status : 'failed'
  return {
    status,
    message: str(r.message),
    action,
    done: asList(r.done as unknown[]).map(rec).map((d) => ({ id: str(d.id), title: str(d.title), to: str(d.to) })),
    refused: refusals(r.refused),
    failed: asList(r.failed as unknown[]).map(rec).map((d) => ({ id: str(d.id), title: str(d.title), error: str(d.error) })),
    warnings: asList(r.warnings as unknown[]).map(str).filter(Boolean),
  }
}

/** "Archive/Web links" -> "Archive / Web links", as the side bar writes section paths. */
export function sectionLabel(path: string): string {
  return path.split('/').map((s) => s.trim()).filter(Boolean).join(' / ')
}

export interface ConfirmWording {
  title: string
  lines: string[]
  confirm: string
  busy: string
}

/** The confirm dialog: the question with its object, what happens, how to get it back. */
export function confirmWording(action: AskingAction, plan: RetirePlan): ConfirmWording {
  const n = plan.pages.length
  const one = n === 1 ? plan.pages[0] : null
  const object = one ? `"${one.title}"` : `${n} pages`
  const inbound = plan.pages.reduce((s, p) => s + p.inbound, 0)
  if (action === 'archive') {
    const where = [...new Set(plan.pages.map((p) => sectionLabel(p.to)))]
    return {
      title: `Archive ${object}?`,
      lines: [
        one
          ? `It moves to ${sectionLabel(one.to)}. Its links stay, and Restore puts it back where it was.`
          : where.length === 1
            ? `They move to ${where[0]}. Their links stay, and Restore puts them back where they were.`
            : 'Each moves to the Archive section of its own type (listed below). Their links stay, and Restore puts them back where they were.',
        'Archived pages are left out of Ask and hidden on the map until you show archived pages in Filter.',
      ],
      confirm: n === 1 ? 'Archive' : `Archive ${n} pages`,
      busy: 'Archiving…',
    }
  }
  const lines = [`${one ? 'It goes' : 'They go'} to OneNote's Deleted Pages, which keeps deleted pages for 60 days; get ${one ? 'it' : 'them'} back there if you need to.`]
  if (inbound) lines.push(`${inbound === 1 ? '1 link' : `${inbound} links`} from other pages ${inbound === 1 ? 'points' : 'point'} here; ${inbound === 1 ? 'it becomes' : 'they become'} plain text "(deleted: ${one ? one.title : 'its title'})".`)
  lines.push('Archive keeps a page out of the way and can be undone here.')
  return { title: `Delete ${object}?`, lines, confirm: n === 1 ? 'Delete' : `Delete ${n} pages`, busy: 'Deleting…' }
}

/** One line per page that will not be included, with the reason. */
export function refusedLines(plan: { refused: RetireRefusal[] }): string[] {
  return plan.refused.map((r) => `${r.title || 'A page'} is left out: ${r.reason}`)
}

/** The line the window shows after the result: the server's message plus each failure. */
export function resultLines(r: RetireResult): string[] {
  const out = [r.message || (r.status === 'failed' ? 'Nothing was changed.' : '')]
  for (const f of r.failed) out.push(`${f.title || f.id}: ${f.error}`)
  return out.filter(Boolean)
}
