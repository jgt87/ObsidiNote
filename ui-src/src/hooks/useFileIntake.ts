import { useRef, useState } from 'react'
import { FILE_TOO_LARGE, fileLocatedNote, fileLookingNote, fileReadingNote, readerRemark, type FileNote } from '../add/fileNotes'
import { MAX_FILE_BYTES, readFileText } from '../add/fileText'
import { locateFile, type LocateResult } from '../api'

/** The address of a dropped file and the text it was read as: the box keeps the link only while it
 *  still holds that file's text (components/Composer.tsx). */
export interface FileLink {
  url: string
  text: string
}

/**
 * A file dropped on the Add box, or picked with "Add a file": its text is read here, in memory
 * (add/fileText.ts), and handed to `onText` like a paste; nothing is stored or uploaded as a file.
 * Then, when it is in a folder OneDrive syncs here (operator, 2026-11-14), its address is looked up
 * so the Add makes that file's link page.
 *
 * Every step after an await first checks that the box has not moved on (a send, an emptied box, a
 * newer file: `cancel`/`reset` count up): a late answer is dropped (code review 2026-11-15).
 */
export function useFileIntake(busy: boolean, onText: (text: string) => void) {
  const run = useRef(0)
  const [note, setNote] = useState<FileNote | null>(null)
  const [link, setLink] = useState<FileLink | null>(null)

  async function take(file: File | undefined) {
    if (!file || busy) return
    const mine = ++run.current
    if (file.size > MAX_FILE_BYTES) {
      setNote(FILE_TOO_LARGE)
      return
    }
    setNote(fileReadingNote(file.name))
    const r = await readFileText(file.name, file.type, new Uint8Array(await file.arrayBuffer()))
    if (mine !== run.current) return
    if (!r.ok) {
      setNote({ text: r.message, error: true })
      return
    }
    onText(r.text)
    setLink(null)
    const remark = readerRemark(r.message)
    setNote(fileLookingNote(file.name, remark))
    let found: LocateResult | null = null
    try {
      found = await locateFile(file.name, file.size, file.lastModified)
    } catch {
      found = null
    }
    if (mine !== run.current) return
    const located = fileLocatedNote(file.name, remark, found)
    if (located.url) setLink({ url: located.url, text: r.text })
    setNote(located.note)
  }

  return {
    note,
    link,
    take,
    /** The box moved on (it was sent): a read or lookup still running is dropped. */
    cancel: () => {
      run.current++
    },
    /** The box was emptied: also forget the note and the link. */
    reset: () => {
      run.current++
      setNote(null)
      setLink(null)
    },
    clearNote: () => setNote(null),
  }
}
