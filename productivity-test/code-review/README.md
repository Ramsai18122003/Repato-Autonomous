# Local code review

PowerShell 7 workflow for reviewing only an explicitly selected set of changed files or one clearly named Git diff range. It runs `git diff --check`, flags suspicious credentials, security, deployment, authorization, and protected-path changes for a person, and sends eligible selected files to the Stage 4 PSScriptAnalyzer/Semgrep runner. Scanner errors and findings cannot produce PASS. Reports and synthetic fixtures stay under the ignored `output/` directory.

From the repository root, after a Ralph iteration, select the changed files reported by that iteration:

```powershell
& .\productivity-test\code-review\Invoke-LocalCodeReview.ps1 -Path @('.\ConnectorServer.cs', '.\FormaApplication.cs')
```

Or specify a Git range explicitly:

```powershell
& .\productivity-test\code-review\Invoke-LocalCodeReview.ps1 -DiffRange 'BASE_SHA..HEAD'
```

To review the current working tree relative to HEAD, specify `HEAD` as the range. Do not omit both selection options; the runner never defaults to the whole repository. A selected file must be changed from HEAD. Protected locations are reported as `NEEDS_HUMAN_REVIEW` and are not sent to Stage 4. Review reports are written to `productivity-test\code-review\output\<run-id>\review-report.md` and `.json`.

The result is PASS, FAIL, or NEEDS_HUMAN_REVIEW. PASS means only that these local automated checks passed for the selected changes. It does not authorize merge, deployment, Revit execution, or other protected operations. Heuristics can miss suspicious changes or flag benign ones; a human must inspect the diff and reports.

Run focused regression tests:

```powershell
pwsh -NoProfile -File .\productivity-test\code-review\Test-LocalCodeReview.ps1
```
