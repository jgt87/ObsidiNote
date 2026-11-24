import { useState } from 'react'
import { Icon } from '../components/icons'
import { unavailable } from '../components/disabledGuard'
import { Notice } from '../components/Notice'
import { WebLink } from '../components/WebLink'
import { oneNoteHref, webUrl } from '../model/links'
import { addResultView, type AddResultView } from './addResultView'
import { ConfirmReplaceDialog, type ReplaceDecision } from './ConfirmReplaceDialog'
import { chipLabel, formatOneNotePath, formatSeconds, formatTopicPath, placementParts, resultHeading } from './format'
import { LinksCard } from './LinksCard'
import { LinkUpdateView } from './LinkUpdateView'
import type { AddResult as AddResultData, PageRef, PlacedPage } from './types'
import { WaitingCard } from './WaitingCard'
import { isWaitingStatus } from './waiting'
import './AddResult.css'

export interface AddResultActions {
  onEditLinks?: () => void
  onMoveInIndex?: () => void
  onUndo?: () => void
  onDone: () => void
  /** "ask-instead": send the same text to Ask. */
  onAsk?: () => void
  /** "ask-instead": add it anyway (mode add). */
  onAddAnyway?: () => void
  /** "needs-confirmation": the person's choice; cancel closes the dialog without one. */
  onDecide?: (decision: ReplaceDecision) => void
  onCancelDecision?: () => void
  /** A link page: read the source again. */
  onUpdateLink?: () => void
  /** Waiting for Copilot: read its answer from the chat (POST /api/add/fetch). */
  onCheckAnswer?: () => void
  /** Not added as a duplicate: add it as a second page with that title (allowDuplicate). */
  onAddDuplicate?: () => void
  /** Not added as a duplicate: open the page that is already there in the page window. */
  onOpenPage?: (pageId: string) => void
}

function RelatedPages({ pages }: { pages: PageRef[] }) {
  return (
    <>
      {pages.map((p, i) => (
        <span key={p.id}>
          {i > 0 && ', '}
          {oneNoteHref(p.link) ? <a className="add-a" href={oneNoteHref(p.link)}>{p.title}</a> : p.title}
        </span>
      ))}
    </>
  )
}

/** The row under the heading. Undo sends the page to OneNote's Deleted Pages: it asks first, as in
 *  History (AGENTS.md: delete always asks). */
function AddActionRow({ view, busy, a }: { view: AddResultView; busy: boolean; a: AddResultActions }) {
  const [askUndo, setAskUndo] = useState(false)
  if (askUndo) return <ConfirmUndo busy={busy} onKeep={() => setAskUndo(false)} onUndo={a.onUndo} />
  return (
    <div className="add-actions">
      <button type="button" className="btn" onClick={a.onDone} {...unavailable(busy)}>
        Done
      </button>
      {OPTIONAL_ACTIONS.map(([shown, action, label]) => {
        const run = a[action]
        return view[shown] && run ? (
          <button key={label} type="button" className="btn" onClick={run} {...unavailable(busy)}>
            {label}
          </button>
        ) : null
      })}
      {view.undo && a.onUndo && (
        <button type="button" className="btn" onClick={() => setAskUndo(true)} {...unavailable(busy)}>
          Undo
        </button>
      )}
    </div>
  )
}

/** The buttons between Done and Undo, in their order: when the view offers them, and when the screen
 *  passed the action. */
const OPTIONAL_ACTIONS: [keyof AddResultView & ('editPlacement' | 'updateLink'), 'onEditLinks' | 'onMoveInIndex' | 'onUpdateLink', string][] = [
  ['editPlacement', 'onEditLinks', 'Edit links'],
  ['editPlacement', 'onMoveInIndex', 'Move in index'],
  ['updateLink', 'onUpdateLink', 'Update'],
]

function ConfirmUndo({ busy, onKeep, onUndo }: { busy: boolean; onKeep: () => void; onUndo?: () => void }) {
  return (
    <div className="add-actions">
      <span className="add-text">Undo this page? It goes to OneNote’s Deleted Pages.</span>
      <button type="button" className="btn" onClick={onKeep} {...unavailable(busy)}>
        Keep
      </button>
      <button type="button" className="btn btn--danger" onClick={onUndo} {...unavailable(busy)}>
        Undo
      </button>
    </div>
  )
}

/** Where the page was filed: its topic path, its OneNote place and its chips. */
function PlacedGroup({ page, chips }: { page: PlacedPage; chips: AddResultData['chips'] }) {
  return (
    <div aria-labelledby="add-placed-heading" role="group">
      <h2 id="add-placed-heading" className="add-label">
        {page.unfiled ? 'Filed under Unfiled, until it gets a topic' : 'Filed under'}
      </h2>
      <div className="add-path">
        {placementParts(page).map((part, i, all) =>
          i === all.length - 1 ? (
            <b key={i}>{part}</b>
          ) : (
            <span key={i}>
              {part}
              <span className="add-path__sep"> / </span>
            </span>
          ),
        )}
      </div>
      <div className="add-muted add-path__where">
        OneNote:{' '}
        {oneNoteHref(page.link) ? (
          <a className="add-a" href={oneNoteHref(page.link)} title="Open in OneNote">
            {formatOneNotePath(page)}
          </a>
        ) : (
          formatOneNotePath(page)
        )}
        {page.alsoUnder.length > 0 && <> · also under {page.alsoUnder.map(formatTopicPath).join(', ')}</>}
      </div>
      {chips.length > 0 && (
        <ul className="add-chips" aria-label="Type, aliases and topics">
          {chips.map((c, i) => (
            <li key={`${c.kind}:${c.label}:${i}`} className={c.kind === 'new-topic' ? 'add-chip add-chip--new' : 'add-chip'}>
              {chipLabel(c)}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

/** What the person added: the text, or the link (opened in the browser) with its new summary. */
function AddedText({ r, linkSummary }: { r: AddResultData; linkSummary: boolean }) {
  const url = r.kind === 'link' ? webUrl(r.text) : ''
  return (
    <div>
      <p className="add-label">{r.kind === 'link' ? 'The link' : 'What you added'}</p>
      {url ? (
        <p className="add-text add-text--pre">
          <WebLink className="add-a" href={url}>
            {r.text.trim()}
          </WebLink>
        </p>
      ) : (
        <p className="add-text add-text--pre">{r.text}</p>
      )}
      {linkSummary && <p className="add-text add-summary">{r.update?.new?.summary}</p>}
    </div>
  )
}

/** The Add result screen (mock-up AddResult): where the item was placed in the central index,
 *  its chips, its links with strength, anchor and why, related pages, and the actions. Also shows
 *  the link update (old vs new), its confirmation, failures and "ask instead". Which part shows
 *  when is decided in addResultView.ts. */
export function AddResult({ result, busy = false, ...a }: { result: AddResultData; busy?: boolean } & AddResultActions) {
  const r = result
  const v = addResultView(r)

  return (
    <div className="add-result">
      <ResultTop r={r} written={v.written} />

      {/* design (review 2026-11-14): the actions sit right under the heading, so "glance, accept,
          leave" needs no scroll. None is primary: the box's Send above is the view's one primary
          button (code review 2026-11-15: Send and Done were both). */}
      {v.actions && <AddActionRow view={v} busy={busy} a={a} />}

      {v.failed && <FailedNotice r={r} busy={busy} a={a} />}

      <Waiting r={r} busy={busy} a={a} />

      {v.askInstead && <AskInsteadCard message={r.message} busy={busy} onAddAnyway={a.onAddAnyway} onAsk={a.onAsk} />}

      <AddedParts r={r} v={v} />

      <UpdateParts r={r} v={v} />

      {v.links && <LinksCard links={r.links} backlinks={r.backlinks} title={v.linksTitle} />}

      {v.related && (
        <p className="add-text add-related">
          Related pages you already had: <RelatedPages pages={r.related} />
        </p>
      )}

      <Warnings warnings={r.warnings} />

      <ConfirmReplace r={r} v={v} busy={busy} a={a} />
    </div>
  )
}

/** Copilot is still at it: the item waits in the Intake; "Check for the answer" once it has an id. */
function Waiting({ r, busy, a }: { r: AddResultData; busy: boolean; a: AddResultActions }) {
  if (!isWaitingStatus(r.status)) return null
  return <WaitingCard status={r.status} message={r.message} busy={busy} onCheck={r.inboxId ? a.onCheckAnswer : undefined} onDone={a.onDone} />
}

/** A link page read again: the old and new summary, or why it could not be read. */
function UpdateParts({ r, v }: { r: AddResultData; v: AddResultView }) {
  return (
    <>
      {v.update && r.update && <LinkUpdateView update={r.update} status={r.status} />}
      {v.couldNotUpdate && (
        // Announced by the home view's one region (model/flowSay.ts), not by a region mounted with it.
        <section className="add-card">
          <p className="add-text">{r.message}</p>
        </section>
      )}
    </>
  )
}

/** A summary edited by hand would be replaced: the person decides (cancel = Done when the screen has
 *  no cancel of its own). */
function ConfirmReplace({ r, v, busy, a }: { r: AddResultData; v: AddResultView; busy: boolean; a: AddResultActions }) {
  if (!v.confirm || !r.confirm || !a.onDecide) return null
  return <ConfirmReplaceDialog request={r.confirm} open busy={busy} onDecide={a.onDecide} onCancel={a.onCancelDecision ?? a.onDone} />
}

/** The heading, and "Written to OneNote" with the time it took once something was written. */
function ResultTop({ r, written }: { r: AddResultData; written: boolean }) {
  return (
    <div className="add-result__top">
      <h1 className="add-result__title">{resultHeading(r.status, r.page?.title ?? '')}</h1>
      {written && (
        <div className="add-muted add-result__status">
          <Icon name="check" className="add-icon" />
          Written to OneNote · {formatSeconds(r.timings.totalMs)}
        </div>
      )}
    </div>
  )
}

/** Why nothing was added; that the item waits in the Intake; pages it matched that were there. A
 *  page with the same title and type (duplicateOf) can be opened, or this one added anyway. */
function FailedNotice({ r, busy, a }: { r: AddResultData; busy: boolean; a: AddResultActions }) {
  const dup = r.duplicateOf
  const actions = dup && (a.onOpenPage || a.onAddDuplicate) ? (
    <>
      {a.onOpenPage && (
        <button type="button" className="btn btn--sm" onClick={() => a.onOpenPage?.(dup)} {...unavailable(busy)}>
          Open it
        </button>
      )}
      {a.onAddDuplicate && (
        <button type="button" className="btn btn--sm" onClick={a.onAddDuplicate} {...unavailable(busy)}>
          Add anyway
        </button>
      )}
    </>
  ) : undefined
  return (
    <Notice error title="Not added" actions={actions}>
      <p>{r.message}</p>
      {r.inbox?.status === 'failed' && <p className="add-muted">The item is kept in your Intake with this reason, so nothing is lost.</p>}
      {r.related.length > 0 && (
        <p>
          Already there: <RelatedPages pages={r.related} />
        </p>
      )}
    </Notice>
  )
}

/** The text reads as a question: add it anyway, or ask it. */
function AskInsteadCard({ message, busy, onAddAnyway, onAsk }: { message: string; busy: boolean; onAddAnyway?: () => void; onAsk?: () => void }) {
  return (
    <section className="add-card add-actions">
      <p className="add-text add-actions__text">{message}</p>
      {onAddAnyway && (
        <button type="button" className="btn" onClick={onAddAnyway} {...unavailable(busy)}>
          Add anyway
        </button>
      )}
      {onAsk && (
        <button type="button" className="btn" onClick={onAsk} {...unavailable(busy)}>
          Ask it
        </button>
      )}
    </section>
  )
}

/** Where the page was filed and what was added, in one card; nothing when neither shows. */
function AddedParts({ r, v }: { r: AddResultData; v: AddResultView }) {
  if (!v.text && !v.placed) return null
  return (
    <section className="add-card add-card--parts">
      {v.placed && r.page && <PlacedGroup page={r.page} chips={r.chips} />}
      {v.text && <AddedText r={r} linkSummary={v.linkSummary} />}
    </section>
  )
}

function Warnings({ warnings }: { warnings: string[] }) {
  if (!warnings.length) return null
  return (
    <ul className="add-warnings" aria-label="Notes">
      {warnings.map((w, i) => (
        <li key={i} className="add-muted">
          {w}
        </li>
      ))}
    </ul>
  )
}
