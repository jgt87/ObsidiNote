import { useCallback, useEffect, useMemo, useRef, useState, type RefObject } from 'react'
import { ActivityView } from './activity/ActivityView'
import { AppDialogs, type AppDialog } from './components/AppDialogs'
import { ErrorBoundary } from './components/ErrorBoundary'
import { HomeView } from './components/HomeView'
import { ViewOpening } from './components/Notice'
import { JournalView } from './journal/JournalView'
import { Rail } from './components/Rail'
import { GraphView } from './graph'
import { useAskChoices, useCopilotRetry, useGraphNavigation, useHashView, useVaultAccess } from './hooks/useAppShell'
import { useHomeFlow } from './hooks/useHomeFlow'
import { useNotebook, useNotebooks, useStatus } from './hooks/useServerData'
import { attentionNotes, sendBlock } from './model/attention'
import { ReadOnlyBanner } from './components/ReadOnlyBanner'
import { askAboutText } from './model/handoff'
import { markViewChanged } from './model/viewChange'
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

  const main = useViewFocus(view)

  return (
    <div className="shell">
      <SkipLink target={main} />
      <ErrorBoundary region="the side bar">
        <Rail view={view} notebooks={notebooks} notebook={notebook} notes={attentionNotes(status, serverDown)} onNewVault={() => setDialog('new-vault')} onSetUp={() => setDialog('set-up')} onRetryCopilot={retryCopilot} onSettings={notebooks.activeId ? () => setDialog('settings') : undefined} onOpenSection={nav.openSection} />
      </ErrorBoundary>
      <main id="main" className="main" ref={main} tabIndex={-1}>
        <AppNotice text={notice} onClose={() => setNotice('')} />
        {vaultWhy && view !== 'graph' && <ReadOnlyBanner text={vaultWhy} onCheck={checkAgain} result={checkResult} />}
        <ErrorBoundary region="this view" resetKey={view}>
        <ViewOpening key={view}>
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
            onAsk={(page, within) => {
              if (within) home.askWithin(within)
              else home.askAbout(askAboutText(page.title))
              goto('home')
            }}
          />
        )}
        {view === 'journal' && (
          <JournalView
            vaultKey={nav.findKey}
            load={nav.loadFind}
            onOpen={(id) => nav.openPage(nav.activeEntry, id)}
            onAsk={(question) => {
              home.askAbout(question)
              goto('home')
            }}
            onAskSeries={(s) => {
              home.askWithin({ series: s.name, count: s.count })
              goto('home')
            }}
          />
        )}
        {view === 'history' && <ActivityView refreshKey={activityKey} onOpen={(id) => nav.openPage(nav.activeEntry, id)} />}
        </ViewOpening>
        </ErrorBoundary>
      </main>
      <ErrorBoundary region="the quick switcher">
        <QuickSwitcher vaultKey={nav.findKey} load={nav.loadFind} onPick={nav.showFound} />
      </ErrorBoundary>
      <ErrorBoundary region="the dialog">
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
      </ErrorBoundary>
    </div>
  )
}

/** What the window says once (a vault became the active one), until it is closed. The region is
 *  always there (empty it takes no room), so a message put in it is announced. */
function AppNotice({ text, onClose }: { text: string; onClose: () => void }) {
  return (
    <div className="live" role="status">
      {text && (
        <p className="home-notice app-notice">
          {text}{' '}
          <button type="button" className="link-btn" onClick={onClose}>
            Close
          </button>
        </p>
      )}
    </div>
  )
}

/** The first thing Tab reaches: "Skip to content", shown only while it has the focus. The views
 *  live in the address's hash (#/graph), so it moves the focus itself instead of following #main. */
function SkipLink({ target }: { target: RefObject<HTMLElement | null> }) {
  return (
    <a
      className="skip-link"
      href="#main"
      onClick={(e) => {
        e.preventDefault()
        target.current?.focus({ preventScroll: true })
      }}
    >
      Skip to content
    </a>
  )
}

/** On a change of view the focus moves to the new view's main area (screen readers then start
 *  there), unless the view already put it somewhere in it (the box after "Ask about this"). The
 *  first view keeps its own focus (the box). Audit 2026-11-24: the focus stayed on the side bar link. */
function useViewFocus(view: string): RefObject<HTMLElement | null> {
  const main = useRef<HTMLElement>(null)
  const shown = useRef(view) // the view the focus was last placed for (StrictMode runs effects twice)
  // Marked while rendering, so the new view's own mount effects (the box) already know.
  if (shown.current !== view) markViewChanged()
  useEffect(() => {
    if (shown.current === view) return
    shown.current = view
    const el = main.current
    if (el && !el.contains(document.activeElement)) el.focus({ preventScroll: true })
  }, [view])
  return main
}
