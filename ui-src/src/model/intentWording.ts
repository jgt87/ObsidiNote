// Words for the intent line and the primary button. Pure (tests: intentWording.test.ts).
import type { IntentResult, Mode } from '../api'
import type { AddTarget } from './notebooks'

export interface IntentLine {
  /** Bold lead, e.g. "Will ask your wiki"; '' for a plain hint. */
  lead: string
  text: string
  /** One-click choices: the other mode after a clear pick, both when it is unclear (2026-11-18). */
  choices: { label: string; mode: Mode }[]
}

export const EMPTY_HINT = 'Paste a link or longer text to add it. Short questions are asked.'

/** While a read-only notebook is shown, an Add still goes to the active vault: say so. */
export function addTargetNote(target: AddTarget | null): string {
  if (!target) return ''
  if (!target.vaultName) return ` No ObsidiNote vault is open, and ${target.shownName} is read only.`
  return ` It goes to ${target.vaultName}, not to ${target.shownName} (read only).`
}

export function intentLine(result: IntentResult | null, target: AddTarget | null = null): IntentLine {
  if (!result || result.intent === 'empty') return { lead: '', text: EMPTY_HINT, choices: [] }
  switch (result.intent) {
    case 'ask':
      return { lead: 'Will ask your wiki', text: `${result.reason}.`, choices: [{ label: 'Add it instead', mode: 'add' }] }
    case 'add':
      return { lead: 'Will add to your wiki', text: `${result.reason}.${addTargetNote(target)}`, choices: [{ label: 'Ask instead', mode: 'ask' }] }
    case 'meetings':
      // A command for the Meetings panel (2026-11-20): nothing is added or asked by sending it.
      return { lead: 'Will fetch your meetings', text: `${result.reason}.`, choices: [{ label: 'Add it instead', mode: 'add' }, { label: 'Ask instead', mode: 'ask' }] }
    case 'unclear':
      // Both ways side by side: sent as it is, it is added and Copilot may still say it is a question.
      return {
        lead: 'Not sure yet',
        text: `${result.reason}.`,
        choices: [
          { label: 'Search your wiki', mode: 'ask' },
          { label: 'Add as a note', mode: 'add' },
        ],
      }
  }
}

/** The primary button follows the intent. */
export function primaryLabel(result: IntentResult | null): string {
  if (result?.intent === 'ask') return 'Ask'
  if (result?.intent === 'add') return 'Add'
  if (result?.intent === 'meetings') return 'Fetch meetings'
  return 'Send'
}
