// The fields of the Settings dialog (SettingsDialog.tsx), each on the form's state (useSettingsForm).
// A field cannot be changed while the form is off (not loaded, read only, saving).
import { unavailable } from './disabledGuard'
import type { RefObject } from 'react'
import { numberChoices } from '../model/settingsForm'
import { NUMBER_RANGES, settleNumber, type NumberKey } from '../model/vaultSettings'
import { Icon } from './icons'
import type { SettingsForm } from './useSettingsForm'

type Form = { form: SettingsForm }

export function CheckField({ form, name, label }: Form & { name: 'labelsHubsOnly' | 'askIncludeArchived' | 'graphShowArchived'; label: string }) {
  const { s, setS, off } = form
  return (
    <label className="nv__check">
      <input type="checkbox" checked={s[name]} {...unavailable(off)} onChange={(e) => setS({ ...s, [name]: e.target.checked })} />
      {label}
    </label>
  )
}

/** A whole number typed in a field; its range under it, and while it is out of range, what it becomes. */
export function NumberField({ form, name, label, unit }: Form & { name: NumberKey; label: string; unit: string }) {
  const { s, nums, setNums, off } = form
  const r = NUMBER_RANGES[name]
  const bad = form.draft.badNumbers.includes(name)
  return (
    <div className="st__num">
      <label htmlFor={`st-${name}`} className="st__num-label">
        {label}
      </label>
      <input
        id={`st-${name}`}
        className="field st__num-field"
        type="number"
        inputMode="numeric"
        min={r.min}
        max={r.max}
        step={1}
        value={nums[name]}
        {...unavailable(off)} readOnly={off}
        aria-invalid={bad || undefined}
        aria-describedby={`st-${name}-hint${bad ? ` st-${name}-error` : ''}`}
        onChange={(e) => setNums({ ...nums, [name]: e.target.value })}
        // Leaving the field never keeps a value the setting cannot take (12 becomes 10).
        onBlur={() => setNums({ ...nums, [name]: String(settleNumber(nums[name], name, s[name])) })}
      />
      <span id={`st-${name}-hint`} className="nv__muted">
        {unit} ({r.min} to {r.max})
      </span>
      {bad && (
        <span id={`st-${name}-error`} className="st__num-error" role="alert">
          <Icon name="warn" />
          {r.min} to {r.max} only; it becomes {settleNumber(nums[name], name, s[name])} when you leave the field.
        </span>
      )}
    </div>
  )
}

/** "Company addresses": one per line; the entries that are not an address are named under it. */
export function HostsField({ form, first }: Form & { first: RefObject<HTMLTextAreaElement | null> }) {
  const { hostText, setHostText, off } = form
  const bad = form.draft.badHosts
  return (
    <>
      <label className="nv__label" htmlFor="st-hosts">
        Company addresses (one per line)
      </label>
      <textarea
        id="st-hosts"
        ref={first}
        className="field nv__field nv__area"
        rows={4}
        value={hostText}
        {...unavailable(off)} readOnly={off}
        onChange={(e) => setHostText(e.target.value)}
        placeholder="intranet.example.com&#10;*.corp.example.com"
        aria-describedby="st-hosts-hint"
      />
      <p id="st-hosts-hint" className="nv__muted">
        Links to these addresses are filed under Internal links. Microsoft 365 and your company’s own tenants are found without this list.
      </p>
      {bad.length > 0 && (
        <p className="nv__error" role="alert">
          Not an address: {bad.join(', ')}
        </p>
      )}
    </>
  )
}

/** How many related pages Add links to. A short range: a list, so no other value can be entered at all. */
export function RelatedCountField({ form }: Form) {
  const { nums, setNums, off } = form
  return (
    <div className="st__num">
      <label htmlFor="st-relatedCount" className="st__num-label">
        Related pages to link a new page to
      </label>
      <select
        id="st-relatedCount"
        className="field st__select"
        value={nums.relatedCount}
        {...unavailable(off)}
        onChange={(e) => !off && setNums({ ...nums, relatedCount: e.target.value })}
      >
        {numberChoices('relatedCount').map((v) => (
          <option key={v} value={v}>
            {v}
          </option>
        ))}
      </select>
    </div>
  )
}

/** What the knowledge graph opens on: Topics or Sources. */
export function GraphViewField({ form }: Form) {
  const { s, setS, off } = form
  return (
    <div className="st__num">
      <label htmlFor="st-view" className="st__num-label">
        Opens on
      </label>
      <select id="st-view" className="field st__select" value={s.graphView} {...unavailable(off)} onChange={(e) => !off && setS({ ...s, graphView: e.target.value === 'sources' ? 'sources' : 'topics' })}>
        <option value="topics">Topics</option>
        <option value="sources">Sources</option>
      </select>
    </div>
  )
}
