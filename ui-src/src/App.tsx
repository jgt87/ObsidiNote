import { useCallback, useEffect, useMemo, useState } from 'react'
import type { AskChoices } from './components/AskOptions'
import { EmptyView } from './components/EmptyView'
import { HomeView } from './components/HomeView'
import { HistoryIcon } from './components/icons'
import { NewVaultDialog } from './components/NewVaultDialog'
import { Rail } from './components/Rail'
import { fetchGraph, GraphView } from './graph'
import { useHomeFlow } from './hooks/useHomeFlow'
import { useNotebook, useNotebooks, useStatus } from './hooks/useServerData'
import { attentionNotes } from './model/attention'
import { askAboutText } from './model/handoff'
import { addTargetFor, askSourceChoices, graphRefFor } from './model/notebooks'
import { viewFromHash, VIEWS, type View } from './model/views'

export function App() {
  const [view, setView] = useState<View>(() => viewFromHash(window.location.hash))
  const { status, serverDown } = useStatus()
  const notebooks = useNotebooks()
  const notebook = useNotebook(notebooks.shownId)
  const addTarget = addTargetFor(notebooks.list, notebooks.activeId, notebooks.shownId)
  const [choices, setChoices] = useState<AskChoices>({ sources: [], includeArchived: false })
  const [graphFocus, setGraphFocus] = useState<string[]>([])
  const [newVaultOpen, setNewVaultOpen] = useState(false)
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
  const sourceOptions = useMemo(() => askSourceChoices(notebooks.list, notebooks.activeId), [notebooks.list, notebooks.activeId])

  return (
    <div className="shell">
      <Rail view={view} notebooks={notebooks} notebook={notebook} notes={attentionNotes(status, serverDown)} onNewVault={() => setNewVaultOpen(true)} />
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
          <HomeView home={home} addTarget={addTarget} notebook={notebook} choices={choices} onChoices={setChoices} sourceOptions={sourceOptions} />
        )}
        {view === 'graph' && (
          <GraphView
            load={loadGraph}
            sourceKey={refKey}
            focusIds={graphFocus}
            onAdd={() => goto('home')}
            onAsk={(page) => {
              home.askAbout(askAboutText(page.title))
              goto('home')
            }}
          />
        )}
        {view === 'history' && (
          <EmptyView title="History" icon={<HistoryIcon />}>
            History comes in a later step. It will list everything ObsidiNote adds to your notebook, so you can open or undo it.
          </EmptyView>
        )}
      </main>
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
    </div>
  )
}
