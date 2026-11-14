// Where a page without an address came from (operator, 2026-11-14): the "From:" choice under the
// box (prefilled from the paste, add/pasteOrigin.ts), and the "From" field of Edit. The server keeps
// the same table (lib/NotebookStructure.psm1 $script:Origins) and refuses other ids; both are pinned
// to tests/fixtures/origins.json (origins.test.ts and tests/PageEdit.Tests.ps1): change all three
// together. '' = typed in ObsidiNote (or not known).

export interface Origin {
  id: string
  /** What the person picks ("Outlook mail"). */
  label: string
  /** The Sources-view area the page then lands in ("Outlook"). */
  source: string
  kind: 'm365' | 'other'
}

export const ORIGINS: Origin[] = [
  { id: 'outlook', label: 'Outlook mail', source: 'Outlook', kind: 'm365' },
  { id: 'teams', label: 'Teams chat', source: 'Teams', kind: 'm365' },
  { id: 'word', label: 'Word document', source: 'Word', kind: 'm365' },
  { id: 'onedrive', label: 'OneDrive file', source: 'OneDrive', kind: 'm365' },
  { id: 'sharepoint', label: 'SharePoint page', source: 'SharePoint', kind: 'm365' },
  { id: 'web', label: 'Web page', source: 'Other web sites', kind: 'other' },
  // A file dropped on the box (2026-11-14): its text is read in the browser (add/fileText.ts).
  { id: 'file', label: 'File you dropped', source: 'Files', kind: 'other' },
]

/** The label of "no origin". */
export const TYPED_LABEL = 'Typed in ObsidiNote'

/** A known origin id, else '' (typed). */
export function validOrigin(id: unknown): string {
  return typeof id === 'string' && ORIGINS.some((o) => o.id === id) ? id : ''
}

export function originLabel(id: string): string {
  return ORIGINS.find((o) => o.id === id)?.label ?? TYPED_LABEL
}
