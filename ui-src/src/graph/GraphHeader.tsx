// The knowledge graph's heading and bar (grouping, Filter, search, Graph/List), the read-only
// banner and the Tags grouping's chips. Render only; KnowledgeGraph.tsx holds the state.
import type { KeyboardEvent, ReactNode, RefObject } from 'react'
import { ReadOnlyBanner } from '../components/ReadOnlyBanner'
import { plural } from './format'
import { readOnlyBanner } from './graphViewModel'
import type { GraphSource } from './model'
import { readOnlyWhy } from './readOnly'
import type { GroupBy } from './sourceView'
import { Icon } from '../components/icons'

/** The heading: the view's title (none when the app shell shows one) and one line of counts. */
export function GraphHeading({ title, source, pages, areas, links, hiddenArchived }: { title: string; source: string; pages: number; areas: { joiner: string; areas: string }; links: number; hiddenArchived: number }) {
  return (
    <div className="kg-head__title">
      {title && <h1 className="kg-title">{title}</h1>}
      <span className="kg-meta">
        {source ? `${source} · ` : ''}
        {plural(pages, 'page')}
        {areas.joiner}
        {areas.areas} · {plural(links, 'link')}
        {hiddenArchived > 0 ? ` · ${hiddenArchived} archived hidden` : ''}
      </span>
    </div>
  )
}

/** Why this source is read only, once, above the graph (graphViewModel.ts readOnlyBanner); nothing
 *  for a source that can be written. */
export function SourceBanner({ source, appNote, checkResult, onCheckAgain }: { source: GraphSource; appNote?: string; checkResult: string; onCheckAgain?: () => Promise<void> | void }) {
  if (!source.readOnly) return null
  const b = readOnlyBanner(source, readOnlyWhy(source), appNote, checkResult, onCheckAgain)
  return <ReadOnlyBanner text={b.text} onCheck={b.onCheck} result={b.result} />
}

export interface GraphToolsProps {
  mode: 'graph' | 'list'
  onMode: (m: 'graph' | 'list') => void
  groupBy: GroupBy
  onGroup: (g: GroupBy) => void
  /** The Filter button (FilterPanel.tsx), made by the view. */
  filter: ReactNode
  query: string
  onQuery: (q: string) => void
  onSearchKey: (e: KeyboardEvent<HTMLInputElement>) => void
  searchRef: RefObject<HTMLInputElement | null>
  /** Search results, or null without a search: read out as "N matches". */
  matches: readonly string[] | null
}

export function GraphTools({ mode, onMode, groupBy, onGroup, filter, query, onQuery, onSearchKey, searchRef, matches }: GraphToolsProps) {
  return (
    <div className="kg-tools">
      {mode === 'graph' && (
        <>
          <div className="seg seg--sm" role="group" aria-label="Group the map by">
            <button type="button" className="seg__btn" data-label="Topics" aria-pressed={groupBy === 'topics'} onClick={() => onGroup('topics')}>
              Topics
            </button>
            <button type="button" className="seg__btn" data-label="Sources" aria-pressed={groupBy === 'sources'} onClick={() => onGroup('sources')}>
              Sources
            </button>
            <button type="button" className="seg__btn" data-label="Tags" aria-pressed={groupBy === 'tags'} onClick={() => onGroup('tags')}>
              Tags
            </button>
          </div>
        </>
      )}
      {filter}
      <label htmlFor="kg-search" className="kg-sr">
        Search pages and topics
      </label>
      {/* design: the search has its own clear button, shown whenever there is text (operator,
          2026-11-15: the browser's own "x" only shows while the pointer is over the field). */}
      <span className="kg-searchbox">
        <input
          id="kg-search"
          ref={searchRef}
          className="field kg-search"
          type="search"
          placeholder="Search pages and topics  /"
          value={query}
          onChange={(e) => onQuery(e.target.value)}
          onKeyDown={onSearchKey}
          aria-describedby="kg-search-count"
        />
        {query && (
          <button
            type="button"
            className="kg-search__clear"
            aria-label="Clear search"
            title="Clear search"
            onClick={() => {
              onQuery('')
              searchRef.current?.focus()
            }}
          >
            <Icon name="close" />
          </button>
        )}
      </span>
      <span id="kg-search-count" className="kg-sr" aria-live="polite">
        {matches ? plural(matches.length, 'match', 'matches') : ''}
      </span>
      <div className="seg seg--sm" role="group" aria-label="View">
        <button type="button" className="seg__btn" data-label="Graph" aria-pressed={mode === 'graph'} onClick={() => onMode('graph')}>
          Graph
        </button>
        <button type="button" className="seg__btn" data-label="List" aria-pressed={mode === 'list'} onClick={() => onMode('list')}>
          List
        </button>
      </div>
    </div>
  )
}

export interface TagBarProps {
  tags: { name: string; count: number }[]
  /** The tags chosen as areas, or null for every tag. */
  choice: ReadonlySet<string> | null
  onToggle: (name: string) => void
  onAll: () => void
  /** Pages on the map (tagged with a shown tag) and in the vault. */
  shownPages: number
  allPages: number
}

/** The Tags grouping: which tags make the areas. Every tag is on at first; a chip takes one out or
 *  puts it back. Only pages that carry a shown tag are on this map. */
export function TagBar({ tags, choice, onToggle, onAll, shownPages, allPages }: TagBarProps) {
  const on = (name: string) => !choice || choice.has(name)
  return (
    <div className="kg-tagbar" role="group" aria-label="Tags shown as areas">
      {tags.length === 0 ? (
        <span className="kg-meta">No page has a tag yet. Add one in a page’s window, or tick rows in the List and tag them together.</span>
      ) : (
        <>
          <span className="kg-meta">Areas:</span>
          {tags.map((t) => (
            <button key={t.name} type="button" className="btn btn--sm" aria-pressed={on(t.name)} onClick={() => onToggle(t.name)}>
              <Icon name={on(t.name) ? 'toggle-on' : 'toggle-off'} className="toggle-mark" />
              {t.name} <span className="kg-meta num">{t.count}</span>
            </button>
          ))}
          {choice && (
            <button type="button" className="kg-linkbtn" onClick={onAll}>
              All tags
            </button>
          )}
          <span className="kg-meta">
            {plural(shownPages, 'tagged page')} of {plural(allPages, 'page')} shown
          </span>
        </>
      )}
    </div>
  )
}
