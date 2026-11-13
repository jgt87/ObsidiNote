import { AddResult } from '../add/AddResult'
import { AskView } from '../ask/AskStates'
import type { NotebookState } from '../hooks/useServerData'
import type { useHomeFlow } from '../hooks/useHomeFlow'
import type { AddTarget } from '../model/notebooks'
import { AskOptions, type AskChoices } from './AskOptions'
import { Composer } from './Composer'
import { RecentList } from './RecentList'
import './HomeView.css'

type Home = ReturnType<typeof useHomeFlow>

/** Add or ask: the box, Ask's options, then the result of the last send (Add result, Ask answer or
 *  a notice), or the recently changed pages while nothing was sent. */
export function HomeView({ home, addTarget, notebook, choices, onChoices, sourceOptions }: {
  home: Home
  addTarget: AddTarget | null
  notebook: NotebookState
  choices: AskChoices
  onChoices: (c: AskChoices) => void
  sourceOptions: { id: string; label: string }[]
}) {
  const { flow } = home
  const note = home.followUp ? (
    <p className="home-note" role="status">
      Follow-up to <b>{home.followUp.question}</b>, from the same pages.{' '}
      <button type="button" className="link-btn" onClick={home.cancelFollowUp}>
        Ask a new question instead
      </button>
    </p>
  ) : null
  return (
    <div className="page">
      <h1 className="page__title">Add something, or ask your wiki</h1>
      <Composer addTarget={addTarget} onSend={home.send} busy={home.busy} prefill={home.prefill} note={note} clearKey={home.clearKey}>
        <AskOptions choices={choices} options={sourceOptions} onChange={onChoices} />
      </Composer>
      <FlowArea home={home} />
      {flow.kind === 'idle' && <RecentList notebook={notebook} />}
    </div>
  )
}

function FlowArea({ home }: { home: Home }) {
  const { flow } = home
  if (flow.kind === 'idle') return null
  if (flow.kind === 'notice') {
    return (
      <p className={flow.error ? 'home-notice home-notice--error' : 'home-notice'} role={flow.error ? 'alert' : 'status'}>
        {flow.text}
      </p>
    )
  }
  if (flow.kind === 'adding') {
    return (
      <p className="home-notice" role="status" aria-busy="true">
        Adding: inbox, Copilot, then OneNote. This takes a little while.
      </p>
    )
  }
  if (flow.kind === 'add') {
    const r = flow.result
    return (
      <AddResult
        result={r}
        busy={flow.busy}
        onDone={home.add.onDone}
        onUndo={r.undo ? () => home.add.onUndo(r) : undefined}
        onUpdateLink={r.kind === 'link' ? () => home.add.onUpdateLink(r) : undefined}
        onDecide={(d) => home.add.onDecide(r, d)}
        onCancelDecision={home.add.onDone}
        onAsk={() => home.add.onAsk(r)}
        onAddAnyway={() => home.add.onAddAnyway(r)}
      />
    )
  }
  const view = flow.view
  if (view.kind !== 'result') return <AskView state={view} onSaveOpenQuestion={() => undefined} onFollowUp={() => undefined} onSavePage={() => undefined} onShowOnMap={() => undefined} />
  const a = home.askActions(view.result)
  return <AskView state={view} {...a} />
}
