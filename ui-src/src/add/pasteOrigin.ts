// Which app a paste came from, read from the HTML the clipboard carries (D-015).
// Pure and a best guess: the person sees it as the "From:"
// choice under the box and can change it before Add. Markers, checked in this order:
// - Teams: its message markup (itemprop="copy-paste-block", data-tid) or a Teams address;
// - Outlook: its Office namespace, its reply/forward header blocks or Outlook on the web's markup;
// - Word: Word's Office namespace or its Mso styles;
// - any other HTML: a web page. No HTML (plain text) says nothing: the choice stays as it was.

const TEAMS = /itemprop=["']?copy-paste-block|data-tid=|teams\.microsoft\.com|teams\.cloud\.microsoft/i
const OUTLOOK = /urn:schemas-microsoft-com:office:outlook|OutlookMessageHeader|divRplyFwdMsg|elementToProof|x_MsoNormal|appendonsend/i
const WORD = /urn:schemas-microsoft-com:office:word|class=["']?Mso[A-Z]/i

/** The origin id for pasted HTML ('outlook' | 'teams' | 'word' | 'web'), or null for none. */
export function originOfPaste(html: string | null | undefined): string | null {
  if (!html || !/<[a-z!]/i.test(html)) return null
  if (TEAMS.test(html)) return 'teams'
  if (OUTLOOK.test(html)) return 'outlook'
  if (WORD.test(html)) return 'word'
  return 'web'
}

/** The lines a paste is remembered by. */
const MARK_LINES = 5
const MARK_MIN = 12

/** The part of a paste remembered to tell later whether it is still in the box: up to five of its
 *  lines (the first 60 characters of each), so fixing a typo or cutting the greeting in one line
 *  does not lose where the text came from. A paste with no line of 12 characters or more has no
 *  mark ('' = it stays until the box is emptied): a mark like "Hi" matched any text typed over it
 *  (code review 2026-11-15). */
export function pasteMark(pasted: string): string {
  const lines = pasted.split('\n').map((l) => l.trim().slice(0, 60)).filter((l) => l.length >= MARK_MIN)
  return [...new Set(lines)].slice(0, MARK_LINES).join('\n')
}

/**
 * Whether the "From:" choice still belongs to the box's text: only while the pasted text is still
 * there (code review 2026-11-14: select-all and type over, or a prefill, kept "Teams" on unrelated
 * text). An empty mark (typed, or the choice set by hand) always keeps it.
 */
export function originStillApplies(text: string, mark: string): boolean {
  return !mark || mark.split('\n').some((line) => text.includes(line))
}

/** What the box remembers of the paste its "From:" choice was read from. "seen": the paste has
 *  landed in the text (the text changes after the paste event); "from": the origin that belongs to
 *  the mark; "lost": the pasted text was in the box and is gone again. */
export interface MarkState {
  mark: string
  seen: boolean
  from: string
  lost: boolean
}

export function newMark(mark = '', from = ''): MarkState {
  return { mark, seen: false, from, lost: false }
}

/** After the box's text changed: the next mark state, and the "From:" choice to set (undefined =
 *  leave it). The origin goes when the pasted text goes, and comes back with it (Ctrl+Z); an
 *  emptied box forgets both. */
export function followMark(m: MarkState, text: string): { mark: MarkState; origin?: string } {
  if (!text.trim()) return { mark: newMark(), origin: '' }
  const still = originStillApplies(text, m.mark)
  if (m.mark && still) return m.lost ? { mark: { ...m, seen: true, lost: false }, origin: m.from } : { mark: { ...m, seen: true } }
  if (m.seen && !still && !m.lost) return { mark: { ...m, lost: true }, origin: '' }
  return { mark: m }
}
