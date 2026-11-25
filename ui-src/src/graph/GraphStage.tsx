// The map itself: SVG for areas, links and dots; HTML over it for labels, the hover card, the
// toolbar and the legend. Labels are HTML (SVG text in generated lists did not render in the
// mock-up's tool), positioned in screen pixels from the same viewport as the SVG.
//
// Performance: the base layer (every area, link and dot) is memoised and never re-renders on
// hover, pan or zoom; pan/zoom only change one transform (useStageView.ts), and focus dims the base
// layer with one attribute and redraws the focused dot and its neighbours in a small layer on top.
// What is named, drawn on top and done on a key is decided in stageModel.ts.

import { memo, useCallback, useMemo, useRef, type RefObject } from 'react'
import { indexPath, type GraphIndex } from './graphIndex'
import { HoverCard } from './HoverCard'
import { bundleEdges, restingBundles, type BundleLayout, type DotLayout, type GraphLayout } from './layout'
import { primaryTopic, type GraphPage } from './model'
import { StageLegend, StageToolbar } from './StageChrome'
import { areaBundles, drawnAtRest, edgeClass, focusEdgeClass, focusEdgeList, sharpDots, stageAnnouncement, stageLabels } from './stageModel'
import { useStageKeyboard, useStagePointer } from './useStageInput'
import { useStageView } from './useStageView'
import { lineMode, type Viewport } from './view'

export interface Filters {
  links: boolean
  mentions: boolean
  hubsOnly: boolean
}

export interface Active {
  id: string
  via: 'pointer' | 'keyboard'
}

interface Props {
  index: GraphIndex
  layout: GraphLayout
  filters: Filters
  /** Search result ids (in rank order), or null when there is no search. */
  matches: string[] | null
  active: Active | null
  onActive: (a: Active | null) => void
  /** Opens the page window; `via` says whether a click or the keyboard did it (focus on close). */
  onOpen: (id: string, via?: 'pointer' | 'keyboard') => void
  stageRef: RefObject<HTMLDivElement | null>
  /** Accessible name of the map (default "Knowledge graph"). */
  label?: string
  /** Pages the filters leave visible (filters.ts), or null for all. Hidden pages get no dot, no
   *  link and no place in keyboard navigation; the layout is not rerun, so dots never jump. */
  shown?: Set<string> | null
  /** "Focus on this page" (F on the focused dot). */
  onFocusPage?: (id: string) => void
  /** What an area stands for, for the legend: a topic, or a source (the Sources view). */
  areaWord?: 'topic' | 'source' | 'tag'
}

type BaseProps = { layout: GraphLayout; links: boolean; mentions: boolean; shown: Set<string> | null; bundles: BundleLayout[] }

/** Line width of a bundle: grows with the summed strength of the links it stands for (one loose
 *  link = 1 px, four related links = 3.2 px), capped at 5 px. */
export function bundleWidth(weight: number): number {
  return Math.min(5, 1 + Math.log2(Math.max(1, weight / 2)) * 1.1)
}

function BundleLine({ b, extra = '' }: { b: BundleLayout; extra?: string }) {
  return <path d={b.d} className={`kg-edge kg-bundle${extra}`} style={{ strokeWidth: `${bundleWidth(b.weight)}px` }} />
}

const BaseLayer = memo(function BaseLayer({ layout, links, mentions, shown, bundles }: BaseProps) {
  const on = (id: string) => !shown || shown.has(id)
  return (
    <>
      {/* Links between topics, UNDER the solid areas so a line never shows across a third topic
          (bundleEdges; only the heaviest at rest, restingBundles). Their page-to-page lines are
          drawn only for the focused page (focus layer). */}
      <g>{links && bundles.map((b) => <BundleLine key={`${b.a}|${b.b}`} b={b} />)}</g>
      <g className="kg-areas">
        {layout.areas.map((a) => (a.pageIds.some(on) ? <circle key={a.id} className="kg-area" cx={a.x} cy={a.y} r={a.r} /> : null))}
      </g>
      <g>{layout.edges.map((e, i) => (drawnAtRest(e, layout, links, mentions, on) ? <path key={i} d={e.d} className={edgeClass(e.edge)} /> : null))}</g>
      <g>
        {layout.dots.map((d) => (on(d.id) ? <circle key={d.id} data-id={d.id} className={dotClass(d)} cx={d.x} cy={d.y} r={d.r} /> : null))}
      </g>
    </>
  )
})

function dotClass(d: DotLayout, extra = ''): string {
  return `kg-dot${d.unlinked ? ' kg-dot--unlinked' : d.hub ? ' kg-dot--hub' : ''}${extra}`
}

export function GraphStage({ index, layout, filters, matches, active, onActive, onOpen, stageRef, label, shown = null, onFocusPage, areaWord = 'topic' }: Props) {
  const { size, v, fit, setView, layerRef, current, preview, commit, zoomBy } = useStageView(stageRef, layout)
  const toolbarRef = useRef<HTMLButtonElement>(null)
  const { isShown, visible, activeDot, near } = useStageFocus(index, layout, shown, matches, active)
  const viaKeyboard = active?.via === 'keyboard'

  // Pointer and keyboard (useStageInput.ts).
  const { dragging, hoverArea, pointerFocus, svgHandlers } = useStagePointer({ layout, stageRef, current, preview, commit, active, onActive, onOpen, isShown })
  const order = useMemo(() => layout.dots.filter((d) => visible(d.id)), [layout.dots, visible])
  const keys = useStageKeyboard({ layout, active, activeDot, order, visible, onActive, onOpen, onFocusPage, zoomBy, fit, v, size, setView, toolbarRef, pointerFocus })

  // ---------- focus layer and names ----------
  const activeId = activeDot?.id ?? null
  const focusEdges = useMemo(() => focusEdgeList(index, layout, activeId, filters.links, filters.mentions, isShown), [index, layout, activeId, filters.links, filters.mentions, isShown])
  const sharp = useMemo(() => sharpDots(layout, activeId, near, matches, isShown), [activeId, near, matches, layout, isShown])
  const dim = !!activeDot || !!matches
  const names = stageLabels({ layout, index, v, fitK: fit.k, size, shown, activeDot, sharp, matches, hubsOnly: filters.hubsOnly, hoverArea })
  const { resting, focusBundles } = useTopicLines(layout, shown, v.k, fit.k, activeDot, filters.links)

  const world = `matrix(${v.k} 0 0 ${v.k} ${-v.x * v.k} ${-v.y * v.k})`
  const { page, announce } = focusedPage(index, activeDot, near.length, !!onFocusPage)

  return (
    <div
      ref={stageRef}
      className="kg-stage"
      tabIndex={0}
      role="group"
      aria-roledescription="knowledge graph"
      aria-label={label ?? 'Knowledge graph'}
      aria-describedby="kg-stage-help"
      data-dragging={dragging}
      onKeyDown={keys.onKeyDown}
      onFocus={keys.onFocus}
      onBlur={keys.onBlur}
    >
      <div ref={layerRef} className="kg-layer">
      <svg className="kg-svg" width={size.w} height={size.h} aria-hidden="true" {...svgHandlers}>
        <g transform={world}>
          <g className="kg-focus-bundles">
            {focusBundles.map((b) => (
              <BundleLine key={`${b.a}|${b.b}`} b={b} extra=" kg-bundle--on" />
            ))}
          </g>
          <g className="kg-base">
            <BaseLayer layout={layout} links={filters.links} mentions={filters.mentions} shown={shown} bundles={resting} />
          </g>
        </g>
        {/* design: D-043. Pointing at a page (or searching) lays one veil in the stage's
            colour over the whole map, areas included, and the focus layer draws the page, its linked
            pages and their lines above it. One rectangle, whatever the size of the map; the base layer
            is never redrawn. In screen space: during a gesture it moves with the layer, and what it
            covers moves with it. */}
        <rect className="kg-veil" data-on={dim} x={0} y={0} width={size.w} height={size.h} />
        <g transform={world}>
          <FocusLayer focusEdges={focusEdges} sharp={sharp} activeDot={activeDot} ring={viaKeyboard} k={v.k} />
        </g>
      </svg>

      <StageNames names={names} dim={dim} />
      </div>

      <FocusCard index={index} layout={layout} page={page} dot={activeDot} view={v} stage={size} near={near} showFocusKey={!!onFocusPage && viaKeyboard} />

      <EmptyFilterNote shown={shown} />

      <div className="kg-bottom">
        <StageToolbar firstRef={toolbarRef} onZoom={zoomBy} onFit={() => setView(fit)} />
        <StageLegend areaWord={areaWord} />
      </div>

      <div className="kg-sr" aria-live="polite">
        {viaKeyboard ? announce : ''}
      </div>
    </div>
  )
}

/**
 * What the stage can reach and what is focused. A search highlights its results; it hides nothing
 * (D-042). The
 * pointer reaches every page the filters show (isShown); the keyboard walks the results while a
 * search runs (visible), as the box's Enter and arrow keys do. The focused dot only counts while
 * its page is shown; `near` are its linked pages that are shown.
 */
function useStageFocus(index: GraphIndex, layout: GraphLayout, shown: Set<string> | null, matches: string[] | null, active: Active | null) {
  const matchSet = useMemo(() => (matches ? new Set(matches) : null), [matches])
  const isShown = useCallback((id: string) => !shown || shown.has(id), [shown])
  const visible = useCallback((id: string) => isShown(id) && (!matchSet || matchSet.has(id)), [matchSet, isShown])
  const activeDot = focusedDot(layout, active, isShown)
  const near = useMemo(() => (activeDot ? (index.neighbours.get(activeDot.id) ?? []).filter(isShown) : []), [index, activeDot, isShown])
  return { isShown, visible, activeDot, near }
}

/** The focused page's dot, while its page is shown; null otherwise. */
function focusedDot(layout: GraphLayout, active: Active | null, isShown: (id: string) => boolean): DotLayout | null {
  if (!active || !isShown(active.id)) return null
  return layout.dotById.get(active.id) ?? null
}

/** The focused page and what a screen reader hears for it ('' without one). */
function focusedPage(index: GraphIndex, activeDot: DotLayout | null, linked: number, canFocusPage: boolean) {
  const page = activeDot ? index.pageById.get(activeDot.id) : undefined
  const announce = page ? stageAnnouncement(page.title, indexPath(index, primaryTopic(page)), linked, canFocusPage) : ''
  return { page, announce }
}

/** The dots of the given pages, for the hover card's list of linked pages. */
const nearDots = (layout: GraphLayout, ids: string[]): DotLayout[] => ids.map((id) => layout.dotById.get(id)).filter((d): d is DotLayout => !!d)

interface FocusCardProps {
  index: GraphIndex
  layout: GraphLayout
  page: GraphPage | undefined
  dot: DotLayout | null
  view: Viewport
  stage: { w: number; h: number }
  near: string[]
  /** The card names F ("focus on this page") only for the keyboard, where F works. */
  showFocusKey: boolean
}

/** The focused page's card beside its dot; nothing without a focused page. */
function FocusCard({ index, layout, page, dot, view, stage, near, showFocusKey }: FocusCardProps) {
  if (!page || !dot) return null
  return <HoverCard index={index} page={page} dot={dot} view={view} stage={stage} near={nearDots(layout, near)} focusKey={showFocusKey ? 'F' : undefined} />
}

/** When the filters leave no page, the map says so instead of showing an empty stage. */
function EmptyFilterNote({ shown }: { shown: Set<string> | null }) {
  if (!shown || shown.size !== 0) return null
  return (
    <p className="kg-stage__empty" role="status">
      No pages match these filters.
    </p>
  )
}

/** The topic lines: at rest the heaviest (restingBundles), zoomed in far enough all of them
 *  (lineMode); pointing at a page shows every line of its area (under the areas, not faded). */
function useTopicLines(layout: GraphLayout, shown: Set<string> | null, k: number, fitK: number, activeDot: DotLayout | null, linksOn: boolean) {
  const bundles = useMemo(() => bundleEdges(layout, shown), [layout, shown])
  const allLines = lineMode(k, fitK) === 'all'
  const resting = useMemo(() => (allLines ? bundles : restingBundles(bundles)), [bundles, allLines])
  const focusBundles = useMemo(() => areaBundles(bundles, activeDot?.area ?? null, linksOn), [bundles, activeDot, linksOn])
  return { resting, focusBundles }
}

/** The focus layer above the veil: the focused page's lines, the pages kept sharp (its linked pages,
 *  or a search's results), and the focused dot itself with the keyboard's ring. */
function FocusLayer({ focusEdges, sharp, activeDot, ring, k }: { focusEdges: ReturnType<typeof focusEdgeList>; sharp: DotLayout[]; activeDot: DotLayout | null; ring: boolean; k: number }) {
  return (
    <g className="kg-focus">
      {focusEdges.map((f, i) => (
        <path key={i} d={f.d} className={focusEdgeClass(f)} />
      ))}
      {sharp.map((d) => (
        <circle key={d.id} data-id={d.id} className={dotClass(d, activeDot ? ' kg-dot--near' : '')} cx={d.x} cy={d.y} r={d.r} />
      ))}
      {activeDot && (
        <>
          <circle data-id={activeDot.id} className={dotClass(activeDot, ' kg-dot--on')} cx={activeDot.x} cy={activeDot.y} r={activeDot.r + 2} />
          {ring && <circle className="kg-ring" cx={activeDot.x} cy={activeDot.y} r={activeDot.r + 2 + 5 / k} />}
        </>
      )}
    </g>
  )
}

/** The names over the map, in screen pixels (stageModel.ts stageLabels): topic or tag names on their
 *  areas (hidden under the pointer or the focused page), group names, and page names. */
function StageNames({ names, dim }: { names: ReturnType<typeof stageLabels>; dim: boolean }) {
  const { areaLabels, groupLabels, hiddenAreas, labels } = names
  return (
    <div className="kg-labels" aria-hidden="true">
      {areaLabels.map((l) => (
        <div key={l.id} className="kg-alabel" data-dim={dim} data-at={l.at} data-hidden={hiddenAreas.has(l.id)} style={{ left: l.x, top: l.top }}>
          <b>{l.text}</b>
          {l.count !== undefined && <span className="kg-alabel__count">{l.count}</span>}
        </div>
      ))}
      {groupLabels.map((g) => (
        <div key={g.key} className="kg-glabel" data-dim={dim} data-hidden={!!g.hidden} style={{ left: g.x, top: g.top }}>
          {g.text}
        </div>
      ))}
      {labels.map((l) => (
        <div key={l.id} className={l.cls} style={{ left: l.x, top: l.y }}>
          {l.text}
        </div>
      ))}
    </div>
  )
}
