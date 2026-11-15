import { Fragment, useState } from 'react'
import { splitLinks, webUrl } from '../model/links'
import { answerShares, citeTarget, combinedLine, confidenceLabel, pathChips, sentencesPerSource, sharePercent, sourceAnchor, sourceOrigin } from './askModel'
import type { AskResult, AskSource } from './types'
import './Ask.css'

export interface AskAnswerActions {
  onFollowUp: () => void
  onSavePage: () => void
  onShowOnMap: () => void
  /** One source page of the active vault on the map (pages that are not links). */
  onShowPage?: (pageId: string) => void
  /** Opens a source page of the active vault in its page window (a citation [n] pressed). */
  onOpenPage?: (pageId: string) => void
  /** Offered for a cited link summary older than 90 days (Update belongs to the Add flow). */
  onUpdateLink?: (pageId: string) => void
}

/** "How it was found": Index > branch + branch > N pages read, and the counts. Folded: it explains
 *  the answer, it is not the answer (review 2026-11-14: it stood above the answer, at more weight). */
export function AskPathCard({ result }: { result: AskResult }) {
  const chips = pathChips(result.path)
  if (!chips.length) return null
  return (
    <details className="card ask-unused ask-path">
      <summary className="ask-label ask-unused__summary">
        How it was found{result.path?.summary ? `: ${result.path.summary}` : ''}
      </summary>
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
    </details>
  )
}

/** An answer from the wiki: the path it took, the answer with citation chips, the sources. */
export function AskAnswer({ result, ...actions }: { result: AskResult } & AskAnswerActions) {
  const anchor = (n: number) => sourceAnchor(result.conversationId, result.turn, n)
  const byNumber = new Map(result.sources.map((s) => [s.n, s]))
  const stale = new Map(result.staleLinks.map((l) => [l.id, l]))
  const dropped = result.invalidCitations.length
  // What the answer was made from (operator, 2026-11-14): pages and topics, sentences per page,
  // and the pages read but not used.
  const combined = combinedLine(result.sources)
  const used = sentencesPerSource(result.answer?.paragraphs ?? [])
  const shares = answerShares(result.answer?.paragraphs ?? [])
  // The source the pointer (or keyboard focus) is on: its sentences in the answer turn to the accent
  // (operator, 2026-11-14). Session state of this card only.
  const [lit, setLit] = useState<number | null>(null)
  return (
    <div className="ask">
      <div>
        <div className="ask-muted">{result.path?.followUp ? 'You asked a follow-up' : 'You asked'}</div>
        <h2 className="ask-question">{result.question}</h2>
      </div>

      <section className="card" aria-label="Answer">
        <p className="ask-label">Answer</p>
        {combined && <p className="ask-muted ask-combined">{combined}</p>}
        {result.answer?.paragraphs.map((p, i) => (
          <p key={i} className="ask-paragraph">
            {p.sentences.map((s, j) => (
              <Fragment key={j}>
                {j > 0 ? ' ' : null}
                <span
                  className={s.unsupported ? 'ask-unsupported' : undefined}
                  data-lit={lit !== null && s.cites.includes(lit) ? '' : undefined}
                  title={s.unsupported ? 'No source was read for this sentence' : undefined}
                >
                  <LinkedText text={s.text} />
                </span>
                {s.unsupported && <span className="visually-hidden"> (no source)</span>}
                {s.cites.map((n) => {
                  const src = byNumber.get(n)
                  const go = citeTarget(src, Boolean(actions.onOpenPage))
                  const name = `Source ${n}: ${src?.title ?? ''}`
                  // design (operator, 2026-11-15: "a reference like [1] being clicked should open that topic
                  // card or direct link, whichever is most relevant"): a link page opens its own address,
                  // a page of the active vault its page window, a page of another notebook OneNote.
                  if (go.kind === 'url' || go.kind === 'onenote')
                    return (
                      <a key={n} className="ask-cite" href={go.href} target={go.kind === 'url' ? '_blank' : undefined} rel={go.kind === 'url' ? 'noopener noreferrer' : undefined} title={go.kind === 'url' ? go.href : 'Open in OneNote'} aria-label={`${name}, ${go.kind === 'url' ? 'opens the link' : 'opens in OneNote'}`}>
                        {n}
                      </a>
                    )
                  if (go.kind === 'page' && src)
                    return (
                      <button key={n} type="button" className="ask-cite" title={`Open ${src.title}`} aria-label={`${name}, opens the page`} onClick={() => actions.onOpenPage?.(src.id)}>
                        {n}
                      </button>
                    )
                  return (
                    <a key={n} className="ask-cite" href={`#${anchor(n)}`} aria-label={name}>
                      {n}
                    </a>
                  )
                })}
              </Fragment>
            ))}
          </p>
        ))}
        <p className="ask-muted ask-answer__meta">
          {confidenceLabel(result.answer?.confidence)}
          {dropped > 0 && ` ${dropped === 1 ? 'One citation pointed' : `${dropped} citations pointed`} to a page that was not read and ${dropped === 1 ? 'was' : 'were'} left out.`}
        </p>
      </section>

      {/* The actions follow the answer directly; the sources and the path explain it below. */}
      <AskActions {...actions} />

      <section className="card" aria-label="Sources">
        <p className="ask-label">Sources</p>
        <ol className="ask-sources">
          {result.sources.map((s) => {
            const st = stale.get(s.id)
            const origin = sourceOrigin(s)
            return (
              <li
                key={s.n}
                id={anchor(s.n)}
                className="ask-src"
                tabIndex={-1}
                onMouseEnter={() => setLit(s.n)}
                onMouseLeave={() => setLit((v) => (v === s.n ? null : v))}
                onFocus={() => setLit(s.n)}
                onBlur={(e) => {
                  if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setLit((v) => (v === s.n ? null : v))
                }}
              >
                <span className="ask-muted">{s.n}</span>
                <div className="ask-src__main">
                  <SourceTitle source={s} onShowPage={actions.onShowPage} />
                  <div className="ask-muted">
                    {s.path}
                    {origin && ` · ${origin}`}
                    {s.archived && ' · archived'}
                  </div>
                  {shares.get(s.n) ? (
                    // How much of the answer came from this page (answerShares): one bar in the accent,
                    // the percent in text beside it; the sentence count stays in words.
                    <ShareBar share={shares.get(s.n)!} sentences={used.get(s.n) ?? 0} />
                  ) : null}
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
                <span className="ask-muted ask-src__age">
                  {s.age}
                  {s.link && (
                    <>
                      {s.age ? ' · ' : ''}
                      <a className="ask-src__onenote" href={s.link} aria-label={`Open "${s.title}" in OneNote`}>
                        OneNote
                      </a>
                    </>
                  )}
                </span>
              </li>
            )
          })}
        </ol>
      </section>

      {result.unused.length > 0 && (
        // Pages Ask read that the answer does not cite: shows nothing relevant was skipped unseen.
        <details className="card ask-unused">
          <summary className="ask-label ask-unused__summary">
            Also read, not used ({result.unused.length})
          </summary>
          <ul className="ask-unused__list">
            {result.unused.map((s) => (
              <li key={s.key} className="ask-unused__row">
                <SourceTitle source={s} onShowPage={actions.onShowPage} />
                <span className="ask-muted"> · {s.path}</span>
              </li>
            ))}
          </ul>
        </details>
      )}

      <AskPathCard result={result} />
    </div>
  )
}

/** A source's share of the answer: a thin bar (track + accent fill with a rounded end) and its
 *  percent and sentence count in text, so the number never depends on reading the bar. */
function ShareBar({ share, sentences }: { share: number; sentences: number }) {
  const pct = sharePercent(share)
  const words = `${pct}% of the answer, ${sentences} ${sentences === 1 ? 'sentence' : 'sentences'}`
  return (
    <div className="ask-share" title={`${(share * 100).toFixed(1)}% of the cited answer text came from this page`}>
      <span className="ask-share__track" role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct} aria-label="Share of the answer">
        <span className="ask-share__fill" style={{ width: `${Math.max(2, pct)}%` }} />
      </span>
      <span className="ask-muted ask-share__label">{words}</span>
    </div>
  )
}

/** Answer text with its web addresses as links (new tab; only http(s)). */
function LinkedText({ text }: { text: string }) {
  return (
    <>
      {splitLinks(text).map((p, i) =>
        p.href ? (
          <a key={i} className="ask-weblink" href={p.href} target="_blank" rel="noopener noreferrer">
            {p.text}
          </a>
        ) : (
          <Fragment key={i}>{p.text}</Fragment>
        ),
      )}
    </>
  )
}

/** A source's title: a link page opens its original address; a page of the active vault shows on
 *  the map; only a read-only page without an address falls back to OneNote. */
function SourceTitle({ source: s, onShowPage }: { source: AskSource; onShowPage?: (id: string) => void }) {
  const url = webUrl(s.url)
  if (url)
    return (
      <a href={url} target="_blank" rel="noopener noreferrer" title={url}>
        {s.title}
      </a>
    )
  if (onShowPage && !s.readOnly)
    return (
      <button type="button" className="ask-src__page" onClick={() => onShowPage(s.id)} title="Show this page on the map">
        {s.title}
      </button>
    )
  return s.link ? <a href={s.link}>{s.title}</a> : <span>{s.title}</span>
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
