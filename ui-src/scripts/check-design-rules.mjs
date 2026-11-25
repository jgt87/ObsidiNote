// Rendered design checks that a reading of the CSS cannot hold (design review 2026-11-14: every one
// of these rules was already written down, and each was broken somewhere without a check).
// A rule DESIGN.md names ("Named Rules") is named here as there, and its failures start with that
// name in brackets. DESIGN.md's One Purple, Results First and One Look Per Choice are not checked here.
//   1 One Primary Per View: one primary button per view (home, home with waiting items, History, graph, page window, Edit)
//   2 the knowledge graph never makes the page scroll (1440x900 and 1024x768)
//   3 in a narrow window (720 and 390 px) the Add box starts on the first screen
//   4 Touch 44: on a touch screen every control is at least 44 px high (390 px, coarse pointer)
//   5 Weight Is Relevance, Every Dot Is Content: no dot of the map lies under a topic name (100 pages, the Sources view, 600 pages)
//   6 a section row of the side bar opens a List that holds pages
//   7 "Labels: hubs only" leaves the topic names and names a page only while it is pointed at
//  10 tags: added in the page window, its chip opens the Tags grouping with that tag alone, added to two ticked rows of the List
//  15 the page window shows the page's text (headings, lists, a table, a link to another page that opens it; only http(s)/mailto/onenote addresses; a long page says so);
//     Errors Read As Errors: a failed read is an error box with one retry
//  14 the page window's title is changed in place (Esc keeps the old one and the window, Enter saves, empty is refused)
//  13 the Tags grouping shows one area per tag with only tagged pages; a chip removes a tag's area;
//     Weight Is Relevance, Every Dot Is Content: no dot under a tag name, the topics inside are named on no dot
//  12 one banner names the reason the window is read only (not the side bar, no badge); Settings lists the vault's tags
//  11 a read-only page window says why and shows Edit disabled
//   9 the map's search shows its clear button whenever it holds text, without hover, and it clears
//   8 during a long zoom-in with the wheel the map is drawn again before it is stretched 1.35 times
//  20 the Journal: entries as rows, a topic search shows everything about it, Decisions with their sources, a row opens the page window;
//     One Primary Per View; Touch 44: 44 px on touch
// Views and states visited: home (idle, with waiting items, after an Add, with an Add that waits),
// History, Journal (no search, a topic, Decisions), knowledge graph (map, List), page window, its Edit form.
//  17 every text field has its own edge or fill of at least 3:1 against what is behind it (home, graph, Edit; light and dark)
//  18 the map's zoom toolbar and legend never overlap, in the app beside the side bar (1920, 1440, 1280, 1024)
//  19 during a search, a page that is not a result still shows its card on hover and opens on click;
//     moving off every dot puts the focus back on the search's result; once cleared, nothing stays focused
//  16 a citation [n] opens the cited page's window (a link page: its address); the box's controls sit in one row
// NOT covered, so the rules above are not proven there: the Ask answer's other states and its error, a failed Add,
// the Settings, New vault and Set up dialogs, the quick switcher, the Filter panel, a link Update
// (old/new), the replace confirmation, a read-only vault, dark theme.
// Drives the app in headless Edge over CDP with the API answered here from invented data, and the
// graph demo. Usage (ui-src): npx vite --port 5193 --strictPort   (separately), then
//   node scripts/check-design-rules.mjs [http://localhost:5193] [cdp port 9559]
// Exit 1 names the view and the rule. Writes nothing.
import { startEdge, stopEdge } from './headlessEdge.mjs'

const BASE = process.argv[2] || 'http://localhost:5193'
const PORT = Number(process.argv[3] || 9559)
const browser = startEdge(PORT, 'obsn-design-')
const wait = (ms) => new Promise((r) => setTimeout(r, ms))

// ---------- invented data for the app's API ----------
const VAULT = '{11111111-1111-1111-1111-111111111111}{1}{B0}'
const ago = (min) => new Date(Date.now() - min * 60000).toISOString()
const waitingItem = (n) => ({ inboxId: `i${n}`, title: `https://fernbrook.example/sites/platform/plan-${n}.docx`, state: 'waiting', kind: 'link', requestKind: 'add', updated: ago(14 * n), since: ago(14 * n), reason: '', filedAs: '', filedTitle: '', filedType: '', canCheck: true, canRemove: true, canUndo: false })
const addedItem = { inboxId: 'i9', title: 'Notes from the steering group', state: 'added', kind: 'text', requestKind: 'add', updated: ago(45), since: '', reason: '', filedAs: 'p12', filedTitle: 'Steering group', filedType: 'meeting', canCheck: false, canRemove: false, canUndo: true }
const notebook = { id: VAULT, name: 'Work wiki', vault: true, active: true, location: 'OneDrive', vaultId: 'v1', kind: 'notebook', notebookId: VAULT }
const section = (name, pages) => ({ name, kind: 'section', pages, children: [] })
let graph = null
let waiting = false
let vaultStatus = null
const added = { intent: 'add', status: 'added', kind: 'link', message: 'Added.', inboxId: '', ref: 'r1a2b3c4d', text: 'https://fernbrook.example/sites/platform/plan.docx',
  page: { id: 'p900', title: 'Network segmentation plan', type: 'link-internal', bucket: 'Internal links', section: 'Internal links', link: 'onenote:x', url: 'https://fernbrook.example/sites/platform/plan.docx', topicPath: 'Security/Networking', alsoUnder: [], oneNotePath: ['Work wiki', 'Internal links', 'Network segmentation plan'], unfiled: false },
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
// Controls under 44 px on a touch screen. Only a text link inside a sentence is exempt (WCAG 2.5.8
// inline); a control of its own is not, whatever its look (audit 2026-11-19: the side bar's Show and
// the Recently changed titles were exempted as links and were 17 and 19 px).
const SMALL = `JSON.stringify([...document.querySelectorAll('button, a.btn, select, input:not([type=checkbox]):not([type=radio]):not([type=file]), [role=tab]')].filter((e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && !e.closest('svg') && !e.matches('.kg-linkbtn, .kg-rowbtn, .ask-src__page') && r.height < 43.5 }).map((e) => (e.textContent.trim() || e.getAttribute('aria-label') || e.tagName).slice(0, 24) + '=' + Math.round(e.getBoundingClientRect().height)))`
const FIELD_EDGES = `JSON.stringify((() => {
  // At rest: a focused field shows its focus look (the home box has autofocus and passed on it).
  if (document.activeElement && document.activeElement !== document.body) document.activeElement.blur()
  const clear = (c) => !c || c === 'transparent' || /,\\s*0\\)$|\\/\\s*0\\)$/.test(c)
  const cv = document.createElement('canvas'); cv.width = cv.height = 1; const cx = cv.getContext('2d', { willReadFrequently: true })
  const paint = (layers) => { cx.globalCompositeOperation = 'copy'; cx.fillStyle = '#fff'; cx.fillRect(0, 0, 1, 1); cx.globalCompositeOperation = 'source-over'; for (const c of layers) { cx.fillStyle = '#000'; cx.fillStyle = c; cx.fillRect(0, 0, 1, 1) } const d = cx.getImageData(0, 0, 1, 1).data; return [d[0], d[1], d[2]] }
  const lum = (rgb) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4 }; return 0.2126 * f(rgb[0]) + 0.7152 * f(rgb[1]) + 0.0722 * f(rgb[2]) }
  const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05) }
  const behind = (e) => { const out = []; for (let p = e.parentElement; p; p = p.parentElement) { const c = getComputedStyle(p).backgroundColor; if (!clear(c)) out.unshift(c) } return out }
  const bad = []
  for (const e of document.querySelectorAll('input:not([type=checkbox]):not([type=radio]):not([type=range]):not([type=hidden]):not([type=file]), select, textarea')) {
    const r = e.getBoundingClientRect(); if (r.width < 4 || r.height < 4 || getComputedStyle(e).visibility === 'hidden') continue
    const s = getComputedStyle(e); const under = behind(e); const base = paint(under)
    const edge = parseFloat(s.borderBottomWidth) >= 1 && !clear(s.borderBottomColor) ? ratio(paint([...under, s.borderBottomColor]), base) : 0
    const fill = clear(s.backgroundColor) ? 0 : ratio(paint([...under, s.backgroundColor]), base)
    if (Math.max(edge, fill) < 3) bad.push((e.id || e.className || e.tagName) + ' edge ' + edge.toFixed(2) + ':1, fill ' + fill.toFixed(2) + ':1')
  }
  return bad })())`
// Text fields whose edge or fill is under 3:1 against what is behind them (rules/ui.md, 1.4.11):
// a field without its own edge does not read as a place to type (D-044).
const UNDER_NAMES = `JSON.stringify((() => { const hit = (a, b) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom
  const dots = [...document.querySelectorAll('.kg-base circle.kg-dot')].map((d) => d.getBoundingClientRect())
  // The name and the page count beside it, as one box.
  const box = (l) => { const rs = [...l.querySelectorAll('b, .kg-alabel__count')].map((e) => e.getBoundingClientRect()); return { left: Math.min(...rs.map((r) => r.left)), right: Math.max(...rs.map((r) => r.right)), top: Math.min(...rs.map((r) => r.top)), bottom: Math.max(...rs.map((r) => r.bottom)) } }
  return [...document.querySelectorAll('.kg-alabel')].map((l) => ({ name: l.textContent, n: dots.filter((d) => hit(box(l), d)).length })).filter((x) => x.n > 0) })())`

// ---------- the browser session ----------

/** The CDP address of the headless Edge, once it answers (up to 12 s). */
async function debuggerUrl() {
  for (let k = 0; k < 60; k++) {
    try {
      return (await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json()).webSocketDebuggerUrl
    } catch {
      await wait(200) // not up yet
    }
  }
  throw new Error(`Edge did not answer on CDP port ${PORT}`)
}

/** Answers of the commands sent, and the app's API calls answered from the invented data above. */
function onMessage(m) {
  const d = JSON.parse(m.data)
  if (d.id && pending.has(d.id)) {
    const p = pending.get(d.id)
    pending.delete(d.id)
    d.error ? p.reject(new Error(JSON.stringify(d.error))) : p.resolve(d.result)
  } else if (d.method === 'Fetch.requestPaused') {
    const { requestId, request } = d.params
    const body = answer(new URL(request.url).pathname)
    // A request the page dropped meanwhile (it navigated away) cannot be answered: nothing to do.
    send('Fetch.fulfillRequest', { requestId, responseCode: body ? 200 : 404, responseHeaders: [{ name: 'Content-Type', value: 'application/json' }], body: Buffer.from(JSON.stringify(body ?? { error: 'not stubbed' })).toString('base64') }, d.sessionId).catch(() => {})
  }
}

/** A page in the headless Edge with its API answered here, and the helpers every rule uses. */
async function connect() {
  ws = new WebSocket(await debuggerUrl())
  await new Promise((r) => ws.addEventListener('open', r))
  const { targetId } = await new Promise((resolve) => {
    ws.addEventListener('message', function first(m) { const d = JSON.parse(m.data); if (d.id === 1) { ws.removeEventListener('message', first); resolve(d.result) } })
    ws.send(JSON.stringify({ id: ++id, method: 'Target.createTarget', params: { url: 'about:blank' } }))
  })
  ws.addEventListener('message', onMessage)
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
    // A page still loading has no context to evaluate in yet: that counts as "not there yet".
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
  const t = { S, js, list, size, go, click, openDot, problems: [], checks: 0 }
  t.expect = (ok, text) => { t.checks++; if (!ok) t.problems.push(text) }
  t.onePrimary = async (view) => { const p = await list(PRIMARIES); t.expect(p.length <= 1, `[One Primary Per View] ${view}: ${p.length} primary buttons (${p.join(', ')})`) }
  return t
}

// ---------- the rules, in the order they run (later ones rely on the stub state earlier ones left) ----------

/** The stub API's graph: the demo map's own model, as vault v1 (the notebook stub's vaultId). */
async function loadStubGraph({ js, size, go }) {
  await size(1440, 900)
  await go('/graph-demo.html?pages=100', '.kg-dot')
  graph = JSON.parse(await js(`import('/src/graph/synthetic.ts').then((m) => JSON.stringify(m.syntheticGraph({ pages: 100, topics: 6, seed: 7 })))`))
  graph.source = { ...graph.source, id: 'v1', kind: 'vault', readOnly: false }
}

// 5 Weight Is Relevance, Every Dot Is Content: no dot under a topic name (the demo map and the Sources view)
async function noDotUnderNames({ list, go, click, expect }) {
  let under = await list(UNDER_NAMES)
  expect(under.length === 0, `[Weight Is Relevance, Every Dot Is Content] map: dots under topic names: ${JSON.stringify(under)}`)
  await click('Sources'); await wait(700)
  under = await list(UNDER_NAMES)
  expect(under.length === 0, `[Weight Is Relevance, Every Dot Is Content] map, Sources view: dots under names: ${JSON.stringify(under)}`)

  await go('/graph-demo.html?pages=600&topics=25', '.kg-dot'); await wait(600)
  under = await list(UNDER_NAMES)
  expect(under.length === 0, `[Weight Is Relevance, Every Dot Is Content] map of 600 pages (fitted zoomed out): dots under topic names: ${JSON.stringify(under)}`)
}

// 7 "Labels: hubs only": the topic names stay, no page is named at rest, the page pointed at is.
async function hubsOnlyLabels({ S, js, list, go, click, expect }) {
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
  const pos = await list(`JSON.stringify((() => { const r = document.querySelectorAll('.kg-base circle.kg-dot--hub')[0].getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2] })())`)
  await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: pos[0], y: pos[1], button: 'none' })
  await wait(400)
  expect((await pageNames()) === 1, `hubs only, pointing at a page: ${await pageNames()} page name(s) (1 expected: its own)`)
  await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 5, y: 5, button: 'none' })
}

// 8 a long zoom-in never shows the map as a far-stretched picture of its last drawing
async function zoomNeverStretched({ S, js, list, go, expect }) {
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
}

// 9 the map's search shows its clear button whenever it holds text (no hover needed), and it clears
async function searchClearButton({ S, js, go, expect }) {
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
}

// 10 tags: set in the page window, shown as one joined group on the map, set on several rows in the List
async function tagsSetEverywhere({ S, js, list, go, click, openDot, expect }) {
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
}

// 13 the Tags grouping: one area per tag, only tagged pages, and a chip takes a tag's area away
async function tagsGrouping({ js, list, go, click, expect }) {
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
    expect(under.length === 0, `[Weight Is Relevance, Every Dot Is Content] Tags grouping: dots under tag names: ${JSON.stringify(under)}`)
    // The topics inside a tag area are named, and no name lies on a dot.
    await click('All tags'); await wait(900)
    const groups = await list(`JSON.stringify((() => { const dots = [...document.querySelectorAll('.kg-base circle.kg-dot')].map((c) => c.getBoundingClientRect()); const labels = [...document.querySelectorAll('.kg-glabel')]; const hit = labels.filter((l) => { const r = l.getBoundingClientRect(); return dots.some((d) => d.left < r.right - 1 && d.right > r.left + 1 && d.top < r.bottom - 1 && d.bottom > r.top + 1) }).map((l) => l.textContent); return { names: labels.length, hit } })())`)
    expect(groups.names >= 3 && groups.hit.length === 0, `[Weight Is Relevance, Every Dot Is Content] Tags grouping, topics inside the areas: ${groups.names} topic name(s) shown, on a dot: ${JSON.stringify(groups.hit)}`)
  }
}

// 14 the title is changed in place: Esc keeps the window and the old title, Enter saves the new one
async function titleInPlace({ S, js, list, go, openDot, expect }) {
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
}

// 15 the page window shows the page's text; a failed read is an error with its own retry; a long page says so
const PAGE_BODY = `JSON.stringify((() => { const b = document.querySelector('dialog[open] .kg-body'); if (!b) return { shown: false }; return { shown: true, headings: b.querySelectorAll('h3, h4, h5').length, lists: b.querySelectorAll('ul, ol').length, table: !!b.querySelector('table'), pageLinks: b.querySelectorAll('button.kg-body__page').length, web: [...b.querySelectorAll('a')].map((a) => a.getAttribute('href')), html: /<script|onerror=/i.test(b.innerHTML), width: Math.round(b.getBoundingClientRect().width), scroll: b.scrollWidth > b.clientWidth + 1 } })())`

/** The demo page's text as it should show: its headings, lists and table, one link to another page,
 *  only http(s)/mailto/onenote addresses, no live HTML, and no sideways scroll. */
function bodyShownRight(body) {
  if (!body.shown || !body.table || body.html || body.scroll) return false
  const addressesSafe = body.web.every((h) => /^(https?:|mailto:|onenote:)/.test(h))
  return body.headings >= 3 && body.lists >= 3 && body.pageLinks === 1 && addressesSafe
}

async function pageTextShown({ js, list, go, openDot, expect }) {
  await go('/graph-demo.html?pages=100', '.kg-dot')
  await openDot(); await wait(700)
  const body = await list(PAGE_BODY)
  expect(bodyShownRight(body), `page text in the page window: ${JSON.stringify(body)}`)
  const before = await js(`document.querySelector('dialog[open] #kg-dlg-title').textContent`)
  await js(`document.querySelector('dialog[open] button.kg-body__page').click()`); await wait(900)
  const after = await js(`document.querySelector('dialog[open] #kg-dlg-title')?.textContent ?? ''`)
  const ownText = await js(`!!document.querySelector('dialog[open] .kg-body')`)
  expect(after && after !== before && ownText, `page text: a link to another page showed "${after}" (was "${before}") with its own text`)
}

/** A failed read: an error box (role alert) that says so, with one retry; the page's links stay. */
const readFailedRight = (err) => /could not be read/.test(err.text) && err.role === 'alert' && err.retry.length === 1 && err.links > 0

async function pageTextFails({ list, go, openDot, expect }) {
  await go('/graph-demo.html?pages=100&body=fail', '.kg-dot')
  await openDot(); await wait(700)
  const err = await list(`JSON.stringify((() => { const n = document.querySelector('dialog[open] .notice--error'); return { text: n?.textContent ?? '', role: n?.getAttribute('role') ?? '', retry: [...(n?.querySelectorAll('button') ?? [])].map((b) => b.textContent.trim()), links: document.querySelectorAll('dialog[open] .kg-row').length } })())`)
  expect(readFailedRight(err), `[Errors Read As Errors] page text, the read fails: ${JSON.stringify(err)} (an error box with one retry; the links stay)`)
}

async function pageTextLong({ js, go, openDot, expect }) {
  await go('/graph-demo.html?pages=100&body=long', '.kg-dot')
  await openDot(); await wait(700)
  const more = await js(`[...document.querySelectorAll('dialog[open] .kg-body .kg-note')].map((n) => n.textContent).join('')`)
  expect(/first part of a long page/.test(more), `page text, a long page: the note reads "${more}"`)
}

// 11 a read-only page says why and shows Edit disabled, not missing
async function readOnlyPage({ list, go, openDot, expect }) {
  await go('/graph-demo.html?pages=100&readOnly=1', '.kg-dot')
  await openDot()
  const ro = await list(`JSON.stringify((() => { const d = document.querySelector('dialog[open]'); const e = [...d.querySelectorAll('button')].find((b) => b.textContent.trim() === 'Edit'); return { edit: !!e, disabled: e?.getAttribute('aria-disabled') === 'true', why: d.querySelector('.kg-dlg__why')?.textContent || '', canTag: !!d.querySelector('.kg-tags__input') } })())`)
  expect(ro.edit && ro.disabled && ro.why.length > 20 && !ro.canTag, `read-only page window: Edit shown ${ro.edit}, disabled ${ro.disabled}, reason "${ro.why}", tag field shown ${ro.canTag}`)
}

// 12 the side bar says why this window cannot write; Settings lists the vault's tags
async function readOnlyBanner({ js, go, click, expect }) {
  vaultStatus ={ name: 'Work wiki', vaultId: 'v1', mode: 'readonly', reason: 'other-pc', since: new Date(Date.now() - 3600000).toISOString(), detail: '' }
  waiting = false; await go('/#/', '.recent__row')
  {
    const note = await js(`[...document.querySelectorAll('.ro-banner')].map((n) => n.textContent).join(' | ')`)
    const elsewhere = await js(`[...document.querySelectorAll('.rail__note, .kg-readonly')].filter((n) => /read only|another PC/i.test(n.textContent)).length`)
    expect(/another PC seems to be writing/.test(note) && /\bmay\b/.test(note) && /If it is closed there/.test(note) && /Check again/.test(note) && !note.includes(' | ') && elsewhere === 0, `vault held on another PC: the one banner reads "${note}"; other places that say it: ${elsewhere}`)
    vaultStatus = null
    await click('Settings'); await wait(900)
    const tags = await js(`document.querySelectorAll('dialog[open] .st__tag').length`)
    const wanted = new Set(graph.pages.flatMap((p) => p.tags || [])).size
    expect(wanted > 0 && tags === wanted, `Settings, Tags: ${tags} tag row(s) shown, the vault's pages carry ${wanted} different tag(s)`)
  }
}

// 17 every text field has its own edge (or fill) of at least 3:1 against what is behind it, light and dark
async function fieldEdges({ S, js, list, go, openDot, expect }) {
  for (const dark of [false, true]) {
    await S('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: dark ? 'dark' : 'light' }] })
    const where = dark ? ' (dark)' : ''
    waiting = false; await go('/#/', '.recent__row')
    let bad = await list(FIELD_EDGES)
    expect(bad.length === 0, `home${where}: text fields without a visible edge: ${bad.join('; ')}`)
    await go('/#/graph', '.kg-dot')
    bad = await list(FIELD_EDGES)
    expect(bad.length === 0, `knowledge graph${where}: text fields without a visible edge: ${bad.join('; ')}`)
    await openDot()
    await js(`[...document.querySelectorAll('dialog[open] button')].find((b) => b.textContent.trim() === 'Edit')?.click()`); await wait(500)
    bad = await list(FIELD_EDGES)
    expect(bad.length === 0, `page window, Edit${where}: text fields without a visible edge: ${bad.join('; ')}`)
  }
  await S('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'light' }] })
}

// 16 a citation [n] in an Ask answer opens that page's window; a link page's citation is its address.
//    And the box: every control (mode switch, paperclip, Send) in one row under the text.

/** An answered Ask from the stub graph: sentence 1 cites a page of the vault (no address), sentence 2
 *  a link page (https://example.com/guide). Returns the answer and the vault page cited. */
function askAnswerFixture(pages) {
  const target = pages.find((p) => !p.url && p.id) ?? pages[0]
  const linkPage = pages.find((p) => p.id !== target.id) ?? pages[1]
  const source = (n, p, url = '') => ({ n, id: p.id, key: p.id, title: p.title, path: 'Security', link: 'onenote:#example', url, updated: '', age: 'today', type: 'note', archived: false, sourceId: 'v1', sourceName: 'Work wiki', readOnly: false, stale: false, summarizedAge: '' })
  const answer = {
    intent: 'ask', ok: true, status: 'answered', conversationId: 'c1', turn: 1, question: 'What did we decide?', writes: 0, note: '', message: '', path: null,
    answer: { confidence: 'high', paragraphs: [{ sentences: [{ text: 'The first sentence.', cites: [1], unsupported: false }, { text: 'The second one.', cites: [2], unsupported: false }] }] },
    sources: [source(1, target), source(2, linkPage, 'https://example.com/guide')], unused: [], staleLinks: [], invalidCitations: [], notFound: null,
  }
  return { answer, target }
}

/** Polls expr up to `tries` times, 100 ms apart, until it gives a truthy value; returns the last value. */
async function waitForValue(js, expr, tries) {
  let v = await js(expr)
  for (let k = 1; k < tries && !v; k++) { await wait(100); v = await js(expr) }
  return v
}

/** The box's controls (mode switch, paperclip "Add a file", Send) on one line: centres within 2 px. */
const composerRowRight = (row) => row.n === 3 && row.spread <= 2 && row.clip === 'Add a file'

/** Ask's citations: a button for the vault page, the address for the link page. */
const citationsRight = (cites) => cites.length === 2 && cites[0].tag === 'BUTTON' && cites[1].href === 'https://example.com/guide'

// The answer cited (set by composerRow, used by askCitations; they run one after the other).
let askTarget = null

async function composerRow({ list, go, expect }) {
  const { answer, target } = askAnswerFixture(graph.pages)
  submitAnswer = answer
  askTarget = target
  waiting = false; await go('/#/', '.recent__row')
  const row = await list(`JSON.stringify((() => { const r = document.querySelector('.composer__bottom'); const tops = [...r.querySelectorAll('.seg, .composer__file-btn, .composer__send')].map((e) => Math.round(e.getBoundingClientRect().top + e.getBoundingClientRect().height / 2)); return { n: tops.length, spread: Math.max(...tops) - Math.min(...tops), clip: r.querySelector('.composer__file-btn')?.getAttribute('aria-label') } })())`)
  expect(composerRowRight(row), `the box's controls: ${JSON.stringify(row)} (mode switch, paperclip "Add a file" and Send on one line)`)
}

async function askCitations({ S, js, list, expect }) {
  await js(`document.querySelector('#composer-text').focus()`)
  await S('Input.insertText', { text: 'What did we decide?' })
  await wait(600)
  await js(`document.querySelector('.composer__send').click()`)
  await waitForValue(js, `!!document.querySelector('[aria-label="Answer"]')`, 51)
  const cites = await list(`JSON.stringify([...document.querySelectorAll('.ask-cite')].map((c) => ({ tag: c.tagName, href: c.getAttribute('href') })))`)
  expect(citationsRight(cites), `Ask citations: ${JSON.stringify(cites)} (a button for the vault page, the address for the link page)`)
  await js(`document.querySelector('button.ask-cite').click()`)
  const title = await waitForValue(js, `document.querySelector('dialog[open] #kg-dlg-title')?.textContent ?? ''`, 60)
  expect(title.includes(askTarget.title), `Ask citation [1]: the page window shows "${title}" ("${askTarget.title}" expected)`)
  submitAnswer = added
}

// 1 One Primary Per View: one primary button per view (the knowledge graph's own is checked after rule 6)
async function onePrimaryPerView({ S, js, go, click, openDot, expect, onePrimary }) {
  await go('/graph-demo.html?pages=100', '.kg-dot'); await openDot(); await onePrimary('page window')
  await click('Edit', `document.querySelector('dialog[open]')`); await wait(400); await onePrimary('page window, Edit form')
  waiting = false; await go('/#/', '.recent__row'); await onePrimary('home')
  waiting = true; await go('/#/', '.act__row'); await onePrimary('home with waiting items')
  // After a send: the result's own buttons must not be a second primary beside Send.
  const sendLink = async () => {
    await js(`document.querySelector('#composer-text').focus()`)
    await S('Input.insertText', { text: 'https://fernbrook.example/sites/platform/plan.docx' })
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
}

// 6 a section row opens the List on that section, and the List holds pages
async function sectionRows({ js, go, expect }) {
  waiting = false; await go('/#/', '.recent__row')
  for (const name of ['Notes', 'Web links']) {
    const clicked = await js(`(() => { const b = [...document.querySelectorAll('button.tree__row')].find((e) => e.querySelector('.tree__name')?.textContent === ${JSON.stringify(name)}); if (b) b.click(); return !!b })()`)
    await wait(1200)
    const rows = await js(`document.querySelectorAll('.kg-tbl__table tbody tr:not(.kg-tbl__group):not(.kg-tbl__more)').length`)
    const wanted = graph.pages.filter((p) => p.section === name && !p.archived).length
    expect(clicked && rows > 0 && rows <= wanted, `section row "${name}": clicked ${clicked}, the List shows ${rows} page(s), the graph holds ${wanted} in that section`)
    await go('/#/', '.recent__row')
  }
}

// 20 the Journal (2026-11-17): the day page's entries are rows; a topic picked from the search shows
// everything about it (other pages too); Decisions lists the decision page with the page it came from;
// a row opens the page window; at most one primary button; 44 px on touch.
async function journalView({ js, list, size, go, click, expect, onePrimary }) {
  const t0 = graph.topics[0]
  const d = new Date(); const pad = (n) => String(n).padStart(2, '0')
  const day = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  if (!graph.pages.some((p) => p.id === 'pj1')) {
    graph.pages.push(
      { id: 'pj1', title: day, kind: 'log', bucket: 'Journal', section: `Journal/${d.getFullYear()}`, topicIds: [t0.id], tags: [], aliases: [], summary: '2 entries', created: new Date().toISOString(),
        entries: [{ ref: 'ra1', at: `${day}T09:30`, title: 'Supplier call', summary: 'Called the supplier.', topicIds: [t0.id], links: [] }, { ref: 'ra2', at: `${day}T11:05`, title: 'Budget agreed', summary: 'Agreed the budget.', topicIds: [], links: [] }] },
      { id: 'pj2', title: 'Decision: supplier', kind: 'decision', bucket: 'Decisions', section: 'Decisions', topicIds: [t0.id], tags: [], aliases: [], summary: 'We chose the supplier.', created: new Date(Date.now() - 86400000).toISOString(), entries: [] },
    )
    graph.edges.push({ from: 'pj2', to: graph.pages.find((p) => p.topicIds?.includes(t0.id) && p.id !== 'pj1' && p.id !== 'pj2')?.id ?? graph.pages[0].id, strength: 2 })
  }
  await size(1440, 900); await go('/#/journal', '.jr__row')
  const rows = await js(`document.querySelectorAll('.jr__row').length`)
  expect(rows >= 2, `Journal: ${rows} rows without a search (expected the day page's 2 entries)`)
  await onePrimary('Journal')
  await js(`(() => { const i = document.querySelector('.jr__field'); const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set; set.call(i, ${JSON.stringify(t0.name.slice(0, 4))}); i.dispatchEvent(new Event('input', { bubbles: true })) })()`)
  await wait(300)
  const picked = await js(`(() => { const b = [...document.querySelectorAll('.jr__suggest button')].find((e) => e.textContent.includes(${JSON.stringify(t0.path)})); if (b) b.click(); return !!b })()`)
  await wait(300)
  const caption = await js(`document.querySelector('.jr__caption')?.textContent ?? ''`)
  const after = await js(`document.querySelectorAll('.jr__row').length`)
  expect(picked && caption.startsWith('Everything about topic') && after > 1, `Journal topic search: suggestion picked ${picked}, caption "${caption}", ${after} rows`)
  await click('Decisions'); await wait(300)
  const dec = await js(`[...document.querySelectorAll('.jr__row .act__title')].map((e) => e.textContent).join('|')`)
  const from = await js(`document.querySelector('.jr__from')?.textContent ?? ''`)
  expect(dec.includes('Decision: supplier') && from.startsWith('From: '), `Journal decisions: rows "${dec}", sources "${from}"`)
  await js(`document.querySelector('.jr__row')?.click()`); await wait(800)
  const opened = await js(`!!document.querySelector('dialog[open]')`)
  expect(opened, 'Journal: a row did not open the page window')
  await size(390, 844, true); await go('/#/journal', '.jr__row')
  const small = await list(SMALL)
  expect(small.length === 0, `[Touch 44] Journal on touch: under 44px: ${small.join(', ')}`)
  await size(1440, 900, false)
}

// 1 One Primary Per View (continued): the knowledge graph's one primary button
async function onePrimaryOnGraph({ go, onePrimary }) {
  await go('/#/graph', '.kg-dot'); await onePrimary('knowledge graph')
}

// 2 the knowledge graph never makes the page scroll
async function graphNoScroll({ list, size, go, expect }) {
  for (const [w, h] of [[1440, 900], [1024, 768]]) {
    await size(w, h); await go('/#/graph', '.kg-dot')
    const [doc, inner] = await list(`JSON.stringify([document.documentElement.scrollHeight, innerHeight])`)
    expect(doc <= inner, `knowledge graph at ${w}x${h}: the page is ${doc}px high in a ${inner}px window`)
  }
}

// 3 the Add box starts on the first screen in a narrow window
async function addBoxFirstScreen({ js, size, go, expect }) {
  waiting = false
  for (const [w, h, touch] of [[720, 900, false], [390, 844, true]]) {
    await size(w, h, touch); await go('/#/', '.recent__row')
    const top = await js(`Math.round(document.querySelector('.composer').getBoundingClientRect().top)`)
    expect(top < h * 0.6, `home at ${w}px: the Add box starts at ${top}px of a ${h}px window`)
  }
}

// 4 Touch 44: on touch every control at least 44 px high
async function touchTargets({ list, size, go, click, openDot, expect }) {
  await size(390, 844, true)
  const touch = async (view) => { const s = await list(SMALL); expect(s.length === 0, `[Touch 44] ${view} on touch: under 44px: ${s.join(', ')}`) }
  waiting = true; await go('/#/', '.act__row'); await touch('home')
  await go('/#/history', '.act__row'); await touch('History')
  await go('/#/graph', '.kg-dot'); await touch('knowledge graph')
  await click('List'); await wait(400); await touch('List')
  await go('/graph-demo.html?pages=100', '.kg-dot'); await openDot(); await touch('page window')
}

// 18 the map's toolbar and legend never overlap, beside the side bar too (2026-11-15: a longer
// legend covered the zoom buttons in the app at 1440, while the demo page without a side bar was fine)
async function toolbarLegendApart({ list, size, go, expect }) {
  for (const [w, h] of [[1920, 1080], [1440, 900], [1280, 800], [1024, 768]]) {
    await size(w, h, false)
    await go('/#/graph', '.kg-dot')
    const hit = await list(`JSON.stringify((() => { const t = document.querySelector('.kg-toolbar')?.getBoundingClientRect(); const l = document.querySelector('.kg-legend')?.getBoundingClientRect()
      if (!t || !l || l.width === 0) return null
      return { overlap: t.left < l.right && l.left < t.right && t.top < l.bottom && l.top < t.bottom, toolbar: [Math.round(t.left), Math.round(t.right)], legend: [Math.round(l.left), Math.round(l.right)] } })())`)
    expect(!hit || !hit.overlap, `map at ${w}px in the app: the legend ${JSON.stringify(hit?.legend)} lies over the zoom toolbar ${JSON.stringify(hit?.toolbar)}`)
  }
}

// 19 a search highlights its results and hides nothing: a page that is not a result still shows
// its card on hover and opens on click (D-042)
async function searchHidesNothing({ S, js, list, size, go, expect }) {
  await size(1440, 900, false)
  await go('/graph-demo.html?pages=100', '.kg-dot')
  await js(`document.querySelector('#kg-search').focus()`)
  await S('Input.insertText', { text: 'zero' }); await wait(600)
  {
    const target = await list(`JSON.stringify((() => { const hits = new Set([...document.querySelectorAll('.kg-focus circle.kg-dot')].map((c) => c.getAttribute('data-id')))
      const d = [...document.querySelectorAll('.kg-base circle.kg-dot')].find((c) => !hits.has(c.getAttribute('data-id')) && (() => { const r = c.getBoundingClientRect(); const e = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); return e === c })())
      if (!d || hits.size === 0) return null
      const r = d.getBoundingClientRect(); return { id: d.getAttribute('data-id'), x: r.x + r.width / 2, y: r.y + r.height / 2, hits: hits.size } })())`)
    expect(!!target, 'search: no dot outside the results could be pointed at, or the search found nothing')
    if (target) {
      const focused = `(document.querySelector('.kg-card') && document.querySelector('.kg-focus circle.kg-dot--on')?.getAttribute('data-id')) || ''`
      // A spot on the map with no dot under it, to move the pointer off every dot.
      const empty = await list(`JSON.stringify((() => { const s = document.querySelector('.kg-stage').getBoundingClientRect()
        for (let y = s.top + 12; y < s.bottom - 60; y += 9) for (let x = s.left + 12; x < s.right - 12; x += 9) { const e = document.elementFromPoint(x, y); if (e && e.closest('.kg-stage') && !e.closest('circle.kg-dot, .kg-card, .kg-toolbar, .kg-legend')) return [x, y] }
        return null })())`)
      const pick = await js(focused)
      await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: target.x - 40, y: target.y - 40 })
      await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: target.x, y: target.y }); await wait(400)
      // The focused dot must be the one pointed at: a card may already be open for the first result.
      const on = await js(focused)
      expect(on === target.id, `search "zero" (${target.hits} results): hovering ${target.id}, which is not a result, focuses "${on}" instead`)
      // Off every dot again: the focus goes back to the search's result until the search is cleared
      // (D-042).
      if (empty) {
        await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: empty[0], y: empty[1] }); await wait(400)
        const back = await js(focused)
        expect(!!pick && back === pick, `search "zero": after hovering ${target.id} and moving off every dot, the focus is on "${back}", not back on the search's result "${pick}"`)
        await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: target.x, y: target.y }); await wait(400)
      } else expect(false, 'search: no spot without a dot was found on the map to move the pointer to')
      for (const type of ['mousePressed', 'mouseReleased']) await S('Input.dispatchMouseEvent', { type, x: target.x, y: target.y, button: 'left', clickCount: 1 })
      await wait(500)
      const opened = await js(`document.querySelector('dialog[open] #kg-dlg-title') ? 'yes' : 'no'`)
      expect(opened === 'yes', `search "zero": clicking a page that is not a result does not open it`)
      // Cleared search: moving off the dots leaves nothing focused.
      await js(`document.querySelector('dialog[open]')?.close()`); await wait(300)
      await js(`document.querySelector('.kg-search__clear')?.click()`); await wait(300)
      if (empty) {
        await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: target.x, y: target.y }); await wait(300)
        await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x: empty[0], y: empty[1] }); await wait(400)
        const after = await js(focused)
        expect(after === '', `search cleared: moving off every dot still leaves "${after}" focused`)
      }
    }
  }
}

const RULES = [
  loadStubGraph, noDotUnderNames, hubsOnlyLabels, zoomNeverStretched, searchClearButton, tagsSetEverywhere, tagsGrouping,
  titleInPlace, pageTextShown, pageTextFails, pageTextLong, readOnlyPage, readOnlyBanner, fieldEdges, composerRow, askCitations,
  onePrimaryPerView, sectionRows, journalView,
  onePrimaryOnGraph, graphNoScroll, addBoxFirstScreen, touchTargets, toolbarLegendApart, searchHidesNothing,
]

async function main() {
  const t = await connect()
  for (const rule of RULES) await rule(t)
  const { checks, problems } = t
  if (checks < 45) problems.push(`only ${checks} checks ran: the script did not reach every view`)
  if (problems.length) { console.error('Design rules broken:\n' + problems.join('\n')); process.exitCode = 1 }
  else console.log(`OK: ${checks} rendered design checks (One Primary Per View, Touch 44, Weight Is Relevance, Every Dot Is Content, Errors Read As Errors; no page scroll on the graph, Add box on the first screen, section rows open their pages).`)
}
main().catch((e) => { console.error(e); process.exitCode = 1 }).finally(async () => {
  try { ws?.close() } catch {} // already closed: nothing to do
  await stopEdge(browser)
})
