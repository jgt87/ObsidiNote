import { useCallback, useEffect, useMemo, useState } from 'react'
import { getSettings, reconnectCopilot } from './api'
import type { AskChoices } from './components/AskOptions'
import { ActivityView } from './activity/ActivityView'
import { HomeView } from './components/HomeView'
import { NewVaultDialog } from './components/NewVaultDialog'
import { SetUpVaultDialog } from './components/SetUpVaultDialog'
import { SettingsDialog } from './components/SettingsDialog'
import { Rail } from './components/Rail'
import { fetchGraph, GraphView } from './graph'
import { useHomeFlow } from './hooks/useHomeFlow'
import { useNotebook, useNotebooks, useStatus } from './hooks/useServerData'
import { attentionNotes, sendBlock } from './model/attention'
import { askAboutText } from './model/handoff'
import { addTargetFor, askSourceChoices, graphRefFor } from './model/notebooks'
import { viewFromHash, VIEWS, type View } from './model/views'
import { QuickSwitcher } from './search/QuickSwitcher'
import type { FindRequest } from './search/switcherModel'

export function App() {
  const [view, setView] = useState<View>(() => viewFromHash(window.location.hash))
  const { status, serverDown, refresh: refreshStatus } = useStatus()
  const retryCopilot = useCallback(async () => {
    try {
      const r = await reconnectCopilot()
      return r.state === 'connected' ? '' : r.message
    } catch (e) {
      return e instanceof Error ? e.message : 'Copilot could not be reached.'
    } finally {
      await refreshStatus()
    }
  }, [refreshStatus])
  const notebooks = useNotebooks()
  const notebook = useNotebook(notebooks.shownId)
  const addTarget = addTargetFor(notebooks.list, notebooks.activeId, notebooks.shownId)
  const [choices, setChoices] = useState<AskChoices>({ sources: [], includeArchived: false })
  const [graphFocus, setGraphFocus] = useState<string[]>([])
  const [newVaultOpen, setNewVaultOpen] = useState(false)
  const [setUpOpen, setSetUpOpen] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
  // Saved settings reach the open graph by remounting it (it reads them when it opens).
  const [graphReload, setGraphReload] = useState(0)
  // Ask's "Include archived pages" starts from the vault's setting (kept in OneNote), per vault.
  useEffect(() => {
    let live = true
    getSettings()
      .then((r) => live && setChoices((c) => ({ ...c, includeArchived: r.settings.askIncludeArchived })))
      .catch(() => {})
    return () => {
      live = false
    }
  }, [notebooks.activeId])
  const [notice, setNotice] = useState('')

  const goto = (v: View) => { window.location.hash = VIEWS[v].hash }
  const home = useHomeFlow(choices, (ids) => {
    // "Show on map": the active vault's graph, its cited pages highlighted.
    if (notebooks.activeId) notebooks.choose(notebooks.activeId)
    setGraphFocus(ids)
    goto('graph')
  })

  useEffect(() => {
    const onHash = () => setView(viewFromHash(window.location.hash))
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  useEffect(() => {
    document.title = view === 'home' ? 'ObsidiNote' : `${VIEWS[view].label} - ObsidiNote`
  }, [view])

  const shown = notebooks.list.find((n) => n.id === notebooks.shownId)
  const ref = graphRefFor(shown)
  const refKey = JSON.stringify(ref)
  const loadGraph = useCallback((signal: AbortSignal) => fetchGraph(JSON.parse(refKey), signal), [refKey])
  // Quick switcher (Ctrl+K): searches the ACTIVE vault; a pick shows that vault's graph.
  const [findRequest, setFindRequest] = useState<FindRequest | null>(null)
  const activeEntry = notebooks.list.find((n) => n.id === notebooks.activeId)
  const findKey = activeEntry?.vault ? JSON.stringify(graphRefFor(activeEntry)) : null
  const loadFind = useCallback((signal: AbortSignal) => fetchGraph(findKey ? JSON.parse(findKey) : {}, signal), [findKey])
  const sourceOptions = useMemo(() => askSourceChoices(notebooks.list, notebooks.activeId), [notebooks.list, notebooks.activeId])
  // A page opened from the home page or History: the knowledge graph of its notebook with the page
  // window open (the same FindRequest the Ctrl+K switcher uses; operator, 2026-11-14).
  const openPage = (entry: typeof shown, pageId: string) => {
    if (!entry) return
    if (entry.id !== notebooks.shownId) notebooks.choose(entry.id)
    setGraphFocus([])
    setFindRequest({ sourceId: entry.vault && entry.vaultId ? entry.vaultId : entry.id, pageId })
    goto('graph')
  }
  // A section picked in the side bar: the shown notebook's List, searched on that section.
  const openSection = (query: string) => {
    if (!shown) return
    setGraphFocus([])
    setFindRequest({ sourceId: shown.vault && shown.vaultId ? shown.vaultId : shown.id, query, list: true })
    goto('graph')
  }
  // The waiting list and History read the Intake again after a vault switch or a finished send.
  const activityKey = `${notebooks.activeId ?? ''}|${home.flow.kind}|${home.clearKey}|${home.changes}`

  return (
    <div className="shell">
      <Rail view={view} notebooks={notebooks} notebook={notebook} notes={attentionNotes(status, serverDown)} onNewVault={() => setNewVaultOpen(true)} onSetUp={() => setSetUpOpen(true)} onRetryCopilot={retryCopilot} onSettings={notebooks.activeId ? () => setSettingsOpen(true) : undefined} onOpenSection={openSection} />
      <main className="main">
        {notice && (
          <p className="home-notice app-notice" role="status">
            {notice}{' '}
            <button type="button" className="link-btn" onClick={() => setNotice('')}>
              Close
            </button>
          </p>
        )}
        {view === 'home' && (
          <HomeView
            home={home}
            addTarget={addTarget}
            notebook={notebook}
            choices={choices}
            onChoices={setChoices}
            sourceOptions={sourceOptions}
            activityKey={activityKey}
            onOpenRecent={(id) => openPage(shown, id)}
            onOpenActive={(id) => openPage(activeEntry, id)}
            block={sendBlock(status, serverDown)}
            onRetryCopilot={retryCopilot}
          />
        )}
        {view === 'graph' && (
          <GraphView
            key={graphReload}
            load={loadGraph}
            sourceKey={refKey}
            focusIds={graphFocus}
            request={findRequest}
            onRequestDone={() => setFindRequest(null)}
            onAdd={() => goto('home')}
            onAsk={(page) => {
              home.askAbout(askAboutText(page.title))
              goto('home')
            }}
          />
        )}
        {view === 'history' && <ActivityView refreshKey={activityKey} onOpen={(id) => openPage(activeEntry, id)} />}
      </main>
      <QuickSwitcher
        vaultKey={findKey}
        load={loadFind}
        onPick={(r) => {
          if (notebooks.activeId) notebooks.choose(notebooks.activeId)
          setGraphFocus([])
          setFindRequest(r)
          goto('graph')
        }}
      />
      {settingsOpen && (
        <SettingsDialog
          onClose={() => setSettingsOpen(false)}
          onSaved={(s) => {
            setChoices((c) => ({ ...c, includeArchived: s.askIncludeArchived }))
            setGraphReload((n) => n + 1)
          }}
          onTagsChanged={() => setGraphReload((n) => n + 1)}
        />
      )}
      {newVaultOpen && (
        <NewVaultDialog
          notebooks={notebooks.list}
          onClose={() => setNewVaultOpen(false)}
          onMade={(r) => {
            setNewVaultOpen(false)
            setNotice(`${r.name} is your active vault now.${r.warning ? ` ${r.warning}` : ''}`)
            notebooks.adopt(r.id)
          }}
        />
      )}
      {setUpOpen && shown && (
        <SetUpVaultDialog
          id={shown.id}
          name={shown.name}
          onClose={() => setSetUpOpen(false)}
          onDone={(r) => {
            setSetUpOpen(false)
            setNotice(`${r.name} is your active vault now.`)
            notebooks.adopt(r.id)
          }}
        />
      )}
    </div>
  )
}
