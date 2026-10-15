[CmdletBinding(DefaultParameterSetName = 'Paths')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Paths')][string[]] $Path,
    [Parameter(Mandatory, ParameterSetName = 'Range')][string] $DiffRange,
    [string] $OutputDirectory = (Join-Path $PSScriptRoot 'output'),
    [string] $SemgrepExecutable = '/home/rsgud/semgrep-env/bin/semgrep',
    [string] $WslDistribution = 'Ubuntu',
    [switch] $SkipSemgrep
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Invoke-GitText([string]$Root, [string[]]$Arguments, [int[]]$AllowedExitCodes = @(0)) {
    $text = (& git -C $Root @Arguments 2>&1 | Out-String); $code = $LASTEXITCODE
    if ($code -notin $AllowedExitCodes) { throw "git $($Arguments -join ' ') failed (exit $code): $($text.Trim())" }; return $text
}
function Split-GitPaths([string]$Text) { @($Text -split "`0" | Where-Object { $_ }) }
function ConvertTo-PowerShellLiteral([string]$Value) { "'" + $Value.Replace("'", "''") + "'" }
function Add-Finding($List, [string]$PathValue, [string]$Rule, [string]$Message, [string]$Severity = 'WARNING') { $List.Add([ordered]@{ Path=$PathValue; Severity=$Severity; Rule=$Rule; Message=$Message }) }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$reportRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'output'))
$reportFull = [IO.Path]::GetFullPath($OutputDirectory)
if ($reportFull -ne $reportRoot -and -not $reportFull.StartsWith($reportRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Reports may only be written under $reportRoot" }
$gitRoot = (Invoke-GitText $repoRoot @('rev-parse','--show-toplevel')).Trim()
if ([IO.Path]::GetFullPath($gitRoot) -ne $repoRoot) { throw "Expected repository root '$repoRoot', got '$gitRoot'." }
if ($PSCmdlet.ParameterSetName -eq 'Range') {
    if ($DiffRange -notmatch '^[A-Za-z0-9._/-]+(?:\.\.\.?[A-Za-z0-9._/-]+)?$') { throw 'Use one Git revision or revision range such as HEAD, BASE..HEAD, or BASE...HEAD.' }
    $changedPaths = Split-GitPaths (Invoke-GitText $repoRoot @('diff','--name-only','-z',$DiffRange,'--'))
    $diffCheck = Invoke-GitText $repoRoot @('diff','--check',$DiffRange,'--') @(0,2)
    $diffText = Invoke-GitText $repoRoot @('diff','--no-ext-diff','--unified=0',$DiffRange,'--')
    $rangeLabel = $DiffRange
} else {
    $selected = @($Path | ForEach-Object {
        $full = [IO.Path]::GetFullPath((Join-Path $repoRoot $_)); $rel = [IO.Path]::GetRelativePath($repoRoot,$full)
        if ($rel -eq '..' -or $rel.StartsWith("..$([IO.Path]::DirectorySeparatorChar)") -or [IO.Path]::IsPathRooted($rel)) { throw "Selected path is outside repository: $_" }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Selected path is missing or not a file: $_" }
        $cursor = $repoRoot
        foreach ($segment in ($rel -split '[\\/]')) { $cursor = Join-Path $cursor $segment; $entry = Get-Item -LiteralPath $cursor -ErrorAction Stop; if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Selected path cannot traverse a reparse point: $_" } }
        $rel -replace '\\','/'
    } | Sort-Object -Unique)
    if (-not $selected.Count) { throw 'Explicit selection contains no files.' }
    $tracked = Split-GitPaths (Invoke-GitText $repoRoot @('diff','--name-only','-z','HEAD','--'))
    $untracked = Split-GitPaths (Invoke-GitText $repoRoot @('ls-files','--others','--exclude-standard','-z'))
    foreach ($item in $selected) { if ($item -notin @($tracked + $untracked)) { throw "Selected file is not changed from HEAD: $item" } }
    $changedPaths = $selected
    $diffCheck = Invoke-GitText $repoRoot (@('diff','--check','HEAD','--') + $selected) @(0,2)
    $diffText = Invoke-GitText $repoRoot (@('diff','--no-ext-diff','--unified=0','HEAD','--') + $selected)
    foreach ($item in $selected | Where-Object { $_ -in $untracked }) {
        $newText = Get-Content -LiteralPath (Join-Path $repoRoot $item) -Raw
        foreach ($line in ($newText -split "`r?`n")) { if ($line -match '[\t ]+$') { $diffCheck += "`n${item}: trailing whitespace in untracked file" } }
        $diffText += "`n+++ b/$item`n" + (($newText -split "`r?`n" | ForEach-Object { "+$_" }) -join "`n")
    }
    $rangeLabel = 'HEAD'
}
$changedPaths = @($changedPaths | Sort-Object -Unique)
if (-not $changedPaths.Count) { throw 'The selection or Git diff range contains no changed files.' }
$findings = [System.Collections.Generic.List[object]]::new()
$protected = @('QA','AgentOrchestration','DeploymentCandidates','QaLaunchAgent','.agent','.agents','.claude','.codex','.gemini','.ralph')
$scannerFiles = [System.Collections.Generic.List[string]]::new()
foreach ($item in $changedPaths) {
    $segments = $item -split '[\\/]'
    if ($segments | Where-Object { $_ -in $protected }) { Add-Finding $findings $item 'protected-path' 'Touches a protected QA, orchestration, deployment, or agent-control path.' 'HUMAN_REVIEW' }
    else { $scannerFiles.Add($item) }
    if ($item -match '(?i)(secret|credential|token|password|private.?key|deploy|installer|manifest|authorization|approval|trust|sandbox)') { Add-Finding $findings $item 'sensitive-path' 'Path suggests credentials, security, deployment, or authorization controls.' 'HUMAN_REVIEW' }
}
$patterns = [ordered]@{
 'credential-material'='(?i)(-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|(?:password|passwd|client_secret|api[_-]?key)\s*[:=]\s*["''][^"'']{6,})'
 'security-or-authorization'='(?i)(BypassExecutionPolicy|ExecutionPolicy\s+Unrestricted|TrustServerCertificate\s*=\s*true|AllowUntrusted|SkipCertificate|DisableTLS|\b(?:Authorize|ApprovalRequired|RequireApproval|Sandbox|Trust)\w*\s*=\s*\$false)'
 'deployment-mechanism'='(?i)(\b(?:Copy-Item|Move-Item|robocopy|xcopy)\b.{0,100}(?:Program Files|Revit|Addins|DeploymentCandidates)|\b(?:deploy|install)\w*\s*[:=]\s*(?:true|1)|\bStart-Process\b.{0,100}(?:Revit|LaunchAgent))'
}
 $currentDiffPath = '(diff)'
foreach ($line in ($diffText -split "`r?`n")) {
 if ($line.StartsWith('+++ b/')) { $currentDiffPath = $line.Substring(6); continue }
 if ($line.StartsWith('+') -and -not $line.StartsWith('+++')) {
  foreach ($rule in $patterns.Keys) { if ($line.Substring(1) -match $patterns[$rule]) { Add-Finding $findings $currentDiffPath $rule 'Added line matches a sensitive-change heuristic; inspect the source change.' 'HUMAN_REVIEW' } }
 }
}
$quality = $null
if ($scannerFiles.Count) {
 try {
    $qualityScript = Join-Path $repoRoot 'productivity-test\quality-check\Invoke-LocalQualityCheck.ps1'
    $qualityOutput = Join-Path (Split-Path $qualityScript) 'output'
    $pathLiterals = @($scannerFiles | ForEach-Object { ConvertTo-PowerShellLiteral $_ }) -join ', '
    $commandText = '& ' + (ConvertTo-PowerShellLiteral $qualityScript) + ' -OutputDirectory ' + (ConvertTo-PowerShellLiteral $qualityOutput) + ' -Path @(' + $pathLiterals + ') -SemgrepExecutable ' + (ConvertTo-PowerShellLiteral $SemgrepExecutable) + ' -WslDistribution ' + (ConvertTo-PowerShellLiteral $WslDistribution)
    if ($SkipSemgrep) { $commandText += ' -SkipSemgrep' }
    $previousRuns = @(Get-ChildItem -LiteralPath $qualityOutput -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $null = & (Get-Command pwsh -ErrorAction Stop).Source -NoProfile -Command $commandText 2>&1
    $stage4Exit = $LASTEXITCODE
    $latest = Get-ChildItem -LiteralPath $qualityOutput -Directory -ErrorAction Stop | Where-Object Name -notin $previousRuns | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw "Stage4 runner exited $stage4Exit without writing a new report." }
    $quality = Get-Content -LiteralPath (Join-Path $latest.FullName 'quality-report.json') -Raw | ConvertFrom-Json -ErrorAction Stop
    if ($stage4Exit -notin @(0,1)) { throw "Stage4 runner exited $stage4Exit." }
 } catch { $quality = [pscustomobject]@{ Status='ERROR'; Scanners=@([pscustomobject]@{ Name='Stage4QualityCheck'; Status='ERROR'; Error=$_.Exception.Message; Findings=@() }) } }
} else { $quality = [pscustomobject]@{ Status='PASS'; Scanners=@() } }
$diffStatus = if ($diffCheck.Trim()) { 'FAIL' } else { 'PASS' }
if ($diffStatus -eq 'FAIL') { Add-Finding $findings '(git diff)' 'diff-check' $diffCheck.Trim() 'ERROR' }
$scannerFailure = $quality.Status -ne 'PASS' -or @($quality.Scanners | Where-Object Status -in @('ERROR','FAIL','SKIPPED')).Count -gt 0
$human = @($findings | Where-Object Severity -eq 'HUMAN_REVIEW').Count -gt 0
$status = if ($diffStatus -eq 'FAIL' -or $scannerFailure -or @($findings | Where-Object Severity -eq 'ERROR').Count) { 'FAIL' } elseif ($human) { 'NEEDS_HUMAN_REVIEW' } else { 'PASS' }
$report = [ordered]@{ SchemaVersion=1; RunId=(Get-Date -Format 'yyyyMMdd-HHmmss-fff'); Status=$status; DiffRange=$rangeLabel; ChangedFiles=$changedPaths; DiffCheck=[ordered]@{ Status=$diffStatus; Output=$diffCheck.Trim() }; Findings=@($findings); Scanners=@($quality.Scanners); Note='Automated PASS never authorizes merge or deployment.' }
New-Item -ItemType Directory -Path $reportFull -Force | Out-Null
$runDir = Join-Path $reportFull $report.RunId; New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
$jsonPath = Join-Path $runDir 'review-report.json'; $mdPath = Join-Path $runDir 'review-report.md'
$report | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $jsonPath -Encoding utf8
$md = [System.Collections.Generic.List[string]]::new(); $md.Add("# Local code review: $status`n"); $md.Add("Changed files: $($changedPaths.Count) | Diff: ``$rangeLabel`` | `git diff --check`: **$diffStatus**"); $md.Add(''); $md.Add('## Findings')
if (-not $findings.Count) { $md.Add('No heuristic findings.') } else { foreach ($f in $findings) { $md.Add("- **$($f.Severity)** ``$($f.Path)`` — $($f.Rule): $($f.Message)") } }
$md.Add(''); $md.Add('## Scanners'); foreach ($s in $quality.Scanners) { $md.Add("- **$($s.Name): $($s.Status)** — $(@($s.Findings).Count) findings$(if ($s.Error) { "; ERROR: $($s.Error)" })"); foreach ($f in $s.Findings) { $md.Add("  - $($f.Severity) ``$($f.Path):$($f.Line)`` $($f.Rule): $($f.Message)") } }; $md.Add(''); $md.Add('> Automated PASS is not authorization to merge or deploy.')
$md | Set-Content -LiteralPath $mdPath -Encoding utf8
$report['ReportJson']=$jsonPath; $report['ReportMarkdown']=$mdPath; $report | ConvertTo-Json -Depth 15
if ($status -ne 'PASS') { exit 1 }
