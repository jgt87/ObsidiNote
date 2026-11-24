import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { seeded, syntheticGraph, type SyntheticOptions } from './synthetic'

// The demo model is seeded: the same seed gives the same model only while the random draws stay in
// the same order (synthetic.ts). The demo page, the README screenshots and the rendered checks
// all draw from it, so a refactor that reorders the draws changes what they show without failing
// anything else. This pins the model for three seeds. A change here is deliberate only when the
// generator's output is meant to change: then update the digests and say so in the change.

/** Everything the draws decide, in a fixed shape: topics, pages and edges. */
function shape(opts: SyntheticOptions): string {
  const m = syntheticGraph(opts)
  return JSON.stringify({
    topics: m.topics.map((t) => [t.id, t.name, t.parent, t.pageCount]),
    pages: m.pages.map((p) => [p.id, p.title, p.topicIds, p.bucket, p.kind, p.modified, p.weight]),
    edges: m.edges.map((e) => [e.from, e.to, e.strength, e.kind, e.reason ?? '']),
  })
}
const digest = (opts: SyntheticOptions): string => createHash('sha256').update(shape(opts)).digest('hex').slice(0, 16)

describe('the seeded demo model stays the same', () => {
  it('the generator draws the same numbers', () => {
    const rnd = seeded(7)
    expect([rnd(), rnd(), rnd()].map((x) => x.toFixed(10))).toEqual(GOLDEN.draws)
  })

  it('seed 7 (the default: demo page, screenshots, rendered checks)', () => {
    const m = syntheticGraph({ pages: 100, topics: 6, seed: 7 })
    expect([m.pages.length, m.edges.length]).toEqual(GOLDEN.seed7.counts)
    expect(m.pages.slice(0, 4).map((p) => `${p.id} ${p.title} ${p.bucket}`)).toEqual(GOLDEN.seed7.firstPages)
    expect(m.edges.slice(0, 4).map((e) => `${e.from}>${e.to} ${e.strength} ${e.reason ?? ''}`)).toEqual(GOLDEN.seed7.firstEdges)
    expect(digest({ pages: 100, topics: 6, seed: 7 })).toBe(GOLDEN.seed7.digest)
  })

  it('seed 42, read only, more topics than named', () => {
    expect(digest({ pages: 60, topics: 9, seed: 42, readOnly: true })).toBe(GOLDEN.seed42)
  })

  it('seed 3, small with unfiled pages', () => {
    expect(digest({ pages: 25, topics: 4, seed: 3, unfiled: 3 })).toBe(GOLDEN.seed3)
  })
})

const GOLDEN = {
  draws: ['0.0117047532', '0.0619582576', '0.9769076328'],
  seed7: {
    counts: [100, 139],
    firstPages: ['p1 Zero-trust networking 00 Index', 'p2 Identity-aware proxies Notes', 'p3 Single sign-on Internal links', 'p4 Device trust checklist Notes'],
    firstEdges: ['p2>p1 3 background reading', 'p3>p1 2 decided in this meeting', 'p4>p1 1 background reading', 'p4>p3 1 the check it relies on'],
    digest: '1474254d6904cec7',
  },
  seed42: 'f982824e8d0a2237',
  seed3: '4194ac6238d0fa19',
}
