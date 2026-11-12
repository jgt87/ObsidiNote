import type { ReactNode } from 'react'
import './EmptyView.css'

/** A view that comes in a later step: its title and one honest sentence, no example data. */
export function EmptyView({ title, icon, children }: { title: string; icon: ReactNode; children: ReactNode }) {
  return (
    <div className="page">
      <h1 className="page__title">{title}</h1>
      <div className="empty">
        <span className="empty__icon">{icon}</span>
        <p className="empty__text">{children}</p>
        <a className="btn" href="#/">
          Back to Add or ask
        </a>
      </div>
    </div>
  )
}
