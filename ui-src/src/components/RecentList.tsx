import type { NotebookState } from '../hooks/useServerData'
import { formatModified } from '../model/format'
import './RecentList.css'

/** The 10 most recently changed pages of the notebook; a title opens the page in OneNote. */
export function RecentList({ notebook }: { notebook: NotebookState }) {
  const nb = notebook.data
  let body: React.JSX.Element
  if (!nb && notebook.loading) body = <p className="recent__state" role="status">Reading your notebook...</p>
  else if (!nb && notebook.error) {
    body = (
      <div className="recent__state" role="alert">
        <p>Could not read the notebook: {notebook.error}</p>
        <button type="button" className="btn btn--sm" onClick={notebook.reload}>
          Try again
        </button>
      </div>
    )
  } else if (!nb?.available) body = <p className="recent__state">{nb?.message || 'The notebook is not available.'}</p>
  else if (!nb.recent.length) body = <p className="recent__state">No pages yet. What you add appears here.</p>
  else {
    body = (
      <ul className="recent__list">
        {nb.recent.map((p, i) => (
          <li key={`${p.link || p.title}:${i}`} className="recent__row">
            <div className="recent__main">
              {p.link ? (
                <a className="recent__title" href={p.link} title={`Open "${p.title}" in OneNote`}>
                  {p.title}
                </a>
              ) : (
                <span className="recent__title">{p.title}</span>
              )}
              <span className="recent__path">{p.section}</span>
            </div>
            <time className="recent__when" dateTime={p.modified}>
              {formatModified(p.modified)}
            </time>
          </li>
        ))}
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
