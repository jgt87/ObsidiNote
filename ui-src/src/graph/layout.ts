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
export const LABEL_SPACE = 34
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

export function dotRadius(page: GraphPage): number {
  if (page.unlinked || page.links === 0) return 3
  if (page.isHub) return Math.min(11, 7 + Math.sqrt(page.links) * 0.6)
  return Math.min(6, 2.6 + Math.sqrt(page.links) * 0.9)
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

function areaRadius(dotRadii: number[], min = MIN_AREA_R): number {
  let sum = 0
  for (const r of dotRadii) sum += (r + 4.5) * (r + 4.5)
  // design: dots fill about 40% of an area, so a topic reads as a roomy grey field with its
  // pages spread inside (the README map), not a tight clump.
  return Math.max(min, Math.sqrt(sum / 0.4) + 14)
}

interface Circle {
  x: number
  y: number
  r: number
}

/** Packs circles in order; each goes to the free tangent spot nearest its target. A circle marked
 *  `outer` (Unfiled) is not pulled to the centre, so it lands at the rim of the picture. */
export function packAreas(radii: number[], targets: (number | null)[], aspect: number, gap = AREA_GAP, outer: boolean[] = []): Circle[] {
  const placed: Circle[] = []
  const box = { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity }
  const steps = 36
  for (let i = 0; i < radii.length; i++) {
    const r = radii[i]
    if (i === 0) {
      placed.push({ x: 0, y: 0, r })
      grow(box, placed[0])
      continue
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
        // Unfiled (outer) gets no pull to the centre, so it ends up at the rim.
        const pull = t !== null ? 4 : outer[i] ? 0 : 0.35
        const score = Math.max(fw, fh) + Math.sqrt(sx * sx + sy * sy) * pull
        if (score < bestScore - 1e-9) {
          bestScore = score
          best = { x, y, r }
        }
      }
    }
    const c = best ?? { x: 0, y: 0, r }
    placed.push(c)
    grow(box, c)
  }
  return placed
}

function grow(box: { minX: number; maxX: number; minY: number; maxY: number }, c: Circle): void {
  box.minX = Math.min(box.minX, c.x - c.r)
  box.maxX = Math.max(box.maxX, c.x + c.r)
  box.minY = Math.min(box.minY, c.y - c.r - LABEL_SPACE)
  box.maxY = Math.max(box.maxY, c.y + c.r + LABEL_SPACE)
}

// ---------- 2. pages inside an area ----------

function placeDots(area: AreaLayout, pages: GraphPage[], index: GraphIndex, areaCentre: Map<string, { x: number; y: number }>): DotLayout[] {
  // Most linked first: they settle in the middle.
  const sorted = [...pages].sort((a, b) => Number(b.isHub) - Number(a.isHub) || b.links - a.links || cmp(a.id, b.id))
  const n = sorted.length
  const dots: DotLayout[] = sorted.map((p, i) => {
    const r = dotRadius(p)
    // Sunflower spiral, rotated per area so areas do not look identical.
    const rot = (hash(area.id) % 360) * (Math.PI / 180)
    const a = i * 2.39996323 + rot
    const d = n <= 1 ? 0 : (area.r - 10) * 0.82 * Math.sqrt((i + 0.5) / n)
    return { id: p.id, area: area.id, x: area.x + Math.cos(a) * d, y: area.y + Math.sin(a) * d, r, hub: p.isHub, unlinked: p.unlinked || p.links === 0 }
  })
  if (n <= 1) return dots
  const pos = new Map(dots.map((d, i) => [d.id, i]))

  // Springs: links inside the area pull together; links to other areas pull towards that area.
  const springs: [number, number, number][] = []
  const outward: [number, number, number, number][] = []
  for (const d of dots) {
    const i = pos.get(d.id)!
    for (const e of index.out.get(d.id) ?? []) {
      const j = pos.get(e.to)
      if (j !== undefined) springs.push([i, j, e.strength])
      else {
        const other = index.pageById.get(e.to)
        const c = other ? areaCentre.get(primaryTopic(other)) : undefined
        if (c) outward.push([i, c.x, c.y, e.strength])
      }
    }
    for (const e of index.in.get(d.id) ?? []) {
      if (pos.has(e.from)) continue
      const other = index.pageById.get(e.from)
      const c = other ? areaCentre.get(primaryTopic(other)) : undefined
      if (c) outward.push([i, c.x, c.y, e.strength])
    }
  }

  const iterations = n > 400 ? 70 : n > 150 ? 110 : 160
  const maxR = dots.reduce((m, d) => Math.max(m, d.r), 0)
  // Hexagonal spacing at which n dots would fill 95% of the area; dots keep 90% of it apart, so
  // they use the whole area and clusters show as denser patches, not one clump in the middle.
  const spacing = ((area.r - 12) * 0.95 * 1.905) / Math.sqrt(n)
  const keep = spacing * 0.9
  const cell = Math.max(maxR * 2 + 6, keep + 1)
  const vx = new Float64Array(n)
  const vy = new Float64Array(n)
  const ideal = Math.max(12, spacing)
  for (let it = 0; it < iterations; it++) {
    const alpha = 1 - it / iterations
    vx.fill(0)
    vy.fill(0)
    for (const [i, j, s] of springs) {
      const a = dots[i]
      const b = dots[j]
      const dx = b.x - a.x
      const dy = b.y - a.y
      const dist = Math.sqrt(dx * dx + dy * dy) || 1
      const f = ((dist - ideal) / dist) * 0.035 * s * alpha
      vx[i] += dx * f
      vy[i] += dy * f
      vx[j] -= dx * f
      vy[j] -= dy * f
    }
    for (const [i, cx, cy, s] of outward) {
      const a = dots[i]
      const dx = cx - a.x
      const dy = cy - a.y
      const dist = Math.sqrt(dx * dx + dy * dy) || 1
      const f = (0.25 * s * alpha) / dist
      vx[i] += dx * f
      vy[i] += dy * f
    }
    // Gentle pull to the centre, so loose pages do not all drift to the rim.
    for (let i = 0; i < n; i++) {
      vx[i] += (area.x - dots[i].x) * 0.0015 * alpha
      vy[i] += (area.y - dots[i].y) * 0.0015 * alpha
    }
    // Collisions and short-range spacing on a grid (keeps this near O(n)).
    const grid = new Map<number, number[]>()
    const key = (gx: number, gy: number) => gx * 73856093 + gy * 19349663
    for (let i = 0; i < n; i++) {
      const k = key(Math.floor(dots[i].x / cell), Math.floor(dots[i].y / cell))
      const list = grid.get(k)
      if (list) list.push(i)
      else grid.set(k, [i])
    }
    for (let i = 0; i < n; i++) {
      const a = dots[i]
      const gx = Math.floor(a.x / cell)
      const gy = Math.floor(a.y / cell)
      for (let ox = -1; ox <= 1; ox++) {
        for (let oy = -1; oy <= 1; oy++) {
          for (const j of grid.get(key(gx + ox, gy + oy)) ?? []) {
            if (j <= i) continue
            const b = dots[j]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let dist = Math.sqrt(dx * dx + dy * dy)
            const min = Math.max(a.r + b.r + 5, keep)
            if (dist >= min) continue
            if (dist < 1e-6) {
              // Same spot: split along a direction from the ids (deterministic).
              const ang = ((hash(a.id + b.id) % 360) * Math.PI) / 180
              dx = Math.cos(ang)
              dy = Math.sin(ang)
              dist = 1
            }
            const push = ((min - dist) / dist) * 0.5
            vx[i] -= dx * push
            vy[i] -= dy * push
            vx[j] += dx * push
            vy[j] += dy * push
          }
        }
      }
    }
    for (let i = 0; i < n; i++) {
      const d = dots[i]
      const mx = Math.max(-6, Math.min(6, vx[i]))
      const my = Math.max(-6, Math.min(6, vy[i]))
      d.x += mx
      d.y += my
      contain(d, area)
    }
  }
  for (const d of dots) {
    contain(d, area)
    d.x = round(d.x)
    d.y = round(d.y)
    contain(d, area)
  }
  return dots
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
  /** Links between pages of the two areas (either direction). */
  count: number
  /** SVG path from rim to rim. */
  d: string
}

/**
 * One line per pair of topic areas, standing for all the links between their pages (operator,
 * 2026-11-14: page-to-page links across topics crossed the whole map). The page-level lines show
 * when a page is focused. Only links (not mentions), and only between pages that are shown.
 */
export function bundleEdges(layout: GraphLayout, shown: Set<string> | null = null): BundleLayout[] {
  const areaById = new Map(layout.areas.map((a) => [a.id, a]))
  const counts = new Map<string, number>()
  for (const { edge } of layout.edges) {
    if (edge.kind === 'mention') continue
    if (shown && (!shown.has(edge.from) || !shown.has(edge.to))) continue
    const da = layout.dotById.get(edge.from)
    const db = layout.dotById.get(edge.to)
    if (!da || !db || da.area === db.area) continue
    const [a, b] = da.area < db.area ? [da.area, db.area] : [db.area, da.area]
    const key = `${a}\u0000${b}`
    counts.set(key, (counts.get(key) ?? 0) + 1)
  }
  const out: BundleLayout[] = []
  for (const [key, count] of [...counts].sort((x, y) => cmp(x[0], y[0]))) {
    const [a, b] = key.split('\u0000')
    const A = areaById.get(a)!
    const B = areaById.get(b)!
    const dx = B.x - A.x
    const dy = B.y - A.y
    const dist = Math.sqrt(dx * dx + dy * dy) || 1
    const ux = dx / dist
    const uy = dy / dist
    out.push({ a, b, count, d: edgePath(A.x + ux * A.r, A.y + uy * A.r, B.x - ux * B.r, B.y - uy * B.r) })
  }
  return out
}

/** True when an edge runs between two different topic areas (drawn as part of a bundle). */
export function crossesAreas(layout: GraphLayout, from: string, to: string): boolean {
  const a = layout.dotById.get(from)
  const b = layout.dotById.get(to)
  return !!a && !!b && a.area !== b.area
}

// ---------- 3. all together ----------

export function layoutGraph(model: GraphModel, opts: LayoutOptions = {}, index: GraphIndex = buildIndex(model)): GraphLayout {
  const aspect = opts.aspect && opts.aspect > 0 ? opts.aspect : 1.45
  const ordered = topicOrder(model.topics).filter((t) => (index.pagesByArea.get(t.id)?.length ?? 0) > 0)
  const areaIds: (string)[] = ordered.map((t) => t.id)
  if (index.pagesByArea.has(UNFILED_ID)) areaIds.push(UNFILED_ID)

  const radii = areaIds.map((id) =>
    areaRadius((index.pagesByArea.get(id) ?? []).map((pid) => dotRadius(index.pageById.get(pid)!)), id === UNFILED_ID ? MIN_UNFILED_R : MIN_AREA_R),
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
  const circles = packAreas(radii, targets, aspect, AREA_GAP, areaIds.map((id) => id === UNFILED_ID))

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
  for (const e of model.edges) {
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
