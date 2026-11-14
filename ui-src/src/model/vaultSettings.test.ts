import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { changedKeys, normalizeSettings, parseHosts, parseNumber, SETTING_DEFAULTS, settleNumber } from './vaultSettings'

describe('vault settings', () => {
  it('match the server defaults (tests/fixtures/vault-settings.json)', () => {
    const want = JSON.parse(readFileSync(new URL('../../../tests/fixtures/vault-settings.json', import.meta.url), 'utf8'))
    expect(SETTING_DEFAULTS).toEqual(want)
  })
  it('fall back to the default for a wrong value, and take a one-item list as sent by PowerShell', () => {
    expect(normalizeSettings({ graphView: 'timeline', labelsHubsOnly: 'yes', internalHosts: 'wiki.example.invalid', relatedCount: 50, linkStaleDays: 2.5 })).toEqual({
      ...SETTING_DEFAULTS,
      internalHosts: ['wiki.example.invalid'],
    })
    expect(normalizeSettings(null)).toEqual(SETTING_DEFAULTS)
    expect(normalizeSettings({ graphView: 'sources', labelsHubsOnly: true, relatedCount: 5, askIncludeArchived: true })).toMatchObject({ graphView: 'sources', relatedCount: 5, askIncludeArchived: true })
  })
  it('read the company addresses field: one per line or comma, scheme and path dropped', () => {
    expect(parseHosts('https://Intranet.Example.invalid/home\n*.corp.example.invalid, intranet.example.invalid\n\nnot a host')).toEqual({
      hosts: ['intranet.example.invalid', '*.corp.example.invalid'],
      bad: ['not a host'],
    })
  })
  it('read a number field only as a whole number in range', () => {
    expect(parseNumber(' 5 ', 'relatedCount')).toBe(5)
    expect(parseNumber('0', 'relatedCount')).toBeNull()
    expect(parseNumber('11', 'relatedCount')).toBeNull()
    expect(parseNumber('2.5', 'linkStaleDays')).toBeNull()
    expect(parseNumber('', 'linkStaleDays')).toBeNull()
    expect(parseNumber('365', 'linkStaleDays')).toBe(365)
  })
  it('move a number to the nearest end of its range when the field is left (operator 2026-11-14: "mentions 1 to 10 but the setting is 12")', () => {
    expect(settleNumber('12', 'relatedCount', 3)).toBe(10)
    expect(settleNumber('0', 'relatedCount', 3)).toBe(1)
    expect(settleNumber('5000', 'linkStaleDays', 90)).toBe(730)
    expect(settleNumber('abc', 'linkStaleDays', 90)).toBe(90)
    expect(settleNumber('', 'linkStaleDays', 45)).toBe(45)
    expect(settleNumber(' 30 ', 'linkStaleDays', 90)).toBe(30)
  })
  it('send only what changed', () => {
    expect(changedKeys(SETTING_DEFAULTS, { ...SETTING_DEFAULTS, relatedCount: 4, internalHosts: ['a.example.invalid'] })).toEqual(['internalHosts', 'relatedCount'])
    expect(changedKeys(SETTING_DEFAULTS, { ...SETTING_DEFAULTS })).toEqual([])
  })
})
