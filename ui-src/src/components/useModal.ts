import { useEffect, type RefObject } from 'react'

/** A native <dialog> shown as a modal while `open` (the page behind is inert, focus is trapped).
 *  When it closes, or its component goes away while it is open (a confirm that is answered), it is
 *  closed properly and the focus goes back to what had it when the dialog opened, without scrolling.
 *  Audit 2026-11-24: the confirms were removed from the page without close(), so the focus fell
 *  back to the page instead of the button that opened them. */
export function useModal(ref: RefObject<HTMLDialogElement | null>, open = true): void {
  useEffect(() => {
    const d = ref.current
    if (!d || !open) return
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null
    if (!d.open) d.showModal()
    return () => {
      if (d.open) d.close()
      if (opener?.isConnected) opener.focus({ preventScroll: true })
    }
  }, [ref, open])
}
