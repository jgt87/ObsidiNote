// The filters of a search, under the knowledge graph's search box: one removable chip per filter
// and "Clear filters" (the free words stay). Nothing is drawn while the query has no filter.

import { describeFilter, parseQuery, withoutFilter, withoutFilters } from './query'
import './SearchFilters.css'

export function SearchFilters({ query, onQuery }: { query: string; onQuery: (q: string) => void }) {
  const filters = parseQuery(query).filters
  if (!filters.length) return null
  return (
    <div className="sf" role="group" aria-label="Search filters">
      <span className="sf__label">Filters:</span>
      {filters.map((f) => (
        <button
          key={`${f.start}:${f.key}:${f.value}`}
          type="button"
          className="sf__chip"
          aria-label={`Remove filter ${describeFilter(f)}`}
          title="Remove this filter"
          onClick={() => onQuery(withoutFilter(query, f))}
        >
          <span className="sf__key">{f.key}:</span> {f.label}
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path d="M4.5 4.5l7 7M11.5 4.5l-7 7" />
          </svg>
        </button>
      ))}
      <button type="button" className="sf__clear" onClick={() => onQuery(withoutFilters(query))}>
        Clear filters
      </button>
    </div>
  )
}
