[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReleaseRoot,[Parameter(Mandatory)][string]$ManifestSha256,[switch]$Execute,
    [string]$ReconcileRequestId,[string]$TaskId='task-bf61fe7f22d74df7a92599681da5919e')
$ErrorActionPreference='Stop'
function Get-CpvRevitProcesses {
    try { @(Get-Process -Name Revit -ErrorAction Stop) }
    catch {
        if($_.FullyQualifiedErrorId -like 'NoProcessFoundForGivenName,*'){ return @() }
        throw
    }
}
if(!$Execute){throw 'Installation is not automatic. Explicit deployment authorization and -Execute are required.'}
$principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Installation requires an elevated administrator PowerShell.'}
Import-Module (Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationRecovery.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationUpgrade.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
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
    if((Get-CpvRevitProcesses).Count){throw 'Revit is running; the guarded upgrade is unavailable.'}
    $agents=@(Get-Process -Name Repato.QaLaunchAgent -ErrorAction Stop)
    if($agents.Count -ne 1 -or $agents[0].ProcessName -cne 'Repato.QaLaunchAgent' -or $agents[0].Path -ine $contract.Executable){throw 'One exact installed Launch Agent process is required.'}
    $processIdentity=Get-RepatoQaLaunchAgentProcessIdentity -ProcessId $agents[0].Id
    if(!$processIdentity -or $processIdentity.ProcessName -cne 'Repato.QaLaunchAgent' -or $processIdentity.Path -ine $contract.Executable){throw 'Installed Launch Agent process identity is unavailable.'}
    $ownerSid=[string]$processIdentity.OwnerSid
    if(!$ownerSid){throw 'Installed Launch Agent process SID is unavailable.'}
    $ownerName=([Security.Principal.SecurityIdentifier]$ownerSid).Translate([Security.Principal.NTAccount]).Value
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
        -RequestId $ReconcileRequestId -TaskId $TaskId -Capabilities $capabilities -Receipt $receipt -InstalledAgent $installedIdentity -ProcessSid $ownerSid `
        -ExpectedExecutable $contract.Executable -ExpectedInstalledVersion '1.0.17+4b0066247088' -CandidateRoot $validated.SourceRoot `
        -CandidateManifestPath $manifest -CandidateManifestSha256 $ManifestSha256 -PriorRuntimeFiles $priorFiles `
        -PriorTaskContractValid ([bool]$priorTaskValid) -NoRevitProcesses $true
    $evidenceSnapshot=Get-CpvPreparationUpgradeEvidenceSnapshot -EvidenceRoot $activeRoot -RunDirectory $upgrade.RunDirectory
} elseif($ReconcileRequestId){throw 'A reconciliation request was supplied but no matching active marker exists.'}
$revit=Get-CpvRevitProcesses
if($revit.Count){throw 'Revit must be stopped.'}
$agents=@(Get-Process Repato.QaLaunchAgent -ErrorAction SilentlyContinue)
if($agents.Count -ne 1 -or $agents[0].Path -ine $contract.Executable){throw 'One exact installed Launch Agent process is required.'}
if(!$capabilities){$capabilities=Get-CpvPreparationCapabilities}
$agentHealth=Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 3000
if(!$agentHealth.Ready -or $agentHealth.User -ine 'RAMSAI\RepatoQA' -or $agentHealth.Sid -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or $agentHealth.SessionId -ne $agents[0].SessionId -or $agentHealth.SessionId -ne $capabilities.sessionId){throw 'Installed Launch Agent authenticated session identity is invalid.'}
$token=$null;$installAttempted=$false;$journalLease=$null
try {
    if($upgrade){
        $journalLease=New-RepatoQaLaunchAgentBootstrapInstallJournal -SourceRoot $ReleaseRoot -ManifestPath $manifest -ManifestSha256 $ManifestSha256 -RequestId $ReconcileRequestId -TaskId $TaskId
        $bootstrap=Get-Module Repato.QaLaunchAgent.Bootstrap
        & $bootstrap {param($lease) $j=Get-InstallJournal $lease;if($j.state -cne 'CandidateStaged'){throw 'Candidate stage was not durably verified.'};Set-InstallJournalState $j 'ServiceStopPending'|Out-Null} $journalLease
    }
    Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid $agents[0].Id -ExpectedAgentStartTime $agents[0].StartTime.ToString('o') -ExpectedSessionId $capabilities.sessionId -AgentExe $contract.Executable -TaskPath $contract.TaskPath -TaskName $contract.TaskName
    if($journalLease){& (Get-Module Repato.QaLaunchAgent.Bootstrap) {param($lease) $j=Get-InstallJournal $lease;if($j.state -cne 'ServiceStopPending'){throw 'Service-stop boundary was not durably recorded.'};Set-InstallJournalState $j 'ServiceStopped'|Out-Null} $journalLease}
    $installAttempted=$true
    $installed=Install-RepatoQaLaunchAgentBootstrap -SourceRoot $ReleaseRoot -ManifestPath $manifest -ManifestSha256 $ManifestSha256 -RetainRollback -DurableJournal $journalLease
    $token=$installed.RollbackToken
    if($upgrade){
        if(!$token -or !$token.Updated -or !$token.BackupRoot -or !(Test-Path -LiteralPath $token.BackupRoot -PathType Container) -or !$token.OldTaskXml){throw 'Verified prior-runtime rollback evidence was not retained.'}
        $backup=Get-RepatoQaLaunchAgentRuntimeIntegrity $token.BackupRoot ([pscustomobject]@{files=$token.PriorFiles})
        if(@($backup|Where-Object {!$_.Match}).Count){throw 'Retained rollback bytes failed integrity validation.'}
        foreach($prior in $upgrade.PriorFiles){$bound=@($token.PriorFiles|Where-Object name -ceq $prior.name);if($bound.Count -ne 1 -or $bound[0].sha256 -ine $prior.sha256){throw 'Retained rollback bytes differ from the verified prior runtime.'}}
    }
    $checked=Test-RepatoQaLaunchAgentBootstrap -ManifestPath $manifest -ManifestSha256 $ManifestSha256
    if(!$checked.InstalledRuntimeIntegrity -or !$checked.TaskContractValid){throw 'Installed runtime/task integrity failed.'}
    if($journalLease){Set-RepatoQaLaunchAgentBootstrapInstallHealthVerification -JournalLease $journalLease}
    Start-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName
    Start-Sleep -Seconds 2
    $capabilities=Get-CpvPreparationCapabilities
    if($upgrade){
        if($capabilities.reconciliationOperation -cne 'cpv-preparation-reconcile-failed'){throw 'Installed agent does not advertise the exact reconciliation capability.'}
        $status=Invoke-CpvPreparationTransport $request
        foreach($name in 'requestId','taskId','workflowId','attemptId','runId','status','failureCode') {if($status.$name -cne $receipt.$name){throw "Protected preparation status changed during upgrade: $name"}}
        if(!(Test-CpvPreparationUpgradeEvidenceSnapshot -Before $evidenceSnapshot -EvidenceRoot $activeRoot -RunDirectory $upgrade.RunDirectory)){throw 'Protected preparation evidence changed during upgrade.'}
    }
    $null=Complete-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $token;$token=$null;$journalLease=$null
    $capabilities|ConvertTo-Json
} catch {
    $failure=$_
    $durableRecoveryHandled=$false
    if($token -and $token.DurableJournal){Restore-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $token|Out-Null;$durableRecoveryHandled=$true}
    elseif($journalLease){
        try{& (Get-Module Repato.QaLaunchAgent.Bootstrap) {param($lease,$context) Invoke-InstallJournalRecoveryCore $lease $context} $journalLease (& (Get-Module Repato.QaLaunchAgent.Bootstrap) { New-RealBootstrapContext })|Out-Null}
        finally{& (Get-Module Repato.QaLaunchAgent.Bootstrap) {param($lease) Close-InstallJournalLease $lease} $journalLease}
        $durableRecoveryHandled=$true
    }
    if(!$durableRecoveryHandled){
        $rollbackVerified=$false
        $processes=@(Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue)
        if($processes.Count -gt 1){throw 'Multiple Launch Agent processes prevent safe installer recovery; task remains stopped.'}
        if($processes.Count){
            $process=$processes[0]
            if($process.Path -ine $contract.Executable){throw 'Unexpected Launch Agent process prevents safe installer recovery; task remains stopped.'}
            $health=Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 3000
            if(!$health.Ready -or $health.User -ine 'RAMSAI\RepatoQA' -or $health.Sid -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or $health.SessionId -ne $process.SessionId){throw 'Launch Agent session identity is unverified; task remains stopped.'}
            Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid $process.Id -ExpectedAgentStartTime $process.StartTime.ToString('o') -ExpectedSessionId $health.SessionId -AgentExe $contract.Executable -TaskPath $contract.TaskPath -TaskName $contract.TaskName
        } else {
            $task=Get-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName -ErrorAction Stop
            if($task.State.ToString() -ceq 'Running'){throw 'Scheduled task is running without an identifiable agent; installer recovery is ambiguous.'}
        }
        if($token){
            $token=Restore-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $token
            if(@($token.RuntimeIntegrity|Where-Object {!$_.Match}).Count){throw 'Restored Launch Agent runtime integrity failed; task remains stopped.'}
            $task=Get-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName -ErrorAction Stop
            if(!(& (Get-Module Repato.QaLaunchAgent.Bootstrap) {param($task) Test-TaskSpec $task} $task)){throw 'Restored Launch Agent task contract failed; task remains stopped.'}
            $rollbackVerified=$true
        }
        elseif($upgrade -and $installAttempted){
            $targetIntegrity=Get-RepatoQaLaunchAgentRuntimeIntegrity $contract.InstallRoot ([pscustomobject]@{files=$upgrade.PriorFiles})
            $restoredTask=Get-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName -ErrorAction SilentlyContinue
            $restoredTaskValid=$false;if($restoredTask){$restoredTaskValid=& (Get-Module Repato.QaLaunchAgent.Bootstrap) {param($task) Test-TaskSpec $task} $restoredTask}
            if(@($targetIntegrity|Where-Object {!$_.Match}).Count -or !$restoredTaskValid){throw 'Rollback token is unavailable and prior runtime/task could not be verified; scheduled task remains stopped.'}
            $rollbackVerified=$true
        }
        if(!$rollbackVerified){throw 'Verified rollback evidence is unavailable; scheduled task remains stopped for manual recovery.'}
        Start-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName
    }
    if($upgrade -and !(Test-CpvPreparationUpgradeEvidenceSnapshot -Before $evidenceSnapshot -EvidenceRoot $activeRoot -RunDirectory $upgrade.RunDirectory)){throw 'Protected preparation evidence changed during rollback.'}
    throw $failure
}
