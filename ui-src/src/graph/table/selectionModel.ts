// The List's ticked rows (pure): what the selection bar offers for them, and which ticks a search
// or a filter leaves. GraphList.tsx holds the ticks (session state) and renders the bar.

import type { GraphPage } from '../model'
import { isLinkPage } from '../linkUpdateRun'

/** The ticked pages, split the way the selection bar acts on them. Ids that are no page are left out. */
export interface SelectionParts {
  /** Every tag any ticked page has, sorted: the tag bar's chips (a chip's x takes it off them all). */
  tags: string[]
  /** Ticked pages that are not archived: what Archive sends. */
  live: string[]
  /** Ticked pages that are archived: what Restore sends. */
  archived: string[]
  /** Ticked link pages: what "Update summaries" runs. */
  links: string[]
}

export function selectionParts(selected: Iterable<string>, pageById: ReadonlyMap<string, GraphPage>): SelectionParts {
  const ticked = [...selected].map((id) => pageById.get(id)).filter((p) => p !== undefined)
  return {
    tags: [...new Set(ticked.flatMap((p) => p.tags ?? []))].sort(),
    live: ticked.filter((p) => !p.archived).map((p) => p.id),
    archived: ticked.filter((p) => p.archived).map((p) => p.id),
    links: ticked.filter(isLinkPage).map((p) => p.id),
  }
}

/** "Archive" or "Restore", with its count only when the selection also holds the other kind, so
 *  the two buttons say how many each one reaches. */
export function retireLabel(word: string, own: number, other: number): string {
  return other ? `${word} (${own})` : word
}

/**
 * The ticks a new model or search leaves: a page that left the model, or that the search or a
 * filter hides (`visible`, null for all), is unticked, so an action on the selection (Delete,
 * Archive, tags) only reaches pages the person can see. The same set comes back when nothing changed.
 */
export function keepVisible(selected: ReadonlySet<string>, exists: (id: string) => boolean, visible: string[] | null): ReadonlySet<string> {
  const shown = visible ? new Set(visible) : null
  const kept = [...selected].filter((id) => exists(id) && (!shown || shown.has(id)))
  return kept.length === selected.size ? selected : new Set(kept)
}
