import type { ReactNode } from 'react'
import { Notice } from '../components/Notice'
import { AskAnswer, AskPathCard, type AskAnswerActions } from './AskAnswer'
import { notFoundText } from './askModel'
import type { AskProgressStep, AskResult } from './types'
import './Ask.css'

/** While Copilot works. design (review 2026-11-14): one line with the time waited, not a stepper:
 *  the answer comes back in one call, so the interface cannot know which of the three steps runs
 *  and a stepper stood on step 1 for the whole wait. `step` 3 = a follow-up (the pages are known). */
export function AskProgress({ question, step }: { question: string; step: AskProgressStep }) {
  return (
    <div className="ask" aria-busy="true">
      <div>
        <div className="ask-muted">You asked</div>
        <h2 className="ask-question">{question}</h2>
      </div>
      <Notice busy title={step === 3 ? 'Writing the answer from the same pages' : 'Reading your wiki'}>
        <p className="ask-muted">
          {step === 3 ? 'Copilot answers from the pages of the last answer.' : 'Copilot picks the topics, then the pages, then writes the answer.'} Asking never changes your notebook.
        </p>
      </Notice>
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
      <section className="card" aria-label="Nothing found">
        <p className="ask-label">Nothing found</p>
        <p className="ask-paragraph">{nf?.message ?? 'Nothing in your wiki answers this yet.'}</p>
        <p className="ask-muted">{notFoundText(nf?.reason)}</p>
      </section>
      <div className="ask-actions">
        <button type="button" className="btn" onClick={onSaveOpenQuestion}>
          {nf?.suggestion.label ?? 'Save as an Open question'}
        </button>
        {nf?.askNew && onAskAsNew && (
          <button type="button" className="btn" onClick={onAskAsNew}>
            Ask it as a new question
          </button>
        )}
        <span className="ask-muted ask-actions__note">Asking never changes your notebook.</span>
      </div>
      <AskPathCard result={result} />
    </div>
  )
}

/** The Ask result area: progress, answer, nothing found, or an error, from one state. */
export type AskViewState =
  | { kind: 'progress'; question: string; step: AskProgressStep }
  | { kind: 'result'; result: AskResult }
  | { kind: 'error'; question: string; message: string; copilot?: boolean }

export function AskView({
  state,
  onSaveOpenQuestion,
  onAskAsNew,
  onRetry,
  connect,
  ...actions
}: {
  state: AskViewState
  onSaveOpenQuestion: () => void
  onAskAsNew?: () => void
  /** Asks the same question again after an error. */
  onRetry?: () => void
  /** The "Connect Copilot again" control, offered when Copilot was the reason. */
  connect?: ReactNode
} & AskAnswerActions) {
  if (state.kind === 'progress') return <AskProgress question={state.question} step={state.step} />
  if (state.kind === 'error') {
    return (
      <div className="ask">
        <div>
          <div className="ask-muted">You asked</div>
          <h2 className="ask-question">{state.question}</h2>
        </div>
        <Notice
          error
          title="Not answered"
          actions={
            <>
              {onRetry && (
                <button type="button" className="btn btn--sm" onClick={onRetry}>
                  Try again
                </button>
              )}
              {state.copilot && connect}
            </>
          }
        >
          <p>{state.message}</p>
        </Notice>
      </div>
    )
  }
  if (state.result.status === 'not-found') return <AskNotFoundView result={state.result} onSaveOpenQuestion={onSaveOpenQuestion} onAskAsNew={onAskAsNew} />
  return <AskAnswer result={state.result} {...actions} />
}
