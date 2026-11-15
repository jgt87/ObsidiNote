import { useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react'
import { getSettings, saveSetting } from '../api'
import { changedKeys, NUMBER_RANGES, parseHosts, parseNumber, SETTING_DEFAULTS, settleNumber, type NumberKey, type VaultSettings } from '../model/vaultSettings'
import { WarnIcon } from './icons'
import { TagsSettings } from './TagsSettings'
import './NewVaultDialog.css'
import './SettingsDialog.css'

/** Settings (operator, 2026-11-14: "a central settings modal accessible from the menu"): everything
 *  the vault keeps in OneNote (lib/VaultSettings.psm1), so every PC that opens it uses the same.
 *  Save sends only what changed. A read-only window shows the values without Save. The theme stays
 *  per PC at the bottom of the side bar; ports and sign-in stay in config\obsidinote.local.json. */
export function SettingsDialog({ onClose, onSaved, onTagsChanged }: { onClose: () => void; onSaved?: (s: VaultSettings) => void; /** A tag was renamed or removed: the graph must read its pages again. */ onTagsChanged?: () => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  const first = useRef<HTMLTextAreaElement>(null)
  const close = useRef(onClose)
  close.current = onClose
  const [before, setBefore] = useState<VaultSettings>(SETTING_DEFAULTS)
  const [s, setS] = useState<VaultSettings>(SETTING_DEFAULTS)
  const [hostText, setHostText] = useState('')
  const [nums, setNums] = useState<Record<NumberKey, string>>({ relatedCount: '3', linkStaleDays: '90', askMaxPages: '20' })
  const [canChange, setCanChange] = useState(false)
  const [why, setWhy] = useState('')
  const [loaded, setLoaded] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    const d = ref.current
    if (d && !d.open) d.showModal()
    let live = true
    getSettings()
      .then((r) => {
        if (!live) return
        setBefore(r.settings)
        setS(r.settings)
        setHostText(r.settings.internalHosts.join('\n'))
        setNums({ relatedCount: String(r.settings.relatedCount), linkStaleDays: String(r.settings.linkStaleDays), askMaxPages: String(r.settings.askMaxPages) })
        setCanChange(r.canChange)
        setWhy(r.message)
        setLoaded(true)
        // The fields are disabled until the settings arrive, so the dialog's own focus went elsewhere.
        if (r.canChange) requestAnimationFrame(() => first.current?.focus())
      })
      .catch((e: unknown) => live && setError(e instanceof Error ? e.message : 'ObsidiNote did not answer.'))
    return () => {
      live = false
    }
  }, [])

  const hosts = parseHosts(hostText)
  const numBad = (Object.keys(NUMBER_RANGES) as NumberKey[]).filter((k) => parseNumber(nums[k], k) === null)
  const next: VaultSettings = {
    ...s,
    internalHosts: hosts.hosts,
    relatedCount: parseNumber(nums.relatedCount, 'relatedCount') ?? s.relatedCount,
    linkStaleDays: parseNumber(nums.linkStaleDays, 'linkStaleDays') ?? s.linkStaleDays,
    askMaxPages: parseNumber(nums.askMaxPages, 'askMaxPages') ?? s.askMaxPages,
  }
  const changed = changedKeys(before, next)
  const invalid = hosts.bad.length > 0 || numBad.length > 0
  const off = !loaded || !canChange || busy

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    if (off || invalid || !changed.length) return
    setBusy(true)
    setError('')
    try {
      let saved = before
      for (const k of changed) saved = (await saveSetting(k, next[k] as never)).settings
      onSaved?.(saved)
      close.current()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'ObsidiNote did not answer.')
    } finally {
      setBusy(false)
    }
  }

  const check = (key: 'labelsHubsOnly' | 'askIncludeArchived' | 'graphShowArchived', label: string) => (
    <label className="nv__check">
      <input type="checkbox" checked={s[key]} disabled={off} onChange={(e) => setS({ ...s, [key]: e.target.checked })} />
      {label}
    </label>
  )
  const number = (key: NumberKey, label: string, unit: string) => {
    const r = NUMBER_RANGES[key]
    const bad = numBad.includes(key)
    return (
      <div className="st__num">
        <label htmlFor={`st-${key}`} className="st__num-label">
          {label}
        </label>
        <input
          id={`st-${key}`}
          className="field st__num-field"
          type="number"
          inputMode="numeric"
          min={r.min}
          max={r.max}
          step={1}
          value={nums[key]}
          disabled={off}
          aria-invalid={bad || undefined}
          aria-describedby={`st-${key}-hint${bad ? ` st-${key}-error` : ''}`}
          onChange={(e) => setNums({ ...nums, [key]: e.target.value })}
          // Leaving the field never keeps a value the setting cannot take (12 becomes 10).
          onBlur={() => setNums({ ...nums, [key]: String(settleNumber(nums[key], key, s[key])) })}
        />
        <span id={`st-${key}-hint`} className="nv__muted">
          {unit} ({r.min} to {r.max})
        </span>
        {bad && (
          <span id={`st-${key}-error`} className="st__num-error" role="alert">
            <WarnIcon />
            {r.min} to {r.max} only; it becomes {settleNumber(nums[key], key, s[key])} when you leave the field.
          </span>
        )}
      </div>
    )
  }

  return (
    <dialog ref={ref} className="nv st" aria-labelledby="st-title" aria-describedby="st-desc" onCancel={(e) => { e.preventDefault(); if (!busy) close.current() }}>
      <form onSubmit={onSubmit}>
        <div className="st__head">
          <h2 id="st-title" className="nv__title">
            Settings
          </h2>
          <p id="st-desc" className="nv__muted">
            Kept in the vault in OneNote, so every PC that opens it uses the same.{loaded && !canChange ? ` ${why || 'They cannot be changed from this window for now.'}` : ''}
          </p>
        </div>
        <div className="st__body">
          <Group title="Links">
            <label className="nv__label" htmlFor="st-hosts">
              Company addresses (one per line)
            </label>
            <textarea
              id="st-hosts"
              ref={first}
              className="field nv__field nv__area"
              rows={4}
              value={hostText}
              disabled={off}
              onChange={(e) => setHostText(e.target.value)}
              placeholder="intranet.example.com&#10;*.corp.example.com"
              aria-describedby="st-hosts-hint"
            />
            <p id="st-hosts-hint" className="nv__muted">
              Links to these addresses are filed under Internal links. Microsoft 365 and your company's own tenants are found without this list.
            </p>
            {hosts.bad.length > 0 && (
              <p className="nv__error" role="alert">
                Not an address: {hosts.bad.join(', ')}
              </p>
            )}
            {number('linkStaleDays', 'Offer Update for a link page after', 'days')}
          </Group>
          <Group title="Add">
            {/* A short range: a list, so no other value can be entered at all. */}
            <div className="st__num">
              <label htmlFor="st-relatedCount" className="st__num-label">
                Related pages to link a new page to
              </label>
              <select
                id="st-relatedCount"
                className="field st__select"
                value={nums.relatedCount}
                disabled={off}
                onChange={(e) => setNums({ ...nums, relatedCount: e.target.value })}
              >
                {Array.from({ length: NUMBER_RANGES.relatedCount.max - NUMBER_RANGES.relatedCount.min + 1 }, (_, i) => String(NUMBER_RANGES.relatedCount.min + i)).map((v) => (
                  <option key={v} value={v}>
                    {v}
                  </option>
                ))}
              </select>
            </div>
          </Group>
          <Group title="Ask">
            {number('askMaxPages', 'Pages Ask may read for one answer', 'pages')}
            <p className="nv__muted">More pages means each page is read more briefly: at 20 about 3,600 characters each, at 50 about 1,500 (its summary and first paragraphs).</p>
            {check('askIncludeArchived', 'Include archived pages')}
          </Group>
          <Group title="Knowledge graph">
            <div className="st__num">
              <label htmlFor="st-view" className="st__num-label">
                Opens on
              </label>
              <select id="st-view" className="field st__select" value={s.graphView} disabled={off} onChange={(e) => setS({ ...s, graphView: e.target.value === 'sources' ? 'sources' : 'topics' })}>
                <option value="topics">Topics</option>
                <option value="sources">Sources</option>
              </select>
            </div>
            {check('labelsHubsOnly', 'Labels: hubs only (topic names; a page shows its name when pointed at)')}
            {check('graphShowArchived', 'Show archived pages')}
          </Group>
          <Group title="Tags">
            <TagsSettings canChange={canChange} onChanged={() => onTagsChanged?.()} />
          </Group>
          {error && (
            <p className="nv__error" role="alert">
              {error}
            </p>
          )}
        </div>
        <div className="nv__actions">
          <button type="button" className="btn btn--ghost" onClick={() => close.current()} disabled={busy}>
            {canChange ? 'Cancel' : 'Close'}
          </button>
          {canChange && (
            <button type="submit" className="btn btn--primary" disabled={off || invalid || !changed.length} aria-busy={busy}>
              {busy ? 'Saving…' : 'Save'}
            </button>
          )}
        </div>
      </form>
    </dialog>
  )
}

function Group({ title, children }: { title: string; children: ReactNode }) {
  return (
    <fieldset className="st__group">
      <legend className="st__legend">{title}</legend>
      {children}
    </fieldset>
  )
}
