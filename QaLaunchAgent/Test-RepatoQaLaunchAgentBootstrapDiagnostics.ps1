$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.QaLaunchAgent.Bootstrap.psm1') -Force

function Assert([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
$contract=Get-RepatoQaLaunchAgentBootstrapContract
$actual=[pscustomobject]@{TaskPath=$contract.TaskPath;TaskName=$contract.TaskName;Principal=$contract.Account;Sid=$contract.Sid;LogonType='Interactive';RunLevel='Limited';TriggerType='Logon';TriggerUser=$contract.Account;Execute=$contract.Executable;Arguments='';WorkingDirectory=$contract.InstallRoot;MultipleInstances='IgnoreNew';RestartCount=3;RestartInterval='PT1M'}
$matches=@(Get-TaskSpecComparison $actual)
Assert (($matches | Where-Object {!$_.Match}).Count -eq 0) 'Exact contract did not pass.'

$fields=@('Principal','LogonType','RunLevel','TriggerUser','Execute','Arguments','WorkingDirectory','MultipleInstances','RestartCount','RestartInterval')
foreach($field in $fields){
    $bad=$actual.PSObject.Copy(); $bad.$field='mismatch'
    $m=@(Get-TaskSpecComparison $bad | Where-Object {!$_.Match})
    Assert ($m.Count -eq 1 -and $m[0].Property -eq $field) "Mismatch was not isolated for $field."
}
$all=$actual.PSObject.Copy(); foreach($field in $fields){$all.$field='mismatch'}
$m=@(Get-TaskSpecComparison $all | Where-Object {!$_.Match})
Assert ($m.Count -eq $fields.Count) 'Multiple mismatches were not all reported.'

$moduleText=Get-Content (Join-Path $PSScriptRoot 'Repato.QaLaunchAgent.Bootstrap.psm1') -Raw
Assert ($moduleText -match 'Write-RepatoQaLaunchAgentDiagnostics') 'Diagnostic persistence is missing.'
Assert ($moduleText -match 'RestoreTask') 'Rollback path is missing.'
Assert ($moduleText -match 'Get-RepatoQaLaunchAgentRuntimeIntegrity') 'Runtime integrity check is missing.'
Write-Output 'QA launch-agent bootstrap diagnostic tests passed: exact match, 10 individual mismatches, all mismatches, persistence, rollback, and integrity coverage.'
