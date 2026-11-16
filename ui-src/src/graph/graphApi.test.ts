import { describe, expect, it } from 'vitest'
import { addLink, editPage, fetchGraph, fetchPageBody, GraphLoadError, LINK_ADD_ROUTE, PAGE_BODY_ROUTE, PAGE_EDIT_ROUTE, renameTag, RETIRE_ROUTES, retirePages, tagPages } from './graphApi'

function fakeFetch(status: number, body: unknown, seen: { url?: string; init?: RequestInit } = {}): typeof fetch {
  return (async (url: RequestInfo | URL, init?: RequestInit) => {
    seen.url = String(url)
    seen.init = init
    return new Response(JSON.stringify(body), { status })
  }) as typeof fetch
}

describe('addLink', () => {
  it('posts from, to and vault with the app header and returns the outcome', async () => {
    const seen: { url?: string; init?: RequestInit } = {}
    expect(await addLink({ from: 'p2', to: 'p1', vault: 'v1' }, fakeFetch(200, { status: 'linked' }, seen))).toBe('linked')
    expect(seen.url).toBe(LINK_ADD_ROUTE)
    expect(seen.init?.method).toBe('POST')
    expect((seen.init?.headers as Record<string, string>)['X-ObsidiNote']).toBe('1')
    expect(JSON.parse(String(seen.init?.body))).toEqual({ from: 'p2', to: 'p1', vault: 'v1' })
    expect(await addLink({ from: 'p2', to: 'p1' }, fakeFetch(200, { status: 'already-linked' }))).toBe('already-linked')
  })
  it('throws the server\'s message on a refusal', async () => {
    await expect(addLink({ from: 'p2', to: 'p1' }, fakeFetch(409, { error: 'Read only: another one writes.' }))).rejects.toThrow('Read only: another one writes.')
    await expect(addLink({ from: 'p2', to: 'p1' }, fakeFetch(500, null))).rejects.toBeInstanceOf(GraphLoadError)
  })
  it('says when the server is not answering', async () => {
    const down = (async () => {
      throw new TypeError('fetch failed')
    }) as typeof fetch
    await expect(addLink({ from: 'a', to: 'b' }, down)).rejects.toThrow('not answering')
  })
})

// Every call goes through the same send / answer / refusal helpers: one test per call pins what it
// sends and how a refusal, a missing server and a cancelled request come back.
const headerOf = (init?: RequestInit) => (init?.headers as Record<string, string>)['X-ObsidiNote']
const aborted = (async () => {
  throw new DOMException('cancelled', 'AbortError')
}) as typeof fetch

describe('fetchGraph and fetchPageBody', () => {
  it('ask with the app header and no cache, and pass on a cancelled request as it is', async () => {
    const seen: { url?: string; init?: RequestInit } = {}
    await expect(fetchGraph({ vault: 'v1' }, undefined, fakeFetch(404, { error: 'No such vault.' }, seen))).rejects.toThrow('No such vault.')
    expect(seen.url).toBe('/api/graph?vault=v1')
    expect(headerOf(seen.init)).toBe('1')
    expect(seen.init?.cache).toBe('no-store')
    await expect(fetchGraph({}, undefined, aborted)).rejects.toMatchObject({ name: 'AbortError' })
    await expect(fetchPageBody('p1', {}, undefined, aborted)).rejects.toMatchObject({ name: 'AbortError' })
  })
  it('reads the page text, with both sources in the address', async () => {
    const seen: { url?: string; init?: RequestInit } = {}
    expect(await fetchPageBody('p1', { vault: 'v1', notebook: 'n1' }, undefined, fakeFetch(200, { markdown: '# Hi', truncated: true }, seen))).toEqual({ markdown: '# Hi', truncated: true })
    expect(seen.url).toBe(`${PAGE_BODY_ROUTE}?page=p1&vault=v1&notebook=n1`)
    expect(headerOf(seen.init)).toBe('1')
    expect(await fetchPageBody('p1', {}, undefined, fakeFetch(200, { markdown: 3 }))).toEqual({ markdown: '', truncated: false })
    await expect(fetchPageBody('p1', {}, undefined, fakeFetch(503, 'text'))).rejects.toThrow('The server answered 503.')
  })
})

describe('the POST calls', () => {
  it('editPage, tagPages and renameTag send JSON with the app header', async () => {
    const seen: { url?: string; init?: RequestInit } = {}
    expect(await editPage({ id: 'p1', title: 'New' } as never, fakeFetch(200, { status: 'unchanged' }, seen))).toBe('unchanged')
    expect(seen.url).toBe(PAGE_EDIT_ROUTE)
    expect((seen.init?.headers as Record<string, string>)['Content-Type']).toBe('application/json')
    expect(headerOf(seen.init)).toBe('1')
    expect(await editPage({ id: 'p1' } as never, fakeFetch(200, {}))).toBe('edited')
    expect(await tagPages({ ids: ['p1'], add: ['a'], remove: [] }, fakeFetch(200, { changed: 1 }, seen))).toBe(1)
    expect(JSON.parse(String(seen.init?.body))).toEqual({ ids: ['p1'], add: ['a'], remove: [] })
    expect(await renameTag({ from: 'a', to: 'b', vault: 'v1' }, fakeFetch(200, {}, seen))).toBe(0)
    expect(JSON.parse(String(seen.init?.body))).toEqual({ from: 'a', to: 'b', vault: 'v1' })
    // A cancelled POST is not passed on: the server may already have it.
    await expect(editPage({ id: 'p1' } as never, aborted)).rejects.toThrow('not answering')
  })
  it('retirePages: a plan to confirm, a result, or the refusal', async () => {
    const seen: { url?: string; init?: RequestInit } = {}
    const plan = await retirePages('archive', ['p1'], 'v1', false, fakeFetch(409, { needsConfirm: true, plan: { pages: [{ id: 'p1', title: 'One' }] } }, seen))
    expect(plan.kind).toBe('plan')
    expect(seen.url).toBe(RETIRE_ROUTES.archive)
    expect(JSON.parse(String(seen.init?.body))).toEqual({ ids: ['p1'], vault: 'v1' })
    const done = await retirePages('delete', ['p1'], '', true, fakeFetch(200, { status: 'done' }, seen))
    expect(done).toMatchObject({ kind: 'result', result: { status: 'done', action: 'delete' } })
    expect(JSON.parse(String(seen.init?.body))).toEqual({ ids: ['p1'], confirm: true })
    await expect(retirePages('restore', ['p1'], 'v1', false, fakeFetch(409, { error: 'Another vault.' }))).rejects.toThrow('Another vault.')
  })
})
