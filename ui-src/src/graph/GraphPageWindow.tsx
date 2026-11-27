// The knowledge graph's page window (KnowledgeGraph.tsx): the open page, if any, with the outcome of
// Archive / Restore / Delete and "Merge duplicates" shown inside it while it is open.
import type { ReactNode } from 'react'
import type { GraphIndex } from './graphIndex'
import { PageDialog, type PageActions } from './PageDialog'
import type { RetireAction } from './retireModel'
import type { PageDialogState } from './useGraphInteraction'

interface Props extends PageActions {
  index: GraphIndex
  /** The open page and the page it was opened on (usePageDialog); null = no window. */
  dialog: PageDialogState | null
  page: { navigate: (id: string) => void; close: () => void }
  onFocusPage: (id: string) => void
  /** A tag picked in the window: the window closes first. */
  onPickTag: (tag: string) => void
  onRetirePages?: (action: RetireAction, ids: string[]) => void
  /** "Merge duplicates" of a series (useMergeFlow's start); offered only with `onMergeSeries`. */
  onMerge: (series: string) => unknown
  notice: ReactNode
}

export function GraphPageWindow({ index, dialog, page, onFocusPage, onPickTag, onRetirePages, onMerge, notice, ...actions }: Props) {
  if (!dialog) return null
  return (
    <PageDialog
      key="dialog"
      index={index}
      pageId={dialog.pageId}
      anchorId={dialog.anchorId}
      onNavigate={page.navigate}
      onClose={page.close}
      onFocusPage={onFocusPage}
      onPickTag={(t) => {
        page.close()
        onPickTag(t)
      }}
      {...actions}
      onRetirePages={onRetirePages}
      onMergePages={actions.onMergeSeries ? (s) => void onMerge(s) : undefined}
      notice={notice}
    />
  )
}
