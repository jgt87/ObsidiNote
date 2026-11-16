// Headless Edge for the rendered checks (check-design-rules, check-control-rows, readme-shots):
// start it with its own temporary profile, and stop it so that nothing is left behind.
//
// The msedge.exe we spawn is only a launcher: it starts the real browser process and exits, so
// killing it (even with its process tree) stops nothing, and the browser's own processes keep the
// profile folder in use, so deleting it fails. That happened on every run for three days until
// the disk was full (2026-11-16: 118 profiles, 19.7 GB). So: ask the browser itself to quit over
// its debugging port, then stop any process still running with this profile, then delete the
// profile, retrying while files are released, and say so when it still cannot be deleted.
import { spawn, spawnSync } from 'node:child_process'
import { existsSync, mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
const wait = (ms) => new Promise((r) => setTimeout(r, ms))

/** Starts headless Edge on CDP port `port` with a new profile in TEMP named `<prefix>…`. */
export function startEdge(port, prefix) {
  const profile = mkdtempSync(join(tmpdir(), prefix))
  const edge = spawn(EDGE, ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--no-first-run', '--window-size=1440,900', 'about:blank'], { stdio: 'ignore' })
  return { edge, profile, port }
}

/** Asks the browser on `port` to quit (CDP Browser.close); resolves when it answered or after 3 s. */
async function closeBrowser(port) {
  try {
    const { webSocketDebuggerUrl } = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json()
    const ws = new WebSocket(webSocketDebuggerUrl)
    await new Promise((resolve) => {
      const done = setTimeout(resolve, 3000)
      ws.addEventListener('open', () => ws.send(JSON.stringify({ id: 1, method: 'Browser.close' })))
      ws.addEventListener('close', () => { clearTimeout(done); resolve() })
      ws.addEventListener('error', () => { clearTimeout(done); resolve() })
    })
  } catch {
    // the browser is not answering (never started, or already gone): the next step stops what is left
  }
}

/** Stops every Edge process that runs with this profile (Windows; the profile path names this run). */
function stopProfileProcesses(profile) {
  if (process.platform !== 'win32') return
  const path = profile.replace(/'/g, "''")
  const cmd = `Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains('${path}') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }`
  spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', cmd], { stdio: 'ignore' })
}

/** Stops Edge and everything it started, then deletes its profile (retrying for up to 5 s).
 *  Returns whether the profile is gone; prints a line when it is not. */
export async function stopEdge({ edge, profile, port }) {
  await closeBrowser(port)
  edge.kill()
  for (let k = 0; k < 20; k++) {
    if (k === 4) stopProfileProcesses(profile) // still in use after 1 s: stop what holds it
    try {
      rmSync(profile, { recursive: true, force: true })
    } catch {
      // still in use by a process that is closing: try again shortly
    }
    if (!existsSync(profile)) return true
    await wait(250)
  }
  console.error(`Note: the temporary browser profile could not be deleted: ${profile}`)
  return false
}
