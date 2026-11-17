import { useState } from 'react'
import { AddResult } from '../add/AddResult'
import { AskView } from '../ask/AskStates'
import type { NotebookState } from '../hooks/useServerData'
import type { useHomeFlow } from '../hooks/useHomeFlow'
import type { AddTarget } from '../model/notebooks'
import { AskOptions, type AskChoices } from './AskOptions'
import type { SendBlock } from '../model/attention'
import { Composer } from './Composer'
import { Notice } from './Notice'
import { RecentList } from './RecentList'
import { WhatsNew } from './WhatsNew'
import { WaitingList } from '../activity/WaitingList'
import './HomeView.css'

type Home = ReturnType<typeof useHomeFlow>

/** Add or ask: the box, Ask's options, then the result of the last send (Add result, Ask answer or
 *  a notice), or what waits for Copilot and the recently changed pages while nothing was sent. */
export function HomeView({ home, addTarget, notebook, choices, onChoices, sourceOptions, activityKey, onOpenRecent, onOpenActive, block, onRetryCopilot }: {
  home: Home
  addTarget: AddTarget | null
  notebook: NotebookState
  choices: AskChoices
  onChoices: (c: AskChoices) => void
  sourceOptions: { id: string; label: string }[]
  /** Changes when the waiting list should be read again (a vault switch, a send finished). */
  activityKey: string
  /** Opens a page of the shown notebook / of the active vault in the page window. */
  onOpenRecent: (pageId: string) => void
  onOpenActive: (pageId: string) => void
  /** Why a send cannot work right now (Copilot off, ObsidiNote gone), shown in the box itself. */
  block?: SendBlock | null
  /** Tries to connect Copilot again; '' when it worked, else what the person should know. */
  onRetryCopilot?: () => Promise<string>
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
  const connect = onRetryCopilot ? <ConnectCopilot onRetry={onRetryCopilot} /> : null
  return (
    <div className="page">
      <h1 className="page__title">Add something, or ask your wiki</h1>
      <WhatsNew />
      <Composer addTarget={addTarget} onSend={home.send} busy={home.busy} prefill={home.prefill} note={note} clearKey={home.clearKey} block={block} connect={block?.retry ? connect : null}>
        <AskOptions choices={choices} options={sourceOptions} onChange={onChoices} />
      </Composer>
      <FlowArea home={home} connect={connect} onOpenPage={onOpenActive} />
      {/* design (round 2, 2026-11-15): after a send the result stands alone; what still waits for
          Copilot and what changed lately show while nothing was sent (and in History). */}
      {flow.kind === 'idle' && <WaitingList refreshKey={activityKey} onOpen={onOpenActive} />}
      {flow.kind === 'idle' && <RecentList notebook={notebook} onOpen={onOpenRecent} />}
    </div>
  )
}

/** "Connect Copilot again": one try (POST /api/copilot/reconnect), then what came of it. */
function ConnectCopilot({ onRetry }: { onRetry: () => Promise<string> }) {
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState('')
  const run = async () => {
    setBusy(true)
    setMsg('')
    try {
      setMsg((await onRetry()) || 'Copilot is connected. Send it again.')
    } finally {
      setBusy(false)
    }
  }
  return (
    <>
      <button type="button" className="btn btn--sm" disabled={busy} aria-busy={busy} onClick={() => void run()}>
        {busy ? 'Connecting…' : 'Connect Copilot again'}
      </button>
      {msg && <span role="status">{msg}</span>}
    </>
  )
}

function FlowArea({ home, connect, onOpenPage }: { home: Home; connect: React.JSX.Element | null; onOpenPage: (pageId: string) => void }) {
  const { flow } = home
  if (flow.kind === 'idle') return null
  if (flow.kind === 'notice') {
    return (
      <Notice error={flow.error} actions={flow.copilot ? connect : undefined}>
        <p>{flow.text}</p>
      </Notice>
    )
  }
  if (flow.kind === 'adding') {
    // design: one honest line with the time waited; the three steps are not reported one by one.
    return (
      <Notice busy title="Adding">
        <p>Copilot reads it and proposes topics and links, then the page is written to OneNote. If Copilot is slow, the item waits here and in History; nothing is lost.</p>
      </Notice>
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
        onCheckAnswer={r.inboxId ? () => home.add.onCheckAnswer(r) : undefined}
        onDecide={(d) => home.add.onDecide(r, d)}
        onCancelDecision={home.add.onDone}
        onAsk={() => home.add.onAsk(r)}
        onAddAnyway={() => home.add.onAddAnyway(r)}
        onAddDuplicate={r.duplicateOf ? () => home.add.onAddDuplicate(r) : undefined}
        onOpenPage={onOpenPage}
      />
    )
  }
  const view = flow.view
  if (view.kind !== 'result') {
    return <AskView state={view} onRetry={home.retryAsk} connect={connect} onSaveOpenQuestion={() => undefined} onFollowUp={() => undefined} onSavePage={() => undefined} onShowOnMap={() => undefined} />
  }
  const a = home.askActions(view.result)
  return <AskView state={view} {...a} onOpenPage={onOpenPage} />
}
