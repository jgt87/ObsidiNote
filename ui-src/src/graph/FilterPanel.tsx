// "Filter" next to the graph's chips: a small popover with type and topic checkboxes (with
// counts), "Only pages without links" and "Show archived"; and the one-line summary of what is
// active, with the focus steps toggle, "Show all" and "Clear". The rules are in filters.ts.

import { useEffect, useId, useMemo, useRef, useState } from 'react'
import { emptyFilter, filterOptions, isFilterActive, type FocusDepth, type GraphFilter } from './filters'
import { plural } from './format'
import type { GraphIndex } from './graphIndex'
import { UNFILED_ID } from './model'
import './FilterPanel.css'

interface PanelProps {
  index: GraphIndex
  filter: GraphFilter
  onChange: (f: GraphFilter) => void
}

function toggle(set: Set<string>, key: string): Set<string> {
  const next = new Set(set)
  if (next.has(key)) next.delete(key)
  else next.add(key)
  return next
}

/** Number of choices made in the panel (the button shows it). */
function choiceCount(f: GraphFilter): number {
  return f.types.size + f.topics.size + (f.unlinkedOnly ? 1 : 0) + (f.showArchived ? 1 : 0)
}

export function FilterButton({ index, filter, onChange }: PanelProps) {
  const [open, setOpen] = useState(false)
  const wrapRef = useRef<HTMLDivElement>(null)
  const buttonRef = useRef<HTMLButtonElement>(null)
  const panelRef = useRef<HTMLDivElement>(null)
  const panelId = useId()
  const options = useMemo(() => filterOptions(index, filter.showArchived), [index, filter.showArchived])
  const archived = useMemo(() => index.model.pages.filter((p) => p.archived).length, [index])
  const n = choiceCount(filter)

  const close = (refocus: boolean) => {
    setOpen(false)
    if (refocus) buttonRef.current?.focus()
  }

  // Open: focus the first box. Outside click or a wheel elsewhere closes it.
  useEffect(() => {
    if (!open) return
    panelRef.current?.querySelector<HTMLElement>('input')?.focus()
    const outside = (e: Event) => {
      if (!wrapRef.current?.contains(e.target as Node)) setOpen(false)
    }
    window.addEventListener('pointerdown', outside)
    window.addEventListener('wheel', outside, { passive: true })
    return () => {
      window.removeEventListener('pointerdown', outside)
      window.removeEventListener('wheel', outside)
    }
  }, [open])

  const box = (key: string, label: string, count: number | null, checked: boolean, onToggle: () => void, depth = 0) => (
    <label key={key} className="kg-fp__opt" data-depth={depth > 0 ? Math.min(depth, 4) : undefined}>
      <input type="checkbox" checked={checked} onChange={onToggle} />
      <span className="kg-fp__name">{label}</span>
      {count !== null && <span className="kg-fp__count">{count}</span>}
    </label>
  )

  return (
    <div
      ref={wrapRef}
      className="kg-fp"
      onKeyDown={(e) => {
        if (e.key === 'Escape' && open) {
          e.preventDefault()
          e.stopPropagation()
          close(true)
        }
      }}
      onBlur={(e) => {
        if (open && !wrapRef.current?.contains(e.relatedTarget as Node | null)) setOpen(false)
      }}
    >
      <button
        ref={buttonRef}
        type="button"
        className="btn btn--sm"
        aria-expanded={open}
        aria-controls={panelId}
        data-active={n > 0 || undefined}
        onClick={() => setOpen((o) => !o)}
      >
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
          <path d="M2 4h12M4.5 8h7M7 12h2" />
        </svg>
        Filter{n > 0 ? ` · ${n}` : ''}
      </button>
      <div ref={panelRef} id={panelId} className="kg-fp__panel" role="group" aria-label="Filter pages" hidden={!open}>
        <fieldset className="kg-fp__set">
          <legend>Type</legend>
          <div className="kg-fp__list">
            {options.types.length
              ? options.types.map((t) => box(`type:${t.key}`, t.key, t.count, filter.types.has(t.key), () => onChange({ ...filter, types: toggle(filter.types, t.key) })))
              : <p className="kg-fp__none">No pages.</p>}
          </div>
        </fieldset>
        <fieldset className="kg-fp__set">
          <legend>Topic</legend>
          <div className="kg-fp__list">
            {options.topics.length
              ? options.topics.map((t) =>
                  box(`topic:${t.id}`, t.id === UNFILED_ID ? 'Unfiled' : t.name, t.count, filter.topics.has(t.id), () => onChange({ ...filter, topics: toggle(filter.topics, t.id) }), t.depth),
                )
              : <p className="kg-fp__none">No topics yet.</p>}
          </div>
        </fieldset>
        <div className="kg-fp__set">
          {box('unlinked', 'Only pages without links', null, filter.unlinkedOnly, () => onChange({ ...filter, unlinkedOnly: !filter.unlinkedOnly }))}
          {box('archived', 'Show archived', archived, filter.showArchived, () => onChange({ ...filter, showArchived: !filter.showArchived }))}
        </div>
        <div className="kg-fp__foot">
          <button type="button" className="btn btn--sm btn--ghost" disabled={!isFilterActive(filter)} onClick={() => onChange(emptyFilter())}>
            Clear filters
          </button>
          <button type="button" className="btn btn--sm" onClick={() => close(true)}>
            Done
          </button>
        </div>
      </div>
    </div>
  )
}

interface SummaryProps extends PanelProps {
  shown: number
}

/** The active filters in one line; nothing when only the default (archived hidden) applies. */
export function FilterSummary({ index, filter, onChange, shown }: SummaryProps) {
  if (!isFilterActive(filter)) return null
  const topicName = (id: string) => (id === UNFILED_ID ? 'Unfiled' : index.topicById.get(id)?.name ?? id)
  const parts: string[] = []
  if (filter.types.size) parts.push(`type: ${[...filter.types].join(', ')}`)
  if (filter.topics.size) parts.push(`topic: ${[...filter.topics].map(topicName).join(', ')}`)
  if (filter.unlinkedOnly) parts.push('without links')
  if (filter.showArchived) parts.push('archived shown')
  const focusPage = filter.focus ? index.pageById.get(filter.focus.id) : undefined
  const setDepth = (depth: FocusDepth) => filter.focus && onChange({ ...filter, focus: { ...filter.focus, depth } })
  return (
    <div className="kg-fsum" role="status">
      <span className="kg-fsum__count">
        Showing {shown} of {plural(index.model.pages.length, 'page')}
      </span>
      {focusPage && filter.focus && (
        <span className="kg-fsum__focus">
          <span>
            Around <b>{focusPage.title}</b>
          </span>
          <span className="kg-seg" role="group" aria-label="Link steps">
            {([1, 2] as const).map((d) => (
              <button key={d} type="button" className="btn btn--sm" aria-pressed={filter.focus!.depth === d} onClick={() => setDepth(d)}>
                {d === 1 ? '1 step' : '2 steps'}
              </button>
            ))}
          </span>
          <button type="button" className="kg-linkbtn" onClick={() => onChange({ ...filter, focus: null })}>
            Show all
          </button>
        </span>
      )}
      {parts.length > 0 && <span className="kg-fsum__parts">Filters: {parts.join(' · ')}</span>}
      <button type="button" className="kg-linkbtn" onClick={() => onChange(emptyFilter())}>
        Clear
      </button>
    </div>
  )
}
