import { Fragment } from 'react'
import { confidenceLabel, pathChips, sourceAnchor, sourceOrigin } from './askModel'
import type { AskResult } from './types'
import './Ask.css'

export interface AskAnswerActions {
  onFollowUp: () => void
  onSavePage: () => void
  onShowOnMap: () => void
  /** Offered for a cited link summary older than 90 days (Update belongs to the Add flow). */
  onUpdateLink?: (pageId: string) => void
}

/** "Path through the central index": Index > branch + branch > N pages read, and the counts. */
export function AskPathCard({ result }: { result: AskResult }) {
  const chips = pathChips(result.path)
  if (!chips.length) return null
  return (
    <section className="card ask-path" aria-label="Path through the index">
      <p className="ask-label">Path through the central index</p>
      <ol className="ask-path__steps">
        {chips.map((c, i) => (
          <li key={i} className="ask-path__item">
            {c.before && (
              <span className="ask-muted" aria-hidden="true">
                {c.before === '+' ? '+' : '›'}
              </span>
            )}
            <span className="ask-step">
              {c.n != null ? <span className="ask-step__n">{c.n}</span> : null}
              {c.label}
              {c.note && <span className="ask-muted"> ({c.note})</span>}
            </span>
          </li>
        ))}
      </ol>
      {result.path?.summary && <p className="ask-muted ask-path__summary">{result.path.summary}</p>}
    </section>
  )
}

/** An answer from the wiki: the path it took, the answer with citation chips, the sources. */
export function AskAnswer({ result, ...actions }: { result: AskResult } & AskAnswerActions) {
  const anchor = (n: number) => sourceAnchor(result.conversationId, result.turn, n)
  const byNumber = new Map(result.sources.map((s) => [s.n, s]))
  const stale = new Map(result.staleLinks.map((l) => [l.id, l]))
  const dropped = result.invalidCitations.length
  return (
    <div className="ask">
      <div>
        <div className="ask-muted">{result.path?.followUp ? 'You asked a follow-up' : 'You asked'}</div>
        <h2 className="ask-question">{result.question}</h2>
      </div>

      <AskPathCard result={result} />

      <section className="card" aria-label="Answer">
        <p className="ask-label">Answer</p>
        {result.answer?.paragraphs.map((p, i) => (
          <p key={i} className="ask-paragraph">
            {p.sentences.map((s, j) => (
              <Fragment key={j}>
                {j > 0 ? ' ' : null}
                <span className={s.unsupported ? 'ask-unsupported' : undefined} title={s.unsupported ? 'No source was read for this sentence' : undefined}>
                  {s.text}
                </span>
                {s.unsupported && <span className="visually-hidden"> (no source)</span>}
                {s.cites.map((n) => (
                  <sup key={n}>
                    <a className="ask-cite" href={`#${anchor(n)}`} aria-label={`Source ${n}: ${byNumber.get(n)?.title ?? ''}`}>
                      {n}
                    </a>
                  </sup>
                ))}
              </Fragment>
            ))}
          </p>
        ))}
        <p className="ask-muted ask-answer__meta">
          {confidenceLabel(result.answer?.confidence)}
          {dropped > 0 && ` ${dropped === 1 ? 'One citation pointed' : `${dropped} citations pointed`} to a page that was not read and ${dropped === 1 ? 'was' : 'were'} left out.`}
        </p>
      </section>

      <section className="card" aria-label="Sources">
        <p className="ask-label">Sources (open in OneNote)</p>
        <ol className="ask-sources">
          {result.sources.map((s) => {
            const st = stale.get(s.id)
            const origin = sourceOrigin(s)
            return (
              <li key={s.n} id={anchor(s.n)} className="ask-src" tabIndex={-1}>
                <span className="ask-muted ask-src__n">{s.n}</span>
                <div className="ask-src__main">
                  {s.link ? (
                    <a href={s.link} title="Open in OneNote">
                      {s.title}
                    </a>
                  ) : (
                    <span>{s.title}</span>
                  )}
                  <div className="ask-muted">
                    {s.path}
                    {origin && ` · ${origin}`}
                    {s.archived && ' · archived'}
                  </div>
                  {st && (
                    <div className="ask-stale">
                      <span className="ask-muted">{st.label}</span>
                      {actions.onUpdateLink && (
                        <button type="button" className="btn btn--sm" onClick={() => actions.onUpdateLink?.(s.id)}>
                          Update
                        </button>
                      )}
                    </div>
                  )}
                </div>
                <span className="ask-muted ask-src__age">{s.age}</span>
              </li>
            )
          })}
        </ol>
      </section>

      <AskActions {...actions} />
    </div>
  )
}

function AskActions({ onFollowUp, onSavePage, onShowOnMap }: AskAnswerActions) {
  return (
    <div className="ask-actions">
      <button type="button" className="btn" onClick={onFollowUp}>
        Ask a follow-up
      </button>
      <button type="button" className="btn" onClick={onSavePage}>
        Save answer as a page
      </button>
      <button type="button" className="btn" onClick={onShowOnMap}>
        Show on map
      </button>
      <span className="ask-muted ask-actions__note">Asking never changes your notebook.</span>
    </div>
  )
}
