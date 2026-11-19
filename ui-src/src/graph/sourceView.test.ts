import { describe, expect, it } from 'vitest'
import { layoutGraph } from './layout'
import { normalizeGraph } from './model'
import { bySource } from './sourceView'

// Invented example data only.
const model = normalizeGraph({
  source: { kind: 'vault', id: 'v1', name: 'Test vault' },
  topics: [{ id: 'Security', name: 'Security', path: 'Security' }],
  pages: [
    { id: 'a', title: 'Leave policy', topicIds: ['Security'], url: 'https://fernbrook.sharepoint.com/sites/HR/x', sourceId: 'sharepoint/hr' },
    { id: 'b', title: 'Plan.docx', topicIds: ['Security'], sourceId: 'onedrive' },
    { id: 'c', title: 'A typed note', topicIds: [], sourceId: 'obsidinote' },
    { id: 'd', title: 'No source sent', topicIds: ['Security'] },
  ],
  edges: [{ from: 'a', to: 'b', strength: 2 }],
  sources: [
    { id: 'sharepoint/hr', name: 'SharePoint: HR', kind: 'm365', pageCount: 1 },
    { id: 'onedrive', name: 'OneDrive', kind: 'm365', pageCount: 1 },
    { id: 'obsidinote', name: 'ObsidiNote notes', kind: 'notes', pageCount: 1 },
  ],
})

describe('normalizeGraph: sources', () => {
  it('keeps the sources, puts a page without a known source in the notes area, counts from the pages', () => {
    expect(model.pages.find((p) => p.id === 'd')!.sourceId).toBe('obsidinote')
    expect(model.sources!.map((s) => `${s.id}:${s.pageCount}`)).toEqual(['sharepoint/hr:1', 'onedrive:1', 'obsidinote:2'])
  })

  it('makes a notes area when the server sent no sources at all', () => {
    const m = normalizeGraph({ source: { kind: 'notebook' }, topics: [], pages: [{ id: 'x', title: 'X' }], edges: [] })
    expect(m.sources).toEqual([{ id: 'onenote', name: 'OneNote pages', kind: 'notes', pageCount: 1 }])
  })
})

describe('bySource', () => {
  const s = bySource(model)
  it('has one area per source, named after it, with what kind it is on the second line', () => {
    expect(s.topics.map((t) => `${t.id}|${t.name}|${t.subjects}|${t.parent}`)).toEqual([
      'sharepoint/hr|SharePoint: HR|Microsoft 365|null',
      'onedrive|OneDrive|Microsoft 365|null',
      'obsidinote|ObsidiNote notes|pages without an address|null',
    ])
  })

  it('puts every page in its source area and keeps the links, so the map draws a line between sources', () => {
    expect(s.pages.map((p) => `${p.id}:${p.topicIds.join()}`)).toEqual(['a:sharepoint/hr', 'b:onedrive', 'c:obsidinote', 'd:obsidinote'])
    expect(s.edges).toEqual(model.edges)
    const l = layoutGraph(s)
    expect(l.areas.map((a) => a.id).sort()).toEqual(['obsidinote', 'onedrive', 'sharepoint/hr'])
  })

  it('leaves the real model alone (the page window and filters keep the topics)', () => {
    expect(model.pages.find((p) => p.id === 'a')!.topicIds).toEqual(['Security'])
  })
})
