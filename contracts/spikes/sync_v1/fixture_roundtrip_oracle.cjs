// ECMAScript's specified binary64 JSON number rendering is the independent
// oracle for fixture transport. This is never a product serializer.
const fs = require('fs');
function canonical(v) {
  if (Array.isArray(v)) return '[' + v.map(canonical).join(',') + ']';
  if (v !== null && typeof v === 'object') {
    return '{' + Object.keys(v).sort().map(k => JSON.stringify(k) + ':' + canonical(v[k])).join(',') + '}';
  }
  return JSON.stringify(v);
}
const rows = JSON.parse(fs.readFileSync(0, 'utf8'));
process.stdout.write(JSON.stringify(rows.map(raw => Buffer.from(canonical(JSON.parse(raw)), 'utf8').toString('hex'))));
