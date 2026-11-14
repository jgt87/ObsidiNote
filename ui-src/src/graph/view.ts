// Pure helpers for the interactive map: viewport maths, keyboard moves, search and focus sets.

import type { GraphIndex } from './graphIndex'
import type { Bounds, DotLayout } from './layout'
import { parseQuery, rankPages } from '../search/query'

/** screen = (world - (x, y)) * k */
export interface Viewport {
  x: number
  y: number
  k: number
}

export const MIN_ZOOM_FACTOR = 0.5
export const MAX_ZOOM = 8
/** "Fit to screen" never zooms in further than this. A small vault fills the frame (operator,
 *  2026-11-14: 25 pages used a third of it at 1.6); labels are screen pixels, so they keep their size. */
export const MAX_FIT = 2.5
/** Up to this many visible pages, every page is named (unless "Labels: hubs only" is on). */
export const ALL_LABELS_UP_TO = 60
/** Zoomed in this far past "fit", every page in view is named. */
export const ALL_LABELS_ZOOM = 1.8

/** Which pages get a name: all of them on a small or zoomed-in map, else the hubs. */
export function labelMode(visiblePages: number, k: number, fitK: number, hubsOnly: boolean): 'all' | 'hubs' {
  if (hubsOnly) return 'hubs'
  return visiblePages <= ALL_LABELS_UP_TO || k >= fitK * ALL_LABELS_ZOOM ? 'all' : 'hubs'
}

/** Zoom (against the fitted view) from which every topic line shows instead of the heaviest
 *  (operator, 2026-11-14: zooming in should reveal all topic lines). */
export const ALL_LINES_ZOOM = 1.5

/** Which topic lines show: all when zoomed in to ALL_LINES_ZOOM or more, else the resting set. */
export function lineMode(k: number, fitK: number): 'all' | 'resting' {
  return k >= fitK * ALL_LINES_ZOOM - 1e-9 ? 'all' : 'resting'
}

/** Stage pixels kept free at the bottom for the toolbar and legend, so the fitted picture never
 *  runs under them (2026-11-14: a topic and its name sat behind the legend). */
export const FIT_BOTTOM = 52

/** Viewport that shows the whole bounds centred in a w x h stage, above `bottom` reserved pixels. */
export function fitViewport(b: Bounds, w: number, h: number, bottom = 0): Viewport {
  const hh = h - bottom
  if (w <= 0 || hh <= 0 || b.w <= 0 || b.h <= 0) return { x: b.x, y: b.y, k: 1 }
  const k = Math.min(w / b.w, hh / b.h, MAX_FIT)
  return { k, x: b.x - (w / k - b.w) / 2, y: b.y - (hh / k - b.h) / 2 }
}

/** Zoom by `factor` keeping the world point under screen (sx, sy) in place. */
export function zoomAt(v: Viewport, factor: number, sx: number, sy: number, minK: number, maxK = MAX_ZOOM): Viewport {
  const k = Math.min(maxK, Math.max(minK, v.k * factor))
  const wx = v.x + sx / v.k
  const wy = v.y + sy / v.k
  return { k, x: wx - sx / k, y: wy - sy / k }
}

export function pan(v: Viewport, dxScreen: number, dyScreen: number): Viewport {
  return { k: v.k, x: v.x - dxScreen / v.k, y: v.y - dyScreen / v.k }
}

export function toScreen(v: Viewport, x: number, y: number): [number, number] {
  return [(x - v.x) * v.k, (y - v.y) * v.k]
}

export type Direction = 'left' | 'right' | 'up' | 'down'

/**
 * The dot an arrow key moves to: the nearest dot within a 90 degree cone in that direction,
 * preferring dots straight ahead. Null when there is none.
 */
export function nextInDirection(dots: DotLayout[], from: DotLayout, dir: Direction, visible?: (id: string) => boolean): DotLayout | null {
  const [ux, uy] = dir === 'left' ? [-1, 0] : dir === 'right' ? [1, 0] : dir === 'up' ? [0, -1] : [0, 1]
  let best: DotLayout | null = null
  let bestScore = Infinity
  for (const d of dots) {
    if (d.id === from.id || (visible && !visible(d.id))) continue
    const dx = d.x - from.x
    const dy = d.y - from.y
    const along = dx * ux + dy * uy
    const across = Math.abs(dx * uy - dy * ux)
    if (along <= 0 || across > along) continue
    const score = along + across * 2
    if (score < bestScore) {
      bestScore = score
      best = d
    }
  }
  return best
}

/** Search: free words and filters (src/search/query.ts), best match first; [] for an empty query. */
export function searchPages(index: GraphIndex, query: string): string[] {
  return rankPages(index, parseQuery(query)).map((r) => r.id)
}

export interface LabelBox {
  id: string
  text: string
  /** Screen anchor: bottom centre of the label. */
  x: number
  y: number
  /** Font size in px, for the width estimate. */
  px: number
  cls: string
}

/** Estimated label rectangle [left, top, right, bottom] with its pill (graph.css .kg-plabel: padding
 *  and border; max width 220 px, 320 px for the focused page's label). */
export function labelRect(l: LabelBox): [number, number, number, number] {
  const on = l.cls.includes('kg-plabel--on')
  const w = Math.min(on ? 320 : 220, l.text.length * l.px * 0.56 + (on ? 26 : 18))
  const h = l.px * 1.25 + (on ? 9 : 7)
  return [l.x - w / 2, l.y - h, l.x + w / 2, l.y]
}

export type Rect = [number, number, number, number]

const overlaps = (r: Rect, k: Rect) => r[0] < k[2] && r[2] > k[0] && r[1] < k[3] && r[3] > k[1]

/** Greedy: keeps labels in the given (priority) order, dropping any that would overlap a kept one
 *  or a rectangle already taken (the topic names). */
export function placeLabels(candidates: LabelBox[], taken: Rect[] = []): LabelBox[] {
  const kept: LabelBox[] = []
  const rects: Rect[] = [...taken]
  for (const c of candidates) {
    const r = labelRect(c)
    if (rects.some((k) => overlaps(r, k))) continue
    kept.push(c)
    rects.push(r)
  }
  return kept
}

// ---------- topic names ----------

export interface AreaLabelInput {
  id: string
  /** Area circle in screen pixels. */
  x: number
  y: number
  r: number
  name: string
  sub: string
}

export interface AreaLabelPlace {
  id: string
  /** Top centre of the label, screen pixels. */
  x: number
  top: number
  /** Always centred on its own area (operator, 2026-11-14); kept as a field for the CSS hook. */
  at: 'center'
  rect: Rect
  /** The "N pages · subjects" line fits (dropped when even the name alone had to squeeze in). */
  withSub: boolean
  /** The name as drawn: shortened with "…" when the full name is wider than its area. */
  text: string
}

/** Estimated size of a topic name (graph.css .kg-alabel: 14px bold name, 11px line under it). */
export function areaLabelSize(name: string, sub: string, withSub: boolean): { w: number; h: number } {
  const w = Math.max(name.length * 14 * 0.62, withSub ? Math.min(260, sub.length * 11 * 0.56) : 0) + 16
  return { w, h: withSub ? 36 : 22 }
}

/**
 * Each topic name centred on its own area (operator, 2026-11-14: names above or below an area sat
 * in the gaps where the topic lines run; centred, a name never meets a line, and the stage hides it
 * while the pointer is over its area so it never blocks the pages). With the "N pages · subjects"
 * line when that fits inside the area, else the name alone; a name wider than its area is shortened
 * with "…" (code review 2026-11-14: a long SharePoint site name on a one-page area covered its
 * neighbours). On an area too small for even a few letters, a name that would still cover another
 * area or a bigger area's name is left out (larger areas keep theirs first); the area's pages and
 * the List still carry it.
 */
export function placeAreaLabels(areas: AreaLabelInput[]): AreaLabelPlace[] {
  const placed = areas.map((a) => {
    const full = areaLabelSize(a.name, a.sub, true)
    const withSub = full.h <= a.r && full.w <= a.r * 1.7
    const text = shortenToWidth(a.name, a.r * 1.8)
    const { w, h } = withSub ? full : areaLabelSize(text, a.sub, false)
    const top = a.y - h / 2
    return { id: a.id, x: a.x, top, at: 'center' as const, rect: [a.x - w / 2, top, a.x + w / 2, top + h] as Rect, withSub, text: withSub ? a.name : text }
  })
  const byId = new Map(areas.map((a) => [a.id, a]))
  const order = [...placed].sort((p, q) => byId.get(q.id)!.r - byId.get(p.id)!.r)
  const kept = new Set<string>()
  const keptRects: Rect[] = []
  for (const p of order) {
    const onOther = areas.some((o) => o.id !== p.id && rectHitsCircle(p.rect, o))
    if (onOther || keptRects.some((k) => overlaps(p.rect, k))) continue
    kept.add(p.id)
    keptRects.push(p.rect)
  }
  return placed.filter((p) => kept.has(p.id))
}

/** A name cut to fit `maxW` screen px (areaLabelSize's estimate), with "…"; at least 3 letters. */
export function shortenToWidth(name: string, maxW: number): string {
  if (areaLabelSize(name, '', false).w <= maxW) return name
  const chars = Math.max(4, Math.floor((maxW - 16) / (14 * 0.62)))
  return chars >= name.length ? name : name.slice(0, chars - 1).trimEnd() + '…'
}

function rectHitsCircle(r: Rect, c: { x: number; y: number; r: number }): boolean {
  const nx = Math.max(r[0], Math.min(c.x, r[2]))
  const ny = Math.max(r[1], Math.min(c.y, r[3]))
  return Math.hypot(c.x - nx, c.y - ny) < c.r
}

// ---------- hover card ----------

/**
 * Where the preview card goes: of the four corners around the dot, the first that stays on the
 * stage and covers the fewest linked pages (operator, 2026-11-14: the card hid the very links it
 * was about). Order on a tie: right-below, right-above, left-below, left-above.
 */
export function cardPosition(
  dot: { x: number; y: number },
  offset: number,
  near: { x: number; y: number }[],
  stage: { w: number; h: number },
  size: { w: number; h: number },
): { left: number; top: number } {
  const m = 8
  const spots = [
    { left: dot.x + offset, top: dot.y + offset },
    { left: dot.x + offset, top: dot.y - offset - size.h },
    { left: dot.x - offset - size.w, top: dot.y + offset },
    { left: dot.x - offset - size.w, top: dot.y - offset - size.h },
  ]
  let best = spots[0]
  let bestScore = Infinity
  for (const s of spots) {
    const out = s.left < m || s.top < m || s.left + size.w > stage.w - m || s.top + size.h > stage.h - m
    const covered = near.filter((p) => p.x > s.left - 6 && p.x < s.left + size.w + 6 && p.y > s.top - 6 && p.y < s.top + size.h + 6).length
    const score = (out ? 1000 : 0) + covered
    if (score < bestScore) {
      bestScore = score
      best = s
    }
  }
  return {
    left: Math.max(m, Math.min(best.left, stage.w - size.w - m)),
    top: Math.max(m, Math.min(best.top, stage.h - size.h - m)),
  }
}

/** The focused page and its direct neighbours (the set that stays sharp). */
export function focusSet(index: GraphIndex, id: string | null): Set<string> {
  if (!id) return new Set()
  return new Set([id, ...(index.neighbours.get(id) ?? [])])
}

/**
 * Previous/next linked page for the dialog's arrow keys: the page the dialog was opened on
 * (anchor), then its linked pages strongest first; wraps round. Null when it has no links.
 */
export function stepLinked(index: GraphIndex, anchor: string, current: string, delta: 1 | -1): string | null {
  const neighbours = index.neighbours.get(anchor) ?? []
  if (!neighbours.length) return null
  const list = [anchor, ...neighbours]
  const i = list.indexOf(current)
  if (i < 0) return delta > 0 ? list[1] : list[list.length - 1]
  return list[(i + delta + list.length) % list.length]
}
