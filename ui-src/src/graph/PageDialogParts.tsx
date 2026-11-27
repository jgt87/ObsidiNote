// The parts of the page window (PageDialog.tsx): its header and the three tab panels; the footer is
// in PageDialogFooter.tsx. Render only; the window holds the state.
import { BusyLabel } from '../components/BusyLabel'
import { unavailable } from '../components/disabledGuard'
import { ExportButton } from '../export/ExportButton'
import { summaryProblem, titleProblem, type PageEditRequest } from './editModel'
import { InlineText } from './InlineText'
import { PageBody, type PageBodyResult } from './PageBody'
import { plural } from './format'
import { indexPath, type GraphIndex } from './graphIndex'
import { primaryTopic, type GraphEdge, type GraphPage, type GraphTopic } from './model'
import { pageMetaLine, tabLabel, twoStepsAway, DIALOG_TABS, type DialogTab } from './pageDialogModel'
import type { ExportSource } from './PageDialogFooter'
import { tagCounts } from './tags'
import { TagsRow } from './TagsRow'
import { Icon } from '../components/icons'


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
        <button type="button" className="btn btn--icon btn--ghost" aria-label="Back" title="Back (Alt+←)" {...unavailable(!canBack)} onClick={onBack}>
          <Icon name="back" />
        </button>
        <button type="button" className="btn btn--icon btn--ghost" aria-label="Forward" title="Forward (Alt+→)" {...unavailable(!canForward)} onClick={onForward}>
          <Icon name="forward" />
        </button>
      </nav>
      <button type="button" className="btn btn--icon" aria-label="Close" onClick={onClose}>
        <Icon name="close" />
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
        <SummaryText page={page} inPlace={inPlace} />
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
        <PageContent index={index} page={page} nav={nav} loadBody={loadBody} />
        <AlsoUnder index={index} page={page} />
      </div>
      <div>
        <p className="kg-lbl">Links out</p>
        <LinkList nav={nav} edges={out} other="to" none="No links out yet." />
        <p className="kg-lbl">Linked from</p>
        <LinkList nav={nav} edges={back} other="from" none="Nothing links here yet." />
        <p className="kg-lbl">Mentions, not linked</p>
        <MentionList index={index} page={page} nav={nav} mentions={mentions} readOnly={readOnly} onLinkMention={onLinkMention} linking={linking} setLinking={setLinking} />
      </div>
    </div>
  )
}

/** The summary: changed where it stands when it can be, else the text (or that there is none). */
function SummaryText({ page, inPlace }: Pick<PageTabProps, 'page' | 'inPlace'>) {
  return (
    <p className="kg-summary">
      {inPlace ? (
        <InlineText key={page.id} value={page.summary} name="summary" empty="No summary yet." multiline problem={summaryProblem} onSave={(summary) => inPlace({ id: page.id, summary })} />
      ) : (
        page.summary || 'No summary yet.'
      )}
    </p>
  )
}

/** The page's own text when it can be read here, else where it is. */
function PageContent({ index, page, nav, loadBody }: Pick<PageTabProps, 'index' | 'page' | 'nav' | 'loadBody'>) {
  return loadBody ? (
    <PageBody pageId={page.id} load={loadBody} hasPage={(id) => index.pageById.has(id)} onOpenPage={nav.go} />
  ) : (
    <p className="kg-note">The page text stays in OneNote: open it there to read or edit it, or export a copy as Markdown.</p>
  )
}

/** The page's other topics, after its first; nothing for a page under one topic. */
function AlsoUnder({ index, page }: Pick<PageTabProps, 'index' | 'page'>) {
  if (page.topicIds.length <= 1) return null
  return (
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
  )
}

/** Links of the page, one row each, named by the page at their `other` end; `none` when there are none. */
function LinkList({ nav, edges, other, none }: { nav: RowNav; edges: GraphEdge[]; other: 'to' | 'from'; none: string }) {
  return <ul className="kg-rows">{edges.length ? edges.map((e) => <LinkRow key={`${e.from}>${e.to}`} nav={nav} e={e} other={e[other]} />) : <None text={none} />}</ul>
}

/** Mentions that are not links yet, each with "link it", and why the last "link it" failed. */
function MentionList({ mentions, ...row }: Pick<PageTabProps, 'index' | 'page' | 'nav' | 'mentions' | 'readOnly' | 'onLinkMention' | 'linking' | 'setLinking'>) {
  const { page, linking } = row
  return (
    <>
      <ul className="kg-rows">
        {mentions.length
          ? mentions.map((e) => <MentionRow key={`${e.from}>${e.to}`} {...row} e={e} />)
          : <None text="No unlinked mentions." />}
      </ul>
      {linking?.error && linking.pageId === page.id && (
        <p className="kg-link-error" role="alert">
          {linking.error}
        </p>
      )}
    </>
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
        <button type="button" className="kg-linkbtn kg-row__sub" aria-label={`Link it: ${nav.title(page.id)} and ${nav.title(other)}`} aria-busy={busy} {...unavailable(!!linking && !linking.error)} onClick={link}>
          <BusyLabel label="link it" busyText="linking…" />
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
        <TopicAbout topic={topic} src={src} />
        <SubtopicList subtopics={subtopics} />
      </div>
      <div>
        <p className="kg-lbl">Other pages in {topic?.name ?? 'Unfiled'}</p>
        <TopicPages index={index} nav={nav} ids={topicPages} />
      </div>
    </div>
  )
}

/** The topic's path and subjects, and its export; for a page without a topic, that it is Unfiled. */
function TopicAbout({ topic, src }: { topic: GraphTopic | undefined; src: ExportSource }) {
  return (
    <>
      <p className="kg-lbl">Topic</p>
      <p className="kg-summary">{topic ? topic.path : 'Unfiled: pages without a topic yet'}</p>
      {topic?.subjects && <p className="kg-row__sub">{topic.subjects}</p>}
      {topic && (
        <p className="kg-dlg__export">
          <ExportButton request={{ scope: 'topic', topic: topic.id, ...src }} label="Export topic as Markdown" />
        </p>
      )}
    </>
  )
}

function SubtopicList({ subtopics }: { subtopics: GraphTopic[] }) {
  if (!subtopics.length) return null
  return (
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
  )
}

/** The topic's other pages, the first 60, then how many more the List shows. */
function TopicPages({ index, nav, ids }: { index: GraphIndex; nav: RowNav; ids: string[] }) {
  return (
    <ul className="kg-rows">
      {ids.length
        ? ids.slice(0, 60).map((id) => (
            <li key={id} className="kg-row">
              <div className="kg-row__sub">{index.pageById.get(id)!.links}</div>
              <RowMain nav={nav} id={id} />
            </li>
          ))
        : <None text="No other pages here." />}
      {ids.length > 60 && <None text={`and ${ids.length - 60} more (List view shows all)`} />}
    </ul>
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

// The footer has its own file; its names stay importable from here.
export { DialogFooter, type DialogFooterProps } from './PageDialogFooter'
