// Possible duplicates (2026-11-17): pages that share a name, their title or an alias, with another
// page of the map. The Filter's "Possible duplicates" shows only them, so they can be opened side by
// side, linked ("Link it" in the page window, as for a mention), edited, archived or deleted. Names are
// compared without case, accents, punctuation or extra spaces. Untitled pages and journal day pages
// (titled with their date, one per day) are left out. Pure (tests: duplicates.test.ts).
import type { GraphPage } from './model'

/** A name in the one form used to compare: lower case, no accents or punctuation, single spaces. */
export function nameKey(name: string): string {
  return name
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
}

const DATE_TITLE = /^\d{4}-\d{2}-\d{2}$/

/** The ids of the pages that share a name with another page; archived pages only when shown. */
export function duplicateIds(pages: GraphPage[], showArchived = false): Set<string> {
  const byName = new Map<string, Set<string>>()
  for (const p of pages) {
    if (p.archived && !showArchived) continue
    if (DATE_TITLE.test(p.title.trim())) continue
    for (const n of new Set([p.title, ...p.aliases].map(nameKey).filter((k) => k && k !== 'untitled page' && k !== 'untitled'))) {
      const set = byName.get(n) ?? new Set<string>()
      set.add(p.id)
      byName.set(n, set)
    }
  }
  const out = new Set<string>()
  for (const set of byName.values()) if (set.size > 1) for (const id of set) out.add(id)
  return out
}
