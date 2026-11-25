import type { NotebookState } from '../hooks/useServerData'
import { formatModified, pageTypeLabel } from '../model/format'
import { Notice } from './Notice'
import './RecentList.css'

/** The 10 most recently changed pages of the notebook. A title opens the page window (the same as in
 *  the knowledge graph: summary, links, Edit, Export; D-026); "OneNote" opens it there. */
export function RecentList({ notebook, onOpen }: { notebook: NotebookState; onOpen?: (pageId: string) => void }) {
  const nb = notebook.data
  let body: React.JSX.Element
  if (!nb && notebook.loading) body = <p className="recent__state" role="status">Reading your notebook...</p>
  else if (!nb && notebook.error) {
    body = (
      <div className="recent__state">
        <Notice
          error
          title="The notebook could not be read"
          actions={
            <button type="button" className="btn btn--sm" onClick={notebook.reload} aria-label="Try again: read the notebook">
              Try again
            </button>
          }
        >
          <p>{notebook.error}</p>
        </Notice>
      </div>
    )
  } else if (!nb?.available) body = <p className="recent__state">{nb?.message || 'The notebook is not available.'}</p>
  else if (!nb.recent.length) body = <p className="recent__state">No pages yet. What you add appears here.</p>
  else {
    body = (
      <ul className="recent__list">
        {nb.recent.map((p, i) => {
          const where = [pageTypeLabel(p.type ?? ''), p.section].filter(Boolean)
          return (
            <li key={`${p.pageId || p.link || p.title}:${i}`} className="recent__row">
              <div className="recent__main">
                {p.pageId && onOpen ? (
                  <button type="button" className="recent__title recent__open" onClick={() => onOpen(p.pageId!)} title={`Open “${p.title}”`}>
                    {p.title}
                  </button>
                ) : p.link ? (
                  <a className="recent__title" href={p.link} title={`Open “${p.title}” in OneNote`}>
                    {p.title}
                  </a>
                ) : (
                  <span className="recent__title">{p.title}</span>
                )}
                <span className="recent__path">{where.join(' in ')}</span>
              </div>
              <time className="recent__when" dateTime={p.modified}>
                {formatModified(p.modified)}
              </time>
              {p.pageId && onOpen && p.link ? (
                <a className="btn btn--sm btn--ghost" href={p.link} aria-label={`Open “${p.title}” in OneNote`}>
                  OneNote
                </a>
              ) : (
                <span />
              )}
            </li>
          )
        })}
      </ul>
    )
  }
  return (
    <section className="recent" aria-labelledby="recent-heading">
      <h2 id="recent-heading" className="recent__heading">
        Recently changed{nb?.notebook && !nb.notebook.active ? ` in ${nb.notebook.name}${nb.notebook.vault ? '' : ' (read only)'}` : ''}
      </h2>
      {body}
    </section>
  )
}
