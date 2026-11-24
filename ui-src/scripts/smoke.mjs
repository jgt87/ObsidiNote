// Smoke check of the committed, shipped interface (../ui), without a server or a browser:
//   - ui/index.html exists;
//   - every script, style sheet and icon it names exists on disk, and every asset the scripts
//     load by name (a lazily loaded chunk) does too;
//   - nothing inline: no <script> without src, no <style>, no style="" and no on...= handler,
//     because the server sends Content-Security-Policy default-src 'self' and would block them.
// Usage (ui-src): npm run smoke   Exit 0 = all hold; 1 = each fault named on stderr.
// No dependencies; reads files only.
import { existsSync, readFileSync, statSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const ui = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'ui')

/** The file a reference in index.html points at, or null for an outside address. */
function fileOf(ref) {
  if (/^[a-z][a-z0-9+.-]*:|^\/\//i.test(ref)) return null
  return join(ui, ref.split(/[?#]/)[0].replace(/^\.?\//, ''))
}

/** src/href values of <script> and <link> tags. */
function referencesIn(html) {
  const tags = html.match(/<(script|link)\b[^>]*>/gi) ?? []
  return tags.flatMap((tag) => [...tag.matchAll(/\b(?:src|href)\s*=\s*["']([^"']+)["']/gi)].map((m) => m[1]))
}

/** What the page has inline, which the CSP blocks. */
function inlineFaults(html) {
  const faults = []
  for (const m of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
    if (!/\bsrc\s*=/.test(m[1]) || m[2].trim()) faults.push(`inline <script>: ${m[0].slice(0, 60)}`)
  }
  if (/<style\b/i.test(html)) faults.push('inline <style> element')
  if (/<[^>]+\sstyle\s*=/i.test(html)) faults.push('inline style="" attribute')
  const handler = html.match(/<[^>]+\son[a-z]+\s*=/i)
  if (handler) faults.push(`inline event handler: ${handler[0].slice(0, 60)}`)
  return faults
}

/** Assets a built script loads by name ("assets/x.js"), checked to exist beside it. */
function chunkFaults(file) {
  if (!file.endsWith('.js')) return []
  const names = new Set(readFileSync(file, 'utf8').match(/assets\/[\w.-]+\.(?:js|css)\b/g) ?? [])
  return [...names].filter((n) => !existsSync(join(ui, n))).map((n) => `${relative(ui, file)} loads ${n}, which is missing`)
}

function check() {
  const index = join(ui, 'index.html')
  if (!existsSync(index)) return [`${index} is missing: run npm run build`]
  const html = readFileSync(index, 'utf8')
  const faults = inlineFaults(html)
  const refs = referencesIn(html)
  if (!refs.some((r) => /\.js(\?|$)/.test(r))) faults.push('index.html names no script')
  for (const ref of refs) {
    const file = fileOf(ref)
    if (!file) continue
    if (!existsSync(file) || statSync(file).size === 0) faults.push(`index.html names ${ref}, which is missing or empty`)
    else faults.push(...chunkFaults(file))
  }
  return faults
}

const faults = check()
if (faults.length) {
  console.error(`smoke: ${faults.length} fault(s) in the committed ui/:`)
  for (const f of faults) console.error(`  ${f}`)
  process.exit(1)
}
console.log('smoke: ui/index.html and every file it loads are present; nothing inline')
