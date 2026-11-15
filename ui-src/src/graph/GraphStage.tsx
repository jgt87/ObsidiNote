// The map itself: SVG for areas, links and dots; HTML over it for labels, the hover card, the
// toolbar and the legend. Labels are HTML (SVG text in generated lists did not render in the
// mock-up's tool), positioned in screen pixels from the same viewport as the SVG.
//
// Performance: the base layer (every area, link and dot) is memoised and never re-renders on
// hover, pan or zoom; pan/zoom only change one transform (useStageView.ts), and focus dims the base
// layer with one attribute and redraws the focused dot and its neighbours in a small layer on top.
// What is named, drawn on top and done on a key is decided in stageModel.ts.

import { memo, useCallback, useEffect, useMemo, useRef, useState, type FocusEvent, type KeyboardEvent, type PointerEvent as ReactPointerEvent, type RefObject } from 'react'
import { plural } from './format'
import { indexPath, type GraphIndex } from './graphIndex'
import { HoverCard } from './HoverCard'
import { bundleEdges, restingBundles, type BundleLayout, type DotLayout, type GraphLayout } from './layout'
import { primaryTopic } from './model'
import { StageLegend, StageToolbar } from './StageChrome'
import { areaAt, drawnAtRest, edgeClass, focusEdgeClass, focusEdgeList, sharpDots, stageKey, stageLabels, type StageKeyAction } from './stageModel'
import { useStageView } from './useStageView'
import { lineMode, pan, toScreen } from './view'

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

const idOf = (t: EventTarget | null): string | null => (t instanceof Element ? t.getAttribute('data-id') : null)

export function GraphStage({ index, layout, filters, matches, active, onActive, onOpen, stageRef, label, shown = null, onFocusPage, areaWord = 'topic' }: Props) {
  const { size, v, fit, setView, layerRef, current, preview, commit, zoomBy } = useStageView(stageRef, layout)
  const [dragging, setDragging] = useState(false)
  /** The topic area under the pointer (its name is hidden while it is). */
  const [hoverArea, setHoverArea] = useState<string | null>(null)
  const drag = useRef<{ x: number; y: number; id: string | null; moved: boolean; pointer: number } | null>(null)
  const pointerFocus = useRef(false)
  const toolbarRef = useRef<HTMLButtonElement>(null)

  const matchSet = useMemo(() => (matches ? new Set(matches) : null), [matches])
  // A search highlights its results; it hides nothing (operator, 2026-11-15: "I'm not able to select
  // any other dots than the searched item"). The pointer reaches every page the filters show
  // (isShown); the keyboard walks the results while a search runs (visible), as the box's Enter
  // and arrow keys do.
  const isShown = useCallback((id: string) => !shown || shown.has(id), [shown])
  const visible = useCallback((id: string) => isShown(id) && (!matchSet || matchSet.has(id)), [matchSet, isShown])
  const activeDot = active && isShown(active.id) ? layout.dotById.get(active.id) ?? null : null
  const viaKeyboard = active?.via === 'keyboard'

  // Keyboard focus keeps the active dot on screen.
  useEffect(() => {
    if (!activeDot || !viaKeyboard || !size.w) return
    const [sx, sy] = toScreen(v, activeDot.x, activeDot.y)
    const m = 48
    if (sx < m || sy < m || sx > size.w - m || sy > size.h - m) {
      setView({ k: v.k, x: activeDot.x - size.w / 2 / v.k, y: activeDot.y - size.h / 2 / v.k })
    }
  }, [activeDot, active?.via]) // eslint-disable-line react-hooks/exhaustive-deps

  // ---------- pointer ----------
  const keyboardMode = useRef(false)
  useEffect(() => {
    if (viaKeyboard) keyboardMode.current = true
  }, [active]) // eslint-disable-line react-hooks/exhaustive-deps
  // A click anywhere outside the map closes a card the keyboard left open (a pointer card closes
  // when the pointer leaves its dot). Not while the page window is open: it sits on top.
  useEffect(() => {
    if (!viaKeyboard) return
    const onDown = (e: PointerEvent) => {
      const el = stageRef.current
      const t = e.target as Node | null
      const insideMap = !!t && !!el?.contains(t)
      if (!el || insideMap || document.querySelector('dialog[open]')) return
      onActive(null)
    }
    window.addEventListener('pointerdown', onDown)
    return () => window.removeEventListener('pointerdown', onDown)
  }, [viaKeyboard, onActive, stageRef])

  const onPointerDown = (e: ReactPointerEvent<SVGSVGElement>) => {
    if (e.button !== 0) return
    pointerFocus.current = true
    drag.current = { x: e.clientX, y: e.clientY, id: idOf(e.target), moved: false, pointer: e.pointerId }
  }
  const trackHoverArea = (e: ReactPointerEvent<SVGSVGElement>) => {
    // The area under the pointer: its name gives way so it never covers the pages.
    const box = e.currentTarget.getBoundingClientRect()
    const over = areaAt(layout.areas, current(), e.clientX - box.left, e.clientY - box.top)
    if (over !== hoverArea) setHoverArea(over)
  }
  const onPointerMove = (e: ReactPointerEvent<SVGSVGElement>) => {
    keyboardMode.current = false
    if (!drag.current?.moved) trackHoverArea(e)
    const d = drag.current
    if (!d || d.pointer !== e.pointerId) return
    const dx = e.clientX - d.x
    const dy = e.clientY - d.y
    if (!d.moved && dx * dx + dy * dy < 16) return
    if (!d.moved) {
      d.moved = true
      setDragging(true)
      e.currentTarget.setPointerCapture(e.pointerId)
      if (active?.via === 'pointer') onActive(null)
    }
    d.x = e.clientX
    d.y = e.clientY
    preview(pan(current(), dx, dy), 400)
  }
  const onPointerUp = (e: ReactPointerEvent<SVGSVGElement>) => {
    const d = drag.current
    drag.current = null
    // Focus from this click (if any) has happened by now; a later keyboard focus must count.
    pointerFocus.current = false
    if (!d || d.pointer !== e.pointerId) return
    if (d.moved) {
      setDragging(false)
      if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId)
      commit()
      return
    }
    if (d.id && isShown(d.id)) onOpen(d.id, 'pointer')
    // A click on an empty spot closes a preview card, also one the keyboard left open (2026-11-13).
    else if (active) onActive(null)
  }
  const onPointerOver = (e: ReactPointerEvent<SVGSVGElement>) => {
    // A resting pointer "enters" new dots when the keyboard redraws the focus layer under it;
    // hover takes over only after the pointer really moves.
    if (drag.current?.moved || keyboardMode.current) return
    const id = idOf(e.target)
    if (id && isShown(id) && active?.id !== id) onActive({ id, via: 'pointer' })
  }
  const onPointerOut = (e: ReactPointerEvent<SVGSVGElement>) => {
    const id = idOf(e.target)
    if (!id || drag.current?.moved) return
    if (idOf(e.relatedTarget) === id) return
    if (active?.via === 'pointer' && active.id === id) onActive(null)
  }

  // ---------- keyboard ----------
  const order = useMemo(() => layout.dots.filter((d) => visible(d.id)), [layout.dots, visible])
  const runKeyAction = (a: StageKeyAction) => {
    if (a.kind === 'activate') onActive({ id: a.id, via: 'keyboard' })
    else if (a.kind === 'open') onOpen(a.id)
    else if (a.kind === 'focusPage') onFocusPage?.(a.id)
    else if (a.kind === 'zoom') zoomBy(a.factor)
    else if (a.kind === 'fit') setView(fit)
    else {
      onActive(null)
      toolbarRef.current?.focus()
    }
  }
  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.target !== e.currentTarget) return
    const r = stageKey(e, { activeDot, hasActive: !!active, order, dots: layout.dots, visible, canFocusPage: !!onFocusPage })
    if (!r) return
    if (r.prevent) e.preventDefault()
    if (r.action) runKeyAction(r.action)
  }
  const onFocus = (e: FocusEvent<HTMLDivElement>) => {
    if (e.target !== e.currentTarget) return
    if (pointerFocus.current) {
      pointerFocus.current = false
      return
    }
    if (!active && order[0]) onActive({ id: order[0].id, via: 'keyboard' })
    else if (active) onActive({ id: active.id, via: 'keyboard' })
  }
  const onBlur = (e: FocusEvent<HTMLDivElement>) => {
    if (e.target === e.currentTarget && viaKeyboard) onActive(null)
  }

  // ---------- focus layer and names ----------
  const activeId = activeDot?.id ?? null
  const near = useMemo(() => (activeDot ? (index.neighbours.get(activeDot.id) ?? []).filter(isShown) : []), [index, activeDot, isShown])
  const focusEdges = useMemo(() => focusEdgeList(index, layout, activeId, filters.links, filters.mentions, isShown), [index, layout, activeId, filters.links, filters.mentions, isShown])
  const sharp = useMemo(() => sharpDots(layout, activeId, near, matches, isShown), [activeId, near, matches, layout, isShown])
  const dim = !!activeDot || !!matches
  const { areaLabels, groupLabels, hiddenAreas, labels } = stageLabels({ layout, index, v, fitK: fit.k, size, shown, activeDot, sharp, matches, hubsOnly: filters.hubsOnly, hoverArea })

  const bundles = useMemo(() => bundleEdges(layout, shown), [layout, shown])
  // At rest the heaviest topic lines; zoomed in far enough, all of them (lineMode).
  const allLines = lineMode(v.k, fit.k) === 'all'
  const resting = useMemo(() => (allLines ? bundles : restingBundles(bundles)), [bundles, allLines])
  // Pointing at a page shows every topic line of its area (under the areas, not faded).
  const focusBundles = useMemo(
    () => (activeDot && filters.links ? bundles.filter((b) => b.a === activeDot.area || b.b === activeDot.area) : []),
    [bundles, activeDot, filters.links],
  )

  const world = `matrix(${v.k} 0 0 ${v.k} ${-v.x * v.k} ${-v.y * v.k})`
  const page = activeDot ? index.pageById.get(activeDot.id) : undefined
  const announce = page
    ? `${page.title}, ${indexPath(index, primaryTopic(page))}, ${plural(near.length, 'linked page')}. Enter opens${onFocusPage ? ', F focuses on this page' : ''}.`
    : ''

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
      onKeyDown={onKeyDown}
      onFocus={onFocus}
      onBlur={onBlur}
    >
      <div ref={layerRef} className="kg-layer">
      <svg
        className="kg-svg"
        width={size.w}
        height={size.h}
        aria-hidden="true"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        onPointerOver={onPointerOver}
        onPointerOut={onPointerOut}
        onPointerLeave={() => setHoverArea(null)}
      >
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
        {/* design (operator, 2026-11-15): pointing at a page (or searching) lays one veil in the stage's
            colour over the whole map, areas included, and the focus layer draws the page, its linked
            pages and their lines above it. One rectangle, whatever the size of the map; the base layer
            is never redrawn. In screen space: during a gesture it moves with the layer, and what it
            covers moves with it. */}
        <rect className="kg-veil" data-on={dim} x={0} y={0} width={size.w} height={size.h} />
        <g transform={world}>
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
                {viaKeyboard && <circle className="kg-ring" cx={activeDot.x} cy={activeDot.y} r={activeDot.r + 2 + 5 / v.k} />}
              </>
            )}
          </g>
        </g>
      </svg>

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
      </div>

      {page && activeDot && (
        <HoverCard
          index={index}
          page={page}
          dot={activeDot}
          view={v}
          stage={size}
          near={near.map((id) => layout.dotById.get(id)).filter((d): d is DotLayout => !!d)}
          focusKey={onFocusPage && viaKeyboard ? 'F' : undefined}
        />
      )}

      {shown && shown.size === 0 && (
        <p className="kg-stage__empty" role="status">
          No pages match these filters.
        </p>
      )}

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
