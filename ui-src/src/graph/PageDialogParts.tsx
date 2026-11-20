// The parts of the page window (PageDialog.tsx): its header, the three tab panels and the footer.
// Render only; the window holds the state.
import type { ReactNode } from 'react'
import { WebLink } from '../components/WebLink'
import { ExportButton } from '../export/ExportButton'
import type { ExportRequest } from '../export/exportApi'
import { summaryProblem, titleProblem, type PageEditRequest } from './editModel'
import { InlineText } from './InlineText'
import { PageBody, type PageBodyResult } from './PageBody'
import { plural } from './format'
import { indexPath, type GraphIndex } from './graphIndex'
import { primaryTopic, type GraphEdge, type GraphPage } from './model'
import { openButtons, pageMetaLine, tabLabel, twoStepsAway, DIALOG_TABS, type DialogTab } from './pageDialogModel'
import type { RetireAction } from './retireModel'
import { tagCounts } from './tags'
import { TagsRow } from './TagsRow'

/** Which source an export reads (export/exportApi.ts exportSourceOf). */
type ExportSource = Pick<ExportRequest, 'vault' | 'notebook'>

export function Bars({ s }: { s: number }) {
  return (
    <div className="kg-bar" role="img" aria-label={`Strength ${s} of 3`}>
      {[1, 2, 3].map((i) => (
        <i key={i} className={i <= s ? 'on' : undefined} />
      ))}
    </div>
  )
}

/** Going to another page from a row, and what a row says about it. */
export interface RowNav {
  go: (id: string) => void
  title: (id: string) => string
  /** The page's topic path without "Index › ". */
  where: (id: string) => string
}

export function rowNav(index: GraphIndex, go: (id: string) => void): RowNav {
  return {
    go,
    title: (id) => index.pageById.get(id)?.title ?? id,
    where: (id) => {
      const p = index.pageById.get(id)
      return p ? indexPath(index, primaryTopic(p)).replace(/^Index › /, '') : ''
    },
  }
}

// design (review 2026-11-14): the page's name and its line under it are the button that opens it;
// the old target was a 27x17px "open" at the far end of the row.
function RowMain({ nav, id, sub }: { nav: RowNav; id: string; sub?: string }) {
  return (
    <button type="button" className="kg-rowbtn" onClick={() => nav.go(id)}>
      <span className="kg-rowbtn__title">{nav.title(id)}</span>
      {sub && <span className="kg-row__sub">{sub}</span>}
    </button>
  )
}

function LinkRow({ nav, e, other }: { nav: RowNav; e: GraphEdge; other: string }) {
  return (
    <li className="kg-row">
      <Bars s={e.strength} />
      <RowMain nav={nav} id={other} sub={[nav.where(other), e.reason].filter(Boolean).join(' · ')} />
    </li>
  )
}

const None = ({ text }: { text: string }) => <li className="kg-row__none">{text}</li>

export interface DialogHeaderProps {
  index: GraphIndex
  page: GraphPage
  /** Title saved where it stands, or null when it is not changed here. */
  inPlace: ((req: PageEditRequest) => Promise<unknown>) | null
  linksOut: number
  linkedFrom: number
  canBack: boolean
  canForward: boolean
  onBack: () => void
  onForward: () => void
  onClose: () => void
}

export function DialogHeader({ index, page, inPlace, linksOut, linkedFrom, canBack, canForward, onBack, onForward, onClose }: DialogHeaderProps) {
  return (
    <header className="kg-dlg__head">
      <div>
        <nav aria-label="Index path" className="kg-dlg__path">
          {indexPath(index, primaryTopic(page))}
        </nav>
        <h2 id="kg-dlg-title" className="kg-dlg__title">
          {inPlace ? <InlineText key={page.id} value={page.title} name="title" problem={titleProblem} onSave={(title) => inPlace({ id: page.id, title })} /> : page.title}
        </h2>
        <div className="kg-dlg__meta">
          <span>{pageMetaLine(page, linksOut, linkedFrom)}</span>
        </div>
      </div>
      <nav className="kg-dlg__hist" aria-label="Pages visited">
        <button type="button" className="btn btn--icon btn--ghost" aria-label="Back" title="Back (Alt+←)" disabled={!canBack} onClick={onBack}>
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
            <path d="M10 3L5 8l5 5" />
          </svg>
        </button>
        <button type="button" className="btn btn--icon btn--ghost" aria-label="Forward" title="Forward (Alt+→)" disabled={!canForward} onClick={onForward}>
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
            <path d="M6 3l5 5-5 5" />
          </svg>
        </button>
      </nav>
      <button type="button" className="btn btn--icon" aria-label="Close" onClick={onClose}>
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
          <path d="M4 4l8 8M12 4l-8 8" />
        </svg>
      </button>
    </header>
  )
}

export function DialogTabs({ tab, topicName, onTab }: { tab: DialogTab; topicName: string | undefined; onTab: (t: DialogTab) => void }) {
  return (
    <div role="tablist" aria-label="Page views" className="kg-tabs">
      {DIALOG_TABS.map((t) => (
        <button
          key={t}
          id={`kg-tab-${t}`}
          type="button"
          role="tab"
          className="kg-tab"
          data-label={tabLabel(t, topicName)}
          aria-selected={tab === t}
          aria-controls="kg-tabpanel"
          tabIndex={tab === t ? 0 : -1}
          onClick={() => onTab(t)}
        >
          {tabLabel(t, topicName)}
        </button>
      ))}
    </div>
  )
}

/** "link it" on a mention: which one is being linked (busy) and the last error, per page shown. */
export interface Linking {
  key: string
  error: string
  pageId: string
}

export interface PageTabProps {
  index: GraphIndex
  page: GraphPage
  nav: RowNav
  inPlace: ((req: PageEditRequest) => Promise<unknown>) | null
  out: GraphEdge[]
  back: GraphEdge[]
  mentions: GraphEdge[]
  readOnly: boolean
  onTagPages?: (ids: string[], add: string[], remove: string[]) => Promise<unknown>
  onPickTag?: (tag: string) => void
  loadBody?: (pageId: string, signal: AbortSignal) => Promise<PageBodyResult>
  onLinkMention?: (from: GraphPage, to: GraphPage) => void | Promise<unknown>
  linking: Linking | null
  setLinking: (l: Linking | null) => void
}

/** The Page tab: summary, tags, the page's own text and other topics | links out, linked from,
 *  mentions that are not links yet ("link it"). */
export function PageTab({ index, page, nav, inPlace, out, back, mentions, readOnly, onTagPages, onPickTag, loadBody, onLinkMention, linking, setLinking }: PageTabProps) {
  return (
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
          onChange={onTagPages && !readOnly ? (add, remove) => onTagPages([page.id], add, remove) : undefined}
          label={`Add a tag to ${page.title}`}
          onPick={onPickTag}
        />
        <p className="kg-lbl">Page content</p>
        {loadBody ? (
          <PageBody pageId={page.id} load={loadBody} hasPage={(id) => index.pageById.has(id)} onOpenPage={nav.go} />
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
        <ul className="kg-rows">{out.length ? out.map((e) => <LinkRow key={`${e.from}>${e.to}`} nav={nav} e={e} other={e.to} />) : <None text="No links out yet." />}</ul>
        <p className="kg-lbl">Linked from</p>
        <ul className="kg-rows">{back.length ? back.map((e) => <LinkRow key={`${e.from}>${e.to}`} nav={nav} e={e} other={e.from} />) : <None text="Nothing links here yet." />}</ul>
        <p className="kg-lbl">Mentions, not linked</p>
        <ul className="kg-rows">
          {mentions.length
            ? mentions.map((e) => <MentionRow key={`${e.from}>${e.to}`} index={index} page={page} nav={nav} e={e} readOnly={readOnly} onLinkMention={onLinkMention} linking={linking} setLinking={setLinking} />)
            : <None text="No unlinked mentions." />}
        </ul>
        {linking?.error && linking.pageId === page.id && (
          <p className="kg-link-error" role="alert">
            {linking.error}
          </p>
        )}
      </div>
    </div>
  )
}

function MentionRow({ index, page, nav, e, readOnly, onLinkMention, linking, setLinking }: Pick<PageTabProps, 'index' | 'page' | 'nav' | 'readOnly' | 'onLinkMention' | 'linking' | 'setLinking'> & { e: GraphEdge }) {
  const other = e.from === page.id ? e.to : e.from
  const key = `${e.from}>${e.to}`
  const busy = linking?.key === key && !linking.error
  const link = () => {
    if (!onLinkMention) return
    setLinking({ key, error: '', pageId: page.id })
    Promise.resolve(onLinkMention(page, index.pageById.get(other)!)).then(
      () => setLinking(null),
      (err: unknown) => setLinking({ key, pageId: page.id, error: err instanceof Error && err.message ? err.message : 'The link could not be added.' }),
    )
  }
  return (
    <li className="kg-row">
      <div className="kg-row__sub" aria-hidden="true">—</div>
      <RowMain nav={nav} id={other} sub={nav.where(other)} />
      {readOnly || !onLinkMention ? null : (
        <button type="button" className="kg-linkbtn kg-row__sub" aria-label={`Link it: ${nav.title(page.id)} and ${nav.title(other)}`} aria-busy={busy} disabled={!!linking && !linking.error} onClick={link}>
          {busy ? 'linking…' : 'link it'}
        </button>
      )}
    </li>
  )
}

/** The Topic tab: the page's topic (path, subjects, export, subtopics) | its other pages. */
export function TopicTab({ index, page, nav, src }: { index: GraphIndex; page: GraphPage; nav: RowNav; src: ExportSource }) {
  const topicId = primaryTopic(page)
  const topic = index.topicById.get(topicId)
  const topicPages = (index.pagesByArea.get(topicId) ?? []).filter((id) => id !== page.id)
  const subtopics = index.model.topics.filter((t) => t.parent === topicId)
  return (
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
                  <RowMain nav={nav} id={id} />
                </li>
              ))
            : <None text="No other pages here." />}
          {topicPages.length > 60 && <None text={`and ${topicPages.length - 60} more (List view shows all)`} />}
        </ul>
      </div>
    </div>
  )
}

/** The Neighbourhood tab: linked pages, strongest first, and how many are two steps away. */
export function NeighbourhoodTab({ index, page, nav }: { index: GraphIndex; page: GraphPage; nav: RowNav }) {
  const neighbours = index.neighbours.get(page.id) ?? []
  const second = twoStepsAway(index, page.id)
  return (
    <div>
      <p className="kg-lbl">Linked pages, strongest first</p>
      <ul className="kg-rows">
        {neighbours.length
          ? neighbours.map((id) => (
              <li key={id} className="kg-row">
                <Bars s={index.strengthBetween.get(id < page.id ? `${id}|${page.id}` : `${page.id}|${id}`) ?? 1} />
                <RowMain nav={nav} id={id} sub={`${nav.where(id)} · ${plural(index.neighbours.get(id)?.length ?? 0, 'linked page')}`} />
              </li>
            ))
          : <None text="No linked pages yet." />}
      </ul>
      <p className="kg-lbl">Two steps away</p>
      <p className="kg-row__sub">{second ? `${plural(second, 'page')} through these links.` : 'None.'}</p>
    </div>
  )
}

export interface DialogFooterProps {
  page: GraphPage
  editing: boolean
  readOnly: boolean
  why: string
  src: ExportSource
  onAsk?: (page: GraphPage, within?: { series: string; count: number }) => void
  /** How many meetings the page's series has (0: not a meeting of a series). */
  seriesCount?: number
  /** Edit is offered (the active vault's page with an edit action). */
  canEdit: boolean
  onToggleEdit: () => void
  onRetirePages?: (action: RetireAction, ids: string[]) => void
  /** "Merge duplicates" of the series (a series page only, with `copies` second copies of meetings). */
  onMergePages?: (series: string) => void
  copies?: number
  onFocusPage?: () => void
  /** The keys line: "Esc closes" and what the arrows do here. */
  keys: ReactNode
}

export function DialogFooter({ page, editing, readOnly, why, src, onAsk, seriesCount = 0, canEdit, onToggleEdit, onRetirePages, onMergePages, copies = 0, onFocusPage, keys }: DialogFooterProps) {
  const open = openButtons(page, editing)
  return (
    <footer className="kg-dlg__foot">
      {/* A link page opens its own address first; OneNote is the second choice (operator, 2026-11-13:
          use OneNote as little as possible as the interface). */}
      {/* design: one primary per view. While the Edit form is open its Save is the primary, so the
          footer's goes quiet. */}
      {open.link && (
        <WebLink className={open.link.primary ? 'btn btn--primary' : 'btn'} href={open.link.href} title={open.link.href}>
          Open link
        </WebLink>
      )}
      {open.onenote &&
        (open.onenote.href ? (
          <a className={open.onenote.primary ? 'btn btn--primary' : 'btn'} href={open.onenote.href}>
            Open in OneNote
          </a>
        ) : (
          <button type="button" className={open.onenote.primary ? 'btn btn--primary' : 'btn'} disabled>
            Open in OneNote
          </button>
        ))}
      <button type="button" className="btn" onClick={() => onAsk?.(page)} disabled={!onAsk}>
        Ask about this
      </button>
      {onAsk && page.series && seriesCount > 1 && (
        <button type="button" className="btn" onClick={() => onAsk(page, { series: page.series ?? '', count: seriesCount })}>
          Ask about this series
        </button>
      )}
      {/* The series page offers it only when a meeting of the series has a second copy (2026-11-19). */}
      {onMergePages && !readOnly && page.series && copies > 0 && (
        <button type="button" className="btn" onClick={() => onMergePages(page.series ?? '')}>
          Merge duplicates ({copies})
        </button>
      )}
      {readOnly && (
        // Shown, not hidden: a missing button gave no hint that pages can be edited at all, or why
        // not here. Focusable, so the reason is reachable by keyboard; it does nothing.
        <button type="button" className="btn" aria-disabled="true" aria-describedby="kg-dlg-why" title={why}>
          Edit
        </button>
      )}
      {canEdit && (
        <button type="button" className="btn" aria-pressed={editing} onClick={onToggleEdit}>
          Edit
        </button>
      )}
      {/* Archive is the default way out of sight and can be undone; Delete asks too
          (FEASIBILITY.md "Archive and delete"). */}
      {onRetirePages && !readOnly && (
        <button type="button" className="btn" onClick={() => onRetirePages(page.archived ? 'restore' : 'archive', [page.id])}>
          {page.archived ? 'Restore' : 'Archive'}
        </button>
      )}
      {onRetirePages && !readOnly && (
        <button type="button" className="btn btn--danger" onClick={() => onRetirePages('delete', [page.id])}>
          Delete
        </button>
      )}
      {/* The two that leave the page (a file, the map) sit apart at the right, quiet. */}
      <span className="kg-dlg__side">
        <ExportButton request={{ scope: 'page', page: page.id, ...src }} label="Export as Markdown" className="btn btn--ghost" />
        {onFocusPage && (
          <button type="button" className="btn btn--ghost" title="Show only this page and its linked pages" onClick={onFocusPage}>
            Focus on this page
          </button>
        )}
      </span>
      {readOnly && (
        <span id="kg-dlg-why" className="kg-dlg__why">
          {why}
        </span>
      )}
      {keys}
    </footer>
  )
}
