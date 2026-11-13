import { beforeEach, describe, expect, it, vi } from 'vitest'
import { dismiss, hiddenCount, isDismissed, loadWhatsNew, normalizeWhatsNew, resetWhatsNewForTests, shouldShow, visibleNotes, type WhatsNewNote } from './whatsNew'

const notes = (n: number): WhatsNewNote[] => Array.from({ length: n }, (_, i) => ({ kind: 'Added', text: `Line ${i + 1}` }))

describe('normalizeWhatsNew', () => {
  it('keeps version, updated and the notes with a known kind and text', () => {
    const w = normalizeWhatsNew({
      version: 'v1.2.0',
      updated: true,
      notes: [{ kind: 'Added', text: ' Find. ' }, { kind: 'Removed', text: 'x' }, { kind: 'Fixed', text: '' }, null],
    })
    expect(w).toEqual({ version: 'v1.2.0', updated: true, notes: [{ kind: 'Added', text: 'Find.' }] })
  })
  it('takes a one-item list handed over as an object, and anything odd as not updated', () => {
    expect(normalizeWhatsNew({ version: 'v1', updated: true, notes: { kind: 'Fixed', text: 'A' } }).notes).toHaveLength(1)
    expect(normalizeWhatsNew(null)).toEqual({ version: '', updated: false, notes: [] })
    expect(normalizeWhatsNew({ version: 'v1', updated: 'yes' }).updated).toBe(false)
  })
})

describe('shouldShow, visibleNotes, hiddenCount', () => {
  const w = { version: 'v1.2.0', updated: true, notes: notes(5) }
  it('shows only after an update to a known version, until dismissed', () => {
    expect(shouldShow(w, false)).toBe(true)
    expect(shouldShow(w, true)).toBe(false)
    expect(shouldShow({ ...w, updated: false }, false)).toBe(false)
    expect(shouldShow({ ...w, version: '' }, false)).toBe(false)
    expect(shouldShow(null, false)).toBe(false)
  })
  it('collapses after 3 lines', () => {
    expect(visibleNotes(w.notes, false).map((n) => n.text)).toEqual(['Line 1', 'Line 2', 'Line 3'])
    expect(hiddenCount(w.notes, false)).toBe(2)
    expect(visibleNotes(w.notes, true)).toHaveLength(5)
    expect(hiddenCount(w.notes, true)).toBe(0)
    expect(hiddenCount(notes(3), false)).toBe(0)
  })
})

describe('this run\'s memory', () => {
  beforeEach(() => resetWhatsNewForTests())
  it('asks the server once, with the app header', async () => {
    const f = vi.fn(async () => new Response(JSON.stringify({ version: 'v1.2.0', updated: true, notes: [] }), { status: 200 }))
    const a = await loadWhatsNew(f as unknown as typeof fetch)
    await loadWhatsNew(f as unknown as typeof fetch)
    expect(f).toHaveBeenCalledTimes(1)
    expect(f.mock.calls[0]).toEqual(['/api/whats-new', { headers: { 'X-ObsidiNote': '1' }, cache: 'no-store' }])
    expect(a.updated).toBe(true)
  })
  it('treats a failed or refused call as nothing to show', async () => {
    const down = vi.fn(async () => {
      throw new Error('offline')
    })
    expect((await loadWhatsNew(down as unknown as typeof fetch)).updated).toBe(false)
    resetWhatsNewForTests()
    const refused = vi.fn(async () => new Response('{}', { status: 403 }))
    expect((await loadWhatsNew(refused as unknown as typeof fetch)).updated).toBe(false)
  })
  it('remembers a dismissal for the run (memory only)', () => {
    expect(isDismissed()).toBe(false)
    dismiss()
    expect(isDismissed()).toBe(true)
  })
})
