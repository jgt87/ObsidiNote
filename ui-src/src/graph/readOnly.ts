// Why a page cannot be changed here, in words. Pure (tests: readOnly.test.ts).
// operator, 2026-11-15: a page of the main vault showed "read only" with no reason and no Edit
// button; the cause (another ObsidiNote held the vault's writer lease) could only be guessed.

import type { GraphSource } from './model'

/** One sentence on why the source is read only and what to do; '' when it can be changed. */
export function readOnlyWhy(source: Pick<GraphSource, 'kind' | 'readOnly' | 'readOnlyReason'>): string {
  if (!source.readOnly) return ''
  switch (source.readOnlyReason) {
    case 'lease':
      return 'Pages may show as read only for now: another ObsidiNote seems to hold this vault. This window takes over within about two minutes after that one closes.'
    case 'not-active':
      return 'This is not the active vault. Choose it under Notebook in the side bar to change its pages.'
    case 'notebook':
      return 'This is a connected notebook: ObsidiNote reads it and never writes in it.'
    default:
      return source.kind === 'notebook' ? 'This is a connected notebook: ObsidiNote reads it and never writes in it.' : 'This vault is open read only in this window.'
  }
}
