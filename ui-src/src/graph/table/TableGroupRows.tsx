// One group of the List table: a heading row that folds the group, its rows, and "Show N more"
// when the group is longer than the row budget.

import { ExportButton } from '../../export/ExportButton'
import type { ExportRequest } from '../../export/exportApi'
import { formatDate, plural } from '../format'
import { ROW_BUDGET, type TableGroup, type TableRow } from './tableModel'
import { Icon } from '../../components/icons'

export const COLUMN_COUNT = 7

interface Props {
  group: TableGroup
  open: boolean
  limit: number
  /** Export request for a topic group; null hides the button. */
  exportRequest: ExportRequest | null
  onToggle: () => void
  onMore: () => void
  onOpen: (id: string) => void
  /** Ticked rows (ids), and the tick handler; without it the rows have no tick box (read only). */
  selected?: ReadonlySet<string>
  onSelect?: (id: string, on: boolean) => void
  /** A tag in the Tags column was clicked. */
  onPickTag?: (tag: string) => void
}

function Chevron({ open }: { open: boolean }) {
  return (
    <Icon name="chevron" className={`kg-tbl__chev${open ? ' is-open' : ''}`} />
  )
}

function Row({ row, onOpen, selected, onSelect, onPickTag }: { row: TableRow; onOpen: (id: string) => void; selected: boolean; onSelect?: (id: string, on: boolean) => void; onPickTag?: (tag: string) => void }) {
  const p = row.page
  const [first, ...rest] = row.topicNames
  return (
    <tr data-selected={selected || undefined}>
      <td className="kg-tbl__page">
        <div className="kg-tbl__title">
          {onSelect && <input type="checkbox" className="kg-tbl__tick" checked={selected} aria-label={`Select ${row.title}`} onChange={(e) => onSelect(row.id, e.target.checked)} />}
          <button type="button" className="kg-linkbtn" onClick={() => onOpen(row.id)} title={row.title}>
            {row.title}
          </button>
          {p.isHub && <span className="kg-tag"> · most linked</span>}
          {p.unlinked && <span className="kg-tag"> · no links yet</span>}
          {p.archived && <span className="kg-tag"> · archived</span>}
          {p.readOnly && <span className="kg-tag"> · read only</span>}
        </div>
      </td>
      <td className="kg-tag" title={row.type || undefined}>
        {row.type}
      </td>
      <td title={row.topicPaths.length ? row.topicPaths.join(', ') : undefined}>
        {first ?? ''}
        {rest.length > 0 && <span className="kg-tag"> +{rest.length}</span>}
      </td>
      <td className="kg-tag" title={row.tags.length ? row.tags.join(', ') : undefined}>
        {onPickTag
          ? row.tags.map((t, i) => (
              <span key={t}>
                {i > 0 && ', '}
                <button type="button" className="kg-linkbtn" onClick={() => onPickTag(t)} title={`Show the pages tagged “${t}” on the map`}>
                  {t}
                </button>
              </span>
            ))
          : row.tags.join(', ')}
      </td>
      <td className="kg-tag" title={row.site || undefined}>
        {row.site}
      </td>
      <td className="num">{row.links}</td>
      <td className="kg-tag">{row.modified && <time dateTime={row.modified}>{formatDate(row.modified)}</time>}</td>
    </tr>
  )
}

export function TableGroupRows({ group, open, limit, exportRequest, onToggle, onMore, onOpen, selected, onSelect, onPickTag }: Props) {
  const shown = open ? group.rows.slice(0, limit) : []
  const hidden = group.rows.length - shown.length
  return (
    <tbody>
      <tr className="kg-tbl__group">
        <th scope="rowgroup" colSpan={COLUMN_COUNT}>
          <div className="kg-tbl__grouphead">
            <button type="button" className="kg-tbl__fold" aria-expanded={open} onClick={onToggle}>
              <Chevron open={open} />
              <span className="kg-tbl__groupname">{group.name}</span>
              <span className="kg-tbl__count">{plural(group.rows.length, 'page')}</span>
            </button>
            {exportRequest && <ExportButton request={exportRequest} label="Export as Markdown" className="kg-linkbtn" />}
          </div>
        </th>
      </tr>
      {shown.map((row) => (
        <Row key={row.id} row={row} onOpen={onOpen} selected={selected?.has(row.id) ?? false} onSelect={onSelect} onPickTag={onPickTag} />
      ))}
      {open && hidden > 0 && (
        <tr className="kg-tbl__more">
          <td colSpan={COLUMN_COUNT}>
            <button type="button" className="kg-linkbtn" onClick={onMore}>
              Show {Math.min(ROW_BUDGET, hidden).toLocaleString('en-GB')} more
            </button>
            <span className="kg-tag"> · {hidden.toLocaleString('en-GB')} not shown</span>
          </td>
        </tr>
      )}
    </tbody>
  )
}
