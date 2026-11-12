// What needs the person's attention, from /api/status. Only problems are listed: a working
// OneNote or Copilot shows nothing (PRODUCT.md: no "connected" pills). Pure (tests: attention.test.ts).
import type { AppStatus, CopilotState } from '../api'

export interface AttentionNote {
  id: string
  text: string
}

const COPILOT: Record<CopilotState, string> = {
  connected: '',
  skipped: 'Copilot is off for this start. Adding and asking will need it: start ObsidiNote without -NoCopilot.',
  'not-running': "ObsidiNote's Edge window is closed, so Copilot is not available. Start ObsidiNote again.",
  'no-tab': "Copilot is not open in ObsidiNote's Edge window. Sign in there if it asks, or start ObsidiNote again.",
}

export function attentionNotes(status: AppStatus | null, serverDown: boolean): AttentionNote[] {
  if (serverDown) {
    return [{ id: 'server', text: 'ObsidiNote is not running. Start it again; its console window must stay open.' }]
  }
  if (!status) return []
  const notes: AttentionNote[] = []
  if (!status.oneNote.running) notes.push({ id: 'onenote', text: 'OneNote is not running. Start OneNote to see your notebook.' })
  else if (!status.oneNote.notebookOpen) notes.push({ id: 'notebook', text: 'No ObsidiNote vault is open in OneNote. Open your ObsidiNote notebook in OneNote.' })
  const copilot = COPILOT[status.copilot.state] ?? ''
  if (copilot) notes.push({ id: 'copilot', text: copilot })
  return notes
}
