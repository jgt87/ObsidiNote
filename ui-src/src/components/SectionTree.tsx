import { useState } from 'react'
import type { SectionNode } from '../api'
import { ChevronIcon } from './icons'

/** The notebook's sections and section groups with page counts; groups fold open and shut.
 *  design: a read-only list with disclosure buttons, not an ARIA tree: rows have no action yet,
 *  so there is nothing to select or open (the tree pattern comes with the central index). */
export function SectionTree({ nodes }: { nodes: SectionNode[] }) {
  if (!nodes.length) return <p className="rail__muted">No sections yet.</p>
  return (
    <ul className="tree">
      {nodes.map((n, i) => (
        <TreeItem key={`${n.kind}:${n.name}:${i}`} node={n} />
      ))}
    </ul>
  )
}

function TreeItem({ node }: { node: SectionNode }) {
  const [open, setOpen] = useState(true)
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
  if (node.kind !== 'group') {
    return (
      <li>
        <div className="tree__row">
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
          <ChevronIcon />
        </span>
        {label}
      </button>
      {open && node.children.length > 0 && (
        <ul className="tree tree--nested">
          {node.children.map((c, i) => (
            <TreeItem key={`${c.kind}:${c.name}:${i}`} node={c} />
          ))}
        </ul>
      )}
    </li>
  )
}
