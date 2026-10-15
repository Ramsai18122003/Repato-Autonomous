[CmdletBinding()]
param(
    [Parameter(Mandatory, ParameterSetName = 'Prepare')]
    [switch] $Prepare,
    [Parameter(Mandatory, ParameterSetName = 'Accept')]
    [switch] $Accept
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$statePath = Join-Path $PSScriptRoot '.pre-ralph-state.json'
$promptPath = Join-Path $PSScriptRoot 'RALPH-PROMPT.md'
$scriptPath = $PSCommandPath
$sourceRel = 'productivity-test/acceptance-pilot/src/rotate-text-by-code-point.js'
$testRel = 'productivity-test/acceptance-pilot/test/rotate-text-by-code-point.test.js'
$expectedRel = @($sourceRel, $testRel)
$expectedFull = @($expectedRel | ForEach-Object { Join-Path $repoRoot ($_ -replace '/', [IO.Path]::DirectorySeparatorChar) })

function Get-Sha256([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if ($Prepare) {
    if (Test-Path -LiteralPath $statePath) { throw "Preflight state already exists; remove it only after confirming no Ralph run is in progress: $statePath" }
    foreach ($path in $expectedFull) {
        if (Test-Path -LiteralPath $path) { throw "FAIL: expected Ralph output already exists before Ralph runs: $path" }
    }
    $state = [ordered]@{
        PreparedUtc = [DateTime]::UtcNow.ToString('o')
        PromptSha256 = Get-Sha256 $promptPath
        AcceptanceScriptSha256 = Get-Sha256 $scriptPath
        ExpectedFiles = $expectedRel
    }
    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding utf8
    Write-Output 'PASS: both expected implementation files were absent; pre-Ralph state recorded.'
    exit 0
}

try {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw 'Pre-Ralph state is missing. Run this script with -Prepare before Ralph.' }
    $stateJson = Get-Content -LiteralPath $statePath -Raw
    $state = $stateJson | ConvertFrom-Json -ErrorAction Stop
    if ($state.PromptSha256 -ne (Get-Sha256 $promptPath) -or $state.AcceptanceScriptSha256 -ne (Get-Sha256 $scriptPath)) {
        throw 'Prompt or acceptance script changed after the pre-Ralph check.'
    }
    if (@($state.ExpectedFiles) -join '|' -ne ($expectedRel -join '|')) { throw 'Pre-Ralph state does not match the expected output list.' }
    $timestampMatch = [regex]::Match($stateJson, '"PreparedUtc"\s*:\s*"(?<value>[^"]+)"')
    if (-not $timestampMatch.Success) { throw 'Pre-Ralph state has no valid PreparedUtc timestamp.' }
    $preparedUtcText = $timestampMatch.Groups['value'].Value
    $preparedUtc = [DateTime]::ParseExact($preparedUtcText, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    foreach ($path in $expectedFull) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "FAIL: Ralph did not create expected implementation file: $path" }
        if ((Get-Item -LiteralPath $path).LastWriteTimeUtc -lt $preparedUtc) { throw "FAIL: expected implementation file predates preflight: $path" }
        $resolved = (Resolve-Path -LiteralPath $path).Path
        $relative = [IO.Path]::GetRelativePath($repoRoot, $resolved).Replace('\', '/')
        if ($relative -cne ($path -replace '\\', '/')) { throw "Unexpected implementation path: $resolved" }
    }

    Write-Output 'Running Node.js assertions...'
    & node $expectedFull[1]
    if ($LASTEXITCODE -ne 0) { throw "Node.js assertions failed (exit $LASTEXITCODE)." }

    $qualityScript = Join-Path $repoRoot 'productivity-test\quality-check\Invoke-LocalQualityCheck.ps1'
    $qualityPaths = @($expectedRel | ForEach-Object { '.\' + ($_ -replace '/', '\') })
    Write-Output 'Running Stage 4 quality checks on the two exact implementation files...'
    & $qualityScript -Path $qualityPaths
    if ($LASTEXITCODE -ne 0) { throw "Stage 4 quality checks failed (exit $LASTEXITCODE)." }

    $reviewScript = Join-Path $repoRoot 'productivity-test\code-review\Invoke-LocalCodeReview.ps1'
    Write-Output 'Running Stage 5 review on the two exact implementation files...'
    & $reviewScript -Path $qualityPaths
    if ($LASTEXITCODE -ne 0) { throw "Stage 5 review failed (exit $LASTEXITCODE)." }

    Write-Output 'PASS: implementation files exist, assertions passed, and Stage 4 and Stage 5 passed.'
    exit 0
} catch {
    [Console]::Error.WriteLine("FAIL: $($_.Exception.Message)")
    exit 1
}
