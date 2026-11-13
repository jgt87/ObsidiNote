import { useEffect, useId, useState } from 'react'
import { dismiss, hiddenCount, isDismissed, loadWhatsNew, shouldShow, visibleNotes, type WhatsNew as WhatsNewData } from '../model/whatsNew'
import './WhatsNew.css'

/** "Updated to vX.Y.Z" on the home view, once after an update: that version's changelog lines.
 *  Nothing shows while it loads, when the start followed no update, or when the server cannot say
 *  (the notice is optional). Dismissed = gone for this run. */
export function WhatsNew() {
  const [info, setInfo] = useState<WhatsNewData | null>(null)
  const [gone, setGone] = useState(isDismissed())
  useEffect(() => {
    let live = true
    void loadWhatsNew().then((w) => {
      if (live) setInfo(w)
    })
    return () => {
      live = false
    }
  }, [])
  if (!info || !shouldShow(info, gone)) return null
  return (
    <WhatsNewNotice
      info={info}
      onDismiss={() => {
        dismiss()
        setGone(true)
      }}
    />
  )
}

export function WhatsNewNotice({ info, onDismiss, startExpanded = false }: { info: WhatsNewData; onDismiss: () => void; startExpanded?: boolean }) {
  const [expanded, setExpanded] = useState(startExpanded)
  const titleId = useId()
  const listId = useId()
  const shown = visibleNotes(info.notes, expanded)
  const more = hiddenCount(info.notes, expanded)
  return (
    <section className="whats-new" aria-labelledby={titleId}>
      <div className="whats-new__head">
        <h2 id={titleId} className="whats-new__title">
          Updated to {info.version}
        </h2>
        <button type="button" className="btn btn--ghost whats-new__dismiss" onClick={onDismiss}>
          Dismiss
        </button>
      </div>
      {shown.length ? (
        <ul id={listId} className="whats-new__list">
          {shown.map((n, i) => (
            <li key={i} className="whats-new__item">
              <span className="whats-new__kind">{n.kind}</span>
              <span className="whats-new__text">{n.text}</span>
            </li>
          ))}
        </ul>
      ) : (
        <p className="whats-new__empty">No notes for this version.</p>
      )}
      {more > 0 && (
        <button type="button" className="link-btn whats-new__more" aria-controls={listId} aria-expanded={false} onClick={() => setExpanded(true)}>
          Show all ({info.notes.length})
        </button>
      )}
    </section>
  )
}
