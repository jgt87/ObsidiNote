// "List": the same data as the map, as one table of all pages. The keyboard and screen-reader
// fallback for the graph; the search (and any filter) applies here too through `matches`.
// Sorting, grouping and counting are pure (table/tableModel.ts); this file holds the view state
// (in memory only) and renders.

import { useEffect, useMemo, useState } from 'react'
import { exportSourceOf } from '../export/exportApi'
import { plural } from './format'
import type { GraphIndex } from './graphIndex'
import type { GraphLayout } from './layout'
import { COLUMN_COUNT, TableGroupRows } from './table/TableGroupRows'
import { tagCounts } from './tags'
import { TagsRow } from './TagsRow'
import type { AddStatus } from '../add/types'
import { LinkUpdateBar } from './LinkUpdateBar'
import type { RetireAction } from './retireModel'
import { keepVisible, retireLabel, selectionParts, type SelectionParts } from './table/selectionModel'
import {
  ariaSort,
  buildTable,
  defaultOpenGroups,
  GROUP_BY_OPTIONS,
  nextSort,
  ROW_BUDGET,
  type GroupBy,
  type SortKey,
  type TableGroup,
  type TableSort,
} from './table/tableModel'
import './table/table.css'

interface Props {
  index: GraphIndex
  layout: GraphLayout
  matches: string[] | null
  onOpen: (id: string) => void
  /** Adds and removes tags on pages; with it the rows get a tick box and ticked rows a tag bar
   *  (a read-only source has none). */
  onTagPages?: (ids: string[], add: string[], remove: string[]) => Promise<unknown>
  /** A tag in the Tags column: shows that tag on the map (the Tags grouping). */
  onPickTag?: (tag: string) => void
  /** Archive / Restore / Delete of the ticked pages (the graph asks first, useRetireFlow). */
  onRetirePages?: (action: RetireAction, ids: string[]) => void
  /** Update of one link page's summary: "Update summaries" runs it for the ticked link pages. */
  onUpdateLink?: (id: string) => Promise<AddStatus>
}

const COLUMNS: { key: SortKey; label: string; className?: string }[] = [
  { key: 'title', label: 'Page', className: 'kg-tbl__c-page' },
  { key: 'type', label: 'Type', className: 'kg-tbl__c-type' },
  { key: 'topics', label: 'Topics', className: 'kg-tbl__c-topics' },
  { key: 'tags', label: 'Tags', className: 'kg-tbl__c-tags' },
  { key: 'site', label: 'Site', className: 'kg-tbl__c-site' },
  { key: 'links', label: 'Links', className: 'kg-tbl__c-links num' },
  { key: 'modified', label: 'Changed', className: 'kg-tbl__c-changed' },
]

function SortArrow({ dir }: { dir: 'ascending' | 'descending' | undefined }) {
  if (!dir) return null
  return (
    <svg className="kg-tbl__arrow" viewBox="0 0 16 16" aria-hidden="true">
      <path d={dir === 'ascending' ? 'M8 12V4M4.5 7.5L8 4l3.5 3.5' : 'M8 4v8M4.5 8.5L8 12l3.5-3.5'} fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export function GraphList({ index, layout, matches, onOpen, onTagPages, onPickTag, onRetirePages, onUpdateLink }: Props) {
  // A running "Update summaries" (the link pages ticked when it started); it stays while it runs.
  const [run, setRun] = useState<string[] | null>(null)
  const canSelect = !!(onTagPages || onRetirePages)
  const { selected, onSelect, clear } = useTicks(index, matches)
  const [groupBy, setGroupBy] = useState<GroupBy>('topic')
  const [sort, setSort] = useState<TableSort | null>(null)
  const table = useMemo(() => buildTable(index, layout.areas, matches, groupBy, sort), [index, layout, matches, groupBy, sort])

  return (
    <div className="kg-tbl">
      <ListBar groupBy={groupBy} onGroupBy={setGroupBy} total={table.total} sort={sort} onDefaultOrder={() => setSort(null)} />
      {canSelect && selected.size > 0 && (
        <SelectionBar index={index} selected={selected} running={run !== null} onClear={clear} onTagPages={onTagPages} onRetirePages={onRetirePages} onUpdate={onUpdateLink ? setRun : undefined} />
      )}
      {run && onUpdateLink && <LinkUpdateBar key={run.join(',')} ids={run} title={titleIn(index)} update={onUpdateLink} onClose={() => setRun(null)} />}
      <div className="kg-tbl__scroll">
        <table className="kg-tbl__table">
          <caption className="kg-sr">All pages of {sourceName(index)}. Column headers sort the table.</caption>
          <colgroup>
            {COLUMNS.map((c) => (
              <col key={c.key} className={c.className} />
            ))}
          </colgroup>
          <ListHead sort={sort} onSort={(key) => setSort((s) => nextSort(s, key))} />
          <ListGroups index={index} groups={table.groups} groupBy={groupBy} onOpen={onOpen} selected={selected} onSelect={canSelect ? onSelect : undefined} onPickTag={onPickTag} />
        </table>
      </div>
    </div>
  )
}

/** A page's title for the update bar; the id when the page is gone. */
const titleIn = (index: GraphIndex) => (id: string) => index.pageById.get(id)?.title ?? id

/** The source's name for the table's caption. */
const sourceName = (index: GraphIndex): string => index.model.source.name || 'this source'

/** Ticked rows, to act on several pages at once (session state). A ticked page that leaves the
 *  model, or that the search or a filter hides, is unticked (selectionModel.ts keepVisible). */
function useTicks(index: GraphIndex, matches: string[] | null) {
  const [selected, setSelected] = useState<ReadonlySet<string>>(new Set())
  useEffect(() => {
    setSelected((s) => keepVisible(s, (id) => index.pageById.has(id), matches))
  }, [index, matches])
  const onSelect = (id: string, on: boolean) =>
    setSelected((s) => {
      const next = new Set(s)
      if (on) next.add(id)
      else next.delete(id)
      return next
    })
  return { selected, onSelect, clear: () => setSelected(new Set()) }
}

/** The bar above the table: grouping, the page count (and sort), and the way back to the default order. */
function ListBar({ groupBy, onGroupBy, total, sort, onDefaultOrder }: { groupBy: GroupBy; onGroupBy: (g: GroupBy) => void; total: number; sort: TableSort | null; onDefaultOrder: () => void }) {
  const sortedLabel = sort ? COLUMNS.find((c) => c.key === sort.key)?.label : null
  return (
    <div className="kg-tbl__bar">
      <label className="kg-tbl__groupby">
        <span>Group by</span>
        <select className="field kg-tbl__select" value={groupBy} onChange={(e) => onGroupBy(e.target.value as GroupBy)}>
          {GROUP_BY_OPTIONS.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
      </label>
      <span className="kg-meta" role="status">
        {plural(total, 'page')}
        {sortedLabel ? `, sorted by ${sortedLabel.toLowerCase()}` : ''}
      </span>
      {sort && (
        <button type="button" className="btn btn--sm btn--ghost" onClick={onDefaultOrder}>
          Default order
        </button>
      )}
    </div>
  )
}

interface SelectionBarProps {
  index: GraphIndex
  selected: ReadonlySet<string>
  /** An "Update summaries" is running: the button waits for it. */
  running: boolean
  onClear: () => void
  onTagPages?: Props['onTagPages']
  onRetirePages?: Props['onRetirePages']
  /** Starts "Update summaries" for these link pages; without it the button is not offered. */
  onUpdate?: (ids: string[]) => void
}

/** The bar for the ticked rows: their tags, Update summaries, Archive / Restore / Delete, Clear. */
function SelectionBar({ index, selected, running, onClear, onTagPages, onRetirePages, onUpdate }: SelectionBarProps) {
  const allTags = useMemo(() => tagCounts(index.model.pages), [index])
  const parts = useMemo(() => selectionParts(selected, index.pageById), [selected, index])
  return (
    <div className="kg-tbl__sel" role="group" aria-label="Selected pages">
      <span className="kg-tbl__sel-count" role="status">
        {plural(selected.size, 'page')} selected
      </span>
      {onTagPages && <TagsRow tags={parts.tags} all={allTags} onChange={(add, remove) => onTagPages([...selected], add, remove)} label="Add a tag to the selected pages" />}
      {onUpdate && parts.links.length > 0 && (
        <button type="button" className="btn btn--sm" disabled={running} onClick={() => onUpdate(parts.links)}>
          Update summaries ({parts.links.length})
        </button>
      )}
      {onRetirePages && <RetireButtons parts={parts} all={[...selected]} onRetirePages={onRetirePages} />}
      <button type="button" className="btn btn--sm btn--ghost" onClick={onClear}>
        Clear selection
      </button>
    </div>
  )
}

/** Archive (the live pages), Restore (the archived ones) and Delete (every ticked page). */
function RetireButtons({ parts, all, onRetirePages }: { parts: SelectionParts; all: string[]; onRetirePages: (action: RetireAction, ids: string[]) => void }) {
  const { live, archived } = parts
  return (
    <>
      {live.length > 0 && (
        <button type="button" className="btn btn--sm" onClick={() => onRetirePages('archive', live)}>
          {retireLabel('Archive', live.length, archived.length)}
        </button>
      )}
      {archived.length > 0 && (
        <button type="button" className="btn btn--sm" onClick={() => onRetirePages('restore', archived)}>
          {retireLabel('Restore', archived.length, live.length)}
        </button>
      )}
      <button type="button" className="btn btn--sm btn--danger" onClick={() => onRetirePages('delete', all)}>
        Delete
      </button>
    </>
  )
}

/** The header row: every column header is a button that sorts by it (nextSort). */
function ListHead({ sort, onSort }: { sort: TableSort | null; onSort: (key: SortKey) => void }) {
  return (
    <thead>
      <tr>
        {COLUMNS.map((c) => {
          const dir = ariaSort(sort, c.key)
          return (
            <th key={c.key} scope="col" aria-sort={dir} className={HEAD_CLASS[c.key]}>
              <button type="button" className="kg-tbl__sort" onClick={() => onSort(c.key)}>
                {c.label}
                <SortArrow dir={dir} />
              </button>
            </th>
          )
        })}
      </tr>
    </thead>
  )
}

/** A header cell's own class: the number column aligns right, the page column has its own width. */
const HEAD_CLASS: Partial<Record<SortKey, string>> = { links: 'num', title: 'kg-tbl__page' }

interface ListGroupsProps {
  index: GraphIndex
  groups: TableGroup[]
  groupBy: GroupBy
  onOpen: (id: string) => void
  selected: ReadonlySet<string>
  onSelect?: (id: string, on: boolean) => void
  onPickTag?: (tag: string) => void
}

/** The groups of rows, or one line when nothing matches. Folding and "Show more" are keyed
 *  "<groupBy>:<group key>" and hold only what the person changed (in memory). */
function ListGroups({ index, groups, groupBy, onOpen, selected, onSelect, onPickTag }: ListGroupsProps) {
  const [folded, setFolded] = useState<Record<string, boolean>>({})
  const [limits, setLimits] = useState<Record<string, number>>({})
  const openByDefault = useMemo(() => defaultOpenGroups(groups), [groups])
  const src = exportSourceOf(index.model.source)
  if (groups.length === 0) {
    return (
      <tbody>
        <tr>
          <td colSpan={COLUMN_COUNT} className="kg-tbl__empty">
            No pages match.
          </td>
        </tr>
      </tbody>
    )
  }
  return groups.map((g) => {
    const k = `${groupBy}:${g.key}`
    const open = folded[k] === undefined ? openByDefault.has(g.key) : !folded[k]
    return (
      <TableGroupRows
        key={k}
        group={g}
        open={open}
        limit={limits[k] ?? ROW_BUDGET}
        exportRequest={groupBy === 'topic' && g.topicId ? { scope: 'topic', topic: g.topicId, ...src } : null}
        onToggle={() => setFolded((f) => ({ ...f, [k]: open }))}
        onMore={() => setLimits((l) => ({ ...l, [k]: (l[k] ?? ROW_BUDGET) + ROW_BUDGET }))}
        onOpen={onOpen}
        selected={selected}
        onSelect={onSelect}
        onPickTag={onPickTag}
      />
    )
  })
}
