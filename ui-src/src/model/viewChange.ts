// Whether the window is still on the view it opened with. The box takes the focus only then; once
// the person chose another view, the view change places the focus (App.tsx useViewFocus). Session
// state in memory only.

let changed = false

/** Called by the app shell as soon as it renders another view (before the new view's effects run). */
export function markViewChanged(): void {
  changed = true
}

/** True until the first change of view. */
export function onFirstView(): boolean {
  return !changed
}
