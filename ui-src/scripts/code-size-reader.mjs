// Dependency-free JS/TS/JSX function reader: function spans, lines and cyclomatic complexity, counted
// the way ESLint's max-lines-per-function (skipBlankLines, skipComments) and complexity rules count
// them. Copy to scripts/code-size-reader.mjs beside check-code-size.mjs: it measures there when ESLint
// or its TypeScript parser cannot run (TypeScript 7 has no JS API for the parser; a test audit,
// 24 Nov 2026). Also this repo's own ratchet (sync/code-size.mjs). Per file it lands within a few
// counts of ESLint, not on it (what still differs: docs/18 §5, a test audit, 24 Nov 2026), so a
// baseline written by one reader is compared with the same reader.
//
// It reads TypeScript types (return types, parameter and variable annotations, type aliases,
// interfaces, generics, `as`) as types: a function type is not a function and a `?` in a type is not
// a branch. JSX is read as JSX: its text and its `/>` and `</tag>` are not code.

// ---------- tokenizer: identifiers, punctuators, one token per string / regex / template part ----------
const PUNCT = ['>>>=', '...', '===', '!==', '**=', '<<=', '>>=', '>>>', '&&=', '||=', '??=', '=>', '==', '!=',
  '<=', '>=', '&&', '||', '??', '?.', '++', '--', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '**', '<<', '>>'];
const REGEX_AFTER = new Set(['(', ',', '=', ':', '[', '!', '&', '|', '?', '{', '}', ';', '+', '-', '*', '%', '<', '>',
  '~', '^', '=>', '&&', '||', '??', '==', '===', '!=', '!==', '+=', '-=', 'return', 'typeof', 'case', 'do', 'else',
  'in', 'of', 'new', 'delete', 'void', 'throw', 'instanceof', 'yield', 'await', '...']);
// Where a `<` starts a JSX element rather than comparing or opening type arguments.
const JSX_AFTER = new Set(['(', ',', '=', ':', '[', '!', '?', '{', ';', '=>', '&&', '||', '??', 'return', 'default',
  'yield', 'await', 'case']);

const prevTok = (s) => (s.toks.length ? s.toks[s.toks.length - 1].v : ';');
// nl: a line break since the previous token (a statement may end there, ASI); tpl: how deep inside
// template ${ } expressions and JSX elements the token is; end: the line its text ends on.
const push = (s, v) => {
  s.toks.push({ v, line: s.line, end: s.line, nl: s.nl, tpl: s.tpl.length + s.jsx });
  s.code.add(s.line);
  s.nl = false;
};
const endLast = (s) => { if (s.toks.length) s.toks[s.toks.length - 1].end = s.line; };
// Moves to `to`; with `text`, every line that holds a visible character of the skipped text is a code
// line (a string, template or JSX text line is not blank to ESLint).
const advance = (s, to, text = false) => {
  for (let k = s.i; k < to && k < s.src.length; k++) {
    if (s.src[k] === '\n') s.line++;
    else if (text && !/\s/.test(s.src[k])) s.code.add(s.line);
  }
  s.i = Math.min(to, s.src.length);
};
// Skips to the char after the closing quote (or the line end for a broken string).
function skipQuoted(s, quote) {
  let k = s.i + 1;
  while (k < s.src.length && s.src[k] !== quote && s.src[k] !== '\n') k += s.src[k] === '\\' ? 2 : 1;
  advance(s, k + 1, true);
}
// Inside a template literal: to the closing backtick, or into a ${ expression.
function templatePart(s) {
  let k = s.i;
  while (k < s.src.length && s.src[k] !== '`' && !(s.src[k] === '$' && s.src[k + 1] === '{')) k += s.src[k] === '\\' ? 2 : 1;
  const open = s.src[k] === '$';
  advance(s, k + (open ? 2 : 1), true);
  endLast(s);
  if (open) { s.depth++; s.tpl.push(s.depth); }
}
function skipRegex(s) {
  let k = s.i + 1, inClass = false;
  while (k < s.src.length && s.src[k] !== '\n' && (inClass || s.src[k] !== '/')) {
    if (s.src[k] === '[') inClass = true; else if (s.src[k] === ']') inClass = false;
    k += s.src[k] === '\\' ? 2 : 1;
  }
  k++;
  while (/[a-z]/i.test(s.src[k] || '')) k++;
  advance(s, k, true);
}
function lineComment(s) {
  const e = s.src.indexOf('\n', s.i);
  advance(s, e < 0 ? s.src.length : e);
}
function blockComment(s) {
  const e = s.src.indexOf('*/', s.i + 2), to = e < 0 ? s.src.length : e + 2;
  if (s.src.slice(s.i, to).includes('\n')) s.nl = true;
  advance(s, to);
}
const word = (s, re) => { let k = s.i; while (k < s.src.length && re.test(s.src[k])) k++; const v = s.src.slice(s.i, k); s.i = k; return v; };

// ---------- JSX: elements, attributes, children text, { } expressions ----------
const TAG = /<(?:(>)|([A-Za-z_$][\w$.:-]*)\s*(\S))/y;
// A `<` in expression position opens JSX: a fragment, a tag followed by an attribute, `/>` or `{`, or
// `<Name>` whose `</Name>` follows. `<T,>`, `<T extends U>` and a `<T>` with no closing tag are type
// parameters or an assertion.
function jsxStarts(s) {
  if (!JSX_AFTER.has(prevTok(s))) return false;
  TAG.lastIndex = s.i;
  const mt = TAG.exec(s.src);
  if (!mt) return false;
  if (mt[1]) return true;
  if (s.src.startsWith('extends', TAG.lastIndex - 1)) return false;
  if (mt[3] === '/' || mt[3] === '{' || /[A-Za-z_$]/.test(mt[3])) return true;
  return mt[3] === '>' && s.src.includes(`</${mt[2]}>`, s.i);
}
function skipTypeArguments(s) {
  let depth = 0, k = s.i;
  do { depth += s.src[k] === '<' ? 1 : s.src[k] === '>' ? -1 : 0; k++; } while (k < s.src.length && depth > 0);
  advance(s, k, true);
}
function jsxContainer(s) {
  s.depth++;
  push(s, '{');
  s.i++;
  run(s, s.depth);
}
// One piece of an opening tag: an { } expression, a quoted value, an element as a value, or one char.
function jsxAttributePiece(s, c) {
  const d = s.src[s.i + 1];
  if (c === '/' && d === '/') lineComment(s); // comments may sit between attributes
  else if (c === '/' && d === '*') blockComment(s);
  else if (c === '{') jsxContainer(s);
  else if (c === '<') jsxElement(s);
  else if (c === '"' || c === "'") {
    const e = s.src.indexOf(c, s.i + 1);
    advance(s, e < 0 ? s.src.length : e + 1, true);
  } else advance(s, s.i + 1, true);
}
/** The opening tag's attributes; true when it closes itself (`/>`). */
function jsxAttributes(s) {
  while (s.i < s.src.length) {
    const c = s.src[s.i];
    if (c === '/' && s.src[s.i + 1] === '>') { advance(s, s.i + 2, true); return true; }
    if (c === '>') { advance(s, s.i + 1, true); return false; }
    jsxAttributePiece(s, c);
  }
  return true;
}
function jsxChildren(s) {
  while (s.i < s.src.length) {
    if (s.src.startsWith('</', s.i)) {
      const e = s.src.indexOf('>', s.i);
      advance(s, e < 0 ? s.src.length : e + 1, true);
      return;
    }
    const c = s.src[s.i];
    if (c === '{') jsxContainer(s);
    else if (c === '<') jsxElement(s);
    else advance(s, s.i + 1, true);
  }
}
// The element is one bracket pair of tokens (<jsx ... jsx>) around the tokens of its { } expressions.
function jsxElement(s) {
  push(s, '<jsx');
  s.jsx++;
  s.i++;
  word(s, /[\w$.:-]/);
  if (s.src[s.i] === '<') skipTypeArguments(s);
  if (!jsxAttributes(s)) jsxChildren(s);
  s.jsx--;
  push(s, 'jsx>');
}

const punctAt = (s) => {
  const p = PUNCT.find((x) => s.src.startsWith(x, s.i)) || s.src[s.i];
  return p === '?.' && /[0-9]/.test(s.src[s.i + 2] || '') ? '?' : p; // a ?.5 : b is a ternary
};
const HANDLERS = [
  [(c) => /\s/.test(c), (s) => { if (s.src[s.i] === '\n') s.nl = true; advance(s, s.i + 1); }],
  [(c, d) => c === '/' && d === '/', lineComment],
  [(c, d) => c === '/' && d === '*', blockComment],
  [(c) => c === '"' || c === "'", (s) => { push(s, '"s"'); skipQuoted(s, s.src[s.i]); endLast(s); }],
  [(c) => c === '`', (s) => { push(s, '`'); s.i++; templatePart(s); }],
  [(c, d, s) => c === '/' && REGEX_AFTER.has(prevTok(s)), (s) => { push(s, '/re/'); skipRegex(s); endLast(s); }],
  [(c) => /[A-Za-z_$]/.test(c), (s) => push(s, word(s, /[\w$]/))],
  [(c, d) => /[0-9]/.test(c) || (c === '.' && /[0-9]/.test(d || '')), (s) => { word(s, /[\w.]/); push(s, '0'); }],
  [(c) => c === '{', (s) => { s.depth++; push(s, '{'); s.i++; }],
  [(c, d, s) => c === '}' && s.tpl.length && s.tpl[s.tpl.length - 1] === s.depth,
    (s) => { s.tpl.pop(); s.depth--; s.i++; push(s, '`'); templatePart(s); }],
  [(c) => c === '}', (s) => { s.depth--; push(s, '}'); s.i++; }],
  [(c, d, s) => c === '<' && jsxStarts(s), jsxElement],
  [() => true, (s) => { const p = punctAt(s); push(s, p); s.i += p.length; }],
];

// Reads tokens until the source ends, or until the `}` that closes brace depth `stop` (a JSX { }).
function run(s, stop) {
  while (s.i < s.src.length) {
    const c = s.src[s.i], d = s.src[s.i + 1];
    if (c === '}' && s.depth === stop) { s.depth--; push(s, '}'); s.i++; return; }
    HANDLERS.find(([test]) => test(c, d, s))[1](s);
  }
}
function scan(src) {
  const s = { src, i: 0, line: 1, depth: 0, tpl: [], jsx: 0, toks: [], nl: false, code: new Set() };
  run(s, -1);
  return s;
}
export const tokenize = (src) => scan(src).toks;

// ---------- brackets ----------
// No prototype: a plain object made a `toString` or `constructor` token an opening bracket, which
// shifted every pair after it and hid the file's later functions (a test audit, 24 Nov 2026).
const table = (o) => Object.assign(Object.create(null), o);
const OPEN = table({ '(': ')', '[': ']', '{': '}', '<jsx': 'jsx>' });
const CLOSE = new Set(Object.values(OPEN));
// match: the other bracket of each pair (-1 for none); parent: the innermost open bracket around each token.
function brackets(toks) {
  const match = new Array(toks.length).fill(-1), parent = new Array(toks.length).fill(-1), stack = [];
  toks.forEach((t, i) => {
    if (CLOSE.has(t.v) && stack.length) { const o = stack.pop(); match[o] = i; match[i] = o; }
    parent[i] = stack.length ? stack[stack.length - 1] : -1;
    if (OPEN[t.v]) stack.push(i);
  });
  return { match, parent };
}
const isIdent = (v) => /^[A-Za-z_$][\w$]*$/.test(v || '');
const tok = (c, i) => (i >= 0 && c.toks[i] ? c.toks[i].v : undefined);

// ---------- types: what a type annotation, alias or interface covers ----------
const ANGLE = table({ '<': 1, '>': -1, '>>': -2, '>>>': -3 });
/** The `>` that closes the `<` at j, or -1 when it is a comparison. */
function angleEnd(c, j) {
  let depth = 0;
  for (let k = j; k < c.toks.length && k < j + 400; k++) {
    const t = c.toks[k].v;
    if (OPEN[t] && c.m[k] > k) { k = c.m[k]; continue; }
    if (CLOSE.has(t) || t === ';') return -1;
    depth += ANGLE[t] || 0;
    if (depth <= 0) return k;
  }
  return -1;
}
// Tokens that need a type after them, inside a type.
const TYPE_OPS = new Set(['|', '&', '=>', 'keyof', 'typeof', 'readonly', 'unique', 'infer', 'extends', '?', ':', '.',
  'is', 'asserts', 'new', 'abstract', '-', '+', '...']);
/** One step through a type from token j: [the next index, whether a type must follow], or null at its end.
 *  `operand`: a type must come here, so a ( or { opens one (else a { is the body after a return type). */
function typeStep(c, j, operand) {
  const v = c.toks[j].v;
  if (v === '<') { const e = angleEnd(c, j); return e < 0 ? null : [e + 1, false]; }
  if (v === '[' || ((v === '(' || v === '{') && operand)) return c.m[j] < 0 ? null : [c.m[j] + 1, false];
  if (TYPE_OPS.has(v)) return [j + 1, true];
  return operand ? [j + 1, false] : null;
}
/** The first token after the type that starts at j. In an arrow's return type, `=>` ends it. */
function typeEnd(c, j, arrow) {
  let operand = true;
  while (j < c.toks.length && !(arrow && !operand && c.toks[j].v === '=>')) {
    const next = typeStep(c, j, operand);
    if (!next) return j;
    [j, operand] = next;
  }
  return j;
}
const markTyped = (c, from, to) => { for (let k = from; k <= to; k++) c.typed[k] = 1; };
/** Marks the type after the `:` at k (and an optional `?` or `!` before it). */
function annotation(c, k) {
  const e = typeEnd(c, k + 1, false);
  markTyped(c, tok(c, k - 1) === '?' || tok(c, k - 1) === '!' ? k - 1 : k, e - 1);
}
const MODIFIERS = new Set(['public', 'private', 'protected', 'readonly', 'override', 'static', 'declare', 'abstract', 'accessor']);
// Where a class or object member starts. A method body on the next line also needs one of these
// before the name: `await go(...)` then a `{ }` block on the next line is a call and a block.
const MEMBER_AFTER = new Set(['{', ',', ';', '}', '#', 'static', 'async', 'get', 'set', '*', ...MODIFIERS]);
// A parameter's name sits after ( , ... or a modifier; a destructured one is a { } or [ ] there.
function isParamName(c, k) {
  let p = k - 1;
  if (tok(c, p) === '?') p--;
  const t = tok(c, p);
  const before = isIdent(t) ? tok(c, p - 1) : (t === '}' || t === ']') ? tok(c, c.m[p] - 1) : null;
  return before === '(' || before === ',' || before === '...' || MODIFIERS.has(before);
}
function markParams(c, open) {
  c.params.add(open);
  for (let k = open + 1; k < c.m[open]; k++) {
    if (c.parent[k] === open && c.toks[k].v === ':' && !c.typed[k] && isParamName(c, k)) annotation(c, k);
  }
}
const statementStart = (c, j) => j === 0 || c.toks[j].nl || ['{', '}', ';', 'export', 'declare'].includes(tok(c, j - 1));
function typeAlias(c, j) {
  if (!isIdent(tok(c, j + 1)) || !statementStart(c, j)) return;
  let k = j + 2;
  if (tok(c, k) === '<') k = angleEnd(c, k) + 1;
  if (k > 0 && tok(c, k) === '=') markTyped(c, j, typeEnd(c, k + 1, false) - 1);
}
function interfaceBody(c, j) {
  if (!isIdent(tok(c, j + 1)) || !statementStart(c, j)) return;
  let k = j + 2;
  while (k > 0 && k < c.toks.length && tok(c, k) !== '{' && tok(c, k) !== ';') k = tok(c, k) === '<' ? angleEnd(c, k) + 1 : k + 1;
  if (tok(c, k) === '{' && c.m[k] > k) markTyped(c, j, c.m[k]);
}
// const x: T, const { a = 1 }: P = ..., for (const [k, v = 0] of ...)
function declaration(c, j) {
  let k = j + 1;
  const t = tok(c, k);
  if ((t === '{' || t === '[') && c.m[k] > k) { c.patterns.add(k); k = c.m[k] + 1; } else if (isIdent(t)) k++;
  else return;
  if (tok(c, k) === '!') k++;
  if (tok(c, k) === ':') annotation(c, k);
}
function classBody(c, j) {
  let k = j + 1;
  while (k < c.toks.length && !(tok(c, k) === '{' && c.parent[k] === c.parent[j]) && tok(c, k) !== ';') k++;
  if (tok(c, k) === '{') c.classes.add(k);
}
// A class member's annotation: `name: T`, `name?: T`, `#name!: T` at the start of the member.
function memberAnnotation(c, k) {
  if (!c.classes.has(c.parent[k])) return;
  const p = tok(c, k - 1) === '?' || tok(c, k - 1) === '!' ? k - 2 : k - 1, t = tok(c, p);
  if (!(isIdent(t) || t === '"s"' || t === ']')) return;
  const first = t === ']' ? c.m[p] : p;
  if (c.toks[first].nl || MEMBER_AFTER.has(tok(c, first - 1))) annotation(c, k);
}
// Type arguments of a call: f<T>(...), new Map<K, V>(), tag<T>`...`. A comparison holds an operator.
const NOT_IN_TYPE = new Set(['&&', '||', '??', '==', '===', '!=', '!==', '+', '*', '/', '%', '<=', '>=', ';', '=']);
function typeArguments(c, j) {
  const e = angleEnd(c, j);
  if (e < 0 || !['(', '`'].includes(tok(c, e + 1))) return;
  for (let k = j + 1; k < e; k++) if (NOT_IN_TYPE.has(c.toks[k].v) && c.parent[k] === c.parent[j]) return;
  markTyped(c, j, e);
}

// ---------- functions: declarations, expressions, methods, arrows ----------
const CONTROL = new Set(['if', 'for', 'while', 'switch', 'catch', 'function', 'with', 'return', 'typeof', 'await', 'new',
  'super', 'import', 'else', 'do', 'in', 'of', 'instanceof', 'delete', 'void', 'throw', 'case', 'yield']);
const NOT_METHOD_AFTER = new Set(['.', '?.', 'new', 'function', 'extends', 'implements']);
/** The ( of a header that starts at k (after any type parameters), or -1. */
function paramsAt(c, k) {
  const p = tok(c, k) === '<' ? angleEnd(c, k) + 1 : k;
  return p > 0 && tok(c, p) === '(' && c.m[p] > p ? p : -1;
}
/** From k (after the name): type parameters, the parameters and a return type, then a { body that
 *  `accept(b)` takes; the body's index or -1. An overload or `declare` signature has no body and is no
 *  function, but with `signature` its types are marked: `declare function f(cb: () => void): void;`. */
function header(c, k, accept, signature) {
  const p = paramsAt(c, k);
  if (p < 0) return -1;
  const b = tok(c, c.m[p] + 1) === ':' ? typeEnd(c, c.m[p] + 2, false) : c.m[p] + 1;
  const body = tok(c, b) === '{' && c.m[b] >= 0 && accept(b);
  if (!body && !signature) return -1;
  markTyped(c, k, p - 1);
  markTyped(c, c.m[p] + 1, b - 1);
  markParams(c, p);
  return body ? b : -1;
}
const always = () => true;
function declared(c, i) {
  let j = i + 1;
  if (tok(c, j) === '*') j++;
  const name = isIdent(tok(c, j)) ? c.toks[j++].v : '(anonymous)';
  const body = header(c, j, always, true);
  if (body >= 0) c.spans.push({ name, start: tok(c, i - 1) === 'async' ? i - 1 : i, end: c.m[body], head: i });
}
const methodName = (c, i, before) => !CONTROL.has(c.toks[i].v) && ['(', '<'].includes(tok(c, i + 1)) && !NOT_METHOD_AFTER.has(before);
/** A method: its key runs from token `key` to token i (a name, or a computed [key]), then a header. */
function method(c, i, key) {
  const before = tok(c, key - 1);
  if (!methodName(c, i, before) || (before === '*' && tok(c, key - 2) === 'function')) return; // function* f: declared()
  const member = MEMBER_AFTER.has(before);
  // A class member that starts with a name and ( but has no body is an overload signature.
  const signature = (member || c.toks[key].nl) && c.classes.has(c.parent[key]);
  const body = header(c, i + 1, (b) => member || !c.toks[b].nl, signature);
  if (body >= 0) c.spans.push({ name: key === i ? c.toks[i].v : '[computed]', start: key, end: c.m[body], head: key });
}
/** The `(` at j opens an arrow's parameters when `=>` (or `: Type =>`) follows them. */
function arrowParams(c, j, start) {
  const close = c.m[j];
  if (close < 0) return false;
  let a = close + 1;
  if (tok(c, a) === ':') {
    const e = typeEnd(c, a + 1, true);
    if (tok(c, e) !== '=>') return false;
    markTyped(c, a, e - 1);
    a = e;
  } else if (tok(c, a) !== '=>') return false;
  if (!c.arrows.has(a)) {
    c.arrows.set(a, tok(c, start - 1) === 'async' ? start - 1 : start);
    markParams(c, j);
  }
  return true;
}
// <T,>(x: T): T => ... and <T extends U>(x: T) => ...
function genericArrow(c, j) {
  const e = angleEnd(c, j);
  if (e > 0 && tok(c, e + 1) === '(' && arrowParams(c, e + 1, j)) markTyped(c, j, e);
}
const typeAfter = (c, j) => markTyped(c, j, typeEnd(c, j + 1, false) - 1);
const STEPS = {
  type: typeAlias, interface: interfaceBody, function: declared, class: classBody,
  const: declaration, let: declaration, var: declaration, as: typeAfter, satisfies: typeAfter,
  catch: (c, j) => tok(c, j + 1) === '(' && tok(c, j + 3) === ':' && annotation(c, j + 3),
  ':': memberAnnotation, ']': (c, j) => c.m[j] >= 0 && method(c, j, c.m[j]),
  '(': (c, j) => c.params.has(j) || arrowParams(c, j, j),
  '<': (c, j) => (j === 0 || JSX_AFTER.has(tok(c, j - 1)) ? genericArrow(c, j) : typeArguments(c, j)),
};
// `get type() {`, `{ as(x) {`, `x.as(`: these words also name members.
const CONTEXTUAL = new Set(['type', 'interface', 'as', 'satisfies']);
const memberNamed = (c, j) => CONTEXTUAL.has(c.toks[j].v) && tok(c, j + 1) === '(' && (MEMBER_AFTER.has(tok(c, j - 1)) || ['.', '?.'].includes(tok(c, j - 1)));
function step(c, j) {
  const t = c.toks[j].v;
  if (Object.hasOwn(STEPS, t) && !memberNamed(c, j)) STEPS[t](c, j);
  if (!isIdent(t) || t === 'function' || c.typed[j]) return;
  if (tok(c, j + 1) === '=>') c.arrows.set(j + 1, tok(c, j - 1) === 'async' ? j - 1 : j);
  else method(c, j, j);
}

// Automatic semicolon insertion: in code written without semicolons a line break ends an expression
// body when the line before ends a value and the next line cannot continue it. Without this a
// one-line `const wait = (ms) => new Promise(...)` ran on to the next , ) ] } or ; and measured
// 133 lines (a test audit, 24 Nov 2026).
const STOP = new Set([',', ')', ']', '}', ';']);
const NOT_A_VALUE = new Set(['return', 'typeof', 'new', 'in', 'of', 'instanceof', 'await', 'yield', 'void', 'delete', 'case', 'else', 'do', 'throw', 'async']);
const endsValue = (v) => (isIdent(v) ? !NOT_A_VALUE.has(v) : /^(\)|\]|\}|"s"|0|\/re\/|`|\+\+|--|jsx>)$/.test(v));
const CONTINUES = /^(\.|\?\.|\(|\[|`|=>|!==?|[-+*/%=<>&|^?:,][-+*/%=<>&|^?:!]*|instanceof|in|of|as|satisfies)$/;
const asiEnd = (toks, j, tpl) => toks[j].nl && toks[j].tpl <= tpl && endsValue(toks[j - 1].v) && !CONTINUES.test(toks[j].v);
function expressionEnd(toks, m, k) {
  let j = k;
  const tpl = toks[k] ? toks[k].tpl : 0;
  while (j < toks.length && !STOP.has(toks[j].v) && !(j > k && asiEnd(toks, j, tpl))) j = (OPEN[toks[j].v] && m[j] > 0 ? m[j] : j) + 1;
  return j - 1;
}
function arrowSpan(c, a, start) {
  let n = start - 2;
  while (n > 0 && c.typed[n]) n--;
  const named = tok(c, start - 1) === '=' && isIdent(tok(c, n));
  const end = tok(c, a + 1) === '{' ? c.m[a + 1] : expressionEnd(c.toks, c.m, a + 1);
  return { name: named ? c.toks[n].v : '(arrow)', start: Math.max(0, start), end, head: a };
}

function analyse(toks) {
  const { match, parent } = brackets(toks);
  const c = { toks, m: match, parent, typed: new Uint8Array(toks.length), arrows: new Map(), params: new Set(), patterns: new Set(), classes: new Set(), spans: [] };
  for (let j = 0; j < toks.length; j++) if (!c.typed[j]) step(c, j);
  c.arrows.forEach((start, a) => c.spans.push(arrowSpan(c, a, start)));
  c.spans = c.spans.filter((sp) => sp.end > sp.start).sort((a, b) => a.start - b.start || b.end - a.end);
  return c;
}
export function functionSpans(toks) {
  return analyse(toks).spans.map((sp) => ({ name: sp.name, start: sp.start, end: sp.end, line: toks[sp.head].line }));
}

// ---------- complexity: 1 + each decision point the function owns (nested functions count for themselves) ----------
// As ESLint's complexity rule: if, loops, case, catch, ?:, && || ??, their assignments, ?. and a
// default value (a = 1 in parameters and destructuring).
const DECISION = new Set(['if', 'for', 'while', 'case', 'catch', '&&', '||', '??', '&&=', '||=', '??=', '?.']);
// A default value: an = in a parameter list or a destructuring pattern, through nested { } and [ ].
function isDefault(c, i) {
  for (let p = c.parent[i]; p >= 0; p = c.parent[p]) {
    if (c.params.has(p) || c.patterns.has(p)) return true;
    if (c.toks[p].v !== '{' && c.toks[p].v !== '[') return false;
  }
  return false;
}
function isDecision(c, i) {
  if (c.typed[i]) return false;
  const t = c.toks[i].v, prev = tok(c, i - 1), next = tok(c, i + 1);
  if (t === '?') return ![':', ')', ',', '='].includes(next);
  if (t === '=') return isDefault(c, i);
  if (!DECISION.has(t)) return false;
  return !isIdent(t) || (prev !== '.' && prev !== '?.' && next !== ':');
}
// max-lines-per-function skips an IIFE: (function () { ... })() and (() => { ... })().
const isIIFE = (c, sp) => tok(c, sp.start - 1) === '(' && c.m[sp.start - 1] === sp.end + 1 && tok(c, sp.end + 2) === '(';
function codeLines(code, from, to) {
  let n = 0;
  for (let l = from; l <= to; l++) if (code.has(l)) n++;
  return n;
}
/** Per function: name, line (of its head, as ESLint reports it), complexity, and lines as
 *  max-lines-per-function counts them (0 for an IIFE, which that rule skips). */
export function measureJs(src) {
  const { toks, code } = scan(src);
  const c = analyse(toks), spans = c.spans;
  const out = spans.map((sp) => ({
    name: sp.name, line: toks[sp.head].line, complexity: 1,
    lines: isIIFE(c, sp) ? 0 : codeLines(code, toks[sp.start].line, toks[sp.end].end),
  }));
  const stack = [];
  let next = 0;
  toks.forEach((t, i) => {
    while (stack.length && spans[stack[stack.length - 1]].end < i) stack.pop();
    while (next < spans.length && spans[next].start <= i) stack.push(next++);
    if (stack.length && isDecision(c, i)) out[stack[stack.length - 1]].complexity++;
  });
  return out;
}
