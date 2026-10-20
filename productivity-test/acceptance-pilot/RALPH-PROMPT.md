# Ralph task: rotate text by Unicode code point

Implement only this task's two files under `productivity-test/acceptance-pilot/`:

- `src/rotate-text-by-code-point.js`
- `test/rotate-text-by-code-point.test.js`

Export a CommonJS function named `rotateTextByCodePoint(text, offset)`. It must require a string and a safe integer offset, throwing `TypeError` for a non-string and `RangeError` for an unsafe or non-integer offset. Rotate the string's Unicode code points left by `offset`, wrapping offsets modulo the code point count. An empty string returns an empty string for any valid offset. Negative offsets rotate right. Do not split surrogate pairs.

The test file must be a direct Node.js script using only `node:assert/strict` and the new module. Include at least four automated assertions covering ordinary rotation, offset wraparound, negative offset, a supplementary Unicode character (such as an emoji), empty input, and invalid inputs.

Constraints: no packages, network, writes outside `productivity-test/acceptance-pilot/`, production source, protected QA, deployment, or agent directories. Do not modify this prompt, the acceptance script, Ralph/Codex settings, or any other files. Do not commit. Finish by reporting the exact created file paths.
