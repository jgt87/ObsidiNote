import { BusyLabel } from './BusyLabel'
import { unavailable } from './disabledGuard'
import { useRef, type ReactNode } from 'react'
import { bareVersion, readOnlyNote } from '../model/settingsForm'
import type { VaultSettings } from '../model/vaultSettings'
import { CheckField, GraphViewField, HostsField, NumberField, RelatedCountField } from './SettingsFields'
import { TagsSettings } from './TagsSettings'
import { useSettingsForm, type SettingsForm } from './useSettingsForm'
import './NewVaultDialog.css'
import './SettingsDialog.css'

/** Settings (D-010): everything
 *  the vault keeps in OneNote (lib/VaultSettings.psm1), so every PC that opens it uses the same.
 *  Save sends only what changed. A read-only window shows the values without Save. The theme stays
 *  per PC at the bottom of the side bar; ports and sign-in stay in config\obsidinote.local.json. */
export function SettingsDialog({ onClose, onSaved, onTagsChanged, version = '' }: { onClose: () => void; onSaved?: (s: VaultSettings) => void; /** A tag was renamed or removed: the graph must read its pages again. */ onTagsChanged?: () => void; /** The running app's version (GET /api/status), shown top right; '' shows none. */ version?: string }) {
  const ref = useRef<HTMLDialogElement>(null)
  const first = useRef<HTMLTextAreaElement>(null)
  const form = useSettingsForm({ ref, first }, onClose, onSaved)
  const { close, busy, error } = form

  return (
    <dialog ref={ref} className="nv st" aria-labelledby="st-title" aria-describedby="st-desc" onCancel={(e) => { e.preventDefault(); if (!busy) close.current() }}>
      <form onSubmit={form.onSubmit}>
        <SettingsHead version={version} note={readOnlyNote(form.loaded, form.canChange, form.why)} />
        <div className="st__body">
          <Group title="Links">
            <HostsField form={form} first={first} />
            <NumberField form={form} name="linkStaleDays" label="Offer Update for a link page after" unit="days" />
          </Group>
          <Group title="Add">
            <RelatedCountField form={form} />
          </Group>
          <Group title="Ask">
            <NumberField form={form} name="askMaxPages" label="Pages Ask may read for one answer" unit="pages" />
            <p className="nv__muted">More pages means each page is read more briefly: at 20 about 3,600 characters each, at 50 about 1,500 (its summary and first paragraphs).</p>
            <CheckField form={form} name="askIncludeArchived" label="Include archived pages" />
          </Group>
          <Group title="Knowledge graph">
            <GraphViewField form={form} />
            <CheckField form={form} name="labelsHubsOnly" label="Labels: hubs only (topic names; a page shows its name when pointed at)" />
            <CheckField form={form} name="graphShowArchived" label="Show archived pages" />
          </Group>
          <Group title="Tags">
            <TagsSettings canChange={form.canChange} onChanged={() => onTagsChanged?.()} />
          </Group>
          {error && (
            <p className="nv__error" role="alert">
              {error}
            </p>
          )}
        </div>
        <SettingsActions form={form} />
      </form>
    </dialog>
  )
}

/** The title with the app's version beside it, and where the settings are kept (plus why they cannot
 *  be changed here, when that is so). */
function SettingsHead({ version, note }: { version: string; note: string }) {
  return (
    <div className="st__head">
      {/* design: D-047: the app's version in the top right, beside the title. */}
      <div className="st__title-row">
        <h2 id="st-title" className="nv__title">
          Settings
        </h2>
        {version && (
          <span className="st__version" title={`ObsidiNote version ${bareVersion(version)}`}>
            v{bareVersion(version)}
          </span>
        )}
      </div>
      <p id="st-desc" className="nv__muted">
        Kept in the vault in OneNote, so every PC that opens it uses the same.{note}
      </p>
    </div>
  )
}

/** Cancel and Save; a window that cannot change the settings only closes. Save is on once something
 *  changed and every field is valid. */
function SettingsActions({ form }: { form: SettingsForm }) {
  const { canChange, busy, off, changed, close } = form
  return (
    <div className="nv__actions">
      <button type="button" className="btn btn--ghost" onClick={() => close.current()} {...unavailable(busy)}>
        {canChange ? 'Cancel' : 'Close'}
      </button>
      {canChange && (
        <button type="submit" className="btn btn--primary" {...unavailable(off || form.draft.invalid || !changed.length)} aria-busy={busy}>
          <BusyLabel label="Save" busyText="Saving…" />
        </button>
      )}
    </div>
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
