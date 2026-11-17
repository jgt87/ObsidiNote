import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { normalizeGraph } from '../model'
import { createDemoServer, demoPageText, WRITER_ELSEWHERE } from './demoServer'

// The graph demo's stand-ins for the server (invented data). Fake timers: each call waits as the
// demo does (300-400 ms), and nothing here waits in real time.
const start = () =>
  normalizeGraph({
    source: { kind: 'vault', readOnly: false },
    topics: [{ id: 't1', name: 'Methods' }],
    pages: [
      { id: 'p1', title: 'Zero trust', kind: 'note', topicIds: ['t1'], summary: 'Old summary', tags: ['a'] },
      { id: 'p2', title: 'VPN plan', kind: 'note', topicIds: ['t1'], tags: [] },
    ],
  })
const server = (query = '') => createDemoServer(new URLSearchParams(query), start())

beforeEach(() => {
  vi.useFakeTimers()
})
afterEach(() => {
  vi.useRealTimers()
})

describe('demoPageText: the invented page text', () => {
  it('links to another page of the map, or says "another page" without one', () => {
    expect(demoPageText({ id: 'p2', title: 'VPN plan' })).toContain('See [VPN plan](obsn:p2) for the background.')
    expect(demoPageText(undefined)).toContain('See another page for the background.')
    expect(demoPageText(undefined)).toMatch(/^# Overview\n\n/)
  })
})

describe("createDemoServer: the stand-ins change the demo's own model", () => {
  it('Edit changes the title and summary after 400 ms and says so', async () => {
    const s = server()
    const log: string[] = []
    const done = s.editPage({ id: 'p1', summary: 'New summary' }, (x) => log.push(x))
    expect(s.model().pages[0].summary).toBe('Old summary')
    await vi.advanceTimersByTimeAsync(400)
    await done
    expect(s.model().pages[0].summary).toBe('New summary')
    expect(s.model().pages[0].title).toBe('Zero trust')
    expect(log).toEqual(['Edit: {"id":"p1","summary":"New summary"}'])
  })
  it('tags are added and taken off at once, each tag once', async () => {
    const s = server()
    await s.tagPages(['p1', 'p2'], ['a', 'b'], [], () => {})
    expect(s.model().pages.map((p) => p.tags.join(','))).toEqual(['a,b', 'a,b'])
    await s.tagPages(['p1'], [], ['a'], () => {})
    expect(s.model().pages[0].tags).toEqual(['b'])
  })
  it('"Link it" only logs; ?link=slow waits a minute', async () => {
    const s = server('link=slow')
    const log: string[] = []
    const done = s.linkMention(s.model().pages[0], s.model().pages[1], (x) => log.push(x))
    await vi.advanceTimersByTimeAsync(59_999)
    expect(log).toEqual([])
    await vi.advanceTimersByTimeAsync(1)
    await done
    expect(log).toEqual(['Link it: Zero trust → VPN plan'])
  })
  it('the page text links to another page; ?body=empty and long show those states', async () => {
    const text = server().loadBody('p1')
    await vi.advanceTimersByTimeAsync(300)
    expect((await text).markdown).toContain('(obsn:p2)')
    const empty = server('body=empty').loadBody('p1')
    await vi.advanceTimersByTimeAsync(300)
    expect(await empty).toEqual({ markdown: '', truncated: false })
    const long = server('body=long').loadBody('p1')
    await vi.advanceTimersByTimeAsync(300)
    expect((await long).truncated).toBe(true)
  })
  it("?<name>=fail shows that call's error and changes nothing", async () => {
    const s = server('edit=fail&tag=fail&link=fail&body=fail')
    const edit = s.editPage({ id: 'p1', title: 'X' }, () => {})
    const link = s.linkMention(s.model().pages[0], s.model().pages[1], () => {})
    const body = s.loadBody('p1')
    const errors = Promise.allSettled([edit, link, body])
    await vi.advanceTimersByTimeAsync(400)
    expect((await errors).map((r) => (r.status === 'rejected' ? (r.reason as Error).message : 'ok'))).toEqual([WRITER_ELSEWHERE, WRITER_ELSEWHERE, 'The page could not be read from OneNote. Try again.'])
    await expect(s.tagPages(['p1'], ['z'], [], () => {})).rejects.toThrow(WRITER_ELSEWHERE)
    expect(s.model().pages[0].title).toBe('Zero trust')
    expect(s.model().pages[0].tags).toEqual(['a'])
  })
})
