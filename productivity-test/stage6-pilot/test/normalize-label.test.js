'use strict';

const assert = require('node:assert/strict');
const { normalizeLabel } = require('../src/normalize-label');

assert.equal(normalizeLabel('  Pilot Task  '), 'pilot-task');
assert.equal(normalizeLabel('Stage 6 / End-to-End!'), 'stage-6-end-to-end');
assert.equal(normalizeLabel('--- !!!'), 'untitled');
assert.throws(() => normalizeLabel(null), TypeError);
console.log('PASS: 4 normalizeLabel behavior assertions.');
