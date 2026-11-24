import type { ReactNode } from 'react'

/** A button's label that can turn busy (operator, 2026-11-24): while the button carries
 *  `aria-busy="true"`, a turning ring and the busy text stand in the label's place. Both labels sit
 *  in one grid cell (styles/app.css .busy-label), so the button keeps the width of the wider one and
 *  nothing beside it moves; the hidden one is not part of the button's name. The button keeps
 *  `aria-busy` and `unavailable(busy)` itself. Without `busyText` the label stays, with the ring. */
export function BusyLabel({ label, busyText }: { label: ReactNode; busyText?: ReactNode }) {
  return (
    <span className="busy-label">
      <span className="busy-label__idle">{label}</span>
      <span className="busy-label__busy">
        <span className="spinner" aria-hidden="true" />
        {busyText ?? label}
      </span>
    </span>
  )
}
