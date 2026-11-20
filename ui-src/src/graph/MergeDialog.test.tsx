import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { MergeDialog } from './MergeDialog'
import type { GraphPage } from './model'
import { DialogFooter } from './PageDialogParts'

const seriesPage = { id: 'ps', title: 'Garden sync (series)', kind: 'meeting', series: 'Garden sync', seriesPage: true, topicIds: [], tags: [], aliases: [], url: '', onenoteUrl: '', archived: false } as unknown as GraphPage
const footer = (o: { readOnly?: boolean; copies?: number; merge?: boolean }) =>
  renderToStaticMarkup(
    <DialogFooter
      page={seriesPage}
      editing={false}
      readOnly={o.readOnly ?? false}
      why=""
      src={{ vault: 'v1' } as never}
      canEdit
      onToggleEdit={() => {}}
      onMergePages={o.merge === false ? undefined : () => {}}
      copies={o.copies ?? 0}
      keys={null}
    />,
  )

describe('Merge duplicates in the page window', () => {
  it('is offered on a series page with second copies, with their number', () => {
    expect(footer({ copies: 2 })).toContain('Merge duplicates (2)')
  })
  it('is not offered without copies, read only, or without the action', () => {
    expect(footer({ copies: 0 })).not.toContain('Merge duplicates')
    expect(footer({ copies: 2, readOnly: true })).not.toContain('Merge duplicates')
    expect(footer({ copies: 2, merge: false })).not.toContain('Merge duplicates')
  })
  it('the confirm lists each meeting with the copy that goes to the Archive', () => {
    const html = renderToStaticMarkup(
      <MergeDialog plan={{ series: 'Garden sync', groups: [{ keep: { id: 'p1', title: 'Garden sync · 2026-11-17 09:00' }, extra: [{ id: 'p2', title: 'Garden sync · 2026-11-17' }] }] }} busy={false} error="" onConfirm={() => {}} onCancel={() => {}} />,
    )
    expect(html).toContain('Merge the second copy of a meeting?')
    expect(html).toContain('Garden sync · 2026-11-17 09:00')
    expect(html).toContain('copy “Garden sync · 2026-11-17” → Archive')
    expect(html).toContain('Merge and archive the copy')
  })
})
