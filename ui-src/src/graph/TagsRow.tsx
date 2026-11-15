// Tags of one page, or of a selection: chips with a remove button, and a field that adds one
// (Enter or comma adds; existing tags are offered while typing; a duplicate is refused quietly).
// Tags are set by hand only. Without `onChange` (a read-only source) the chips are shown and
// nothing can be changed.

import { useId, useState } from 'react'
import { normalizeTag, suggestTags, type TagCount } from './tags'

interface Props {
  /** The tags to show as chips (a page's own; for a selection: none). */
  tags: string[]
  /** Every tag in use, for the suggestions. */
  all: TagCount[]
  /** Adds and removes; resolves when the map shows it. A rejection's message is shown. */
  onChange?: (add: string[], remove: string[]) => Promise<unknown>
  /** What the field is for, e.g. "Add a tag to this page". */
  label: string
  /** Pressing a chip's name (the page window: show every page with that tag). */
  onPick?: (tag: string) => void
}

export function TagsRow({ tags, all, onChange, label, onPick }: Props) {
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const listId = useId()
  const errId = useId()

  const run = async (add: string[], remove: string[]) => {
    if (!onChange || busy) return
    setBusy(true)
    setError('')
    try {
      await onChange(add, remove)
      if (add.length) setText('')
    } catch (e) {
      setError(e instanceof Error && e.message ? e.message : 'The tag could not be saved.')
    } finally {
      setBusy(false)
    }
  }
  const add = () => {
    const r = normalizeTag(text)
    if (!r.ok) return setError(r.error)
    if (tags.includes(r.tag)) {
      setText('')
      return setError('')
    }
    void run([r.tag], [])
  }

  return (
    <div className="kg-tags">
      {tags.length > 0 && (
        <ul className="kg-tags__list" aria-label="Tags">
          {tags.map((t) => (
            <li key={t} className="kg-tagchip">
              {onPick ? (
                <button type="button" className="kg-tagchip__name" onClick={() => onPick(t)} title={`Show every page tagged "${t}"`}>
                  {t}
                </button>
              ) : (
                <span className="kg-tagchip__name">{t}</span>
              )}
              {onChange && (
                <button type="button" className="kg-tagchip__x" aria-label={`Remove tag ${t}`} title={`Remove tag ${t}`} disabled={busy} onClick={() => void run([], [t])}>
                  <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden="true">
                    <path d="M4.5 4.5l7 7M11.5 4.5l-7 7" />
                  </svg>
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
      {!tags.length && !onChange && <span className="kg-row__sub">No tags.</span>}
      {onChange && (
        <span className="kg-tags__add">
          <input
            className="field kg-tags__input"
            type="text"
            value={text}
            placeholder="Add a tag"
            aria-label={label}
            aria-invalid={error ? true : undefined}
            aria-describedby={error ? errId : undefined}
            list={listId}
            maxLength={60}
            disabled={busy}
            onChange={(e) => {
              setText(e.target.value)
              setError('')
            }}
            onKeyDown={(e) => {
              if (e.nativeEvent.isComposing) return
              if (e.key === 'Enter' || e.key === ',') {
                e.preventDefault()
                e.stopPropagation()
                add()
              } else if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') e.stopPropagation() // the page window steps pages with these
            }}
          />
          <datalist id={listId}>
            {suggestTags(all, text, tags).map((t) => (
              <option key={t} value={t} />
            ))}
          </datalist>
          <button type="button" className="btn btn--sm" disabled={busy || !text.trim()} aria-busy={busy} onClick={add}>
            Add
          </button>
        </span>
      )}
      {error && (
        <span id={errId} className="kg-tags__error" role="alert">
          {error}
        </span>
      )}
    </div>
  )
}
