import { describe, expect, it } from 'vitest'
import type { NotebookSummary } from '../api'
import { addTargetFor, askSourceChoices, graphRefFor, pickActiveVault, switcherGroups } from './notebooks'
import { isNotebookId } from './preferences'

const A = '{11111111-1111-1111-1111-111111111111}{1}{B0}'
const B = '{22222222-2222-2222-2222-222222222222}{1}{B0}'
const R = '{33333333-3333-3333-3333-333333333333}{1}{B0}'
const list: NotebookSummary[] = [
  { id: A, name: 'ObsidiNote', vault: true, active: true, location: 'OneDrive' },
  { id: B, name: 'Team wiki', vault: true, active: false, location: 'SharePoint' },
  { id: R, name: 'Reading notes', vault: false, active: false, location: 'this PC' },
]

describe('pickActiveVault', () => {
  it('takes the stored vault when it is open', () => {
    expect(pickActiveVault(list, B)).toBe(B)
  })
  it('ignores a stored id that is not an open vault', () => {
    expect(pickActiveVault(list, R)).toBe(A)
    expect(pickActiveVault(list, '{99999999-9999-9999-9999-999999999999}{1}{B0}')).toBe(A)
  })
  it('is null when no vault is open', () => {
    expect(pickActiveVault([list[2]], null)).toBeNull()
  })
  it('takes the only vault, but picks none of several when none is active or chosen', () => {
    const quiet = list.map((n) => ({ ...n, active: false }))
    expect(pickActiveVault([quiet[1], quiet[2]], null)).toBe(B)
    expect(pickActiveVault(quiet, null)).toBeNull()
  })
})

describe('graphRefFor', () => {
  it('loads a vault by its vault id and anything else as a notebook', () => {
    expect(graphRefFor({ ...list[0], vaultId: 'v-1' })).toEqual({ vault: 'v-1' })
    expect(graphRefFor(list[2])).toEqual({ notebook: R })
    expect(graphRefFor(undefined)).toEqual({})
  })
})

describe('askSourceChoices', () => {
  it('offers every other vault (by vault id) and notebook, read only', () => {
    const l = [{ ...list[0], vaultId: 'v-a' }, { ...list[1], vaultId: 'v-b' }, list[2]]
    expect(askSourceChoices(l, A)).toEqual([
      { id: 'v-b', label: 'Team wiki (vault, read only)' },
      { id: R, label: 'Reading notes (read only)' },
    ])
  })
})

describe('switcherGroups', () => {
  it('lists vaults first, then the others as read only', () => {
    const g = switcherGroups(list)
    expect(g.map((x) => x.label)).toEqual(['ObsidiNote vaults', 'Other notebooks'])
    expect(g[1].options[0].label).toBe('Reading notes (read only)')
  })
  it('leaves out an empty group', () => {
    expect(switcherGroups([list[0]]).length).toBe(1)
  })
})

describe('addTargetFor', () => {
  it('is null while the active vault is shown', () => {
    expect(addTargetFor(list, A, A)).toBeNull()
  })
  it('names the vault an Add goes to while another notebook is shown', () => {
    expect(addTargetFor(list, A, R)).toEqual({ vaultName: 'ObsidiNote', shownName: 'Reading notes' })
  })
})

describe('isNotebookId', () => {
  it('accepts OneNote notebook ids only', () => {
    expect(isNotebookId(A)).toBe(true)
    expect(isNotebookId('Reading notes')).toBe(false)
    expect(isNotebookId(42)).toBe(false)
  })
})
