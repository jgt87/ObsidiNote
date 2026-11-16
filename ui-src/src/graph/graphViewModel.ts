// Decisions of the knowledge graph view (KnowledgeGraph.tsx): the "/" shortcut, where focus goes
// when the page window closes, what a key in the search box does, and the count line in the header.
// Pure (tests: graphViewModel.test.ts).
import { plural } from './format'
import type { GroupBy } from './sourceView'

type KeyLike = { key: string; ctrlKey: boolean; metaKey: boolean; altKey: boolean }
type TargetLike = { closest?: (selector: string) => unknown; isContentEditable?: boolean } | null

/** Is the event's target a place where "/" is typed (a field, a text box, editable text)? */
export function isTypingTarget(t: TargetLike): boolean {
  return !!t && (!!t.closest?.('input, textarea, select, [contenteditable="true"]') || !!t.isContentEditable)
}

/** "/" focuses the search, anywhere on the page, unless the person is typing or a dialog is open. */
export function isSearchSlash(e: KeyLike, target: TargetLike, dialogOpen: boolean): boolean {
  if (e.key !== '/' || e.ctrlKey || e.metaKey || e.altKey || dialogOpen) return false
  return !isTypingTarget(target)
}

export interface CloseFocusInput {
  mode: 'graph' | 'list'
  /** How the page window was opened. */
  openedBy: 'pointer' | 'keyboard'
  /** The page the window showed last (it may have moved on from the one it opened on). */
  last: string | undefined
  /** What had the focus when the window opened (null: nothing to go back to). */
  back: unknown
  stage: unknown
  body: unknown
}

/**
 * Where focus goes when the page window closes:
 * - 'clear': opened with a click on the map: no page stays focused, so no preview card stays
 *   behind (it would only close when the pointer passed over another dot; operator, 2026-11-13);
 * - 'stage': opened with the keyboard from the map (or from nowhere): back to the map, with the page
 *   the window showed last focused;
 * - 'back': anywhere else (the List, the search box): back to what had the focus.
 */
export function closeFocus(i: CloseFocusInput): 'clear' | 'stage' | 'back' {
  if (i.mode !== 'graph') return 'back'
  if (i.openedBy === 'pointer') return 'clear'
  const cameFromMap = !i.back || i.back === i.stage || i.back === i.body
  return i.last && cameFromMap ? 'stage' : 'back'
}

export type SearchKeyAction = { kind: 'open'; id: string } | { kind: 'clear' } | { kind: 'pick'; id: string }

/** A key in the search box: Enter opens the focused result (else the first), Esc clears the search,
 *  the arrows step through the results and wrap around. null: the key is the field's own. */
export function searchKeyAction(key: string, matches: readonly string[] | null, activeId: string | null, query: string): SearchKeyAction | null {
  const has = !!matches?.length
  if (key === 'Enter' && has) return { kind: 'open', id: activeId && matches!.includes(activeId) ? activeId : matches![0] }
  if (key === 'Escape' && query) return { kind: 'clear' }
  if (key === 'ArrowDown' && has) {
    const i = activeId ? matches!.indexOf(activeId) : -1
    return { kind: 'pick', id: matches![(i + 1) % matches!.length] }
  }
  if (key === 'ArrowUp' && has) {
    const i = activeId ? matches!.indexOf(activeId) : 0
    return { kind: 'pick', id: matches![(i - 1 + matches!.length) % matches!.length] }
  }
  return null
}

/** The middle of the header's count line: "N pages in M topics", "in M sources" or ", M tags". */
export function areaCount(i: { mode: 'graph' | 'list'; groupBy: GroupBy; sources: number; tags: number; topics: number }): { joiner: string; areas: string } {
  const onMap = i.mode === 'graph'
  if (onMap && i.groupBy === 'tags') return { joiner: ', ', areas: plural(i.tags, 'tag') }
  if (onMap && i.groupBy === 'sources') return { joiner: ' in ', areas: plural(i.sources, 'source') }
  return { joiner: ' in ', areas: plural(i.topics, 'topic') }
}
