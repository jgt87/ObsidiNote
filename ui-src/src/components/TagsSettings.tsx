// Settings, "Tags": the vault's hand-set tags with their page counts; rename one (renaming to a tag
// that exists merges the two) or take one off every page. Each change is written at once (it is
// not part of the form's Save) and asks first when it removes.

import { useCallback, useEffect, useState } from 'react'
import { fetchGraph, renameTag } from '../graph/graphApi'
import { normalizeTag, tagCounts, type TagCount } from '../graph/tags'
import { plural } from '../model/format'

export function TagsSettings({ canChange, onChanged }: { canChange: boolean; /** The graph must read its pages again. */ onChanged: () => void }) {
  const [tags, setTags] = useState<TagCount[] | null>(null)
  const [vault, setVault] = useState('')
  const [error, setError] = useState('')
  const [edit, setEdit] = useState<{ name: string; mode: 'rename' | 'remove'; to: string } | null>(null)
  const [busy, setBusy] = useState(false)

  const load = useCallback((signal?: AbortSignal) => {
    return fetchGraph({}, signal).then(
      (m) => {
        setTags(tagCounts(m.pages))
        setVault(m.source.id)
        setError('')
      },
      (e: unknown) => {
        if (signal?.aborted) return
        setTags([])
        setError(e instanceof Error && e.message ? e.message : 'The tags could not be read.')
      },
    )
  }, [])
  useEffect(() => {
    const ctl = new AbortController()
    void load(ctl.signal)
    return () => ctl.abort()
  }, [load])

  const apply = async (from: string, to: string) => {
    setBusy(true)
    setError('')
    try {
      await renameTag({ from, to, vault })
      setEdit(null)
      await load()
      onChanged()
    } catch (e) {
      setError(e instanceof Error && e.message ? e.message : 'The tag could not be changed.')
    } finally {
      setBusy(false)
    }
  }
  const rename = () => {
    if (!edit) return
    const r = normalizeTag(edit.to)
    if (!r.ok) return setError(r.error)
    if (r.tag === edit.name) return setEdit(null)
    void apply(edit.name, r.tag)
  }

  if (tags === null) return <p className="nv__muted" role="status">Reading the tags...</p>
  return (
    <>
      {!tags.length && !error && <p className="nv__muted">No tags yet. Add one to a page in its window on the knowledge graph, or to several pages at once in the List.</p>}
      {tags.length > 0 && (
        <ul className="st__tags">
          {tags.map((t) => (
            <li key={t.name} className="st__tag">
              {edit?.name === t.name && edit.mode === 'rename' ? (
                <>
                  <input
                    className="field st__tag-input"
                    aria-label={`New name for the tag ${t.name}`}
                    value={edit.to}
                    autoFocus
                    disabled={busy}
                    onChange={(e) => setEdit({ ...edit, to: e.target.value })}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.preventDefault() // never the Settings form's Save
                        rename()
                      } else if (e.key === 'Escape') {
                        e.stopPropagation()
                        setEdit(null)
                      }
                    }}
                  />
                  <button type="button" className="btn btn--sm" disabled={busy} aria-busy={busy} onClick={rename}>
                    Rename
                  </button>
                  <button type="button" className="btn btn--sm btn--ghost" disabled={busy} onClick={() => setEdit(null)}>
                    Cancel
                  </button>
                </>
              ) : edit?.name === t.name && edit.mode === 'remove' ? (
                <>
                  <span className="st__tag-name">
                    Take <b>{t.name}</b> off {plural(t.count, 'page')}? The pages stay.
                  </span>
                  <button type="button" className="btn btn--sm" disabled={busy} onClick={() => setEdit(null)}>
                    Keep
                  </button>
                  <button type="button" className="btn btn--sm btn--danger" disabled={busy} aria-busy={busy} onClick={() => void apply(t.name, '')}>
                    Remove tag
                  </button>
                </>
              ) : (
                <>
                  <span className="st__tag-name">{t.name}</span>
                  <span className="nv__muted num">{plural(t.count, 'page')}</span>
                  {canChange && (
                    <>
                      <button type="button" className="btn btn--sm btn--ghost" aria-label={`Rename the tag ${t.name}`} onClick={() => { setError(''); setEdit({ name: t.name, mode: 'rename', to: t.name }) }}>
                        Rename
                      </button>
                      <button type="button" className="btn btn--sm btn--ghost" aria-label={`Remove the tag ${t.name} from every page`} onClick={() => { setError(''); setEdit({ name: t.name, mode: 'remove', to: '' }) }}>
                        Remove
                      </button>
                    </>
                  )}
                </>
              )}
            </li>
          ))}
        </ul>
      )}
      {tags.length > 0 && canChange && <p className="nv__muted">Renaming a tag to one that exists merges the two.</p>}
      {error && (
        <p className="nv__error" role="alert">
          {error}
        </p>
      )}
    </>
  )
}
