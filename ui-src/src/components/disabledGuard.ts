// Controls that cannot be used right now carry aria-disabled="true", never the native `disabled`
// attribute: a native disabled control leaves the tab order, so focus falls back to the page when a
// busy button turns unavailable, and its tooltip saying why can no longer be reached (audit
// 2026-11-24, CommonShared docs/20 Button). The press is ignored here, once for the whole window:
// a click (also the one Enter or Space makes, and the implicit submit of a form) on or inside an
// element with aria-disabled="true" is stopped before React sees it. Text fields that cannot be
// changed add `readOnly`; a <select> ignores the change in its own handler (see `unavailable`).

const BLOCKED = '[aria-disabled="true"]'

/** True when the event's target is, or sits inside, an unavailable control. */
export function isBlocked(target: EventTarget | null): boolean {
  return typeof Element !== 'undefined' && target instanceof Element && target.closest(BLOCKED) !== null
}

/** Installs the guard on the window (capture phase, so it runs before React's root listeners). */
export function installDisabledGuard(win: Window): () => void {
  const stop = (e: Event) => {
    if (!isBlocked(e.target)) return
    e.preventDefault()
    e.stopImmediatePropagation()
  }
  win.addEventListener('click', stop, true)
  return () => win.removeEventListener('click', stop, true)
}

/** The attribute for a control that cannot be used: `aria-disabled` while `off`, nothing otherwise. */
export function unavailable(off: boolean): { 'aria-disabled'?: true } {
  return off ? { 'aria-disabled': true } : {}
}
