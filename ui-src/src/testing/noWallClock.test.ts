import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'
import { describe, expect, it } from 'vitest'

// A test never holds a limit in milliseconds: the CI runner's speed changes from run to run
// (v0.10.0's tag run, 2026-11-15, failed on three such limits while the same commit passed on
// main). Speed tests compare growth (testing/scaling.ts) or count operations. A lesson saying
// so existed and three tests still broke it, so this is the check.
const SRC = join(__dirname, '..')

function testFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name)
    if (statSync(p).isDirectory()) return testFiles(p)
    return /\.test\.tsx?$/.test(name) ? [p] : []
  })
}

describe('speed tests compare growth, never milliseconds', () => {
  it('no test file reads the clock itself', () => {
    const files = testFiles(SRC).filter((p) => !p.endsWith('noWallClock.test.ts'))
    expect(files.length).toBeGreaterThan(20)
    const found = files.filter((p) => /performance\.now\(|Date\.now\(\)\s*-/.test(readFileSync(p, 'utf8'))).map((p) => relative(SRC, p))
    expect(found, 'use growth() from testing/scaling.ts, or count operations').toEqual([])
  })
})
