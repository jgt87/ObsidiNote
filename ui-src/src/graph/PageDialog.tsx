// The page modal: a native <dialog> (Esc closes; the map puts focus back on the dot).
// ← and → step to the previous or next linked page of the page it was opened on. Back/Forward
// (header buttons, Alt+← / Alt+→) walk the pages visited in this dialog (history.ts).
// "Focus on this page" narrows the map to the page and its linked pages (filters.ts).
// "Ask about this" only calls back; "Edit" opens the edit form (PageEditForm.tsx: title, details,
// address, links), saved through onEditPage, which the app wires to POST /api/page/edit.
// What each key does and which buttons show is decided in pageDialogModel.ts; the header, tabs and
// footer are PageDialogParts.tsx.

import { useEffect, useRef, useState, type ReactNode } from 'react'
import type { AddStatus } from '../add/types'
import type { RetireAnswer } from './graphApi'
import type { RetireAction } from './retireModel'
import { exportSourceOf } from '../export/exportApi'
import type { PageEditRequest } from './editModel'
import type { PageBodyResult } from './PageBody'
import type { GraphIndex } from './graphIndex'
import { primaryTopic, type GraphPage } from './model'
import { dialogKeysHint, pageLinks, type DialogTab } from './pageDialogModel'
import { DialogFooter, DialogHeader, DialogTabs, NeighbourhoodTab, PageTab, rowNav, TopicTab, type Linking } from './PageDialogParts'
import { PageEditForm } from './PageEditForm'
import { pageReadOnlyWhy } from './readOnly'
import { seriesCopies, seriesCount } from '../model/series'
import type { MergeAnswer } from './mergeModel'
import { useDialogKeys, useModalDialog } from './usePageDialogKeys'
import { usePageHistory } from './usePageHistory'

export interface PageActions {
  /** "Ask about this"; with $within, "Ask about this series": a question limited to the meetings of
   *  the page's series (2026-11-18). */
  onAsk?: (page: GraphPage, within?: { series: string; count: number }) => void
  /** Saves an edit of a page of the active vault; resolves once the map shows it. Read-only sources
   *  get no Edit button. */
  onEditPage?: (req: PageEditRequest) => Promise<unknown>
  /** "link it" on a mention: turn the mention into a link (from -> to). A promise keeps the button
   *  busy until it settles; its rejection's message shows in the dialog. */
  onLinkMention?: (from: GraphPage, to: GraphPage) => void | Promise<unknown>
  /** Adds and removes hand-set tags on pages of the active vault; resolves once the map shows it.
   *  Read-only sources get none. */
  onTagPages?: (ids: string[], add: string[], remove: string[]) => Promise<unknown>
  /** Reads the page's own text (GET /api/page/body); without it the window says where the text is. */
  loadBody?: (pageId: string, signal: AbortSignal) => Promise<PageBodyResult>
  /** Archive, Restore or Delete pages of the active vault (POST /api/pages/...). Without confirm,
   *  archive and delete answer with the plan the confirm shows (useRetireFlow). Read-only sources
   *  get none. */
  onRetire?: (action: RetireAction, ids: string[], confirm: boolean) => Promise<RetireAnswer>
  /** Update of one link page's summary (POST /api/link/update): the List's "Update summaries". */
  onUpdateLink?: (id: string) => Promise<AddStatus>
  /** "Merge duplicates" of a meeting series (POST /api/series/merge). Without confirm it answers with
   *  the plan the confirm shows (useMergeFlow). Read-only sources get none. */
  onMergeSeries?: (series: string, confirm: boolean) => Promise<MergeAnswer>
}

interface Props extends PageActions {
  index: GraphIndex
  pageId: string
  /** The page the dialog was opened on: ← → walk its linked pages. */
  anchorId: string
  onNavigate: (id: string) => void
  onClose: () => void
  /** "Focus on this page": the map shows only this page and its linked pages. */
  onFocusPage?: (id: string) => void
  /** A tag was pressed: show every page that has it. */
  onPickTag?: (tag: string) => void
  /** Archive / Restore / Delete pressed (the graph asks first, useRetireFlow). */
  onRetirePages?: (action: RetireAction, ids: string[]) => void
  /** "Merge duplicates" pressed on a series page (the graph asks first, useMergeFlow). */
  onMergePages?: (series: string) => void
  /** What the last Archive / Restore / Delete did, shown at the top of the window. */
  notice?: ReactNode
}

export function PageDialog({ index, pageId, anchorId, onNavigate, onClose, onFocusPage, onPickTag, onAsk, onEditPage, onLinkMention, onTagPages, loadBody, onRetirePages, onMergePages, notice }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  const [tab, setTab] = useState<DialogTab>('page')
  // Edit form open for this page (closes when another page is shown).
  const [editing, setEditing] = useState(false)
  useEffect(() => setEditing(false), [pageId])
  const history = usePageHistory(pageId, onNavigate)
  // "link it": the mention being linked (busy) and the last error, per page shown.
  const [linking, setLinking] = useState<Linking | null>(null)
  const page = index.pageById.get(pageId)
  useModalDialog(ref)
  const onKeyDown = useDialogKeys({ ref, index, anchorId, pageId, tab, setTab, history })

  if (!page) return null
  const topic = index.topicById.get(primaryTopic(page))
  const { out, back, mentions } = pageLinks(index, page.id)
  // A page the person made is shown like a read-only one: Edit greyed out with its reason, no
  // Archive or Delete, no tags (the server refuses all of them for such a page).
  const why = pageReadOnlyWhy(page, index.model.source)
  const ro = page.readOnly || page.own === false
  const { canEdit, inPlace } = editAccess(ro, onEditPage, editing)
  const nav = rowNav(index, history.go)
  const close = () => ref.current?.close()

  const src = exportSourceOf(index.model.source)

  return (
    <dialog
      ref={ref}
      className="kg-dialog"
      aria-labelledby="kg-dlg-title"
      onClose={onClose}
      onKeyDown={onKeyDown}
      onClick={(e) => {
        if (e.target === e.currentTarget) close()
      }}
    >
      <DialogHeader
        index={index}
        page={page}
        inPlace={inPlace}
        linksOut={out.length}
        linkedFrom={back.length}
        canBack={history.canBack}
        canForward={history.canForward}
        onBack={history.back}
        onForward={history.forward}
        onClose={close}
      />
      <DialogTabs tab={tab} topicName={topic?.name} onTab={setTab} />

      <div id="kg-tabpanel" role="tabpanel" aria-labelledby={`kg-tab-${tab}`} className="kg-dlg__body">
        {notice}
        {editing ? (
          onEditPage && (
            <PageEditForm
              index={index}
              page={page}
              onSave={async (req) => {
                await onEditPage(req)
                setEditing(false)
              }}
              onCancel={() => setEditing(false)}
            />
          )
        ) : (
          <ShownTab
            tab={tab}
            pageTab={
              <PageTab
                index={index}
                page={page}
                nav={nav}
                inPlace={inPlace}
                out={out}
                back={back}
                mentions={mentions}
                readOnly={ro}
                onTagPages={onTagPages}
                onPickTag={onPickTag}
                loadBody={loadBody}
                onLinkMention={onLinkMention}
                linking={linking}
                setLinking={setLinking}
              />
            }
            topicTab={<TopicTab index={index} page={page} nav={nav} src={src} />}
            neighbourhoodTab={<NeighbourhoodTab index={index} page={page} nav={nav} />}
          />
        )}
      </div>

      <DialogFooter
        page={page}
        editing={editing}
        readOnly={ro}
        why={why}
        src={src}
        onAsk={onAsk}
        seriesCount={page.series ? seriesCount(index.model.pages, page.series) : 0}
        canEdit={canEdit}
        onToggleEdit={() => {
          setTab('page')
          setEditing((e) => !e)
        }}
        onRetirePages={onRetirePages}
        onMergePages={onMergePages}
        copies={page.seriesPage && page.series ? seriesCopies(index.model.pages, page.series) : 0}
        onFocusPage={focusAndClose(onFocusPage, page.id, close)}
        keys={<span className="kg-dlg__keys">{dialogKeysHint((index.neighbours.get(anchorId) ?? []).length, history.canBack || history.canForward)}</span>}
      />
    </dialog>
  )
}

/** Who may change the page: the Edit form only for a page that can be written, and the title and
 *  summary in place (InlineText) only while the form is not open, which holds its own copy of both. */
function editAccess(readOnly: boolean, onEditPage: PageActions['onEditPage'], editing: boolean) {
  const canEdit = !!onEditPage && !readOnly
  return { canEdit, inPlace: canEdit && !editing ? onEditPage! : null }
}

/** "Focus on this page": the map narrows to it and the window closes; none when the map offers it not. */
function focusAndClose(onFocusPage: ((id: string) => void) | undefined, pageId: string, close: () => void): (() => void) | undefined {
  if (!onFocusPage) return undefined
  return () => {
    onFocusPage(pageId)
    close()
  }
}

/** The chosen tab's content (each tab is made only when it is the one shown). */
function ShownTab({ tab, pageTab, topicTab, neighbourhoodTab }: { tab: DialogTab; pageTab: ReactNode; topicTab: ReactNode; neighbourhoodTab: ReactNode }) {
  const byTab: Record<DialogTab, ReactNode> = { page: pageTab, topic: topicTab, neighbourhood: neighbourhoodTab }
  return <>{byTab[tab]}</>
}
