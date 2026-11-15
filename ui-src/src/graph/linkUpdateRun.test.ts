import { describe, expect, it } from 'vitest'
import { advance, isLinkPage, isStale, outcomeOf, runLine, staleCutoff, startRun } from './linkUpdateRun'
import type { GraphPage } from './model'

const pg = (over: Partial<GraphPage>): GraphPage => ({
  id: 'p1', title: 'T', topicIds: [], bucket: 'Web links', section: 'Web links', tags: [], kind: 'link-web', links: 0, linkedFrom: 0, weight: 0,
  isHub: false, unlinked: true, sourceId: '', origin: '', summary: '', onenoteUrl: '', modified: '', readOnly: false, aliases: [], site: '',
  archived: false, url: 'https://example.org/', ...over,
})

describe('stale link summaries', () => {
  const now = Date.parse('2026-11-15T12:00:00Z')
  const cut = staleCutoff(90, now)
  it('the cut-off is N days back', () => {
    expect(cut).toBe('2026-08-17T12:00:00.000Z')
  })
  it('a link page read before the cut-off, or never, is stale; one read after is not', () => {
    expect(isStale(pg({ summarizedAt: '2026-07-01T09:00:00.000Z' }), cut)).toBe(true)
    expect(isStale(pg({ summarizedAt: '' }), cut)).toBe(true)
    expect(isStale(pg({}), cut)).toBe(true)
    expect(isStale(pg({ summarizedAt: '2026-11-01T09:00:00.000Z' }), cut)).toBe(false)
  })
  it('a page that is not a link is never stale', () => {
    expect(isLinkPage(pg({ url: '', kind: 'concept' }))).toBe(false)
    expect(isStale(pg({ url: '', kind: 'concept' }), cut)).toBe(false)
  })
})

describe('the run, one page at a time', () => {
  const title = (id: string) => `Page ${id}`
  it('walks the pages in order and sums up what came of them', () => {
    let s = startRun(['a', 'b', 'c', 'a'])
    expect(s.ids).toEqual(['a', 'b', 'c'])
    expect(runLine(s, title)).toBe('Updating 1 of 3: Page a')
    s = advance(s, 'a', outcomeOf('updated'))
    s = advance(s, 'b', outcomeOf('needs-confirmation'))
    expect(runLine(s, title)).toBe('Updating 3 of 3: Page c')
    s = advance(s, 'c', outcomeOf('waiting'))
    expect(s.current).toBe('')
    expect(runLine(s, title)).toBe('1 updated, 1 needs your decision (open the page and press Update), 1 waits for Copilot (see Waiting for Copilot on the home page).')
  })
  it('Stop ends after the page being updated', () => {
    let s = startRun(['a', 'b', 'c'])
    s = { ...s, stopped: true }
    expect(runLine(s, title)).toMatch(/stops after this one/)
    s = advance(s, 'a', outcomeOf('unchanged'))
    expect(s.current).toBe('')
    expect(runLine(s, title)).toBe('Stopped after 1 page. 1 unchanged.')
  })
  it('any other status is a failure', () => {
    expect(outcomeOf('could-not-update')).toBe('failed')
    expect(outcomeOf('kept')).toBe('updated')
  })
})
