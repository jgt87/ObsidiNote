import { describe, expect, it } from 'vitest'
import type { AppStatus } from '../api'
import { attentionNotes, leaseCheckNote, sendBlock, vaultNote } from './attention'

function status(over: Partial<AppStatus['oneNote']> = {}, copilot: AppStatus['copilot']['state'] = 'connected'): AppStatus {
  return {
    app: 'ObsidiNote',
    version: 'v0.0.0',
    uiPort: 8767,
    oneNote: { state: 'window', running: true, notebookOpen: true, notebook: 'ObsidiNote', ...over },
    copilot: { state: copilot, port: 9334 },
  }
}

describe('attentionNotes', () => {
  it('shows nothing when all is well', () => {
    expect(attentionNotes(status(), false)).toEqual([])
  })
  it('names a OneNote that is not running, or a notebook that is not open', () => {
    expect(attentionNotes(status({ running: false, notebookOpen: false, state: 'none' }), false).map((n) => n.id)).toEqual(['onenote'])
    expect(attentionNotes(status({ notebookOpen: false }), false)[0].text).toMatch('No ObsidiNote vault is open in OneNote.')
  })
  it('names Copilot when it is off or gone', () => {
    expect(attentionNotes(status({}, 'skipped'), false).map((n) => n.id)).toEqual(['copilot'])
    expect(attentionNotes(status({}, 'not-running'), false)[0].text).toMatch('Edge window is closed')
  })
  it('offers the refresh button when Copilot is gone, not when it was turned off for this start', () => {
    expect(attentionNotes(status({}, 'not-running'), false)[0].retry).toBe(true)
    expect(attentionNotes(status({}, 'no-tab'), false)[0].retry).toBe(true)
    expect(attentionNotes(status({}, 'skipped'), false)[0].retry).toBe(false)
    expect(attentionNotes(status({ running: false, notebookOpen: false, state: 'none' }), false)[0].retry).toBeUndefined()
  })
  it('says when the server does not answer', () => {
    expect(attentionNotes(null, true).map((n) => n.id)).toEqual(['server'])
  })
})

describe('leaseCheckNote: what "Check again" found', () => {
  const now = new Date('2026-11-15T09:00:30Z')
  const held = (renewed: string, until: string) => ({ name: 'V', vaultId: 'v1', mode: 'readonly' as const, reason: 'this-pc', renewed, until })
  it('says nothing once this window is the writer (the note goes)', () => {
    expect(leaseCheckNote({ name: 'V', vaultId: 'v1', mode: 'writer', reason: '' }, now)).toBe('')
  })
  it('a holder that renewed within 90 seconds seems to be running: close it, waiting will not help', () => {
    const text = leaseCheckNote(held('2026-11-15T09:00:00Z', '2026-11-15T09:02:00Z'), now)
    expect(text).toMatch(/still held.*seems to be still running\. Close its console window on this PC/)
    expect(text).not.toMatch(/should take over by/)
  })
  it('a holder that has not renewed lately runs out: this window takes over by its end time', () => {
    const text = leaseCheckNote(held('2026-11-15T08:57:00Z', '2026-11-15T08:59:00Z'), now)
    expect(text).toMatch(/not free yet.*should take over by \d\d:\d\d\./)
  })
  it('another PC: close ObsidiNote there', () => {
    expect(leaseCheckNote({ ...held('2026-11-15T09:00:00Z', '2026-11-15T09:02:00Z'), reason: 'other-pc' }, now)).toMatch(/Close ObsidiNote on that PC/)
  })
})

describe('vaultNote: why this window cannot write in its vault', () => {
  const withVault = (vault: AppStatus['vault']): AppStatus => ({ ...status(), vault })
  it('says nothing while this window is the writer, or when the server gives no reason', () => {
    expect(vaultNote(status())).toBe('')
    expect(vaultNote(withVault({ name: 'V', vaultId: 'v1', mode: 'writer', reason: '' }))).toBe('')
    expect(vaultNote(withVault({ name: 'V', vaultId: 'v1', mode: 'readonly' }))).toBe('')
  })
  it('names the other PC, this PC and a vault that was not opened, each with what comes next', () => {
    expect(vaultNote(withVault({ name: 'V', vaultId: 'v1', mode: 'readonly', reason: 'other-pc', since: '' }))).toMatch(/another PC seems to be writing.*If it is closed there/)
    expect(vaultNote(withVault({ name: 'V', vaultId: 'v1', mode: 'readonly', reason: 'this-pc', since: '' }))).toMatch(/^Starting up: .*earlier ObsidiNote on this PC\. This usually clears/)
  })
  it('names the time it should clear by when the server gives one', () => {
    expect(vaultNote(withVault({ name: 'V', vaultId: 'v1', mode: 'readonly', reason: 'this-pc', until: '2026-11-15T09:02:00Z' }))).toMatch(/usually clears by \d\d:\d\d\./)
    expect(vaultNote(withVault({ name: 'V', vaultId: 'v1', mode: 'readonly', reason: 'this-pc' }))).toMatch(/usually clears within about two minutes\./)
  })
  it('says what may be the case for a lease, never a verdict (read from a record, not seen)', () => {
    for (const reason of ['other-pc', 'this-pc'] as const) {
      const text = vaultNote(withVault({ name: 'V', vaultId: 'v1', mode: 'readonly', reason, since: '' }))
      expect(text).toMatch(/\bmay\b/)
      expect(text).not.toMatch(/^Read only:/)
    }
    expect(vaultNote(withVault({ name: '', vaultId: '', mode: 'none', reason: 'not-opened', detail: 'two vaults are open' }))).toBe('The vault could not be opened: two vaults are open Nothing can be added until it is; start ObsidiNote again after fixing it.')
  })
  it('is listed with the other things that need attention', () => {
    expect(attentionNotes(withVault({ name: 'V', vaultId: 'v1', mode: 'readonly', reason: 'other-pc' }), false).map((n) => n.id)).toEqual([])
  })
})

describe('sendBlock: why a send cannot work, for the box itself', () => {
  it('is silent while Copilot is connected or the status is not known yet', () => {
    expect(sendBlock(status(), false)).toBeNull()
    expect(sendBlock(null, false)).toBeNull()
  })
  it('switches Send off only when ObsidiNote itself is gone', () => {
    expect(sendBlock(null, true)).toMatchObject({ disableSend: true, retry: false })
    expect(sendBlock(status({}, 'no-tab'), false)).toMatchObject({ disableSend: false, retry: true })
    expect(sendBlock(status({}, 'not-running'), false)).toMatchObject({ disableSend: false, retry: true })
  })
  it('offers no reconnect when Copilot was switched off for this start', () => {
    const b = sendBlock(status({}, 'skipped'), false)
    expect(b).toMatchObject({ disableSend: false, retry: false })
    expect(b?.text).not.toMatch(/-NoCopilot/)
  })
})
