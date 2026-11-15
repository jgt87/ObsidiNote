// Rendered design checks that a reading of the CSS cannot hold (design review 2026-11-14: every one
// of these rules was already written down, and each was broken somewhere without a check):
//   1 one primary button per view (home, home with waiting items, History, graph, page window, Edit)
//   2 the knowledge graph never makes the page scroll (1440x900 and 1024x768)
//   3 in a narrow window (720 and 390 px) the Add box starts on the first screen
//   4 on a touch screen every control is at least 44 px high (390 px, coarse pointer)
//   5 no dot of the map lies under a topic name (100 pages, the Sources view, 600 pages)
//   6 a section row of the side bar opens a List that holds pages
//   7 "Labels: hubs only" leaves the topic names and names a page only while it is pointed at
//  10 tags: added in the page window, its chip opens the Tags grouping with that tag alone, added to two ticked rows of the List
//  15 the page window shows the page's text (headings, lists, a table, a link to another page that opens it; only http(s)/mailto/onenote addresses; a failed read as an error with one retry; a long page says so)
//  14 the page window's title is changed in place (Esc keeps the old one and the window, Enter saves, empty is refused)
//  13 the Tags grouping shows one area per tag with only tagged pages; a chip removes a tag's area; the topics inside are named on no dot
//  12 one banner names the reason the window is read only (not the side bar, no badge); Settings lists the vault's tags
//  11 a read-only page window says why and shows Edit disabled
//   9 the map's search shows its clear button whenever it holds text, without hover, and it clears
//   8 during a long zoom-in with the wheel the map is drawn again before it is stretched 1.35 times
// Views and states visited: home (idle, with waiting items, after an Add, with an Add that waits),
// History, knowledge graph (map, List), page window, its Edit form.
// NOT covered, so the rules above are not proven there: the Ask answer and its error, a failed Add,
// the Settings, New vault and Set up dialogs, the quick switcher, the Filter panel, a link Update
// (old/new), the replace confirmation, a read-only vault, dark theme.
// Drives the app in headless Edge over CDP with the API answered here from invented data, and the
// graph demo. Usage (ui-src): npx vite --port 5193 --strictPort   (separately), then
//   node scripts/check-design-rules.mjs [http://localhost:5193] [cdp port 9559]
// Exit 1 names the view and the rule. Writes nothing.
import { spawn } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const BASE = process.argv[2] || 'http://localhost:5193'
const PORT = Number(process.argv[3] || 9559)
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
const profile = mkdtempSync(join(tmpdir(), 'obsn-design-'))
const edge = spawn(EDGE, ['--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`, '--no-first-run', '--window-size=1440,900', 'about:blank'], { stdio: 'ignore' })
const wait = (ms) => new Promise((r) => setTimeout(r, ms))

// ---------- invented data for the app's API ----------
const VAULT = '{11111111-1111-1111-1111-111111111111}{1}{B0}'
const ago = (min) => new Date(Date.now() - min * 60000).toISOString()
const waitingItem = (n) => ({ inboxId: `i${n}`, title: `https://contoso.example/sites/platform/plan-${n}.docx`, state: 'waiting', kind: 'link', requestKind: 'add', updated: ago(14 * n), since: ago(14 * n), reason: '', filedAs: '', filedTitle: '', filedType: '', canCheck: true, canRemove: true, canUndo: false })
const addedItem = { inboxId: 'i9', title: 'Notes from the steering group', state: 'added', kind: 'text', requestKind: 'add', updated: ago(45), since: '', reason: '', filedAs: 'p12', filedTitle: 'Steering group', filedType: 'meeting', canCheck: false, canRemove: false, canUndo: true }
const notebook = { id: VAULT, name: 'Work wiki', vault: true, active: true, location: 'OneDrive', vaultId: 'v1', kind: 'notebook', notebookId: VAULT }
const section = (name, pages) => ({ name, kind: 'section', pages, children: [] })
let graph = null
let waiting = false
let vaultStatus = null
const added = { intent: 'add', status: 'added', kind: 'link', message: 'Added.', inboxId: '', ref: 'r1a2b3c4d', text: 'https://contoso.example/sites/platform/plan.docx',
  page: { id: 'p900', title: 'Network segmentation plan', type: 'link-internal', bucket: 'Internal links', section: 'Internal links', link: 'onenote:x', url: 'https://contoso.example/sites/platform/plan.docx', topicPath: 'Security/Networking', alsoUnder: [], oneNotePath: ['Work wiki', 'Internal links', 'Network segmentation plan'], unfiled: false },
  chips: [{ kind: 'type', label: 'Internal link' }], links: [{ target: 'p3', title: 'Zero trust overview', link: 'onenote:x', anchor: 'zero trust', strength: 3, why: 'Applies the model.' }],
  backlinks: 1, related: [], dropped: [], warnings: [], timings: { totalMs: 48200 }, undo: { id: 'u1', pageId: 'p900', targets: ['p3'] }, inbox: { pageId: 'i9', status: 'filed' }, update: null, confirm: null }
let submitAnswer = added
function answer(path) {
  switch (path) {
    case '/api/status': return { app: 'ObsidiNote', version: 'v0.0.0', uiPort: 8767, oneNote: { state: 'window', running: true, notebookOpen: true, notebook: 'Work wiki' }, copilot: { state: 'connected', port: 9334 }, ...(vaultStatus ? { vault: vaultStatus } : {}) }
    case '/api/notebooks': return { notebooks: [notebook], message: '', activeVaultId: VAULT, mode: 'writer' }
    case '/api/notebook': return { available: true, message: '', notebook, sections: ['00 Index', '01 Intake', 'Notes', 'Web links', 'Meetings', 'Decisions'].map((n, i) => section(n, 3 + i)), totals: { sections: 6, pages: 33 },
      recent: graph.pages.slice(0, 6).map((p, i) => ({ title: p.title, section: p.bucket, modified: ago(60 * (i + 1)), link: 'onenote:x', pageId: p.id, type: p.kind })) }
    case '/api/settings': return { settings: { internalHosts: [], graphView: 'topics', labelsHubsOnly: false, relatedCount: 3, linkStaleDays: 90, askIncludeArchived: false, graphShowArchived: false, askMaxPages: 20 }, canChange: true }
    case '/api/whats-new': return { version: 'v0.0.0', updated: false, notes: [] }
    case '/api/activity': return { canChange: true, vaultId: 'v1', items: [...(waiting ? [waitingItem(1), waitingItem(2)] : []), addedItem] }
    case '/api/graph': return graph
    case '/api/intent': return { intent: 'add', reason: 'It is a link', rule: 2 }
    case '/api/submit': return submitAnswer
    default: return null
  }
}

let ws, id = 0
const pending = new Map()
const send = (method, params = {}, sessionId) =>
  new Promise((resolve, reject) => { const i = ++id; pending.set(i, { resolve, reject }); ws.send(JSON.stringify({ id: i, method, params, sessionId })) })

// Visible, enabled-or-not primary buttons outside closed dialogs.
const PRIMARIES = `JSON.stringify([...document.querySelectorAll('.btn--primary')].filter((e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && (!e.closest('dialog') || e.closest('dialog[open]')) && (!document.querySelector('dialog[open]') || e.closest('dialog[open]')) }).map((e) => e.textContent.trim()))`
// Controls under 44 px on a touch screen. Text links inside a sentence are exempt (WCAG 2.5.8 inline).
const SMALL = `JSON.stringify([...document.querySelectorAll('button, a.btn, select, input:not([type=checkbox]):not([type=radio]):not([type=file]), [role=tab]')].filter((e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && !e.closest('svg') && !e.matches('.link-btn, .kg-linkbtn, .kg-rowbtn, .recent__open, .ask-src__page') && r.height < 43.5 }).map((e) => (e.textContent.trim() || e.getAttribute('aria-label') || e.tagName).slice(0, 24) + '=' + Math.round(e.getBoundingClientRect().height)))`
const UNDER_NAMES = `JSON.stringify((() => { const hit = (a, b) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom
  const dots = [...document.querySelectorAll('.kg-base circle.kg-dot')].map((d) => d.getBoundingClientRect())
  return [...document.querySelectorAll('.kg-alabel b')].map((l) => ({ name: l.textContent, n: dots.filter((d) => hit(l.getBoundingClientRect(), d)).length })).filter((x) => x.n > 0) })())`

async function main() {
  let ver
  for (let k = 0; k < 60 && !ver; k++) { try { ver = await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json() } catch { await wait(200) } }
  ws = new WebSocket(ver.webSocketDebuggerUrl)
  await new Promise((r) => ws.addEventListener('open', r))
  const { targetId } = await new Promise((resolve) => {
    ws.addEventListener('message', function first(m) { const d = JSON.parse(m.data); if (d.id === 1) { ws.removeEventListener('message', first); resolve(d.result) } })
    ws.send(JSON.stringify({ id: ++id, method: 'Target.createTarget', params: { url: 'about:blank' } }))
  })
  ws.addEventListener('message', (m) => {
    const d = JSON.parse(m.data)
    if (d.id && pending.has(d.id)) { const p = pending.get(d.id); pending.delete(d.id); d.error ? p.reject(new Error(JSON.stringify(d.error))) : p.resolve(d.result) }
    else if (d.method === 'Fetch.requestPaused') {
      const { requestId, request } = d.params
      const body = answer(new URL(request.url).pathname)
      send('Fetch.fulfillRequest', { requestId, responseCode: body ? 200 : 404, responseHeaders: [{ name: 'Content-Type', value: 'application/json' }], body: Buffer.from(JSON.stringify(body ?? { error: 'not stubbed' })).toString('base64') }, d.sessionId).catch(() => {})
    }
  })
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true })
  const S = (m, p) => send(m, p, sessionId)
  const js = async (e) => (await S('Runtime.evaluate', { expression: e, awaitPromise: true, returnByValue: true })).result.value
  const list = async (e) => JSON.parse(await js(e))
  await S('Page.enable')
  await S('Fetch.enable', { patterns: [{ urlPattern: '*/api/*' }] })
  const size = async (w, h, touch = false) => { await S('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: touch }); await S('Emulation.setTouchEmulationEnabled', { enabled: touch }) }
  const go = async (path, ready) => {
    await S('Page.navigate', { url: 'about:blank' })
    await S('Page.navigate', { url: BASE + path })
    let ok = false
    for (let k = 0; k < 150 && !ok; k++) { ok = await js(`!!document.querySelector(${JSON.stringify(ready)})`).catch(() => false); if (!ok) await wait(100) }
    if (!ok) throw new Error(`${path}: ${ready} never appeared (is Vite running on ${BASE}?)`)
    await wait(500)
  }
  const click = (text, scope = 'document') => js(`[...${scope}.querySelectorAll('button')].find((b) => b.textContent.trim() === ${JSON.stringify(text)})?.click()`)
  const openDot = async () => {
    const pos = await list(`JSON.stringify((() => { const r = document.querySelectorAll('.kg-base circle.kg-dot--hub')[0].getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2] })())`)
    for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) await S('Input.dispatchMouseEvent', { type, x: pos[0], y: pos[1], button: type === 'mouseMoved' ? 'none' : 'left', clickCount: 1 })
    await wait(500)
  }

  const problems = []
  let checks = 0
  const expect = (ok, text) => { checks++; if (!ok) problems.push(text) }

  await size(1440, 900)
  await go('/graph-demo.html?pages=100', '.kg-dot')
  graph = JSON.parse(await js(`import('/src/graph/synthetic.ts').then((m) => JSON.stringify(m.syntheticGraph({ pages: 100, topics: 6, seed: 7 })))`))
  // The app asks for the graph of vault v1 (the notebook stub's vaultId): the stub graph is that vault's.
  graph.source = { ...graph.source, id: 'v1', kind: 'vault', readOnly: false }

  // 5 no dot under a topic name (the demo map and the Sources view)
  let under = await list(UNDER_NAMES)
  expect(under.length === 0, `map: dots under topic names: ${JSON.stringify(under)}`)
  await click('Sources'); await wait(700)
  under = await list(UNDER_NAMES)
  expect(under.length === 0, `map, Sources view: dots under names: ${JSON.stringify(under)}`)

  await go('/graph-demo.html?pages=600&topics=25', '.kg-dot'); await wait(600)
  under = await list(UNDER_NAMES)
  expect(under.length === 0, `map of 600 pages (fitted zoomed out): dots under topic names: ${JSON.stringify(under)}`)

  // "Labels: hubs only": the topic names stay, no page is named at rest, the page pointed at is.
  await go('/graph-demo.html?pages=100', '.kg-dot')
  const pageNames = () => js(`document.querySelectorAll('.kg-plabel').length`)
  const topicNames = () => js(`document.querySelectorAll('.kg-alabel').length`)
  const before = [await pageNames(), await topicNames()]
  // The switch is in the Filter panel ("Show on the map"), no longer a button in the bar.
  await click('Filter'); await wait(300)
  await js(`[...document.querySelectorAll('.kg-fp__opt')].find((l) => l.textContent.trim() === 'Labels: hubs only').querySelector('input').click()`)
  await wait(300)
  await js(`[...document.querySelectorAll('.kg-fp__foot button')].find((b) => b.textContent.trim() === 'Done').click()`)
  await wait(400)
  expect(before[0] > 0 && (await pageNames()) === 0 && (await topicNames()) === before[1], `hubs only: ${await pageNames()} page name(s) at rest (were ${before[0]}), ${await topicNames()} topic name(s) (were ${before[1]})`)
  {
    const pos = await list(`JSON.stringify((() => { const r = document.querySelectorAll('.kg-base circle.kg-dot--hub')[0].getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2] })())`)
    await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: pos[0], y: pos[1], button: 'none' })
    await wait(400)
    expect((await pageNames()) === 1, `hubs only, pointing at a page: ${await pageNames()} page name(s) (1 expected: its own)`)
    await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 5, y: 5, button: 'none' })
  }

  // 8 a long zoom-in never shows the map as a far-stretched picture of its last drawing
  await go('/graph-demo.html?pages=100', '.kg-dot')
  {
    const r = await list(`JSON.stringify((() => { const b = document.querySelector('.kg-stage').getBoundingClientRect(); return [b.x + b.width / 2, b.y + b.height / 2] })())`)
    const areaWidth = () => js(`document.querySelector('.kg-area').getBoundingClientRect().width`)
    const widthBefore = await areaWidth()
    let worst = 1
    for (let i = 0; i < 14; i++) {
      await S('Input.dispatchMouseEvent', { type: 'mouseWheel', x: r[0], y: r[1], deltaX: 0, deltaY: -60 })
      await wait(25)
      const scale = await js(`(() => { const m = /scale\\(([\\d.]+)\\)/.exec(document.querySelector('.kg-layer').style.transform); return m ? Number(m[1]) : 1 })()`)
      worst = Math.max(worst, scale)
    }
    // The wheel must really have zoomed, or the next line passes on a map that never moved.
    await wait(400)
    const grew = (await areaWidth()) / widthBefore
    expect(grew > 1.8, `zooming in with the wheel: the map grew ${grew.toFixed(2)} times after 14 wheel steps (the check did not zoom)`)
    expect(worst <= 1.35, `zooming in with the wheel: the map was shown stretched ${worst.toFixed(2)} times before being drawn again (1.35 at most)`)
  }

  // 9 the map's search shows its clear button whenever it holds text (no hover needed), and it clears
  await go('/graph-demo.html?pages=100', '.kg-dot')
  {
    const shown = () => js(`(() => { const b = document.querySelector('.kg-search__clear'); if (!b) return false; const r = b.getBoundingClientRect(); return r.width > 0 && r.height > 0 && getComputedStyle(b).opacity === '1' && getComputedStyle(b).visibility === 'visible' })()`)
    const empty = await shown()
    await js(`document.querySelector('#kg-search').focus()`)
    await S('Input.insertText', { text: 'zero' })
    await wait(300)
    await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 5, y: 5, button: 'none' })
    await js(`document.activeElement.blur()`)
    await wait(200)
    const withText = await shown()
    await js(`document.querySelector('.kg-search__clear')?.click()`)
    await wait(300)
    const after = await js(`document.querySelector('#kg-search').value`)
    expect(!empty && withText && after === '', `map search: clear button with an empty field ${empty}, with text and the pointer elsewhere ${withText}, value after pressing it "${after}"`)
  }

  // 10 tags: set in the page window, shown as one joined group on the map, set on several rows in the List
  await go('/graph-demo.html?pages=100', '.kg-dot')
  {
    await openDot()
    await js(`document.querySelector('dialog[open] .kg-tags__input').focus()`)
    await S('Input.insertText', { text: '  Trial   Tag ' })
    await S('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13 })
    await S('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13 })
    await wait(900)
    const chips = await list(`JSON.stringify([...document.querySelectorAll('dialog[open] .kg-tagchip__name')].map((e) => e.textContent.trim()))`)
    expect(chips.includes('trial tag'), `tags, page window: after adding "  Trial   Tag " the page's tags are ${JSON.stringify(chips)} ("trial tag" expected)`)
    // The tag's chip: the window closes and the map shows the Tags grouping with that tag alone.
    await js(`[...document.querySelectorAll('dialog[open] .kg-tagchip__name')].find((e) => e.textContent.trim() === 'trial tag').click()`)
    await wait(900)
    const one = await list(`JSON.stringify({ open: !!document.querySelector('dialog[open]'), areas: [...document.querySelectorAll('.kg-alabel b')].map((e) => e.textContent), dots: document.querySelectorAll('.kg-base circle.kg-dot').length, tags: document.querySelector('.seg__btn[aria-pressed="true"]')?.textContent.trim(), picker: !!document.querySelector('.kg-tagpick'), lines: document.querySelectorAll('.kg-tagline').length })`)
    expect(!one.open && one.tags === 'Tags' && JSON.stringify(one.areas) === '["trial tag"]' && one.dots === 1 && !one.picker && one.lines === 0, `tags, a chip in the page window: ${JSON.stringify(one)} (window closed, Tags grouping, the one area "trial tag" with 1 page expected)`)
    await click('Topics'); await wait(600)
    await click('List'); await wait(500)
    await js(`[...document.querySelectorAll('.kg-tbl__tick')].slice(0, 2).forEach((b) => b.click())`)
    await wait(300)
    const bar = await js(`document.querySelector('.kg-tbl__sel-count')?.textContent || ''`)
    await js(`document.querySelector('.kg-tbl__sel .kg-tags__input').focus()`)
    await S('Input.insertText', { text: 'bulk' })
    await S('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13 })
    await S('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13 })
    await wait(900)
    const tagged = await js(`[...document.querySelectorAll('.kg-tbl__table tbody tr[data-selected]')].filter((r) => /\\bbulk\\b/.test(r.children[3]?.textContent || '')).length`)
    expect(/^2 pages selected/.test(bar) && tagged === 2, `tags, List: bar says "${bar}", ${tagged} of the 2 ticked rows show the tag "bulk" in the Tags column`)
  }
  // 13 the Tags grouping: one area per tag, only tagged pages, and a chip takes a tag's area away
  await go('/graph-demo.html?pages=100', '.kg-dot')
  {
    await click('Tags'); await wait(900)
    const names = async () => list(`JSON.stringify([...document.querySelectorAll('.kg-alabel b')].map((e) => e.textContent).sort())`)
    const dots = () => js(`document.querySelectorAll('.kg-base circle.kg-dot').length`)
    const all = await names()
    const tagged = await dots()
    expect(JSON.stringify(all) === JSON.stringify(['follow up', 'key reference', 'licensing']) && tagged > 0 && tagged < 100, `Tags grouping: areas ${JSON.stringify(all)}, ${tagged} dots (only the tagged pages of 100)`)
    await js(`[...document.querySelectorAll('.kg-tagbar button[aria-pressed]')].find((b) => b.textContent.trim().startsWith('licensing'))?.click()`)
    await wait(900)
    const fewer = await names()
    expect(!fewer.includes('licensing') && fewer.length === 2 && (await dots()) < tagged, `Tags grouping, "licensing" switched off: areas ${JSON.stringify(fewer)}, ${await dots()} dots (were ${tagged})`)
    const under = await list(UNDER_NAMES)
    expect(under.length === 0, `Tags grouping: dots under tag names: ${JSON.stringify(under)}`)
    // The topics inside a tag area are named, and no name lies on a dot.
    await click('All tags'); await wait(900)
    const groups = await list(`JSON.stringify((() => { const dots = [...document.querySelectorAll('.kg-base circle.kg-dot')].map((c) => c.getBoundingClientRect()); const labels = [...document.querySelectorAll('.kg-glabel')]; const hit = labels.filter((l) => { const r = l.getBoundingClientRect(); return dots.some((d) => d.left < r.right - 1 && d.right > r.left + 1 && d.top < r.bottom - 1 && d.bottom > r.top + 1) }).map((l) => l.textContent); return { names: labels.length, hit } })())`)
    expect(groups.names >= 3 && groups.hit.length === 0, `Tags grouping, topics inside the areas: ${groups.names} topic name(s) shown, on a dot: ${JSON.stringify(groups.hit)}`)
  }
  // 14 the title is changed in place: Esc keeps the window and the old title, Enter saves the new one
  await go('/graph-demo.html?pages=100', '.kg-dot')
  {
    await openDot()
    const key = async (k, code) => { for (const type of ['keyDown', 'keyUp']) await S('Input.dispatchKeyEvent', { type, key: k, code: k, windowsVirtualKeyCode: code }) }
    const titleNow = () => js(`document.querySelector('dialog[open] #kg-dlg-title')?.textContent.replace('Change the title', '').trim() ?? ''`)
    const before = await titleNow()
    await js(`document.querySelector('dialog[open] #kg-dlg-title .kg-inline').click()`); await wait(300)
    await S('Input.insertText', { text: 'Thrown away' })
    await key('Escape', 27); await wait(400)
    const afterEsc = await list(`JSON.stringify({ open: !!document.querySelector('dialog[open]'), field: !!document.querySelector('dialog[open] .kg-inline-edit') })`)
    expect(afterEsc.open && !afterEsc.field && (await titleNow()) === before, `title in place, Esc: window open ${afterEsc.open}, field still shown ${afterEsc.field}, title "${await titleNow()}" (was "${before}")`)
    await js(`document.querySelector('dialog[open] #kg-dlg-title .kg-inline').click()`); await wait(300)
    await S('Input.insertText', { text: 'Renamed in place' })
    await key('Enter', 13); await wait(900)
    expect((await titleNow()) === 'Renamed in place' && !(await js(`!!document.querySelector('dialog[open] .kg-inline-edit')`)), `title in place, Enter: the title reads "${await titleNow()}" ("Renamed in place" expected)`)
    await js(`document.querySelector('dialog[open] #kg-dlg-title .kg-inline').click()`); await wait(300)
    await js(`(() => { const f = document.querySelector('dialog[open] .kg-inline-edit__field'); f.select() })()`)
    await S('Input.insertText', { text: ' ' })
    await key('Enter', 13); await wait(500)
    const empty = await js(`document.querySelector('dialog[open] .kg-inline-edit__error')?.textContent ?? ''`)
    expect(/cannot be empty/.test(empty), `title in place, an empty title: the message reads "${empty}"`)
  }
  // 15 the page window shows the page's text; a failed read is an error with its own retry; a long page says so
  await go('/graph-demo.html?pages=100', '.kg-dot')
  {
    await openDot(); await wait(700)
    const body = await list(`JSON.stringify((() => { const b = document.querySelector('dialog[open] .kg-body'); if (!b) return { shown: false }; return { shown: true, headings: b.querySelectorAll('h3, h4, h5').length, lists: b.querySelectorAll('ul, ol').length, table: !!b.querySelector('table'), pageLinks: b.querySelectorAll('button.kg-body__page').length, web: [...b.querySelectorAll('a')].map((a) => a.getAttribute('href')), html: /<script|onerror=/i.test(b.innerHTML), width: Math.round(b.getBoundingClientRect().width), scroll: b.scrollWidth > b.clientWidth + 1 } })())`)
    expect(body.shown && body.headings >= 3 && body.lists >= 3 && body.table && body.pageLinks === 1 && body.web.every((h) => /^(https?:|mailto:|onenote:)/.test(h)) && !body.html && !body.scroll, `page text in the page window: ${JSON.stringify(body)}`)
    const before = await js(`document.querySelector('dialog[open] #kg-dlg-title').textContent`)
    await js(`document.querySelector('dialog[open] button.kg-body__page').click()`); await wait(900)
    const after = await js(`document.querySelector('dialog[open] #kg-dlg-title')?.textContent ?? ''`)
    expect(after && after !== before && (await js(`!!document.querySelector('dialog[open] .kg-body')`)), `page text: a link to another page showed "${after}" (was "${before}") with its own text`)
  }
  await go('/graph-demo.html?pages=100&body=fail', '.kg-dot')
  {
    await openDot(); await wait(700)
    const err = await list(`JSON.stringify((() => { const n = document.querySelector('dialog[open] .notice--error'); return { text: n?.textContent ?? '', role: n?.getAttribute('role') ?? '', retry: [...(n?.querySelectorAll('button') ?? [])].map((b) => b.textContent.trim()), links: document.querySelectorAll('dialog[open] .kg-row').length } })())`)
    expect(/could not be read/.test(err.text) && err.role === 'alert' && err.retry.length === 1 && err.links > 0, `page text, the read fails: ${JSON.stringify(err)} (an error box with one retry; the links stay)`)
  }
  await go('/graph-demo.html?pages=100&body=long', '.kg-dot')
  {
    await openDot(); await wait(700)
    const more = await js(`[...document.querySelectorAll('dialog[open] .kg-body .kg-note')].map((n) => n.textContent).join('')`)
    expect(/first part of a long page/.test(more), `page text, a long page: the note reads "${more}"`)
  }
  // 11 a read-only page says why and shows Edit disabled, not missing
  await go('/graph-demo.html?pages=100&readOnly=1', '.kg-dot')
  {
    await openDot()
    const ro = await list(`JSON.stringify((() => { const d = document.querySelector('dialog[open]'); const e = [...d.querySelectorAll('button')].find((b) => b.textContent.trim() === 'Edit'); return { edit: !!e, disabled: e?.getAttribute('aria-disabled') === 'true', why: d.querySelector('.kg-dlg__why')?.textContent || '', canTag: !!d.querySelector('.kg-tags__input') } })())`)
    expect(ro.edit && ro.disabled && ro.why.length > 20 && !ro.canTag, `read-only page window: Edit shown ${ro.edit}, disabled ${ro.disabled}, reason "${ro.why}", tag field shown ${ro.canTag}`)
  }

  // 12 the side bar says why this window cannot write; Settings lists the vault's tags
  vaultStatus = { name: 'Work wiki', vaultId: 'v1', mode: 'readonly', reason: 'other-pc', since: new Date(Date.now() - 3600000).toISOString(), detail: '' }
  waiting = false; await go('/#/', '.recent__row')
  {
    const note = await js(`[...document.querySelectorAll('.ro-banner')].map((n) => n.textContent).join(' | ')`)
    const elsewhere = await js(`[...document.querySelectorAll('.rail__note, .kg-readonly')].filter((n) => /read only|another PC/i.test(n.textContent)).length`)
    expect(/another PC/.test(note) && /Close it there/.test(note) && /Check again/.test(note) && !note.includes(' | ') && elsewhere === 0, `vault held on another PC: the one banner reads "${note}"; other places that say it: ${elsewhere}`)
    vaultStatus = null
    await click('Settings'); await wait(900)
    const tags = await js(`document.querySelectorAll('dialog[open] .st__tag').length`)
    const wanted = new Set(graph.pages.flatMap((p) => p.tags || [])).size
    expect(wanted > 0 && tags === wanted, `Settings, Tags: ${tags} tag row(s) shown, the vault's pages carry ${wanted} different tag(s)`)
  }

  // 1 one primary button per view
  const onePrimary = async (view) => { const p = await list(PRIMARIES); expect(p.length <= 1, `${view}: ${p.length} primary buttons (${p.join(', ')})`) }
  await go('/graph-demo.html?pages=100', '.kg-dot'); await openDot(); await onePrimary('page window')
  await click('Edit', `document.querySelector('dialog[open]')`); await wait(400); await onePrimary('page window, Edit form')
  waiting = false; await go('/#/', '.recent__row'); await onePrimary('home')
  waiting = true; await go('/#/', '.act__row'); await onePrimary('home with waiting items')
  // After a send: the result's own buttons must not be a second primary beside Send.
  const sendLink = async () => {
    await js(`document.querySelector('#composer-text').focus()`)
    await S('Input.insertText', { text: 'https://contoso.example/sites/platform/plan.docx' })
    await wait(700)
    await js(`document.querySelector('.composer__send').click()`)
    await wait(900)
  }
  waiting = false; submitAnswer = added; await go('/#/', '.recent__row'); await sendLink()
  expect(await js(`!!document.querySelector('.add-result')`), 'home after an Add: no Add result on screen (the check did not reach the state)')
  await onePrimary('home after an Add')
  waiting = true; submitAnswer = { ...added, status: 'waiting', message: 'Copilot is still reading the link.', inboxId: 'i1', page: null, chips: [], links: [], undo: null, backlinks: 0 }
  await go('/#/', '.act__row'); await sendLink(); await onePrimary('home with an Add that waits')
  submitAnswer = added
  await go('/#/history', '.act__row'); await onePrimary('History')

  // 6 a section row opens the List on that section, and the List holds pages
  waiting = false; await go('/#/', '.recent__row')
  for (const name of ['Notes', 'Web links']) {
    const clicked = await js(`(() => { const b = [...document.querySelectorAll('button.tree__row')].find((e) => e.querySelector('.tree__name')?.textContent === ${JSON.stringify(name)}); if (b) b.click(); return !!b })()`)
    await wait(1200)
    const rows = await js(`document.querySelectorAll('.kg-tbl__table tbody tr:not(.kg-tbl__group):not(.kg-tbl__more)').length`)
    const wanted = graph.pages.filter((p) => p.section === name && !p.archived).length
    expect(clicked && rows > 0 && rows <= wanted, `section row "${name}": clicked ${clicked}, the List shows ${rows} page(s), the graph holds ${wanted} in that section`)
    await go('/#/', '.recent__row')
  }
  await go('/#/graph', '.kg-dot'); await onePrimary('knowledge graph')

  // 2 the knowledge graph never makes the page scroll
  for (const [w, h] of [[1440, 900], [1024, 768]]) {
    await size(w, h); await go('/#/graph', '.kg-dot')
    const [doc, inner] = await list(`JSON.stringify([document.documentElement.scrollHeight, innerHeight])`)
    expect(doc <= inner, `knowledge graph at ${w}x${h}: the page is ${doc}px high in a ${inner}px window`)
  }

  // 3 the Add box starts on the first screen in a narrow window
  waiting = false
  for (const [w, h, touch] of [[720, 900, false], [390, 844, true]]) {
    await size(w, h, touch); await go('/#/', '.recent__row')
    const top = await js(`Math.round(document.querySelector('.composer').getBoundingClientRect().top)`)
    expect(top < h * 0.6, `home at ${w}px: the Add box starts at ${top}px of a ${h}px window`)
  }

  // 4 touch: every control at least 44 px high
  await size(390, 844, true)
  const touch = async (view) => { const s = await list(SMALL); expect(s.length === 0, `${view} on touch: under 44px: ${s.join(', ')}`) }
  waiting = true; await go('/#/', '.act__row'); await touch('home')
  await go('/#/history', '.act__row'); await touch('History')
  await go('/#/graph', '.kg-dot'); await touch('knowledge graph')
  await click('List'); await wait(400); await touch('List')
  await go('/graph-demo.html?pages=100', '.kg-dot'); await openDot(); await touch('page window')

  if (checks < 36) problems.push(`only ${checks} checks ran: the script did not reach every view`)
  if (problems.length) { console.error('Design rules broken:\n' + problems.join('\n')); process.exitCode = 1 }
  else console.log(`OK: ${checks} rendered design checks (one primary per view, no page scroll on the graph, Add box on the first screen, 44px touch targets, no dot under a topic name, section rows open their pages).`)
}
main().catch((e) => { console.error(e); process.exitCode = 1 }).finally(async () => {
  try { ws?.close() } catch {}
  edge.kill()
  await wait(800)
  try { rmSync(profile, { recursive: true, force: true }) } catch {}
})
