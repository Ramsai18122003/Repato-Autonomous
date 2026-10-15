'use strict';

function rotateTextByCodePoint(text, offset) {
  if (typeof text !== 'string') {
    throw new TypeError('text must be a string');
  }
  if (!Number.isSafeInteger(offset)) {
    throw new RangeError('offset must be a safe integer');
  }

  const codePoints = Array.from(text);
  if (codePoints.length === 0) {
    return '';
  }

  const rotation = ((offset % codePoints.length) + codePoints.length) % codePoints.length;
  return codePoints.slice(rotation).concat(codePoints.slice(0, rotation)).join('');
}

module.exports = rotateTextByCodePoint;
