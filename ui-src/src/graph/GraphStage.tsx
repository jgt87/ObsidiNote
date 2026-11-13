// The map itself: SVG for areas, links and dots; HTML over it for labels, the hover card, the
// toolbar and the legend. Labels are HTML (SVG text in generated lists did not render in the
// mock-up's tool), positioned in screen pixels from the same viewport as the SVG.
//
// Performance: the base layer (every area, link and dot) is memoised and never re-renders on
// hover, pan or zoom; pan/zoom only change one transform, and focus dims the base layer with one
// attribute and redraws the focused dot and its neighbours in a small layer on top.

import { memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type FocusEvent, type KeyboardEvent, type PointerEvent as ReactPointerEvent, type RefObject } from 'react'
import { flushSync } from 'react-dom'
import { plural } from './format'
import { indexPath, type GraphIndex } from './graphIndex'
import { HoverCard } from './HoverCard'
import { edgePath, type DotLayout, type GraphLayout } from './layout'
import { primaryTopic, type GraphEdge } from './model'
import { fitViewport, MIN_ZOOM_FACTOR, nextInDirection, pan, placeLabels, toScreen, zoomAt, type Direction, type LabelBox, type Viewport } from './view'

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
  onOpen: (id: string) => void
  stageRef: RefObject<HTMLDivElement | null>
  /** Accessible name of the map (default "Knowledge graph"). */
  label?: string
}

const BaseLayer = memo(function BaseLayer({ layout, links, mentions }: { layout: GraphLayout; links: boolean; mentions: boolean }) {
  return (
    <>
      <g>
        {layout.areas.map((a) => (
          <circle key={a.id} className="kg-area" cx={a.x} cy={a.y} r={a.r} />
        ))}
      </g>
      <g>
        {layout.edges.map((e, i) => {
          const m = e.edge.kind === 'mention'
          if (m ? !mentions : !links) return null
          return <path key={i} d={e.d} className={m ? 'kg-edge kg-edge--mention' : `kg-edge kg-s${e.edge.strength}`} />
        })}
      </g>
      <g>
        {layout.dots.map((d) => (
          <circle key={d.id} data-id={d.id} className={dotClass(d)} cx={d.x} cy={d.y} r={d.r} />
        ))}
      </g>
    </>
  )
})

function dotClass(d: DotLayout, extra = ''): string {
  return `kg-dot${d.unlinked ? ' kg-dot--unlinked' : d.hub ? ' kg-dot--hub' : ''}${extra}`
}

const KEY_DIR: Record<string, Direction> = { ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down' }

export function GraphStage({ index, layout, filters, matches, active, onActive, onOpen, stageRef, label }: Props) {
  const [size, setSize] = useState<{ w: number; h: number }>({ w: 0, h: 0 })
  const [view, setView] = useState<Viewport | null>(null)
  const [dragging, setDragging] = useState(false)
  const drag = useRef<{ x: number; y: number; id: string | null; moved: boolean; pointer: number } | null>(null)
  const pointerFocus = useRef(false)
  const toolbarRef = useRef<HTMLButtonElement>(null)
  const layerRef = useRef<HTMLDivElement>(null)
  // While a wheel or drag gesture runs, the picture moves with a CSS transform only (cheap,
  // composited); the real viewport is committed when the gesture settles.
  const live = useRef<Viewport | null>(null)
  const timer = useRef(0)

  // Stage size.
  useLayoutEffect(() => {
    const el = stageRef.current
    if (!el) return
    const measure = () => setSize({ w: el.clientWidth, h: el.clientHeight })
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    return () => ro.disconnect()
  }, [stageRef])

  const fit = useMemo(() => fitViewport(layout.bounds, size.w, size.h), [layout.bounds, size.w, size.h])
  // A new layout or the first measurement: show everything.
  useEffect(() => {
    if (size.w > 0) setView(fit)
  }, [layout, size.w > 0]) // eslint-disable-line react-hooks/exhaustive-deps
  const v = view ?? fit
  const viewRef = useRef(v)
  viewRef.current = v
  const minK = fit.k * MIN_ZOOM_FACTOR

  const commit = useCallback(() => {
    window.clearTimeout(timer.current)
    const next = live.current
    if (!next) return
    live.current = null
    flushSync(() => setView(next))
    if (layerRef.current) layerRef.current.style.transform = ''
    stageRef.current?.removeAttribute('data-moving')
  }, [stageRef])
  const preview = useCallback(
    (next: Viewport, settle: number) => {
      live.current = next
      const base = viewRef.current
      const tx = (base.x - next.x) * next.k
      const ty = (base.y - next.y) * next.k
      if (layerRef.current) layerRef.current.style.transform = `translate(${tx}px, ${ty}px) scale(${next.k / base.k})`
      stageRef.current?.setAttribute('data-moving', 'true')
      window.clearTimeout(timer.current)
      timer.current = window.setTimeout(commit, settle)
    },
    [commit, stageRef],
  )
  useEffect(() => () => window.clearTimeout(timer.current), [])

  // Scroll to zoom (a native listener: React's wheel handler is passive).
  useEffect(() => {
    const el = stageRef.current
    if (!el) return
    const onWheel = (e: WheelEvent) => {
      e.preventDefault()
      const r = el.getBoundingClientRect()
      const factor = Math.exp(-e.deltaY * (e.deltaMode === 1 ? 0.05 : 0.0015))
      preview(zoomAt(live.current ?? viewRef.current, factor, e.clientX - r.left, e.clientY - r.top, minK), 140)
    }
    el.addEventListener('wheel', onWheel, { passive: false })
    return () => el.removeEventListener('wheel', onWheel)
  }, [stageRef, preview, minK])

  // Buttons and +/- keys: the same cheap preview, committed after a short pause (repeated
  // presses stay smooth).
  const zoomBy = useCallback(
    (factor: number) => preview(zoomAt(live.current ?? viewRef.current, factor, size.w / 2, size.h / 2, minK), 220),
    [preview, size, minK],
  )

  const matchSet = useMemo(() => (matches ? new Set(matches) : null), [matches])
  const visible = useCallback((id: string) => !matchSet || matchSet.has(id), [matchSet])
  const activeDot = active ? layout.dotById.get(active.id) ?? null : null

  // Keyboard focus keeps the active dot on screen.
  useEffect(() => {
    if (!activeDot || active?.via !== 'keyboard' || !size.w) return
    const [sx, sy] = toScreen(v, activeDot.x, activeDot.y)
    const m = 48
    if (sx < m || sy < m || sx > size.w - m || sy > size.h - m) {
      setView({ k: v.k, x: activeDot.x - size.w / 2 / v.k, y: activeDot.y - size.h / 2 / v.k })
    }
  }, [activeDot, active?.via]) // eslint-disable-line react-hooks/exhaustive-deps

  // ---------- pointer ----------
  const idOf = (t: EventTarget | null): string | null => (t instanceof Element ? t.getAttribute('data-id') : null)

  const keyboardMode = useRef(false)
  useEffect(() => {
    if (active?.via === 'keyboard') keyboardMode.current = true
  }, [active])

  const onPointerDown = (e: ReactPointerEvent<SVGSVGElement>) => {
    if (e.button !== 0) return
    pointerFocus.current = true
    drag.current = { x: e.clientX, y: e.clientY, id: idOf(e.target), moved: false, pointer: e.pointerId }
  }
  const onPointerMove = (e: ReactPointerEvent<SVGSVGElement>) => {
    keyboardMode.current = false
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
    preview(pan(live.current ?? viewRef.current, dx, dy), 400)
  }
  const onPointerUp = (e: ReactPointerEvent<SVGSVGElement>) => {
    const d = drag.current
    drag.current = null
    if (!d || d.pointer !== e.pointerId) return
    if (d.moved) {
      setDragging(false)
      if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId)
      commit()
      return
    }
    if (d.id && visible(d.id)) onOpen(d.id)
  }
  const onPointerOver = (e: ReactPointerEvent<SVGSVGElement>) => {
    // A resting pointer "enters" new dots when the keyboard redraws the focus layer under it;
    // hover takes over only after the pointer really moves.
    if (drag.current?.moved || keyboardMode.current) return
    const id = idOf(e.target)
    if (id && visible(id) && active?.id !== id) onActive({ id, via: 'pointer' })
  }
  const onPointerOut = (e: ReactPointerEvent<SVGSVGElement>) => {
    const id = idOf(e.target)
    if (!id || drag.current?.moved) return
    if (idOf(e.relatedTarget) === id) return
    if (active?.via === 'pointer' && active.id === id) onActive(null)
  }

  // ---------- keyboard ----------
  const order = useMemo(() => layout.dots.filter((d) => visible(d.id)), [layout.dots, visible])
  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.target !== e.currentTarget) return
    const dir = KEY_DIR[e.key]
    if (dir) {
      e.preventDefault()
      if (!activeDot) {
        if (order[0]) onActive({ id: order[0].id, via: 'keyboard' })
        return
      }
      const next = nextInDirection(layout.dots, activeDot, dir, visible)
      if (next) onActive({ id: next.id, via: 'keyboard' })
      return
    }
    if (e.key === 'Tab' && activeDot && !e.altKey && !e.ctrlKey && !e.metaKey) {
      const i = order.findIndex((d) => d.id === activeDot.id)
      const j = i + (e.shiftKey ? -1 : 1)
      if (i >= 0 && j >= 0 && j < order.length) {
        e.preventDefault()
        onActive({ id: order[j].id, via: 'keyboard' })
      }
      // At either end Tab leaves the map as usual.
      return
    }
    if (e.key === 'Enter' && activeDot) {
      e.preventDefault()
      onOpen(activeDot.id)
    } else if (e.key === 'Escape' && active) {
      e.preventDefault()
      onActive(null)
      toolbarRef.current?.focus()
    } else if (e.key === '+' || e.key === '=') {
      e.preventDefault()
      zoomBy(1.25)
    } else if (e.key === '-') {
      e.preventDefault()
      zoomBy(0.8)
    } else if (e.key === '0') {
      e.preventDefault()
      setView(fit)
    }
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
    if (e.target === e.currentTarget && active?.via === 'keyboard') onActive(null)
  }

  // ---------- focus layer ----------
  const near = useMemo(() => (active ? index.neighbours.get(active.id) ?? [] : []), [index, active])
  const focusEdges = useMemo(() => {
    if (!active) return [] as { e: GraphEdge; d: string }[]
    const list: GraphEdge[] = []
    if (filters.links) list.push(...(index.out.get(active.id) ?? []), ...(index.in.get(active.id) ?? []))
    if (filters.mentions) list.push(...(index.mentions.get(active.id) ?? []))
    return list.flatMap((e) => {
      const a = layout.dotById.get(e.from)
      const b = layout.dotById.get(e.to)
      return a && b ? [{ e, d: edgePath(a.x, a.y, b.x, b.y) }] : []
    })
  }, [index, layout, active, filters.links, filters.mentions])

  const sharp: DotLayout[] = useMemo(() => {
    const ids = active ? [...near] : matches ? matches.slice(0, 400) : []
    return ids.map((id) => layout.dotById.get(id)).filter((d): d is DotLayout => !!d && d.id !== active?.id)
  }, [active, near, matches, layout])

  const dim = !!active || !!matches

  // ---------- labels ----------
  // Candidates in priority order (focused page first); placeLabels drops the ones that would
  // overlap a label already placed, so labels never pile up on each other.
  const candidates: LabelBox[] = []
  const addLabel = (d: DotLayout, cls: string) => {
    const [x, y] = toScreen(v, d.x, d.y)
    if (x < -200 || y < -40 || x > size.w + 200 || y > size.h + 40) return
    const px = cls.includes('--on') ? 13 : cls.includes('--hub') ? 12 : 11
    candidates.push({ id: d.id, text: index.pageById.get(d.id)!.title, x, y: y - d.r * v.k - 4, px, cls })
  }
  if (activeDot) {
    addLabel(activeDot, 'kg-plabel kg-plabel--on')
    for (const d of sharp) if (!filters.hubsOnly || d.hub) addLabel(d, d.hub ? 'kg-plabel kg-plabel--hub' : 'kg-plabel')
  } else if (matches) {
    for (const d of sharp.slice(0, 40)) addLabel(d, d.hub ? 'kg-plabel kg-plabel--hub' : 'kg-plabel')
  } else {
    for (const d of layout.dots) if (d.hub) addLabel(d, 'kg-plabel kg-plabel--hub')
  }
  const labels = placeLabels(candidates)

  const page = active ? index.pageById.get(active.id) : undefined
  const announce = page ? `${page.title}, ${indexPath(index, primaryTopic(page))}, ${plural(near.length, 'linked page')}. Enter opens.` : ''

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
      >
        <g transform={`matrix(${v.k} 0 0 ${v.k} ${-v.x * v.k} ${-v.y * v.k})`}>
          <g className="kg-base" data-dim={dim}>
            <BaseLayer layout={layout} links={filters.links} mentions={filters.mentions} />
          </g>
          <g className="kg-focus">
            {focusEdges.map(({ e, d }, i) => (
              <path key={i} d={d} className={e.kind === 'mention' ? 'kg-edge kg-edge--mention' : `kg-edge kg-s${e.strength}`} />
            ))}
            {sharp.map((d) => (
              <circle key={d.id} data-id={d.id} className={dotClass(d, active ? ' kg-dot--near' : '')} cx={d.x} cy={d.y} r={d.r} />
            ))}
            {activeDot && (
              <>
                <circle data-id={activeDot.id} className={dotClass(activeDot, ' kg-dot--on')} cx={activeDot.x} cy={activeDot.y} r={activeDot.r + 2} />
                {active?.via === 'keyboard' && <circle className="kg-ring" cx={activeDot.x} cy={activeDot.y} r={activeDot.r + 2 + 5 / v.k} />}
              </>
            )}
          </g>
        </g>
      </svg>

      <div className="kg-labels" aria-hidden="true">
        {layout.areas.map((a) => {
          const [x, y] = toScreen(v, a.x, a.y - a.r)
          return (
            <div key={a.id} className="kg-alabel" data-dim={dim} style={{ left: x, top: y - 4 }}>
              <b>{a.name}</b>
              <span>{a.sub}</span>
            </div>
          )
        })}
        {labels.map((l) => (
          <div key={l.id} className={l.cls} style={{ left: l.x, top: l.y }}>
            {l.text}
          </div>
        ))}
      </div>
      </div>

      {page && activeDot && <HoverCard index={index} page={page} dot={activeDot} view={v} stage={size} />}

      <div className="kg-toolbar" onPointerDown={(e) => e.stopPropagation()}>
        <button ref={toolbarRef} type="button" className="btn btn--ghost" aria-label="Zoom in" title="Zoom in (+)" onClick={() => zoomBy(1.25)}>
          +
        </button>
        <button type="button" className="btn btn--ghost" aria-label="Zoom out" title="Zoom out (−)" onClick={() => zoomBy(0.8)}>
          −
        </button>
        <button type="button" className="btn btn--ghost" aria-label="Fit to screen" title="Fit to screen (0)" onClick={() => setView(fit)}>
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
            <path d="M2 6V2h4M10 2h4v4M14 10v4h-4M6 14H2v-4" />
          </svg>
        </button>
        <span className="kg-toolbar__sep" aria-hidden="true" />
        <span className="kg-hint" id="kg-stage-help">
          <span>Hover a dot to focus it</span>
          <span>Click to open</span>
          <span>Scroll to zoom · drag to pan</span>
          <span className="kg-sr">Arrow keys or Tab move between pages, Enter opens, Esc leaves the map.</span>
        </span>
      </div>

      <div className="kg-legend" aria-label="Legend" role="note">
        <span className="kg-legend__item">
          <svg viewBox="0 0 22 12" aria-hidden="true">
            <circle className="kg-dot kg-dot--hub" cx="6" cy="6" r="5" />
            <circle className="kg-dot" cx="17" cy="6" r="2.5" />
          </svg>
          big dot = hub (many links)
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
            <circle className="kg-area" cx="11" cy="6" r="6" />
          </svg>
          grey area = topic
        </span>
        <span className="kg-legend__item">
          <svg viewBox="0 0 22 12" aria-hidden="true">
            <circle className="kg-dot kg-dot--unlinked" cx="11" cy="6" r="4" />
          </svg>
          page with no links yet
        </span>
      </div>

      <div className="kg-sr" aria-live="polite">
        {active?.via === 'keyboard' ? announce : ''}
      </div>
    </div>
  )
}
