import { describe, expect, it } from 'vitest'
import type { NotebookSummary, NotebookView } from '../api'
import { canSetUpShown, notebookLine, sectionsEmptyText, sectionsHeading } from './railWording'

const summary = (o: Partial<NotebookSummary> = {}): NotebookSummary => ({ id: 'n1', name: 'Alpha', vault: true, active: true, location: '', ...o })
const view = (notebook: NotebookSummary | null): NotebookView => ({
  available: true,
  message: '',
  notebook,
  sections: [],
  totals: { sections: 0, pages: 0 },
  recent: [],
})

describe('the side bar wording', () => {
  it('names the notebook in the section heading once it is known', () => {
    expect(sectionsHeading(null)).toBe('Sections')
    expect(sectionsHeading(view(null))).toBe('Sections')
    expect(sectionsHeading(view(summary()))).toBe('Sections of Alpha')
  })

  it('says it is reading only while nothing has come back yet', () => {
    expect(sectionsEmptyText(true, null)).toBe('Reading the notebook...')
    expect(sectionsEmptyText(true, view(null))).toBe('No sections to show.')
    expect(sectionsEmptyText(false, null)).toBe('No sections to show.')
  })

  it('adds the place and "read only" to the notebook line when they apply', () => {
    expect(notebookLine(summary())).toBe('Alpha')
    expect(notebookLine(summary({ location: 'OneDrive' }))).toBe('Alpha (OneDrive)')
    expect(notebookLine(summary({ vault: false, location: 'OneDrive' }))).toBe('Alpha (OneDrive), read only')
  })

  it('offers set-up only for the shown notebook that can be set up', () => {
    expect(canSetUpShown(null, 'n1')).toBe(false)
    expect(canSetUpShown(view(summary()), 'n1')).toBe(false)
    expect(canSetUpShown(view(summary({ canSetUp: true })), 'n1')).toBe(true)
    expect(canSetUpShown(view(summary({ canSetUp: true })), 'n2')).toBe(false)
  })
})
