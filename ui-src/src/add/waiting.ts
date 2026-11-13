// Wording of an Add that waits for Copilot (status waiting) and of the outcomes of "Check for the
// answer". Pure (tests: waiting.test.ts).
import type { AddStatus } from './types'

export type WaitingStatus = 'waiting' | 'still-waiting' | 'mismatch' | 'invalid'

const WAITING: readonly AddStatus[] = ['waiting', 'still-waiting', 'mismatch', 'invalid']

/** The item waits in the Intake and "Check for the answer" applies. */
export function isWaitingStatus(status: AddStatus): status is WaitingStatus {
  return WAITING.includes(status)
}

/** The short line under the server's message: what it means for the item. */
export function waitingNote(status: WaitingStatus): string {
  switch (status) {
    case 'waiting':
      return 'Copilot is still working on it. The item waits in your Intake; nothing else was written yet.'
    case 'still-waiting':
      return 'No answer yet. Try again later; the item keeps waiting in your Intake.'
    case 'mismatch':
      return 'The answer in that chat is not for this item, so it was not used. Nothing was written.'
    case 'invalid':
      return 'The answer could not be used. Nothing was written; the item keeps waiting in your Intake.'
  }
}

/** The label of the card: the state of the wait. */
export function waitingLabel(status: WaitingStatus): string {
  switch (status) {
    case 'waiting':
      return 'Waiting for Copilot'
    case 'still-waiting':
      return 'Still waiting'
    case 'mismatch':
      return 'Answer not for this item'
    case 'invalid':
      return 'Answer not usable'
  }
}
