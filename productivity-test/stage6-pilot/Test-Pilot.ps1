[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testFile = Join-Path $PSScriptRoot 'test\normalize-label.test.js'

& node $testFile
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Output 'PASS: Stage 6 pilot behavior checks.'
