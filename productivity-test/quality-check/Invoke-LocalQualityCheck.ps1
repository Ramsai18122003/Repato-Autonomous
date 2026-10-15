[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]] $Path,

    [string] $OutputDirectory = (Join-Path $PSScriptRoot 'output'),
    [string] $SemgrepExecutable = '/home/rsgud/semgrep-env/bin/semgrep',
    [string] $WslDistribution = 'Ubuntu',
    [switch] $SkipSemgrep
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SupportedSemgrepExtensions = @('.cs', '.go', '.java', '.js', '.py', '.rb', '.ts')
$script:QualityToolRoot = $PSScriptRoot
$script:ProtectedSegments = @(
    'QA', 'AgentOrchestration', 'DeploymentCandidates', 'QaLaunchAgent',
    '.agent', '.agents', '.claude', '.codex', '.gemini', '.ralph'
)

function Resolve-QualityFiles {
    param([string[]] $InputPath, [string] $Root)

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $files = [System.Collections.Generic.List[IO.FileInfo]]::new()
    foreach ($input in $InputPath) {
        $candidate = if ([IO.Path]::IsPathRooted($input)) { $input } else { Join-Path $rootFull $input }
        if (-not (Test-Path -LiteralPath $candidate)) { throw "Selected path does not exist: $input" }
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        $relative = [IO.Path]::GetRelativePath($rootFull, $resolved)
        if ($relative -eq '..' -or $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)") -or [IO.Path]::IsPathRooted($relative)) {
            throw "Selected path must be inside the repository: $input"
        }
        $segments = $relative -split '[\\/]'
        if ($segments | Where-Object { $script:ProtectedSegments -contains $_ }) {
            throw "Protected path cannot be analyzed by this local workflow: $input"
        }
        $item = Get-Item -LiteralPath $resolved
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Selected path cannot be a reparse point: $input" }
        if ($item.PSIsContainer) {
            $pending = [System.Collections.Generic.Stack[IO.DirectoryInfo]]::new()
            $pending.Push([IO.DirectoryInfo]$item)
            while ($pending.Count) {
                $directory = $pending.Pop()
                foreach ($child in $directory.EnumerateFileSystemInfos()) {
                    if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                    if ($child -is [IO.DirectoryInfo]) {
                        if ($script:ProtectedSegments -contains $child.Name) { continue }
                        $pending.Push([IO.DirectoryInfo]$child)
                    } else { $files.Add([IO.FileInfo]$child) }
                }
            }
        } else { $files.Add([IO.FileInfo]$item) }
    }

    $unique = @{}
    foreach ($file in $files) { $unique[$file.FullName] = $file }
    return @($unique.Values | Sort-Object FullName)
}

function ConvertTo-WslPath {
    param([Parameter(Mandatory)][string] $WindowsPath)
    $full = [IO.Path]::GetFullPath($WindowsPath)
    if ($full -notmatch '^([A-Za-z]):\\(.*)$') { throw "WSL Semgrep requires a drive-letter path: $WindowsPath" }
    return "/mnt/$($Matches[1].ToLowerInvariant())/" + ($Matches[2] -replace '\\', '/')
}

function Write-QualityReport {
    param([object] $Report, [string] $Directory)
    $jsonPath = Join-Path $Directory 'quality-report.json'
    $textPath = Join-Path $Directory 'quality-report.txt'
    $json = $Report | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $jsonPath -Value $json -Encoding utf8
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("Local quality check: $($Report.Status)")
    $lines.Add("Files selected: $($Report.FilesSelected)")
    foreach ($scanner in $Report.Scanners) {
        $lines.Add("$($scanner.Name): $($scanner.Status) ($($scanner.Findings.Count) findings)")
        if ($scanner.Error) { $lines.Add("  Tool failure: $($scanner.Error)") }
        foreach ($finding in $scanner.Findings) {
            $lines.Add("  [$($finding.Severity)] $($finding.Path):$($finding.Line) $($finding.Rule): $($finding.Message)")
        }
    }
    Set-Content -LiteralPath $textPath -Value $lines -Encoding utf8
    return @{ Json = $jsonPath; Text = $textPath }
}

function Invoke-LocalQualityCheck {
    param([string[]] $SelectedPath, [string] $RepoRoot, [string] $ReportDirectory, [switch] $NoSemgrep,
        [string] $SemgrepExecutable = '/home/rsgud/semgrep-env/bin/semgrep',
        [string] $WslDistribution = 'Ubuntu', [scriptblock] $SemgrepInvoker)
    $reportRoot = [IO.Path]::GetFullPath((Join-Path $script:QualityToolRoot 'output'))
    $reportFull = [IO.Path]::GetFullPath($ReportDirectory)
    if ($reportFull -ne $reportRoot -and -not $reportFull.StartsWith($reportRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Reports may only be written under $reportRoot"
    }
    $checkPath = $reportRoot
    if (Test-Path -LiteralPath $checkPath) {
        if ((Get-Item -LiteralPath $checkPath).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'The report output root cannot be a reparse point.' }
    }
    $relativeReport = [IO.Path]::GetRelativePath($reportRoot, $reportFull)
    if ($relativeReport -ne '.') {
        foreach ($segment in ($relativeReport -split '[\\/]')) {
            $checkPath = Join-Path $checkPath $segment
            if (Test-Path -LiteralPath $checkPath -PathType Container) {
                if ((Get-Item -LiteralPath $checkPath).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Report output path cannot traverse a reparse point.' }
            }
        }
    }
    New-Item -ItemType Directory -Path $reportFull -Force | Out-Null
    $files = @(Resolve-QualityFiles -InputPath $SelectedPath -Root $RepoRoot)
    if (-not $files.Count) { throw 'The explicit selection contains no files.' }
    $runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $runDirectory = Join-Path $reportFull $runId
    New-Item -ItemType Directory -Path $runDirectory -ErrorAction Stop | Out-Null

    $scanners = [System.Collections.Generic.List[object]]::new()
    $powershellFiles = @($files | Where-Object Extension -in @('.ps1', '.psm1', '.psd1'))
    if ($powershellFiles.Count) {
        $scan = [ordered]@{ Name = 'PSScriptAnalyzer'; Status = 'PASS'; Findings = @(); Error = $null }
        try {
            if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer | Where-Object Version -eq ([version]'1.25.0'))) {
                throw 'PSScriptAnalyzer 1.25.0 is not installed.'
            }
            Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -ErrorAction Stop
            $raw = @($powershellFiles | ForEach-Object {
                Invoke-ScriptAnalyzer -Path $_.FullName -Severity Error, Warning, Information -ErrorAction Stop
            })
            $scan.Findings = @($raw | ForEach-Object { [ordered]@{
                Severity = [string]$_.Severity; Path = [IO.Path]::GetRelativePath($RepoRoot, $_.ScriptPath)
                Line = [int]$_.Line; Rule = [string]$_.RuleName; Message = [string]$_.Message
            } })
            if ($scan.Findings | Where-Object Severity -eq 'Error') { $scan.Status = 'FAIL' }
        } catch { $scan.Status = 'ERROR'; $scan.Error = $_.Exception.Message }
        $scanners.Add([pscustomobject]$scan)
    }

    $semgrepFiles = @($files | Where-Object { $script:SupportedSemgrepExtensions -contains $_.Extension.ToLowerInvariant() })
    if ($semgrepFiles.Count -and -not $NoSemgrep) {
        $scan = [ordered]@{ Name = 'Semgrep'; Status = 'PASS'; Findings = @(); Error = $null }
        try {
            $wsl = $null
            if (-not $SemgrepInvoker) {
                $wsl = Get-Command wsl.exe -ErrorAction Stop
                $probe = & $wsl.Source --distribution $WslDistribution --exec $SemgrepExecutable --version 2>&1
                if ($LASTEXITCODE -ne 0) { throw "Semgrep executable unavailable in WSL distribution '$WslDistribution' at '$SemgrepExecutable' (exit $LASTEXITCODE): $($probe -join ' ')" }
            }
            $ruleFile = ConvertTo-WslPath (Join-Path $script:QualityToolRoot 'semgrep-rules.yml')
            $paths = @($semgrepFiles | ForEach-Object { ConvertTo-WslPath $_.FullName })
            $semgrepArguments = @('--config', $ruleFile, '--json') + $paths
            if ($SemgrepInvoker) {
                $processResult = & $SemgrepInvoker -Arguments $semgrepArguments
                $output = $processResult.Output
                $exitCode = [int]$processResult.ExitCode
            } else {
                $output = & $wsl.Source --distribution $WslDistribution --exec $SemgrepExecutable @semgrepArguments 2>&1
                $exitCode = $LASTEXITCODE
            }
            $jsonText = ($output | Where-Object { $_ -is [string] } | Out-String).Trim()
            if ($exitCode -gt 1) { throw "Semgrep scanner failed (exit $exitCode): $jsonText" }
            $parsed = $jsonText | ConvertFrom-Json -ErrorAction Stop
            if (@($parsed.errors).Count) {
                $errorText = @($parsed.errors | ForEach-Object { $_.message }) -join '; '
                throw "Semgrep reported scanner or configuration errors: $errorText"
            }
            $scan.Findings = @($parsed.results | ForEach-Object { [ordered]@{
                Severity = [string]$_.extra.severity; Path = [string]$_.path; Line = [int]$_.start.line
                Rule = [string]$_.check_id; Message = [string]$_.extra.message
            } })
            if ($scan.Findings.Count) { $scan.Status = 'FAIL' }
            elseif ($exitCode -ne 0) { throw "Semgrep exited $exitCode without reporting findings: $jsonText" }
        } catch { $scan.Status = 'ERROR'; $scan.Error = $_.Exception.Message }
        $scanners.Add([pscustomobject]$scan)
    } elseif ($semgrepFiles.Count -and $NoSemgrep) {
        $scanners.Add([pscustomobject]@{ Name = 'Semgrep'; Status = 'SKIPPED'; Findings = @(); Error = 'Explicitly skipped.' })
    }

    if (-not $scanners.Count) { throw 'No selected files are supported by the configured scanners.' }
    $status = if ($scanners | Where-Object Status -in @('FAIL', 'ERROR', 'SKIPPED')) { 'FAIL' } else { 'PASS' }
    $report = [pscustomobject]@{ SchemaVersion = 1; RunId = $runId; Status = $status; FilesSelected = $files.Count; Scanners = @($scanners) }
    $paths = Write-QualityReport -Report $report -Directory $runDirectory
    $report | Add-Member -NotePropertyName ReportJson -NotePropertyValue $paths.Json
    $report | Add-Member -NotePropertyName ReportText -NotePropertyValue $paths.Text
    return $report
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$result = Invoke-LocalQualityCheck -SelectedPath $Path -RepoRoot $repoRoot -ReportDirectory $OutputDirectory `
    -NoSemgrep:$SkipSemgrep -SemgrepExecutable $SemgrepExecutable -WslDistribution $WslDistribution
Write-Output $result
if ($result.Status -ne 'PASS') { exit 1 }
