const fs = require('fs');
const BS = String.fromCharCode(92);
const DQ = String.fromCharCode(34);
const SQ = String.fromCharCode(39);

function check(f) {
  const s = fs.readFileSync(f, 'utf8');
  let i = 0, line = 1;
  let inStr = 0; // 0 none, 1 dq, 2 multi-dq, 3 multi-dq-end, 4 sq
  let lineC = false, blkC = false;
  const pairs = { '{': '}', '(': ')', '[': ']' };
  const stack = [];
  let bad = null;
  while (i < s.length) {
    const c = s[i], n = s[i + 1], m = s[i + 2];
    if (c === '\n') { line++; lineC = false; i++; continue; }
    if (lineC) { i++; continue; }
    if (blkC) { if (c === '*' && n === '/') { blkC = false; i += 2; continue; } i++; continue; }
    if (inStr === 1) { if (c === BS) { i += 2; continue; } if (c === DQ) inStr = 0; i++; continue; }
    if (inStr === 2) { if (c === BS) { i += 2; continue; } if (c === DQ) { inStr = 3; } i++; continue; }
    if (inStr === 3) { if (c === DQ && n === DQ) { inStr = 0; i += 2; continue; } if (c === DQ) { inStr = 2; } i++; continue; }
    if (inStr === 4) { if (c === BS) { i += 2; continue; } if (c === SQ) inStr = 0; i++; continue; }
    if (c === '/' && n === '/') { lineC = true; i += 2; continue; }
    if (c === '/' && n === '*') { blkC = true; i += 2; continue; }
    if (c === DQ && n === DQ && m === DQ) { inStr = 2; i += 3; continue; }
    if (c === DQ) { inStr = 1; i++; continue; }
    if (c === SQ) { inStr = 4; i++; continue; }
    if (c === '{' || c === '(' || c === '[') { stack.push({ c, line }); i++; continue; }
    if (c === '}' || c === ')' || c === ']') {
      const top = stack.pop();
      if (!top || pairs[top.c] !== c) { bad = 'MISMATCH ' + c + ' at line ' + line + ' (open ' + (top ? top.c + '@' + top.line : 'none') + ')'; break; }
      i++; continue;
    }
    i++;
  }
  const ok = !bad && stack.length === 0 && inStr === 0;
  console.log(f + ': ' + (ok ? 'OK' : (bad || ('leftover stack=' + stack.length + ' ' + stack.slice(-3).map(x => x.c + '@' + x.line).join(',') + ' inStr=' + inStr))));
  return ok;
}

// Exit non-zero when any file is unbalanced, so CI can gate on this.
const results = process.argv.slice(2).map(check);
if (results.some((ok) => !ok)) process.exitCode = 1;
