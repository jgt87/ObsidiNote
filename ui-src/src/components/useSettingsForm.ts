// The Settings dialog's state (SettingsDialog.tsx): opens the dialog, reads the vault's settings once,
// keeps the fields' text, and saves only what changed, one call per setting.
import { useEffect, useRef, useState, type FormEvent, type RefObject } from 'react'
import { getSettings, saveSetting } from '../api'
import { numberTexts, settingsDraft, type NumberTexts } from '../model/settingsForm'
import { changedKeys, SETTING_DEFAULTS, type VaultSettings } from '../model/vaultSettings'

interface Refs {
  ref: RefObject<HTMLDialogElement | null>
  /** The first field, focused once the settings arrived and can be changed. */
  first: RefObject<HTMLTextAreaElement | null>
}

export function useSettingsForm({ ref, first }: Refs, onClose: () => void, onSaved?: (s: VaultSettings) => void) {
  const close = useRef(onClose)
  close.current = onClose
  const [before, setBefore] = useState<VaultSettings>(SETTING_DEFAULTS)
  const [s, setS] = useState<VaultSettings>(SETTING_DEFAULTS)
  const [hostText, setHostText] = useState('')
  const [nums, setNums] = useState<NumberTexts>({ relatedCount: '3', linkStaleDays: '90', askMaxPages: '20' })
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
        setNums(numberTexts(r.settings))
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

  const draft = settingsDraft(s, hostText, nums)
  const { next } = draft
  const changed = changedKeys(before, next)
  const off = !loaded || !canChange || busy

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    if (off || draft.invalid || !changed.length) return
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

  return { close, s, setS, hostText, setHostText, nums, setNums, canChange, why, loaded, busy, error, draft, changed, off, onSubmit }
}

export type SettingsForm = ReturnType<typeof useSettingsForm>
