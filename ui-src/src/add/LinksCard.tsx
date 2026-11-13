import { backlinksLine } from './format'
import { StrengthBar } from './StrengthBar'
import type { ResultLink } from './types'

/** The "Links" card: strength, page with its anchor, why; then the backlinks line. */
export function LinksCard({ links, backlinks, title = 'Links', showBacklinks = true }: { links: ResultLink[]; backlinks: number; title?: string; showBacklinks?: boolean }) {
  return (
    <section className="add-card" aria-labelledby="add-links-heading">
      <div className="add-card__head">
        <h2 id="add-links-heading" className="add-label">
          {title}
        </h2>
        {links.length > 0 && <span className="add-muted">strength · page · why</span>}
      </div>
      {links.length === 0 && <p className="add-muted add-links__empty">No links to existing pages.</p>}
      <ul className="add-links">
        {links.map((l) => (
          <li key={l.target} className="add-link">
            <StrengthBar strength={l.strength} />
            <div className="add-link__main">
              {l.link ? (
                <a className="add-a" href={l.link} title={`Open "${l.title}" in OneNote`}>
                  {l.title || l.target}
                </a>
              ) : (
                <span>{l.title || l.target}</span>
              )}
              {l.anchor && <div className="add-muted">anchor: "{l.anchor}"</div>}
            </div>
            <div className="add-muted">{l.why}</div>
          </li>
        ))}
        {showBacklinks && (
          <li className="add-link add-link--note">
            <span className="add-muted">new</span>
            <div>{backlinksLine(backlinks)}</div>
            <div />
          </li>
        )}
      </ul>
    </section>
  )
}
