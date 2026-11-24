import { Notice } from '../components/Notice'
import { ActivityRow } from './ActivityRow'
import { useActivity } from './useActivity'
import './activity.css'

/** History (operator, 2026-11-14): what Add and link Update did in the active vault, newest first,
 *  read from its Intake. Edits and "Link it" are not listed (they make no Intake item). */
export function ActivityView({ refreshKey, onOpen }: { refreshKey: string; onOpen: (pageId: string) => void }) {
  const { data, error, loading, reload } = useActivity(refreshKey)
  let body: React.JSX.Element
  if (!data && loading) body = <p className="act__empty" role="status">Reading your Intake...</p>
  else if (!data && error) {
    body = (
      <Notice
        error
        title="History could not be read"
        actions={
          <button type="button" className="btn btn--sm" onClick={reload} aria-label="Try again: read History">
            Try again
          </button>
        }
      >
        <p>{error}</p>
      </Notice>
    )
  } else if (!data?.items.length) body = <p className="act__empty">Nothing added yet. What you add, and what happens to it, appears here.</p>
  else {
    body = (
      <ul className="act__list">
        {data.items.map((i) => (
          <ActivityRow key={i.inboxId} item={i} canChange={data.canChange} vaultId={data.vaultId} onChanged={reload} onOpen={onOpen} />
        ))}
      </ul>
    )
  }
  return (
    <div className="page">
      <h1 className="page__title">History</h1>
      <p className="act__intro">
        Everything you added and every link page you updated, newest first, from your vault’s Intake.
        {data && !data.canChange ? ' Undo and Remove are not available in this window for now; the note above says why.' : ''}
      </p>
      {!data && error ? (
        body
      ) : (
        <section className="act" aria-label="History">
          {body}
        </section>
      )}
    </div>
  )
}
