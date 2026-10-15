[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'Invoke-LocalQualityCheck.ps1'
$source = Get-Content -LiteralPath $scriptPath -Raw
$functionText = $source.Substring($source.IndexOf('function Resolve-QualityFiles'), $source.IndexOf('$repoRoot =') - $source.IndexOf('function Resolve-QualityFiles'))
. ([scriptblock]::Create($functionText))
$script:SupportedSemgrepExtensions = @('.cs', '.go', '.java', '.js', '.py', '.rb', '.ts')
$script:QualityToolRoot = $PSScriptRoot
$script:ProtectedSegments = @('QA', 'AgentOrchestration', 'DeploymentCandidates', 'QaLaunchAgent', '.agent', '.agents', '.claude', '.codex', '.gemini', '.ralph')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$outputRoot = Join-Path $PSScriptRoot 'output'
$fixtures = Join-Path $outputRoot 'test-fixtures'
New-Item -ItemType Directory -Path $fixtures -Force | Out-Null
$spacedFixtures = Join-Path $outputRoot 'test fixtures'
New-Item -ItemType Directory -Path $spacedFixtures -Force | Out-Null
$sourceFile = Join-Path $spacedFixtures 'sample with space.cs'
Set-Content -LiteralPath $sourceFile -Value 'class Sample {}' -Encoding utf8

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "ASSERT: $Message" } }
try {
    $selected = @(Resolve-QualityFiles -InputPath @($sourceFile, $sourceFile) -Root $repoRoot)
    Assert-True ($selected.Count -eq 1) 'Selection must de-duplicate explicit files.'
    $threw = $false
    try { Resolve-QualityFiles -InputPath @('QA\Fixtures') -Root $repoRoot | Out-Null } catch { $threw = $true }
    Assert-True $threw 'Protected QA paths must be rejected.'
    $threw = $false
    try { Resolve-QualityFiles -InputPath @('missing-quality-check-path') -Root $repoRoot | Out-Null } catch { $threw = $true }
    Assert-True $threw 'Missing selections must fail.'
    $reportDir = Join-Path $outputRoot 'synthetic-report-test'
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    $report = [pscustomobject]@{ Status = 'FAIL'; FilesSelected = 1; Scanners = @([pscustomobject]@{ Name='Fake'; Status='ERROR'; Findings=@(); Error='simulated failure' }) }
    $written = Write-QualityReport -Report $report -Directory $reportDir
    Assert-True ((Test-Path $written.Json) -and (Test-Path $written.Text)) 'Both report formats must be written.'
    Assert-True ((Get-Content $written.Text -Raw).Contains('simulated failure')) 'Text report must retain tool errors.'

    $missingTool = Invoke-LocalQualityCheck -SelectedPath @($sourceFile) -RepoRoot $repoRoot -ReportDirectory $outputRoot -SemgrepInvoker {
        param([string[]]$Arguments)
        [pscustomobject]@{ ExitCode = 2; Output = 'simulated missing Semgrep executable' }
    }
    Assert-True ($missingTool.Status -eq 'FAIL' -and $missingTool.Scanners[0].Status -eq 'ERROR' -and $missingTool.Scanners[0].Error.Contains('simulated missing Semgrep executable')) 'Mocked missing scanner must be reported as FAIL without WSL.'
    $failedScan = Invoke-LocalQualityCheck -SelectedPath @($sourceFile) -RepoRoot $repoRoot -ReportDirectory $outputRoot -SemgrepInvoker {
        param([string[]]$Arguments)
        $script:CapturedSemgrepArguments = $Arguments
        [pscustomobject]@{ ExitCode = 2; Output = 'simulated scanner crash' }
    }
    Assert-True ($failedScan.Status -eq 'FAIL' -and $failedScan.Scanners[0].Error.Contains('simulated scanner crash')) 'Scanner failures must be reported as FAIL with diagnostics.'
    $expectedWslPath = ConvertTo-WslPath $sourceFile
    Assert-True ($script:CapturedSemgrepArguments -contains $expectedWslPath) 'Paths containing spaces must remain one WSL argument.'
    $findingPayload = @{ results = @(@{ extra = @{ severity = 'ERROR'; message = 'synthetic finding' }; path = $expectedWslPath; start = @{ line = 7 }; check_id = 'repato.synthetic' }); errors = @() } | ConvertTo-Json -Depth 6 -Compress
    $findingReport = Invoke-LocalQualityCheck -SelectedPath @($sourceFile) -RepoRoot $repoRoot -ReportDirectory $outputRoot -SemgrepInvoker {
        param([string[]]$Arguments)
        [pscustomobject]@{ ExitCode = 1; Output = $findingPayload }
    }
    Assert-True ($findingReport.Status -eq 'FAIL' -and $findingReport.Scanners[0].Status -eq 'FAIL' -and $findingReport.Scanners[0].Findings.Count -eq 1 -and -not $findingReport.Scanners[0].Error) 'Findings must be FAIL with details, distinct from scanner execution errors.'

    $before = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash
    $skipReport = Invoke-LocalQualityCheck -SelectedPath @($sourceFile) -RepoRoot $repoRoot -ReportDirectory $outputRoot -NoSemgrep
    $after = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash
    Assert-True ($before -eq $after) 'Analysis must not modify selected sources.'
    Assert-True ($skipReport.FilesSelected -eq 1) 'Explicit selection count must be reported.'
    Assert-True ((Test-Path $skipReport.ReportJson) -and (Test-Path $skipReport.ReportText)) 'Runner must produce reports.'
    Write-Output 'PASS: selection, protected-path rejection, missing selection, missing tool, scanner failure, report handling, and source read-only checks.'
} finally {
    # Generated test material intentionally remains inside ignored output/ for auditability.
}
