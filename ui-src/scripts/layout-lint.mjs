// The shared rendered layout lint (scripts/shared/check-design-rules.mjs, a copy of CommonShared's
// templates/scripts/check-design-rules.mjs: refresh it from there, never edit it here) run on this
// app with invented data. It checks what this project's own check-design-rules.mjs does not: text
// under 10/11px, text touching or spilling out of its box, sideways scroll, fields under 16px on
// touch, text hidden under reduced motion, 44px reach on touch, one primary per view, and lists the
// findings to judge (panels darker than the page in dark, straight quotes, tight insets).
// Its first run (audit 2026-11-19) found two touch targets this project's check had exempted.
//
// The config is built here, in memory, and written to a temp folder for the run only: the API
// answers are the same invented data as check-design-rules.mjs, the graph comes from the demo
// generator (src/graph/synthetic.ts) through Vite's module loader.
//
// Usage (ui-src): npx vite --port 5193 --strictPort   (separately), then
//   node scripts/layout-lint.mjs [http://localhost:5193] [cdp port 9561] [--strict]
// Exit: the shared check's code (0 pass, 1 a rule broken, 2 setup or nothing checked).
import { spawnSync } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const ui = join(here, '..')
const args = process.argv.slice(2)
const strict = args.includes('--strict')
const [base = 'http://localhost:5193', port = '9561'] = args.filter((a) => !a.startsWith('--'))

const { createServer } = await import(pathToFileURL(join(ui, 'node_modules', 'vite', 'dist', 'node', 'index.js')).href)
const vite = await createServer({ root: ui, configFile: false, server: { middlewareMode: true }, logLevel: 'silent' })
const { syntheticGraph } = await vite.ssrLoadModule('/src/graph/synthetic.ts')
const graph = syntheticGraph({ pages: 100, topics: 6, seed: 7 })
await vite.close()

const VAULT = '{11111111-1111-1111-1111-111111111111}{1}{B0}'
const ago = (min) => new Date(Date.now() - min * 60000).toISOString()
const notebook = { id: VAULT, name: 'Work wiki', vault: true, active: true, location: 'OneDrive', vaultId: 'v1', kind: 'notebook', notebookId: VAULT }
const section = (name, pages) => ({ name, kind: 'section', pages, children: [] })
const item = (inboxId, state, more) => ({ inboxId, state, kind: 'text', requestKind: 'add', updated: ago(30), since: '', reason: '', filedAs: '', filedTitle: '', filedType: '', canCheck: false, canRemove: false, canUndo: false, ...more })

const api = {
  '/api/status': { app: 'ObsidiNote', version: 'v0.0.0', uiPort: 8767, oneNote: { state: 'window', running: true, notebookOpen: true, notebook: 'Work wiki' }, copilot: { state: 'connected', port: 9334 } },
  '/api/notebooks': { notebooks: [notebook], message: '', activeVaultId: VAULT, mode: 'writer' },
  '/api/notebook': { available: true, message: '', notebook, sections: ['00 Index', '01 Intake', 'Notes', 'Web links', 'Meetings', 'Decisions'].map((n, i) => section(n, 3 + i)), totals: { sections: 6, pages: 33 },
    recent: graph.pages.slice(0, 6).map((p, i) => ({ title: p.title, section: p.bucket, modified: ago(60 * (i + 1)), link: 'onenote:x', pageId: p.id, type: p.kind })) },
  '/api/settings': { settings: { internalHosts: [], graphView: 'topics', labelsHubsOnly: false, relatedCount: 3, linkStaleDays: 90, askIncludeArchived: false, graphShowArchived: false, askMaxPages: 20 }, canChange: true },
  '/api/whats-new': { version: 'v0.0.0', updated: false, notes: [] },
  '/api/activity': { canChange: true, vaultId: 'v1', items: [
    item('i1', 'waiting', { title: 'https://fernbrook.example/sites/platform/plan-1.docx', kind: 'link', since: ago(14), canCheck: true, canRemove: true }),
    item('i9', 'added', { title: 'Notes from the steering group', filedAs: 'p12', filedTitle: 'Steering group', filedType: 'meeting', canUndo: true }),
  ] },
  '/api/graph': graph,
  '/api/intent': { intent: 'add', reason: 'It is a link', rule: 2 },
}

const config = {
  base,
  api,
  primary: '.btn--primary',
  // The map's drawing (dots, areas, lines) is data, not text in boxes.
  lintIgnore: '.kg-stage svg',
  waivers: [
    { rule: 'tight-inset', match: 'kg-plabel', reason: 'A page name on the map is a small pill next to its dot; a wider inset would cover more dots (DESIGN.md, Every Dot Is Content).' },
    { rule: 'card-in-card', match: 'kg-toolbar', reason: 'The zoom toolbar floats over the map on a phone; the map stage is a drawing area, not a card.' },
  ],
  views: [
    { name: 'home', path: '/', ready: '.composer', main: '.composer' },
    { name: 'history', path: '/#/history', ready: 'main' },
    { name: 'journal', path: '/#/journal', ready: 'main' },
    { name: 'graph', path: '/#/graph', ready: 'circle', fill: true },
  ],
}

const dir = mkdtempSync(join(tmpdir(), 'obsn-layout-'))
let status = 2
try {
  const file = join(dir, 'design-check.json')
  writeFileSync(file, JSON.stringify(config))
  const run = spawnSync(process.execPath, [join(here, 'shared', 'check-design-rules.mjs'), '--config', file, '--port', String(port), ...(strict ? ['--strict'] : [])], { stdio: 'inherit' })
  status = run.status ?? 2
} finally {
  rmSync(dir, { recursive: true, force: true })
}
process.exit(status)
