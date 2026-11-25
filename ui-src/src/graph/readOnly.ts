// Why a page cannot be changed here, in words. Pure (tests: readOnly.test.ts).
// D-102, D-056: a page of the main vault showed "read only" with no reason and no Edit
// button; the cause (another ObsidiNote held the vault's writer lease) could only be guessed.

import type { GraphPage, GraphSource } from './model'

/** Why a page you made yourself is not changed here (D-056). ObsidiNote lists those pages and never edits, archives or deletes them. */
export const OWN_PAGE_WHY = 'You made this page in OneNote: ObsidiNote lists it and never changes it. Change, archive or delete it in OneNote.'

/** Why this page cannot be changed in the window: the source's reason first, then a page that is
 *  not one of ObsidiNote's own; '' when it can be changed. */
export function pageReadOnlyWhy(page: Pick<GraphPage, 'readOnly' | 'own'>, source: Pick<GraphSource, 'kind' | 'readOnly' | 'readOnlyReason'>): string {
  if (page.readOnly) return readOnlyWhy(source)
  return page.own === false ? OWN_PAGE_WHY : ''
}

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
