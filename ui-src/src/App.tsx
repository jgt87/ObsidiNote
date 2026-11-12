import { useEffect, useState } from 'react'
import { Composer } from './components/Composer'
import { EmptyView } from './components/EmptyView'
import { GraphIcon, HistoryIcon } from './components/icons'
import { Rail } from './components/Rail'
import { RecentList } from './components/RecentList'
import { useNotebook, useNotebooks, useStatus } from './hooks/useServerData'
import { attentionNotes } from './model/attention'
import { addTargetFor } from './model/notebooks'
import { viewFromHash, VIEWS, type View } from './model/views'

export function App() {
  const [view, setView] = useState<View>(() => viewFromHash(window.location.hash))
  const { status, serverDown } = useStatus()
  const notebooks = useNotebooks()
  const notebook = useNotebook(notebooks.shownId)
  const addTarget = addTargetFor(notebooks.list, notebooks.activeId, notebooks.shownId)

  useEffect(() => {
    const onHash = () => setView(viewFromHash(window.location.hash))
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  useEffect(() => {
    document.title = view === 'home' ? 'ObsidiNote' : `${VIEWS[view].label} - ObsidiNote`
  }, [view])

  return (
    <div className="shell">
      <Rail view={view} notebooks={notebooks} notebook={notebook} notes={attentionNotes(status, serverDown)} />
      <main className="main">
        {view === 'home' && (
          <div className="page">
            <h1 className="page__title">Add something, or ask your wiki</h1>
            <Composer addTarget={addTarget} />
            <RecentList notebook={notebook} />
          </div>
        )}
        {view === 'graph' && (
          <EmptyView title="Knowledge graph" icon={<GraphIcon />}>
            The knowledge graph comes in a later step. It will show your pages as dots, grouped by topic, with lines for the links between them.
          </EmptyView>
        )}
        {view === 'history' && (
          <EmptyView title="History" icon={<HistoryIcon />}>
            History comes in a later step. It will list everything ObsidiNote adds to your notebook, so you can open or undo it.
          </EmptyView>
        )}
      </main>
    </div>
  )
}
