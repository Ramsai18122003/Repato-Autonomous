# Local quality checks

PowerShell 7 runner for explicitly selected files only. Reports are written under this directory's ignored `output/` folder. Analysis reads source files and does not rewrite them. QA, agent implementation, deployment, and task-store paths are rejected.

Prerequisites already present on the machine: PowerShell 7, PSScriptAnalyzer 1.25.0, WSL Ubuntu, and Semgrep at `/home/rsgud/semgrep-env/bin/semgrep`. The runner calls that explicit Linux executable through `wsl.exe --distribution Ubuntu --exec`; it does not depend on WSL's `PATH`. Override with `-SemgrepExecutable /path/in/wsl` and `-WslDistribution <name>` when needed. The runner does not install or download tools or rules. Semgrep rules are local in `semgrep-rules.yml`.

PSScriptAnalyzer is discovered through PowerShell's normal module paths. If a nested `pwsh -NoProfile` process cannot see a trusted installation discovered by the caller, pass its module directory (the directory containing `PSScriptAnalyzer.psd1`) with `-PSScriptAnalyzerModulePath`. The path is used only by that quality-check process; the runner does not alter persistent `PSModulePath` or install modules. Missing or invalid modules remain scanner errors and fail the check.

From the repository root, select exact paths:

```powershell
pwsh -NoProfile -File .\productivity-test\quality-check\Invoke-LocalQualityCheck.ps1 -Path .\ConnectorServer.cs
$analyzer = Get-Module -ListAvailable PSScriptAnalyzer | Where-Object Version -eq ([version]'1.25.0') | Select-Object -First 1
pwsh -NoProfile -File .\productivity-test\quality-check\Invoke-LocalQualityCheck.ps1 -Path .\Test.ps1 -PSScriptAnalyzerModulePath $analyzer.ModuleBase
pwsh -NoProfile -File .\productivity-test\quality-check\Invoke-LocalQualityCheck.ps1 -Path .\some-directory
pwsh -NoProfile -Command '& .\productivity-test\quality-check\Invoke-LocalQualityCheck.ps1 -Path @(".\ConnectorServer.cs", ".\FormaApplication.cs")'
```

Codex and Ralph workflows should invoke the same command with the specific files changed in the task, for example:

```powershell
pwsh -NoProfile -File .\productivity-test\quality-check\Invoke-LocalQualityCheck.ps1 -Path .\ConnectorServer.cs
```

Exit code is zero only on PASS. Rule findings produce scanner status `FAIL` with locations and severities; missing tools, invalid rule output, and scanner crashes produce status `ERROR` with diagnostics. Both lead to overall FAIL. `-OutputDirectory` may choose a subdirectory under `productivity-test\quality-check\output` only. PowerShell-only selections do not invoke Semgrep; `-SkipSemgrep` is recorded as SKIPPED and does not yield an overall PASS for Semgrep-supported files.

Focused tests cover explicit selection and de-duplication, protected path rejection, missing selections and tools, scanner errors versus findings, spaced-path argument preservation, report contents, and source immutability:

```powershell
pwsh -NoProfile -File .\productivity-test\quality-check\Test-LocalQualityCheck.ps1
```

Verify the local rule file without network access:

```powershell
wsl.exe --distribution Ubuntu --exec /home/rsgud/semgrep-env/bin/semgrep --validate --config /mnt/c/Repato-Autonomous/ProductivityPilot/productivity-test/quality-check/semgrep-rules.yml
```
