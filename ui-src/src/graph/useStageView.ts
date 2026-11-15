// The map stage's size and viewport, with cheap pan and zoom: while a wheel or drag gesture runs,
// the picture moves with a CSS transform only (composited); the real viewport is committed when the
// gesture settles. Used by GraphStage.tsx.
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type RefObject } from 'react'
import { flushSync } from 'react-dom'
import type { GraphLayout } from './layout'
import { FIT_BOTTOM, fitViewport, MIN_ZOOM_FACTOR, needsSharp, zoomAt, type Viewport } from './view'

export function useStageView(stageRef: RefObject<HTMLDivElement | null>, layout: GraphLayout) {
  const [size, setSize] = useState<{ w: number; h: number }>({ w: 0, h: 0 })
  const [view, setView] = useState<Viewport | null>(null)
  const layerRef = useRef<HTMLDivElement>(null)
  const live = useRef<Viewport | null>(null)
  const timer = useRef(0)
  const drawnAt = useRef(0)

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

  const fit = useMemo(() => fitViewport(layout.bounds, size.w, size.h, FIT_BOTTOM), [layout.bounds, size.w, size.h])
  // A new layout or the first measurement: show everything.
  useEffect(() => {
    if (size.w > 0) setView(fit)
  }, [layout, size.w > 0]) // eslint-disable-line react-hooks/exhaustive-deps
  const v = view ?? fit
  const viewRef = useRef(v)
  viewRef.current = v
  const minK = fit.k * MIN_ZOOM_FACTOR
  /** The viewport the picture shows right now (mid-gesture: the one not committed yet). */
  const current = useCallback(() => live.current ?? viewRef.current, [])

  const commit = useCallback(() => {
    window.clearTimeout(timer.current)
    const next = live.current
    if (!next) return
    live.current = null
    flushSync(() => setView(next))
    drawnAt.current = performance.now()
    if (layerRef.current) layerRef.current.style.transform = ''
    stageRef.current?.removeAttribute('data-moving')
  }, [stageRef])
  const preview = useCallback(
    (next: Viewport, settle: number) => {
      live.current = next
      const base = viewRef.current
      // A zoom-in that has stretched the last drawing far enough is drawn again at once, so the
      // circles and names stay sharp while the wheel keeps turning (view.ts needsSharp).
      if (needsSharp(next.k / base.k, performance.now() - drawnAt.current, layout.dots.length)) {
        commit()
        return
      }
      const tx = (base.x - next.x) * next.k
      const ty = (base.y - next.y) * next.k
      if (layerRef.current) layerRef.current.style.transform = `translate(${tx}px, ${ty}px) scale(${next.k / base.k})`
      stageRef.current?.setAttribute('data-moving', 'true')
      window.clearTimeout(timer.current)
      timer.current = window.setTimeout(commit, settle)
    },
    [commit, stageRef, layout.dots.length],
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
      preview(zoomAt(current(), factor, e.clientX - r.left, e.clientY - r.top, minK), 140)
    }
    el.addEventListener('wheel', onWheel, { passive: false })
    return () => el.removeEventListener('wheel', onWheel)
  }, [stageRef, preview, minK, current])

  // Buttons and +/- keys: the same cheap preview, committed after a short pause (repeated
  // presses stay smooth).
  const zoomBy = useCallback((factor: number) => preview(zoomAt(current(), factor, size.w / 2, size.h / 2, minK), 220), [preview, size, minK, current])

  return { size, v, fit, setView, layerRef, current, preview, commit, zoomBy }
}
