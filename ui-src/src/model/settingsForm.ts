// The Settings dialog's form (components/SettingsDialog.tsx): the text of its fields, the settings
// that text stands for, what is wrong with it, and the wording around it. Pure (settingsForm.test.ts).
import { NUMBER_RANGES, parseHosts, parseNumber, type NumberKey, type VaultSettings } from './vaultSettings'

/** The number fields' text, by setting (a field may hold text that is not a valid number yet). */
export type NumberTexts = Record<NumberKey, string>

/** The number fields' text for stored settings. */
export function numberTexts(s: VaultSettings): NumberTexts {
  return { relatedCount: String(s.relatedCount), linkStaleDays: String(s.linkStaleDays), askMaxPages: String(s.askMaxPages) }
}

export interface SettingsDraft {
  /** The settings the fields stand for; a number field that cannot be read keeps the stored value. */
  next: VaultSettings
  /** The "Company addresses" entries that are not a host. */
  badHosts: string[]
  /** The number fields whose text is not a whole number in range. */
  badNumbers: NumberKey[]
  /** Anything wrong: Save stays off. */
  invalid: boolean
}

/** What the form's fields say, read against the settings they started from (`s`). */
export function settingsDraft(s: VaultSettings, hostText: string, nums: NumberTexts): SettingsDraft {
  const hosts = parseHosts(hostText)
  const badNumbers = (Object.keys(NUMBER_RANGES) as NumberKey[]).filter((k) => parseNumber(nums[k], k) === null)
  const next: VaultSettings = {
    ...s,
    internalHosts: hosts.hosts,
    relatedCount: parseNumber(nums.relatedCount, 'relatedCount') ?? s.relatedCount,
    linkStaleDays: parseNumber(nums.linkStaleDays, 'linkStaleDays') ?? s.linkStaleDays,
    askMaxPages: parseNumber(nums.askMaxPages, 'askMaxPages') ?? s.askMaxPages,
  }
  return { next, badHosts: hosts.bad, badNumbers, invalid: hosts.bad.length > 0 || badNumbers.length > 0 }
}

/** Every value a number setting can take, as the text of a list's options (a short range). */
export function numberChoices(key: NumberKey): string[] {
  const r = NUMBER_RANGES[key]
  return Array.from({ length: r.max - r.min + 1 }, (_, i) => String(r.min + i))
}

/** The sentence after "Kept in the vault ..." when this window cannot change the settings (with a
 *  leading space), else ''. Nothing is said before the settings arrived. */
export function readOnlyNote(loaded: boolean, canChange: boolean, why: string): string {
  return loaded && !canChange ? ` ${why || 'They cannot be changed from this window for now.'}` : ''
}

/** The running app's version without a leading "v" (GET /api/status gives either form). */
export function bareVersion(version: string): string {
  return version.replace(/^v/i, '')
}
