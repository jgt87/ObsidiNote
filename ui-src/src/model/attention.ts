// What needs the person's attention, from /api/status. Only problems are listed: a working
// OneNote or Copilot shows nothing (PRODUCT.md: no "connected" pills). Pure (tests: attention.test.ts).
import type { AppStatus, CopilotState } from '../api'
import { clockTime, formatModified } from './format'
import type { VaultState } from '../api'

export interface AttentionNote {
  id: string
  text: string
  /** The note offers the refresh button that tries to connect Copilot again (user, 2026-11-14). */
  retry?: boolean
}

const COPILOT: Record<CopilotState, string> = {
  connected: '',
  skipped: 'Copilot is off for this start. Adding and asking need it: close ObsidiNote and start it again the usual way.',
  'not-running': "ObsidiNote’s Edge window is closed, so Copilot is not available. Press the refresh button to open it again.",
  'no-tab': "Copilot is not connected in ObsidiNote’s Edge window. Press the refresh button to connect again; sign in there if it asks.",
}

/** The states the refresh button can fix; "skipped" was the person's choice for this start. */
const RETRY: Record<CopilotState, boolean> = { connected: false, skipped: false, 'not-running': true, 'no-tab': true }

/** Why this window cannot write in its vault, and what to do; '' when it can (or the server is too
 *  old to say). operator, 2026-11-15: pages of the main vault showed "read only" with no reason.
 *  The lease reasons are read from a lease record, not seen happen, and usually pass by themselves
 *  (a start taking over from the one before), so they say what may be the case and what comes next,
 *  never a verdict (operator, 2026-11-15: "this currently isn't confirmed so the statement must be
 *  adjusted to make it probable/possible"). */
export function vaultNote(status: AppStatus): string {
  const v = status.vault
  if (!v || v.mode === 'writer' || !v.reason) return ''
  const since = v.since ? ` since ${formatModified(v.since)}` : ''
  const by = v.until && clockTime(v.until) ? `by ${clockTime(v.until)}` : 'within about two minutes'
  if (v.reason === 'other-pc') return `Pages may show as read only for now: an ObsidiNote on another PC seems to be writing in this vault${since}. If it is closed there, this window takes over ${by}.`
  if (v.reason === 'this-pc') return `Starting up: pages may show as read only for a moment while this window takes over the vault from an earlier ObsidiNote on this PC. This usually clears ${by}.`
  if (v.reason === 'not-opened') return `The vault could not be opened${v.detail ? `: ${v.detail}` : '.'} Nothing can be added until it is; start ObsidiNote again after fixing it.`
  return ''
}

/**
 * What "Check again" found, under the note ('' when this window is the writer now: the note goes).
 * A holder that renewed its lease within the last 90 seconds is still running (it renews every
 * minute), so waiting will not help and the person is told where to close it; otherwise the lease
 * runs out at "until" and this window takes over then (operator, 2026-11-15: "Check again doesn't
 * seem to clear the message").
 */
export function leaseCheckNote(v: VaultState, now: Date = new Date()): string {
  if (v.mode === 'writer' || !v.reason || v.reason === 'not-opened') return ''
  const at = clockTime(now.toISOString())
  const renewed = v.renewed ? new Date(v.renewed) : null
  const running = renewed && !Number.isNaN(renewed.getTime()) && now.getTime() - renewed.getTime() < 90_000
  if (running) {
    const where = v.reason === 'this-pc' ? 'its console window on this PC (titled ObsidiNote)' : 'ObsidiNote on that PC'
    return `Checked at ${at}: the vault is still held, and its holder renewed it at ${clockTime(v.renewed!)}, so it seems to be still running. Close ${where}; this window then takes over within about two minutes.`
  }
  const by = v.until && clockTime(v.until) ? `by ${clockTime(v.until)}` : 'within about two minutes'
  return `Checked at ${at}: not free yet. Its holder has not renewed it lately, so this window should take over ${by}.`
}

/** Why a send cannot work right now, for the box itself (review 2026-11-14: the only warning sat
 *  at the bottom of the side bar, far from Send). Send is switched off only when ObsidiNote itself
 *  is gone; with Copilot reported off it stays on, so a status that lags never locks the box. */
export interface SendBlock {
  text: string
  disableSend: boolean
  /** "Connect Copilot again" can fix it. */
  retry: boolean
}

export function sendBlock(status: AppStatus | null, serverDown: boolean): SendBlock | null {
  if (serverDown) return { text: 'ObsidiNote is not running, so nothing can be sent. Start it again; your text stays here.', disableSend: true, retry: false }
  if (!status || status.copilot.state === 'connected' || !(status.copilot.state in COPILOT)) return null
  const retry = RETRY[status.copilot.state] ?? false
  return { text: retry ? 'Copilot is not connected. Adding and asking need it.' : 'Copilot is off for this start. Adding and asking need it.', disableSend: false, retry }
}

export function attentionNotes(status: AppStatus | null, serverDown: boolean): AttentionNote[] {
  if (serverDown) {
    return [{ id: 'server', text: 'ObsidiNote is not running. Start it again; its console window must stay open.' }]
  }
  if (!status) return []
  const notes: AttentionNote[] = []
  if (!status.oneNote.running) notes.push({ id: 'onenote', text: 'OneNote is not running. Start OneNote to see your notebook.' })
  else if (!status.oneNote.notebookOpen) notes.push({ id: 'notebook', text: 'No ObsidiNote vault is open in OneNote. Choose one under Notebook, set up an empty notebook, or make a new vault.' })
  // Why the vault is read only is not a side bar note: the banner above the content says it
  // (vaultNote, components/ReadOnlyBanner).
  const copilot = COPILOT[status.copilot.state] ?? ''
  if (copilot) notes.push({ id: 'copilot', text: copilot, retry: RETRY[status.copilot.state] ?? false })
  return notes
}
