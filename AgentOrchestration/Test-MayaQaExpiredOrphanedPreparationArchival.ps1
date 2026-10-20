$ErrorActionPreference='Stop'
$here=$PSScriptRoot
Import-Module (Join-Path $here 'Repato.AgentOrchestration.psm1') -Force
$module=Import-Module (Join-Path $here 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue -PassThru
$root=Join-Path ([IO.Path]::GetTempPath()) ('maya-expired-orphaned-preparation-'+[guid]::NewGuid().ToString('N'))
$taskId='task-expired-orphaned-preparation';$workflowId='workflow-expired-orphaned-preparation'
$failedAttempt='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';$failedRun='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
$orphanedRun='dddddddddddddddddddddddddddddddd'
try {
    $qa=Join-Path $root 'QA';$runs=Join-Path $qa 'TestRuns';$fixtures=Join-Path $qa 'Fixtures';$prepRuntime=Join-Path $runs ('fixture-preparation-'+$orphanedRun)
    $null=New-Item -ItemType Directory -Path $prepRuntime,$fixtures -Force
    & $module {param($qaRoot) $script:RecoveryTestQaRoot=$qaRoot;Set-Item -Path Function:Get-MayaQaRoot -Value { $script:RecoveryTestQaRoot };Set-Item -Path Function:Get-MayaQaRuntimeRoot -Value { Join-Path $script:RecoveryTestQaRoot 'TestRuns' }} $qa
    $source=Join-Path $fixtures 'CreatePlanViewsEmpty.rvt';[IO.File]::WriteAllBytes($source,[byte[]](4,3,2,1));$sourceHash=(Get-FileHash $source -Algorithm SHA256).Hash
    $model=Join-Path $prepRuntime 'model.rvt';[IO.File]::WriteAllBytes($model,[byte[]](1,2,3,4));$modelHash=(Get-FileHash $model -Algorithm SHA256).Hash
    $prepRequestPath=Join-Path $prepRuntime 'tara-expired-orphaned.request.json';$prepResultPath=$prepRequestPath+'.preparation.json'
    ([ordered]@{operation='prepare-disposable-create-plan-views-fixture';taskId=$taskId;workflowId=$workflowId;attemptId=$failedAttempt;runId=$orphanedRun;requestPath=$prepRequestPath;modelPath=$model;modelSha256=$sourceHash;outputPath=$prepResultPath;expiresUtc='2026-10-20T00:00:00+00:00'}|ConvertTo-Json)|Set-Content $prepRequestPath
    ([ordered]@{SchemaVersion=1;Operation='prepare-disposable-create-plan-views-fixture';Status='Passed';TaskId=$taskId;WorkflowId=$workflowId;AttemptId=$failedAttempt;RunId=$orphanedRun;ModelPath=$model;SourceModelSha256=$sourceHash;PreparedModelSha256=$modelHash}|ConvertTo-Json)|Set-Content $prepResultPath
    $prepRequestSha=(Get-FileHash $prepRequestPath -Algorithm SHA256).Hash;$prepResultSha=(Get-FileHash $prepResultPath -Algorithm SHA256).Hash
    $fpe=[pscustomobject][ordered]@{RequestPath=$prepRequestPath;RequestSha256=$prepRequestSha;ResultPath=$prepResultPath;ResultSha256=$prepResultSha;AttemptId=$failedAttempt;RunId=$orphanedRun;SourceSha256=$sourceHash;PreparedModelPath=$model;PreparedModelSha256=$modelHash}
    $store=Join-Path $root 'Store';New-RepatoTask $store $taskId 'Expired orphaned preparation archival' 'orphan archival contract' 'qa/orphan-archival'|Out-Null
    Invoke-RepatoStoreMutation $store {param($d,$preview)
        $t=Find-RepatoTask $d $taskId;$t.revision=8;$t.status='in-progress';$t.workflowStage='build-checks'
        $t|Add-Member NoteProperty mayaQaCandidateReplacementRetirement ([pscustomobject]@{WorkflowId=$workflowId;FailedAttemptId=$failedAttempt;RecoveredAttemptId='dddddddddddddddddddddddddddddddd';RecoveredRunId='c0ffee00000000000000000000000003';RetiredUtc='2026-10-20T00:00:00+00:00';ApprovalRequestId='consumed-approval';ConsumedApprovalPreserved=$true;NativeLaunchAbsent=$true}) -Force
        $t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@([pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;AttemptId=$failedAttempt;RunId=$failedRun;Stage='qa-failed';ExecutionStatus='QaFailed';FailureCode='native-qa-failed';SideEffectsPerformed=$true})) -Force
        $t|Add-Member NoteProperty approvalRequests ([object[]]@([pscustomobject]@{requestId='consumed-approval';action='qa-run';status='approved';consumedUtc='2026-10-20T05:00:00Z';executionBinding=[pscustomobject]@{RunId=$orphanedRun}})) -Force
        $handoffEntry=[pscustomobject]@{RunId=$orphanedRun;ArchivedUtc='2026-10-20T00:00:00+00:00';Reason='Superseded'}
        $workflowRec=[pscustomobject][ordered]@{taskId=$taskId;workflowId=$workflowId;qaWorkflowId='create-plan-views-v1';stage='planned';workflowRevision=5;qaBuildStatus='succeeded';qaBuildRequest=[pscustomobject]@{BuildRequestId='build-orphan'};qaBuildEvidence=[pscustomobject]@{ArtifactSha256=('B'*64);DeploymentValidation=$true;ManifestIntegrityValidation=$true;QaIsolation=$true};qaFixturePreparationEvidence=$fpe;qaDisposableModelSha256=$modelHash;qaHandoffHistory=[object[]]@($handoffEntry);qaRunHistory=[object[]]@()}
        $t|Add-Member NoteProperty deploymentWorkflows ([object[]]@($workflowRec)) -Force
        $t
    }|Out-Null
    $revisionBefore=[long](Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;[long]$t.revision})
    $wRevisionBefore=[long](Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;[long]@($t.deploymentWorkflows|Where-Object {$_.workflowId -ceq $workflowId})[0].workflowRevision})
    $badIdentityRejected=$false
    try{Remove-MayaQaExpiredOrphanedPreparation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -ExpectedFailedAttemptId 'ffffffffffffffffffffffffffffffff' -ExpectedOrphanedRunId $orphanedRun -ProcessProvider { @() }|Out-Null}catch{$badIdentityRejected=$_.Exception.Message -match 'retirement identity is invalid'}
    if(!$badIdentityRejected){throw 'Wrong failed-attempt identity was not rejected.'}
    $activeApprovalRejected=$false
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.approvalRequests=@($t.approvalRequests)+@([pscustomobject]@{requestId='pending-approval';action='qa-run';status='pending';expiresUtc='2099-01-01T00:00:00Z'});$t}|Out-Null
    try{Remove-MayaQaExpiredOrphanedPreparation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -ExpectedFailedAttemptId $failedAttempt -ExpectedOrphanedRunId $orphanedRun -ProcessProvider { @() }|Out-Null}catch{$activeApprovalRejected=$_.Exception.Message -match 'unexpired QA approval'}
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.approvalRequests=@($t.approvalRequests|Where-Object {$_.requestId -cne 'pending-approval'});$t}|Out-Null
    if(!$activeApprovalRejected){throw 'Pending QA approval did not block the archival.'}
    $activeAttemptRejected=$false
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t|Add-Member NoteProperty mayaTaraAttempt ([pscustomobject]@{AttemptId='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'}) -Force;$t}|Out-Null
    try{Remove-MayaQaExpiredOrphanedPreparation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -ExpectedFailedAttemptId $failedAttempt -ExpectedOrphanedRunId $orphanedRun -ProcessProvider { @() }|Out-Null}catch{$activeAttemptRejected=$_.Exception.Message -match 'Active Tara execution state'}
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.PSObject.Properties.Remove('mayaTaraAttempt');$t}|Out-Null
    if(!$activeAttemptRejected){throw 'Active Tara attempt did not block the archival.'}
    $revitRunningRejected=$false
    try{Remove-MayaQaExpiredOrphanedPreparation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -ExpectedFailedAttemptId $failedAttempt -ExpectedOrphanedRunId $orphanedRun -ProcessProvider { ,[pscustomobject]@{Id=4242} }|Out-Null}catch{$revitRunningRejected=$_.Exception.Message -match 'blocked while Revit is running'}
    if(!$revitRunningRejected){throw 'Running Revit process did not block the archival.'}
    $modelHashMismatchRejected=$false
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$w=@($t.deploymentWorkflows|Where-Object {$_.workflowId -ceq $workflowId})[0];$w.qaDisposableModelSha256=('A'*64);$t}|Out-Null
    try{Remove-MayaQaExpiredOrphanedPreparation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -ExpectedFailedAttemptId $failedAttempt -ExpectedOrphanedRunId $orphanedRun -ProcessProvider { @() }|Out-Null}catch{$modelHashMismatchRejected=$_.Exception.Message -match 'disposable model hash'}
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$w=@($t.deploymentWorkflows|Where-Object {$_.workflowId -ceq $workflowId})[0];$w.qaDisposableModelSha256=$modelHash;$t}|Out-Null
    if(!$modelHashMismatchRejected){throw 'Disposable model hash mismatch was not rejected.'}
    $futureExpiryRejected=$false
    $futureRequest=Get-Content $prepRequestPath -Raw|ConvertFrom-Json;$futureRequest.expiresUtc='2099-01-01T00:00:00+00:00';$futureRequest|ConvertTo-Json|Set-Content $prepRequestPath;$futureRequestSha=(Get-FileHash $prepRequestPath -Algorithm SHA256).Hash
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$w=@($t.deploymentWorkflows|Where-Object {$_.workflowId -ceq $workflowId})[0];$w.qaFixturePreparationEvidence.RequestSha256=$futureRequestSha;$t}|Out-Null
    try{Remove-MayaQaExpiredOrphanedPreparation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -ExpectedFailedAttemptId $failedAttempt -ExpectedOrphanedRunId $orphanedRun -ProcessProvider { @() }|Out-Null}catch{$futureExpiryRejected=$_.Exception.Message -match 'has not expired'}
    if(!$futureExpiryRejected){throw 'Unexpired orphaned preparation was not rejected.'}
    ($(Get-Content $prepRequestPath -Raw|ConvertFrom-Json)).expiresUtc='2026-10-20T00:00:00+00:00'
    ([ordered]@{operation='prepare-disposable-create-plan-views-fixture';taskId=$taskId;workflowId=$workflowId;attemptId=$failedAttempt;runId=$orphanedRun;requestPath=$prepRequestPath;modelPath=$model;modelSha256=$sourceHash;outputPath=$prepResultPath;expiresUtc='2026-10-20T00:00:00+00:00'}|ConvertTo-Json)|Set-Content $prepRequestPath
    $prepRequestSha=(Get-FileHash $prepRequestPath -Algorithm SHA256).Hash
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$w=@($t.deploymentWorkflows|Where-Object {$_.workflowId -ceq $workflowId})[0];$w.qaFixturePreparationEvidence.RequestSha256=$prepRequestSha;$t}|Out-Null
    $missingHandoffRejected=$false
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$w=@($t.deploymentWorkflows|Where-Object {$_.workflowId -ceq $workflowId})[0];$w.qaHandoffHistory=[object[]]@([pscustomobject]@{RunId='00000000000000000000000000000000';ArchivedUtc='2026-10-20T00:00:00+00:00'});$t}|Out-Null
    try{Remove-MayaQaExpiredOrphanedPreparation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -ExpectedFailedAttemptId $failedAttempt -ExpectedOrphanedRunId $orphanedRun -ProcessProvider { @() }|Out-Null}catch{$missingHandoffRejected=$_.Exception.Message -match 'Archived prior run identity'}
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$w=@($t.deploymentWorkflows|Where-Object {$_.workflowId -ceq $workflowId})[0];$w.qaHandoffHistory=[object[]]@([pscustomobject]@{RunId=$orphanedRun;ArchivedUtc='2026-10-20T00:00:00+00:00';Reason='Superseded'});$t}|Out-Null
    if(!$missingHandoffRejected){throw 'Missing archived handoff run was not rejected.'}
    $dry=Remove-MayaQaExpiredOrphanedPreparation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -ExpectedFailedAttemptId $failedAttempt -ExpectedOrphanedRunId $orphanedRun -ProcessProvider { @() } -DryRun
    if($dry.SideEffectsPerformed -or $dry.OrphanedRunId -ne $orphanedRun){throw 'Dry-run archival contract failed.'}
    $revisionAfterDry=[long](Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;[long]$t.revision})
    if($revisionAfterDry -ne $revisionBefore){throw 'Dry-run archival mutated the task store.'}
    $archived=Remove-MayaQaExpiredOrphanedPreparation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -ExpectedFailedAttemptId $failedAttempt -ExpectedOrphanedRunId $orphanedRun -ProcessProvider { @() }
    if($archived.Status -cne 'Archived' -or !$archived.SideEffectsPerformed){throw 'Archival result contract failed.'}
    $t=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId;$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $workflowId)[0]
    if($w.PSObject.Properties['qaFixturePreparationEvidence'] -or $w.PSObject.Properties['qaDisposableModelSha256']){throw 'Expired orphaned preparation was not removed from the workflow.'}
    if(@($w.qaFixturePreparationEvidenceHistory).Count -ne 1){throw 'Archived preparation history was not appended exactly once.'}
    $entry=$w.qaFixturePreparationEvidenceHistory[0]
    if($entry.Reason -cne 'expired-orphaned-preparation-superseded' -or (Get-FileHash $prepRequestPath -Algorithm SHA256).Hash -ine $entry.Evidence.RequestSha256){throw 'Archived preparation evidence identity is invalid.'}
    if($w.workflowRevision -ne ($wRevisionBefore+1) -or $t.workflowStage -cne 'build-checks'){throw 'Workflow revision or stage was not advanced correctly.'}
    if(@($t.approvalRequests|Where-Object {$_.requestId -ceq 'consumed-approval' -and $_.status -ceq 'approved' -and $_.consumedUtc}).Count -ne 1){throw 'Consumed approval was changed by archival.'}
    $repeatRejected=$false
    try{Remove-MayaQaExpiredOrphanedPreparation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -ExpectedFailedAttemptId $failedAttempt -ExpectedOrphanedRunId $orphanedRun -ProcessProvider { @() }|Out-Null}catch{$repeatRejected=$_.Exception.Message -match 'No expired orphaned preparation evidence is present'}
    if(!$repeatRejected){throw 'Repeated archival unexpectedly succeeded.'}
    $dryRun=New-MayaQaRun -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId 'create-plan-views-v1' -RunId 'freshRunBecauseArchivalCompleted' -ExpectedTaskRevision ([long]$t.revision) -DryRun
    if($dryRun.RunId -ne 'freshRunBecauseArchivalCompleted'){throw 'Fresh plan dry-run did not accept the archived state.'}
    [pscustomobject]@{Success=$true;DryRunWasReadOnly=$true;WrongIdentityRejected=$true;ActiveApprovalBlocked=$true;ActiveAttemptBlocked=$true;RevitRunningBlocked=$true;ModelHashMismatchRejected=$true;FutureExpiryRejected=$true;MissingHandoffRejected=$true;ArchivedExactlyOnce=$true;RepeatRejected=$true;FreshPlanDryRunAllowed=$true}|ConvertTo-Json -Compress
} finally {if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
