// The one icon set (DESIGN.md "Icons"): 16 px grid, 1.5 px round stroke, no fill, currentColor.
// Every icon in the window is <Icon name="..." />; a new one is added to ICONS here, never drawn
// inline in a component. Sized by the one .icon class (styles/app.css) from the viewBox, never by
// width/height per use; a smaller place sets the size on `.icon` in its own sheet. Decorative
// (aria-hidden): the button or text beside it carries the name.
// Not icons and so not here: the map itself (GraphStage) and the legend's samples of it
// (StageChrome), which are drawn with the map's own classes.
import type { ReactNode } from 'react'

type IconDef = { body: ReactNode; box?: string }

const ICONS = {
  plus: { body: <path d="M8 3v10M3 8h10" /> },
  graph: {
    body: (
      <>
        <circle cx="4" cy="4" r="2" />
        <circle cx="12" cy="6" r="2" />
        <circle cx="6" cy="12" r="2" />
        <path d="M5.9 4.5 10.1 5.5M4.6 5.9 5.4 10.1" />
      </>
    ),
  },
  history: { body: <path d="M3 4h10M3 8h10M3 12h6" /> },
  /** A day on a calendar (one page per day); the rings stand above the frame so the lines keep a gap at 16 px. */
  journal: {
    body: (
      <>
        <rect x="2.5" y="3.5" width="11" height="10" rx="1.5" />
        <path d="M2.5 7.5h11M5.5 1.5v2M10.5 1.5v2" />
      </>
    ),
  },
  /** A meeting page: two people (D-072). Not a calendar, so it is not read as the Journal. */
  meeting: {
    body: (
      <>
        <circle cx="6" cy="5.5" r="2" />
        <path d="M2.5 13.5c0-2.2 1.6-3.5 3.5-3.5s3.5 1.3 3.5 3.5" />
        <circle cx="11.5" cy="6" r="1.5" />
        <path d="M11.5 10c1.3 0 2.5.9 2.5 2.8" />
      </>
    ),
  },
  /** A magnifier: Ask, and every search box. */
  search: {
    body: (
      <>
        <circle cx="7" cy="7" r="4.5" />
        <path d="m10.5 10.5 3 3" />
      </>
    ),
  },
  add: {
    body: (
      <>
        <rect x="2.5" y="2.5" width="11" height="11" rx="2" />
        <path d="M8 5.5v5M5.5 8h5" />
      </>
    ),
  },
  info: {
    body: (
      <>
        <circle cx="8" cy="8" r="5.75" />
        <path d="M8 7.5v3.5M8 5.2v.1" />
      </>
    ),
  },
  pencil: { body: <path d="M10.5 3.2l2.3 2.3L6 12.3l-3 .7.7-3z" /> },
  lock: {
    body: (
      <>
        <rect x="3" y="7" width="10" height="7" rx="1.5" />
        <path d="M5.5 7V5a2.5 2.5 0 015 0v2" />
      </>
    ),
  },
  warn: {
    body: (
      <>
        <path d="M8 2.5 14 13H2Z" />
        <path d="M8 6.5v3M8 11.3v.1" />
      </>
    ),
  },
  /** Try again: a circular arrow. */
  refresh: {
    body: (
      <>
        <path d="M13 8a5 5 0 1 1-1.46-3.54" />
        <path d="M13 2.5v3h-3" />
      </>
    ),
  },
  /** Points right; the parent rotates it (CSS transform) when open. */
  chevron: { body: <path d="m6.5 4.5 3.5 3.5-3.5 3.5" /> },
  /** Add a file, beside Send (D-045). */
  paperclip: { body: <path d="M13.2 7.4 8 12.6a3.2 3.2 0 0 1-4.5-4.5l5.4-5.4a2.1 2.1 0 0 1 3 3L6.5 11a1.05 1.05 0 0 1-1.5-1.5l4.8-4.8" /> },
  /** Three sliders, not a gear, to stay in the set's simple strokes. */
  settings: {
    body: (
      <>
        <path d="M2.5 4h2M7.5 4h6M2.5 8h6.5M12 8h1.5M2.5 12h1M6.5 12h7" />
        <circle cx="6" cy="4" r="1.5" />
        <circle cx="10.5" cy="8" r="1.5" />
        <circle cx="5" cy="12" r="1.5" />
      </>
    ),
  },
  check: { body: <path d="m3 8.5 3 3 7-7" /> },
  filter: { body: <path d="M2 4h12M4.5 8h7M7 12h2" /> },
  /** Close, clear, remove (a tag, a filter). */
  close: { body: <path d="M4.5 4.5l7 7M11.5 4.5l-7 7" /> },
  back: { body: <path d="M10 3L5 8l5 5" /> },
  forward: { body: <path d="M6 3l5 5-5 5" /> },
  /** Fit the map to the screen: four corners. */
  fit: { body: <path d="M2 6V2h4M10 2h4v4M14 10v4h-4M6 14H2v-4" /> },
  'sort-up': { body: <path d="M8 12V4M4.5 7.5L8 4l3.5 3.5" /> },
  'sort-down': { body: <path d="M8 4v8M4.5 8.5L8 12l3.5-3.5" /> },
  /** The check box of an on/off button (DESIGN.md "One Look Per Choice"), drawn on its own 12 px grid. */
  'toggle-off': { box: '0 0 12 12', body: <rect x="1" y="1" width="10" height="10" rx="2" /> },
  'toggle-on': {
    box: '0 0 12 12',
    body: (
      <>
        <rect x="1" y="1" width="10" height="10" rx="2" />
        <path d="m3.4 6.2 1.9 1.9 3.3-3.8" />
      </>
    ),
  },
} satisfies Record<string, IconDef>

export type IconName = keyof typeof ICONS

/** One icon by name. `className` adds a place's own class (its size or turn) to `.icon`. */
export function Icon({ name, className }: { name: IconName; className?: string }) {
  const def: IconDef = ICONS[name]
  return (
    <svg
      className={className ? `icon ${className}` : 'icon'}
      viewBox={def.box ?? '0 0 16 16'}
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {def.body}
    </svg>
  )
}
