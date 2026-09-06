// Independent ECMAScript numeric oracle. Inputs are generated finite JSON numbers.
// This is not used to parse untrusted objects or certify duplicate-key rejection.
const readline = require('node:readline');
const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on('line', line => {
  const value = JSON.parse(line);
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error('Expected finite number');
  process.stdout.write(JSON.stringify(value) + '\n');
});
