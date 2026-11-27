import { describe, expect, it } from 'vitest'
import { bareVersion, numberChoices, numberTexts, readOnlyNote, settingsDraft } from './settingsForm'
import { SETTING_DEFAULTS } from './vaultSettings'

const stored = { ...SETTING_DEFAULTS, internalHosts: ['intranet.example.com'], relatedCount: 4, linkStaleDays: 60, askMaxPages: 25 }

describe('settingsDraft: what the fields say', () => {
  it('reads the fields as settings: hosts in normal form, numbers as numbers', () => {
    const d = settingsDraft(stored, 'Intranet.example.com, *.corp.example.com', { relatedCount: '5', linkStaleDays: '120', askMaxPages: '30' })
    expect(d.next).toEqual({ ...stored, internalHosts: ['intranet.example.com', '*.corp.example.com'], relatedCount: 5, linkStaleDays: 120, askMaxPages: 30 })
    expect(d).toMatchObject({ badHosts: [], badNumbers: [], invalid: false })
  })
  it('keeps the stored value of a number it cannot read, and names that field', () => {
    const d = settingsDraft(stored, 'intranet.example.com', { relatedCount: '4', linkStaleDays: '1000', askMaxPages: '' })
    expect(d.next.linkStaleDays).toBe(60)
    expect(d.next.askMaxPages).toBe(25)
    expect(d.badNumbers).toEqual(['linkStaleDays', 'askMaxPages'])
    expect(d.invalid).toBe(true)
  })
  it('names an entry that is not an address, and leaves it out of the settings', () => {
    const d = settingsDraft(stored, 'intranet.example.com\nnot an address!', numberTexts(stored))
    expect(d.badHosts).toEqual(['not an address!'])
    expect(d.next.internalHosts).toEqual(['intranet.example.com'])
    expect(d.invalid).toBe(true)
  })
  it('starts from the stored settings: nothing wrong, nothing different', () => {
    const d = settingsDraft(stored, stored.internalHosts.join('\n'), numberTexts(stored))
    expect(d.next).toEqual(stored)
    expect(d.invalid).toBe(false)
  })
})

describe('the wording and lists around the fields', () => {
  it('gives the number fields their text', () => {
    expect(numberTexts(stored)).toEqual({ relatedCount: '4', linkStaleDays: '60', askMaxPages: '25' })
  })
  it('lists every value of a short range, both ends included', () => {
    expect(numberChoices('relatedCount')).toEqual(['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'])
  })
  it('says why a window cannot change the settings, only once they arrived', () => {
    expect(readOnlyNote(true, false, 'Another PC seems to be writing.')).toBe(' Another PC seems to be writing.')
    expect(readOnlyNote(true, false, '')).toBe(' They cannot be changed from this window for now.')
    expect(readOnlyNote(false, false, 'x')).toBe('')
    expect(readOnlyNote(true, true, 'x')).toBe('')
  })
  it('shows the version with one "v"', () => {
    expect(bareVersion('v0.12.27')).toBe('0.12.27')
    expect(bareVersion('V1.0.0')).toBe('1.0.0')
    expect(bareVersion('0.12.27')).toBe('0.12.27')
  })
})
