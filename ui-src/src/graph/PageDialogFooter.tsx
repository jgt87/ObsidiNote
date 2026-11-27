// The page window's footer (PageDialog.tsx): open the page, ask about it, edit, archive or delete it,
// export it or focus the map on it. Which actions show is decided in pageDialogModel.ts. Render only.
import { unavailable } from '../components/disabledGuard'
import type { ReactNode } from 'react'
import { WebLink } from '../components/WebLink'
import { ExportButton } from '../export/ExportButton'
import type { ExportRequest } from '../export/exportApi'
import type { GraphPage } from './model'
import { footerOffers, openButtons } from './pageDialogModel'
import type { RetireAction } from './retireModel'

/** Which source an export reads (export/exportApi.ts exportSourceOf). */
export type ExportSource = Pick<ExportRequest, 'vault' | 'notebook'>

export interface DialogFooterProps {
  page: GraphPage
  editing: boolean
  readOnly: boolean
  why: string
  src: ExportSource
  onAsk?: (page: GraphPage, within?: { series: string; count: number }) => void
  /** How many meetings the page's series has (0: not a meeting of a series). */
  seriesCount?: number
  /** Edit is offered (the active vault's page with an edit action). */
  canEdit: boolean
  onToggleEdit: () => void
  onRetirePages?: (action: RetireAction, ids: string[]) => void
  /** "Merge duplicates" of the series (a series page only, with `copies` second copies of meetings). */
  onMergePages?: (series: string) => void
  copies?: number
  onFocusPage?: () => void
  /** The keys line: "Esc closes" and what the arrows do here. */
  keys: ReactNode
}

export function DialogFooter({ page, editing, readOnly, why, src, onAsk, seriesCount = 0, canEdit, onToggleEdit, onRetirePages, onMergePages, copies = 0, onFocusPage, keys }: DialogFooterProps) {
  const offers = footerOffers({ page, readOnly, seriesCount, copies, canAsk: !!onAsk, canMerge: !!onMergePages, canRetire: !!onRetirePages })
  const series = page.series ?? ''
  return (
    <footer className="kg-dlg__foot">
      <OpenButtons page={page} editing={editing} />
      <button type="button" className="btn" onClick={() => onAsk?.(page)} {...unavailable(!onAsk)}>
        Ask about this
      </button>
      {offers.askSeries && (
        <button type="button" className="btn" onClick={() => onAsk?.(page, { series, count: seriesCount })}>
          Ask about this series
        </button>
      )}
      {/* The series page offers it only when a meeting of the series has a second copy (2026-11-19). */}
      {offers.merge && (
        <button type="button" className="btn" onClick={() => onMergePages?.(series)}>
          Merge duplicates ({copies})
        </button>
      )}
      <EditButton readOnly={readOnly} why={why} canEdit={canEdit} editing={editing} onToggleEdit={onToggleEdit} />
      <RetireButtons page={page} action={offers.retire} onRetirePages={onRetirePages} />
      {/* The two that leave the page (a file, the map) sit apart at the right, quiet. */}
      <span className="kg-dlg__side">
        <ExportButton request={{ scope: 'page', page: page.id, ...src }} label="Export as Markdown" className="btn btn--ghost" />
        {onFocusPage && (
          <button type="button" className="btn btn--ghost" title="Show only this page and its linked pages" onClick={onFocusPage}>
            Focus on this page
          </button>
        )}
      </span>
      {readOnly && (
        <span id="kg-dlg-why" className="kg-dlg__why">
          {why}
        </span>
      )}
      {keys}
    </footer>
  )
}

/** "Open link" and "Open in OneNote". A link page opens its own address first; OneNote is the second
 *  choice (D-005). */
function OpenButtons({ page, editing }: { page: GraphPage; editing: boolean }) {
  // design: one primary per view. While the Edit form is open its Save is the primary, so the
  // footer's goes quiet.
  const open = openButtons(page, editing)
  const look = (primary: boolean) => (primary ? 'btn btn--primary' : 'btn')
  return (
    <>
      {open.link && (
        <WebLink className={look(open.link.primary)} href={open.link.href} title={open.link.href}>
          Open link
        </WebLink>
      )}
      {open.onenote &&
        (open.onenote.href ? (
          <a className={look(open.onenote.primary)} href={open.onenote.href}>
            Open in OneNote
          </a>
        ) : (
          <button type="button" className={look(open.onenote.primary)} aria-disabled="true" title="This page has no OneNote link">
            Open in OneNote
          </button>
        ))}
    </>
  )
}

/** Edit: a toggle for the Edit form where pages can be changed; in a read-only window shown greyed out
 *  with the reason. */
function EditButton({ readOnly, why, canEdit, editing, onToggleEdit }: { readOnly: boolean; why: string; canEdit: boolean; editing: boolean; onToggleEdit: () => void }) {
  return (
    <>
      {readOnly && (
        // Shown, not hidden: a missing button gave no hint that pages can be edited at all, or why
        // not here. Focusable, so the reason is reachable by keyboard; it does nothing.
        <button type="button" className="btn" aria-disabled="true" aria-describedby="kg-dlg-why" title={why}>
          Edit
        </button>
      )}
      {canEdit && (
        <button type="button" className="btn" aria-pressed={editing} onClick={onToggleEdit}>
          Edit
        </button>
      )}
    </>
  )
}

/** Archive (or Restore) and Delete. Archive is the default way out of sight and can be undone; Delete
 *  asks too (FEASIBILITY.md "Archive and delete"). */
function RetireButtons({ page, action, onRetirePages }: { page: GraphPage; action: 'archive' | 'restore' | null; onRetirePages?: (action: RetireAction, ids: string[]) => void }) {
  if (!action) return null
  return (
    <>
      <button type="button" className="btn" onClick={() => onRetirePages?.(action, [page.id])}>
        {action === 'restore' ? 'Restore' : 'Archive'}
      </button>
      <button type="button" className="btn btn--danger" onClick={() => onRetirePages?.('delete', [page.id])}>
        Delete
      </button>
    </>
  )
}
