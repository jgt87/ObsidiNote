// Dev-only demo of the knowledge graph on synthetic data (graph-demo.html). Not part of the
// production build (vite builds index.html only).

import { StrictMode, useCallback, useState } from 'react'
import { createRoot } from 'react-dom/client'
import '../../../../src/styles/tokens.css'
import { GraphView } from '../GraphView'
import { layoutGraph } from '../layout'
import type { PageEditRequest } from '../editModel'
import type { GraphModel, GraphPage } from '../model'
import type { PageBodyResult } from '../PageBody'
import { syntheticGraph } from '../synthetic'
import { QuickSwitcher } from '../../search/QuickSwitcher'
import type { FindRequest } from '../../search/switcherModel'
import './demo.css'

// Quick switcher (Ctrl+K) on the same synthetic model.
const loadFind = () => new Promise<GraphModel>((resolve) => setTimeout(() => resolve(model), 150))

const q = new URLSearchParams(location.search)
const pages = Number(q.get('pages') ?? 100)
const topics = Number(q.get('topics') ?? (pages > 300 ? 12 : 6))
const seed = Number(q.get('seed') ?? 7)
const readOnly = q.get('readOnly') === '1'
const state = q.get('state') ?? ''
const bench = q.get('bench') === '1'
if (q.get('theme')) document.documentElement.dataset.theme = q.get('theme')!

let model = syntheticGraph({ pages: state === 'empty' ? 0 : pages, topics, seed, readOnly })

// ---------- stand-ins for the server: never the real routes (the dev server proxies /api to a
// running app). Each ?<name>=fail shows that call's error. ----------

const WRITER_ELSEWHERE = 'Read only: another ObsidiNote is writing in this vault.'

/** After `ms`, fails with `message` when ?<param>=fail, else runs `ok` and resolves. */
function afterOrFail(param: string, message: string, ms: number, ok: () => void): Promise<void> {
  return new Promise<void>((resolve, reject) =>
    setTimeout(() => {
      if (q.get(param) === 'fail') return reject(new Error(message))
      ok()
      resolve()
    }, ms),
  )
}

/** Edit: the title and summary change in the demo's own model. ?edit=fail shows the error in the form. */
function editPage(req: PageEditRequest, log: (s: string) => void): Promise<void> {
  return afterOrFail('edit', WRITER_ELSEWHERE, 400, () => {
    model = { ...model, pages: model.pages.map((p) => (p.id === req.id ? { ...p, title: req.title ?? p.title, summary: req.summary ?? p.summary } : p)) }
    log(`Edit: ${JSON.stringify(req)}`)
  })
}

/** "Link it" on a mention. ?link=fail shows the error; ?link=slow keeps the button busy for a minute. */
function linkMention(a: GraphPage, b: GraphPage, log: (s: string) => void): Promise<void> {
  return afterOrFail('link', WRITER_ELSEWHERE, q.get('link') === 'slow' ? 60_000 : 400, () => log(`Link it: ${a.title} → ${b.title}`))
}

/** Tags change in the demo's own model. ?tag=fail shows the error. */
async function tagPages(ids: string[], add: string[], remove: string[], log: (s: string) => void): Promise<void> {
  if (q.get('tag') === 'fail') throw new Error(WRITER_ELSEWHERE)
  model = { ...model, pages: model.pages.map((p) => (ids.includes(p.id) ? { ...p, tags: [...p.tags.filter((t) => !remove.includes(t)), ...add.filter((t) => !p.tags.includes(t))] } : p)) }
  log(`Tag ${ids.length} page(s): +[${add.join(', ')}] -[${remove.join(', ')}]`)
}

/** An invented page text: headings, lists, a task list, a table, a web link and a link to another
 *  page of the map. */
function demoPageText(id: string): string {
  const other = model.pages.find((p) => p.id !== id)
  return [
    '# Overview',
    'An invented page text for the demo: it checks **who** asks and *from where*, as [the guide](https://example.com/guide) says.',
    '## Steps',
    '1. Plan\n2. Roll **out**\n3. Review',
    `See ${other ? `[${other.title}](obsn:${other.id})` : 'another page'} for the background.`,
    '- Check the user\n    - with a second factor\n- Check the device',
    '- [ ] ask the network team\n- [x] read the guide',
    '| Name | Use |\n| --- | --- |\n| Proxy | checks every request |\n| `vpn` | the old way |',
    '## Your notes',
    'My own words stay.',
  ].join('\n\n')
}

/** The page's text. ?body=fail|empty|long shows the other states. */
function loadBody(id: string): Promise<PageBodyResult> {
  return new Promise((resolve, reject) =>
    setTimeout(() => {
      const body = q.get('body')
      if (body === 'fail') return reject(new Error('The page could not be read from OneNote. Try again.'))
      if (body === 'empty') return resolve({ markdown: '', truncated: false })
      resolve({ truncated: body === 'long', markdown: demoPageText(id) })
    }, 300),
  )
}

function Demo() {
  const [log, setLog] = useState('')
  const [fail, setFail] = useState(state === 'error')
  const [find, setFind] = useState<FindRequest | null>(null)
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
        onEditPage={(req) => editPage(req, setLog)}
        onLinkMention={(a, b) => linkMention(a, b, setLog)}
        onTagPages={(ids, add, remove) => tagPages(ids, add, remove, setLog)}
        loadBody={loadBody}
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
  layoutGraph(model)
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
  const out: Record<string, unknown> = { pages: model.pages.length, topics: model.topics.length, edges: model.edges.length }
  await benchFirstPaint(out)
  await benchHover(out)
  await benchWheel(out, document.querySelector<HTMLElement>('.kg-stage')!)
  await benchButtons(out)
  out.idleFrameMs = stats(await timeFrames(30, () => {}))
  document.getElementById('bench')!.textContent = JSON.stringify(out, null, 2)
  document.title = 'bench-done'
}
if (bench) void runBench()
