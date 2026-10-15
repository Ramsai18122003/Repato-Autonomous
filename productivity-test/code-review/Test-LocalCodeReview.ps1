[CmdletBinding()]
param([string] $PSScriptAnalyzerModulePath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$output = Join-Path $PSScriptRoot 'output'
$sandbox = Join-Path $output ('fixture-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $sandbox 'productivity-test\code-review') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $sandbox 'productivity-test\quality-check') -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'Invoke-LocalCodeReview.ps1') (Join-Path $sandbox 'productivity-test\code-review\Invoke-LocalCodeReview.ps1')
Copy-Item (Join-Path $sourceRoot 'productivity-test\quality-check\Invoke-LocalQualityCheck.ps1') (Join-Path $sandbox 'productivity-test\quality-check\Invoke-LocalQualityCheck.ps1')
Copy-Item (Join-Path $sourceRoot 'productivity-test\quality-check\semgrep-rules.yml') (Join-Path $sandbox 'productivity-test\quality-check\semgrep-rules.yml')
if (-not $PSScriptAnalyzerModulePath) {
    # A local test module makes this path-flow regression deterministic on -NoProfile
    # machines where PSScriptAnalyzer is intentionally absent from PSModulePath.
    $testModule = Join-Path $sandbox 'test-modules\PSScriptAnalyzer\1.25.0'
    New-Item -ItemType Directory -Path $testModule -Force | Out-Null
    @'
function Invoke-ScriptAnalyzer {
    [CmdletBinding()]
    param([string] $Path, [string[]] $Severity)
    return @()
}
Export-ModuleMember -Function Invoke-ScriptAnalyzer
'@ | Set-Content -LiteralPath (Join-Path $testModule 'PSScriptAnalyzer.psm1') -Encoding utf8
    @'
@{
    RootModule = 'PSScriptAnalyzer.psm1'
    ModuleVersion = '1.25.0'
    GUID = 'e48df532-78f9-4d7a-ae9a-9a39e948162c'
    FunctionsToExport = @('Invoke-ScriptAnalyzer')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
'@ | Set-Content -LiteralPath (Join-Path $testModule 'PSScriptAnalyzer.psd1') -Encoding utf8
    $PSScriptAnalyzerModulePath = $testModule
}
function Assert-True([bool]$Value,[string]$Message) { if (-not $Value) { throw "ASSERT: $Message" } }
function ConvertTo-PowerShellLiteral([string]$Value) { "'" + $Value.Replace("'", "''") + "'" }
function Write-ReviewFailureDiagnostics([string]$Case, $Run) {
    Write-Output "FAILURE DIAGNOSTICS: $Case"
    Write-Output "Temporary Git repository: $sandbox"
    Write-Output "Child executable: $($Run.Executable)"
    Write-Output "Child command: $($Run.Command)"
    Write-Output "Child exit code: $($Run.ExitCode)"
    Write-Output "Generated JSON report: $(if ($Run.ReportPath) { $Run.ReportPath } else { '<not generated>' })"
    if ($Run.Report) {
        Write-Output "Review status: $($Run.Report.Status)"
        Write-Output "Review findings/errors: $(@($Run.Report.Findings | ForEach-Object { "$($_.Severity) $($_.Path): $($_.Rule) — $($_.Message)" }) -join '; ')"
        Write-Output "Scanner outcomes: $(@($Run.Report.Scanners | ForEach-Object { "$($_.Name)=$($_.Status)$(if ($_.Error) { ": $($_.Error)" })" }) -join '; ')"
    } else {
        Write-Output 'Review status: <no JSON report>'
    }
    Write-Output "Child stderr: $(if ($Run.Stderr) { $Run.Stderr } else { '<empty>' })"
    Write-Output "Child output: $(if ($Run.Output) { $Run.Output } else { '<empty>' })"
}
function Invoke-Review([string[]]$Arguments, [switch]$RestrictModuleDiscovery) {
    if ($PSScriptAnalyzerModulePath -and '-PSScriptAnalyzerModulePath' -notin $Arguments) {
        $Arguments += @('-PSScriptAnalyzerModulePath', $PSScriptAnalyzerModulePath)
    }
    $scriptPath = ConvertTo-PowerShellLiteral (Join-Path $sandbox 'productivity-test\code-review\Invoke-LocalCodeReview.ps1')
    $argumentParts = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        if ($Arguments[$index] -eq '-Path') {
            $paths = [System.Collections.Generic.List[string]]::new(); $index++
            while ($index -lt $Arguments.Count -and $Arguments[$index] -notmatch '^-[A-Za-z]') { $paths.Add((ConvertTo-PowerShellLiteral $Arguments[$index])); $index++ }
            $index--; $argumentParts.Add('-Path @(' + ($paths -join ', ') + ')')
        } elseif ($Arguments[$index] -match '^-[A-Za-z]') { $argumentParts.Add($Arguments[$index]) }
        else { $argumentParts.Add((ConvertTo-PowerShellLiteral $Arguments[$index])) }
    }
    $argumentText = $argumentParts -join ' '
    $commandText = '& ' + $scriptPath + ' ' + $argumentText
    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    $savedModulePath = $env:PSModulePath
    try {
        if ($RestrictModuleDiscovery) { $env:PSModulePath = Join-Path $PSHOME 'Modules' }
        $outputRecords = @(& $pwshPath -NoProfile -Command $commandText 2>&1)
        $exit = $LASTEXITCODE
    } finally {
        $env:PSModulePath = $savedModulePath
    }
    $outputText = $outputRecords | ForEach-Object { $_.ToString() }
    $stderrText = @($outputRecords | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() }) -join "`n"
    $reviewOutput = Join-Path $sandbox 'productivity-test\code-review\output'
    $reportFile = Get-ChildItem -LiteralPath $reviewOutput -Recurse -Filter review-report.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $report = if ($reportFile) { Get-Content -LiteralPath $reportFile.FullName -Raw | ConvertFrom-Json } else { $null }
    return [pscustomobject]@{ ExitCode=$exit; Executable=$pwshPath; Command=$commandText; Output=($outputText -join "`n"); Stderr=$stderrText; Report=$report; ReportPath=$(if ($reportFile) { $reportFile.FullName } else { $null }) }
}
try {
    & git -C $sandbox init -q
    & git -C $sandbox config user.email review-test@example.invalid
    & git -C $sandbox config user.name 'Synthetic Review Test'
    New-Item -ItemType Directory -Path (Join-Path $sandbox '.codex') -Force | Out-Null
    Set-Content (Join-Path $sandbox 'base.txt') 'baseline' -NoNewline
    Set-Content (Join-Path $sandbox '.codex\settings.json') '{}' -NoNewline
    & git -C $sandbox add -- base.txt .codex/settings.json
    & git -C $sandbox commit -qm baseline

    $clean = Join-Path $sandbox "clean file's.ps1"
    Set-Content -LiteralPath $clean -Value 'function Get-ReviewValue { return 42 }' -NoNewline
    $run = Invoke-Review @('-Path',"clean file's.ps1",'-SkipSemgrep') -RestrictModuleDiscovery
    if ($run.ExitCode -ne 0 -or -not $run.Report -or $run.Report.Status -ne 'PASS') {
        Write-ReviewFailureDiagnostics 'Clean spaced-path change must PASS' $run
        Assert-True $false 'Clean spaced-path change must PASS.'
    }
    Assert-True ($run.Report.Scanners.Count -eq 1 -and $run.Report.Scanners[0].Name -eq 'PSScriptAnalyzer' -and $run.Report.Scanners[0].Status -eq 'PASS') 'Clean -NoProfile child must load the explicitly supplied, validated PSScriptAnalyzer test module.'
    $md = Get-ChildItem -LiteralPath (Join-Path $sandbox 'productivity-test\code-review\output') -Recurse -Filter review-report.md | Select-Object -First 1; Assert-True ([bool]$md) 'Markdown report must exist.'

    $run = Invoke-Review @('-Path',"clean file's.ps1",'-SkipSemgrep','-PSScriptAnalyzerModulePath',(Join-Path $sandbox 'missing-analyzer')) -RestrictModuleDiscovery
    Assert-True ($run.ExitCode -eq 1 -and $run.Report.Status -eq 'FAIL' -and $run.Report.Scanners[0].Status -eq 'ERROR') 'Invalid explicit analyzer path must remain fail-closed when standard discovery is unavailable.'

    $unsafe = Join-Path $sandbox 'unsafe.ps1'
    Set-Content -LiteralPath $unsafe -Value '$client_secret = "synthetic-secret-value-123"' -NoNewline
    $run = Invoke-Review @('-Path','unsafe.ps1','-SkipSemgrep')
    Assert-True ($run.ExitCode -eq 1 -and $run.Report.Status -eq 'NEEDS_HUMAN_REVIEW') 'Credential-like addition must require human review.'
    Assert-True ($run.Report.Findings[0].Path -eq 'unsafe.ps1') 'Sensitive findings must identify the changed file.'

    $protected = Join-Path $sandbox '.codex\settings.json'
    Set-Content -LiteralPath $protected -Value '{ "allow": true }' -NoNewline
    $run = Invoke-Review @('-Path','.codex/settings.json')
    Assert-True ($run.ExitCode -eq 1 -and $run.Report.Status -eq 'NEEDS_HUMAN_REVIEW') 'Protected path must require human review.'

    $multiOne = Join-Path $sandbox 'sample one.js'
    $multiTwo = Join-Path $sandbox "sample'two.js"
    Set-Content -LiteralPath $multiOne -Value 'export const one = 1;' -NoNewline
    Set-Content -LiteralPath $multiTwo -Value 'export const two = 2;' -NoNewline
    $qualityScript = Join-Path $sandbox 'productivity-test\quality-check\Invoke-LocalQualityCheck.ps1'
    @'
[CmdletBinding()]
param([string[]]$Path,[string]$OutputDirectory,[string]$SemgrepExecutable,[string]$WslDistribution,[string]$PSScriptAnalyzerModulePath,[switch]$SkipSemgrep)
$run = Join-Path $OutputDirectory ('mock-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $run -Force | Out-Null
[ordered]@{ SchemaVersion=1; Status='PASS'; FilesSelected=$Path.Count; Paths=@($Path); Scanners=@([ordered]@{ Name='Semgrep'; Status='PASS'; Findings=@(); Error=$null }) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'quality-report.json')
'@ | Set-Content -LiteralPath $qualityScript -Encoding utf8
    $run = Invoke-Review @('-Path','sample one.js',"sample'two.js")
    Assert-True ($run.ExitCode -eq 0 -and $run.Report.Status -eq 'PASS') "Multi-file Stage 4 handoff must PASS. Child output: $($run.Output)"
    Assert-True ($run.Report.ChangedFiles.Count -eq 2 -and $run.Report.Scanners[0].Status -eq 'PASS') 'Multi-file review must retain both selected paths.'
    $qualityReportFile = Get-ChildItem -LiteralPath (Join-Path $sandbox 'productivity-test\quality-check\output') -Recurse -Filter quality-report.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $qualityReport = Get-Content -LiteralPath $qualityReportFile.FullName -Raw | ConvertFrom-Json
    Assert-True ($qualityReport.Paths.Count -eq 2 -and $qualityReport.Paths[0] -eq 'sample one.js' -and $qualityReport.Paths[1] -eq "sample'two.js") 'Stage 4 must receive both paths intact, including spaces and apostrophes.'

    $toolFile = Join-Path $sandbox 'Tool.cs'
    Set-Content -LiteralPath $toolFile -Value 'class Tool {}' -NoNewline
    @'
[CmdletBinding()]
param([string[]]$Path,[string]$OutputDirectory,[string]$SemgrepExecutable,[string]$WslDistribution,[string]$PSScriptAnalyzerModulePath,[switch]$SkipSemgrep)
$run = Join-Path $OutputDirectory ('mock-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $run -Force | Out-Null
[ordered]@{ SchemaVersion=1; Status='FAIL'; FilesSelected=$Path.Count; Scanners=@([ordered]@{ Name='Semgrep'; Status='ERROR'; Findings=@(); Error='synthetic scanner unavailable' }) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'quality-report.json')
exit 1
'@ | Set-Content -LiteralPath $qualityScript -Encoding utf8
    $run = Invoke-Review @('-Path','Tool.cs')
    Assert-True ($run.ExitCode -eq 1 -and $run.Report.Status -eq 'FAIL' -and $run.Report.Scanners[0].Status -eq 'ERROR') 'Missing scanner must be a visible FAIL.'
    Copy-Item (Join-Path $sourceRoot 'productivity-test\quality-check\Invoke-LocalQualityCheck.ps1') $qualityScript -Force

    $run = Invoke-Review @('-DiffRange','bad-range-does-not-exist')
    Assert-True ($run.ExitCode -ne 0) 'Malformed Git range must fail closed.'

    Set-Content -LiteralPath (Join-Path $sandbox 'base.txt') -Value 'changed  ' -NoNewline
    $run = Invoke-Review @('-DiffRange','HEAD')
    Assert-True ($run.ExitCode -eq 1 -and $run.Report.Status -eq 'FAIL' -and $run.Report.DiffCheck.Status -eq 'FAIL') 'Diff whitespace must fail.'

    Write-Output 'PASS: clean, suspicious addition, protected path, missing scanner, malformed range, diff-check, and spaced path.'
} finally {
    # Synthetic repository and generated reports intentionally remain under ignored output/.
}
