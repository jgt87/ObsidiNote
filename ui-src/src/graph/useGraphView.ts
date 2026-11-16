// The knowledge graph's map layouts per grouping, and the vault's map settings. Used by
// KnowledgeGraph.tsx.
import { useEffect, useMemo, useRef, useState } from 'react'
import { getSettings, saveSetting } from '../api'
import type { VaultSettings } from '../model/vaultSettings'
import { buildIndex, type GraphIndex } from './graphIndex'
import { layoutGraph } from './layout'
import type { GraphModel } from './model'
import { bySource, type GroupBy } from './sourceView'
import { byTag } from './tagView'

/**
 * The layouts of the map: by topic always (the List and the counts use it), and by where the pages
 * come from (sourceView.ts) or by hand-set tag (tagView.ts) only while that grouping is chosen.
 * Only the map's areas change: the page window, filters, search and List keep the topics.
 */
export function useMapLayouts(model: GraphModel, index: GraphIndex, aspect: number, groupBy: GroupBy, tagChoice: ReadonlySet<string> | null) {
  const layout = useMemo(() => layoutGraph(model, { aspect }, index), [model, index, aspect])
  const sourceLayout = useMemo(() => {
    if (groupBy !== 'sources') return null
    const m = bySource(model)
    return layoutGraph(m, { aspect }, buildIndex(m))
  }, [groupBy, model, aspect])
  const tagLayout = useMemo(() => {
    if (groupBy !== 'tags') return null
    const m = byTag(model, tagChoice)
    return layoutGraph(m, { aspect }, buildIndex(m))
  }, [groupBy, model, aspect, tagChoice])
  return { layout, sourceLayout, tagLayout, mapLayout: tagLayout ?? sourceLayout ?? layout }
}

/**
 * The map opens with the vault's settings (kept in OneNote, model/vaultSettings.ts): `apply` gets
 * them once. A change made on the map is saved there with `remember`, when this window may change
 * them and the map is the active vault's own (another vault or a connected notebook is read only);
 * otherwise it lasts this session. `staleDays`: the vault's "older than N days" for link summaries
 * (linkStaleDays), the Filter's stale box.
 */
export function useGraphSettings(readOnly: boolean, apply: (s: VaultSettings) => void) {
  const [staleDays, setStaleDays] = useState(90)
  const canSave = useRef(false)
  useEffect(() => {
    let live = true
    getSettings()
      .then((s) => {
        if (!live) return
        canSave.current = s.canChange
        apply(s.settings)
        setStaleDays(s.settings.linkStaleDays)
      })
      .catch(() => {}) // the defaults stay; the map works without them
    return () => {
      live = false
    }
    // Once per view, as before: `apply` only calls state setters.
  }, [])
  const remember = <K extends 'graphView' | 'labelsHubsOnly'>(key: K, value: VaultSettings[K]) => {
    if (canSave.current && !readOnly) saveSetting(key, value).catch(() => {})
  }
  return { staleDays, remember }
}
