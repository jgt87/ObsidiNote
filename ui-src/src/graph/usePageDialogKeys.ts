// The page window opens as a modal, and its keys act (PageDialog.tsx). Which key means what is
// decided in pageDialogModel.ts dialogKeyAction; here the actions are carried out.
import { useEffect, type KeyboardEvent, type RefObject } from 'react'
import type { GraphIndex } from './graphIndex'
import { dialogKeyAction, nextTab, type DialogKeyAction, type DialogTab } from './pageDialogModel'
import { stepLinked } from './view'

/** Opens the dialog as a modal once it is mounted (native <dialog>: Esc closes, focus stays inside). */
export function useModalDialog(ref: RefObject<HTMLDialogElement | null>): void {
  useEffect(() => {
    const d = ref.current
    if (d && !d.open) d.showModal()
  }, []) // eslint-disable-line react-hooks/exhaustive-deps
}

export interface DialogKeysInput {
  ref: RefObject<HTMLDialogElement | null>
  index: GraphIndex
  /** The page the window was opened on: ← → step through its linked pages. */
  anchorId: string
  pageId: string
  tab: DialogTab
  setTab: (t: DialogTab) => void
  history: { go: (id: string) => void; back: () => void; forward: () => void }
}

/** The window's keydown handler: Alt+← → walk the visits, ← → on a tab switch tabs (and move focus
 *  to it), ← → elsewhere step to the previous or next linked page of the page it was opened on. */
export function useDialogKeys({ ref, index, anchorId, pageId, tab, setTab, history }: DialogKeysInput) {
  const showTab = (delta: 1 | -1) => {
    const n = nextTab(tab, delta)
    setTab(n)
    ref.current?.querySelector<HTMLElement>(`#kg-tab-${n}`)?.focus()
  }
  const step = (delta: 1 | -1) => {
    const next = stepLinked(index, anchorId, pageId, delta)
    if (next) history.go(next)
  }
  const actions: Record<DialogKeyAction, () => void> = {
    back: history.back,
    forward: history.forward,
    'tab-next': () => showTab(1),
    'tab-prev': () => showTab(-1),
    'step-next': () => step(1),
    'step-prev': () => step(-1),
  }
  return (e: KeyboardEvent<HTMLDialogElement>) => {
    const t = e.target as HTMLElement
    const a = dialogKeyAction(e, t.getAttribute('role') === 'tab', !!t.closest('input, textarea, select'))
    if (!a) return
    e.preventDefault()
    actions[a]()
  }
}
