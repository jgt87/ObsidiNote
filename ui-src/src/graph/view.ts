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
/** "Fit to screen" never zooms in further than this: a vault with a few pages keeps normal-sized dots. */
export const MAX_FIT = 1.6

/** Viewport that shows the whole bounds centred in a w x h stage. */
export function fitViewport(b: Bounds, w: number, h: number): Viewport {
  if (w <= 0 || h <= 0 || b.w <= 0 || b.h <= 0) return { x: b.x, y: b.y, k: 1 }
  const k = Math.min(w / b.w, h / b.h, MAX_FIT)
  return { k, x: b.x - (w / k - b.w) / 2, y: b.y - (h / k - b.h) / 2 }
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

/** Greedy: keeps labels in the given (priority) order, dropping any that would overlap a kept one. */
export function placeLabels(candidates: LabelBox[]): LabelBox[] {
  const kept: LabelBox[] = []
  const rects: [number, number, number, number][] = []
  for (const c of candidates) {
    const r = labelRect(c)
    if (rects.some((k) => r[0] < k[2] && r[2] > k[0] && r[1] < k[3] && r[3] > k[1])) continue
    kept.push(c)
    rects.push(r)
  }
  return kept
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
