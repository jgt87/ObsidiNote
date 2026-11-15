// The map's fixed chrome: the zoom toolbar with its hint, and the legend. Render only.
import type { RefObject } from 'react'

export function StageToolbar({ firstRef, onZoom, onFit }: { firstRef: RefObject<HTMLButtonElement | null>; onZoom: (factor: number) => void; onFit: () => void }) {
  return (
    <div className="kg-toolbar" onPointerDown={(e) => e.stopPropagation()}>
      <button ref={firstRef} type="button" className="btn btn--ghost" aria-label="Zoom in" title="Zoom in (+)" onClick={() => onZoom(1.25)}>
        +
      </button>
      <button type="button" className="btn btn--ghost" aria-label="Zoom out" title="Zoom out (−)" onClick={() => onZoom(0.8)}>
        −
      </button>
      <button type="button" className="btn btn--ghost" aria-label="Fit to screen" title="Fit to screen (0)" onClick={onFit}>
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
          <path d="M2 6V2h4M10 2h4v4M14 10v4h-4M6 14H2v-4" />
        </svg>
      </button>
      {/* design (operator, 2026-11-16): no guiding text beside the zoom buttons. The map's help stays
          for screen readers (the stage's aria-describedby). */}
      <span className="kg-sr" id="kg-stage-help">
        Hover a dot to focus it, click to open, scroll to zoom and drag to pan. Arrow keys or Tab move between pages, Enter opens, F focuses on the page, Esc leaves the map.
      </span>
    </div>
  )
}

export function StageLegend({ areaWord }: { areaWord: 'topic' | 'source' | 'tag' }) {
  return (
    <div className="kg-legend" aria-label="Legend" role="note">
      <span className="kg-legend__item">
        <svg viewBox="0 0 22 12" aria-hidden="true">
          <circle className="kg-dot kg-dot--hub" cx="6" cy="6" r="5" />
          <circle className="kg-dot" cx="17" cy="6" r="2.5" />
        </svg>
        bigger dot = more pages link here
      </span>
      <span className="kg-legend__item">
        <svg viewBox="0 0 22 12" aria-hidden="true">
          <path className="kg-edge kg-s1" d="M0 3H22" />
          <path className="kg-edge kg-s3" d="M0 9H22" />
        </svg>
        thicker line = stronger link
      </span>
      <span className="kg-legend__item">
        <svg viewBox="0 0 22 12" aria-hidden="true">
          <g className="kg-focus">
            <path className="kg-edge kg-s2 kg-edge--in" d="M0 6H22" />
          </g>
        </svg>
        dashed = links to the page you point at
      </span>
      <span className="kg-legend__item">
        <svg viewBox="0 0 22 12" aria-hidden="true">
          <circle className="kg-area" cx="4" cy="6" r="4" />
          <path className="kg-edge kg-bundle" d="M8 6H14" style={{ strokeWidth: '2.5px' }} />
          <circle className="kg-area" cx="18" cy="6" r="4" />
        </svg>
        line between {areaWord}s = their links
      </span>
      <span className="kg-legend__item">
        <svg viewBox="0 0 22 12" aria-hidden="true">
          <circle className="kg-area" cx="11" cy="6" r="6" />
        </svg>
        grey area = {areaWord}
      </span>
      <span className="kg-legend__item">
        <svg viewBox="0 0 22 12" aria-hidden="true">
          <circle className="kg-dot kg-dot--unlinked" cx="11" cy="6" r="4" />
        </svg>
        page with no links yet
      </span>
    </div>
  )
}
