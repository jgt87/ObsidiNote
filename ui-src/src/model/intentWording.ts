// Words for the intent line and the primary button. Pure (tests: intentWording.test.ts).
import type { IntentResult, Mode } from '../api'
import type { AddTarget } from './notebooks'

export interface IntentLine {
  /** Bold lead, e.g. "Will ask your wiki"; '' for a plain hint. */
  lead: string
  text: string
  /** One-click flip to the other mode, when there is a clear pick. */
  flip: { label: string; mode: Mode } | null
}

export const EMPTY_HINT = 'Paste a link or longer text to add it. Short questions are asked.'

/** While a read-only notebook is shown, an Add still goes to the active vault: say so. */
export function addTargetNote(target: AddTarget | null): string {
  if (!target) return ''
  if (!target.vaultName) return ` No ObsidiNote vault is open, and ${target.shownName} is read only.`
  return ` It goes to ${target.vaultName}, not to ${target.shownName} (read only).`
}

export function intentLine(result: IntentResult | null, target: AddTarget | null = null): IntentLine {
  if (!result || result.intent === 'empty') return { lead: '', text: EMPTY_HINT, flip: null }
  switch (result.intent) {
    case 'ask':
      return { lead: 'Will ask your wiki', text: `${result.reason}.`, flip: { label: 'Add it instead', mode: 'add' } }
    case 'add':
      return { lead: 'Will add to your wiki', text: `${result.reason}.${addTargetNote(target)}`, flip: { label: 'Ask instead', mode: 'ask' } }
    case 'unclear':
      return { lead: 'Not sure yet', text: `${result.reason}. Copilot will decide when you send it, or choose Add or Ask.`, flip: null }
  }
}

/** The primary button follows the intent. */
export function primaryLabel(result: IntentResult | null): string {
  if (result?.intent === 'ask') return 'Ask'
  if (result?.intent === 'add') return 'Add'
  return 'Send'
}
