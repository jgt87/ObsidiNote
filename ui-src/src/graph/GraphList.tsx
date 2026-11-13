// "List": the same data as the map, as one table of all pages. The keyboard and screen-reader
// fallback for the graph; the search (and any filter) applies here too through `matches`.
// Sorting, grouping and counting are pure (table/tableModel.ts); this file holds the view state
// (in memory only) and renders.

import { useMemo, useState } from 'react'
import { exportSourceOf } from '../export/exportApi'
import { plural } from './format'
import type { GraphIndex } from './graphIndex'
import type { GraphLayout } from './layout'
import { COLUMN_COUNT, TableGroupRows } from './table/TableGroupRows'
import {
  ariaSort,
  buildTable,
  defaultOpenGroups,
  GROUP_BY_OPTIONS,
  nextSort,
  ROW_BUDGET,
  type GroupBy,
  type SortKey,
  type TableSort,
} from './table/tableModel'
import './table/table.css'

interface Props {
  index: GraphIndex
  layout: GraphLayout
  matches: string[] | null
  onOpen: (id: string) => void
}

const COLUMNS: { key: SortKey; label: string; className?: string }[] = [
  { key: 'title', label: 'Page', className: 'kg-tbl__c-page' },
  { key: 'type', label: 'Type', className: 'kg-tbl__c-type' },
  { key: 'topics', label: 'Topics', className: 'kg-tbl__c-topics' },
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

export function GraphList({ index, layout, matches, onOpen }: Props) {
  const [groupBy, setGroupBy] = useState<GroupBy>('topic')
  const [sort, setSort] = useState<TableSort | null>(null)
  // Folding and "Show more", keyed "<groupBy>:<group key>"; only what the person changed.
  const [folded, setFolded] = useState<Record<string, boolean>>({})
  const [limits, setLimits] = useState<Record<string, number>>({})

  const table = useMemo(() => buildTable(index, layout.areas, matches, groupBy, sort), [index, layout, matches, groupBy, sort])
  const openByDefault = useMemo(() => defaultOpenGroups(table.groups), [table])
  const src = exportSourceOf(index.model.source)
  const sortedLabel = sort ? COLUMNS.find((c) => c.key === sort.key)?.label : null

  return (
    <div className="kg-tbl">
      <div className="kg-tbl__bar">
        <label className="kg-tbl__groupby">
          <span>Group by</span>
          <select className="field kg-tbl__select" value={groupBy} onChange={(e) => setGroupBy(e.target.value as GroupBy)}>
            {GROUP_BY_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
        </label>
        <span className="kg-meta" role="status">
          {plural(table.total, 'page')}
          {sortedLabel ? `, sorted by ${sortedLabel.toLowerCase()}` : ''}
        </span>
        {sort && (
          <button type="button" className="btn btn--sm btn--ghost" onClick={() => setSort(null)}>
            Default order
          </button>
        )}
      </div>
      <div className="kg-tbl__scroll">
        <table className="kg-tbl__table">
          <caption className="kg-sr">All pages of {index.model.source.name || 'this source'}. Column headers sort the table.</caption>
          <colgroup>
            {COLUMNS.map((c) => (
              <col key={c.key} className={c.className} />
            ))}
          </colgroup>
          <thead>
            <tr>
              {COLUMNS.map((c) => {
                const dir = ariaSort(sort, c.key)
                return (
                  <th key={c.key} scope="col" aria-sort={dir} className={c.key === 'links' ? 'num' : c.key === 'title' ? 'kg-tbl__page' : undefined}>
                    <button type="button" className="kg-tbl__sort" onClick={() => setSort((s) => nextSort(s, c.key))}>
                      {c.label}
                      <SortArrow dir={dir} />
                    </button>
                  </th>
                )
              })}
            </tr>
          </thead>
          {table.groups.length === 0 ? (
            <tbody>
              <tr>
                <td colSpan={COLUMN_COUNT} className="kg-tbl__empty">
                  No pages match.
                </td>
              </tr>
            </tbody>
          ) : (
            table.groups.map((g) => {
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
                />
              )
            })
          )}
        </table>
      </div>
    </div>
  )
}
