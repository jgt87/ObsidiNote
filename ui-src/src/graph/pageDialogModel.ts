// Decisions of the page window (PageDialog.tsx): what an arrow key does, the line under the title,
// which "Open" buttons show and which is the primary, the tab names, and the pages two steps away.
// Pure (tests: pageDialogModel.test.ts).
import { pageTypeLabel } from '../model/format'
import { formatDate, plural } from './format'
import type { GraphIndex } from './graphIndex'
import type { GraphPage } from './model'

export type DialogTab = 'page' | 'topic' | 'neighbourhood'
export const DIALOG_TABS: DialogTab[] = ['page', 'topic', 'neighbourhood']

export type DialogKeyAction = 'back' | 'forward' | 'tab-next' | 'tab-prev' | 'step-next' | 'step-prev'

type KeyLike = { key: string; altKey: boolean; ctrlKey: boolean; metaKey: boolean; shiftKey: boolean }

/**
 * An arrow key in the page window. Alt+Left/Right: Back/Forward over the pages visited in this
 * window (never the browser's own history). On a tab: the next or previous tab (ARIA tabs pattern).
 * In a field: the field's own. Elsewhere: the previous or next linked page. null: not the window's.
 */
export function dialogKeyAction(e: KeyLike, onTab: boolean, inField: boolean): DialogKeyAction | null {
  if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return null
  const right = e.key === 'ArrowRight'
  if (e.altKey && !e.ctrlKey && !e.metaKey && !e.shiftKey) return right ? 'forward' : 'back'
  if (onTab) return right ? 'tab-next' : 'tab-prev'
  if (inField) return null
  return right ? 'step-next' : 'step-prev'
}

/** The tab after (or before) `tab`, wrapping round. */
export function nextTab(tab: DialogTab, delta: 1 | -1): DialogTab {
  const i = DIALOG_TABS.indexOf(tab)
  return DIALOG_TABS[(i + delta + DIALOG_TABS.length) % DIALOG_TABS.length]
}

export function tabLabel(tab: DialogTab, topicName: string | undefined): string {
  if (tab === 'page') return 'Page'
  if (tab === 'topic') return `Topic: ${topicName ?? 'Unfiled'}`
  return 'Neighbourhood'
}

/** The line under the title: what the page is (or "most linked page"), its section, when it
 *  changed, and its link counts. "hub" is the operator's word for a topic area (2026-11-15): never
 *  used for a page here. */
export function pageMetaLine(page: GraphPage, linksOut: number, linkedFrom: number): string {
  return [
    page.isHub ? 'most linked page' : pageTypeLabel(page.kind),
    page.bucket,
    formatDate(page.modified) && `changed ${formatDate(page.modified)}`,
    plural(linksOut, 'link'),
    plural(linkedFrom, 'backlink'),
  ]
    .filter(Boolean)
    .join(' · ')
}

export interface OpenButtons {
  /** "Open link": a link page's own address. */
  link: { href: string; primary: boolean } | null
  /** "Open in OneNote": href '' = shown, but disabled (no OneNote link known). */
  onenote: { href: string; primary: boolean } | null
}

/**
 * The window's "Open" buttons. A link page opens its own address first and OneNote second
 * (operator, 2026-11-13: use OneNote as little as possible as the interface); any other page opens
 * in OneNote, shown disabled when there is no OneNote link. One primary per view: while the Edit
 * form is open its Save is the primary, so these go quiet.
 */
export function openButtons(page: Pick<GraphPage, 'url' | 'onenoteUrl'>, editing: boolean): OpenButtons {
  if (page.url) return { link: { href: page.url, primary: !editing }, onenote: page.onenoteUrl ? { href: page.onenoteUrl, primary: false } : null }
  return { link: null, onenote: { href: page.onenoteUrl || '', primary: !editing } }
}

/** A page's links: those it makes, those made to it, and the mentions it is part of. */
export function pageLinks(index: GraphIndex, pageId: string) {
  return {
    out: index.out.get(pageId) ?? [],
    back: index.in.get(pageId) ?? [],
    mentions: (index.mentions.get(pageId) ?? []).filter((e) => e.from === pageId || e.to === pageId),
  }
}

/** The keys line at the foot of the window: Esc always; the arrows when the page it was opened on
 *  has linked pages; Alt+arrows once there is a page to go back or forward to. */
export function dialogKeysHint(linkedOfAnchor: number, canMove: boolean): string {
  return `Esc closes${linkedOfAnchor ? ' · ← → previous or next linked page' : ''}${canMove ? ' · Alt+← → back or forward' : ''}`
}

/** How many pages are two links away from `pageId` (linked to its linked pages, not to it). */
export function twoStepsAway(index: GraphIndex, pageId: string): number {
  const neighbours = index.neighbours.get(pageId) ?? []
  const second = new Set<string>()
  for (const n of neighbours) for (const m of index.neighbours.get(n) ?? []) if (m !== pageId && !neighbours.includes(m)) second.add(m)
  return second.size
}
