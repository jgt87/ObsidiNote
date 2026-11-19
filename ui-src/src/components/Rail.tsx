import { useState } from 'react'
import iconUrl from '../../../assets/icon.svg'
import type { NotebookView } from '../api'
import type { NotebooksState, NotebookState } from '../hooks/useServerData'
import type { AttentionNote } from '../model/attention'
import { plural } from '../model/format'
import { canSetUpShown, notebookLine, sectionsEmptyText, sectionsHeading } from '../model/railWording'
import { VIEW_ORDER, VIEWS, type View } from '../model/views'
import { GraphIcon, HistoryIcon, JournalIcon, PlusIcon, SettingsIcon, WarnIcon } from './icons'
import { RetryButton } from './RetryButton'
import { NotebookSwitcher } from './NotebookSwitcher'
import { SectionTree } from './SectionTree'
import { ThemeSwitch } from './ThemeSwitch'
import './Rail.css'

const NAV_ICONS: Record<View, () => React.JSX.Element> = { home: PlusIcon, graph: GraphIcon, journal: JournalIcon, history: HistoryIcon }

interface Props {
  view: View
  notebooks: NotebooksState
  notebook: NotebookState
  notes: AttentionNote[]
  onNewVault: () => void
  onSetUp: () => void
  /** Tries to connect Copilot again; resolves to '' when it worked, else what the person should know. */
  onRetryCopilot: () => Promise<string>
  /** Opens Settings (kept in the vault in OneNote); none without an active vault. */
  onSettings?: () => void
  /** Opens the List of the shown notebook on one section's pages (a search query). */
  onOpenSection?: (query: string) => void
}

export function Rail({ view, notebooks, notebook, notes, onNewVault, onSetUp, onRetryCopilot, onSettings, onOpenSection }: Props) {
  const nb = notebook.data
  return (
    <nav className="rail" aria-label="Main">
      <div className="rail__brand">
        <img src={iconUrl} width="26" height="26" alt="" />
        <span>ObsidiNote</span>
      </div>

      {/* The menu first, under the name; the notebook switcher below it (operator, 2026-11-14). */}
      <RailMenu view={view} onSettings={onSettings} />

      <NotebookSwitcher notebooks={notebooks} onNewVault={onNewVault} onSetUp={canSetUpShown(nb, notebooks.shownId) ? onSetUp : null} />

      <RailSections notebook={notebook} onOpenSection={onOpenSection} />

      <footer className="rail__footer">
        <RailNotes notes={notes} onRetryCopilot={onRetryCopilot} />
        <RailNotebookCounts nb={nb} />
        <div className="rail__theme">
          <ThemeSwitch />
        </div>
      </footer>
    </nav>
  )
}

/** The views, then Settings when there is an active vault. */
function RailMenu({ view, onSettings }: { view: View; onSettings?: () => void }) {
  return (
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
      {onSettings && (
        // Not a view: opens the Settings window (kept in the vault in OneNote).
        <li>
          <button type="button" className="rail__link rail__link--btn" onClick={onSettings}>
            <SettingsIcon />
            Settings
          </button>
        </li>
      )}
    </ul>
  )
}

/** The shown notebook's sections, foldable in a narrow window. */
function RailSections({ notebook, onOpenSection }: { notebook: NotebookState; onOpenSection?: (query: string) => void }) {
  const nb = notebook.data
  // In a narrow window the side bar is a bar at the top; its section list is folded there until
  // asked for, so the Add box stays on the first screen (review 2026-11-14). Wide: always shown.
  const [sectionsOpen, setSectionsOpen] = useState(false)
  return (
    <section className="rail__notebook" aria-labelledby="rail-sections">
      <div className="rail__sections-head">
        <h2 id="rail-sections" className="rail__label">
          {sectionsHeading(nb)}
        </h2>
        <button type="button" className="link-btn rail__fold" aria-expanded={sectionsOpen} aria-controls="rail-section-list" onClick={() => setSectionsOpen(!sectionsOpen)}>
          {sectionsOpen ? 'Hide' : 'Show'}
        </button>
      </div>
      <div id="rail-section-list" className="rail__scroll" data-open={sectionsOpen}>
        {nb?.available ? (
          <SectionTree nodes={nb.sections} onOpen={onOpenSection} vault={Boolean(nb.notebook?.vault)} />
        ) : (
          <p className="rail__muted">{sectionsEmptyText(notebook.loading, nb)}</p>
        )}
      </div>
    </section>
  )
}

/** What needs attention; nothing when all is well. */
function RailNotes({ notes, onRetryCopilot }: { notes: AttentionNote[]; onRetryCopilot: () => Promise<string> }) {
  if (notes.length === 0) return null
  return (
    <ul className="rail__notes" role="status" aria-label="Needs attention">
      {notes.map((n) => (
        <li key={n.id} className="rail__note">
          <WarnIcon />
          {n.retry ? <RetryButton text={n.text} onRetry={onRetryCopilot} /> : <span>{n.text}</span>}
        </li>
      ))}
    </ul>
  )
}

/** The shown notebook's counts and name; nothing until it has been read. Export as Markdown lives
 *  in the page window, per page and per topic (operator, 2026-11-14: not a button in the side bar). */
function RailNotebookCounts({ nb }: { nb: NotebookView | null }) {
  if (!nb?.available || !nb.notebook) return null
  return (
    <div className="rail__vault">
      <p className="rail__muted num">
        {plural(nb.totals.pages, 'page')} · {plural(nb.totals.sections, 'section')}
        <br />
        {notebookLine(nb.notebook)}
      </p>
    </div>
  )
}
