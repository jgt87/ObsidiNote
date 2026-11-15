// The size of a topic name on the map, shared by the layout (which keeps that room free of dots)
// and the stage (which draws the name there). Pure (tests: view.test.ts, layout.test.ts).

/** Height of a topic name's line, px (graph.css .kg-alabel: 14px bold). */
export const NAME_H = 22

/** Estimated size of a topic name (graph.css .kg-alabel: 14px bold). */
export function areaLabelSize(name: string): { w: number; h: number } {
  return { w: [...name].length * 14 * 0.62 + 16, h: NAME_H }
}

/** A name cut to fit `maxW` screen px (areaLabelSize's estimate), with "…". '' when not even two
 *  letters and the "…" fit: the caller then draws no name (code review 2026-11-15: a floor of four
 *  letters gave a name wider than its area). Cut by code point, so an emoji is never halved. */
export function shortenToWidth(name: string, maxW: number): string {
  if (areaLabelSize(name).w <= maxW) return name
  const letters = [...name]
  const fit = Math.floor((maxW - 16) / (14 * 0.62))
  if (fit < 3) return ''
  return fit >= letters.length ? name : letters.slice(0, fit - 1).join('').trimEnd() + '…'
}

/**
 * The room in the middle of an area that stays free for its name: half width and half height, in
 * layout units. `scale` = layout units per screen pixel at the zoom the map is fitted to: 1 on
 * a small map, more on a map that is fitted zoomed out, where the name (drawn at a fixed screen
 * size) covers more of the layout (layout.ts layoutGraph works it out).
 * design (review 2026-11-14): the name sits in the middle of its area (operator, 2026-11-14), and
 * the dots keep out of that room, so a name never lies on the pages it names.
 */
export function labelSlot(name: string, r: number, scale = 1): { hw: number; hh: number } {
  return { hw: Math.min(areaLabelSize(name).w * scale, r * 1.8) / 2, hh: (NAME_H * scale) / 2 }
}
