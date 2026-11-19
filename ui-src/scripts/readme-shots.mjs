// The README's screenshots, taken from the real interface with invented data (no OneNote, no
// Copilot, no content of anyone's). Run it again after a visible change:
//   (ui-src) npx vite --port 5194 --strictPort      (separately), then
//   node scripts/readme-shots.mjs [http://localhost:5194] [cdp port 9566]
// Writes docs/screenshots/*.png (1440x900, light theme). Drives headless Edge over CDP and answers
// the API here, like check-design-rules.mjs.
import { writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { startEdge, stopEdge } from './headlessEdge.mjs'

const BASE = process.argv[2] || 'http://localhost:5194'
const PORT = Number(process.argv[3] || 9566)
const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'docs', 'screenshots')
const browser = startEdge(PORT, 'obsn-shots-')
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
  // Invented titles only: no real book, author or company (operator, 2026-11-19).
  'Reading notes': ['Notes on team flow', 'Small batches', 'Plans that bend', 'Systems at the kitchen table', 'Quiet focus', 'Wide and shallow', 'Leading from the back', 'Why people care', 'From engineer to lead', 'Habits in small steps', 'Honest feedback', 'Products people want', 'One bottleneck', 'Counting what counts', 'Strategy on one page', 'A notebook that remembers', 'Notes that link', 'Working in the open', 'Time is short', 'Meetings worth having', 'Doing less, better', 'Room in the calendar', 'Steady teams', 'The senior path', 'Writing for people in a hurry'],
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
// Answers of POST /api/submit in turn (Today's meetings adds several); null = submitAnswer.
let submitQueue = null
const addResult = {
  intent: 'add', status: 'added', kind: 'link', message: 'Added.', inboxId: '', ref: 'r1a2b3c4d', text: 'https://fernbrook.example/sites/security/zero-trust-roadmap.docx',
  page: { id: 'p900', title: 'Zero-trust roadmap 2026', type: 'link-internal', bucket: 'Internal links', section: 'Internal links', link: 'onenote:x', url: 'https://fernbrook.example/sites/security/zero-trust-roadmap.docx', topicPath: 'Security/Networking', alsoUnder: ['Projects'], oneNotePath: ['Work wiki', 'Internal links', 'Zero-trust roadmap 2026'], unfiled: false },
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
// Today's meetings as Copilot would list them (invented).
const meeting = (time, title, attendees, t, r, n) => ({ title, start: `2026-03-10 ${time}`, time, attendees, hasTranscript: t, hasRecap: r, hasNotes: n, readable: t || r || n })
const MEETINGS = [
  meeting('09:00', 'Stand-up: migration wave 2', 7, true, false, false),
  meeting('11:30', 'Partner portal: proxy go-live check', 5, true, true, false),
  meeting('13:00', 'Lunch and learn: Shape Up', 18, false, false, false),
  meeting('15:00', 'Office move: weekly planning', 6, false, false, true),
]
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
    case '/api/status': return { app: 'ObsidiNote', version: 'v0.12.9', uiPort: 8767, oneNote: { state: 'window', running: true, notebookOpen: true, notebook: 'Work wiki' }, copilot: { state: 'connected', port: 9334 }, vault: { name: 'Work wiki', vaultId: 'v1', mode: 'writer', reason: '', since: '', detail: '' } }
    case '/api/notebooks': return { notebooks: [notebook], message: '', activeVaultId: VAULT, mode: 'writer' }
    case '/api/notebook': return { available: true, message: '', notebook, sections: ['00 Index', '01 Intake', 'Notes', 'Internal links', 'Web links', 'People', 'Projects', 'Meetings', 'Decisions'].map((n, i) => section(n, [6, 2, 31, 14, 12, 9, 20, 14, 10][i])), totals: { sections: 9, pages: 118 },
      recent: [
        ['Identity-aware proxies', 'concept', 'Notes'], ['Steering group, 12 February', 'meeting', 'Meetings'], ['Partner portal', 'project', 'Projects'],
        ['Beyond the perimeter', 'link-web', 'Web links'], ['Decision log template', 'concept', 'Notes'], ['Split tunnelling', 'decision', 'Decisions'],
      ].map(([t, type, sec], i) => ({ title: t, section: sec, modified: ago(50 * (i + 1) + i * i * 40), link: 'onenote:x', pageId: graph.pages.find((x) => x.title === t)?.id ?? graph.pages[i].id, type })) }
    case '/api/settings': return { settings: { internalHosts: [], graphView: 'topics', labelsHubsOnly: false, relatedCount: 3, linkStaleDays: 90, askIncludeArchived: false, graphShowArchived: false, askMaxPages: 20 }, canChange: true, message: '' }
    case '/api/whats-new': return { version: 'v0.12.9', updated: false, notes: [] }
    case '/api/activity': return { canChange: true, vaultId: 'v1', items: [] }
    case '/api/graph': return graph
    case '/api/intent': return { intent: 'ask', reason: 'it reads as a question (starts with "What", ends with "?")', rule: 1 }
    // The answer's sources carry the ids of the map's pages, as the server's do (a citation opens one).
    case '/api/submit': if (submitQueue?.length) return submitQueue.shift()
      return submitAnswer?.intent === 'ask' ? { ...submitAnswer, sources: submitAnswer.sources.map((s) => ({ ...s, id: graph.pages.find((p) => p.title === s.title)?.id ?? s.id })) } : submitAnswer
    case '/api/meetings/day': return { day: '', meetings: MEETINGS }
    case '/api/meetings/notes': return { found: true, text: '# Meeting', attendees: 5, decisions: 2, actions: 3, basedOn: 'transcript' }
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
  addJournal(graph)

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
  await type('https://fernbrook.example/sites/security/zero-trust-roadmap.docx')
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

  // 8 journal: one page per day, searched on a topic (everything about it, all sources and days)
  await go('/#/journal', '.jr__row')
  const topic = graph.topics.find((t) => t.name === 'Projects') ?? graph.topics[0]
  await js(`(() => { const i = document.querySelector('.jr__field'); const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set; set.call(i, 'proj'); i.dispatchEvent(new Event('input', { bubbles: true })) })()`)
  await wait(300)
  await js(`[...document.querySelectorAll('.jr__suggest button')].find((b) => b.textContent.endsWith(${JSON.stringify(topic.path)}))?.click()`)
  await wait(500)
  await shot('journal')

  // 9 today's meetings: the day's list, two added (one added, one still waiting for Copilot)
  await go('/#/', '.mt')
  await js(`[...document.querySelectorAll('.mt button')].find((b) => b.textContent.includes('Fetch')).click()`)
  for (let k = 0; k < 50 && !(await js(`!!document.querySelector('.mt__row')`)); k++) await wait(100)
  submitQueue = [{ intent: 'add', status: 'added', page: { title: 'Migration wave 2: two teams still need laptops' } }, { intent: 'add', status: 'waiting', inboxId: 'i2', message: '' }]
  await js(`[...document.querySelectorAll('.mt__row input')][3].click()`)
  await wait(200)
  await js(`[...document.querySelectorAll('.mt button')].find((b) => b.textContent.startsWith('Add ')).click()`)
  for (let k = 0; k < 80 && !(await js(`!!document.querySelector('.mt__foot [role=status]')`)); k++) await wait(100)
  submitQueue = null
  await js(`window.scrollTo(0, 0)`)
  await wait(400)
  await shot('meetings')

  // 10 a meeting series in the Journal: its meetings only, and "Ask about these meetings"
  await go('/#/journal', '.jr__row')
  await js(`(() => { const i = document.querySelector('.jr__field'); const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set; set.call(i, 'stand-up'); i.dispatchEvent(new Event('input', { bubbles: true })) })()`)
  await wait(300)
  await js(`[...document.querySelectorAll('.jr__suggest button')].find((b) => b.textContent.startsWith('Meetings:'))?.click()`)
  await wait(500)
  await shot('series')

  // 11 asking within that series: the home page with the limit above the box
  await js(`[...document.querySelectorAll('.jr__series button')].find((b) => b.textContent.startsWith('Ask about'))?.click()`)
  for (let k = 0; k < 50 && !(await js(`!!document.querySelector('#composer-text')`)); k++) await wait(100)
  await type('What did the stand-ups say about laptops?')
  await shot('ask-series')
}

// Journal day pages of the last days and a decision page with the pages it came from (invented).
function addJournal(g) {
  const proj = g.topics.find((t) => t.name === 'Projects') ?? g.topics[0]
  const sec = g.topics.find((t) => t.name === 'Security') ?? g.topics[1] ?? proj
  const pad = (n) => String(n).padStart(2, '0')
  const dayOf = (back) => { const d = new Date(Date.now() - back * 86400000); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` }
  const days = [
    [0, [['08:40', 'Stand-up: migration wave 2', 'Wave 2 starts Monday; two teams still need laptops.', proj], ['13:15', 'Call with the proxy vendor', 'Licences for partners are included; support hours to confirm.', sec], ['16:50', 'Budget for the office move agreed', 'Finance agreed the move budget; movers booked for May.', proj]]],
    [1, [['09:05', 'Steering group', 'Partner portal goes first; VPN off for partners at the end of March.', proj], ['15:30', 'Phishing drill debrief', 'Click rate down to 4%; repeat in June.', sec]]],
    [3, [['10:00', 'Workshop: onboarding portal', 'Three journeys chosen for the first release.', proj]]],
  ]
  for (const [back, entries] of days) {
    const date = dayOf(back)
    g.pages.push({
      id: `pj${back}`, title: date, kind: 'log', bucket: 'Journal', section: `Journal/${date.slice(0, 4)}`, topicIds: [...new Set(entries.map((e) => e[3].id))], tags: [], aliases: [],
      summary: `${entries.length} entries`, created: `${date}T07:00:00.000Z`,
      entries: entries.map(([hm, title, summary, t], i) => ({ ref: `r${back}${i}`, at: `${date}T${hm}`, title, summary, topicIds: [t.id], links: [] })),
    })
  }
  // A daily stand-up as a meeting series: one page per day, each linked to the day before (2026-11-18).
  const series = 'Stand-up: migration wave 2'
  const standups = [[0, '08:40', 'Two teams still need laptops; wave 2 starts Monday.'], [1, '08:45', 'Pilot group moved without problems.'], [2, '08:40', 'Laptop order confirmed for both teams.'], [3, '08:50', 'Wave 2 plan agreed; pilot group picked.']]
  for (const [back, hm, summary] of standups) {
    const date = dayOf(back)
    g.pages.push({ id: `pm${back}`, title: `${series} · ${date}`, kind: 'meeting', bucket: 'Meetings', section: 'Meetings', topicIds: [proj.id], tags: [], aliases: [], summary, created: `${date}T20:00:00.000Z`, series, meetingAt: `${date}T${hm}` })
    if (back < 3) g.edges.push({ from: `pm${back}`, to: `pm${back + 1}`, strength: 1 })
  }
  // Its overview page (2026-11-19): not a meeting, linked to each of them.
  g.pages.push({ id: 'pms', title: `${series} (series)`, kind: 'meeting', seriesPage: true, bucket: 'Meetings', section: 'Meetings', topicIds: [proj.id], tags: [], aliases: [], summary: 'Wave 2 moves two teams; laptops are ordered and the pilot group has moved.', created: `${dayOf(3)}T20:05:00.000Z`, series, meetingAt: '' })
  for (const [back] of standups) g.edges.push({ from: 'pms', to: `pm${back}`, strength: 1 })
  const pick = (title) => g.pages.find((p) => p.title === title)?.id
  g.pages.push({ id: 'pjd', title: 'Decision: partners leave the VPN first', kind: 'decision', bucket: 'Decisions', section: 'Decisions', topicIds: [proj.id], tags: [], aliases: [], summary: 'The partner portal moves to the identity-aware proxy before staff do.', created: new Date(Date.now() - 86400000).toISOString() })
  for (const t of ['Partner portal', 'VPN retirement plan', 'Identity-aware proxies']) if (pick(t)) g.edges.push({ from: 'pjd', to: pick(t), strength: 3 })
}

try {
  await main()
} catch (e) {
  console.error(e.message)
  process.exitCode = 1
} finally {
  try { ws?.close() } catch {} // already closed: nothing to do
  await stopEdge(browser)
}
