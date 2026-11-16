// What the Add or ask box shows and sends for its current text, mode and reading. Pure (tests:
// composerView.test.ts); components/Composer.tsx holds the state and renders.
import type { Intent, Mode } from '../api'

export interface ComposerViewInput {
  text: string
  /** The address when the text is one link and nothing else (model/links.ts loneLink), else null. */
  onlyLink: string | null
  mode: Mode
  /** What the server read the text as; undefined while it is not known. */
  intent: Intent | undefined
  /** The "From" choice: where the text came from ('' = typed). */
  origin: string
  /** The address of a dropped file found in a synced folder, while one is kept. */
  fileLink: { url: string } | null
  busy: boolean
  /** Sending cannot work right now (Copilot or ObsidiNote gone). */
  disableSend: boolean
}

export interface ComposerView {
  empty: boolean
  /** The "From" choice: not for an empty box, a link alone (its address says where it lives) or
   *  a question (an Ask files nothing). */
  showFrom: boolean
  /** The origin that goes with a send ('' when "From" is not shown). */
  sendOrigin: string
  /** The dropped file's address, for as long as the box still holds that file's text: the "From"
   *  choice is "File" while it does, so trimming a paragraph or fixing a typo keeps it (code review
   *  2026-11-15: any edit dropped it without a word). '' otherwise. */
  liveFileUrl: string
  /** A file's address was kept and is not any more: the box says so. */
  linkDropped: boolean
  /** Ask's options (what Ask reads) only when the text will be asked (operator, 2026-11-14). */
  asking: boolean
  canSend: boolean
}

export function composerView(i: ComposerViewInput): ComposerView {
  const empty = !i.text.trim()
  const showFrom = !empty && !i.onlyLink && i.mode !== 'ask' && i.intent !== 'ask'
  const liveFileUrl = i.fileLink && i.origin === 'file' && !empty ? i.fileLink.url : ''
  return {
    empty,
    showFrom,
    sendOrigin: showFrom ? i.origin : '',
    liveFileUrl,
    linkDropped: !!i.fileLink && !liveFileUrl && !empty,
    asking: i.mode === 'ask' || (i.mode === 'auto' && i.intent === 'ask'),
    canSend: !empty && !i.busy && !i.disableSend,
  }
}
