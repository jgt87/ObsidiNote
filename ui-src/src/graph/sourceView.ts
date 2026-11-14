// The knowledge graph by source (operator, 2026-11-14: "switch from topic areas to data sources:
// SharePoint is one source, OneDrive another"). Pure: the same model with its areas made from
// GraphModel.sources instead of the topic tree, so the map's layout, lines, sizes and hover all
// work unchanged. The server decides each page's source (lib/GraphModel.psm1, Get-LinkSource);
// this module only regroups. The page window, filters and List keep the real topics.

import type { GraphModel, GraphSourceArea, GraphTopic } from './model'

/** What the map groups its areas by. Session state (in memory), like the other view state. */
export type GroupBy = 'topics' | 'sources'

/** The second line of a source area's name: what kind of source it is. */
const KIND_LINE: Record<GraphSourceArea['kind'], string> = {
  m365: 'Microsoft 365',
  service: 'company service',
  web: 'web site',
  other: 'web sites with one or two pages',
  notes: 'pages without an address',
}

/** The model with one area per source: each page in the area of its sourceId, no topic tree. */
export function bySource(model: GraphModel): GraphModel {
  const sources = model.sources ?? []
  const topics: GraphTopic[] = sources.map((s) => ({ id: s.id, name: s.name, path: s.name, parent: null, pageCount: s.pageCount, subjects: KIND_LINE[s.kind] }))
  const known = new Set(sources.map((s) => s.id))
  const pages = model.pages.map((p) => ({ ...p, topicIds: known.has(p.sourceId) ? [p.sourceId] : [] }))
  return { ...model, topics, pages }
}
