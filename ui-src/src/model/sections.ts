// A section of the side bar's list as a search of the knowledge graph's List. Pure (tests:
// sections.test.ts, on tests/fixtures/graph-pages.json, which the server's own test produces).
// A graph page carries its section path as OneNote has it ("Notes 2", "Journal/2026",
// "Group/Section"); the search language matches it exactly with section:"..." (search/query.ts).
// Not the page's `bucket`: that is the type bucket ("Journal" for every year, "Notes" for
// "Notes 2"), which is what made the first version of this open empty lists (2026-11-15).

/** The query that lists a section's pages, or null when its pages are not in the graph. In an
 *  ObsidiNote vault those are the generated Index pages and the Intake requests (lib/Index.psm1
 *  Test-RequestSection) and the Archive, whose pages the graph hides unless its own filter shows
 *  them; a connected notebook's sections are all in its graph, whatever they are called.
 *  `path` = the group names above the section, then its own name. */
export function sectionQuery(path: string[], vault = true): string | null {
  const names = path.map((p) => p.trim()).filter(Boolean)
  if (!names.length) return null
  const top = names[0].toLowerCase()
  if (vault && (top === '00 index' || top === '01 intake' || top === '01 inbox' || top === 'archive')) return null
  return `section:"${names.join('/').replace(/"/g, '')}"`
}
