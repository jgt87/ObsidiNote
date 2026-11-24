// The page window's Edit form: title, type (another section moves the page), topics, aliases, summary, a link
// page's address, and its links to other pages. Saving sends only what changed (editModel.ts); the
// server writes only ObsidiNote's own parts of the page, never your own text in OneNote.

import { useEffect, useId, useMemo, useState, type FormEvent } from 'react'
import { unavailable } from '../components/disabledGuard'
import { Icon } from '../components/icons'
import { editProblemAt, editRequest, formFor, linkChoices, moveNote, typeChoices, type EditField, type EditForm, type PageEditRequest } from './editModel'
import type { GraphIndex } from './graphIndex'
import type { GraphPage, Strength } from './model'
import { ORIGINS, TYPED_LABEL } from '../model/origins'
import './PageEditForm.css'

interface Props {
  index: GraphIndex
  page: GraphPage
  /** Saves the request; its rejection's message shows in the form. */
  onSave: (req: PageEditRequest) => Promise<unknown>
  onCancel: () => void
}

const STRENGTHS: { value: Strength; label: string }[] = [
  { value: 3, label: 'Strong' },
  { value: 2, label: 'Medium' },
  { value: 1, label: 'Weak' },
]

export function PageEditForm({ index, page, onSave, onCancel }: Props) {
  const id = useId()
  const before = useMemo(() => formFor(index, page), [index, page])
  const [form, setForm] = useState<EditForm>(before)
  const [busy, setBusy] = useState(false)
  const { error, errId, show, invalid } = useFieldError(id)
  const [pick, setPick] = useState('')
  const types = typeChoices(index.model, page)
  const choices = linkChoices(index, page, form.links)
  const isLink = !!page.url
  // While saving, the fields are read only: a change is ignored (the select has no readOnly).
  const set = (patch: Partial<EditForm>) => {
    if (!busy) setForm((f) => ({ ...f, ...patch }))
  }
  const title = (target: string) => index.pageById.get(target)?.title ?? target

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    if (busy) return
    const problem = editProblemAt(form, isLink)
    if (problem) return show(problem.text, problem.field)
    const req = editRequest(page, index.model.source.id, before, form)
    if (!req) return onCancel()
    setBusy(true)
    show('', null)
    try {
      await onSave(req)
    } catch (err) {
      show(err instanceof Error && err.message ? err.message : 'The page could not be saved.', null)
      setBusy(false)
    }
  }

  const addLink = () => {
    if (!pick || busy) return
    set({ links: [...form.links, { target: pick, strength: 2, why: '' }] })
    setPick('')
  }

  return (
    <form className="kg-edit" onSubmit={submit} aria-busy={busy}>
      <div className="kg-edit__grid">
        <label htmlFor={`${id}-title`}>Title</label>
        {/* No maxLength: it cuts a longer paste off without a word; the check on Save says so instead. */}
        <input id={`${id}-title`} className="field" value={form.title} onChange={(e) => set({ title: e.target.value })} {...unavailable(busy)} readOnly={busy} required {...invalid({ name: 'title' })} />

        {types.length > 1 && (
          <>
            <label htmlFor={`${id}-type`}>Type</label>
            <div>
              <select id={`${id}-type`} className="field" value={form.type} onChange={(e) => set({ type: e.target.value })} {...unavailable(busy)}>
                {types.map((t) => (
                  <option key={t} value={t}>
                    {t}
                  </option>
                ))}
              </select>
              {moveNote(index.model, page, form.type) && <p className="kg-edit__hint">{moveNote(index.model, page, form.type)}</p>}
            </div>
          </>
        )}

        {isLink ? (
          <>
            <label htmlFor={`${id}-url`}>Address</label>
            <div>
              <input id={`${id}-url`} className="field" type="url" value={form.url} onChange={(e) => set({ url: e.target.value })} {...unavailable(busy)} readOnly={busy} {...invalid({ name: 'url' })} />
              <p className="kg-edit__hint">After a new address, use Update on the page to read it again.</p>
            </div>
          </>
        ) : (
          <>
            <label htmlFor={`${id}-origin`}>From</label>
            <div>
              <select id={`${id}-origin`} className="field" value={form.origin} onChange={(e) => set({ origin: e.target.value })} {...unavailable(busy)}>
                <option value="">{TYPED_LABEL}</option>
                {ORIGINS.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.label}
                  </option>
                ))}
              </select>
              <p className="kg-edit__hint">Where this came from: its place in the Sources view of the map.</p>
            </div>
          </>
        )}

        <label htmlFor={`${id}-topics`}>Topics</label>
        <div>
          <textarea id={`${id}-topics`} className="field kg-edit__area" rows={2} value={form.topics} onChange={(e) => set({ topics: e.target.value })} {...unavailable(busy)} readOnly={busy} />
          <p className="kg-edit__hint">One topic path per line, e.g. Security / Networking. The first is where the page sits.</p>
        </div>

        <label htmlFor={`${id}-aliases`}>Aliases</label>
        <input id={`${id}-aliases`} className="field" value={form.aliases} placeholder="Other names, separated by commas" onChange={(e) => set({ aliases: e.target.value })} {...unavailable(busy)} readOnly={busy} />

        <label htmlFor={`${id}-summary`}>Summary</label>
        <textarea id={`${id}-summary`} className="field kg-edit__area" rows={3} value={form.summary} onChange={(e) => set({ summary: e.target.value })} {...unavailable(busy)} readOnly={busy} {...invalid({ name: 'summary' })} />
      </div>

      <fieldset className="kg-edit__links" {...unavailable(busy)}>
        <legend className="kg-lbl">Links to other pages</legend>
        {form.links.length === 0 && <p className="kg-edit__hint">No links.</p>}
        <ul className="kg-edit__list">
          {form.links.map((l, i) => (
            <li key={l.target} className="kg-edit__link">
              <span className="kg-edit__target" title={title(l.target)}>
                {title(l.target)}
              </span>
              <select
                className="field"
                aria-label={`Strength of the link to ${title(l.target)}`}
                value={l.strength}
                onChange={(e) => set({ links: form.links.map((x, j) => (j === i ? { ...x, strength: Number(e.target.value) as Strength } : x)) })}
              >
                {STRENGTHS.map((s) => (
                  <option key={s.value} value={s.value}>
                    {s.label}
                  </option>
                ))}
              </select>
              {/* A real label, visually hidden: the placeholder "Why" is what shows (operator, 2026-11-24). */}
              <label className="visually-hidden" htmlFor={`${id}-why-${i}`}>
                Why it links to {title(l.target)}
              </label>
              <input
                className="field"
                id={`${id}-why-${i}`}
                placeholder="Why"
                value={l.why}
                readOnly={busy}
                onChange={(e) => set({ links: form.links.map((x, j) => (j === i ? { ...x, why: e.target.value } : x)) })}
                {...invalid({ name: 'why', link: i })}
              />
              {/* Full-size buttons: they share a row with 32px fields (one height per row). */}
              <button type="button" className="btn" onClick={() => set({ links: form.links.filter((_, j) => j !== i) })} aria-label={`Remove the link to ${title(l.target)}`}>
                Remove
              </button>
            </li>
          ))}
        </ul>
        {choices.length > 0 && (
          <div className="kg-edit__add">
            <select className="field" aria-label="Page to link to" value={pick} onChange={(e) => !busy && setPick(e.target.value)}>
              <option value="">Link to another page…</option>
              {choices.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.title}
                </option>
              ))}
            </select>
            <button type="button" className="btn" onClick={addLink} {...unavailable(!pick)}>
              Add link
            </button>
          </div>
        )}
      </fieldset>

      {/* Mounted empty and kept, so a message put in it is announced. */}
      <div id={errId} className="live" role="alert">
        {error && (
          <p className="kg-edit__error">
            <Icon name="warn" />
            <span>{error.text}</span>
          </p>
        )}
      </div>
      <div className="kg-edit__actions">
        <span className="kg-edit__hint">Your own text on the page is never changed.</span>
        <button type="button" className="btn" onClick={onCancel} {...unavailable(busy)}>
          Cancel
        </button>
        <button type="submit" className="btn btn--primary" {...unavailable(busy)}>
          {busy ? 'Saving…' : 'Save'}
        </button>
      </div>
    </form>
  )
}

/** What is wrong with the form and the field it is about (none for a refusal of the server). The
 *  field gets aria-invalid and points at the message, and takes the focus on every Save that finds
 *  it wrong (audit 2026-11-24: the form showed one message and marked no field). '' clears it. */
function useFieldError(id: string) {
  // `n` counts the tries, so a second Save with the same problem puts the focus back on its field.
  const [error, setError] = useState<{ text: string; field: EditField | null; n: number } | null>(null)
  const errId = `${id}-error`
  const fieldId = (f: EditField) => (f.name === 'why' ? `${id}-why-${f.link}` : `${id}-${f.name}`)
  useEffect(() => {
    if (error?.field) document.getElementById(fieldId(error.field))?.focus()
  }, [error]) // eslint-disable-line react-hooks/exhaustive-deps
  return {
    error,
    errId,
    show: (text: string, field: EditField | null) => setError((e) => (text ? { text, field, n: (e?.n ?? 0) + 1 } : null)),
    invalid: (f: EditField) => (error?.field && fieldId(error.field) === fieldId(f) ? { 'aria-invalid': true, 'aria-describedby': errId } : {}),
  }
}
