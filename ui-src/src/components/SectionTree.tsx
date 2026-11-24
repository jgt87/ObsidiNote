import { useState } from 'react'
import type { SectionNode } from '../api'
import { sectionQuery } from '../model/sections'
import { Icon } from './icons'

/** The notebook's sections and section groups with page counts; groups fold open and shut.
 *  A section row opens the knowledge graph's List on that section's pages (review 2026-11-14: the
 *  rows looked like navigation and did nothing). Sections whose pages are not in the graph (Index,
 *  Intake, Archive) stay plain text. design: a list with buttons, not an ARIA tree. */
export function SectionTree({ nodes, onOpen, vault = false }: { nodes: SectionNode[]; onOpen?: (query: string) => void; /** The notebook is an ObsidiNote vault (its Index, Intake and Archive are not in the graph). */ vault?: boolean }) {
  if (!nodes.length) return <p className="rail__muted">No sections yet.</p>
  return (
    <ul className="tree">
      {nodes.map((n, i) => (
        <TreeItem key={`${n.kind}:${n.name}:${i}`} node={n} path={[n.name]} onOpen={onOpen} vault={vault} />
      ))}
    </ul>
  )
}

function TreeItem({ node, path, onOpen, vault }: { node: SectionNode; path: string[]; onOpen?: (query: string) => void; vault: boolean }) {
  const [open, setOpen] = useState(true)
  const query = node.kind !== 'group' && onOpen ? sectionQuery(path, vault) : null
  const label = (
    <>
      <span className="tree__name" title={node.name}>
        {node.name}
      </span>
      <span className="tree__count num" aria-label={`${node.pages} pages`}>
        {node.pages}
      </span>
    </>
  )
  if (query && onOpen) {
    return (
      <li>
        <button type="button" className="tree__row tree__toggle" onClick={() => onOpen(query)} title={`List the pages in ${path.join(' / ')}`}>
          <span className="tree__chev" aria-hidden="true" />
          {label}
        </button>
      </li>
    )
  }
  if (node.kind !== 'group') {
    return (
      <li>
        <div className="tree__row tree__row--plain">
          <span className="tree__chev" aria-hidden="true" />
          {label}
        </div>
      </li>
    )
  }
  return (
    <li>
      <button type="button" className="tree__row tree__toggle" aria-expanded={open} onClick={() => setOpen(!open)}>
        <span className="tree__chev" data-open={open}>
          <Icon name="chevron" />
        </span>
        {label}
      </button>
      {open && node.children.length > 0 && (
        <ul className="tree tree--nested">
          {node.children.map((c, i) => (
            <TreeItem key={`${c.kind}:${c.name}:${i}`} node={c} path={[...path, c.name]} onOpen={onOpen} vault={vault} />
          ))}
        </ul>
      )}
    </li>
  )
}
