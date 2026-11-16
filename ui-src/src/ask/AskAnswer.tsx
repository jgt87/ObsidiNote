import { Fragment, useState, type Dispatch, type ReactNode, type SetStateAction } from 'react'
import { splitLinks, webUrl } from '../model/links'
import { answerShares, citeChipView, citeTarget, combinedLine, confidenceLabel, droppedCitationsNote, pathChips, sentencesPerSource, sharePercent, sourceAnchor, sourceOrigin } from './askModel'
import type { AskResult, AskSentence, AskSource, AskStaleLink } from './types'
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
  // What the answer was made from (operator, 2026-11-14): pages and topics, sentences per page,
  // and the pages read but not used.
  const paragraphs = result.answer?.paragraphs ?? []
  const used = sentencesPerSource(paragraphs)
  const shares = answerShares(paragraphs)
  // The source the pointer (or keyboard focus) is on: its sentences in the answer turn to the accent
  // (operator, 2026-11-14). Session state of this card only.
  const [lit, setLit] = useState<number | null>(null)
  const cite = (n: number) => <CiteChip key={n} n={n} source={byNumber.get(n)} anchor={anchor(n)} onOpenPage={actions.onOpenPage} />
  return (
    <div className="ask">
      <div>
        <div className="ask-muted">{result.path?.followUp ? 'You asked a follow-up' : 'You asked'}</div>
        <h2 className="ask-question">{result.question}</h2>
      </div>

      <AnswerCard result={result} lit={lit} cite={cite} />

      {/* The actions follow the answer directly; the sources and the path explain it below. */}
      <AskActions {...actions} />

      <section className="card" aria-label="Sources">
        <p className="ask-label">Sources</p>
        <ol className="ask-sources">
          {result.sources.map((s) => (
            <SourceRow key={s.n} source={s} id={anchor(s.n)} share={shares.get(s.n)} sentences={used.get(s.n) ?? 0} stale={stale.get(s.id)} setLit={setLit} onShowPage={actions.onShowPage} onUpdateLink={actions.onUpdateLink} />
          ))}
        </ol>
      </section>

      <UnusedSources sources={result.unused} onShowPage={actions.onShowPage} />

      <AskPathCard result={result} />
    </div>
  )
}

/** The answer: what it was made from, its paragraphs with their citations, how sure it is and
 *  which citations were left out. Without an answer only the confidence line stays. */
function AnswerCard({ result, lit, cite }: { result: AskResult; lit: number | null; cite: (n: number) => ReactNode }) {
  const combined = combinedLine(result.sources)
  return (
    <section className="card" aria-label="Answer">
      <p className="ask-label">Answer</p>
      {combined && <p className="ask-muted ask-combined">{combined}</p>}
      {result.answer?.paragraphs.map((p, i) => (
        <p key={i} className="ask-paragraph">
          {p.sentences.map((s, j) => (
            <Fragment key={j}>
              {j > 0 ? ' ' : null}
              <AnswerSentence sentence={s} lit={lit} />
              {s.cites.map(cite)}
            </Fragment>
          ))}
        </p>
      ))}
      <p className="ask-muted ask-answer__meta">
        {confidenceLabel(result.answer?.confidence)}
        {droppedCitationsNote(result.invalidCitations.length)}
      </p>
    </section>
  )
}

/** One sentence of the answer; lit while the pointer or focus is on a source it cites. */
function AnswerSentence({ sentence: s, lit }: { sentence: AskSentence; lit: number | null }) {
  return (
    <>
      <span
        className={s.unsupported ? 'ask-unsupported' : undefined}
        data-lit={lit !== null && s.cites.includes(lit) ? '' : undefined}
        title={s.unsupported ? 'No source was read for this sentence' : undefined}
      >
        <LinkedText text={s.text} />
      </span>
      {s.unsupported && <span className="visually-hidden"> (no source)</span>}
    </>
  )
}

/**
 * A citation [n]. design (operator, 2026-11-15: "a reference like [1] being clicked should open that
 * topic card or direct link, whichever is most relevant"): a link page opens its own address, a page
 * of the active vault its page window, a page of another notebook OneNote; else it jumps to the
 * source in the list.
 */
function CiteChip({ n, source: src, anchor, onOpenPage }: { n: number; source: AskSource | undefined; anchor: string; onOpenPage?: (pageId: string) => void }) {
  const v = citeChipView(n, src?.title, citeTarget(src, Boolean(onOpenPage)), anchor)
  if (v.tag === 'button')
    return (
      <button type="button" className="ask-cite" title={v.title} aria-label={v.label} onClick={() => src && onOpenPage?.(src.id)}>
        {n}
      </button>
    )
  return (
    <a className="ask-cite" href={v.href} target={v.newTab ? '_blank' : undefined} rel={v.newTab ? 'noopener noreferrer' : undefined} title={v.title} aria-label={v.label}>
      {n}
    </a>
  )
}

interface SourceRowProps {
  source: AskSource
  /** The row's anchor id, the target of a citation that has nowhere else to go. */
  id: string
  /** Its share of the answer (answerShares), when it has one. */
  share: number | undefined
  sentences: number
  stale: AskStaleLink | undefined
  setLit: Dispatch<SetStateAction<number | null>>
  onShowPage?: (pageId: string) => void
  onUpdateLink?: (pageId: string) => void
}

/** One source in the list: number, title, where it is, its share of the answer, an old summary's
 *  Update, its age and OneNote link. Pointing at it (or focusing it) lights its sentences. */
function SourceRow({ source: s, id, share, sentences, stale: st, setLit, onShowPage, onUpdateLink }: SourceRowProps) {
  const origin = sourceOrigin(s)
  const unlight = () => setLit((v) => (v === s.n ? null : v))
  return (
    <li
      id={id}
      className="ask-src"
      tabIndex={-1}
      onMouseEnter={() => setLit(s.n)}
      onMouseLeave={unlight}
      onFocus={() => setLit(s.n)}
      onBlur={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget as Node | null)) unlight()
      }}
    >
      <span className="ask-muted">{s.n}</span>
      <div className="ask-src__main">
        <SourceTitle source={s} onShowPage={onShowPage} />
        <div className="ask-muted">
          {s.path}
          {origin && ` · ${origin}`}
          {s.archived && ' · archived'}
        </div>
        {/* How much of the answer came from this page: one bar in the accent, the percent in text
            beside it; the sentence count stays in words. */}
        {share ? <ShareBar share={share} sentences={sentences} /> : null}
        {st && (
          <div className="ask-stale">
            <span className="ask-muted">{st.label}</span>
            {onUpdateLink && (
              <button type="button" className="btn btn--sm" onClick={() => onUpdateLink(s.id)}>
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
}

/** Pages Ask read that the answer does not cite: shows nothing relevant was skipped unseen. */
function UnusedSources({ sources, onShowPage }: { sources: AskSource[]; onShowPage?: (pageId: string) => void }) {
  if (!sources.length) return null
  return (
    <details className="card ask-unused">
      <summary className="ask-label ask-unused__summary">Also read, not used ({sources.length})</summary>
      <ul className="ask-unused__list">
        {sources.map((s) => (
          <li key={s.key} className="ask-unused__row">
            <SourceTitle source={s} onShowPage={onShowPage} />
            <span className="ask-muted"> · {s.path}</span>
          </li>
        ))}
      </ul>
    </details>
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
