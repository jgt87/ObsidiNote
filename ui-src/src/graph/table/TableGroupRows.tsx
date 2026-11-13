// One group of the List table: a heading row that folds the group, its rows, and "Show N more"
// when the group is longer than the row budget.

import { ExportButton } from '../../export/ExportButton'
import type { ExportRequest } from '../../export/exportApi'
import { formatDate, plural } from '../format'
import { ROW_BUDGET, type TableGroup, type TableRow } from './tableModel'

export const COLUMN_COUNT = 6

interface Props {
  group: TableGroup
  open: boolean
  limit: number
  /** Export request for a topic group; null hides the button. */
  exportRequest: ExportRequest | null
  onToggle: () => void
  onMore: () => void
  onOpen: (id: string) => void
}

function Chevron({ open }: { open: boolean }) {
  return (
    <svg className={`kg-tbl__chev${open ? ' is-open' : ''}`} viewBox="0 0 16 16" aria-hidden="true">
      <path d="M6 4l4 4-4 4" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function Row({ row, onOpen }: { row: TableRow; onOpen: (id: string) => void }) {
  const p = row.page
  const [first, ...rest] = row.topicNames
  return (
    <tr>
      <td className="kg-tbl__page">
        <div className="kg-tbl__title">
          <button type="button" className="kg-linkbtn" onClick={() => onOpen(row.id)} title={row.title}>
            {row.title}
          </button>
          {p.isHub && <span className="kg-tag"> · hub</span>}
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
      <td className="kg-tag" title={row.site || undefined}>
        {row.site}
      </td>
      <td className="num">{row.links}</td>
      <td className="kg-tag">{row.modified && <time dateTime={row.modified}>{formatDate(row.modified)}</time>}</td>
    </tr>
  )
}

export function TableGroupRows({ group, open, limit, exportRequest, onToggle, onMore, onOpen }: Props) {
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
        <Row key={row.id} row={row} onOpen={onOpen} />
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
