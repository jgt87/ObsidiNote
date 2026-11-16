import { useState, type DragEvent as ReactDragEvent } from 'react'
import { dragIsTakeable, droppedLink } from '../add/fileNotes'

/**
 * The Add box as a drop target: a file let go on it is read (`onFile`), a link dragged from a
 * browser tab (a OneDrive or SharePoint file, a web page) is taken like a pasted link (`onLink`).
 * `dragging` while something it can take is over it.
 */
export function useBoxDrop(onFile: (file: File) => void, onLink: (link: string) => void) {
  const [dragging, setDragging] = useState(false)

  function onDragOver(e: ReactDragEvent<HTMLElement>) {
    if (!dragIsTakeable([...e.dataTransfer.types])) return
    e.preventDefault()
    e.dataTransfer.dropEffect = 'copy'
    setDragging(true)
  }

  function onDragLeave(e: ReactDragEvent<HTMLElement>) {
    if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDragging(false)
  }

  function onDrop(e: ReactDragEvent<HTMLElement>) {
    setDragging(false)
    if (e.dataTransfer.files.length) {
      e.preventDefault()
      onFile(e.dataTransfer.files[0])
      return
    }
    const link = droppedLink(e.dataTransfer.getData('text/uri-list') || '')
    if (link) {
      e.preventDefault()
      onLink(link)
    }
  }

  return { dragging, onDragOver, onDragLeave, onDrop }
}
