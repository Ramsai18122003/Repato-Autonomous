One bounded Ralph-style iteration (iteration 1 of 1). Implement only the task in PLAN.md, only under this isolated pilot directory. Create:
- src/normalize-label.js with the specified normalizeLabel function and CommonJS export.
- test/normalize-label.test.js using only Node's built-in assert module as a direct script, with no worker subprocess.
- Test-Pilot.ps1, a PowerShell 7 entry point that invokes the Node test file and returns a failing exit code when tests fail.

Constraints: no dependencies, no network, no writes outside this directory, no production/agent/QA/deployment changes, no commits. Do not change Codex, Ralph, approval, sandbox, or hook settings. Keep this to one implementation pass. Verify the generated files exist and summarize their paths; the caller will run the checks.
