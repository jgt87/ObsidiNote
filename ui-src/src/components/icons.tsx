// One icon set: 16 px, 1.5 px stroke, currentColor. Decorative unless the caller labels it.
import type { ReactNode } from 'react'

function Icon({ children }: { children: ReactNode }) {
  return (
    <svg className="icon" width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {children}
    </svg>
  )
}

export const PlusIcon = () => (
  <Icon>
    <path d="M8 3v10M3 8h10" />
  </Icon>
)

export const GraphIcon = () => (
  <Icon>
    <circle cx="4" cy="4" r="2" />
    <circle cx="12" cy="6" r="2" />
    <circle cx="6" cy="12" r="2" />
    <path d="M5.9 4.5 10.1 5.5M4.6 5.9 5.4 10.1" />
  </Icon>
)

export const HistoryIcon = () => (
  <Icon>
    <path d="M3 4h10M3 8h10M3 12h6" />
  </Icon>
)

export const AskIcon = () => (
  <Icon>
    <circle cx="7" cy="7" r="4.5" />
    <path d="m10.5 10.5 3 3" />
  </Icon>
)

export const AddIcon = () => (
  <Icon>
    <rect x="2.5" y="2.5" width="11" height="11" rx="2" />
    <path d="M8 5.5v5M5.5 8h5" />
  </Icon>
)

export const InfoIcon = () => (
  <Icon>
    <circle cx="8" cy="8" r="5.75" />
    <path d="M8 7.5v3.5M8 5.2v.1" />
  </Icon>
)

export const WarnIcon = () => (
  <Icon>
    <path d="M8 2.5 14 13H2Z" />
    <path d="M8 6.5v3M8 11.3v.1" />
  </Icon>
)

/** Try again: a circular arrow. */
export const RefreshIcon = () => (
  <Icon>
    <path d="M13 8a5 5 0 1 1-1.46-3.54" />
    <path d="M13 2.5v3h-3" />
  </Icon>
)

/** Points right; the parent rotates it (CSS transform) when open. */
export const ChevronIcon = () => (
  <Icon>
    <path d="m6.5 4.5 3.5 3.5-3.5 3.5" />
  </Icon>
)
