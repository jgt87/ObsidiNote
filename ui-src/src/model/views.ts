// The views and their place in the address (#/graph). The view is UI state, not content.

export type View = 'home' | 'graph' | 'history'

export const VIEWS: Record<View, { label: string; hash: string }> = {
  home: { label: 'Add or ask', hash: '#/' },
  graph: { label: 'Knowledge graph', hash: '#/graph' },
  history: { label: 'History', hash: '#/history' },
}

export const VIEW_ORDER: View[] = ['home', 'graph', 'history']

export function viewFromHash(hash: string): View {
  const found = VIEW_ORDER.find((v) => v !== 'home' && VIEWS[v].hash === hash)
  return found ?? 'home'
}
