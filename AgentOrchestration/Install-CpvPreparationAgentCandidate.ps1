[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReleaseRoot,[Parameter(Mandatory)][string]$ManifestSha256,[switch]$Execute)
$ErrorActionPreference='Stop'
if(!$Execute){throw 'Installation is not automatic. Explicit deployment authorization and -Execute are required.'}
$principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Installation requires an elevated administrator PowerShell.'}
Import-Module (Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationRecovery.psm1') -Force -WarningAction SilentlyContinue
. (Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1')
$contract=Get-RepatoQaLaunchAgentBootstrapContract
if(@(Get-Process Revit -ErrorAction SilentlyContinue).Count){throw 'Revit must be stopped.'}
if(Test-Path -LiteralPath 'C:\Users\RepatoQA\AppData\Local\Repato\QaLaunchAgent\Logs\CpvPreparation\active.json'){throw 'An active/interrupted preparation must be reconciled before agent installation.'}
$manifest=Join-Path $ReleaseRoot 'Repato.QaLaunchAgent.release.json'
if((Get-FileHash $manifest).Hash -cne $ManifestSha256){throw 'Release manifest hash mismatch.'}
$agents=@(Get-Process Repato.QaLaunchAgent -ErrorAction SilentlyContinue)
if($agents.Count -ne 1 -or $agents[0].Path -ine $contract.Executable){throw 'One exact installed Launch Agent process is required.'}
Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid $agents[0].Id -ExpectedAgentStartTime $agents[0].StartTime.ToString('o') -AgentExe $contract.Executable -TaskPath $contract.TaskPath -TaskName $contract.TaskName
$token=$null
try {
    $installed=Install-RepatoQaLaunchAgentBootstrap -SourceRoot $ReleaseRoot -ManifestPath $manifest -ManifestSha256 $ManifestSha256 -RetainRollback
    $token=$installed.RollbackToken
    $checked=Test-RepatoQaLaunchAgentBootstrap -ManifestPath $manifest -ManifestSha256 $ManifestSha256
    if(!$checked.InstalledRuntimeIntegrity -or !$checked.TaskContractValid){throw 'Installed runtime/task integrity failed.'}
    Start-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName
    Start-Sleep -Seconds 2
    $capabilities=Get-CpvPreparationCapabilities
    $null=Complete-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $token;$token=$null
    $capabilities|ConvertTo-Json
} catch {
    $failure=$_
    Stop-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName -ErrorAction SilentlyContinue
    $process=Get-Process Repato.QaLaunchAgent -ErrorAction SilentlyContinue
    if($process -and $process.Path -ieq $contract.Executable){Stop-Process -InputObject $process -Force}
    if($token){Restore-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $token|Out-Null}
    Start-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName
    throw $failure
}
