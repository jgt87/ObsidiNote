// The size of a topic name on the map, shared by the layout (which keeps that room free of dots)
// and the stage (which draws the name there). Pure (tests: view.test.ts, layout.test.ts).

/** Height of a topic name's line, px (graph.css .kg-alabel: 14px bold). */
export const NAME_H = 22

/** Width of the page count beside a topic name (graph.css .kg-alabel__count: 12px, after the
 *  --space-3 gap of 8px); 0 without a count. */
export function countWidth(count?: number): number {
  return count === undefined ? 0 : String(count).length * 12 * 0.56 + 8
}

/** Estimated size of a topic name (graph.css .kg-alabel: 14px bold), with its page count when one
 *  is given: the layout keeps room for both, and the stage draws both. */
export function areaLabelSize(name: string, count?: number): { w: number; h: number } {
  return { w: [...name].length * 14 * 0.62 + 16 + countWidth(count), h: NAME_H }
}

/** A name cut to fit `maxW` screen px (areaLabelSize's estimate, count included), with "…". ''
 *  when not even two letters and the "…" fit: the caller then draws no name (code review
 *  2026-11-15: a floor of four letters gave a name wider than its area). Cut by code point, so an
 *  emoji is never halved. */
export function shortenToWidth(name: string, maxW: number, count?: number): string {
  if (areaLabelSize(name, count).w <= maxW) return name
  const letters = [...name]
  const fit = Math.floor((maxW - 16 - countWidth(count)) / (14 * 0.62))
  if (fit < 3) return ''
  return fit >= letters.length ? name : letters.slice(0, fit - 1).join('').trimEnd() + '…'
}

/** Height of a group name inside an area, px (graph.css .kg-glabel: 11px). */
export const GROUP_H = 16

/** Estimated size of a group name inside an area (the Tags grouping: a topic's name). */
export function groupLabelSize(name: string): { w: number; h: number } {
  return { w: [...name].length * 11 * 0.56 + 8, h: GROUP_H }
}

/**
 * The room in the middle of an area that stays free for its name: half width and half height, in
 * layout units. `scale` = layout units per screen pixel at the zoom the map is fitted to: 1 on
 * a small map, more on a map that is fitted zoomed out, where the name (drawn at a fixed screen
 * size) covers more of the layout (layout.ts layoutGraph works it out).
 * design (review 2026-11-14): the name sits in the middle of its area (operator, 2026-11-14), and
 * the dots keep out of that room, so a name never lies on the pages it names.
 */
export function labelSlot(name: string, r: number, scale = 1, count?: number): { hw: number; hh: number } {
  return { hw: Math.min(areaLabelSize(name, count).w * scale, r * 1.8) / 2, hh: (NAME_H * scale) / 2 }
}
