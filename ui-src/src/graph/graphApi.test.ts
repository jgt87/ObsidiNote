import { describe, expect, it } from 'vitest'
import { addLink, GraphLoadError, LINK_ADD_ROUTE } from './graphApi'

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
