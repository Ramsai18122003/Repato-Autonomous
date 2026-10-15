'use strict';

const assert = require('node:assert/strict');
const rotateTextByCodePoint = require('../src/rotate-text-by-code-point');

assert.equal(rotateTextByCodePoint('abcdef', 2), 'cdefab');
assert.equal(rotateTextByCodePoint('abcdef', 8), 'cdefab');
assert.equal(rotateTextByCodePoint('abcdef', -2), 'efabcd');
assert.equal(rotateTextByCodePoint('A😀BC', 2), 'BCA😀');
assert.equal(rotateTextByCodePoint('', 123), '');
assert.throws(() => rotateTextByCodePoint(42, 0), TypeError);
assert.throws(() => rotateTextByCodePoint('abc', 1.5), RangeError);
assert.throws(() => rotateTextByCodePoint('abc', Number.MAX_SAFE_INTEGER + 1), RangeError);
