// Code-size ratchet: functions under 80 lines and cyclomatic complexity 10 or
// less. Older code may break the rule, so a source file may not gain
// violations over the committed baseline, and a file not in the baseline may
// have none. Tests are exempt (a describe block is long by nature).
// Origin: CommonShared templates/scripts/check-code-size.mjs. Fitted here: the
// starter measures with ESLint; this project installs no linter for it (operator,
// 2026-11-24), so it measures with the dependency-free reader the CommonShared
// audit uses (scripts/code-size-reader.mjs, copied in unedited).
//
//   node scripts/check-code-size.mjs            check (`npm run lint`)
//   node scripts/check-code-size.mjs --update   write or lower the baseline after
//                                               a split; it never rises by hand
//
// A file that must grow past the limit is split instead; raising its number in
// the baseline is the operator's decision. scripts/shared/ holds copies of shared
// scripts that are never edited here: their size is not ours.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { measureJs } from './code-size-reader.mjs';

const SOURCE = /^(src\/.*\.(ts|tsx)|scripts\/.*\.mjs)$/;
const IGNORED = /^scripts\/(shared\/|code-size-reader\.mjs$)/;
const IS_TEST = /\.(test|spec)\.[cm]?[jt]sx?$/;
const MAX_LINES = 80;
const MAX_COMPLEXITY = 10;
const RULES = { lines: 'max-lines-per-function', complexity: 'complexity' };

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// Baseline keys are relative to the repository (ui-src/src/...), the form a repository-wide audit reads.
const PREFIX = 'ui-src/';
const baselinePath = path.join(root, 'scripts', 'code-size-baseline.json');

/** Violations per file and rule, from [{ file, fns: [{ lines, complexity }] }]; source files only, files sorted. */
export function violationCounts(measured) {
  const counts = {};
  for (const { file, fns } of measured) {
    if (IS_TEST.test(file)) continue;
    for (const fn of fns) {
      if (fn.lines > MAX_LINES) ((counts[file] ??= {})[RULES.lines] = (counts[file]?.[RULES.lines] ?? 0) + 1);
      if (fn.complexity > MAX_COMPLEXITY) ((counts[file] ??= {})[RULES.complexity] = (counts[file]?.[RULES.complexity] ?? 0) + 1);
    }
  }
  return Object.fromEntries(Object.keys(counts).sort().map((file) => [file, counts[file]]));
}

/** The baseline --update writes: it only ever lowers; a count above the old baseline keeps the old number. */
export function lowerBaseline(counts, baseline) {
  const next = {};
  for (const [file, rules] of Object.entries(counts)) {
    for (const [rule, count] of Object.entries(rules)) {
      const old = baseline ? baseline[file]?.[rule] ?? 0 : count;
      if (count <= old) (next[file] ??= {})[rule] = count;
      else if (old > 0) (next[file] ??= {})[rule] = old;
    }
  }
  return next;
}

/** Each file and rule over its baseline count, as "file: rule count (allowed n)". */
export function ratchetFailures(counts, baseline) {
  const failures = [];
  for (const [file, rules] of Object.entries(counts)) {
    for (const [rule, count] of Object.entries(rules)) {
      const allowed = baseline[file]?.[rule] ?? 0;
      if (count > allowed) failures.push(`${file}: ${rule} ${count} (allowed ${allowed})`);
    }
  }
  return failures;
}

/** The interface's own source files (tracked or new, not ignored), each measured; a file the reader cannot follow fails the check. */
function measureAll() {
  const listed = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], { cwd: root, encoding: 'utf8' });
  const files = [...new Set(listed.split('\0'))]
    .filter((f) => SOURCE.test(f) && !IGNORED.test(f) && fs.existsSync(path.join(root, f)))
    .sort();
  const unread = [];
  const measured = files.flatMap((file) => {
    try {
      return [{ file: PREFIX + file, fns: measureJs(fs.readFileSync(path.join(root, file), 'utf8')) }];
    } catch (e) {
      unread.push(`${file}: ${e.message}`);
      return [];
    }
  });
  // A silent skip would report zero violations: no files found, or one the reader could not follow, fails.
  if (!files.length || unread.length) {
    console.error(`code size: ${files.length} files found; ${unread.length} could not be read.`);
    unread.forEach((line) => console.error(`  ${line}`));
    process.exit(1);
  }
  return measured;
}

function main() {
  const counts = violationCounts(measureAll());
  const baseline = fs.existsSync(baselinePath) ? JSON.parse(fs.readFileSync(baselinePath, 'utf8')) : null;

  if (process.argv.includes('--update')) {
    const next = lowerBaseline(counts, baseline);
    fs.writeFileSync(baselinePath, `${JSON.stringify(next, null, 2)}\n`);
    console.log(`code size baseline written: ${Object.keys(next).length} files`);
    return;
  }
  if (!baseline) {
    console.error('code size: no baseline yet. Run with --update once to write it.');
    process.exit(1);
  }
  const failures = ratchetFailures(counts, baseline);
  if (failures.length) {
    console.error(`code size: a function grew past ${MAX_LINES} lines or complexity ${MAX_COMPLEXITY}; split it.`);
    failures.forEach((line) => console.error(`  ${line}`));
    process.exitCode = 1;
  } else {
    const total = Object.values(counts).reduce((sum, r) => sum + Object.values(r).reduce((a, b) => a + b, 0), 0);
    console.log(`code size: no file grew (${total} older violations in the baseline)`);
  }
}

// Runs only as a program: a test can import the pure parts above.
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
