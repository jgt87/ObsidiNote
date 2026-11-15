import { describe, expect, it } from 'vitest'
import { growth } from './scaling'

// The helper tells linear work from work that compares every item with every other, or the
// growth tests built on it would pass on the slow code they are meant to catch.
const items = (n: number) => Array.from({ length: n }, (_, i) => (i * 7919) % n)
let sink = 0
const linear = (xs: number[]) => () => {
  for (const x of xs) sink += x
}
const allPairs = (xs: number[]) => () => {
  for (const a of xs) for (const b of xs) if (a === b) sink++
}

describe('growth', () => {
  it('reads about 10 for linear work on ten times the input, and far more for all pairs', () => {
    expect(growth(linear(items(20000)), linear(items(200000)))).toBeLessThan(30)
    expect(growth(allPairs(items(150)), allPairs(items(1500)), 2)).toBeGreaterThan(30)
    expect(sink).toBeGreaterThan(0)
  })
})
