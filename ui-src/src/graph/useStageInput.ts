// The map stage's pointer and keyboard handling (GraphStage.tsx). What a key does is decided in
// stageModel.ts stageKey; here the events are read and the results applied.
import { useEffect, useRef, useState, type FocusEvent, type KeyboardEvent, type PointerEvent as ReactPointerEvent, type RefObject } from 'react'
import type { Active } from './GraphStage'
import type { DotLayout, GraphLayout } from './layout'
import { areaAt, stageKey, type StageKeyAction } from './stageModel'
import { pan, toScreen, type Viewport } from './view'

const idOf = (t: EventTarget | null): string | null => (t instanceof Element ? t.getAttribute('data-id') : null)

export interface StagePointerInput {
  layout: GraphLayout
  stageRef: RefObject<HTMLDivElement | null>
  /** The viewport the picture shows right now (mid-gesture too). */
  current: () => Viewport
  preview: (next: Viewport, settle: number) => void
  commit: () => void
  active: Active | null
  onActive: (a: Active | null) => void
  onOpen: (id: string, via?: 'pointer' | 'keyboard') => void
  /** Pages the filters leave visible: the pointer reaches every one of them. */
  isShown: (id: string) => boolean
}

/**
 * Hover focuses a page, a click opens it, a drag pans. The area under the pointer is tracked (its
 * name gives way so it never covers the pages). A resting pointer "enters" new dots when the
 * keyboard redraws the focus layer under it; hover takes over only after the pointer really moves.
 * A click anywhere outside the map closes a card the keyboard left open (a pointer card closes when
 * the pointer leaves its dot); not while the page window is open: it sits on top.
 */
export function useStagePointer({ layout, stageRef, current, preview, commit, active, onActive, onOpen, isShown }: StagePointerInput) {
  const [dragging, setDragging] = useState(false)
  /** The topic area under the pointer (its name is hidden while it is). */
  const [hoverArea, setHoverArea] = useState<string | null>(null)
  const drag = useRef<{ x: number; y: number; id: string | null; moved: boolean; pointer: number } | null>(null)
  /** The stage got focus from this click: a keyboard focus handler leaves it alone. */
  const pointerFocus = useRef(false)
  const keyboardMode = useRef(false)
  const viaKeyboard = active?.via === 'keyboard'

  useEffect(() => {
    if (viaKeyboard) keyboardMode.current = true
  }, [active]) // eslint-disable-line react-hooks/exhaustive-deps
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

  return {
    dragging,
    hoverArea,
    pointerFocus,
    svgHandlers: {
      onPointerDown,
      onPointerMove,
      onPointerUp,
      onPointerCancel: onPointerUp,
      onPointerOver,
      onPointerOut,
      onPointerLeave: () => setHoverArea(null),
    },
  }
}

export interface StageKeyboardInput {
  layout: GraphLayout
  active: Active | null
  activeDot: DotLayout | null
  /** The visible dots in their keyboard order. */
  order: DotLayout[]
  visible: (id: string) => boolean
  onActive: (a: Active | null) => void
  onOpen: (id: string, via?: 'pointer' | 'keyboard') => void
  onFocusPage?: (id: string) => void
  zoomBy: (factor: number) => void
  fit: Viewport
  v: Viewport
  size: { w: number; h: number }
  setView: (v: Viewport) => void
  /** Esc leaves the map for its toolbar's first button. */
  toolbarRef: RefObject<HTMLButtonElement | null>
  pointerFocus: RefObject<boolean>
}

/** The map's keys (stageModel.ts stageKey), focus and blur; keyboard focus keeps the active dot on
 *  screen. */
export function useStageKeyboard({ layout, active, activeDot, order, visible, onActive, onOpen, onFocusPage, zoomBy, fit, v, size, setView, toolbarRef, pointerFocus }: StageKeyboardInput) {
  const viaKeyboard = active?.via === 'keyboard'
  useEffect(() => {
    if (!activeDot || !viaKeyboard || !size.w) return
    const [sx, sy] = toScreen(v, activeDot.x, activeDot.y)
    const m = 48
    if (sx < m || sy < m || sx > size.w - m || sy > size.h - m) {
      setView({ k: v.k, x: activeDot.x - size.w / 2 / v.k, y: activeDot.y - size.h / 2 / v.k })
    }
  }, [activeDot, active?.via]) // eslint-disable-line react-hooks/exhaustive-deps

  const run = (a: StageKeyAction) => {
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
    if (r.action) run(r.action)
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
  return { onKeyDown, onFocus, onBlur }
}
