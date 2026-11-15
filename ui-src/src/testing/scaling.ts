// How a piece of code grows with its input, for speed tests (shared rule: a speed test counts
// operations or compares scaling, never wall-clock milliseconds). A CI runner can be ten times
// slower than this PC on one run and not on the next (v0.10.0's tag run, 2026-11-15: three tests
// with millisecond limits failed while the same commit passed on main), but both sizes are timed
// on the same machine in the same run, so their ratio holds. Used by tests only; the test
// `noWallClock.test.ts` keeps performance.now() out of the test files themselves.

/** Mean time of one call, repeating the call until at least `minMs` has passed. */
function perCall(fn: () => void, minMs: number): number {
  let n = 0
  const t0 = performance.now()
  do {
    fn()
    n++
  } while (performance.now() - t0 < minMs)
  return (performance.now() - t0) / n
}

/**
 * How many times longer `big` takes than `small`: the best of `rounds` timings of each, after
 * one warm-up call. For a big input ten times the small one, linear work gives about 10,
 * n log n about 13, and work that compares every item with every other about 100.
 */
export function growth(small: () => void, big: () => void, rounds = 3, minMs = 30): number {
  small()
  big()
  let s = Infinity
  let b = Infinity
  for (let i = 0; i < rounds; i++) {
    s = Math.min(s, perCall(small, minMs))
    b = Math.min(b, perCall(big, minMs))
  }
  return b / s
}
