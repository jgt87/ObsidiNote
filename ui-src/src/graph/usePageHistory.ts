// The page window's Back/Forward over the pages visited in it (history.ts); gone when it closes.
// Used by PageDialog.tsx.
import { useEffect, useState } from 'react'
import { canGoBack, canGoForward, currentPage, goBack, goForward, startHistory, visit, type PageHistory } from './history'

/**
 * `go` visits a page (following a link in the window); `back` and `forward` walk the visits. A page
 * set from outside (not through these) still counts as a visit. Every move tells the graph which
 * page to show (onNavigate).
 */
export function usePageHistory(pageId: string, onNavigate: (id: string) => void) {
  const [hist, setHist] = useState<PageHistory>(() => startHistory(pageId))
  useEffect(() => {
    setHist((h) => (currentPage(h) === pageId ? h : visit(h, pageId)))
  }, [pageId])
  const go = (id: string) => {
    setHist((h) => visit(h, id))
    onNavigate(id)
  }
  const move = (next: PageHistory) => {
    if (next === hist) return
    setHist(next)
    onNavigate(currentPage(next))
  }
  return {
    go,
    back: () => move(goBack(hist)),
    forward: () => move(goForward(hist)),
    canBack: canGoBack(hist),
    canForward: canGoForward(hist),
  }
}
