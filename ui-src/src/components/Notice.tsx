import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from 'react'
import { Icon } from './icons'

/** False inside a part of the window whose announcements one kept live region owns (the home
 *  view's result area, HomeView.tsx): its notices are then plain boxes, so nothing is said twice. */
export const NoticeIsLive = createContext(true)

/** True while a view draws for the first time (App's `ViewOpening`, keyed by the view). */
const ViewIsOpening = createContext<{ current: boolean }>({ current: false })

/** Around a view: an error box that is already there when the view opens is a status (it is the
 *  view's state, read with the rest of it); one that appears later is an alert (operator, 2026-11-24). */
export function ViewOpening({ children }: { children: ReactNode }) {
  const opening = useRef(true)
  useEffect(() => {
    opening.current = false
  }, [])
  return <ViewIsOpening.Provider value={opening}>{children}</ViewIsOpening.Provider>
}

/** The interface's one message box (.notice in tokens.css). An error carries the warning icon, a
 *  soft fill and, where there is one, the way forward in `actions`; `busy` shows a turning ring
 *  with the seconds waited. */
export function Notice({ error = false, busy = false, title, children, actions }: {
  error?: boolean
  busy?: boolean
  title?: ReactNode
  children?: ReactNode
  actions?: ReactNode
}) {
  const live = useContext(NoticeIsLive)
  const opening = useContext(ViewIsOpening)
  // An error drawn in the view's first render was present on open; once it clears, a new one is news.
  const [present, setPresent] = useState(() => error && opening.current)
  if (present && !error) setPresent(false)
  const role = live ? (error && !present ? 'alert' : 'status') : undefined
  return (
    <div className={error ? 'notice notice--error' : 'notice'} role={role} aria-busy={busy || undefined}>
      {error && <Icon name="warn" />}
      {busy && <span className="spinner" aria-hidden="true" />}
      <div className="notice__body">
        {title && (
          <p className="notice__title">
            {title}
            {busy && <Elapsed />}
          </p>
        )}
        {children}
        {actions && <div className="notice__actions">{actions}</div>}
      </div>
    </div>
  )
}

/** Seconds since it appeared (" · 12 s", then " · 1 min 5 s"). Not read out: a status region that
 *  changes every second would be announced every second. */
export function Elapsed() {
  const [s, setS] = useState(0)
  useEffect(() => {
    const start = Date.now()
    const t = window.setInterval(() => setS(Math.floor((Date.now() - start) / 1000)), 1000)
    return () => window.clearInterval(t)
  }, [])
  return (
    <span className="notice__elapsed num" aria-hidden="true">
      {' · '}
      {elapsedText(s)}
    </span>
  )
}

export function elapsedText(seconds: number): string {
  // No-break spaces: a number and its unit never break apart.
  return seconds < 60 ? `${seconds} s` : `${Math.floor(seconds / 60)} min ${seconds % 60} s`
}
