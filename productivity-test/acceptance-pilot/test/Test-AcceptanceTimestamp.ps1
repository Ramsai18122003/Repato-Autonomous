[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$timestamp = '2026-10-15T04:52:14.9804412Z'
$json = '{"PreparedUtc":"' + $timestamp + '"}'
$expectedUtc = [DateTime]::ParseExact($timestamp, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
$originalCulture = [Globalization.CultureInfo]::CurrentCulture

try {
    foreach ($cultureName in @('en-US', 'fr-FR')) {
        [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo($cultureName)
        $timestampMatch = [regex]::Match($json, '"PreparedUtc"\s*:\s*"(?<value>[^"]+)"')
        if (-not $timestampMatch.Success) { throw 'PreparedUtc timestamp was not found.' }
        $timestampText = $timestampMatch.Groups['value'].Value
        $actualUtc = [DateTime]::ParseExact($timestampText, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        if ($actualUtc -ne $expectedUtc) { throw "Timestamp mismatch under ${cultureName}: $actualUtc" }
    }
}
finally {
    [Globalization.CultureInfo]::CurrentCulture = $originalCulture
}

Write-Output 'PASS: ISO round-trip preflight timestamp parses identically under en-US and fr-FR.'
