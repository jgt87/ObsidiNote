import iconUrl from '../../../assets/icon.svg'
import type { NotebooksState, NotebookState } from '../hooks/useServerData'
import type { AttentionNote } from '../model/attention'
import { plural } from '../model/format'
import { VIEW_ORDER, VIEWS, type View } from '../model/views'
import { GraphIcon, HistoryIcon, PlusIcon, WarnIcon } from './icons'
import { NotebookSwitcher } from './NotebookSwitcher'
import { SectionTree } from './SectionTree'
import './Rail.css'

const NAV_ICONS: Record<View, () => React.JSX.Element> = { home: PlusIcon, graph: GraphIcon, history: HistoryIcon }

interface Props {
  view: View
  notebooks: NotebooksState
  notebook: NotebookState
  notes: AttentionNote[]
}

export function Rail({ view, notebooks, notebook, notes }: Props) {
  const nb = notebook.data
  return (
    <nav className="rail" aria-label="Main">
      <div className="rail__brand">
        <img src={iconUrl} width="26" height="26" alt="" />
        <span>ObsidiNote</span>
      </div>

      <NotebookSwitcher notebooks={notebooks} />

      <ul className="rail__nav">
        {VIEW_ORDER.map((v) => {
          const Icon = NAV_ICONS[v]
          return (
            <li key={v}>
              <a href={VIEWS[v].hash} className="rail__link" aria-current={v === view ? 'page' : undefined}>
                <Icon />
                {VIEWS[v].label}
              </a>
            </li>
          )
        })}
      </ul>

      <section className="rail__notebook" aria-labelledby="rail-sections">
        <h2 id="rail-sections" className="rail__label">
          Sections{nb?.notebook ? ` of ${nb.notebook.name}` : ''}
        </h2>
        {nb?.available ? (
          <SectionTree nodes={nb.sections} />
        ) : (
          // The reason is in the attention note below (from /api/status); no need to say it twice.
          <p className="rail__muted">{notebook.loading && !nb ? 'Reading the notebook...' : 'No sections to show.'}</p>
        )}
      </section>

      <footer className="rail__footer">
        {notes.length > 0 && (
          <ul className="rail__notes" role="status" aria-label="Needs attention">
            {notes.map((n) => (
              <li key={n.id} className="rail__note">
                <WarnIcon />
                <span>{n.text}</span>
              </li>
            ))}
          </ul>
        )}
        {nb?.available && nb.notebook && (
          <p className="rail__muted num">
            {plural(nb.totals.pages, 'page')} · {plural(nb.totals.sections, 'section')}
            <br />
            {nb.notebook.name}
            {nb.notebook.location ? ` (${nb.notebook.location})` : ''}
            {nb.notebook.vault ? '' : ', read only'}
          </p>
        )}
      </footer>
    </nav>
  )
}
