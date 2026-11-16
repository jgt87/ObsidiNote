import { useCallback, useMemo, useState } from 'react'
import { ActivityView } from './activity/ActivityView'
import { AppDialogs, type AppDialog } from './components/AppDialogs'
import { HomeView } from './components/HomeView'
import { Rail } from './components/Rail'
import { GraphView } from './graph'
import { useAskChoices, useCopilotRetry, useGraphNavigation, useHashView, useVaultAccess } from './hooks/useAppShell'
import { useHomeFlow } from './hooks/useHomeFlow'
import { useNotebook, useNotebooks, useStatus } from './hooks/useServerData'
import { attentionNotes, sendBlock } from './model/attention'
import { ReadOnlyBanner } from './components/ReadOnlyBanner'
import { askAboutText } from './model/handoff'
import { addTargetFor, askSourceChoices } from './model/notebooks'
import { QuickSwitcher } from './search/QuickSwitcher'

export function App() {
  const { view, goto } = useHashView()
  const { status, serverDown, refresh: refreshStatus } = useStatus()
  const retryCopilot = useCopilotRetry(refreshStatus)
  const notebooks = useNotebooks()
  const notebook = useNotebook(notebooks.shownId)
  const addTarget = addTargetFor(notebooks.list, notebooks.activeId, notebooks.shownId)
  const [choices, setChoices] = useAskChoices(notebooks.activeId)
  const [dialog, setDialog] = useState<AppDialog>(null)
  // Saved settings reach the open graph by remounting it (it reads them when it opens).
  const [graphReload, setGraphReload] = useState(0)
  const reloadGraph = useCallback(() => setGraphReload((n) => n + 1), [])
  const [notice, setNotice] = useState('')
  const { vaultWhy, checkResult, checkAgain } = useVaultAccess(status, serverDown, refreshStatus, reloadGraph)
  const nav = useGraphNavigation(notebooks, goto)
  const home = useHomeFlow(choices, nav.showCited)
  const sourceOptions = useMemo(() => askSourceChoices(notebooks.list, notebooks.activeId), [notebooks.list, notebooks.activeId])
  // The waiting list and History read the Intake again after a vault switch or a finished send.
  const activityKey = `${notebooks.activeId ?? ''}|${home.flow.kind}|${home.clearKey}|${home.changes}`

  return (
    <div className="shell">
      <Rail view={view} notebooks={notebooks} notebook={notebook} notes={attentionNotes(status, serverDown)} onNewVault={() => setDialog('new-vault')} onSetUp={() => setDialog('set-up')} onRetryCopilot={retryCopilot} onSettings={notebooks.activeId ? () => setDialog('settings') : undefined} onOpenSection={nav.openSection} />
      <main className="main">
        <AppNotice text={notice} onClose={() => setNotice('')} />
        {vaultWhy && view !== 'graph' && <ReadOnlyBanner text={vaultWhy} onCheck={checkAgain} result={checkResult} />}
        {view === 'home' && (
          <HomeView
            home={home}
            addTarget={addTarget}
            notebook={notebook}
            choices={choices}
            onChoices={setChoices}
            sourceOptions={sourceOptions}
            activityKey={activityKey}
            onOpenRecent={(id) => nav.openPage(nav.shown, id)}
            onOpenActive={(id) => nav.openPage(nav.activeEntry, id)}
            block={sendBlock(status, serverDown)}
            onRetryCopilot={retryCopilot}
          />
        )}
        {view === 'graph' && (
          <GraphView
            key={graphReload}
            load={nav.loadGraph}
            sourceKey={nav.refKey}
            focusIds={nav.graphFocus}
            request={nav.findRequest}
            onRequestDone={nav.requestDone}
            readOnlyNote={vaultWhy}
            checkResult={checkResult}
            onCheckAgain={checkAgain}
            onAdd={() => goto('home')}
            onAsk={(page) => {
              home.askAbout(askAboutText(page.title))
              goto('home')
            }}
          />
        )}
        {view === 'history' && <ActivityView refreshKey={activityKey} onOpen={(id) => nav.openPage(nav.activeEntry, id)} />}
      </main>
      <QuickSwitcher vaultKey={nav.findKey} load={nav.loadFind} onPick={nav.showFound} />
      <AppDialogs
        dialog={dialog}
        onClose={() => setDialog(null)}
        notebooks={notebooks.list}
        shown={nav.shown}
        version={status?.version ?? ''}
        onSettingsSaved={(s) => {
          setChoices((c) => ({ ...c, includeArchived: s.askIncludeArchived }))
          reloadGraph()
        }}
        onTagsChanged={reloadGraph}
        onAdopt={(id, message) => {
          setDialog(null)
          setNotice(message)
          notebooks.adopt(id)
        }}
      />
    </div>
  )
}

/** What the window says once (a vault became the active one), until it is closed; nothing when empty. */
function AppNotice({ text, onClose }: { text: string; onClose: () => void }) {
  if (!text) return null
  return (
    <p className="home-notice app-notice" role="status">
      {text}{' '}
      <button type="button" className="link-btn" onClick={onClose}>
        Close
      </button>
    </p>
  )
}
