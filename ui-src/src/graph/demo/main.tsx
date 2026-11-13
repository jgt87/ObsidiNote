// Dev-only demo of the knowledge graph on synthetic data (graph-demo.html). Not part of the
// production build (vite builds index.html only).

import { StrictMode, useCallback, useState } from 'react'
import { createRoot } from 'react-dom/client'
import '../../../../src/styles/tokens.css'
import { GraphView } from '../GraphView'
import { layoutGraph } from '../layout'
import type { GraphModel } from '../model'
import { syntheticGraph } from '../synthetic'
import './demo.css'

const q = new URLSearchParams(location.search)
const pages = Number(q.get('pages') ?? 100)
const topics = Number(q.get('topics') ?? (pages > 300 ? 12 : 6))
const seed = Number(q.get('seed') ?? 7)
const readOnly = q.get('readOnly') === '1'
const state = q.get('state') ?? ''
const bench = q.get('bench') === '1'
if (q.get('theme')) document.documentElement.dataset.theme = q.get('theme')!

const model = syntheticGraph({ pages: state === 'empty' ? 0 : pages, topics, seed, readOnly })

function Demo() {
  const [log, setLog] = useState('')
  const [fail, setFail] = useState(state === 'error')
  const load = useCallback(
    (signal: AbortSignal) =>
      new Promise<GraphModel>((resolve, reject) => {
        if (state === 'loading') return // stays in the skeleton
        const t = setTimeout(() => (fail ? reject(new Error('ObsidiNote is not answering. Is it still running?')) : resolve(model)), 250)
        signal.addEventListener('abort', () => clearTimeout(t))
      }),
    [fail],
  )
  return (
    <div className="demo">
      <GraphView
        load={load}
        onAsk={(p) => setLog(`Ask about this: ${p.title}`)}
        onEditLinks={(p) => setLog(`Edit links: ${p.title}`)}
        onMoveInIndex={(p) => setLog(`Move in index: ${p.title}`)}
        onLinkMention={(a, b) => setLog(`Link it: ${a.title} → ${b.title}`)}
        onAdd={() => setLog('Add')}
      />
      <div className="demo-log" aria-live="polite">
        {log}
        {fail && (
          <button type="button" className="btn btn--sm" style={{ marginLeft: 8 }} onClick={() => setFail(false)}>
            Let the next try succeed
          </button>
        )}
      </div>
      {bench && <pre id="bench" className="demo-bench" />}
    </div>
  )
}

const t0 = performance.now()
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Demo />
  </StrictMode>,
)

// ---------- benchmark (?bench=1): layout, first render, hover and zoom frame times ----------
const frame = () => new Promise<number>((r) => requestAnimationFrame(r))
const stats = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b)
  const avg = s.reduce((a, b) => a + b, 0) / (s.length || 1)
  return { avg: +avg.toFixed(2), p95: +(s[Math.floor(s.length * 0.95)] ?? 0).toFixed(2), max: +(s[s.length - 1] ?? 0).toFixed(2) }
}
async function runBench() {
  const out: Record<string, unknown> = { pages: model.pages.length, topics: model.topics.length, edges: model.edges.length }
  const l0 = performance.now()
  layoutGraph(model)
  out.layoutMs = +(performance.now() - l0).toFixed(1)
  // wait for the map (the loader resolves after 250 ms)
  while (!document.querySelector('.kg-stage svg circle.kg-dot')) await frame()
  await frame()
  out.firstPaintMs = +(performance.now() - t0).toFixed(1)
  out.firstPaintNote = 'from script start, includes the 250 ms simulated load and a layout in StrictMode (twice)'
  out.svgElements = document.querySelectorAll('.kg-stage svg *').length

  const dots = [...document.querySelectorAll<SVGCircleElement>('.kg-base circle.kg-dot')]
  const hover: number[] = []
  for (let i = 0; i < 80; i++) {
    const el = dots[(i * 37) % dots.length]
    const s = performance.now()
    el.dispatchEvent(new PointerEvent('pointerover', { bubbles: true, pointerId: 1 }))
    await frame()
    hover.push(performance.now() - s)
    el.dispatchEvent(new PointerEvent('pointerout', { bubbles: true, pointerId: 1 }))
  }
  out.hoverFrameMs = stats(hover)

  const stage = document.querySelector<HTMLElement>('.kg-stage')!
  const r = stage.getBoundingClientRect()
  const zoom: number[] = []
  for (let i = 0; i < 60; i++) {
    const s = performance.now()
    stage.dispatchEvent(new WheelEvent('wheel', { bubbles: true, cancelable: true, deltaY: i < 30 ? -60 : 60, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 }))
    await frame()
    zoom.push(performance.now() - s)
  }
  out.wheelZoomFrameMs = stats(zoom)
  // the settle after the wheel gesture: one full re-render at the new zoom
  const settle0 = performance.now()
  while (stage.hasAttribute('data-moving')) await frame()
  await frame()
  out.wheelSettleMs = +(performance.now() - settle0).toFixed(1)
  out.wheelSettleNote = 'includes the 140 ms settle delay'
  // zoom buttons re-render at once (worst case per step)
  const btn = document.querySelector<HTMLButtonElement>('[aria-label="Zoom in"]')!
  const btnOut = document.querySelector<HTMLButtonElement>('[aria-label="Zoom out"]')!
  const steps: number[] = []
  for (let i = 0; i < 20; i++) {
    const s = performance.now()
    ;(i % 2 ? btnOut : btn).click()
    await frame()
    steps.push(performance.now() - s)
  }
  out.buttonZoomFrameMs = stats(steps)
  const idle: number[] = []
  for (let i = 0; i < 30; i++) {
    const s = performance.now()
    await frame()
    idle.push(performance.now() - s)
  }
  out.idleFrameMs = stats(idle)
  document.getElementById('bench')!.textContent = JSON.stringify(out, null, 2)
  document.title = 'bench-done'
}
if (bench) void runBench()
