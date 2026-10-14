$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root=Join-Path $base ('maya-ambiguous-launch-'+[guid]::NewGuid().ToString('N'))
$store=Join-Path $root 'store';$runtime=Join-Path $root 'runtime';$files=Join-Path $root 'files'
New-Item -ItemType Directory -Path $runtime,$files -Force|Out-Null
try {
    $taskId='synthetic-ambiguous-launch-task';$workflowId='synthetic-ambiguous-launch-workflow';$qa='create-plan-views-v1';$attemptId=[guid]::NewGuid().ToString('N');$runId=[guid]::NewGuid().ToString('N');$claimId=[guid]::NewGuid().ToString('N')
    New-RepatoTask $store $taskId 'synthetic launch disposition' 'isolated synthetic workflow' 'qa/synthetic-launch-disposition' 'maya'|Out-Null
    $manifest=Join-Path $files 'Repato.CreatePlanViews.TestRunner.addin';[IO.File]::WriteAllText($manifest,'synthetic runner manifest');$manifestHash=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
    $task=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId
    $attempt=[pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;AttemptId=$attemptId;RunId=$runId;RequestExpiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(10).ToString('O')}
    $execution=[pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qa;TestId=$qa;HandoffId='synthetic-handoff';AttemptId=$attemptId;RunId=$runId;ClaimOwner='Tara';ClaimId=$claimId;ClaimStatus='claimed';Stage='claimed';ExecutionStatus='Claimed';TaskRevisionAtClaim=([long]$task.revision-1);DisposableRuntimeRoot=$runtime;DisposableModelPath=(Join-Path $runtime 'model.rvt');DisposableModelSha256=('A'*64);AuthoritativeFixtureSha256=('B'*64);RunnerManifestPath=$manifest;RunnerManifestSha256=$manifestHash;ValidatedRunnerManifestPath=$manifest;ValidatedRunnerManifestSha256=$manifestHash;LaunchingUtc=$null;FailedUtc=$null;FailureCode=$null;FailureDetails=$null;RequestPath=$null;NativeRequestId=$null;NativeProcessId=$null;SideEffectsPerformed=$false;FixturePreparationEvidence=[pscustomobject]@{RequestPath='synthetic-request';RequestSha256=('C'*64);ResultPath='synthetic-result';ResultSha256=('D'*64);AttemptId='synthetic-prep-attempt';RunId='synthetic-prep-run'}}
    Invoke-RepatoStoreMutation $store {param($data,$preview)$t=Find-RepatoTask $data $taskId;$t|Add-Member NoteProperty mayaPlan ([pscustomobject]@{WorkflowId=$workflowId;QaWorkflowId=$qa}) -Force;$t|Add-Member NoteProperty mayaTaraAttempt $attempt -Force;$t|Add-Member NoteProperty mayaTaraExecution $execution -Force;$t}|Out-Null
    $state=[pscustomobject]@{Accepted=$false};$lostResponse={param($exe,$args)$state.Accepted=$true;throw 'Synthetic accepted launch followed by lost response.'}.GetNewClosure()
    $threw=$false;$launchError=$null
    try { Invoke-MayaQaCanonicalNativeCore -StoreRoot $store -TaskId $taskId -ClaimId $claimId -Executable 'synthetic-revit.exe' -Arguments '' -ProcessLauncher $lostResponse -ManifestValidationBoundary {param($path,$hash)$true}|Out-Null } catch {$threw=$true;$launchError=$_.Exception.Message+' at '+$_.ScriptStackTrace}
    $current=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId;$record=$current.mayaTaraExecution
    if(!$state.Accepted -or !$threw -or $record.Stage -cne 'launch-outcome-unknown' -or $record.ExecutionStatus -cne 'LaunchOutcomeUnknown' -or $record.FailureCode -cne 'native-launch-outcome-unknown' -or !$record.SideEffectsPerformed -or !$record.RequestPath -or !$record.NativeRequestId){throw "Lost response was not persisted as ambiguous: accepted=$($state.Accepted);threw=$threw;error=$launchError;stage=$($record.Stage);status=$($record.ExecutionStatus);code=$($record.FailureCode);sideEffects=$($record.SideEffectsPerformed);request=$($record.RequestPath);nativeRequest=$($record.NativeRequestId)"}
    $retryRejected=$false;try{Invoke-MayaQaCanonicalNativeCore -StoreRoot $store -TaskId $taskId -ClaimId $claimId -Executable 'synthetic-revit.exe' -ProcessLauncher {throw 'duplicate dispatch boundary reached'} -ManifestValidationBoundary {param($path,$hash)$true}|Out-Null}catch{$retryRejected=$true}
    if(!$retryRejected){throw 'Duplicate dispatch was accepted after an ambiguous launch.'}
    $recoveryRejected=$false;try{Recover-MayaQaTerminalLaunchFailure -StoreRoot $store -TaskId $taskId -DryRun|Out-Null}catch{$recoveryRejected=$true}
    if(!$recoveryRejected){throw 'Ambiguous launch was incorrectly accepted by terminal launch-failure recovery.'}
    [pscustomobject]@{SyntheticAcceptedThenLostResponse='PASS';AmbiguousStatePersisted='PASS';DuplicateDispatchRejected='PASS';AutomaticRecoveryRejected='PASS';UsesTemporaryStore=$true;NativeAgentInvoked=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
} finally {
    if([IO.Path]::GetFullPath($root).StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $root)){Remove-Item -LiteralPath $root -Recurse -Force}
}
