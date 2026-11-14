// The preview card next to the focused dot. It floats with a shadow and never catches the
// pointer (.kg-card and its children have pointer-events: none), so it cannot steal the hover.

import { formatDate } from './format'
import { indexPath, type GraphIndex } from './graphIndex'
import type { DotLayout } from './layout'
import { primaryTopic, type GraphPage } from './model'
import { cardPosition, toScreen, type Viewport } from './view'

const W = 280
const H = 168

interface Props {
  index: GraphIndex
  page: GraphPage
  dot: DotLayout
  view: Viewport
  stage: { w: number; h: number }
  /** The focused page's linked pages: the card goes where it covers the fewest of them. */
  near?: DotLayout[]
  /** Key that focuses the map on this page; shown on the keyboard path only. */
  focusKey?: string
}

export function HoverCard({ index, page, dot, view, stage, near = [], focusKey }: Props) {
  const [sx, sy] = toScreen(view, dot.x, dot.y)
  const off = dot.r * view.k + 12
  const points = near.map((d) => {
    const [x, y] = toScreen(view, d.x, d.y)
    return { x, y }
  })
  const { left, top } = cardPosition({ x: sx, y: sy }, off, points, stage, { w: W, h: H })
  const out = index.out.get(page.id)?.length ?? 0
  const back = index.in.get(page.id)?.length ?? 0
  const added = formatDate(page.modified)
  return (
    <div className="kg-card" role="tooltip" style={{ left, top }}>
      <div className="kg-card__path">{indexPath(index, primaryTopic(page))}</div>
      <div className="kg-card__title">{page.title}</div>
      {page.summary && <div className="kg-card__summary">{page.summary}</div>}
      <div className="kg-card__meta">
        {out} {out === 1 ? 'link' : 'links'} · {back} {back === 1 ? 'backlink' : 'backlinks'} · {page.isHub ? 'hub page' : page.kind || 'page'}
        {added ? ` · ${added}` : ''}
        {page.readOnly ? ' · read only' : ''}
      </div>
      <div className="kg-card__foot">
        {focusKey ? (
          <>
            <span>
              <kbd>Enter</kbd> open
            </span>
            <span>
              <kbd>{focusKey}</kbd> focus on this page
            </span>
          </>
        ) : (
          <>
            <span>Click to open</span>
            <span>Enter</span>
          </>
        )}
      </div>
    </div>
  )
}
