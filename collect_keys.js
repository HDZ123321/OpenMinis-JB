const fs = require('fs');
const path = require('path');

const dir = 'src/ios/Views/Chat/AIChatView/Jailbreak';
const files = fs.readdirSync(dir).filter(f => f.endsWith('.swift'));

const keys = new Set();
for (const f of files) {
  const src = fs.readFileSync(path.join(dir, f), 'utf8');
  const re = /AppLocalized\(\s*"((?:[^"\\]|\\.)*)"/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    keys.add(m[1].replace(/\\"/g, '"'));
  }
}
console.log(keys.size + ' keys');
for (const k of [...keys].sort()) console.log('  ' + k);
