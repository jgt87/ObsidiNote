// The README's screenshots, taken from the real interface with invented data (no OneNote, no
// Copilot, no content of anyone's). Run it again after a visible change:
//   (ui-src) npx vite --port 5194 --strictPort      (separately), then
//   node scripts/readme-shots.mjs [http://localhost:5194] [cdp port 9566]
// Writes docs/screenshots/*.png (1440x900, light theme). Drives headless Edge over CDP and answers
// the API here, like check-design-rules.mjs.
import { spawn } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const BASE = process.argv[2] || 'http://localhost:5194'
const PORT = Number(process.argv[3] || 9566)
const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'docs', 'screenshots')
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
const profile = mkdtempSync(join(tmpdir(), 'obsn-shots-'))
const edge = spawn(EDGE, ['--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`, '--no-first-run', '--window-size=1440,900', 'about:blank'], { stdio: 'ignore' })
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
const ago = (min) => new Date(Date.now() - min * 60000).toISOString()

// ---------- invented data ----------
const VAULT = '{11111111-1111-1111-1111-111111111111}{1}{B0}'
const notebook = { id: VAULT, name: 'Work wiki', vault: true, active: true, location: 'OneDrive', vaultId: 'v1', kind: 'notebook', notebookId: VAULT }
const section = (name, pages) => ({ name, kind: 'section', pages, children: [] })
// The demo graph names some pages "<topic> page <n>"; these read like a real wiki instead.
const MORE = {
  Security: ['Password policy', 'Device compliance', 'Conditional access', 'Privileged access', 'Phishing drill results', 'Security baseline 2026', 'Incident response steps', 'Key rotation', 'Audit log retention', 'Guest access rules', 'Threat model: portal', 'MFA rollout', 'Secrets in pipelines', 'Least privilege review', 'Endpoint protection', 'Data classification', 'Security champions', 'Pen test findings', 'Backup encryption', 'Access reviews Q3', 'Vendor risk checklist', 'Logging standard', 'SOC handover', 'Certificate inventory', 'Browser hardening', 'Admin workstations', 'Email filtering', 'USB policy'],
  Projects: ['Intranet refresh', 'Data platform pilot', 'Mobile app beta', 'Office move', 'Onboarding portal', 'Service desk tool', 'Analytics dashboard', 'Customer survey 2026', 'Migration wave 2', 'Print service retirement', 'Website relaunch', 'API gateway', 'Archive cleanup', 'Room booking', 'Partner onboarding', 'Kiosk devices', 'Chat assistant trial', 'Field app', 'Translation workflow', 'Budget tool'],
  Methods: ['Retrospective format', 'RACI template', 'Risk register', 'Weekly status', 'Pre-mortem', 'Definition of done', 'Meeting notes template', 'Post-incident review', 'Stakeholder map', 'Release checklist', 'OKR template', 'Interview guide', 'Workshop agenda', 'Estimation guide', 'Handover checklist'],
  People: ['Jamie (finance)', 'Taylor (legal)', 'Morgan (HR)', 'Casey (facilities)', 'Riley (support lead)', 'Quinn (architecture)', 'Avery (sales)'],
  'Reading notes': ['Accelerate', 'The phoenix project', 'Shape Up', 'Thinking in systems', 'Deep work', 'Range', 'Turn the ship around', 'Drive', 'The manager’s path', 'Atomic habits', 'Radical candor', 'Inspired', 'The goal', 'Measure what matters', 'Good strategy bad strategy', 'Building a second brain', 'How to take smart notes', 'Show your work', 'Four thousand weeks', 'The art of gathering', 'Essentialism', 'Make time', 'Resilient management', 'Staff engineer', 'Writing for busy readers'],
  Networking: ['DNS filtering', 'Branch firewalls', 'Wi-Fi guest network', 'SD-WAN pilot', 'IPv6 plan', 'Load balancers', 'Network diagram', 'Remote access options'],
}
function realTitles(g) {
  const topicName = new Map(g.topics.map((t) => [t.id, t.name]))
  const used = new Map()
  for (const p of g.pages) {
    // The demo files its most linked pages as type "hub" in 00 Index; a real vault files them by type.
    if (p.kind === 'hub') Object.assign(p, { kind: 'concept', bucket: 'Notes', section: 'Notes' })
    const m = /^(.*) page \d+$/.exec(p.title)
    if (!m) continue
    const name = topicName.get(p.topicIds[0]) ?? m[1]
    const pool = MORE[name] ?? MORE[m[1]] ?? []
    const k = used.get(name) ?? 0
    used.set(name, k + 1)
    if (pool[k]) p.title = pool[k]
  }
  const SUMMARY = {
    'Identity-aware proxies': 'A proxy in front of each application checks who asks and from which device on every request, instead of trusting the whole network after a VPN sign-in.',
    'Zero-trust networking': 'No device is trusted for being inside the network; every request is checked on identity, device and context.',
    'Partner portal': 'The portal partners use for orders and support; first system to leave the VPN.',
    'VPN retirement plan': 'Three waves that move remote access off the VPN by the end of the year.',
  }
  const REMOTE = new Set(['Identity-aware proxies', 'Zero-trust networking', 'VPN retirement plan', 'Partner portal', 'Split tunnelling', 'Proxy placement'])
  for (const p of g.pages) {
    p.summary = SUMMARY[p.title] ?? `Notes on ${p.title.toLowerCase()}.`
    if (REMOTE.has(p.title)) p.tags = [...new Set(['remote access', ...p.tags])]
  }
  return g
}

let graph = null
let submitAnswer = null
const addResult = {
  intent: 'add', status: 'added', kind: 'link', message: 'Added.', inboxId: '', ref: 'r1a2b3c4d', text: 'https://contoso.example/sites/security/zero-trust-roadmap.docx',
  page: { id: 'p900', title: 'Zero-trust roadmap 2026', type: 'link-internal', bucket: 'Internal links', section: 'Internal links', link: 'onenote:x', url: 'https://contoso.example/sites/security/zero-trust-roadmap.docx', topicPath: 'Security/Networking', alsoUnder: ['Projects'], oneNotePath: ['Work wiki', 'Internal links', 'Zero-trust roadmap 2026'], unfiled: false },
  chips: [{ kind: 'type', label: 'Internal link' }, { kind: 'topic', label: 'Security / Networking' }, { kind: 'topic', label: 'Projects' }],
  links: [
    { target: 'p3', title: 'Identity-aware proxies', link: 'onenote:x', anchor: 'identity-aware proxies', strength: 3, why: 'The roadmap is built on this approach.' },
    { target: 'p4', title: 'VPN retirement plan', link: 'onenote:x', anchor: 'retire the VPN', strength: 3, why: 'Same goal, earlier plan.' },
    { target: 'p5', title: 'Partner portal', link: 'onenote:x', anchor: 'partner portal', strength: 2, why: 'First wave of the roadmap.' },
    { target: 'p6', title: 'Sam (security lead)', link: 'onenote:x', anchor: 'Sam', strength: 1, why: 'Owner of the roadmap.' },
  ],
  backlinks: 2, related: [], dropped: [], warnings: [], timings: { totalMs: 41200 }, undo: { id: 'u1', pageId: 'p900', targets: ['p3', 'p4'] }, inbox: { pageId: 'i9', status: 'filed' }, update: null, confirm: null,
}
const src = (n, title, path, type, age, stale = false) => ({ n, id: `s${n}`, key: `s${n}`, title, path, link: 'onenote:#example', updated: '', age, type, archived: false, sourceId: 'v1', sourceName: 'Work wiki', readOnly: false, stale, summarizedAge: '' })
const askResult = {
  intent: 'ask', ok: true, status: 'answered', conversationId: 'c1', turn: 1, question: 'What did we decide about remote access for the partner portal?', writes: 0,
  note: 'Asking never changes your notebook.', message: 'Answered from 3 pages.',
  path: {
    branchesTotal: 6, branchesPicked: 2, pagesTotal: 41, pagesPicked: 3, pagesRead: 4, invalidBranches: 0, invalidPages: 0,
    steps: [
      { n: 1, kind: 'index', label: 'Index' },
      { n: 2, kind: 'branches', label: 'Security, Projects', branches: [{ path: 'Security / Networking', key: 'Security/Networking', source: 'Work wiki', readOnly: false, why: '' }, { path: 'Projects', key: 'Projects', source: 'Work wiki', readOnly: false, why: '' }] },
      { n: 3, kind: 'pages', label: '4 pages read', count: 4 },
    ],
    summary: 'Copilot picked 2 of 6 top-level branches, then 4 of 41 pages. Nothing outside these pages was used.',
  },
  answer: {
    confidence: 'high',
    paragraphs: [
      { sentences: [
        { text: 'The partner portal is the first system to move from the VPN to an identity-aware proxy.', cites: [1, 2], unsupported: false },
        { text: 'Partners sign in with their own company account, and every request is checked for user and device.', cites: [1], unsupported: false },
      ] },
      { sentences: [
        { text: 'The decision was made in the steering group in February, with the VPN switched off for partners at the end of March.', cites: [3], unsupported: false },
        { text: 'Sam owns the rollout; open points are listed on the roadmap page.', cites: [2], unsupported: false },
      ] },
    ],
  },
  sources: [
    src(1, 'Identity-aware proxies', 'Security / Networking', 'note', 'today'),
    src(2, 'Zero-trust roadmap 2026', 'Security / Networking', 'link-internal', 'today'),
    src(3, 'Steering group, 12 February', 'Projects', 'meeting', 'last month'),
  ],
  unused: [src(0, 'Split tunnelling', 'Security / Networking', 'note', 'last week')],
  staleLinks: [], invalidCitations: [], notFound: null,
}
const BODY = [
  '# Why',
  'The VPN gives every signed-in device the whole network. An **identity-aware proxy** checks *who* asks and *from which device*, for every request, and only opens the one application.',
  '## Decided',
  '1. Partners move first (see [Partner portal](obsn:PARTNER))\n2. Staff follow in two waves\n3. The VPN is switched off for partners at the end of March',
  '## Open points',
  '- [x] Choose the proxy product\n- [ ] Device checks for partner laptops\n- [ ] Support hours during the switch',
  '| Wave | Who | When |\n| --- | --- | --- |\n| 1 | Partners | March |\n| 2 | Office staff | May |\n| 3 | Field staff | September |',
  'Background reading: [the vendor guide](https://example.com/guides/proxy).',
  '## Your notes',
  'Ask Robin whether the data platform can sit behind the same proxy.',
].join('\n\n')

function answer(path) {
  switch (path) {
    case '/api/status': return { app: 'ObsidiNote', version: 'v0.9.1', uiPort: 8767, oneNote: { state: 'window', running: true, notebookOpen: true, notebook: 'Work wiki' }, copilot: { state: 'connected', port: 9334 }, vault: { name: 'Work wiki', vaultId: 'v1', mode: 'writer', reason: '', since: '', detail: '' } }
    case '/api/notebooks': return { notebooks: [notebook], message: '', activeVaultId: VAULT, mode: 'writer' }
    case '/api/notebook': return { available: true, message: '', notebook, sections: ['00 Index', '01 Intake', 'Notes', 'Internal links', 'Web links', 'People', 'Projects', 'Meetings', 'Decisions'].map((n, i) => section(n, [6, 2, 31, 14, 12, 9, 20, 14, 10][i])), totals: { sections: 9, pages: 118 },
      recent: [
        ['Identity-aware proxies', 'concept', 'Notes'], ['Steering group, 12 February', 'meeting', 'Meetings'], ['Partner portal', 'project', 'Projects'],
        ['Beyond the perimeter', 'link-web', 'Web links'], ['Decision log template', 'concept', 'Notes'], ['Split tunnelling', 'decision', 'Decisions'],
      ].map(([t, type, sec], i) => ({ title: t, section: sec, modified: ago(50 * (i + 1) + i * i * 40), link: 'onenote:x', pageId: graph.pages.find((x) => x.title === t)?.id ?? graph.pages[i].id, type })) }
    case '/api/settings': return { settings: { internalHosts: [], graphView: 'topics', labelsHubsOnly: false, relatedCount: 3, linkStaleDays: 90, askIncludeArchived: false, graphShowArchived: false, askMaxPages: 20 }, canChange: true, message: '' }
    case '/api/whats-new': return { version: 'v0.9.1', updated: false, notes: [] }
    case '/api/activity': return { canChange: true, vaultId: 'v1', items: [] }
    case '/api/graph': return graph
    case '/api/intent': return { intent: 'ask', reason: 'it reads as a question (starts with "What", ends with "?")', rule: 1 }
    // The answer's sources carry the ids of the map's pages, as the server's do (a citation opens one).
    case '/api/submit': return submitAnswer?.intent === 'ask' ? { ...submitAnswer, sources: submitAnswer.sources.map((s) => ({ ...s, id: graph.pages.find((p) => p.title === s.title)?.id ?? s.id })) } : submitAnswer
    case '/api/page/body': {
      const portal = graph.pages.find((p) => p.title === 'Partner portal')
      return { id: 'x', markdown: BODY.replace('PARTNER', portal ? portal.id : 'none'), truncated: false, length: BODY.length }
    }
    default: return null
  }
}

let ws, id = 0
const pending = new Map()
const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => { const i = ++id; pending.set(i, { resolve, reject }); ws.send(JSON.stringify({ id: i, method, params, sessionId })) })

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
  await S('Page.enable')
  await S('Fetch.enable', { patterns: [{ urlPattern: '*/api/*' }] })
  await S('Emulation.setDeviceMetricsOverride', { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false })
  await S('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'light' }, { name: 'prefers-reduced-motion', value: 'reduce' }] })
  const go = async (path, ready) => {
    await S('Page.navigate', { url: 'about:blank' })
    await S('Page.navigate', { url: BASE + path })
    let ok = false
    for (let k = 0; k < 150 && !ok; k++) { ok = await js(`!!document.querySelector(${JSON.stringify(ready)})`).catch(() => false); if (!ok) await wait(100) }
    if (!ok) throw new Error(`${path}: ${ready} never appeared (is Vite running on ${BASE}?)`)
    await wait(700)
  }
  const shot = async (name) => {
    await js(`document.activeElement && document.activeElement.blur && document.activeElement !== document.body && !document.activeElement.closest('dialog') ? document.activeElement.blur() : null`)
    await wait(250)
    const { data } = await S('Page.captureScreenshot', { format: 'png' })
    writeFileSync(join(OUT, `${name}.png`), Buffer.from(data, 'base64'))
    console.log('wrote', `docs/screenshots/${name}.png`)
  }
  const mouse = async (x, y, click = false) => {
    await S('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y })
    if (click) for (const type of ['mousePressed', 'mouseReleased']) await S('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 })
  }
  const dotOf = (title) => js(`(() => { const id = ${JSON.stringify(graph.pages.find((p) => p.title === title)?.id ?? '')}; const c = document.querySelector('.kg-base circle[data-id="' + id + '"]') || document.querySelectorAll('.kg-base circle.kg-dot--hub')[0]; const r = c.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2] })()`)
  const type = async (text) => {
    await js(`document.querySelector('#composer-text').focus()`)
    await S('Input.insertText', { text })
    await wait(900)
  }

  await go('/graph-demo.html?pages=100', '.kg-dot')
  graph = realTitles(JSON.parse(await js(`import('/src/graph/synthetic.ts').then((m) => JSON.stringify(m.syntheticGraph({ pages: 110, topics: 6, seed: 7 })))`)))
  graph.source = { ...graph.source, id: 'v1', kind: 'vault', name: 'Work wiki', readOnly: false, readOnlyReason: '' }

  // 1 home: a question typed, the box says what it will do
  await go('/#/', '.recent__row')
  await type('What did we decide about remote access for the partner portal?')
  await shot('home')

  // 2 ask: the answer with its sources
  submitAnswer = askResult
  await js(`document.querySelector('.composer__send').click()`)
  for (let k = 0; k < 50 && !(await js(`!!document.querySelector('[aria-label="Answer"]')`)); k++) await wait(100)
  await wait(600)
  await js(`window.scrollTo(0, 0)`)
  await shot('ask')

  // 3 add: a pasted link, filed and linked
  await go('/#/', '.recent__row')
  submitAnswer = addResult
  await type('https://contoso.example/sites/security/zero-trust-roadmap.docx')
  await js(`document.querySelector('.composer__send').click()`)
  for (let k = 0; k < 50 && !(await js(`!!document.querySelector('.add-result, [class*="add-res"]')`)); k++) await wait(100)
  await wait(700)
  await shot('add')

  // 4 map: topics, one page pointed at
  await go('/#/graph', '.kg-dot')
  const at = await dotOf('Identity-aware proxies')
  await mouse(at[0], at[1])
  await wait(700)
  await shot('map')

  // 5 page window: the page's own text
  await mouse(at[0], at[1], true)
  for (let k = 0; k < 50 && !(await js(`!!document.querySelector('dialog[open] .kg-body')`)); k++) await wait(100)
  await wait(500)
  await shot('page')

  // 6 tags: one area per tag, the topics named inside
  await go('/#/graph', '.kg-dot')
  await js(`[...document.querySelectorAll('.seg__btn')].find((b) => b.textContent.trim() === 'Tags').click()`)
  await wait(1000)
  await mouse(5, 5)
  await shot('tags')

  // 7 list: every page in one table
  await js(`[...document.querySelectorAll('.seg__btn')].find((b) => b.textContent.trim() === 'Topics').click()`)
  await wait(400)
  await js(`[...document.querySelectorAll('.seg__btn')].find((b) => b.textContent.trim() === 'List').click()`)
  await wait(900)
  await shot('list')
}

try {
  await main()
} catch (e) {
  console.error(e.message)
  process.exitCode = 1
} finally {
  try { ws?.close() } catch {}
  edge.kill()
  await wait(500)
  try { rmSync(profile, { recursive: true, force: true }) } catch {}
}
