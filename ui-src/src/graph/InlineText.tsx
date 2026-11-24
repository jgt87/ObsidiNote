// A line of the page window that is changed where it stands (design round 2, 2026-11-15: the
// title and the summary no longer need the Edit form; operator, 2026-11-15: "How can I edit a card
// like this one, for example if I'd like to adjust the title"). The text is a button; pressing it
// turns it into a field with Save and Cancel. Enter saves (Shift+Enter is a new line in the
// summary), Esc puts the old text back and never closes the page window.

import { useEffect, useId, useRef, useState, type KeyboardEvent } from 'react'
import { unavailable } from '../components/disabledGuard'
import { Icon } from '../components/icons'

interface Props {
  value: string
  /** What it is, for the names of the controls: "title", "summary". */
  name: string
  /** Shown while there is no text. */
  empty?: string
  multiline?: boolean
  /** What is wrong with the new text ('' = nothing); the server checks again. */
  problem: (next: string) => string
  /** Saves the new text; a rejection's message shows under the field and the field stays. */
  onSave: (next: string) => Promise<unknown>
}

export function InlineText({ value, name, empty = '', multiline = false, problem, onSave }: Props) {
  // null = showing the text; a string = the field's content.
  const [draft, setDraft] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const errId = `${useId()}-error`
  const view = useRef<HTMLButtonElement>(null)
  const field = useRef<HTMLInputElement & HTMLTextAreaElement>(null)
  const open = draft !== null
  useEffect(() => {
    if (!open) return
    field.current?.focus()
    field.current?.select()
  }, [open])

  const stop = () => {
    setDraft(null)
    setError('')
    requestAnimationFrame(() => view.current?.focus())
  }
  const save = async () => {
    const next = (draft ?? '').trim()
    if (next === value.trim()) return stop()
    const wrong = problem(next)
    if (wrong) return setError(wrong)
    setBusy(true)
    setError('')
    try {
      await onSave(next)
      stop()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'ObsidiNote did not answer.')
    } finally {
      setBusy(false)
    }
  }
  const onKeyDown = (e: KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    if (e.key === 'Escape') {
      // Before the dialog sees it: Esc ends the change, not the page window.
      e.preventDefault()
      e.stopPropagation()
      if (!busy) stop()
    } else if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
      e.preventDefault()
      if (!busy) void save()
    }
  }

  if (!open) {
    return (
      <button ref={view} type="button" className="kg-inline" data-empty={value ? undefined : true} onClick={() => setDraft(value)} title={`Change the ${name}`}>
        <span className="kg-inline__text">{value || empty}</span>
        <Icon name="pencil" />
        <span className="kg-sr">Change the {name}</span>
      </button>
    )
  }
  const Field = multiline ? 'textarea' : 'input'
  return (
    <span className="kg-inline-edit">
      <Field
        ref={field}
        className="field kg-inline-edit__field"
        aria-label={name[0].toUpperCase() + name.slice(1)}
        aria-invalid={error ? true : undefined}
        aria-describedby={error ? errId : undefined}
        value={draft ?? ''}
        rows={multiline ? 4 : undefined}
        readOnly={busy}
        onChange={(e) => setDraft(e.target.value)}
        onKeyDown={onKeyDown}
      />
      <span className="kg-inline-edit__row">
        <button type="button" className="btn btn--sm" onClick={() => void save()} {...unavailable(busy)}>
          {busy ? 'Saving…' : 'Save'}
        </button>
        <button type="button" className="btn btn--sm btn--ghost" onClick={stop} {...unavailable(busy)}>
          Cancel
        </button>
        {/* Mounted empty with the field and kept, so a problem is announced; the field points at it. */}
        <span id={errId} role="alert" className="kg-inline-edit__error live">
          {error}
        </span>
      </span>
    </span>
  )
}
