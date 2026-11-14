// The page window's Edit form: title, type (within its section), topics, aliases, summary, a link
// page's address, and its links to other pages. Saving sends only what changed (editModel.ts); the
// server writes only ObsidiNote's own parts of the page, never your own text in OneNote.

import { useId, useMemo, useState, type FormEvent } from 'react'
import { editProblem, editRequest, formFor, linkChoices, typeChoices, type EditForm, type PageEditRequest } from './editModel'
import type { GraphIndex } from './graphIndex'
import type { GraphPage, Strength } from './model'
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
  const [error, setError] = useState('')
  const [pick, setPick] = useState('')
  const types = typeChoices(index.model, page)
  const choices = linkChoices(index, page, form.links)
  const isLink = !!page.url
  const set = (patch: Partial<EditForm>) => setForm((f) => ({ ...f, ...patch }))
  const title = (target: string) => index.pageById.get(target)?.title ?? target

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    const problem = editProblem(form, isLink)
    if (problem) return setError(problem)
    const req = editRequest(page, index.model.source.id, before, form)
    if (!req) return onCancel()
    setBusy(true)
    setError('')
    try {
      await onSave(req)
    } catch (err) {
      setError(err instanceof Error && err.message ? err.message : 'The page could not be saved.')
      setBusy(false)
    }
  }

  const addLink = () => {
    if (!pick) return
    set({ links: [...form.links, { target: pick, strength: 2, why: '' }] })
    setPick('')
  }

  return (
    <form className="kg-edit" onSubmit={submit} aria-busy={busy}>
      <div className="kg-edit__grid">
        <label htmlFor={`${id}-title`}>Title</label>
        <input id={`${id}-title`} className="field" value={form.title} maxLength={200} onChange={(e) => set({ title: e.target.value })} disabled={busy} required />

        {types.length > 1 && (
          <>
            <label htmlFor={`${id}-type`}>Type</label>
            <select id={`${id}-type`} className="field" value={form.type} onChange={(e) => set({ type: e.target.value })} disabled={busy}>
              {types.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </>
        )}

        {isLink && (
          <>
            <label htmlFor={`${id}-url`}>Address</label>
            <div>
              <input id={`${id}-url`} className="field" type="url" value={form.url} onChange={(e) => set({ url: e.target.value })} disabled={busy} />
              <p className="kg-edit__hint">After a new address, use Update on the page to read it again.</p>
            </div>
          </>
        )}

        <label htmlFor={`${id}-topics`}>Topics</label>
        <div>
          <textarea id={`${id}-topics`} className="field kg-edit__area" rows={2} value={form.topics} onChange={(e) => set({ topics: e.target.value })} disabled={busy} />
          <p className="kg-edit__hint">One topic path per line, e.g. Security / Networking. The first is where the page sits.</p>
        </div>

        <label htmlFor={`${id}-aliases`}>Aliases</label>
        <input id={`${id}-aliases`} className="field" value={form.aliases} placeholder="Other names, separated by commas" onChange={(e) => set({ aliases: e.target.value })} disabled={busy} />

        <label htmlFor={`${id}-summary`}>Summary</label>
        <textarea id={`${id}-summary`} className="field kg-edit__area" rows={3} maxLength={2000} value={form.summary} onChange={(e) => set({ summary: e.target.value })} disabled={busy} />
      </div>

      <fieldset className="kg-edit__links" disabled={busy}>
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
              <input
                className="field"
                aria-label={`Why it links to ${title(l.target)}`}
                placeholder="Why"
                maxLength={300}
                value={l.why}
                onChange={(e) => set({ links: form.links.map((x, j) => (j === i ? { ...x, why: e.target.value } : x)) })}
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
            <select className="field" aria-label="Page to link to" value={pick} onChange={(e) => setPick(e.target.value)}>
              <option value="">Link to another page…</option>
              {choices.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.title}
                </option>
              ))}
            </select>
            <button type="button" className="btn" onClick={addLink} disabled={!pick}>
              Add link
            </button>
          </div>
        )}
      </fieldset>

      {error && (
        <p className="kg-edit__error" role="alert">
          {error}
        </p>
      )}
      <div className="kg-edit__actions">
        <span className="kg-edit__hint">Your own text on the page is never changed.</span>
        <button type="button" className="btn" onClick={onCancel} disabled={busy}>
          Cancel
        </button>
        <button type="submit" className="btn btn--primary" disabled={busy}>
          {busy ? 'Saving…' : 'Save'}
        </button>
      </div>
    </form>
  )
}
