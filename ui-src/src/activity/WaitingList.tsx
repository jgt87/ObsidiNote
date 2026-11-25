import { ActivityRow } from './ActivityRow'
import { waitingItems } from './activityModel'
import { useActivity } from './useActivity'
import './activity.css'

/** "Waiting for Copilot" on the home page (D-013): every Intake item still waiting,
 *  with Check for the answer and Remove, so it is not lost when the Add result is gone. Nothing
 *  shows when nothing waits (or the list cannot be read: History says why). */
export function WaitingList({ refreshKey, onOpen }: { refreshKey: string; onOpen: (pageId: string) => void }) {
  const { data, reload } = useActivity(refreshKey)
  const items = data ? waitingItems(data) : []
  if (!items.length) return null
  return (
    <section className="act" aria-labelledby="waiting-heading">
      <h2 id="waiting-heading" className="act__heading">
        Waiting for Copilot
      </h2>
      <ul className="act__list">
        {items.map((i) => (
          <ActivityRow key={i.inboxId} item={i} canChange={data!.canChange} vaultId={data!.vaultId} onChanged={reload} onOpen={onOpen} />
        ))}
      </ul>
    </section>
  )
}
