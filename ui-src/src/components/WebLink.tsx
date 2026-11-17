import type { MouseEvent, ReactNode } from 'react'
import { openInBrowser } from '../api'

/** Whether a click on a web link goes to the default browser: a plain primary click. A click with
 *  Ctrl, Shift, Alt or Meta, or another button, keeps the browser's own meaning (copy, new window). */
export function opensInDefaultBrowser(e: Pick<MouseEvent, 'button' | 'ctrlKey' | 'shiftKey' | 'altKey' | 'metaKey' | 'defaultPrevented'>): boolean {
  return !e.defaultPrevented && e.button === 0 && !e.ctrlKey && !e.shiftKey && !e.altKey && !e.metaKey
}

/** A link to a web address (http/https) that opens in a new tab of the person's default browser
 *  (operator, 2026-11-17), through ObsidiNote's server, which asks Windows to open it. It stays a real
 *  link (copy address, middle click); when the server cannot open it, the window opens it itself. */
export function WebLink({ href, className, title, label, children }: { href: string; className?: string; title?: string; label?: string; children: ReactNode }) {
  const onClick = (e: MouseEvent<HTMLAnchorElement>) => {
    if (!opensInDefaultBrowser(e)) return
    e.preventDefault()
    openInBrowser(href).catch(() => window.open(href, '_blank', 'noopener,noreferrer'))
  }
  return (
    <a className={className} href={href} target="_blank" rel="noopener noreferrer" title={title} aria-label={label} onClick={onClick}>
      {children}
    </a>
  )
}
