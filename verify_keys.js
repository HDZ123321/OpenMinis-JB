// Checks that every AppLocalized("...") key used by the jailbreak layer
// exists in Localizable.xcstrings with zh-Hans and zh-Hant values.
const fs = require('fs');
const path = require('path');

const dir = 'src/ios/Views/Chat/AIChatView/Jailbreak';
const keys = new Set();

for (const file of fs.readdirSync(dir)) {
  if (!file.endsWith('.swift')) continue;
  const src = fs.readFileSync(path.join(dir, file), 'utf8');
  const re = new RegExp('AppLocalized\\(\\s*"((?:[^"\\\\]|\\\\.)*)"', 'g');
  let m;
  while ((m = re.exec(src)) !== null) keys.add(m[1].replace(/\\"/g, '"'));
}

const xc = JSON.parse(fs.readFileSync('src/ios/Localizable.xcstrings', 'utf8'));
const missing = [];
const noZh = [];

for (const k of [...keys].sort()) {
  const entry = xc.strings[k];
  if (!entry) { missing.push(k); continue; }
  const loc = entry.localizations || {};
  for (const lang of ['zh-Hans', 'zh-Hant']) {
    const unit = loc[lang] && loc[lang].stringUnit;
    if (!unit || !unit.value) noZh.push(k + ' [' + lang + ']');
  }
}

console.log('keys used:', keys.size);
console.log('missing in xcstrings:', missing.length);
missing.forEach((k) => console.log('  MISSING:', k));
console.log('missing zh:', noZh.length);
noZh.forEach((k) => console.log('  NOZH:', k));

// Exit non-zero so CI fails on a key that would silently render in English.
if (missing.length || noZh.length) process.exitCode = 1;
