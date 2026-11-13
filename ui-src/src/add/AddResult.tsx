import { ConfirmReplaceDialog, type ReplaceDecision } from './ConfirmReplaceDialog'
import { chipLabel, formatOneNotePath, formatSeconds, formatTopicPath, placementParts, resultHeading } from './format'
import { LinksCard } from './LinksCard'
import { LinkUpdateView } from './LinkUpdateView'
import type { AddResult as AddResultData } from './types'
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

/** The Add result screen (mock-up AddResult): where the item was placed in the central index,
 *  its chips, its links with strength, anchor and why, related pages, and the actions. Also shows
 *  the link update (old vs new), its confirmation, failures and "ask instead". */
export function AddResult({ result, busy = false, ...a }: { result: AddResultData; busy?: boolean } & AddResultActions) {
  const r = result
  const title = r.page?.title ?? ''
  const heading = resultHeading(r.status, title)
  const isUpdate = r.status === 'updated' || r.status === 'unchanged' || r.status === 'kept' || r.status === 'could-not-update' || r.status === 'needs-confirmation'
  const written = r.status === 'added' || r.status === 'updated' || r.status === 'unchanged' || r.status === 'kept'
  const waiting = isWaitingStatus(r.status)

  return (
    <div className="add-result">
      <div className="add-result__top">
        <h1 className="add-result__title">{heading}</h1>
        {written && (
          <div role="status" className="add-muted add-result__status">
            <CheckIcon />
            Written to OneNote · {formatSeconds(r.timings.totalMs)}
          </div>
        )}
      </div>

      {r.status === 'failed' && (
        <section className="add-card add-card--alert" role="alert">
          <p className="add-label">Not added</p>
          <p className="add-text">{r.message}</p>
          {r.inbox?.status === 'failed' && <p className="add-muted">The item is kept in your Intake with this reason, so nothing is lost.</p>}
          {r.related.length > 0 && (
            <p className="add-text">
              Already there:{' '}
              {r.related.map((p, i) => (
                <span key={p.id}>
                  {i > 0 && ', '}
                  {p.link ? <a className="add-a" href={p.link}>{p.title}</a> : p.title}
                </span>
              ))}
            </p>
          )}
        </section>
      )}

      {isWaitingStatus(r.status) && (
        <WaitingCard status={r.status} message={r.message} busy={busy} onCheck={r.inboxId ? a.onCheckAnswer : undefined} />
      )}

      {r.status === 'ask-instead' && (
        <section className="add-card add-actions">
          <p className="add-text add-actions__text">{r.message}</p>
          {a.onAddAnyway && (
            <button type="button" className="btn" onClick={a.onAddAnyway} disabled={busy}>
              Add anyway
            </button>
          )}
          {a.onAsk && (
            <button type="button" className="btn btn--primary" onClick={a.onAsk} disabled={busy}>
              Ask it
            </button>
          )}
        </section>
      )}

      {r.text && r.status !== 'ask-instead' && (
        <section className="add-card">
          <p className="add-label">{r.kind === 'link' ? 'The link' : 'What you added'}</p>
          <p className="add-text add-text--pre">{r.text}</p>
          {r.kind === 'link' && r.update?.new && r.status === 'added' && <p className="add-text add-summary">{r.update.new.summary}</p>}
        </section>
      )}

      {r.page && r.status !== 'failed' && (
        <section className="add-card" aria-labelledby="add-placed-heading">
          <h2 id="add-placed-heading" className="add-label">
            {r.page.unfiled ? 'Placed in the central index (Unfiled until it gets a topic)' : 'Placed in the central index'}
          </h2>
          <div className="add-path">
            {placementParts(r.page).map((part, i, all) =>
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
            {r.page.link ? (
              <a className="add-a" href={r.page.link} title="Open in OneNote">
                {formatOneNotePath(r.page)}
              </a>
            ) : (
              formatOneNotePath(r.page)
            )}
            {r.page.alsoUnder.length > 0 && <> · also under {r.page.alsoUnder.map(formatTopicPath).join(', ')}</>}
          </div>
          {r.chips.length > 0 && (
            <ul className="add-chips" aria-label="Type, aliases and topics">
              {r.chips.map((c, i) => (
                <li key={`${c.kind}:${c.label}:${i}`} className={c.kind === 'new-topic' ? 'add-chip add-chip--new' : 'add-chip'}>
                  {chipLabel(c)}
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      {isUpdate && r.update && <LinkUpdateView update={r.update} status={r.status} />}
      {r.status === 'could-not-update' && (
        <section className="add-card" role="status">
          <p className="add-text">{r.message}</p>
        </section>
      )}

      {(r.status === 'added' || (r.status === 'updated' && r.links.length > 0)) && (
        <LinksCard links={r.links} backlinks={r.backlinks} title={r.status === 'updated' ? 'New links' : 'Links'} />
      )}

      {r.warnings.length > 0 && (
        <section className="add-card" aria-label="Notes">
          <ul className="add-warnings">
            {r.warnings.map((w, i) => (
              <li key={i} className="add-muted">
                {w}
              </li>
            ))}
          </ul>
        </section>
      )}

      {r.status !== 'ask-instead' && (
        <section className="add-card add-actions">
          <div className="add-actions__text add-text">
            {r.related.length > 0 && r.status !== 'failed' && (
              <>
                Related pages you already had:{' '}
                {r.related.map((p, i) => (
                  <span key={p.id}>
                    {i > 0 && ', '}
                    {p.link ? <a className="add-a" href={p.link}>{p.title}</a> : p.title}
                  </span>
                ))}
              </>
            )}
          </div>
          {r.status === 'added' && a.onEditLinks && (
            <button type="button" className="btn" onClick={a.onEditLinks} disabled={busy}>
              Edit links
            </button>
          )}
          {r.status === 'added' && a.onMoveInIndex && (
            <button type="button" className="btn" onClick={a.onMoveInIndex} disabled={busy}>
              Move in index
            </button>
          )}
          {r.kind === 'link' && r.page && r.status !== 'needs-confirmation' && a.onUpdateLink && (
            <button type="button" className="btn" onClick={a.onUpdateLink} disabled={busy}>
              Update
            </button>
          )}
          {r.status === 'added' && r.undo && a.onUndo && (
            <button type="button" className="btn" onClick={a.onUndo} disabled={busy}>
              Undo
            </button>
          )}
          {/* design: while the item waits, "Check for the answer" is the view's one primary button. */}
          <button type="button" className={waiting && r.inboxId && a.onCheckAnswer ? 'btn' : 'btn btn--primary'} onClick={a.onDone} disabled={busy}>
            Done
          </button>
        </section>
      )}

      {r.status === 'needs-confirmation' && r.confirm && a.onDecide && (
        <ConfirmReplaceDialog request={r.confirm} open busy={busy} onDecide={a.onDecide} onCancel={a.onCancelDecision ?? a.onDone} />
      )}
    </div>
  )
}
