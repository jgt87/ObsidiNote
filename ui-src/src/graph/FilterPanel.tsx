// "Filter" next to the graph's chips: a small popover with type and topic checkboxes (with
// counts), "Only pages without links", "Link summaries older than N days" and "Show archived"; and the one-line summary of what is
// active, with the focus steps toggle, "Show all" and "Clear". The rules are in filters.ts.

import { useEffect, useId, useMemo, useRef, useState, type FocusEvent, type KeyboardEvent, type ReactNode } from 'react'
import { duplicateIds } from './duplicates'
import { emptyFilter, filterOptions, filterParts, isFilterActive, type FocusDepth, type GraphFilter } from './filters'
import { plural } from './format'
import type { GraphIndex } from './graphIndex'
import { isLinkPage, isStale, staleCutoff } from './linkUpdateRun'
import { UNFILED_ID } from './model'
import './FilterPanel.css'

interface PanelProps {
  index: GraphIndex
  filter: GraphFilter
  onChange: (f: GraphFilter) => void
}

/** What the map draws (not which pages): the panel's first group, on the map only. */
export interface MapShow {
  links: boolean
  mentions: boolean
  hubsOnly: boolean
}

interface ButtonProps extends PanelProps {
  /** With these the panel starts with "Show on the map" (design round 2, 2026-11-15: the three
   *  switches left the toolbar, which keeps grouping, search, Filter and Graph/List). */
  show?: MapShow
  onShow?: (key: keyof MapShow, value: boolean) => void
  /** The vault's linkStaleDays: "Link summaries older than N days" (FEASIBILITY.md, Links). */
  staleDays?: number
}

function toggle(set: Set<string>, key: string): Set<string> {
  const next = new Set(set)
  if (next.has(key)) next.delete(key)
  else next.add(key)
  return next
}

/** Number of choices made in the panel (the button shows it). */
function choiceCount(f: GraphFilter): number {
  return f.types.size + f.topics.size + f.tags.size + (f.unlinkedOnly ? 1 : 0) + (f.duplicatesOnly ? 1 : 0) + (f.showArchived ? 1 : 0) + (f.staleBefore !== null ? 1 : 0)
}

/**
 * The panel's open state. Opening focuses its first box; a click or a wheel outside it, or the focus
 * leaving it, closes it; Esc closes it and puts the focus back on the button.
 */
function usePopover() {
  const [open, setOpen] = useState(false)
  const wrapRef = useRef<HTMLDivElement>(null)
  const buttonRef = useRef<HTMLButtonElement>(null)
  const panelRef = useRef<HTMLDivElement>(null)
  const close = (refocus: boolean) => {
    setOpen(false)
    if (refocus) buttonRef.current?.focus()
  }
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
  const wrapHandlers = {
    onKeyDown: (e: KeyboardEvent<HTMLDivElement>) => {
      if (e.key === 'Escape' && open) {
        e.preventDefault()
        e.stopPropagation()
        close(true)
      }
    },
    onBlur: (e: FocusEvent<HTMLDivElement>) => {
      if (open && !wrapRef.current?.contains(e.relatedTarget as Node | null)) setOpen(false)
    },
  }
  return { open, toggle: () => setOpen((o) => !o), close, wrapRef, buttonRef, panelRef, wrapHandlers }
}

/** How many pages each page-level choice would count: archived ones, and link pages whose summary
 *  is older than staleDays (among the pages shown); whether there are link pages at all. */
function usePageCounts(index: GraphIndex, staleDays: number, showArchived: boolean) {
  const archived = useMemo(() => index.model.pages.filter((p) => p.archived).length, [index])
  const hasLinks = useMemo(() => index.model.pages.some(isLinkPage), [index])
  const stale = useMemo(() => {
    const cut = staleCutoff(staleDays, Date.now())
    return index.model.pages.filter((p) => (showArchived || !p.archived) && isStale(p, cut)).length
  }, [index, staleDays, showArchived])
  const duplicates = useMemo(() => duplicateIds(index.model.pages, showArchived).size, [index, showArchived])
  return { archived, hasLinks, stale, duplicates }
}

/** One checkbox row: its name, a count when there is one, indented by topic depth (at most 4). */
function Box({ label, count = null, checked, onToggle, depth = 0 }: { label: string; count?: number | null; checked: boolean; onToggle: () => void; depth?: number }) {
  return (
    <label className="kg-fp__opt" data-depth={depth > 0 ? Math.min(depth, 4) : undefined}>
      <input type="checkbox" checked={checked} onChange={onToggle} />
      <span className="kg-fp__name">{label}</span>
      {count !== null && <span className="kg-fp__count">{count}</span>}
    </label>
  )
}

/** A titled group of boxes; `none` stands in for an empty group. */
function BoxSet({ legend, none, children }: { legend: string; none?: string; children: ReactNode[] }) {
  return (
    <fieldset className="kg-fp__set">
      <legend>{legend}</legend>
      <div className="kg-fp__list">{children.length || none === undefined ? children : <p className="kg-fp__none">{none}</p>}</div>
    </fieldset>
  )
}

const SHOW_BOXES: [keyof MapShow, string][] = [['links', 'Links'], ['mentions', 'Mentions, not linked'], ['hubsOnly', 'Labels: hubs only']]

export function FilterButton({ index, filter, onChange, show, onShow, staleDays = 90 }: ButtonProps) {
  const pop = usePopover()
  const panelId = useId()
  const options = useMemo(() => filterOptions(index, filter.showArchived), [index, filter.showArchived])
  const counts = usePageCounts(index, staleDays, filter.showArchived)
  const n = choiceCount(filter)
  const set = (patch: Partial<GraphFilter>) => onChange({ ...filter, ...patch })

  return (
    <div ref={pop.wrapRef} className="kg-fp" {...pop.wrapHandlers}>
      <button ref={pop.buttonRef} type="button" className="btn btn--sm" aria-expanded={pop.open} aria-controls={panelId} data-active={n > 0 || undefined} onClick={pop.toggle}>
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
          <path d="M2 4h12M4.5 8h7M7 12h2" />
        </svg>
        Filter{n > 0 ? ` · ${n}` : ''}
      </button>
      <div ref={pop.panelRef} id={panelId} className="kg-fp__panel" role="group" aria-label="Filter pages" hidden={!pop.open}>
        <ShowBoxes show={show} onShow={onShow} />
        <BoxSet legend="Type" none="No pages.">
          {options.types.map((t) => <Box key={`type:${t.key}`} label={t.key} count={t.count} checked={filter.types.has(t.key)} onToggle={() => set({ types: toggle(filter.types, t.key) })} />)}
        </BoxSet>
        <BoxSet legend="Topic" none="No topics yet.">
          {options.topics.map((t) => (
            <Box key={`topic:${t.id}`} label={t.id === UNFILED_ID ? 'Unfiled' : t.name} count={t.count} checked={filter.topics.has(t.id)} onToggle={() => set({ topics: toggle(filter.topics, t.id) })} depth={t.depth} />
          ))}
        </BoxSet>
        {options.tags.length > 0 && (
          <BoxSet legend="Tag">
            {options.tags.map((t) => <Box key={`tag:${t.name}`} label={t.name} count={t.count} checked={filter.tags.has(t.name)} onToggle={() => set({ tags: toggle(filter.tags, t.name) })} />)}
          </BoxSet>
        )}
        <PageStateBoxes filter={filter} set={set} counts={counts} staleDays={staleDays} />
        <div className="kg-fp__foot">
          <button type="button" className="btn btn--sm btn--ghost" disabled={!isFilterActive(filter)} onClick={() => onChange(emptyFilter())}>
            Clear filters
          </button>
          <button type="button" className="btn btn--sm" onClick={() => pop.close(true)}>
            Done
          </button>
        </div>
      </div>
    </div>
  )
}

/** "Show on the map": what the map draws (graph mode only; the List has no such choices). */
function ShowBoxes({ show, onShow }: { show?: MapShow; onShow?: ButtonProps['onShow'] }) {
  if (!show || !onShow) return null
  return (
    <BoxSet legend="Show on the map">
      {SHOW_BOXES.map(([key, label]) => <Box key={`show:${key}`} label={label} checked={show[key]} onToggle={() => onShow(key, !show[key])} />)}
    </BoxSet>
  )
}

/** Pages by state: without links, link summaries past the vault's `linkStaleDays` (only when
 *  there are link pages), and archived pages. */
function PageStateBoxes({ filter, set, counts, staleDays }: { filter: GraphFilter; set: (patch: Partial<GraphFilter>) => void; counts: ReturnType<typeof usePageCounts>; staleDays: number }) {
  const stale = filter.staleBefore !== null
  return (
    <div className="kg-fp__set">
      <Box label="Only pages without links" checked={filter.unlinkedOnly} onToggle={() => set({ unlinkedOnly: !filter.unlinkedOnly })} />
      {(counts.duplicates > 0 || filter.duplicatesOnly) && (
        <Box label="Possible duplicates (same title or alias)" count={counts.duplicates} checked={filter.duplicatesOnly} onToggle={() => set({ duplicatesOnly: !filter.duplicatesOnly })} />
      )}
      {counts.hasLinks && (
        <Box label={`Link summaries older than ${staleDays} days`} count={counts.stale} checked={stale} onToggle={() => set({ staleBefore: stale ? null : staleCutoff(staleDays, Date.now()) })} />
      )}
      <Box label="Show archived" count={counts.archived} checked={filter.showArchived} onToggle={() => set({ showArchived: !filter.showArchived })} />
    </div>
  )
}

interface SummaryProps extends PanelProps {
  shown: number
}

/** The active filters in one line; nothing when only the default (archived hidden) applies. */
export function FilterSummary({ index, filter, onChange, shown }: SummaryProps) {
  if (!isFilterActive(filter)) return null
  const parts = filterParts(filter, (id) => (id === UNFILED_ID ? 'Unfiled' : index.topicById.get(id)?.name ?? id))
  return (
    <div className="kg-fsum" role="status">
      <span className="kg-fsum__count">
        Showing {shown} of {plural(index.model.pages.length, 'page')}
      </span>
      <FocusSteps index={index} filter={filter} onChange={onChange} />
      {parts.length > 0 && <span className="kg-fsum__parts">Filters: {parts.join(' · ')}</span>}
      <button type="button" className="kg-linkbtn" onClick={() => onChange(emptyFilter())}>
        Clear
      </button>
    </div>
  )
}

/** "Around <page>": one or two link steps, and "Show all"; nothing without a focus on a page that
 *  is in the graph. */
function FocusSteps({ index, filter, onChange }: PanelProps) {
  const focus = filter.focus
  const focusPage = focus ? index.pageById.get(focus.id) : undefined
  if (!focus || !focusPage) return null
  const setDepth = (depth: FocusDepth) => onChange({ ...filter, focus: { ...focus, depth } })
  return (
    <span className="kg-fsum__focus">
      <span>
        Around <b>{focusPage.title}</b>
      </span>
      <span className="seg seg--sm" role="group" aria-label="Link steps">
        {([1, 2] as const).map((d) => (
          <button key={d} type="button" className="seg__btn" data-label={d === 1 ? '1 step' : '2 steps'} aria-pressed={focus.depth === d} onClick={() => setDepth(d)}>
            {d === 1 ? '1 step' : '2 steps'}
          </button>
        ))}
      </span>
      <button type="button" className="kg-linkbtn" onClick={() => onChange({ ...filter, focus: null })}>
        Show all
      </button>
    </span>
  )
}
