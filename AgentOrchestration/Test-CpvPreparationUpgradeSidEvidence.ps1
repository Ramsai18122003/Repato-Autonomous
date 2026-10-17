[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationUpgrade.psm1') -Force -PassThru
$script:assertions=0
function Assert([bool]$Condition,[string]$Message){$script:assertions++;if(!$Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$script:assertions++;$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};if(!$failed){throw $Message}}
function Resolve-Sid($identity,[string]$processSid){& $module {param($i,$s)Get-CpvInstalledAgentSid -InstalledAgent $i -ProcessSid $s} $identity $processSid}
$validSid='S-1-5-21-1031246752-3872016183-2454652381-1015'
$missing=[pscustomobject]@{ProcessName='Repato.QaLaunchAgent';Id=4242}
$incorrect=[pscustomobject]@{Sid='S-1-5-21-1-2-3-1000'}
$valid=[pscustomobject]@{Sid=$validSid}
Assert ((Resolve-Sid $missing $validSid) -ceq $validSid) 'Missing object SID did not resolve from trusted process-owner evidence.'
Reject {Resolve-Sid $missing 'S-1-5-21-1-2-3-1000'} 'Missing process SID evidence was accepted.'
Reject {Resolve-Sid $incorrect $validSid} 'Incorrect installed SID evidence was replaced by fallback evidence.'
Assert ((Resolve-Sid $valid $validSid) -ceq $validSid) 'Valid process SID evidence was rejected.'
[pscustomobject]@{Test='CpvPreparationUpgradeSidEvidence';Assertions=$script:assertions;MissingSidFallback='PASS';MissingEvidenceRejected='PASS';IncorrectSidRejected='PASS';ValidSidAccepted='PASS';LiveStoresTouched=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
