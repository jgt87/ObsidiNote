// What the side bar says about the shown notebook: pure, so each case has a test (railWording.test.ts).
import type { NotebookSummary, NotebookView } from '../api'

/** The heading over the section list: with the notebook's name once it is known. */
export function sectionsHeading(nb: NotebookView | null): string {
  return `Sections${nb?.notebook ? ` of ${nb.notebook.name}` : ''}`
}

/** The line in place of the section list. The reason it is empty is in the attention note
 *  (from /api/status), so it is not said here a second time. */
export function sectionsEmptyText(loading: boolean, nb: NotebookView | null): string {
  return loading && !nb ? 'Reading the notebook...' : 'No sections to show.'
}

/** The footer's name line: the notebook, where it is, and "read only" when it is no vault. */
export function notebookLine(notebook: NotebookSummary): string {
  return `${notebook.name}${notebook.location ? ` (${notebook.location})` : ''}${notebook.vault ? '' : ', read only'}`
}

/** Set-up is offered only for the notebook the switcher shows, when the server says it can be. */
export function canSetUpShown(nb: NotebookView | null, shownId: string | null): boolean {
  return Boolean(nb?.notebook?.canSetUp && nb.notebook.id === shownId)
}
