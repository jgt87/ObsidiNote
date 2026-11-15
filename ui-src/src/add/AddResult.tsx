import { useState } from 'react'
import { Notice } from '../components/Notice'
import { webUrl } from '../model/links'
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
}

function CheckIcon() {
  return (
    <svg className="add-icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
      <path d="m3 8.5 3 3 7-7" />
    </svg>
  )
}

function RelatedPages({ pages }: { pages: PageRef[] }) {
  return (
    <>
      {pages.map((p, i) => (
        <span key={p.id}>
          {i > 0 && ', '}
          {p.link ? <a className="add-a" href={p.link}>{p.title}</a> : p.title}
        </span>
      ))}
    </>
  )
}

/** The row under the heading. Undo sends the page to OneNote's Deleted Pages: it asks first, as in
 *  History (AGENTS.md: delete always asks). */
function AddActionRow({ view, busy, a }: { view: AddResultView; busy: boolean; a: AddResultActions }) {
  const [askUndo, setAskUndo] = useState(false)
  if (askUndo) {
    return (
      <div className="add-actions">
        <span className="add-text">Undo this page? It goes to OneNote's Deleted Pages.</span>
        <button type="button" className="btn" onClick={() => setAskUndo(false)} disabled={busy}>
          Keep
        </button>
        <button type="button" className="btn btn--danger" onClick={a.onUndo} disabled={busy}>
          Undo
        </button>
      </div>
    )
  }
  return (
    <div className="add-actions">
      <button type="button" className="btn" onClick={a.onDone} disabled={busy}>
        Done
      </button>
      {view.editPlacement && a.onEditLinks && (
        <button type="button" className="btn" onClick={a.onEditLinks} disabled={busy}>
          Edit links
        </button>
      )}
      {view.editPlacement && a.onMoveInIndex && (
        <button type="button" className="btn" onClick={a.onMoveInIndex} disabled={busy}>
          Move in index
        </button>
      )}
      {view.updateLink && a.onUpdateLink && (
        <button type="button" className="btn" onClick={a.onUpdateLink} disabled={busy}>
          Update
        </button>
      )}
      {view.undo && a.onUndo && (
        <button type="button" className="btn" onClick={() => setAskUndo(true)} disabled={busy}>
          Undo
        </button>
      )}
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
        {page.link ? (
          <a className="add-a" href={page.link} title="Open in OneNote">
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
          <a className="add-a" href={url} target="_blank" rel="noopener noreferrer">
            {r.text.trim()}
          </a>
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
      <div className="add-result__top">
        <h1 className="add-result__title">{resultHeading(r.status, r.page?.title ?? '')}</h1>
        {v.written && (
          <div role="status" className="add-muted add-result__status">
            <CheckIcon />
            Written to OneNote · {formatSeconds(r.timings.totalMs)}
          </div>
        )}
      </div>

      {/* design (review 2026-11-14): the actions sit right under the heading, so "glance, accept,
          leave" needs no scroll. None is primary: the box's Send above is the view's one primary
          button (code review 2026-11-15: Send and Done were both). */}
      {v.actions && <AddActionRow view={v} busy={busy} a={a} />}

      {v.failed && (
        <Notice error title="Not added">
          <p>{r.message}</p>
          {r.inbox?.status === 'failed' && <p className="add-muted">The item is kept in your Intake with this reason, so nothing is lost.</p>}
          {r.related.length > 0 && (
            <p>
              Already there: <RelatedPages pages={r.related} />
            </p>
          )}
        </Notice>
      )}

      {isWaitingStatus(r.status) && <WaitingCard status={r.status} message={r.message} busy={busy} onCheck={r.inboxId ? a.onCheckAnswer : undefined} onDone={a.onDone} />}

      {v.askInstead && (
        <section className="add-card add-actions">
          <p className="add-text add-actions__text">{r.message}</p>
          {a.onAddAnyway && (
            <button type="button" className="btn" onClick={a.onAddAnyway} disabled={busy}>
              Add anyway
            </button>
          )}
          {a.onAsk && (
            <button type="button" className="btn" onClick={a.onAsk} disabled={busy}>
              Ask it
            </button>
          )}
        </section>
      )}

      {(v.text || v.placed) && (
        <section className="add-card add-card--parts">
          {v.placed && r.page && <PlacedGroup page={r.page} chips={r.chips} />}
          {v.text && <AddedText r={r} linkSummary={v.linkSummary} />}
        </section>
      )}

      {v.update && r.update && <LinkUpdateView update={r.update} status={r.status} />}
      {v.couldNotUpdate && (
        <section className="add-card" role="status">
          <p className="add-text">{r.message}</p>
        </section>
      )}

      {v.links && <LinksCard links={r.links} backlinks={r.backlinks} title={v.linksTitle} />}

      {v.related && (
        <p className="add-text add-related">
          Related pages you already had: <RelatedPages pages={r.related} />
        </p>
      )}

      {r.warnings.length > 0 && (
        <ul className="add-warnings" aria-label="Notes">
          {r.warnings.map((w, i) => (
            <li key={i} className="add-muted">
              {w}
            </li>
          ))}
        </ul>
      )}

      {v.confirm && r.confirm && a.onDecide && (
        <ConfirmReplaceDialog request={r.confirm} open busy={busy} onDecide={a.onDecide} onCancel={a.onCancelDecision ?? a.onDone} />
      )}
    </div>
  )
}
