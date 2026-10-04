const crypto = require('node:crypto');

// Tanpa huruf/angka yang mirip (0/O, 1/I/L) supaya mudah dibaca kasir.
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

function generateCode(prefix, length = 6) {
  let suffix = '';
  for (let i = 0; i < length; i++) {
    suffix += ALPHABET[crypto.randomInt(ALPHABET.length)];
  }
  return prefix ? `${prefix}-${suffix}` : suffix;
}

module.exports = { generateCode };
