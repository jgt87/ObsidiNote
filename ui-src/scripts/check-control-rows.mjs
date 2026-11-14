// Rendered check: every row of controls has one height (CommonShared rules/ui.md "One height per bar
// and per control kind, checked by a test over rendered heights at desktop and phone width").
// Drives the graph demo in headless Edge over CDP: graph, List, Filter panel, page window and its
// Edit form, at 1440 and 390 px; a row = controls with the same parent and centre line.
// Usage (ui-src): npx vite --port 5193 --strictPort   (separately), then
//   node scripts/check-control-rows.mjs [http://localhost:5193] [cdp port 9557]
// Exit 1 when a row mixes heights. Invented demo data only; writes nothing.
import { spawn } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const BASE = (process.argv[2] || 'http://localhost:5193') + '/graph-demo.html'
const PORT = Number(process.argv[3] || 9557)
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
const profile = mkdtempSync(join(tmpdir(), 'kg-rows-'))
const edge = spawn(EDGE, ['--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`, '--no-first-run', '--window-size=1440,900', 'about:blank'], { stdio: 'ignore' })
const wait = (ms) => new Promise((r) => setTimeout(r, ms))

let ws, id = 0
const pending = new Map()
const send = (method, params = {}, sessionId) =>
  new Promise((resolve, reject) => { const i = ++id; pending.set(i, { resolve, reject }); ws.send(JSON.stringify({ id: i, method, params, sessionId })) })

const SCAN = `(() => {
  const els = [...document.querySelectorAll('a.btn, button, select, input:not([type=checkbox]):not([type=radio]), .field')]
    .filter((e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && !e.closest('svg') })
  const groups = new Map()
  for (const e of els) {
    const r = e.getBoundingClientRect()
    const key = (e.parentElement.className || e.parentElement.tagName) + '|' + Math.round((r.top + r.height / 2) / 6)
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key).push((e.textContent.trim() || e.getAttribute('aria-label') || e.tagName).slice(0, 16) + '=' + Math.round(r.height))
  }
  const bad = []
  for (const [k, list] of groups) if (list.length > 1 && new Set(list.map((x) => x.split('=').pop())).size > 1) bad.push(k.split('|')[0] + ': ' + list.join(', '))
  return JSON.stringify(bad)
})()`

async function main() {
  let ver
  for (let k = 0; k < 50 && !ver; k++) { try { ver = await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json() } catch { await wait(200) } }
  ws = new WebSocket(ver.webSocketDebuggerUrl)
  await new Promise((r) => ws.addEventListener('open', r))
  ws.addEventListener('message', (m) => { const d = JSON.parse(m.data); if (d.id && pending.has(d.id)) { const p = pending.get(d.id); pending.delete(d.id); d.error ? p.reject(new Error(JSON.stringify(d.error))) : p.resolve(d.result) } })
  const { targetId } = await send('Target.createTarget', { url: 'about:blank' })
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true })
  const S = (m, p) => send(m, p, sessionId)
  const js = async (e) => (await S('Runtime.evaluate', { expression: e, awaitPromise: true, returnByValue: true })).result.value
  const go = async (q) => { await S('Page.navigate', { url: BASE + q }); for (let k = 0; k < 150; k++) { if (await js(`!!document.querySelector('.kg-dot')`)) break; await wait(100) }; await wait(400) }
  const click = (text, scope = 'document') => js(`[...${scope}.querySelectorAll('button')].find((b) => b.textContent.trim() === ${JSON.stringify(text)})?.click()`)
  await S('Page.enable')
  const problems = []
  for (const [w, h, mobile] of [[1440, 900, false], [390, 844, true]]) {
    await S('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile })
    const check = async (view) => { for (const b of JSON.parse(await js(SCAN))) problems.push(`${w}px ${view}: ${b}`) }
    await go('?pages=100'); await check('graph')
    await click('List'); await wait(400); await check('list')
    await click('Filter'); await wait(300); await check('filter panel')
    await go('?pages=100')
    const pos = await js(`(() => { const r = document.querySelectorAll('.kg-base circle.kg-dot--hub')[0].getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2] })()`)
    for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) await S('Input.dispatchMouseEvent', { type, x: pos[0], y: pos[1], button: type === 'mouseMoved' ? 'none' : 'left', clickCount: 1 })
    await wait(400); await check('page window')
    await click('Edit', `document.querySelector('dialog[open]')`); await wait(300); await check('edit form')
  }
  if (problems.length) { console.error('Rows with mixed control heights:\n' + problems.join('\n')); process.exitCode = 1 }
  else console.log('OK: every row of controls has one height (graph, list, filter panel, page window, edit form; 1440 and 390 px).')
}
main().catch((e) => { console.error(e); process.exitCode = 1 }).finally(async () => {
  try { ws?.close() } catch {}
  edge.kill()
  await wait(800)
  try { rmSync(profile, { recursive: true, force: true }) } catch {}
})
