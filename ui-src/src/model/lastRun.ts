// "Try again" repeats the request that failed, exactly: the same call with the same arguments and
// the same steps after it. Pure (tests: lastRun.test.ts).
//
// code review 2026-11-15: a retry that built a similar request instead (a new question where a
// follow-up had failed) lost the conversation, and skipped what the first send did on success.

export interface LastRun {
  /** Runs `fn` now and remembers it as the thing to repeat. */
  run: (fn: () => void) => void
  /** Runs the remembered thing again; nothing when nothing ran yet. */
  again: () => void
}

export function lastRun(): LastRun {
  let last: (() => void) | null = null
  return {
    run(fn) {
      last = fn
      fn()
    },
    again() {
      last?.()
    },
  }
}
