[CmdletBinding()]
param()
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
function Assert-True([bool]$Value,[string]$Message) { if (-not $Value) { throw "ASSERT: $Message" } }
function ConvertTo-PowerShellLiteral([string]$Value) { "'" + $Value.Replace("'", "''") + "'" }
function Invoke-Review([string[]]$Arguments) {
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
    $outputText = & (Get-Command pwsh).Source -NoProfile -Command $commandText 2>&1
    $exit = $LASTEXITCODE
    $reviewOutput = Join-Path $sandbox 'productivity-test\code-review\output'
    $reportFile = Get-ChildItem -LiteralPath $reviewOutput -Recurse -Filter review-report.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $report = if ($reportFile) { Get-Content -LiteralPath $reportFile.FullName -Raw | ConvertFrom-Json } else { $null }    return [pscustomobject]@{ ExitCode=$exit; Output=($outputText -join "`n"); Report=$report }
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
    $run = Invoke-Review @('-Path',"clean file's.ps1",'-SkipSemgrep')
    Assert-True ($run.ExitCode -eq 0 -and $run.Report.Status -eq 'PASS') 'Clean spaced-path change must PASS.'
    $md = Get-ChildItem -LiteralPath (Join-Path $sandbox 'productivity-test\code-review\output') -Recurse -Filter review-report.md | Select-Object -First 1; Assert-True ([bool]$md) 'Markdown report must exist.'

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
param([string[]]$Path,[string]$OutputDirectory,[string]$SemgrepExecutable,[string]$WslDistribution,[switch]$SkipSemgrep)
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
param([string[]]$Path,[string]$OutputDirectory,[string]$SemgrepExecutable,[string]$WslDistribution,[switch]$SkipSemgrep)
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
