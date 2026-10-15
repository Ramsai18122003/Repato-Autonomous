[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReleaseRoot,[Parameter(Mandatory)][string]$ManifestSha256,[switch]$Execute,
    [string]$ReconcileRequestId,[string]$TaskId='task-bf61fe7f22d74df7a92599681da5919e')
$ErrorActionPreference='Stop'
if(!$Execute){throw 'Installation is not automatic. Explicit deployment authorization and -Execute are required.'}
$principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Installation requires an elevated administrator PowerShell.'}
Import-Module (Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationRecovery.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationUpgrade.psm1') -Force -WarningAction SilentlyContinue
. (Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1')
$contract=Get-RepatoQaLaunchAgentBootstrapContract
$manifest=Join-Path $ReleaseRoot 'Repato.QaLaunchAgent.release.json'
if((Get-FileHash $manifest).Hash -cne $ManifestSha256){throw 'Release manifest hash mismatch.'}
$activeRoot='C:\Users\RepatoQA\AppData\Local\Repato\QaLaunchAgent\Logs\CpvPreparation'
$activePath=Join-Path $activeRoot 'active.json';$upgrade=$null;$evidenceSnapshot=$null
if(Test-Path -LiteralPath $activePath){
    if(!$ReconcileRequestId){throw 'An active/interrupted preparation must be reconciled before agent installation.'}
    if($TaskId -cne 'task-bf61fe7f22d74df7a92599681da5919e' -or $ReconcileRequestId -cne '9953e14c15524fe09440d1c7d7353950'){
        throw 'Only the explicitly approved CPV failed request can use this upgrade exception.'
    }
    if(@(Get-Process -Name Revit -ErrorAction Stop).Count){throw 'Revit is running; the guarded upgrade is unavailable.'}
    $agents=@(Get-Process -Name Repato.QaLaunchAgent -ErrorAction Stop)
    if($agents.Count -ne 1 -or $agents[0].ProcessName -cne 'Repato.QaLaunchAgent' -or $agents[0].Path -ine $contract.Executable){throw 'One exact installed Launch Agent process is required.'}
    $ownerProcess=Get-CimInstance Win32_Process -Filter "ProcessId=$($agents[0].Id)" -ErrorAction Stop
    if(!$ownerProcess){throw 'Installed Launch Agent process identity is unavailable.'}
    $owner=Invoke-CimMethod -InputObject $ownerProcess -MethodName GetOwner -ErrorAction Stop
    if($owner.ReturnValue -ne 0){throw 'Installed Launch Agent owner is unavailable.'}
    $ownerName=$owner.Domain+'\'+$owner.User
    $ownerSid=([Security.Principal.NTAccount]$ownerName).Translate([Security.Principal.SecurityIdentifier]).Value
    $capabilities=Get-CpvPreparationCapabilities
    $request=[pscustomobject]@{schemaVersion=1;operation='cpv-preparation-status';requestId=$ReconcileRequestId}
    $receipt=Invoke-CpvPreparationTransport $request
    $priorFiles=@(foreach($name in $contract.RuntimeFiles){$path=Join-Path $contract.InstallRoot $name;if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Prior runtime rollback file is missing: $name"};[pscustomobject]@{name=$name;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}})
    $priorTask=Get-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName -ErrorAction Stop
    $bootstrap=Get-Module Repato.QaLaunchAgent.Bootstrap
    $priorTaskValid=& $bootstrap {param($task) Test-TaskSpec $task} $priorTask
    $validated=& $bootstrap {param($root,$path,$hash) Read-ValidatedManifest $root $path $hash} $ReleaseRoot $manifest $ManifestSha256.ToUpperInvariant()
    $productVersion=(Get-Item -LiteralPath $agents[0].Path).VersionInfo.ProductVersion
    $installedIdentity=[pscustomobject]@{ProcessName=$agents[0].ProcessName;Path=$agents[0].Path;ProductVersion=$productVersion;Id=$agents[0].Id;StartTime=$agents[0].StartTime;User=$ownerName;Sid=$ownerSid;SessionId=$agents[0].SessionId}
    $upgrade=Assert-CpvPreparationUpgradeEvidence -EvidenceRoot $activeRoot -RuntimeRoot 'C:\Repato-Autonomous\Source\QA\TestRuns' `
        -RequestId $ReconcileRequestId -TaskId $TaskId -Capabilities $capabilities -Receipt $receipt -InstalledAgent $installedIdentity `
        -ExpectedExecutable $contract.Executable -ExpectedInstalledVersion '1.0.17+4b0066247088' -CandidateRoot $validated.SourceRoot `
        -CandidateManifestPath $manifest -CandidateManifestSha256 $ManifestSha256 -PriorRuntimeFiles $priorFiles `
        -PriorTaskContractValid ([bool]$priorTaskValid) -NoRevitProcesses $true
    $evidenceSnapshot=Get-CpvPreparationUpgradeEvidenceSnapshot -EvidenceRoot $activeRoot -RunDirectory $upgrade.RunDirectory
} elseif($ReconcileRequestId){throw 'A reconciliation request was supplied but no matching active marker exists.'}
$revit=@(Get-Process -Name Revit -ErrorAction Stop)
if($revit.Count){throw 'Revit must be stopped.'}
$agents=@(Get-Process Repato.QaLaunchAgent -ErrorAction SilentlyContinue)
if($agents.Count -ne 1 -or $agents[0].Path -ine $contract.Executable){throw 'One exact installed Launch Agent process is required.'}
Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid $agents[0].Id -ExpectedAgentStartTime $agents[0].StartTime.ToString('o') -AgentExe $contract.Executable -TaskPath $contract.TaskPath -TaskName $contract.TaskName
$token=$null;$installAttempted=$false
try {
    $installAttempted=$true
    $installed=Install-RepatoQaLaunchAgentBootstrap -SourceRoot $ReleaseRoot -ManifestPath $manifest -ManifestSha256 $ManifestSha256 -RetainRollback
    $token=$installed.RollbackToken
    if($upgrade){
        if(!$token -or !$token.Updated -or !$token.BackupRoot -or !(Test-Path -LiteralPath $token.BackupRoot -PathType Container) -or !$token.OldTaskXml){throw 'Verified prior-runtime rollback evidence was not retained.'}
        $backup=Get-RepatoQaLaunchAgentRuntimeIntegrity $token.BackupRoot ([pscustomobject]@{files=$token.PriorFiles})
        if(@($backup|Where-Object {!$_.Match}).Count){throw 'Retained rollback bytes failed integrity validation.'}
        foreach($prior in $upgrade.PriorFiles){$bound=@($token.PriorFiles|Where-Object name -ceq $prior.name);if($bound.Count -ne 1 -or $bound[0].sha256 -ine $prior.sha256){throw 'Retained rollback bytes differ from the verified prior runtime.'}}
    }
    $checked=Test-RepatoQaLaunchAgentBootstrap -ManifestPath $manifest -ManifestSha256 $ManifestSha256
    if(!$checked.InstalledRuntimeIntegrity -or !$checked.TaskContractValid){throw 'Installed runtime/task integrity failed.'}
    Start-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName
    Start-Sleep -Seconds 2
    $capabilities=Get-CpvPreparationCapabilities
    if($upgrade){
        if($capabilities.reconciliationOperation -cne 'cpv-preparation-reconcile-failed'){throw 'Installed agent does not advertise the exact reconciliation capability.'}
        $status=Invoke-CpvPreparationTransport $request
        foreach($name in 'requestId','taskId','workflowId','attemptId','runId','status','failureCode') {if($status.$name -cne $receipt.$name){throw "Protected preparation status changed during upgrade: $name"}}
        if(!(Test-CpvPreparationUpgradeEvidenceSnapshot -Before $evidenceSnapshot -EvidenceRoot $activeRoot -RunDirectory $upgrade.RunDirectory)){throw 'Protected preparation evidence changed during upgrade.'}
    }
    $null=Complete-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $token;$token=$null
    $capabilities|ConvertTo-Json
} catch {
    $failure=$_
    Stop-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName -ErrorAction SilentlyContinue
    $process=Get-Process Repato.QaLaunchAgent -ErrorAction SilentlyContinue
    if($process -and $process.Path -ieq $contract.Executable){Stop-Process -InputObject $process -Force}
    if($token){Restore-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $token|Out-Null}
    elseif($upgrade -and $installAttempted){
        $targetIntegrity=Get-RepatoQaLaunchAgentRuntimeIntegrity $contract.InstallRoot ([pscustomobject]@{files=$upgrade.PriorFiles})
        $restoredTask=Get-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName -ErrorAction SilentlyContinue
        $restoredTaskValid=$false;if($restoredTask){$restoredTaskValid=& (Get-Module Repato.QaLaunchAgent.Bootstrap) {param($task) Test-TaskSpec $task} $restoredTask}
        if(@($targetIntegrity|Where-Object {!$_.Match}).Count -or !$restoredTaskValid){throw 'Rollback token is unavailable and prior runtime/task could not be verified; scheduled task remains stopped.'}
    }
    Start-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName
    if($upgrade -and !(Test-CpvPreparationUpgradeEvidenceSnapshot -Before $evidenceSnapshot -EvidenceRoot $activeRoot -RunDirectory $upgrade.RunDirectory)){throw 'Protected preparation evidence changed during rollback.'}
    throw $failure
}
