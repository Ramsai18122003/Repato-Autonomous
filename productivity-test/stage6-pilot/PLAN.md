# Stage 6 Pilot Plan: Local label normalizer

## Goal
Add a dependency-free helper that turns a user supplied label into a stable lowercase slug, and verify the behavior with focused local tests.

## Scope and boundary
This is a disposable workflow pilot under `productivity-test/stage6-pilot/`. It does not initialize or modify the production GSD roadmap. No production source, agent configuration, QA path, or deployment artifact is in scope.

## Requirement
- **PILOT-01:** `normalizeLabel(value)` trims and lowercases text, replaces each run of non-ASCII letters or digits with one hyphen, removes leading/trailing hyphens, and returns `untitled` when no letters or digits remain. Non-string inputs throw `TypeError`.

## Task
1. Implement the Node.js helper with CommonJS export.
2. Add dependency-free Node assertions for normal input, punctuation/spacing, empty normalized output, and invalid input.
3. Add a PowerShell 7 entry point that runs those tests and propagates failures.

## Acceptance checks
- `node .\test\normalize-label.test.js` passes and checks each requirement.
- `pwsh -NoProfile -File .\Test-Pilot.ps1` passes.
- Stage 4 scans the PowerShell entry point with PSScriptAnalyzer and JavaScript files with local Semgrep.
- Stage 5 reviews only the three pilot implementation/test files and returns PASS.

## Execution limit
One Codex implementation iteration only; no automatic retry. All task files and generated evidence remain under this pilot directory. A missing Ralph runner must be recorded as an orchestration limitation, not represented as a successful Ralph run.
