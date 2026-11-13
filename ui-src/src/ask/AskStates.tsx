import { AskAnswer, AskPathCard, type AskAnswerActions } from './AskAnswer'
import { notFoundText, PROGRESS_LABELS } from './askModel'
import type { AskProgressStep, AskResult } from './types'
import './Ask.css'

const STEPS: AskProgressStep[] = [1, 2, 3]

/** While the three Copilot steps run. `step` is the one running now. */
export function AskProgress({ question, step }: { question: string; step: AskProgressStep }) {
  return (
    <div className="ask" aria-busy="true">
      <div>
        <div className="ask-muted">You asked</div>
        <h2 className="ask-question">{question}</h2>
      </div>
      <section className="card" aria-label="Progress">
        <p className="ask-label">Looking through your index</p>
        <ol className="ask-progress">
          {STEPS.map((n) => {
            const state = n < step ? 'done' : n === step ? 'now' : 'next'
            return (
              <li key={n} className={`ask-progress__item ask-progress__item--${state}`} aria-current={state === 'now' ? 'step' : undefined}>
                <span className="ask-step__n" aria-hidden="true">
                  {state === 'done' ? '✓' : n}
                </span>
                <span>{PROGRESS_LABELS[n]}</span>
                {state === 'done' && <span className="visually-hidden"> done</span>}
              </li>
            )
          })}
        </ol>
        <p className="ask-muted" role="status" aria-live="polite">
          {PROGRESS_LABELS[step]}
        </p>
      </section>
      <span className="ask-muted">Asking never changes your notebook.</span>
    </div>
  )
}

/** Nothing found: say so plainly and offer to keep the question as an Open question. */
export function AskNotFoundView({
  result,
  onSaveOpenQuestion,
  onAskAsNew,
}: {
  result: AskResult
  onSaveOpenQuestion: () => void
  onAskAsNew?: () => void
}) {
  const nf = result.notFound
  return (
    <div className="ask">
      <div>
        <div className="ask-muted">{result.path?.followUp ? 'You asked a follow-up' : 'You asked'}</div>
        <h2 className="ask-question">{result.question}</h2>
      </div>
      <AskPathCard result={result} />
      <section className="card" aria-label="Nothing found">
        <p className="ask-label">Nothing found</p>
        <p className="ask-paragraph">{nf?.message ?? 'Nothing in your wiki answers this yet.'}</p>
        <p className="ask-muted">{notFoundText(nf?.reason)}</p>
      </section>
      <div className="ask-actions">
        <button type="button" className="btn btn--primary" onClick={onSaveOpenQuestion}>
          {nf?.suggestion.label ?? 'Save as an Open question'}
        </button>
        {nf?.askNew && onAskAsNew && (
          <button type="button" className="btn" onClick={onAskAsNew}>
            Ask it as a new question
          </button>
        )}
        <span className="ask-muted ask-actions__note">Asking never changes your notebook.</span>
      </div>
    </div>
  )
}

/** The Ask result area: progress, answer, nothing found, or an error, from one state. */
export type AskViewState =
  | { kind: 'progress'; question: string; step: AskProgressStep }
  | { kind: 'result'; result: AskResult }
  | { kind: 'error'; question: string; message: string }

export function AskView({
  state,
  onSaveOpenQuestion,
  onAskAsNew,
  ...actions
}: { state: AskViewState; onSaveOpenQuestion: () => void; onAskAsNew?: () => void } & AskAnswerActions) {
  if (state.kind === 'progress') return <AskProgress question={state.question} step={state.step} />
  if (state.kind === 'error') {
    return (
      <div className="ask">
        <h2 className="ask-question">{state.question}</h2>
        <section className="card" role="alert">
          <p className="ask-label">Not answered</p>
          <p className="ask-paragraph">{state.message}</p>
        </section>
      </div>
    )
  }
  if (state.result.status === 'not-found') return <AskNotFoundView result={state.result} onSaveOpenQuestion={onSaveOpenQuestion} onAskAsNew={onAskAsNew} />
  return <AskAnswer result={state.result} {...actions} />
}
