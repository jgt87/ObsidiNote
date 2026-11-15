// Layout of the knowledge graph. Pure and deterministic: the same model always gives the same
// picture (no Math.random, no clock, no locale-dependent sorting).
//
// 1. Topic areas: one circle per topic that is the primary topic of at least one page (plus
//    "Unfiled" when needed), in topic-tree order (depth first, siblings by path). Each is packed
//    tangent to the areas already placed, at the free spot that keeps the picture smallest when
//    fitted to the stage (so the areas fill the stage's shape) and close to its parent area (a
//    subtopic) or the centre. Areas never overlap.
// 2. Pages: inside their primary topic's area. Hubs and well-linked pages start in the middle
//    (sunflower order), then a few hundred cheap steps pull linked pages together, push dots
//    apart and keep every dot inside its area (link-density clustering).
// 3. Edges: quadratic curves whose control point sits off the midpoint, perpendicular to the line.

import { buildIndex, type GraphIndex } from './graphIndex'
import { areaLabelSize, labelSlot, NAME_H } from './labelSize'
import { groupLabelSize } from './labelSize'
import { primaryTopic, UNFILED_ID, type GraphEdge, type GraphModel, type GraphPage, type GraphTopic } from './model'

export interface AreaLayout {
  id: string
  /** null for the Unfiled area. */
  topic: GraphTopic | null
  name: string
  /** "N pages · subjects" */
  sub: string
  x: number
  y: number
  r: number
  pageIds: string[]
  /** The room in the middle kept free of dots for the name (labelSize.ts labelSlot): half extents. */
  slot: { hw: number; hh: number }
  /** Names of the groups inside the area (pages with a `group`, the Tags grouping), each where
   *  it lies on no dot, not on the area's name and inside the area; a group without such a place
   *  has no name here (the hover card still names the page's topic). */
  groups?: GroupLabel[]
}

/** A group's name inside an area: `x` = its centre, `y` = its top, in layout units. */
export interface GroupLabel {
  id: string
  name: string
  count: number
  x: number
  y: number
  w: number
  h: number
}

export interface DotLayout {
  id: string
  area: string
  x: number
  y: number
  r: number
  hub: boolean
  unlinked: boolean
}

export interface EdgeLayout {
  edge: GraphEdge
  /** SVG path data "M ax ay Q cx cy bx by". */
  d: string
}

export interface Bounds {
  x: number
  y: number
  w: number
  h: number
}

export interface GraphLayout {
  areas: AreaLayout[]
  dots: DotLayout[]
  dotById: Map<string, DotLayout>
  edges: EdgeLayout[]
  /** World rectangle that holds every area and its label. */
  bounds: Bounds
}

export interface LayoutOptions {
  /** Width / height of the stage the picture is fitted to (areas spread to match). */
  aspect?: number
}

export const AREA_GAP = 36
/** Room kept above and below an area for its name: none since the names sit centred inside their
 *  areas (operator, 2026-11-14; was 34 for a name above or below). */
export const LABEL_SPACE = 0
const CURVE = 0.18

// ---------- small helpers ----------

/** Plain code-unit comparison: stable in every locale. */
function cmp(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}

/** FNV-1a hash of a string, for per-item deterministic jitter. */
export function hash(s: string): number {
  let h = 0x811c9dc5
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return h >>> 0
}

function round(n: number): number {
  return Math.round(n * 10) / 10
}

/** Smallest and largest dot. */
export const DOT_MIN_R = 3
export const DOT_MAX_R = 11

/** Dot size from the page's link weight (weights.ts): one smooth scale, so 1 and 4 links differ
 *  and there is no jump at a hub threshold (operator, 2026-11-14: radius went 4.4 -> 8.3 between
 *  4 and 5 links). A hub is marked by its thicker outline and its label, not by a jump in size. */
export function dotRadius(page: GraphPage): number {
  if (page.unlinked || page.weight <= 0) return DOT_MIN_R
  return Math.min(DOT_MAX_R, 3.2 + Math.sqrt(page.weight) * 1.25)
}

/**
 * The links as drawn: one line per pair of pages and kind (two pages that link each other get one
 * line, with the stronger strength), in the order the edges came. The page dialog and the edit form
 * keep both directions (graphIndex out/in); only the drawing merges them.
 */
export function onePerPair(edges: GraphEdge[]): GraphEdge[] {
  const at = new Map<string, number>()
  const out: GraphEdge[] = []
  for (const e of edges) {
    const key = `${e.kind}:${e.from < e.to ? `${e.from}|${e.to}` : `${e.to}|${e.from}`}`
    const i = at.get(key)
    if (i === undefined) {
      at.set(key, out.length)
      out.push(e)
    } else if (e.strength > out[i].strength) out[i] = { ...out[i], strength: e.strength }
  }
  return out
}

/** Control point of the curved edge from a to b. */
export function controlPoint(ax: number, ay: number, bx: number, by: number): [number, number] {
  const mx = (ax + bx) / 2
  const my = (ay + by) / 2
  return [mx - (by - ay) * CURVE, my + (bx - ax) * CURVE]
}

export function edgePath(ax: number, ay: number, bx: number, by: number): string {
  const [cx, cy] = controlPoint(ax, ay, bx, by)
  return `M${round(ax)} ${round(ay)}Q${round(cx)} ${round(cy)} ${round(bx)} ${round(by)}`
}

// ---------- 1. topic areas ----------

/** Topic ids in tree order (depth first; siblings and roots sorted by path, then id). */
export function topicOrder(topics: GraphTopic[]): GraphTopic[] {
  const children = new Map<string | null, GraphTopic[]>()
  for (const t of topics) {
    const list = children.get(t.parent) ?? []
    list.push(t)
    children.set(t.parent, list)
  }
  for (const list of children.values()) list.sort((a, b) => cmp(a.path, b.path) || cmp(a.id, b.id))
  const out: GraphTopic[] = []
  const seen = new Set<string>()
  const walk = (parent: string | null) => {
    for (const t of children.get(parent) ?? []) {
      if (seen.has(t.id)) continue
      seen.add(t.id)
      out.push(t)
      walk(t.id)
    }
  }
  walk(null)
  // Anything left (a parent cycle) still gets a place, in id order.
  for (const t of [...topics].sort((a, b) => cmp(a.id, b.id))) if (!seen.has(t.id)) out.push(t)
  return out
}

/** Smallest area: a topic, and the Unfiled area (only as big as its few pages need; operator,
 *  2026-11-14: two unfiled pages got as much room as a full topic). */
export const MIN_AREA_R = 52
export const MIN_UNFILED_R = 30

function areaRadius(dotRadii: number[], min = MIN_AREA_R, name = '', scale = 1): number {
  let sum = 0
  for (const r of dotRadii) sum += (r + 4.5) * (r + 4.5)
  // design: dots fill about 40% of an area, so a topic reads as a roomy grey field with its
  // pages spread inside (the README map), not a tight clump. The room kept free for the name
  // (labelSlot) comes on top, so the dots are not squeezed by it. Sized by the name alone: its page
  // count fits in the 40% slack (taking it into the size moved the areas, and bent topic lines).
  const nameRoom = name ? Math.min(areaLabelSize(name).w, 220) * NAME_H * scale * scale : 0
  return Math.max(min, Math.sqrt(sum / 0.4 + nameRoom) + 14)
}

interface Circle {
  x: number
  y: number
  r: number
}

/** Packs circles in order; each goes to the free tangent spot nearest its target. A circle marked
 *  `outer` (Unfiled) is not pulled to the centre, so it lands at the rim of the picture. */
/** How strongly Unfiled is pushed to the rim, against the size of the fitted picture: small, so it
 *  takes the farthest spot that keeps the fitted size (it uses the stage's spare height or width). */
const OUTER_PUSH = 0.1

/** Cost, in fitted-picture px, of a topic line that would have to pass another area (operator,
 *  2026-11-14: the areas are placed so that topic lines do not pass under other topics; a line is
 *  bent around one only where no placement avoids it). */
export const CROSS_PENALTY = 30
/** Clearance a topic line keeps from an area it passes (world px), for the placement check. */
const CROSS_CLEARANCE = 6

/**
 * Packs circles in the given order; each goes to the free tangent spot with the lowest score:
 * the size of the picture fitted to the stage, plus the distance to its parent (a subtopic stays
 * next to it) or to the circles it has links with (`links[i][j]`, summed link strength), plus
 * CROSS_PENALTY for every topic line that the spot would make pass another circle: its own lines
 * to placed circles, and the placed lines it would sit on. A circle marked `outer` (Unfiled) goes
 * to the rim.
 */
export function packAreas(radii: number[], targets: (number | null)[], aspect: number, gap = AREA_GAP, outer: boolean[] = [], links: number[][] = []): Circle[] {
  const placed: Circle[] = []
  const box = { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity }
  const steps = 36
  // The linked pairs among the placed circles, kept as circles are placed, so the crossing check
  // per candidate spot only walks real lines, not every pair (code review 2026-11-14: all pairs per
  // spot grow with the 4th power of the area count; 200 areas 857 ms -> 229 ms, layout.test.ts).
  const placedLines: Line[] = []
  for (let i = 0; i < radii.length; i++) {
    const r = radii[i]
    if (i === 0) {
      placed.push({ x: 0, y: 0, r })
      grow(box, placed[0])
      continue
    }
    const mine: Line[] = []
    for (let j = 0; j < placed.length; j++) {
      const w = links[i]?.[j] ?? 0
      if (w > 0) mine.push({ j, k: i, w })
    }
    const t = targets[i]
    const tx = t === null ? 0 : placed[t].x
    const ty = t === null ? 0 : placed[t].y
    let best: Circle | null = null
    let bestScore = Infinity
    for (const p of placed) {
      const d = p.r + r + gap
      for (let k = 0; k < steps; k++) {
        const a = (k / steps) * Math.PI * 2
        const x = p.x + Math.cos(a) * d
        const y = p.y + Math.sin(a) * d
        let ok = true
        for (const q of placed) {
          const dx = q.x - x
          const dy = q.y - y
          const min = q.r + r + gap - 1e-6
          if (dx * dx + dy * dy < min * min) {
            ok = false
            break
          }
        }
        if (!ok) continue
        // Two parts: how big the picture gets when fitted to the stage (width over the aspect,
        // or height with label space, whichever is larger), so the areas fill the stage's shape;
        // and the distance to the target (x shrunk by the aspect). A subtopic weighs the
        // distance to its parent far more, so it stays next to it.
        const fw = (Math.max(box.maxX, x + r) - Math.min(box.minX, x - r)) / aspect
        const fh = Math.max(box.maxY, y + r + LABEL_SPACE) - Math.min(box.minY, y - r - LABEL_SPACE)
        const sx = (x - tx) / aspect
        const sy = y - ty
        // Unfiled (outer) is pushed away from the picture's centre, so it ends up at the rim and
        // not in a gap between topics (no pull alone let it fill a gap once dot sizes changed).
        let score = Math.max(fw, fh)
        if (outer[i]) score -= Math.hypot((x - (box.minX + box.maxX) / 2) / aspect, y - (box.minY + box.maxY) / 2) * OUTER_PUSH
        else if (t !== null) score += Math.sqrt(sx * sx + sy * sy) * 4
        else score += linkPull(i, x, y, placed, links, aspect) * 0.35
        if (mine.length || placedLines.length) score += crossings({ x, y, r }, placed, mine, placedLines) * CROSS_PENALTY
        if (score < bestScore - 1e-9) {
          bestScore = score
          best = { x, y, r }
        }
      }
    }
    const c = best ?? { x: 0, y: 0, r }
    placed.push(c)
    grow(box, c)
    placedLines.push(...mine)
  }
  return placed
}

/** A topic line between placed circles j and k (k placed later), with its summed strength. */
interface Line { j: number; k: number; w: number }

/** Mean distance from (x, y) to the placed circles linked to i, weighted by link strength (x shrunk
 *  by the aspect); the distance to the centre when i has no links to placed circles. */
function linkPull(i: number, x: number, y: number, placed: Circle[], links: number[][], aspect: number): number {
  let sum = 0
  let w = 0
  for (let j = 0; j < placed.length; j++) {
    const lw = links[i]?.[j] ?? 0
    if (lw <= 0) continue
    sum += Math.hypot((x - placed[j].x) / aspect, y - placed[j].y) * lw
    w += lw
  }
  return w > 0 ? sum / w : Math.hypot(x / aspect, y)
}

/** Topic lines that would pass another circle if the new circle sat at c, weighted by their strength
 *  (so the strongest lines, the ones shown at rest, get a clear way first): its own lines (`mine`, to
 *  linked placed circles) that pass a third one, and the placed lines that pass c. */
function crossings(c: Circle, placed: Circle[], mine: Line[], placedLines: Line[]): number {
  let n = 0
  for (const { j, w } of mine) {
    for (let k = 0; k < placed.length; k++) {
      if (k === j) continue
      if (segmentDistance(c, placed[j], placed[k]).d < placed[k].r + CROSS_CLEARANCE) {
        n += w
        break
      }
    }
  }
  for (const { j, k, w } of placedLines) {
    if (segmentDistance(placed[j], placed[k], c).d < c.r + CROSS_CLEARANCE) n += w
  }
  return n
}

/**
 * The order the areas are packed in: the most linked root area first, then always the area with
 * the strongest links to the ones already placed (a subtopic only after its parent, which counts
 * as a link of PARENT_LINK), so linked topics are placed next to each other. `outer` areas last.
 * Ties keep the input (topic-tree) order. Returns indices into the input. Pure.
 */
export function packOrder(targets: (number | null)[], links: number[][], outer: boolean[] = []): number[] {
  const n = targets.length
  const total = (i: number) => (links[i] ?? []).reduce((s, w) => s + (w > 0 ? w : 0), 0)
  const placed = new Set<number>()
  const order: number[] = []
  const take = (i: number) => {
    placed.add(i)
    order.push(i)
  }
  let first = -1
  for (let i = 0; i < n; i++) if (!outer[i] && targets[i] === null && (first < 0 || total(i) > total(first))) first = i
  if (first >= 0) take(first)
  for (;;) {
    let best = -1
    let bestScore = -1
    for (let i = 0; i < n; i++) {
      if (placed.has(i) || outer[i]) continue
      const t = targets[i]
      if (t !== null && !placed.has(t)) continue
      let s = t !== null ? PARENT_LINK : 0
      for (const j of placed) s += Math.max(0, links[i]?.[j] ?? 0)
      if (s > bestScore) {
        bestScore = s
        best = i
      }
    }
    if (best < 0) break
    take(best)
  }
  for (let i = 0; i < n; i++) if (!placed.has(i)) take(i)
  return order
}

/** What a parent-subtopic relation counts as in packOrder (a core link). */
const PARENT_LINK = 3

function grow(box: { minX: number; maxX: number; minY: number; maxY: number }, c: Circle): void {
  box.minX = Math.min(box.minX, c.x - c.r)
  box.maxX = Math.max(box.maxX, c.x + c.r)
  box.minY = Math.min(box.minY, c.y - c.r - LABEL_SPACE)
  box.maxY = Math.max(box.maxY, c.y + c.r + LABEL_SPACE)
}

// ---------- 2. pages inside an area ----------

type Centre = { x: number; y: number }
/** A link inside the area: [dot i, dot j, strength]. */
type Spring = [number, number, number]
/** A link to another area: [dot i, that area's centre x, y, strength]. */
type Outward = [number, number, number, number]

/** The pages in the order they are seeded: most linked first, so they settle in the middle. */
function seedOrder(pages: GraphPage[]): GraphPage[] {
  return [...pages].sort((a, b) => Number(b.isHub) - Number(a.isHub) || b.weight - a.weight || b.links - a.links || cmp(a.id, b.id))
}

/** First positions: a sunflower spiral, rotated per area so areas do not look identical. */
function seedDots(area: AreaLayout, sorted: GraphPage[]): DotLayout[] {
  const n = sorted.length
  return sorted.map((p, i) => {
    const r = dotRadius(p)
    const rot = (hash(area.id) % 360) * (Math.PI / 180)
    const a = i * 2.39996323 + rot
    const d = n <= 1 ? 0 : (area.r - 10) * 0.82 * Math.sqrt((i + 0.5) / n)
    return { id: p.id, area: area.id, x: area.x + Math.cos(a) * d, y: area.y + Math.sin(a) * d, r, hub: p.isHub, unlinked: p.unlinked || p.links === 0 }
  })
}

/** Groups (only when every page has one and there are two or more): each gathers round its own
 *  point, half way out, the largest first, and its dots start there. Returns the points. */
function seedGroups(area: AreaLayout, sorted: GraphPage[], dots: DotLayout[]): Map<string, Centre> {
  const anchor = new Map<string, Centre>()
  const count = new Map<string, number>()
  for (const p of sorted) count.set(p.group!.id, (count.get(p.group!.id) ?? 0) + 1)
  const order = [...count.keys()].sort((a, b) => count.get(b)! - count.get(a)! || cmp(a, b))
  const rot = (hash(area.id) % 360) * (Math.PI / 180)
  order.forEach((g, i) => {
    const a = rot + (i * 2 * Math.PI) / order.length
    anchor.set(g, { x: area.x + Math.cos(a) * area.r * 0.52, y: area.y + Math.sin(a) * area.r * 0.52 })
  })
  const seen = new Map<string, number>()
  sorted.forEach((p, i) => {
    const g = p.group!.id
    const k = seen.get(g) ?? 0
    seen.set(g, k + 1)
    const c = anchor.get(g)!
    const d = area.r * 0.3 * Math.sqrt((k + 0.5) / count.get(g)!)
    dots[i].x = c.x + Math.cos(k * 2.39996323) * d
    dots[i].y = c.y + Math.sin(k * 2.39996323) * d
  })
  return anchor
}

/** The only page of an area sits under the name, not under its letters. */
function placeAlone(dots: DotLayout[], area: AreaLayout): DotLayout[] {
  for (const d of dots) {
    d.y = area.y + area.slot.hh + d.r + SLOT_MARGIN
    contain(d, area)
    d.x = round(d.x)
    d.y = round(d.y)
  }
  return dots
}

/** Springs: links inside the area pull together; links to other areas pull towards that area. */
function dotSprings(dots: DotLayout[], index: GraphIndex, areaCentre: Map<string, Centre>): { springs: Spring[]; outward: Outward[] } {
  const pos = new Map(dots.map((d, i) => [d.id, i]))
  const centreOf = (id: string) => {
    const other = index.pageById.get(id)
    return other ? areaCentre.get(primaryTopic(other)) : undefined
  }
  const springs: Spring[] = []
  const outward: Outward[] = []
  for (const d of dots) {
    const i = pos.get(d.id)!
    for (const e of index.out.get(d.id) ?? []) {
      const j = pos.get(e.to)
      const c = j === undefined ? centreOf(e.to) : undefined
      if (j !== undefined) springs.push([i, j, e.strength])
      else if (c) outward.push([i, c.x, c.y, e.strength])
    }
    for (const e of index.in.get(d.id) ?? []) {
      const c = pos.has(e.from) ? undefined : centreOf(e.from)
      if (c) outward.push([i, c.x, c.y, e.strength])
    }
  }
  return { springs, outward }
}

function placeDots(area: AreaLayout, pages: GraphPage[], index: GraphIndex, areaCentre: Map<string, Centre>): DotLayout[] {
  const sorted = seedOrder(pages)
  const n = sorted.length
  const dots = seedDots(area, sorted)
  const grouped = isGrouped(sorted)
  const anchor = grouped ? seedGroups(area, sorted, dots) : new Map<string, Centre>()
  if (n <= 1) return placeAlone(dots, area)
  const { springs, outward } = dotSprings(dots, index, areaCentre)

  const iterations = n > 400 ? 70 : n > 150 ? 110 : 160
  const maxR = dots.reduce((m, d) => Math.max(m, d.r), 0)
  // Hexagonal spacing at which n dots would fill 95% of the area; dots keep 90% of it apart, so
  // they use the whole area and clusters show as denser patches, not one clump in the middle.
  const spacing = ((area.r - 12) * 0.95 * 1.905) / Math.sqrt(n)
  // Grouped (the Tags grouping): the pages of a group stay close, so the groups read as groups
  // and their names have room between them; ungrouped pages spread over the whole area.
  const keep = grouped ? Math.min(spacing * 0.9, maxR * 2 + 12) : spacing * 0.9
  const cell = Math.max(maxR * 2 + 6, keep + 1)
  const v: Forces = { x: new Float64Array(n), y: new Float64Array(n) }
  const ideal = Math.max(12, spacing)
  const groupOf = grouped ? sorted.map((p) => anchor.get(p.group!.id)!) : null
  for (let it = 0; it < iterations; it++) {
    const alpha = 1 - it / iterations
    v.x.fill(0)
    v.y.fill(0)
    pullSprings(dots, springs, ideal, alpha, v)
    pullOutward(dots, outward, alpha, v)
    // Gentle pull to the centre, so loose pages do not all drift to the rim.
    pullTo(dots, () => area, 0.0015, alpha, v)
    if (groupOf) pullTo(dots, (i) => groupOf[i], 0.08, 1, v)
    pushApart(dots, cell, keep, v)
    moveDots(dots, area, v)
  }
  for (const d of dots) {
    clearSlot(d, area)
    contain(d, area)
    d.x = round(d.x)
    d.y = round(d.y)
    contain(d, area)
  }
  return dots
}

/** The step each dot takes in one round of the simulation, summed over the forces. */
type Forces = { x: Float64Array; y: Float64Array }

/** Links inside the area pull their dots to the ideal distance, harder for stronger links. */
function pullSprings(dots: DotLayout[], springs: Spring[], ideal: number, alpha: number, v: Forces): void {
  for (const [i, j, s] of springs) {
    const a = dots[i]
    const b = dots[j]
    const dx = b.x - a.x
    const dy = b.y - a.y
    const dist = Math.sqrt(dx * dx + dy * dy) || 1
    const f = ((dist - ideal) / dist) * 0.035 * s * alpha
    v.x[i] += dx * f
    v.y[i] += dy * f
    v.x[j] -= dx * f
    v.y[j] -= dy * f
  }
}

/** Links to other areas pull their dot towards that area's centre. */
function pullOutward(dots: DotLayout[], outward: Outward[], alpha: number, v: Forces): void {
  for (const [i, cx, cy, s] of outward) {
    const a = dots[i]
    const dx = cx - a.x
    const dy = cy - a.y
    const dist = Math.sqrt(dx * dx + dy * dy) || 1
    const f = (0.25 * s * alpha) / dist
    v.x[i] += dx * f
    v.y[i] += dy * f
  }
}

/** Every dot pulled towards its point (the area's centre, or its group's), in proportion to the
 *  distance. `k` and `alpha` stay two factors, applied in that order: the layout is pinned exactly,
 *  and (d * k) * alpha is not always d * (k * alpha) in floating point. */
function pullTo(dots: DotLayout[], point: (i: number) => Centre, k: number, alpha: number, v: Forces): void {
  for (let i = 0; i < dots.length; i++) {
    const c = point(i)
    v.x[i] += (c.x - dots[i].x) * k * alpha
    v.y[i] += (c.y - dots[i].y) * k * alpha
  }
}

const cellKey = (gx: number, gy: number) => gx * 73856093 + gy * 19349663

/** Collisions and short-range spacing: dots closer than `keep` (or touching) push apart. On a grid
 *  of `cell`-sized squares, so each dot only meets its neighbours (keeps this near O(n)). */
function pushApart(dots: DotLayout[], cell: number, keep: number, v: Forces): void {
  const grid = new Map<number, number[]>()
  for (let i = 0; i < dots.length; i++) {
    const k = cellKey(Math.floor(dots[i].x / cell), Math.floor(dots[i].y / cell))
    const list = grid.get(k)
    if (list) list.push(i)
    else grid.set(k, [i])
  }
  for (let i = 0; i < dots.length; i++) {
    const gx = Math.floor(dots[i].x / cell)
    const gy = Math.floor(dots[i].y / cell)
    for (let ox = -1; ox <= 1; ox++) {
      for (let oy = -1; oy <= 1; oy++) {
        for (const j of grid.get(cellKey(gx + ox, gy + oy)) ?? []) if (j > i) pushPair(dots, i, j, keep, v)
      }
    }
  }
}

function pushPair(dots: DotLayout[], i: number, j: number, keep: number, v: Forces): void {
  const a = dots[i]
  const b = dots[j]
  let dx = b.x - a.x
  let dy = b.y - a.y
  let dist = Math.sqrt(dx * dx + dy * dy)
  const min = Math.max(a.r + b.r + 5, keep)
  if (dist >= min) return
  if (dist < 1e-6) {
    // Same spot: split along a direction from the ids (deterministic).
    const ang = ((hash(a.id + b.id) % 360) * Math.PI) / 180
    dx = Math.cos(ang)
    dy = Math.sin(ang)
    dist = 1
  }
  const push = ((min - dist) / dist) * 0.5
  v.x[i] -= dx * push
  v.y[i] -= dy * push
  v.x[j] += dx * push
  v.y[j] += dy * push
}

/** Each dot takes its step (at most 6 units a round), then is kept off the name and inside the area. */
function moveDots(dots: DotLayout[], area: AreaLayout, v: Forces): void {
  for (let i = 0; i < dots.length; i++) {
    const d = dots[i]
    d.x += Math.max(-6, Math.min(6, v.x[i]))
    d.y += Math.max(-6, Math.min(6, v.y[i]))
    clearSlot(d, area)
    contain(d, area)
  }
}

/** Pages that are laid out in groups: two or more groups, and every page in one. */
function isGrouped(pages: GraphPage[]): boolean {
  const ids = new Set(pages.map((p) => p.group?.id ?? ''))
  return pages.length > 1 && ids.size > 1 && !ids.has('')
}

type Box = [number, number, number, number]
const boxesMeet = (a: Box, b: Box) => a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]

/** True when the dot (with `margin`) reaches into the box. */
export function dotMeetsBox(d: { x: number; y: number; r: number }, b: Box, margin = 0): boolean {
  const nx = Math.max(b[0], Math.min(d.x, b[2]))
  const ny = Math.max(b[1], Math.min(d.y, b[3]))
  return Math.hypot(d.x - nx, d.y - ny) < d.r + margin
}

/**
 * Where each group's name goes: above its dots, else below, left or right of them; the first
 * place that lies inside the area, on no dot, not on the area's name and on no other group's
 * name. Largest group first. A group with no such place gets no name (never a name on a dot).
 * `scale` = layout units per screen pixel at the fitted zoom, as for the area's own name.
 */
function groupLabels(area: AreaLayout, pages: GraphPage[], dots: DotLayout[], scale: number): GroupLabel[] {
  const by = new Map<string, { name: string; dots: DotLayout[] }>()
  pages.forEach((p, i) => {
    const g = by.get(p.group!.id) ?? { name: p.group!.name, dots: [] }
    g.dots.push(dots[i])
    by.set(p.group!.id, g)
  })
  const taken: Box[] = [[area.x - area.slot.hw, area.y - area.slot.hh, area.x + area.slot.hw, area.y + area.slot.hh]]
  const out: GroupLabel[] = []
  const order = [...by.entries()].sort((a, b) => b[1].dots.length - a[1].dots.length || cmp(a[0], b[0]))
  for (const [id, g] of order) {
    const size = groupLabelSize(g.name)
    const w = size.w * scale
    const h = size.h * scale
    const minX = Math.min(...g.dots.map((d) => d.x - d.r))
    const maxX = Math.max(...g.dots.map((d) => d.x + d.r))
    const minY = Math.min(...g.dots.map((d) => d.y - d.r))
    const maxY = Math.max(...g.dots.map((d) => d.y + d.r))
    const cx = (minX + maxX) / 2
    const cy = (minY + maxY) / 2
    const gap = 3 * scale
    const places: [number, number][] = [
      [cx, minY - h - gap],
      [cx, maxY + gap],
      [minX - w / 2 - gap, cy - h / 2],
      [maxX + w / 2 + gap, cy - h / 2],
    ]
    for (const [x, top] of places) {
      const box: Box = [x - w / 2, top, x + w / 2, top + h]
      const inside = [[box[0], box[1]], [box[2], box[1]], [box[0], box[3]], [box[2], box[3]]].every(([px, py]) => Math.hypot(px - area.x, py - area.y) <= area.r - 2)
      if (!inside || taken.some((t) => boxesMeet(box, t)) || dots.some((d) => dotMeetsBox(d, box, 2 * scale))) continue
      out.push({ id, name: g.name, count: g.dots.length, x: round(x), y: round(top), w: round(w), h: round(h) })
      taken.push(box)
      break
    }
  }
  return out
}

/** Space between a dot and the room kept for the topic name. */
const SLOT_MARGIN = 3

/** Moves a dot out of the room kept free for the area's name (AreaLayout.slot): up or down, the
 *  short way out of a wide, low box. A dot exactly on the middle line goes by its id, so the
 *  layout stays the same on every run. In an area too small for both, staying inside the area wins
 *  (contain runs after this). */
function clearSlot(d: DotLayout, area: AreaLayout): void {
  const ex = area.slot.hw + d.r + SLOT_MARGIN
  const ey = area.slot.hh + d.r + SLOT_MARGIN
  const dy = d.y - area.y
  if (Math.abs(d.x - area.x) >= ex || Math.abs(dy) >= ey) return
  const down = dy !== 0 ? dy > 0 : hash(d.id) % 2 === 0
  d.y = area.y + (down ? ey : -ey)
}

/** Keeps a dot (with its radius and a margin) inside its area. */
function contain(d: DotLayout, area: AreaLayout): void {
  const limit = area.r - d.r - 6
  const dx = d.x - area.x
  const dy = d.y - area.y
  const dist = Math.sqrt(dx * dx + dy * dy)
  if (dist > limit && dist > 0) {
    const s = (limit - 0.11) / dist
    d.x = area.x + dx * s
    d.y = area.y + dy * s
  }
}

// ---------- links between topics ----------

export interface BundleLayout {
  /** Area ids, a < b. */
  a: string
  b: string
  /** Links between pages of the two areas (either direction; a pair that links both ways once). */
  count: number
  /** Sum of those links' strengths (core 3, related 2, loose 1): drives the line width. */
  weight: number
  /** Angles (radians) where the line leaves area a and reaches area b, on their rims. */
  angleA: number
  angleB: number
  /** SVG path from rim to rim: a cubic curve that leaves each rim at a right angle. */
  d: string
}

/** Topic lines shown with nothing focused (operator, 2026-11-14, after the code-map reference: a
 *  calm picture; pointing at a page shows all of its topic's lines). */
export const RESTING_BUNDLES = 8
/** Smallest gap, in world px along a rim, between two topic lines leaving the same area. */
export const BUNDLE_SPREAD = 14

/**
 * One line per pair of topic areas, standing for all the links between their pages (operator,
 * 2026-11-14: page-to-page links across topics crossed the whole map). The page-level lines show
 * when a page is focused. Only links (not mentions), and only between pages that are shown.
 * Each line starts on the side of its area that faces the other area; lines that would leave an
 * area at almost the same spot are spread along the rim (spreadEnds), and every line leaves the rim
 * at a right angle. The stage draws them UNDER the (solid) areas, so a line never shows across a
 * third topic; it is seen only in the gaps between areas.
 */
export function bundleEdges(layout: GraphLayout, shown: Set<string> | null = null): BundleLayout[] {
  const areaById = new Map(layout.areas.map((a) => [a.id, a]))
  const counts = new Map<string, { count: number; weight: number }>()
  for (const { edge } of layout.edges) {
    if (edge.kind === 'mention') continue
    if (shown && (!shown.has(edge.from) || !shown.has(edge.to))) continue
    const da = layout.dotById.get(edge.from)
    const db = layout.dotById.get(edge.to)
    if (!da || !db || da.area === db.area) continue
    const [a, b] = da.area < db.area ? [da.area, db.area] : [db.area, da.area]
    const key = `${a}\u0000${b}`
    const c = counts.get(key) ?? { count: 0, weight: 0 }
    c.count++
    c.weight += edge.strength
    counts.set(key, c)
  }
  const out: BundleLayout[] = []
  for (const [key, { count, weight }] of [...counts].sort((x, y) => cmp(x[0], y[0]))) {
    const [a, b] = key.split('\u0000')
    const A = areaById.get(a)!
    const B = areaById.get(b)!
    // A first route from rim to rim (centre line) says where the line has to go: each end faces
    // its first bend, or the other area when the way is clear.
    const others = layout.areas.filter((x) => x.id !== a && x.id !== b)
    const facing = Math.atan2(B.y - A.y, B.x - A.x)
    const rough = routeAround(
      { x: A.x + Math.cos(facing) * A.r, y: A.y + Math.sin(facing) * A.r },
      { x: B.x - Math.cos(facing) * B.r, y: B.y - Math.sin(facing) * B.r },
      others,
    )
    const first = rough[1]
    const last = rough[rough.length - 2]
    out.push({ a, b, count, weight, angleA: Math.atan2(first.y - A.y, first.x - A.x), angleB: Math.atan2(last.y - B.y, last.x - B.x), d: '' })
  }
  // Spread the ends per area, then draw.
  const ends = new Map<string, { angle: number; set: (x: number) => void }[]>()
  for (const bl of out) {
    for (const [id, get, set] of [
      [bl.a, () => bl.angleA, (x: number) => (bl.angleA = x)],
      [bl.b, () => bl.angleB, (x: number) => (bl.angleB = x)],
    ] as const) {
      const list = ends.get(id) ?? []
      list.push({ angle: get(), set })
      ends.set(id, list)
    }
  }
  for (const [id, list] of ends) {
    const spread = spreadEnds(
      list.map((e) => e.angle),
      BUNDLE_SPREAD / areaById.get(id)!.r,
    )
    list.forEach((e, i) => e.set(spread[i]))
  }
  for (const bl of out) {
    const others = layout.areas.filter((x) => x.id !== bl.a && x.id !== bl.b)
    bl.d = rimPath(areaById.get(bl.a)!, bl.angleA, areaById.get(bl.b)!, bl.angleB, others)
  }
  return out
}

/** Room kept between a topic line and an area it goes around (world px). */
export const ROUTE_CLEARANCE = 6
/** Where a bend sits: in the middle of the gap the packing leaves between areas (AREA_GAP), so a
 *  bend is always at least AREA_GAP / 2 from every other area too and never needs a bend itself. */
const BEND_OUT = AREA_GAP / 2

/**
 * Bends from s to e around every circle in the way (operator, 2026-11-14: a topic line must never
 * pass under another topic). A segment that comes closer than r + ROUTE_CLEARANCE to a circle's
 * centre gets a bend just outside that circle, on the side the segment already passes; repeated
 * until every segment is clear. Returns the points, s first and e last. Pure.
 */
export function routeAround(s: Pt, e: Pt, circles: { x: number; y: number; r: number }[]): Pt[] {
  const pts: Pt[] = [s, e]
  for (let guard = 0; guard < 24; guard++) {
    const hit = firstBend(pts, circles)
    if (!hit) break
    pts.splice(hit.i + 1, 0, hit.at)
  }
  return pts
}

/** The first segment of the route that comes too close to a circle, and the bend it needs. */
function firstBend(pts: Pt[], circles: { x: number; y: number; r: number }[]): { i: number; at: Pt } | null {
  for (let i = 0; i < pts.length - 1; i++) {
    const at = segmentBend(pts[i], pts[i + 1], circles)
    if (at) return { i, at }
  }
  return null
}

/** The bend a-b needs round the circle it meets first (closest to a), or null when it is clear. */
function segmentBend(a: Pt, b: Pt, circles: { x: number; y: number; r: number }[]): Pt | null {
  let best = Infinity
  let at: Pt | null = null
  for (const c of circles) {
    const { t, d } = segmentDistance(a, b, c)
    if (d >= c.r + ROUTE_CLEARANCE - 0.5 || t >= best) continue
    best = t
    at = bendPoint(a, b, c, t)
  }
  return at
}

/** A bend from the circle's centre through the point at t of a-b, out past the rim. */
function bendPoint(a: Pt, b: Pt, c: { x: number; y: number; r: number }, t: number): Pt {
  const px = a.x + (b.x - a.x) * t
  const py = a.y + (b.y - a.y) * t
  let ux = px - c.x
  let uy = py - c.y
  let len = Math.hypot(ux, uy)
  if (len < 1e-6) {
    // Straight through the centre: go round on the left of the segment.
    ux = -(b.y - a.y)
    uy = b.x - a.x
    len = Math.hypot(ux, uy) || 1
  }
  const out = c.r + BEND_OUT
  return { x: c.x + (ux / len) * out, y: c.y + (uy / len) * out }
}

interface Pt {
  x: number
  y: number
}

/** Work counters for tests: a speed check that counts operations holds on any machine, where a
 *  wall-clock bound loose enough for a slow runner also passed the slow algorithm. */
export const layoutStats = { segmentChecks: 0 }

/** Distance from a circle's centre to the segment a-b, and where along it (t in 0..1) it is closest. */
function segmentDistance(a: Pt, b: Pt, c: Pt): { t: number; d: number } {
  layoutStats.segmentChecks++
  const dx = b.x - a.x
  const dy = b.y - a.y
  const l2 = dx * dx + dy * dy || 1
  const t = Math.max(0, Math.min(1, ((c.x - a.x) * dx + (c.y - a.y) * dy) / l2))
  return { t, d: Math.hypot(a.x + dx * t - c.x, a.y + dy * t - c.y) }
}

/**
 * Angles moved apart so that no two are closer than `min` (radians), each group of close angles
 * centred on where it was. Returns the new angles in the input order. Pure.
 */
export function spreadEnds(angles: number[], min: number): number[] {
  const n = angles.length
  if (n < 2) return [...angles]
  const step = Math.min(min, (Math.PI * 2) / n)
  const norm = (x: number) => ((x % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2)
  const out = angles.map(norm)
  // The circle is cut at its widest gap, so a group around angle 0 stays one group.
  const sorted = [...out].sort((p, q) => p - q)
  let cut = sorted[0]
  let widest = sorted[0] + Math.PI * 2 - sorted[n - 1]
  for (let k = 1; k < n; k++) if (sorted[k] - sorted[k - 1] > widest) [widest, cut] = [sorted[k] - sorted[k - 1], sorted[k]]
  const order = out.map((x, i) => ({ x: cut + norm(x - cut), i })).sort((p, q) => p.x - q.x || p.i - q.i)
  // Groups placed `step` apart, each starting where the mean of its members wants it; a group that
  // reaches the one before it merges with it (one pass, exact: no group ends closer than step).
  const groups: { items: { x: number; i: number }[]; start: number }[] = []
  for (const o of order) {
    groups.push({ items: [o], start: o.x })
    for (;;) {
      const cur = groups[groups.length - 1]
      const prev = groups[groups.length - 2]
      if (!prev || prev.start + prev.items.length * step <= cur.start + 1e-9) break
      const items = [...prev.items, ...cur.items]
      const start = items.reduce((s, it, k) => s + it.x - k * step, 0) / items.length
      groups.splice(groups.length - 2, 2, { items, start })
    }
  }
  for (const g of groups) g.items.forEach((it, k) => (out[it.i] = g.start + k * step))
  // Lone angles keep their exact input value.
  return out.map((x, i) => (Math.abs(x - norm(angles[i])) < 1e-12 ? angles[i] : x))
}

/** Smooth curve from the rim of A at angle aa to the rim of B at angle ab, around the circles in
 *  the way (routeAround), leaving and reaching each rim at a right angle (the first and last
 *  control points lie along the rim's normal); cubic pieces through the bends. */
function rimPath(A: { x: number; y: number; r: number }, aa: number, B: { x: number; y: number; r: number }, ab: number, others: { x: number; y: number; r: number }[] = []): string {
  const s = { x: A.x + Math.cos(aa) * A.r, y: A.y + Math.sin(aa) * A.r }
  const e = { x: B.x + Math.cos(ab) * B.r, y: B.y + Math.sin(ab) * B.r }
  const pts = routeAround(s, e, others)
  let pieces = curvePieces(pts, aa, ab)
  // The smooth curve can still cut a corner the bends cleared: add a bend where it does.
  for (let guard = 0; guard < 8; guard++) {
    const hit = curveHit(pieces, others)
    if (!hit) break
    const c = hit.circle
    const l = Math.hypot(hit.at.x - c.x, hit.at.y - c.y) || 1
    const out = c.r + BEND_OUT
    pts.splice(hit.piece + 1, 0, { x: c.x + ((hit.at.x - c.x) / l) * out, y: c.y + ((hit.at.y - c.y) / l) * out })
    pieces = curvePieces(pts, aa, ab)
  }
  let d = `M${round(s.x)} ${round(s.y)}`
  for (const [, c1, c2, q] of pieces) d += `C${round(c1.x)} ${round(c1.y)} ${round(c2.x)} ${round(c2.y)} ${round(q.x)} ${round(q.y)}`
  return d
}

/** Cubic pieces [p, c1, c2, q] through the points: at the ends along the rim normals (angles aa
 *  out of A, ab out of B), at bends along the neighbours' direction. */
function curvePieces(pts: Pt[], aa: number, ab: number): Pt[][] {
  const tan = pts.map((_, i) => {
    if (i === 0) return { x: Math.cos(aa), y: Math.sin(aa) }
    if (i === pts.length - 1) return { x: -Math.cos(ab), y: -Math.sin(ab) }
    const dx = pts[i + 1].x - pts[i - 1].x
    const dy = pts[i + 1].y - pts[i - 1].y
    const l = Math.hypot(dx, dy) || 1
    return { x: dx / l, y: dy / l }
  })
  const out: Pt[][] = []
  for (let i = 0; i < pts.length - 1; i++) {
    const p = pts[i]
    const q = pts[i + 1]
    const len = Math.hypot(q.x - p.x, q.y - p.y)
    // Ends keep the earlier look (0.35 of the way); bends a third, the usual smooth handle.
    const k1 = len * (i === 0 ? 0.35 : 1 / 3)
    const k2 = len * (i === pts.length - 2 ? 0.35 : 1 / 3)
    out.push([p, { x: p.x + tan[i].x * k1, y: p.y + tan[i].y * k1 }, { x: q.x - tan[i + 1].x * k2, y: q.y - tan[i + 1].y * k2 }, q])
  }
  return out
}

/** The point at t (0..1) of a cubic piece [p0, p1, p2, p3]. */
function cubicAt([p0, p1, p2, p3]: Pt[], t: number): Pt {
  const u = 1 - t
  return {
    x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
    y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y,
  }
}

/** The first point of the curve (sampled) that comes within a few px of a circle, or null. */
function curveHit(pieces: Pt[][], circles: { x: number; y: number; r: number }[]): { piece: number; at: Pt; circle: { x: number; y: number; r: number } } | null {
  for (let i = 0; i < pieces.length; i++) {
    for (let k = 1; k < 32; k++) {
      const at = cubicAt(pieces[i], k / 32)
      const circle = circles.find((c) => Math.hypot(at.x - c.x, at.y - c.y) < c.r + 2)
      if (circle) return { piece: i, at, circle }
    }
  }
  return null
}

/** The topic lines shown at rest: the RESTING_BUNDLES heaviest (ties by area ids). */
export function restingBundles(bundles: BundleLayout[], max = RESTING_BUNDLES): BundleLayout[] {
  return [...bundles].sort((x, y) => y.weight - x.weight || cmp(x.a, y.a) || cmp(x.b, y.b)).slice(0, max)
}

/** True when an edge runs between two different topic areas (drawn as part of a bundle). */
export function crossesAreas(layout: GraphLayout, from: string, to: string): boolean {
  const a = layout.dotById.get(from)
  const b = layout.dotById.get(to)
  return !!a && !!b && a.area !== b.area
}

// ---------- 3. all together ----------

/** How far the name room may grow (a map fitted at a quarter of its size), and the margin for the
 *  areas growing with it. */
const MAX_NAME_SCALE = 4
const NAME_SCALE_MARGIN = 0.9

/** The stage width the name room is worked out for (a 1440px window with the side bar). */
export const NOMINAL_STAGE_W = 1100

/** The zoom at which a layout of these bounds is fitted on the nominal stage (view.ts fitViewport). */
export function nominalFit(bounds: Bounds, aspect: number): number {
  return Math.min(NOMINAL_STAGE_W / bounds.w, (NOMINAL_STAGE_W / aspect - 52) / bounds.h, 2.5)
}

/**
 * The layout. A topic name is drawn at a fixed screen size, so on a map that is fitted zoomed out
 * it covers more of the layout than its room of one layout unit per pixel: 4 dots lay under names
 * at 300 pages and over 200 at 600 (code review 2026-11-15). So the map is laid out once, the
 * fitted zoom is read from its size, and while the name room is smaller on screen than the name
 * it is laid out again with the room that much larger (the areas grow a little with it, so the
 * zoom drops again: a margin, and at most three more passes).
 */
export function layoutGraph(model: GraphModel, opts: LayoutOptions = {}, index: GraphIndex = buildIndex(model)): GraphLayout {
  const aspect = opts.aspect && opts.aspect > 0 ? opts.aspect : 1.45
  let scale = 1
  let layout = layoutOnce(model, aspect, index, scale)
  for (let pass = 0; pass < 3 && layout.areas.length; pass++) {
    const k = nominalFit(layout.bounds, aspect)
    if (k >= 0.97 || scale * k >= 1) break
    scale = Math.min(MAX_NAME_SCALE, 1 / (k * NAME_SCALE_MARGIN))
    layout = layoutOnce(model, aspect, index, scale)
  }
  // Group names (the Tags grouping) are placed last, at the size they really have on the fitted
  // map: on a small map, fitted zoomed in, a name covers less of the layout than one unit per
  // pixel, and a name sized for more would stand far from its pages.
  if (layout.areas.length) {
    const unit = 1 / (nominalFit(layout.bounds, aspect) * NAME_SCALE_MARGIN)
    for (const area of layout.areas) {
      const pages = area.pageIds.map((id) => index.pageById.get(id)!)
      if (!isGrouped(pages)) continue
      const groups = groupLabels(area, pages, pages.map((p) => layout.dotById.get(p.id)!), unit)
      if (groups.length) area.groups = groups
    }
  }
  return layout
}

function layoutOnce(model: GraphModel, aspect: number, index: GraphIndex, slotScale: number): GraphLayout {
  const ordered = topicOrder(model.topics).filter((t) => (index.pagesByArea.get(t.id)?.length ?? 0) > 0)
  const areaIds: (string)[] = ordered.map((t) => t.id)
  if (index.pagesByArea.has(UNFILED_ID)) areaIds.push(UNFILED_ID)

  const nameOf = (id: string) => index.topicById.get(id)?.name ?? 'Unfiled'
  const radii = areaIds.map((id) =>
    areaRadius((index.pagesByArea.get(id) ?? []).map((pid) => dotRadius(index.pageById.get(pid)!)), id === UNFILED_ID ? MIN_UNFILED_R : MIN_AREA_R, nameOf(id), slotScale),
  )
  const slot = new Map(areaIds.map((id, i) => [id, i]))
  const targets = areaIds.map((id) => {
    // Nearest ancestor that has its own area: subtopics sit next to their parent.
    let parent = index.topicById.get(id)?.parent ?? null
    while (parent !== null) {
      const s = slot.get(parent)
      if (s !== undefined) return s
      parent = index.topicById.get(parent)?.parent ?? null
    }
    return null
  })
  const outer = areaIds.map((id) => id === UNFILED_ID)
  // Summed link strength between areas (pages in their primary topic): linked topics are placed
  // next to each other, so their line needs no other topic out of the way.
  const links = areaIds.map(() => areaIds.map(() => 0))
  for (const e of onePerPair(model.edges)) {
    if (e.kind === 'mention') continue
    const pa = index.pageById.get(e.from)
    const pb = index.pageById.get(e.to)
    if (!pa || !pb) continue
    const i = slot.get(primaryTopic(pa))
    const j = slot.get(primaryTopic(pb))
    if (i === undefined || j === undefined || i === j) continue
    links[i][j] += e.strength
    links[j][i] += e.strength
  }
  const order = packOrder(targets, links, outer)
  const at = new Map(order.map((orig, k) => [orig, k]))
  const packed = packAreas(
    order.map((o) => radii[o]),
    order.map((o) => (targets[o] === null ? null : at.get(targets[o]!)!)),
    aspect,
    AREA_GAP,
    order.map((o) => outer[o]),
    order.map((o) => order.map((p) => links[o][p])),
  )
  const circles = areaIds.map((_, i) => packed[at.get(i)!])

  const areas: AreaLayout[] = areaIds.map((id, i) => {
    const topic = index.topicById.get(id) ?? null
    const count = index.pagesByArea.get(id)?.length ?? 0
    const total = topic ? Math.max(topic.pageCount, count) : count
    const subjects = topic?.subjects ?? 'pages without a topic yet'
    return {
      id,
      topic,
      name: topic ? topic.name : 'Unfiled',
      sub: `${total} ${total === 1 ? 'page' : 'pages'}${subjects ? ` · ${subjects}` : ''}`,
      x: round(circles[i].x),
      y: round(circles[i].y),
      r: round(circles[i].r),
      pageIds: index.pagesByArea.get(id) ?? [],
      // The name's room includes its page count: the stage shows the count of the pages drawn,
      // never more than this (stageModel.ts stageLabels), so it never needs more room.
      slot: labelSlot(nameOf(id), circles[i].r, slotScale, count),
    }
  })
  const centre = new Map(areas.map((a) => [a.id, { x: a.x, y: a.y }]))

  const dots: DotLayout[] = []
  for (const area of areas) {
    const pages = area.pageIds.map((id) => index.pageById.get(id)!)
    dots.push(...placeDots(area, pages, index, centre))
  }
  const dotById = new Map(dots.map((d) => [d.id, d]))

  const edges: EdgeLayout[] = []
  for (const e of onePerPair(model.edges)) {
    const a = dotById.get(e.from)
    const b = dotById.get(e.to)
    if (a && b) edges.push({ edge: e, d: edgePath(a.x, a.y, b.x, b.y) })
  }

  let minX = Infinity
  let minY = Infinity
  let maxX = -Infinity
  let maxY = -Infinity
  for (const a of areas) {
    minX = Math.min(minX, a.x - a.r)
    maxX = Math.max(maxX, a.x + a.r)
    minY = Math.min(minY, a.y - a.r - LABEL_SPACE)
    // Room for a topic name placed under its area (view.ts placeAreaLabels) at the bottom edge.
    maxY = Math.max(maxY, a.y + a.r + LABEL_SPACE)
  }
  const pad = 24
  const bounds: Bounds = areas.length
    ? { x: minX - pad, y: minY - pad, w: maxX - minX + pad * 2, h: maxY - minY + pad * 2 }
    : { x: 0, y: 0, w: 1100, h: 760 }
  return { areas, dots, dotById, edges, bounds }
}
