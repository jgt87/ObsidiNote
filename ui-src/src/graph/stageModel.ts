// What the map stage draws on top of its base layer and how it answers keys: the focus layer's
// lines and dots, the topic, group and page names, and the key map. Pure (tests: stageModel.test.ts);
// GraphStage.tsx reads state, calls these and renders.
import type { GraphIndex } from './graphIndex'
import { groupLabelSize } from './labelSize'
import { edgePath, onePerPair, type AreaLayout, type DotLayout, type EdgeLayout, type GraphLayout } from './layout'
import type { GraphEdge } from './model'
import { labelMode, labelRect, nextInDirection, placeAreaLabels, placeLabels, toScreen, type Direction, type LabelBox, type Rect, type Viewport } from './view'

/** The class of a page-to-page line: dashed for a mention, else by link strength. */
export function edgeClass(e: GraphEdge): string {
  return e.kind === 'mention' ? 'kg-edge kg-edge--mention' : `kg-edge kg-s${e.strength}`
}

/** A page-to-page line drawn in the base layer: its kind is switched on, both pages are shown and
 *  both lie in one area (links across topics are drawn only for the focused page). */
export function drawnAtRest(e: EdgeLayout, layout: GraphLayout, links: boolean, mentions: boolean, isShown: (id: string) => boolean): boolean {
  if (e.edge.kind === 'mention' ? !mentions : !links) return false
  if (!isShown(e.edge.from) || !isShown(e.edge.to)) return false
  const a = layout.dotById.get(e.edge.from)
  const b = layout.dotById.get(e.edge.to)
  return !(a && b && a.area !== b.area)
}

/** A line of the focused page: `incoming` = a link of another page to it that it does not return
 *  (drawn dashed); a link both ways counts as its own. */
export interface FocusEdge {
  e: GraphEdge
  d: string
  incoming: boolean
}

/** The focused page's own links (and mentions), one line per pair, between shown pages only. */
export function focusEdgeList(index: GraphIndex, layout: GraphLayout, activeId: string | null, links: boolean, mentions: boolean, isShown: (id: string) => boolean): FocusEdge[] {
  if (!activeId) return []
  const list: GraphEdge[] = []
  if (links) list.push(...(index.out.get(activeId) ?? []), ...(index.in.get(activeId) ?? []))
  if (mentions) list.push(...(index.mentions.get(activeId) ?? []))
  const linksTo = new Set((index.out.get(activeId) ?? []).map((e) => e.to))
  return onePerPair(list).flatMap((e) => {
    if (!isShown(e.from) || !isShown(e.to)) return []
    const a = layout.dotById.get(e.from)
    const b = layout.dotById.get(e.to)
    const incoming = e.kind !== 'mention' && e.to === activeId && !linksTo.has(e.from)
    return a && b ? [{ e, d: edgePath(a.x, a.y, b.x, b.y), incoming }] : []
  })
}

/** The class of a line of the focused page: a link to it (one it does not return) is dashed. */
export function focusEdgeClass(f: FocusEdge): string {
  return f.incoming ? `${edgeClass(f.e)} kg-edge--in` : edgeClass(f.e)
}

/** Dots drawn undimmed over the base layer: the focused page's neighbours, else the first 400
 *  search results; never the focused dot itself (it has its own circle). */
export function sharpDots(layout: GraphLayout, activeId: string | null, near: string[], matches: string[] | null, isShown: (id: string) => boolean): DotLayout[] {
  const ids = activeId ? [...near] : matches ? matches.filter(isShown).slice(0, 400) : []
  return ids.map((id) => layout.dotById.get(id)).filter((d): d is DotLayout => !!d && d.id !== activeId)
}

export interface StageLabelInput {
  layout: GraphLayout
  index: GraphIndex
  v: Viewport
  /** The zoom that fits the whole map. */
  fitK: number
  size: { w: number; h: number }
  shown: Set<string> | null
  activeDot: DotLayout | null
  sharp: DotLayout[]
  matches: string[] | null
  hubsOnly: boolean
  hoverArea: string | null
}

/** A group's name as placed on screen (layout.ts GroupLabel is its room in layout units). */
export interface PlacedGroupName {
  key: string
  text: string
  x: number
  top: number
  rect: Rect
  /** Hidden under a linked page's name while a page is focused. */
  hidden?: boolean
}

function areaShown(a: AreaLayout, shown: Set<string> | null): boolean {
  return !shown || a.pageIds.some((id) => shown.has(id))
}

/** Group names inside an area (the Tags grouping: a topic's name over its pages). The layout kept
 *  their room free of dots at the fitted zoom; zoomed out further they would cover dots, so they go. */
function groupLabelList(layout: GraphLayout, v: Viewport, fitK: number, shown: Set<string> | null): PlacedGroupName[] {
  if (v.k < fitK * 0.9) return []
  return layout.areas
    .filter((a) => a.groups && areaShown(a, shown))
    .flatMap((a) =>
      a.groups!.map((g) => {
        const [x, y] = toScreen(v, g.x, g.y)
        const s = groupLabelSize(g.name)
        // Its room is g.h layout units high; the text sits in the middle of it.
        const top = y + (g.h * v.k - s.h) / 2
        return { key: `${a.id}|${g.id}`, text: g.name, x, top, rect: [x - s.w / 2, top, x + s.w / 2, top + s.h] as Rect }
      }),
    )
}

/** Page names to try, in priority order (the focused page first). */
function pageLabelCandidates(i: StageLabelInput): LabelBox[] {
  const { layout, index, v, size, shown, activeDot, sharp, matches, hubsOnly } = i
  const isShown = (id: string) => !shown || shown.has(id)
  const candidates: LabelBox[] = []
  const add = (d: DotLayout, cls: string) => {
    const [x, y] = toScreen(v, d.x, d.y)
    if (x < -200 || y < -40 || x > size.w + 200 || y > size.h + 40) return
    const px = cls.includes('--on') ? 13 : cls.includes('--hub') ? 12 : 11
    candidates.push({ id: d.id, text: index.pageById.get(d.id)!.title, x, y: y - d.r * v.k - 4, px, cls })
  }
  const near = (d: DotLayout) => add(d, d.hub ? 'kg-plabel kg-plabel--hub' : 'kg-plabel')
  if (activeDot) {
    add(activeDot, 'kg-plabel kg-plabel--on')
    // "Labels: hubs only": the page pointed at, and nothing around it.
    if (!hubsOnly) sharp.forEach(near)
  } else if (matches) {
    sharp.slice(0, 40).forEach(near)
  } else {
    // A small map, or one zoomed in, names every page (most linked first); a larger one the most
    // linked only; with "Labels: hubs only" no page at rest, only the topic names (labelMode).
    const mode = labelMode(shown ? shown.size : layout.dots.length, v.k, i.fitK, hubsOnly)
    if (mode !== 'none') for (const d of layout.dots) if (d.hub && isShown(d.id)) add(d, 'kg-plabel kg-plabel--hub')
    if (mode === 'all') for (const d of layout.dots) if (!d.hub && isShown(d.id)) add(d, 'kg-plabel')
  }
  return candidates
}

const meets = (r: Rect, k: Rect) => r[0] < k[2] && r[2] > k[0] && r[1] < k[3] && r[3] > k[1]

/**
 * Every name on the map. Topic names first, each where it touches no other topic
 * (placeAreaLabels), with the count of its pages drawn beside it; at rest page names then keep
 * clear of them, and placeLabels drops a page name that would overlap one already placed, so names
 * never pile up. A topic's name gives way while the pointer is over its area, or one of its pages
 * is focused, so it never covers the pages (operator, 2026-11-14): those areas are in `hiddenAreas`.
 * While a page is focused the rest of the map is faded, so the names of the page and its linked
 * pages come first (operator, 2026-11-15): a faded topic or group name they would meet is hidden
 * instead of dropping theirs.
 */
export function stageLabels(i: StageLabelInput) {
  const { layout, v, shown } = i
  const areaLabels = placeAreaLabels(
    layout.areas
      .filter((a) => areaShown(a, shown))
      .map((a) => {
        const [x, y] = toScreen(v, a.x, a.y)
        const count = shown ? a.pageIds.filter((id) => shown.has(id)).length : a.pageIds.length
        return { id: a.id, x, y, r: a.r * v.k, name: a.name, count }
      }),
  )
  const groupLabels = groupLabelList(layout, v, i.fitK, shown)
  const hiddenAreas = new Set([i.hoverArea, i.activeDot?.area].filter((x): x is string => !!x))
  if (!i.activeDot) {
    const labels = placeLabels(pageLabelCandidates(i), [...areaLabels.filter((l) => !hiddenAreas.has(l.id)).map((l) => l.rect), ...groupLabels.map((g) => g.rect)])
    return { areaLabels, groupLabels, hiddenAreas, labels }
  }
  const labels = placeLabels(pageLabelCandidates(i))
  const rects = labels.map(labelRect)
  for (const l of areaLabels) if (rects.some((r) => meets(r, l.rect))) hiddenAreas.add(l.id)
  for (const g of groupLabels) if (rects.some((r) => meets(r, g.rect))) g.hidden = true
  return { areaLabels, groupLabels, hiddenAreas, labels }
}

/** The topic area at a point of the stage (screen pixels), or null. */
export function areaAt(areas: AreaLayout[], v: Viewport, sx: number, sy: number): string | null {
  const wx = sx / v.k + v.x
  const wy = sy / v.k + v.y
  return areas.find((a) => Math.hypot(wx - a.x, wy - a.y) <= a.r)?.id ?? null
}

const KEY_DIR: Record<string, Direction> = { ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down' }

export type StageKeyAction = { kind: 'activate'; id: string } | { kind: 'open'; id: string } | { kind: 'focusPage'; id: string } | { kind: 'leave' } | { kind: 'zoom'; factor: number } | { kind: 'fit' }

export interface StageKeyState {
  activeDot: DotLayout | null
  /** A page is active (pointed at or focused), shown or not. */
  hasActive: boolean
  /** The visible dots in their keyboard order. */
  order: DotLayout[]
  dots: DotLayout[]
  visible: (id: string) => boolean
  canFocusPage: boolean
}

type KeyInput = { key: string; shiftKey: boolean; altKey: boolean; ctrlKey: boolean; metaKey: boolean }

/**
 * What a key on the map does: `prevent` = the key is the map's (the browser does nothing with it),
 * `action` = what follows (null: nothing, e.g. an arrow with no page to go to). null for a key the
 * map leaves alone. Arrows move to the nearest visible page that way (the first page when none is
 * active); Tab walks the order and leaves the map at either end; Enter opens; F focuses on the page;
 * Esc leaves the map for its toolbar; + / - zoom; 0 fits.
 */
export function stageKey(e: KeyInput, s: StageKeyState): { prevent: boolean; action: StageKeyAction | null } | null {
  const { activeDot } = s
  const dir = KEY_DIR[e.key]
  if (dir) {
    if (!activeDot) return { prevent: true, action: s.order[0] ? { kind: 'activate', id: s.order[0].id } : null }
    const next = nextInDirection(s.dots, activeDot, dir, s.visible)
    return { prevent: true, action: next ? { kind: 'activate', id: next.id } : null }
  }
  if (e.key === 'Tab' && activeDot && !e.altKey && !e.ctrlKey && !e.metaKey) {
    const i = s.order.findIndex((d) => d.id === activeDot.id)
    const j = i + (e.shiftKey ? -1 : 1)
    return i >= 0 && j >= 0 && j < s.order.length ? { prevent: true, action: { kind: 'activate', id: s.order[j].id } } : null
  }
  if (e.key === 'Enter' && activeDot) return { prevent: true, action: { kind: 'open', id: activeDot.id } }
  if ((e.key === 'f' || e.key === 'F') && activeDot && s.canFocusPage && !e.ctrlKey && !e.metaKey && !e.altKey) return { prevent: true, action: { kind: 'focusPage', id: activeDot.id } }
  if (e.key === 'Escape' && s.hasActive) return { prevent: true, action: { kind: 'leave' } }
  if (e.key === '+' || e.key === '=') return { prevent: true, action: { kind: 'zoom', factor: 1.25 } }
  if (e.key === '-') return { prevent: true, action: { kind: 'zoom', factor: 0.8 } }
  if (e.key === '0') return { prevent: true, action: { kind: 'fit' } }
  return null
}
