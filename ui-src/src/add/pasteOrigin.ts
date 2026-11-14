// Which app a paste came from, read from the HTML the clipboard carries (operator, 2026-11-14:
// "record where new items come from"). Pure and a best guess: the person sees it as the "From:"
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
