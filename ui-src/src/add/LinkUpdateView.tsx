import { changedFields } from './format'
import type { LinkUpdate } from './types'

/** Old vs new of a link page's summary: changed fields, summary text, key facts added or removed,
 *  and links that the new summary no longer proposes (kept, listed for review). */
export function LinkUpdateView({ update, status }: { update: LinkUpdate; status: string }) {
  const { old, new: next, diff } = update
  const fields = changedFields(update)

  if (status === 'unchanged') {
    return (
      <section className="add-card">
        <p className="add-label">Summary</p>
        <p className="add-text">No changes since {update.oldAt || 'the last check'}. Only the date was updated.</p>
      </section>
    )
  }

  return (
    <section className="add-card" aria-labelledby="add-update-heading">
      <div className="add-card__head">
        <h2 id="add-update-heading" className="add-label">
          What changed
        </h2>
        <span className="add-muted">
          {update.oldAt ? `summarized ${update.oldAt}` : 'first summary'}
          {update.newAt ? ` → ${update.newAt}` : ''}
        </span>
      </div>

      {fields.length > 0 && (
        <dl className="add-diff">
          {fields.map((f) => (
            <div key={f.label} className="add-diff__row">
              <dt className="add-muted">{f.label}</dt>
              <dd>
                <del className="add-old">{f.old || '(empty)'}</del>
                <ins className="add-new">{f.new || '(empty)'}</ins>
              </dd>
            </div>
          ))}
        </dl>
      )}

      <div className="add-compare">
        <div>
          <h3 className="add-label">Before</h3>
          <p className="add-text">{old?.summary || 'No earlier summary.'}</p>
        </div>
        <div>
          <h3 className="add-label">Now</h3>
          <p className="add-text">{next?.summary || 'The source could not be read; the earlier summary stays.'}</p>
        </div>
      </div>

      {diff && (diff.factsAdded.length > 0 || diff.factsRemoved.length > 0) && (
        <div className="add-facts">
          <h3 className="add-label">Key facts</h3>
          <ul className="add-facts__list">
            {diff.factsAdded.map((f) => (
              <li key={`a:${f}`}>
                <span className="add-facts__sign" aria-label="added">
                  +
                </span>
                {f}
              </li>
            ))}
            {diff.factsRemoved.map((f) => (
              <li key={`r:${f}`} className="add-old">
                <span className="add-facts__sign" aria-label="removed">
                  −
                </span>
                {f}
              </li>
            ))}
          </ul>
        </div>
      )}

      {update.review.length > 0 && (
        <div className="add-facts">
          <h3 className="add-label">Links to review</h3>
          <p className="add-muted">The new summary no longer points to these pages. The links stay until you remove them.</p>
          <ul className="add-facts__list">
            {update.review.map((r) => (
              <li key={r.target}>
                {r.link ? (
                  <a className="add-a" href={r.link}>
                    {r.title || r.target}
                  </a>
                ) : (
                  r.title || r.target
                )}
              </li>
            ))}
          </ul>
        </div>
      )}
      <p className="add-muted add-note">Earlier summaries are kept on the page (the last 3). Your notes are not touched.</p>
    </section>
  )
}
