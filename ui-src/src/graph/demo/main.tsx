// Dev-only demo of the knowledge graph on synthetic data (graph-demo.html). Not part of the
// production build (vite builds index.html only).

import { StrictMode, useCallback, useState } from 'react'
import { createRoot } from 'react-dom/client'
import '../../../../src/styles/tokens.css'
// The shared helpers the app's components rely on: .icon sizes, .live regions, .visually-hidden.
import '../../styles/app.css'
import { installDisabledGuard } from '../../components/disabledGuard'
import { GraphView } from '../GraphView'
import { layoutGraph } from '../layout'
import type { GraphModel } from '../model'
import { syntheticGraph } from '../synthetic'
import { createDemoServer } from './demoServer'
import { QuickSwitcher } from '../../search/QuickSwitcher'
import type { FindRequest } from '../../search/switcherModel'
import './demo.css'

// Quick switcher (Ctrl+K) on the same synthetic model.
const loadFind = () => new Promise<GraphModel>((resolve) => setTimeout(() => resolve(demo.model()), 150))

const q = new URLSearchParams(location.search)
const pages = Number(q.get('pages') ?? 100)
const topics = Number(q.get('topics') ?? (pages > 300 ? 12 : 6))
const seed = Number(q.get('seed') ?? 7)
const readOnly = q.get('readOnly') === '1'
const state = q.get('state') ?? ''
const bench = q.get('bench') === '1'
if (q.get('theme')) document.documentElement.dataset.theme = q.get('theme')!

// The stand-ins for the server, over the demo's own model (demoServer.ts).
const demo = createDemoServer(q, syntheticGraph({ pages: state === 'empty' ? 0 : pages, topics, seed, readOnly }))

function Demo() {
  const [log, setLog] = useState('')
  const [fail, setFail] = useState(state === 'error')
  const [find, setFind] = useState<FindRequest | null>(null)
  const load = useCallback(
    (signal: AbortSignal) =>
      new Promise<GraphModel>((resolve, reject) => {
        if (state === 'loading') return // stays in the skeleton
        const t = setTimeout(() => (fail ? reject(new Error('ObsidiNote is not answering. Is it still running?')) : resolve(demo.model())), 250)
        signal.addEventListener('abort', () => clearTimeout(t))
      }),
    [fail],
  )
  return (
    <div className="demo">
      <GraphView
        load={load}
        onAsk={(p) => setLog(`Ask about this: ${p.title}`)}
        onEditPage={(req) => demo.editPage(req, setLog)}
        onLinkMention={(a, b) => demo.linkMention(a, b, setLog)}
        onTagPages={(ids, add, remove) => demo.tagPages(ids, add, remove, setLog)}
        loadBody={demo.loadBody}
        onAdd={() => setLog('Add')}
        request={find}
        onRequestDone={() => setFind(null)}
      />
      <QuickSwitcher vaultKey="demo" load={loadFind} onPick={setFind} />
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
installDisabledGuard(window)
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
/** Runs `act(i)` n times, each followed by one frame, and the time from the act to that frame;
 *  `after(i)` runs once the frame is timed. */
async function timeFrames(n: number, act: (i: number) => void, after?: (i: number) => void): Promise<number[]> {
  const times: number[] = []
  for (let i = 0; i < n; i++) {
    const s = performance.now()
    act(i)
    await frame()
    times.push(performance.now() - s)
    after?.(i)
  }
  return times
}

/** The layout alone, then the first paint of the map (waiting for its first dot). */
async function benchFirstPaint(out: Record<string, unknown>) {
  const l0 = performance.now()
  layoutGraph(demo.model())
  out.layoutMs = +(performance.now() - l0).toFixed(1)
  // wait for the map (the loader resolves after 250 ms)
  while (!document.querySelector('.kg-stage svg circle.kg-dot')) await frame()
  await frame()
  out.firstPaintMs = +(performance.now() - t0).toFixed(1)
  out.firstPaintNote = 'from script start, includes the 250 ms simulated load and a layout in StrictMode (twice)'
  out.svgElements = document.querySelectorAll('.kg-stage svg *').length
}

/** 80 hovers spread over the dots: pointer over, one frame, pointer out. */
async function benchHover(out: Record<string, unknown>) {
  const dots = [...document.querySelectorAll<SVGCircleElement>('.kg-base circle.kg-dot')]
  const dot = (i: number) => dots[(i * 37) % dots.length]
  out.hoverFrameMs = stats(
    await timeFrames(
      80,
      (i) => dot(i).dispatchEvent(new PointerEvent('pointerover', { bubbles: true, pointerId: 1 })),
      (i) => dot(i).dispatchEvent(new PointerEvent('pointerout', { bubbles: true, pointerId: 1 })),
    ),
  )
}

/** 60 wheel steps (30 in, 30 out) at the stage's centre, then the settle after the gesture: one full
 *  re-render at the new zoom. */
async function benchWheel(out: Record<string, unknown>, stage: HTMLElement) {
  const r = stage.getBoundingClientRect()
  out.wheelZoomFrameMs = stats(
    await timeFrames(60, (i) =>
      stage.dispatchEvent(new WheelEvent('wheel', { bubbles: true, cancelable: true, deltaY: i < 30 ? -60 : 60, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 })),
    ),
  )
  const settle0 = performance.now()
  while (stage.hasAttribute('data-moving')) await frame()
  await frame()
  out.wheelSettleMs = +(performance.now() - settle0).toFixed(1)
  out.wheelSettleNote = 'includes the 140 ms settle delay'
}

/** The zoom buttons re-render at once (worst case per step): 20 steps, in and out by turns. */
async function benchButtons(out: Record<string, unknown>) {
  const btn = document.querySelector<HTMLButtonElement>('[aria-label="Zoom in"]')!
  const btnOut = document.querySelector<HTMLButtonElement>('[aria-label="Zoom out"]')!
  out.buttonZoomFrameMs = stats(await timeFrames(20, (i) => (i % 2 ? btnOut : btn).click()))
}

async function runBench() {
  const m = demo.model()
  const out: Record<string, unknown> = { pages: m.pages.length, topics: m.topics.length, edges: m.edges.length }
  await benchFirstPaint(out)
  await benchHover(out)
  await benchWheel(out, document.querySelector<HTMLElement>('.kg-stage')!)
  await benchButtons(out)
  out.idleFrameMs = stats(await timeFrames(30, () => {}))
  document.getElementById('bench')!.textContent = JSON.stringify(out, null, 2)
  document.title = 'bench-done'
}
if (bench) void runBench()
