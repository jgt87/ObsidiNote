// The page modal: a native <dialog> (Esc closes; the map puts focus back on the dot).
// ← and → step to the previous or next linked page of the page it was opened on. Back/Forward
// (header buttons, Alt+← / Alt+→) walk the pages visited in this dialog (history.ts).
// "Focus on this page" narrows the map to the page and its linked pages (filters.ts).
// "Ask about this" only calls back; "Edit" opens the edit form (PageEditForm.tsx: title, details,
// address, links), saved through onEditPage, which the app wires to POST /api/page/edit.

import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from 'react'
import type { AddStatus } from '../add/types'
import type { RetireAnswer } from './graphApi'
import type { RetireAction } from './retireModel'
import { ExportButton } from '../export/ExportButton'
import { exportSourceOf } from '../export/exportApi'
import { summaryProblem, titleProblem, type PageEditRequest } from './editModel'
import { InlineText } from './InlineText'
import { PageBody, type PageBodyResult } from './PageBody'
import { formatDate, plural } from './format'
import { pageTypeLabel } from '../model/format'
import { indexPath, type GraphIndex } from './graphIndex'
import { primaryTopic, type GraphEdge, type GraphPage } from './model'
import { canGoBack, canGoForward, currentPage, goBack, goForward, startHistory, visit, type PageHistory } from './history'
import { PageEditForm } from './PageEditForm'
import { readOnlyWhy } from './readOnly'
import { tagCounts } from './tags'
import { TagsRow } from './TagsRow'
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

type Tab = 'page' | 'topic' | 'neighbourhood'
const TABS: Tab[] = ['page', 'topic', 'neighbourhood']

function Bars({ s }: { s: number }) {
  return (
    <div className="kg-bar" role="img" aria-label={`Strength ${s} of 3`}>
      {[1, 2, 3].map((i) => (
        <i key={i} className={i <= s ? 'on' : undefined} />
      ))}
    </div>
  )
}

/* marker */
export function PageDialog({ index, pageId, anchorId, onNavigate, onClose, onFocusPage, onPickTag, onAsk, onEditPage, onLinkMention, onTagPages, loadBody, onRetirePages, notice }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  const [tab, setTab] = useState<Tab>('page')
  // Edit form open for this page (closes when another page is shown).
  const [editing, setEditing] = useState(false)
  useEffect(() => setEditing(false), [pageId])
  // Back/Forward over the pages visited in this dialog (history.ts); gone when it closes.
  const [hist, setHist] = useState<PageHistory>(() => startHistory(pageId))
  // "link it": the mention being linked (busy) and the last error, per page shown.
  const [linking, setLinking] = useState<{ key: string; error: string; pageId: string } | null>(null)
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
  const topicId = primaryTopic(page)
  const topic = index.topicById.get(topicId)
  const out = index.out.get(page.id) ?? []
  const back = index.in.get(page.id) ?? []
  const mentions = (index.mentions.get(page.id) ?? []).filter((e) => e.from === page.id || e.to === page.id)
  const ro = page.readOnly
  const why = ro ? readOnlyWhy(index.model.source) : ''
  // Title and summary are changed where they stand (InlineText); not while the form is open,
  // which holds its own copy of both.
  const inPlace = onEditPage && !ro && !editing ? onEditPage : null
  const title = (id: string) => index.pageById.get(id)?.title ?? id
  const where = (id: string) => {
    const p = index.pageById.get(id)
    return p ? indexPath(index, primaryTopic(p)).replace(/^Index › /, '') : ''
  }

  const step = (delta: 1 | -1) => {
    const next = stepLinked(index, anchorId, page.id, delta)
    if (next) go(next)
  }
  const onKeyDown = (e: KeyboardEvent<HTMLDialogElement>) => {
    const t = e.target as HTMLElement
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return
    if (e.altKey && !e.ctrlKey && !e.metaKey && !e.shiftKey) {
      // Alt+Left/Right: Back/Forward in this dialog (never the browser's own history).
      e.preventDefault()
      move(e.key === 'ArrowLeft' ? goBack(hist) : goForward(hist))
      return
    }
    if (t.getAttribute('role') === 'tab') {
      // Arrows move between tabs inside the tab list (ARIA tabs pattern).
      e.preventDefault()
      const i = TABS.indexOf(tab)
      const n = TABS[(i + (e.key === 'ArrowRight' ? 1 : -1) + TABS.length) % TABS.length]
      setTab(n)
      ref.current?.querySelector<HTMLElement>(`#kg-tab-${n}`)?.focus()
      return
    }
    if (t.closest('input, textarea, select')) return
    e.preventDefault()
    step(e.key === 'ArrowRight' ? 1 : -1)
  }

  // design (review 2026-11-14): the page's name and its line under it are the button that opens it;
  // the old target was a 27x17px "open" at the far end of the row.
  const rowMain = (id: string, sub?: string) => (
    <button type="button" className="kg-rowbtn" onClick={() => go(id)}>
      <span className="kg-rowbtn__title">{title(id)}</span>
      {sub && <span className="kg-row__sub">{sub}</span>}
    </button>
  )
  const linkRow = (e: GraphEdge, other: string, withBars: boolean) => (
    <li key={`${e.from}>${e.to}`} className="kg-row">
      {withBars ? <Bars s={e.strength} /> : <div className="kg-row__sub" aria-hidden="true">—</div>}
      {rowMain(other, [where(other), e.reason].filter(Boolean).join(' · '))}
    </li>
  )
  const none = (text: string) => <li className="kg-row__none">{text}</li>

  const neighbours = index.neighbours.get(page.id) ?? []
  const second = new Set<string>()
  for (const n of neighbours) for (const m of index.neighbours.get(n) ?? []) if (m !== page.id && !neighbours.includes(m)) second.add(m)
  const topicPages = (index.pagesByArea.get(topicId) ?? []).filter((id) => id !== page.id)
  const subtopics = index.model.topics.filter((t) => t.parent === topicId)
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
        if (e.target === e.currentTarget) ref.current?.close()
      }}
    >
      <header className="kg-dlg__head">
        <div>
          <nav aria-label="Index path" className="kg-dlg__path">
            {indexPath(index, topicId)}
          </nav>
          <h2 id="kg-dlg-title" className="kg-dlg__title">
            {inPlace ? <InlineText key={page.id} value={page.title} name="title" problem={titleProblem} onSave={(title) => inPlace({ id: page.id, title })} /> : page.title}
          </h2>
          <div className="kg-dlg__meta">
            <span>
              {[
                // "hub" is the operator's word for a topic area (2026-11-15): never used for a page here.
                page.isHub ? 'most linked page' : pageTypeLabel(page.kind),
                page.bucket,
                formatDate(page.modified) && `changed ${formatDate(page.modified)}`,
                plural(out.length, 'link'),
                plural(back.length, 'backlink'),
              ]
                .filter(Boolean)
                .join(' · ')}
            </span>
          </div>
        </div>
        <nav className="kg-dlg__hist" aria-label="Pages visited">
          <button type="button" className="btn btn--icon btn--ghost" aria-label="Back" title="Back (Alt+←)" disabled={!canGoBack(hist)} onClick={() => move(goBack(hist))}>
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
              <path d="M10 3L5 8l5 5" />
            </svg>
          </button>
          <button type="button" className="btn btn--icon btn--ghost" aria-label="Forward" title="Forward (Alt+→)" disabled={!canGoForward(hist)} onClick={() => move(goForward(hist))}>
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
              <path d="M6 3l5 5-5 5" />
            </svg>
          </button>
        </nav>
        <button type="button" className="btn btn--icon" aria-label="Close" onClick={() => ref.current?.close()}>
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
            <path d="M4 4l8 8M12 4l-8 8" />
          </svg>
        </button>
      </header>

      <div role="tablist" aria-label="Page views" className="kg-tabs">
        {TABS.map((t) => (
          <button
            key={t}
            id={`kg-tab-${t}`}
            type="button"
            role="tab"
            className="kg-tab"
            aria-selected={tab === t}
            aria-controls="kg-tabpanel"
            tabIndex={tab === t ? 0 : -1}
            onClick={() => setTab(t)}
          >
            {t === 'page' ? 'Page' : t === 'topic' ? `Topic: ${topic?.name ?? 'Unfiled'}` : 'Neighbourhood'}
          </button>
        ))}
      </div>

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
          <div className="kg-cols">
            <div>
              <p className="kg-lbl">Summary</p>
              <p className="kg-summary">
                {inPlace ? (
                  <InlineText key={page.id} value={page.summary} name="summary" empty="No summary yet." multiline problem={summaryProblem} onSave={(summary) => inPlace({ id: page.id, summary })} />
                ) : (
                  page.summary || 'No summary yet.'
                )}
              </p>
              <p className="kg-lbl">Tags</p>
              <TagsRow
                key={page.id}
                tags={page.tags}
                all={tagCounts(index.model.pages)}
                onChange={onTagPages && !ro ? (add, remove) => onTagPages([page.id], add, remove) : undefined}
                label={`Add a tag to ${page.title}`}
                onPick={onPickTag}
              />
              <p className="kg-lbl">Page content</p>
              {loadBody ? (
                <PageBody pageId={page.id} load={loadBody} hasPage={(id) => index.pageById.has(id)} onOpenPage={go} />
              ) : (
                <p className="kg-note">The page text stays in OneNote: open it there to read or edit it, or export a copy as Markdown.</p>
              )}
              {page.topicIds.length > 1 && (
                <>
                  <p className="kg-lbl">Also under</p>
                  <ul className="kg-rows">
                    {page.topicIds.slice(1).map((id) => (
                      <li key={id} className="kg-row__none">
                        {indexPath(index, id)}
                      </li>
                    ))}
                  </ul>
                </>
              )}
            </div>
            <div>
              <p className="kg-lbl">Links out</p>
              <ul className="kg-rows">{out.length ? out.map((e) => linkRow(e, e.to, true)) : none('No links out yet.')}</ul>
              <p className="kg-lbl">Linked from</p>
              <ul className="kg-rows">{back.length ? back.map((e) => linkRow(e, e.from, true)) : none('Nothing links here yet.')}</ul>
              <p className="kg-lbl">Mentions, not linked</p>
              <ul className="kg-rows">
                {mentions.length
                  ? mentions.map((e) => {
                      const other = e.from === page.id ? e.to : e.from
                      return (
                        <li key={`${e.from}>${e.to}`} className="kg-row">
                          <div className="kg-row__sub" aria-hidden="true">—</div>
                          {rowMain(other, where(other))}
                          {ro || !onLinkMention ? null : (
                            <button
                              type="button"
                              className="kg-linkbtn kg-row__sub"
                              aria-label={`Link it: ${title(page.id)} and ${title(other)}`}
                              aria-busy={linking?.key === `${e.from}>${e.to}` && !linking.error}
                              disabled={!!linking && !linking.error}
                              onClick={() => {
                                const key = `${e.from}>${e.to}`
                                setLinking({ key, error: '', pageId: page.id })
                                Promise.resolve(onLinkMention(page, index.pageById.get(other)!)).then(
                                  () => setLinking(null),
                                  (err: unknown) => setLinking({ key, pageId: page.id, error: err instanceof Error && err.message ? err.message : 'The link could not be added.' }),
                                )
                              }}
                            >
                              {linking?.key === `${e.from}>${e.to}` && !linking.error ? 'linking…' : 'link it'}
                            </button>
                          )}
                        </li>
                      )
                    })
                  : none('No unlinked mentions.')}
              </ul>
              {linking?.error && linking.pageId === page.id && (
                <p className="kg-link-error" role="alert">
                  {linking.error}
                </p>
              )}
            </div>
          </div>
        )}

        {!editing && tab === 'topic' && (
          <div className="kg-cols">
            <div>
              <p className="kg-lbl">Topic</p>
              <p className="kg-summary">{topic ? topic.path : 'Unfiled: pages without a topic yet'}</p>
              {topic?.subjects && <p className="kg-row__sub">{topic.subjects}</p>}
              {topic && (
                <p className="kg-dlg__export">
                  <ExportButton request={{ scope: 'topic', topic: topic.id, ...src }} label="Export topic as Markdown" />
                </p>
              )}
              {subtopics.length > 0 && (
                <>
                  <p className="kg-lbl">Subtopics</p>
                  <ul className="kg-rows">
                    {subtopics.map((t) => (
                      <li key={t.id} className="kg-row__none">
                        {t.name} · {plural(t.pageCount, 'page')}
                      </li>
                    ))}
                  </ul>
                </>
              )}
            </div>
            <div>
              <p className="kg-lbl">Other pages in {topic?.name ?? 'Unfiled'}</p>
              <ul className="kg-rows">
                {topicPages.length
                  ? topicPages.slice(0, 60).map((id) => (
                      <li key={id} className="kg-row">
                        <div className="kg-row__sub">{index.pageById.get(id)!.links}</div>
                        {rowMain(id)}
                      </li>
                    ))
                  : none('No other pages here.')}
                {topicPages.length > 60 && none(`and ${topicPages.length - 60} more (List view shows all)`)}
              </ul>
            </div>
          </div>
        )}

        {!editing && tab === 'neighbourhood' && (
          <div>
            <p className="kg-lbl">Linked pages, strongest first</p>
            <ul className="kg-rows">
              {neighbours.length
                ? neighbours.map((id) => (
                    <li key={id} className="kg-row">
                      <Bars s={index.strengthBetween.get(id < page.id ? `${id}|${page.id}` : `${page.id}|${id}`) ?? 1} />
                      {rowMain(id, `${where(id)} · ${plural(index.neighbours.get(id)?.length ?? 0, 'linked page')}`)}
                    </li>
                  ))
                : none('No linked pages yet.')}
            </ul>
            <p className="kg-lbl">Two steps away</p>
            <p className="kg-row__sub">{second.size ? `${plural(second.size, 'page')} through these links.` : 'None.'}</p>
          </div>
        )}
      </div>

      <footer className="kg-dlg__foot">
        {/* A link page opens its own address first; OneNote is the second choice (operator, 2026-11-13:
            use OneNote as little as possible as the interface). */}
        {/* design: one primary per view. While the Edit form is open its Save is the primary, so the
            footer's goes quiet. */}
        {page.url && (
          <a className={editing ? 'btn' : 'btn btn--primary'} href={page.url} target="_blank" rel="noopener noreferrer" title={page.url}>
            Open link
          </a>
        )}
        {page.url ? (
          page.onenoteUrl && (
            <a className="btn" href={page.onenoteUrl}>
              Open in OneNote
            </a>
          )
        ) : page.onenoteUrl ? (
          <a className={editing ? 'btn' : 'btn btn--primary'} href={page.onenoteUrl}>
            Open in OneNote
          </a>
        ) : (
          <button type="button" className={editing ? 'btn' : 'btn btn--primary'} disabled>
            Open in OneNote
          </button>
        )}
        <button type="button" className="btn" onClick={() => onAsk?.(page)} disabled={!onAsk}>
          Ask about this
        </button>
        {ro && (
          // Shown, not hidden: a missing button gave no hint that pages can be edited at all, or why
          // not here. Focusable, so the reason is reachable by keyboard; it does nothing.
          <button type="button" className="btn" aria-disabled="true" aria-describedby="kg-dlg-why" title={why}>
            Edit
          </button>
        )}
        {onEditPage && !ro && (
          <button
            type="button"
            className="btn"
            aria-pressed={editing}
            onClick={() => {
              setTab('page')
              setEditing((e) => !e)
            }}
          >
            Edit
          </button>
        )}
        {/* Archive is the default way out of sight and can be undone; Delete asks too
            (FEASIBILITY.md "Archive and delete"). */}
        {onRetirePages && !ro && (
          <button type="button" className="btn" onClick={() => onRetirePages(page.archived ? 'restore' : 'archive', [page.id])}>
            {page.archived ? 'Restore' : 'Archive'}
          </button>
        )}
        {onRetirePages && !ro && (
          <button type="button" className="btn btn--danger" onClick={() => onRetirePages('delete', [page.id])}>
            Delete
          </button>
        )}
        {/* The two that leave the page (a file, the map) sit apart at the right, quiet. */}
        <span className="kg-dlg__side">
        <ExportButton request={{ scope: 'page', page: page.id, ...src }} label="Export as Markdown" className="btn btn--ghost" />
        {onFocusPage && (
          <button
            type="button"
            className="btn btn--ghost"
            title="Show only this page and its linked pages"
            onClick={() => {
              onFocusPage(page.id)
              ref.current?.close()
            }}
          >
            Focus on this page
          </button>
        )}
        </span>
        {ro && (
          <span id="kg-dlg-why" className="kg-dlg__why">
            {why}
          </span>
        )}
        <span className="kg-dlg__keys">
          Esc closes{pos ? ' · ← → previous or next linked page' : ''}
          {canGoBack(hist) || canGoForward(hist) ? ' · Alt+← → back or forward' : ''}
        </span>
      </footer>
    </dialog>
  )
}

