// What needs the person's attention, from /api/status. Only problems are listed: a working
// OneNote or Copilot shows nothing (PRODUCT.md: no "connected" pills). Pure (tests: attention.test.ts).
import type { AppStatus, CopilotState } from '../api'

export interface AttentionNote {
  id: string
  text: string
  /** The note offers the refresh button that tries to connect Copilot again (user, 2026-11-14). */
  retry?: boolean
}

const COPILOT: Record<CopilotState, string> = {
  connected: '',
  skipped: 'Copilot is off for this start. Adding and asking will need it: start ObsidiNote without -NoCopilot.',
  'not-running': "ObsidiNote's Edge window is closed, so Copilot is not available. Press the refresh button to open it again.",
  'no-tab': "Copilot is not connected in ObsidiNote's Edge window. Press the refresh button to connect again; sign in there if it asks.",
}

/** The states the refresh button can fix; "skipped" was the person's choice for this start. */
const RETRY: Record<CopilotState, boolean> = { connected: false, skipped: false, 'not-running': true, 'no-tab': true }

export function attentionNotes(status: AppStatus | null, serverDown: boolean): AttentionNote[] {
  if (serverDown) {
    return [{ id: 'server', text: 'ObsidiNote is not running. Start it again; its console window must stay open.' }]
  }
  if (!status) return []
  const notes: AttentionNote[] = []
  if (!status.oneNote.running) notes.push({ id: 'onenote', text: 'OneNote is not running. Start OneNote to see your notebook.' })
  else if (!status.oneNote.notebookOpen) notes.push({ id: 'notebook', text: 'No ObsidiNote vault is open in OneNote. Choose one under Notebook, set up an empty notebook, or make a new vault.' })
  const copilot = COPILOT[status.copilot.state] ?? ''
  if (copilot) notes.push({ id: 'copilot', text: copilot, retry: RETRY[status.copilot.state] ?? false })
  return notes
}
