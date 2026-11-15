import { useEffect, useState, type ReactNode } from 'react'
import { WarnIcon } from './icons'

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
  return (
    <div className={error ? 'notice notice--error' : 'notice'} role={error ? 'alert' : 'status'} aria-busy={busy || undefined}>
      {error && <WarnIcon />}
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
  return seconds < 60 ? `${seconds} s` : `${Math.floor(seconds / 60)} min ${seconds % 60} s`
}
