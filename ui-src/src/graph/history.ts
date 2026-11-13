// Back/Forward in the page dialog. Pure (tests: history.test.ts).
//
// The dialog records every page reached by following a link, a backlink, a mention or the
// arrow keys. Back and Forward move through that list without adding to it; a new visit after
// Back drops the pages ahead (as a browser does). The history lives as long as the dialog.

export interface PageHistory {
  pages: string[]
  at: number
}

/** Longest history kept; the oldest pages drop off first. */
export const HISTORY_MAX = 50

export function startHistory(id: string): PageHistory {
  return { pages: [id], at: 0 }
}

export function currentPage(h: PageHistory): string {
  return h.pages[h.at]
}

/** A visit: the same page again changes nothing. */
export function visit(h: PageHistory, id: string): PageHistory {
  if (currentPage(h) === id) return h
  const pages = [...h.pages.slice(0, h.at + 1), id]
  const drop = Math.max(0, pages.length - HISTORY_MAX)
  return { pages: pages.slice(drop), at: pages.length - 1 - drop }
}

export function canGoBack(h: PageHistory): boolean {
  return h.at > 0
}

export function canGoForward(h: PageHistory): boolean {
  return h.at < h.pages.length - 1
}

export function goBack(h: PageHistory): PageHistory {
  return canGoBack(h) ? { pages: h.pages, at: h.at - 1 } : h
}

export function goForward(h: PageHistory): PageHistory {
  return canGoForward(h) ? { pages: h.pages, at: h.at + 1 } : h
}
