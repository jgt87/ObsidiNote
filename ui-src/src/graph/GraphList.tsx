// "List": the same data as the map, as tables per topic area. The keyboard and screen-reader
// fallback for the graph; the search filter applies here too.

import { formatDate } from './format'
import type { GraphIndex } from './graphIndex'
import type { GraphLayout } from './layout'

interface Props {
  index: GraphIndex
  layout: GraphLayout
  matches: string[] | null
  onOpen: (id: string) => void
}

export function GraphList({ index, layout, matches, onOpen }: Props) {
  const keep = matches ? new Set(matches) : null
  const areas = layout.areas
    .map((a) => ({ a, ids: [...a.pageIds].filter((id) => !keep || keep.has(id)) }))
    .filter((x) => x.ids.length > 0)
  if (!areas.length) return <p className="kg-meta">No pages match.</p>
  return (
    <div className="kg-list">
      {areas.map(({ a, ids }) => {
        ids.sort((x, y) => {
          const px = index.pageById.get(x)!
          const py = index.pageById.get(y)!
          return Number(py.isHub) - Number(px.isHub) || py.links - px.links || (px.title < py.title ? -1 : 1)
        })
        return (
          <section key={a.id} aria-labelledby={`kg-list-${a.id}`}>
            <h3 id={`kg-list-${a.id}`}>
              {a.topic?.path ?? a.name} <span>{a.sub}</span>
            </h3>
            <table className="kg-table">
              <thead>
                <tr>
                  <th scope="col">Page</th>
                  <th scope="col">Type</th>
                  <th scope="col" className="num">
                    Links
                  </th>
                  <th scope="col">Changed</th>
                </tr>
              </thead>
              <tbody>
                {ids.map((id) => {
                  const p = index.pageById.get(id)!
                  return (
                    <tr key={id}>
                      <td>
                        <button type="button" className="kg-linkbtn" onClick={() => onOpen(id)}>
                          {p.title}
                        </button>
                        {p.isHub && <span className="kg-tag"> · hub</span>}
                        {p.unlinked && <span className="kg-tag"> · no links yet</span>}
                        {p.readOnly && <span className="kg-tag"> · read only</span>}
                      </td>
                      <td className="kg-tag">{p.kind || p.bucket}</td>
                      <td className="num">{p.links}</td>
                      <td className="kg-tag">
                        <time dateTime={p.modified}>{formatDate(p.modified)}</time>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </section>
        )
      })}
    </div>
  )
}
