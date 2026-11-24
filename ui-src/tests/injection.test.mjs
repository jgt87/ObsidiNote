// Injection sinks as a dependency-free node:test (docs/24, rules/security.md "Injection").
// Copy to tests/, adjust CONFIG, run with `node --test tests/injection.test.mjs`
// (INJECTION_SRC=path checks another folder). It reads the source of every language the project
// has (JS/TS and their markup, Python, PowerShell, C#) and flags the sink mistakes that can be
// seen in code: queries and commands built from strings, raw HTML sinks, evaluated strings,
// unsafe loaders. It cannot prove a sink safe; each sink still needs its hostile-value test
// (docs/24 §5). A line that is safe as written carries `injection: <why>` (for example a constant
// HTML string), and the reason is reviewed like a waiver.
// The same rules for Python projects without Node: templates/tests/test_injection.py.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

// AUDIT_FILES (set by an audit): a text file with one project-relative path a line, the tracked
// files minus vendored folders and minified files, under AUDIT_ROOT (default: the working folder).
// When set, only those files are read.
const pathKey = (p) => { const k = resolve(p).replace(/\\/g, '/'); return process.platform === 'win32' ? k.toLowerCase() : k; };
const AUDIT = process.env.AUDIT_FILES && new Set(readFileSync(process.env.AUDIT_FILES, 'utf8').split(/\r?\n/)
  .map((l) => l.trim()).filter(Boolean).map((l) => pathKey(join(process.env.AUDIT_ROOT || process.cwd(), l))));
const audited = (p) => !AUDIT || AUDIT.has(pathKey(p));

const CONFIG = {
  // The project's source: INJECTION_SRC, else the first of src/, app/, lib/ next to this file's
  // folder, else the project root (the folder above this file's).
  srcDir: process.env.INJECTION_SRC || ['src', 'app', 'lib'].map((d) => join(import.meta.dirname, '..', d)).find((d) => existsSync(d)) || join(import.meta.dirname, '..'),
  // Folders never read (generated or third-party code, and tests, which hold hostile values on purpose).
  skip: /(^|[\\/])(node_modules|dist|build|vendor|\.venv|venv|__pycache__|coverage|tests?|__tests__)([\\/]|$)/,
};

const JS = /\.(m?[jt]sx?|cjs|vue|svelte|astro|html)$/;
const PY = /\.py$/;
const PS = /\.ps(m?1)$/;
const CS = /\.cs$/;
// A query, not a word: SELECT … FROM, INSERT INTO, UPDATE … SET, DELETE FROM (a "select" or
// "where" in prose or markup is not one).
const SQL_WORD = String.raw`\b(?:SELECT\s[^;]*?\bFROM\b|INSERT\s+INTO\b|UPDATE\s+[\w."]+\s+SET\b|DELETE\s+FROM\b)`;

// [id, which files, pattern, what to do instead (docs/24 §2)]
export const RULES = [
  ['sql-join', JS, new RegExp(String.raw`(?<![\w.$])\`[^\`]*${SQL_WORD}[^\`]*\$\{`, 'i'), 'bind parameters; a tagged sql`` helper that binds is fine'],
  ['sql-join', JS, new RegExp(String.raw`(?:"[^"\n]*${SQL_WORD}[^"\n]*"|'[^'\n]*${SQL_WORD}[^'\n]*')\s*\+\s*[\w$(]`, 'i'), 'bind parameters'],
  ['sql-join', PY, new RegExp(String.raw`\.execute(?:many)?\s*\(\s*(?:f["']|["'][^"'\n]*["']\s*(?:%|\.format\b|\+))`), 'pass parameters as the second argument'],
  ['sql-join', CS, /new\s+(?:Sql|Npgsql|Sqlite|MySql)Command\s*\(\s*(?:\$"|"[^"\n]*"\s*\+)/, 'use command.Parameters'],
  ['query-object', JS, /\.(?:find|findOne|findMany|updateOne|updateMany|deleteOne|deleteMany|where)\s*\(\s*req\.(?:body|query|params)\s*[),]/, 'build the filter from typed values'],
  ['raw-html', JS, /\.(?:innerHTML|outerHTML)\s*\+?=\s*(?!\s*(?:'[^'$]*'|"[^"$]*"|`[^`$]*`)\s*[;\n])/, 'textContent, or an allow-list sanitiser'],
  ['raw-html', JS, /\b(?:insertAdjacentHTML|document\.write(?:ln)?)\s*\(/, 'insertAdjacentText / DOM nodes'],
  ['raw-html', JS, /dangerouslySetInnerHTML\s*=\s*\{\{\s*__html\s*:\s*(?![^}]*(?:sanitiz|purif))/i, 'render text, or sanitise with an allow-list first'],
  ['raw-html', JS, /\sv-html\s*=|\{@html\s/, 'text binding, or sanitise with an allow-list first'],
  ['eval', JS, /(?<![\w.$])eval\s*\(|\bnew\s+Function\s*\(|\bset(?:Timeout|Interval)\s*\(\s*['"`]/, 'data is data: parse it, never run it'],
  ['eval', PY, /(?<![\w.])(?:eval|exec)\s*\(/, 'ast.literal_eval for literals; never run input'],
  ['shell', JS, /\bexec(?:Sync)?\s*\(\s*(?:`[^`]*\$\{|[^)\n]*\+)/, 'execFile / spawn with an argument array'],
  ['shell', JS, /\bshell\s*:\s*true\b/, 'spawn without a shell'],
  ['shell', PY, /\bshell\s*=\s*True\b|\bos\.(?:system|popen)\s*\(/, 'subprocess.run([...]) without a shell'],
  ['shell', PS, /(?<![\w-])(?:Invoke-Expression|iex)(?![\w-])/i, 'call the command with parameters or splatting'],
  ['path', JS, /\b(?:readFile|readFileSync|createReadStream|sendFile|writeFile|writeFileSync|unlink|rm)\s*\([^)\n]*\breq\.(?:query|params|body)/, 'resolve, then require the result inside the allowed base'],
  ['path', PY, /\bopen\s*\([^)\n]*\brequest\.(?:args|form|query_params|path_params|json)/, 'resolve, then require the result inside the allowed base'],
  ['redirect', JS, /\.redirect\s*\(\s*(?:\d+\s*,\s*)?req\.(?:query|body|params)/, 'a relative path or an allow-listed host'],
  ['regex-input', JS, /\bnew\s+RegExp\s*\(\s*(?!['"`/])[\w$.]+\s*[,)]/, 'escape the text first, or match with includes()'],
  ['deserialise', PY, /\bpickle\.loads?\s*\(|\byaml\.(?:unsafe_load|load)\s*\((?![^)]*SafeLoader)/, 'JSON with a schema; yaml.safe_load'],
  ['deserialise', CS, /\bnew\s+BinaryFormatter\s*\(|\bTypeNameHandling\.(?:All|Auto|Objects)\b/, 'System.Text.Json with known types'],
];

/** Findings for one file: "line [id] what to do". Comments are read too: a pattern in a comment
 *  is rare, and the marker clears it. */
export function injectionFindings(file, text) {
  const out = [];
  const lines = text.split('\n');
  for (const [id, files, re, fix] of RULES) {
    if (!files.test(file)) continue;
    const g = new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g');
    for (const m of text.matchAll(g)) {
      const line = text.slice(0, m.index).split('\n').length;
      if (/injection:/.test(lines[line - 1])) continue;
      out.push(`${line} [${id}] ${fix}`);
    }
  }
  return out;
}

const walk = (dir) => (existsSync(dir) ? readdirSync(dir, { recursive: true, encoding: 'utf8' }) : [])
  .filter((f) => !CONFIG.skip.test(f) && !/\.test\.|(^|[\\/])test_/.test(f) && [JS, PY, PS, CS].some((r) => r.test(f)) && audited(join(dir, f)));

test('no injection sink built from strings in the source', () => {
  const bad = walk(CONFIG.srcDir).flatMap((f) => injectionFindings(f, readFileSync(join(CONFIG.srcDir, f), 'utf8')).map((x) => `${f}:${x}`));
  assert.deepEqual(bad, []);
});

test('each injection rule catches its case and leaves the safe form alone (the check itself works)', () => {
  const ids = (file, text) => injectionFindings(file, text).map((x) => x.match(/\[([\w-]+)\]/)[1]);
  const cases = [
    ['db.ts', 'db.query(`SELECT * FROM users WHERE id = ${id}`)', ['sql-join']],
    ['db.ts', 'db.query(sql`SELECT * FROM users WHERE id = ${id}`)', []],
    ['db.ts', 'db.query("SELECT * FROM users WHERE id = $1", [id])', []],
    ['db.js', 'q = "SELECT * FROM t WHERE name = \'" + name + "\'"', ['sql-join']],
    ['db.py', 'cur.execute(f"SELECT * FROM t WHERE id = {x}")', ['sql-join']],
    ['db.py', 'cur.execute("SELECT * FROM t WHERE id = %s", (x,))', []],
    ['Repo.cs', 'var c = new SqlCommand($"SELECT * FROM t WHERE id = {id}", conn);', ['sql-join']],
    ['api.js', 'const u = await User.findOne(req.body);', ['query-object']],
    ['view.js', 'el.innerHTML = comment.text;', ['raw-html']],
    ['view.js', "el.innerHTML = '';\nel.textContent = comment.text;", []],
    ['View.tsx', '<div dangerouslySetInnerHTML={{ __html: post.body }} />', ['raw-html']],
    ['View.tsx', '<div dangerouslySetInnerHTML={{ __html: sanitize(post.body) }} />', []],
    ['Note.vue', '<p v-html="note.body"></p>', ['raw-html']],
    ['calc.js', 'const r = eval(input);', ['eval']],
    ['calc.js', 'const r = JSON.parse(input);', []],
    ['git.js', 'execSync(`git log ${branch}`)', ['shell']],
    ['git.js', "execFileSync('git', ['log', '--', branch])", []],
    ['git.js', "spawn(cmd, args, { shell: true })", ['shell']],
    ['run.py', 'subprocess.run(cmd, shell=True)', ['shell']],
    ['run.py', "subprocess.run(['git', 'log', '--', branch])", []],
    ['run.ps1', 'Invoke-Expression "git log $branch"', ['shell']],
    ['run.ps1', '& git log -- $branch', []],
    ['files.js', "res.sendFile(path.join(root, req.query.file))", ['path']],
    ['go.js', 'res.redirect(req.query.next)', ['redirect']],
    ['find.js', 'const re = new RegExp(term, "i");', ['regex-input']],
    ['find.js', 'const re = new RegExp(escapeRegExp(term), "i");', []],
    ['load.py', 'data = yaml.load(f)', ['deserialise']],
    ['load.py', 'data = yaml.load(f, Loader=yaml.SafeLoader)', []],
    ['load.py', 'obj = pickle.loads(blob)', ['deserialise']],
    ['view.js', "el.innerHTML = template; // injection: template is a constant built above", []],
  ];
  for (const [file, text, want] of cases) assert.deepEqual(ids(file, text), want, `${file}: ${text}`);
});
