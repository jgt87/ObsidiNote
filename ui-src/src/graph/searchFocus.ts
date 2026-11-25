// Where the map's focus goes while a search runs (D-042: back on the search's result after
// leaving every dot, until the search is cleared). Pure
// (tests: searchFocus.test.ts); KnowledgeGraph.tsx wires it between the stage and its state.
import type { Active } from './GraphStage'

/** The result the search box has chosen: `pick` while it is still one of the results, else the
 *  first result; null without results. */
export function searchPick(results: readonly string[] | null, pick: string | null): string | null {
  if (!results?.length) return null
  return pick && results.includes(pick) ? pick : results[0]
}

/** The focus after the stage asked for `next`: a cleared focus (the pointer left a dot, a click on
 *  an empty spot) goes back to the search's chosen result while a search runs. As a pointer focus:
 *  a keyboard focus would make the stage ignore the next dot the pointer enters. Any other request
 *  is kept as it is. */
export function focusAfter(next: Active | null, results: readonly string[] | null, pick: string | null): Active | null {
  if (next) return next
  const id = searchPick(results, pick)
  return id ? { id, via: 'pointer' } : null
}
