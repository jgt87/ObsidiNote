// What the Add box says while it takes a dropped or picked file, and what a drop carries. Pure
// (tests: fileNotes.test.ts); the reading itself is fileText.ts, the box is components/Composer.tsx.
import type { LocateResult } from '../api'

export interface FileNote {
  text: string
  error: boolean
}

export const FILE_TOO_LARGE: FileNote = { text: 'This file is larger than 10 MB. Paste the part you want to keep instead.', error: true }

export function fileReadingNote(name: string): FileNote {
  return { text: `Reading ${name}…`, error: false }
}

/** The reader's own remark (e.g. that the text was cut), as a sentence to append; '' for none. */
export function readerRemark(message: string): string {
  return message ? ` ${message}` : ''
}

/** The text is in the box; the OneDrive lookup still runs. */
export function fileLookingNote(name: string, remark: string): FileNote {
  return { text: `${name} is in the box.${remark} Looking for it in OneDrive…`, error: false }
}

/** After the OneDrive lookup: the note, and the file's address when exactly one synced file matched
 *  (null otherwise; a failed lookup counts as not found). */
export function fileLocatedNote(name: string, remark: string, found: LocateResult | null): { note: FileNote; url: string | null } {
  if (found?.status === 'found' && found.url) {
    return { note: { text: `${name} is in your OneDrive or SharePoint: the page keeps its link.${remark} Check the text, then press Add.`, error: false }, url: found.url }
  }
  const why = found?.status === 'many' ? ' (more than one file matched, so no link is kept)' : ''
  return { note: { text: `${name} is in the box${why}.${remark} Check it, then press Add.`, error: false }, url: null }
}

/** A drag the box takes: files, or a link dragged from a browser tab. */
export function dragIsTakeable(types: readonly string[]): boolean {
  return types.includes('Files') || types.includes('text/uri-list')
}

/** The first web address of a dropped link list (text/uri-list), trimmed; null for none. */
export function droppedLink(uriList: string): string | null {
  const link = uriList.split(/\r?\n/).find((l) => /^https?:\/\//i.test(l.trim()))
  return link ? link.trim() : null
}
