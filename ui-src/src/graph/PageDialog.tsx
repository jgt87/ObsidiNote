// The page modal: a native <dialog> (Esc closes; the map puts focus back on the dot).
// ← and → step to the previous or next linked page of the page it was opened on. Back/Forward
// (header buttons, Alt+← / Alt+→) walk the pages visited in this dialog (history.ts).
// "Focus on this page" narrows the map to the page and its linked pages (filters.ts).
// "Ask about this" only calls back; "Edit" opens the edit form (PageEditForm.tsx: title, details,
// address, links), saved through onEditPage, which the app wires to POST /api/page/edit.
// What each key does and which buttons show is decided in pageDialogModel.ts; the header, tabs and
// footer are PageDialogParts.tsx.

import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from 'react'
import type { AddStatus } from '../add/types'
import type { RetireAnswer } from './graphApi'
import type { RetireAction } from './retireModel'
import { exportSourceOf } from '../export/exportApi'
import type { PageEditRequest } from './editModel'
import type { PageBodyResult } from './PageBody'
import type { GraphIndex } from './graphIndex'
import { primaryTopic, type GraphPage } from './model'
import { canGoBack, canGoForward, currentPage, goBack, goForward, startHistory, visit, type PageHistory } from './history'
import { dialogKeyAction, nextTab, type DialogTab } from './pageDialogModel'
import { DialogFooter, DialogHeader, DialogTabs, NeighbourhoodTab, PageTab, rowNav, TopicTab, type Linking } from './PageDialogParts'
import { PageEditForm } from './PageEditForm'
import { readOnlyWhy } from './readOnly'
import { stepLinked } from './view'

export interface PageActions {
  onAsk?: (page: GraphPage) => void
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
  /** What the last Archive / Restore / Delete did, shown at the top of the window. */
  notice?: ReactNode
}

export function PageDialog({ index, pageId, anchorId, onNavigate, onClose, onFocusPage, onPickTag, onAsk, onEditPage, onLinkMention, onTagPages, loadBody, onRetirePages, notice }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  const [tab, setTab] = useState<DialogTab>('page')
  // Edit form open for this page (closes when another page is shown).
  const [editing, setEditing] = useState(false)
  useEffect(() => setEditing(false), [pageId])
  // Back/Forward over the pages visited in this dialog (history.ts); gone when it closes.
  const [hist, setHist] = useState<PageHistory>(() => startHistory(pageId))
  // "link it": the mention being linked (busy) and the last error, per page shown.
  const [linking, setLinking] = useState<Linking | null>(null)
  const page = index.pageById.get(pageId)

  useEffect(() => {
    const d = ref.current
    if (d && !d.open) d.showModal()
  }, [])
  // A page set from outside (not through go/back/forward) still counts as a visit.
  useEffect(() => {
    setHist((h) => (currentPage(h) === pageId ? h : visit(h, pageId)))
  }, [pageId])

  const go = (id: string) => {
    setHist((h) => visit(h, id))
    onNavigate(id)
  }
  const move = (next: PageHistory) => {
    if (next === hist) return
    setHist(next)
    onNavigate(currentPage(next))
  }

  if (!page) return null
  const topic = index.topicById.get(primaryTopic(page))
  const out = index.out.get(page.id) ?? []
  const back = index.in.get(page.id) ?? []
  const mentions = (index.mentions.get(page.id) ?? []).filter((e) => e.from === page.id || e.to === page.id)
  const ro = page.readOnly
  const why = ro ? readOnlyWhy(index.model.source) : ''
  // Title and summary are changed where they stand (InlineText); not while the form is open,
  // which holds its own copy of both.
  const inPlace = onEditPage && !ro && !editing ? onEditPage : null
  const nav = rowNav(index, go)
  const close = () => ref.current?.close()

  const onKeyDown = (e: KeyboardEvent<HTMLDialogElement>) => {
    const t = e.target as HTMLElement
    const a = dialogKeyAction(e, t.getAttribute('role') === 'tab', !!t.closest('input, textarea, select'))
    if (!a) return
    e.preventDefault()
    if (a === 'back' || a === 'forward') move(a === 'back' ? goBack(hist) : goForward(hist))
    else if (a === 'tab-next' || a === 'tab-prev') {
      const n = nextTab(tab, a === 'tab-next' ? 1 : -1)
      setTab(n)
      ref.current?.querySelector<HTMLElement>(`#kg-tab-${n}`)?.focus()
    } else {
      const next = stepLinked(index, anchorId, page.id, a === 'step-next' ? 1 : -1)
      if (next) go(next)
    }
  }

  const pos = (index.neighbours.get(anchorId) ?? []).length
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
        canBack={canGoBack(hist)}
        canForward={canGoForward(hist)}
        onBack={() => move(goBack(hist))}
        onForward={() => move(goForward(hist))}
        onClose={close}
      />
      <DialogTabs tab={tab} topicName={topic?.name} onTab={setTab} />

      <div id="kg-tabpanel" role="tabpanel" aria-labelledby={`kg-tab-${tab}`} className="kg-dlg__body">
        {notice}
        {editing && onEditPage && (
          <PageEditForm
            index={index}
            page={page}
            onSave={async (req) => {
              await onEditPage(req)
              setEditing(false)
            }}
            onCancel={() => setEditing(false)}
          />
        )}
        {!editing && tab === 'page' && (
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
        )}
        {!editing && tab === 'topic' && <TopicTab index={index} page={page} nav={nav} src={src} />}
        {!editing && tab === 'neighbourhood' && <NeighbourhoodTab index={index} page={page} nav={nav} />}
      </div>

      <DialogFooter
        page={page}
        editing={editing}
        readOnly={ro}
        why={why}
        src={src}
        onAsk={onAsk}
        canEdit={!!onEditPage && !ro}
        onToggleEdit={() => {
          setTab('page')
          setEditing((e) => !e)
        }}
        onRetirePages={onRetirePages}
        onFocusPage={
          onFocusPage
            ? () => {
                onFocusPage(page.id)
                close()
              }
            : undefined
        }
        keys={
          <span className="kg-dlg__keys">
            Esc closes{pos ? ' · ← → previous or next linked page' : ''}
            {canGoBack(hist) || canGoForward(hist) ? ' · Alt+← → back or forward' : ''}
          </span>
        }
      />
    </dialog>
  )
}
