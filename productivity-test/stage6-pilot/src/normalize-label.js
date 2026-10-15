'use strict';

function normalizeLabel(value) {
  if (typeof value !== 'string') {
    throw new TypeError('Label must be a string.');
  }

  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

  return normalized || 'untitled';
}

module.exports = { normalizeLabel };
