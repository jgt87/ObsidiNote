// The views and their place in the address (#/graph). The view is UI state, not content.

export type View = 'home' | 'graph' | 'journal' | 'history'

export const VIEWS: Record<View, { label: string; hash: string }> = {
  home: { label: 'Add or ask', hash: '#/' },
  graph: { label: 'Knowledge graph', hash: '#/graph' },
  // The Journal (D-060): one page per day, searched by topic across all sources.
  journal: { label: 'Journal', hash: '#/journal' },
  history: { label: 'History', hash: '#/history' },
}

export const VIEW_ORDER: View[] = ['home', 'graph', 'journal', 'history']

/** The window title for a view: the app's name alone on the home page. */
export function viewTitle(view: View): string {
  return view === 'home' ? 'ObsidiNote' : `${VIEWS[view].label} - ObsidiNote`
}

export function viewFromHash(hash: string): View {
  const found = VIEW_ORDER.find((v) => v !== 'home' && VIEWS[v].hash === hash)
  return found ?? 'home'
}
