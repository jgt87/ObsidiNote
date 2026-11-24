import { useState } from 'react'
import { oneNoteHref } from '../model/links'
import { backlinksLine } from './format'
import { StrengthBar } from './StrengthBar'
import type { ResultLink } from './types'

/** How many links show before "Show all" (the strongest come first from the server). */
export const LINKS_SHOWN = 3

/** The "Links" card: strength, page with the words it hangs on, why; then the backlinks line.
 *  The first three show; the rest fold behind "Show all" so the result stays one screen. */
export function LinksCard({ links, backlinks, title = 'Links', showBacklinks = true }: { links: ResultLink[]; backlinks: number; title?: string; showBacklinks?: boolean }) {
  const [all, setAll] = useState(false)
  const shown = all ? links : links.slice(0, LINKS_SHOWN)
  return (
    <section className="add-card" aria-labelledby="add-links-heading">
      <div className="add-card__head">
        <h2 id="add-links-heading" className="add-label">
          {title}
        </h2>
        {links.length > LINKS_SHOWN && (
          <button type="button" className="link-btn add-muted" aria-expanded={all} onClick={() => setAll(!all)}>
            {all ? 'Show the strongest only' : `Show all ${links.length}`}
          </button>
        )}
      </div>
      {links.length === 0 && <p className="add-muted add-links__empty">No links to existing pages.</p>}
      <ul className="add-links">
        {shown.map((l) => (
          <li key={l.target} className="add-link">
            <StrengthBar strength={l.strength} />
            <div className="add-link__main">
              {oneNoteHref(l.link) ? (
                <a className="add-a" href={oneNoteHref(l.link)} title={`Open “${l.title}” in OneNote`}>
                  {l.title || l.target}
                </a>
              ) : (
                <span>{l.title || l.target}</span>
              )}
              {l.anchor && <div className="add-muted">on the words “{l.anchor}”</div>}
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
