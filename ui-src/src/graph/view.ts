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
  /** Where it ended up: above the area, inside its top, or below it. */
  at: 'above' | 'inside' | 'below'
  rect: Rect
  /** The "N pages · subjects" line fits (dropped when even the name alone had to squeeze in). */
  withSub: boolean
}

/** Estimated size of a topic name (graph.css .kg-alabel: 12px name, 11px line under it). */
export function areaLabelSize(name: string, sub: string, withSub: boolean): { w: number; h: number } {
  const w = Math.max(name.length * 12 * 0.6, withSub ? Math.min(260, sub.length * 11 * 0.56) : 0) + 16
  return { w, h: withSub ? 34 : 20 }
}

function rectHitsCircle(r: Rect, c: { x: number; y: number; r: number }): boolean {
  const nx = Math.max(r[0], Math.min(c.x, r[2]))
  const ny = Math.max(r[1], Math.min(c.y, r[3]))
  const dx = c.x - nx
  const dy = c.y - ny
  return dx * dx + dy * dy < c.r * c.r
}

/**
 * Places each topic name where it touches no other topic area and no other name (operator,
 * 2026-11-14: names lay on top of neighbouring topics): above its area, else inside its top,
 * else below it; then the same without the "N pages" line; else above anyway (never dropped).
 */
export function placeAreaLabels(areas: AreaLabelInput[]): AreaLabelPlace[] {
  const placed: AreaLabelPlace[] = []
  const gap = 4
  for (const a of areas) {
    const others = areas.filter((o) => o.id !== a.id)
    let chosen: AreaLabelPlace | null = null
    for (const withSub of [true, false]) {
      const { w, h } = areaLabelSize(a.name, a.sub, withSub)
      const spots: [AreaLabelPlace['at'], number][] = [
        ['above', a.y - a.r - gap - h],
        ['inside', a.y - a.r + Math.max(6, a.r * 0.12)],
        ['below', a.y + a.r + gap],
      ]
      for (const [at, top] of spots) {
        const rect: Rect = [a.x - w / 2, top, a.x + w / 2, top + h]
        // Inside must fit within the area's width at that height.
        if (at === 'inside' && (h > a.r || w > a.r * 1.7)) continue
        if (others.some((o) => rectHitsCircle(rect, o))) continue
        if (placed.some((p) => overlaps(rect, p.rect))) continue
        chosen = { id: a.id, x: a.x, top, at, rect, withSub }
        break
      }
      if (chosen) break
    }
    if (!chosen) {
      const { w, h } = areaLabelSize(a.name, a.sub, true)
      const top = a.y - a.r - gap - h
      chosen = { id: a.id, x: a.x, top, at: 'above', rect: [a.x - w / 2, top, a.x + w / 2, top + h], withSub: true }
    }
    placed.push(chosen)
  }
  return placed
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
