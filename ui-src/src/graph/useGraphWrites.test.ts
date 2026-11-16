import { describe, expect, it } from 'vitest'
import { normalizeGraph } from './model'
import { canWrite, rereadAfter } from './useGraphWrites'

describe('rereadAfter: the map read again after a write', () => {
  it('resolves when the map was read again', async () => {
    let reads = 0
    await expect(rereadAfter(async () => void reads++, 'unused')).resolves.toBeUndefined()
    expect(reads).toBe(1)
  })
  it('says the write stands when only the read failed', async () => {
    const failing = async () => {
      throw new Error('network down')
    }
    await expect(rereadAfter(failing, 'The page was saved, but the map could not be read again.')).rejects.toThrow('The page was saved, but the map could not be read again.')
  })
})

describe('canWrite: which sources get the write actions', () => {
  it('only a vault that is not read only', () => {
    expect(canWrite(null)).toBe(false)
    expect(canWrite(normalizeGraph({ source: { kind: 'vault', readOnly: false } }))).toBe(true)
    expect(canWrite(normalizeGraph({ source: { kind: 'vault', readOnly: true, readOnlyReason: 'lease' } }))).toBe(false)
    expect(canWrite(normalizeGraph({ source: { kind: 'notebook', readOnly: true } }))).toBe(false)
  })
})
