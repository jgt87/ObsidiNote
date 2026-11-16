// The graph's write actions (GraphView.tsx): each writes through the API (or a handler given from
// outside, the demo's), then reads the map again in place, so the map and an open page window stay
// and show the change. Read-only sources and connected notebooks get none of them.
import { useMemo } from 'react'
import { updateLink } from '../add/api'
import { exportSourceOf } from '../export/exportApi'
import { addLink, editPage, fetchPageBody, retirePages, tagPages } from './graphApi'
import { mentionBetween } from './mentions'
import type { GraphModel } from './model'
import type { PageActions } from './PageDialog'

/** Reads the map again after a write that succeeded; when that read fails, the write still stands,
 *  so the failure says so (`message`) instead of reporting the write as failed. */
export async function rereadAfter(refresh: () => Promise<void>, message: string): Promise<void> {
  await refresh().catch(() => {
    throw new Error(message)
  })
}

/** A vault the window can write in (not a connected notebook, not read only). */
export const canWrite = (model: GraphModel | null): model is GraphModel => !!model && model.source.kind === 'vault' && !model.source.readOnly

/** "Link it" on a mention: the link goes from the page that mentions to the page it names. */
function useLinkMention(model: GraphModel | null, refresh: () => Promise<void>, given: PageActions['onLinkMention']) {
  return useMemo<PageActions['onLinkMention']>(() => {
    if (given) return given
    if (!canWrite(model)) return undefined
    return async (a, b) => {
      const m = mentionBetween(model, a.id, b.id)
      await addLink({ from: m ? m.from : a.id, to: m ? m.to : b.id, vault: model.source.id })
      await rereadAfter(refresh, 'The link was added, but the map could not be read again. Reload the map to see it.')
    }
  }, [given, model, refresh])
}

/** Edit in the page window: save, then read the map again in place (the window stays open). */
function useEditPage(model: GraphModel | null, refresh: () => Promise<void>, given: PageActions['onEditPage']) {
  const writable = canWrite(model)
  return useMemo<PageActions['onEditPage']>(() => {
    if (!given && !writable) return undefined
    return async (req) => {
      await (given ? given(req) : editPage(req))
      await rereadAfter(refresh, 'The page was saved, but the map could not be read again. Reload the map to see it.')
    }
  }, [given, writable, refresh])
}

/** Tags: write, then read the map again in place. */
function useTagPages(model: GraphModel | null, refresh: () => Promise<void>, given: PageActions['onTagPages']) {
  return useMemo<PageActions['onTagPages']>(() => {
    if (!canWrite(model)) return undefined
    const vault = model.source.id
    return async (ids, add, remove) => {
      if (given) await given(ids, add, remove)
      else await tagPages({ ids, add, remove, vault })
      await rereadAfter(refresh, 'The tags were saved, but the map could not be read again. Reload the map to see them.')
    }
  }, [given, model, refresh])
}

/** Archive / Restore / Delete: after a result the map is read again in place; a plan (the confirm's
 *  data) writes nothing, so it needs no re-read. A failed re-read is said in the result's message,
 *  never as a failure: the pages did change. */
function useRetire(model: GraphModel | null, refresh: () => Promise<void>, given: PageActions['onRetire']) {
  return useMemo<PageActions['onRetire']>(() => {
    if (!canWrite(model)) return undefined
    const vault = model.source.id
    return async (action, ids, confirm) => {
      const a = given ? await given(action, ids, confirm) : await retirePages(action, ids, vault, confirm)
      if (a.kind === 'result') {
        await refresh().catch(() => {
          a.result.message += ' The map could not be read again; reload it to see the change.'
        })
      }
      return a
    }
  }, [given, model, refresh])
}

/** One link page's Update (the List's "Update summaries"), then the map again, so the page's date
 *  and the stale filter follow; a failed re-read is left unsaid (the next one shows it). */
function useUpdateLink(model: GraphModel | null, refresh: () => Promise<void>, given: PageActions['onUpdateLink']) {
  return useMemo<PageActions['onUpdateLink']>(() => {
    if (!canWrite(model)) return undefined
    return async (id) => {
      const status = given ? await given(id) : (await updateLink(id)).status
      await refresh().catch(() => {})
      return status
    }
  }, [given, model, refresh])
}

/** The page window's text: the shown source's page, read when the window shows it. The function
 *  only changes with the source, so an open page is not read again after a tag or an edit. */
function useLoadBody(model: GraphModel | null, given: PageActions['loadBody']) {
  const bodySource = model ? JSON.stringify(exportSourceOf(model.source)) : ''
  return useMemo<PageActions['loadBody']>(() => {
    if (given) return given
    if (!bodySource) return undefined
    return (pageId, signal) => fetchPageBody(pageId, JSON.parse(bodySource), signal)
  }, [given, bodySource])
}

/** Every action the page window and the List can take on the shown model. */
export function useGraphWrites(model: GraphModel | null, refresh: () => Promise<void>, given: PageActions) {
  return {
    onLinkMention: useLinkMention(model, refresh, given.onLinkMention),
    onEditPage: useEditPage(model, refresh, given.onEditPage),
    onTagPages: useTagPages(model, refresh, given.onTagPages),
    loadBody: useLoadBody(model, given.loadBody),
    onRetire: useRetire(model, refresh, given.onRetire),
    onUpdateLink: useUpdateLink(model, refresh, given.onUpdateLink),
  }
}
