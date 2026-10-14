$ErrorActionPreference='Stop'
$here=$PSScriptRoot
Import-Module (Join-Path $here 'Repato.AgentOrchestration.psm1') -Force
$module=Import-Module (Join-Path $here 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue -PassThru
$root=Join-Path ([IO.Path]::GetTempPath()) ('maya-native-prepared-recovery-'+[guid]::NewGuid().ToString('N'))
$taskId='task-native-prepared-recovery';$workflowId='workflow-native-prepared-recovery';$qaWorkflowId='create-plan-views-v1'
$oldAttempt=[guid]::NewGuid().ToString('N');$oldRun=[guid]::NewGuid().ToString('N');$claimId=[guid]::NewGuid().ToString('N');$nativeRequestId=[guid]::NewGuid().ToString('N')
$inspectorState=[pscustomobject]@{Calls=0};$processInspector={param($pid,$execution)$inspectorState.Calls++;$null}.GetNewClosure()
try {
    $qa=Join-Path $root 'QA';$fixtures=Join-Path $qa 'Fixtures';$runs=Join-Path $qa 'TestRuns';$reports=Join-Path $qa 'Reports';$oldRuntime=Join-Path $runs 'old-runtime';$prepRuntime=Join-Path $runs 'fixture-preparation'
    $null=New-Item -ItemType Directory -Path $fixtures,$oldRuntime,$prepRuntime,$reports -Force
    & $module {param($qaRoot) $script:RecoveryTestQaRoot=$qaRoot;Set-Item -Path Function:Get-MayaQaRoot -Value { $script:RecoveryTestQaRoot }} $qa

    $source=Join-Path $fixtures 'CreatePlanViewsEmpty.rvt';$prepModel=Join-Path $prepRuntime 'model.rvt';$oldModel=Join-Path $oldRuntime 'model.rvt'
    [IO.File]::WriteAllBytes($source,[byte[]](1,2,3,4));[IO.File]::WriteAllBytes($prepModel,[byte[]](5,6,7,8));Copy-Item $prepModel $oldModel
    $sourceHash=(Get-FileHash $source -Algorithm SHA256).Hash;$preparedHash=(Get-FileHash $prepModel -Algorithm SHA256).Hash
    $launchUtc=[DateTimeOffset]::UtcNow.AddSeconds(-30);$decisionUtc=$launchUtc.AddMinutes(-1);$approvalExpiry=[DateTimeOffset]::UtcNow.AddMinutes(5)
    $prepAttempt=[guid]::NewGuid().ToString('N');$prepRun=[guid]::NewGuid().ToString('N');$prepRequest=Join-Path $prepRuntime 'fixture.request.json';$prepResult=$prepRequest+'.preparation.json'
    ([ordered]@{operation='prepare-disposable-create-plan-views-fixture';taskId=$taskId;workflowId=$workflowId;attemptId=$prepAttempt;runId=$prepRun;requestPath=$prepRequest;modelPath=$prepModel;modelSha256=$sourceHash;outputPath=$prepResult}|ConvertTo-Json -Depth 6)|Set-Content -LiteralPath $prepRequest -Encoding UTF8
    ([ordered]@{Status='Passed';Operation='prepare-disposable-create-plan-views-fixture';TaskId=$taskId;WorkflowId=$workflowId;AttemptId=$prepAttempt;RunId=$prepRun;ModelPath=$prepModel;SourceModelSha256=$sourceHash;PreparedModelSha256=$preparedHash}|ConvertTo-Json -Depth 6)|Set-Content -LiteralPath $prepResult -Encoding UTF8
    $prepEvidence=[pscustomobject]@{RequestPath=$prepRequest;RequestSha256=(Get-FileHash $prepRequest -Algorithm SHA256).Hash;ResultPath=$prepResult;ResultSha256=(Get-FileHash $prepResult -Algorithm SHA256).Hash;AttemptId=$prepAttempt;RunId=$prepRun;SourceSha256=$sourceHash;PreparedModelPath=$prepModel;PreparedModelSha256=$preparedHash}
    ([ordered]@{fixtureId='CreatePlanViewsEmpty';sourceSha256=$sourceHash;preparedModelSha256=$preparedHash;fixturePreparationRequestPath=$prepEvidence.RequestPath;fixturePreparationRequestSha256=$prepEvidence.RequestSha256;fixturePreparationResultPath=$prepEvidence.ResultPath;fixturePreparationResultSha256=$prepEvidence.ResultSha256;fixturePreparationAttemptId=$prepAttempt;fixturePreparationRunId=$prepRun}|ConvertTo-Json -Depth 6)|Set-Content -LiteralPath ($oldModel+'.fixture.json') -Encoding UTF8

    $artifact=Join-Path $root 'Repato.Revit.dll';$manifest=Join-Path $root 'runner.addin';$isolation=Join-Path $root 'isolation.json'
    foreach($path in @($artifact,$manifest,$isolation)){[IO.File]::WriteAllText($path,[guid]::NewGuid().ToString('N'))}
    $artifactHash=(Get-FileHash $artifact -Algorithm SHA256).Hash;$manifestHash=(Get-FileHash $manifest -Algorithm SHA256).Hash;$isolationHash=(Get-FileHash $isolation -Algorithm SHA256).Hash
    $requestPath=Join-Path $oldRuntime 'failed.request.json';$resultPath=$requestPath+'.result.json';$reportPath=Join-Path $reports ($oldRun+'.json')
    $handoffId=[guid]::NewGuid().ToString('N')
    $request=[ordered]@{requestId=$nativeRequestId;TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaWorkflowId;TestId=$qaWorkflowId;HandoffId=$handoffId;AttemptId=$oldAttempt;RunId=$oldRun;ClaimId=$claimId;modelPath=$oldModel;modelSha256=$preparedHash}
    $request|ConvertTo-Json|Set-Content -LiteralPath $requestPath -Encoding UTF8
    $receipt=[ordered]@{RequestId=$nativeRequestId;TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaWorkflowId;TestId=$qaWorkflowId;HandoffId=$handoffId;AttemptId=$oldAttempt;RunId=$oldRun;ClaimId=$claimId;ReportPath=$reportPath;Status='Failed'}
    $receipt|ConvertTo-Json|Set-Content -LiteralPath $resultPath -Encoding UTF8
    $report=[ordered]@{RequestId=$nativeRequestId;TaskId=$taskId;WorkflowId=$workflowId;TestId=$qaWorkflowId;AttemptId=$oldAttempt;RunId=$oldRun;ClaimId=$claimId;Status='Failed';DocumentPath='';RollbackStatus='NotStarted';Errors=@('An existing .rvt file is required.');CreatedIds=@();ChangedIds=@();DeletedIds=@();Screenshots=@()}
    $report|ConvertTo-Json|Set-Content -LiteralPath $reportPath -Encoding UTF8
    $resultHash=(Get-FileHash $resultPath -Algorithm SHA256).Hash;$reportHash=(Get-FileHash $reportPath -Algorithm SHA256).Hash

    $store=Join-Path $root 'Store';New-RepatoTask $store $taskId 'Synthetic recovery' 'Prepared fixture recovery contract' 'qa/native-prepared-recovery'|Out-Null
    Invoke-RepatoStoreMutation $store {
        param($data,$preview);$task=Find-RepatoTask $data $taskId;$task.revision=7;$task.status='in-progress';$task.workflowStage='approval'
        $task|Add-Member NoteProperty mayaPlan ([pscustomobject]@{WorkflowId=$workflowId;QaWorkflowId=$qaWorkflowId}) -Force
        $task|Add-Member NoteProperty mayaTaraQaPacket ([pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaWorkflowId;HandoffId=$handoffId}) -Force
        $task|Add-Member NoteProperty mayaTaraAttempt ([pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;AttemptId=$oldAttempt;RunId=$oldRun;RequestExpiresUtc=$approvalExpiry.ToString('O')}) -Force
        $task|Add-Member NoteProperty mayaTaraExecution ([pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaWorkflowId;TestId=$qaWorkflowId;HandoffId=$handoffId;AttemptId=$oldAttempt;RunId=$oldRun;ClaimOwner='Tara';ClaimId=$claimId;ClaimStatus='claimed';Stage='executing';ExecutionStatus='Executing';NativeProcessId=4242;NativeRequestId=$nativeRequestId;RequestPath=$requestPath;LaunchedUtc=$launchUtc.ToString('O');DisposableRuntimeRoot=$oldRuntime;DisposableModelPath=$oldModel;DisposableModelSha256=$preparedHash;FixturePreparationEvidence=$prepEvidence;AuthoritativeFixturePath=$source;AuthoritativeFixtureSha256=$sourceHash;ArtifactPath=$artifact;ArtifactSha256=$artifactHash;RunnerManifestPath=$manifest;RunnerManifestSha256=$manifestHash;IsolationPolicyPath=$isolation;IsolationPolicySha256=$isolationHash;IsolationAllowed=$true;SideEffectsPerformed=$false;EvidencePath=$null;VerificationStatus='Pending';CompletionStatus='Pending'}) -Force
        $binding=[pscustomobject][ordered]@{SchemaVersion='maya-qa-startup-retest-approval-v1';TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaWorkflowId;AttemptId=$oldAttempt;RunId=$oldRun;CandidateSha256=$artifactHash;ModelPath=$oldModel;ModelSha256=$preparedHash}
        $json=ConvertTo-Json -InputObject $binding -Depth 20 -Compress;$sha=[Security.Cryptography.SHA256]::Create();try{$bindingHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$sha.Dispose()}
        $task.approvalRequests=[object[]]@([pscustomobject]@{requestId=[guid]::NewGuid().ToString('N');action='qa-run';requiredLevel='user';status='approved';bindingHash=$bindingHash;recoveryBinding=$binding;attemptId=$oldAttempt;runId=$oldRun;previousStatus='in-progress';requestedRevision=6;approvedRevision=7;requestedUtc=$decisionUtc.AddMinutes(-1).ToString('O');expiresUtc=$approvalExpiry.ToString('O');decidedUtc=$decisionUtc.ToString('O');decidedBy='user';reason='synthetic approved QA';consumedUtc=$null})
        $task
    }|Out-Null

    $beforeRecovery=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId;$runtimeCountBefore=@(Get-ChildItem -LiteralPath $runs -Directory).Count
    $report.DocumentPath=$oldModel;$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $reportPath -Encoding UTF8
    $rejected=$false;try{Recover-MayaQaCorrelatedNativeFailure -StoreRoot $store -TaskId $taskId -RuntimeRoot $runs -ProcessInspector $processInspector -AttemptDurationMinutes 10|Out-Null}catch{$rejected=$_.Exception.Message -match 'Model-path failure report contains document, mutation, rollback, or screenshot evidence'}
    if(!$rejected -or [long](Find-RepatoTask (Read-RepatoTaskStore $store) $taskId).revision -ne [long]$beforeRecovery.revision -or @(Get-ChildItem -LiteralPath $runs -Directory).Count -ne $runtimeCountBefore){throw 'Pre-open model-path failure with document evidence was not rejected without side effects.'}
    $report.DocumentPath='';$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $reportPath -Encoding UTF8

    $originalRequest=Get-Content -LiteralPath $requestPath -Raw;$tamperedRequest=$request|ConvertTo-Json -Depth 6|ConvertFrom-Json;$tamperedRequest.modelPath=Join-Path $oldRuntime 'different.rvt';$tamperedRequest|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $requestPath -Encoding UTF8
    $rejected=$false;try{Recover-MayaQaCorrelatedNativeFailure -StoreRoot $store -TaskId $taskId -RuntimeRoot $runs -ProcessInspector $processInspector -AttemptDurationMinutes 10|Out-Null}catch{$rejected=$_.Exception.Message -match 'Native request model path/hash does not match the canonical disposable model binding'}
    if(!$rejected -or [long](Find-RepatoTask (Read-RepatoTaskStore $store) $taskId).revision -ne [long]$beforeRecovery.revision -or @(Get-ChildItem -LiteralPath $runs -Directory).Count -ne $runtimeCountBefore){throw 'Request model path mismatch was not rejected without side effects.'}
    $originalRequest|Set-Content -LiteralPath $requestPath -Encoding UTF8

    $recovered=Recover-MayaQaCorrelatedNativeFailure -StoreRoot $store -TaskId $taskId -RuntimeRoot $runs -ProcessInspector $processInspector -AttemptDurationMinutes 10
    $task=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId;$new=$task.mayaTaraExecution;$archived=@($task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $oldAttempt -and $_.RunId -ceq $oldRun})
    if($archived.Count -ne 1 -or $archived[0].ResultPath -cne $resultPath -or $archived[0].ReportPath -cne $reportPath -or $archived[0].ResultSha256 -ine $resultHash -or $archived[0].ReportSha256 -ine $reportHash){throw 'Original correlated receipt/report were not preserved in the failed-attempt archive.'}
    $consumedApproval=@($task.approvalRequests|Where-Object {$_.attemptId -ceq $oldAttempt -and $_.runId -ceq $oldRun})
    if($consumedApproval.Count -ne 1 -or $consumedApproval[0].status -cne 'approved' -or [DateTimeOffset]::Parse([string]$consumedApproval[0].consumedUtc) -ne $launchUtc){throw 'Exact approved attempt was not preserved and consumed at its recorded launch time.'}
    if((Get-FileHash $resultPath -Algorithm SHA256).Hash -ine $resultHash -or (Get-FileHash $reportPath -Algorithm SHA256).Hash -ine $reportHash){throw 'Recovery modified original receipt or report bytes.'}
    if($task.status -cne 'in-progress' -or $task.workflowStage -cne 'approval' -or $new.Stage -cne 'prepared' -or $new.ExecutionStatus -cne 'Prepared' -or $new.DisposableModelSha256 -ine $preparedHash -or !$new.FixturePreparationEvidence -or $new.FixturePreparationEvidence.ResultSha256 -ine $prepEvidence.ResultSha256){throw 'Recovery did not produce the in-progress approval-stage state with its prepared-model binding and authenticated evidence.'}
    $null=& $module {param($qa,$taskId,$workflowId,$source,$sourceHash,$runtime,$model,$modelHash) Test-MayaQaCorrelatedDisposableFixtureProvenance -QaRoot $qa -TaskId $taskId -WorkflowId $workflowId -FixtureId 'CreatePlanViewsEmpty' -SourcePath $source -SourceSha256 $sourceHash -RuntimeRoot $runtime -ModelPath $model -ModelSha256 $modelHash} $qa $taskId $workflowId $source $sourceHash $new.DisposableRuntimeRoot $new.DisposableModelPath $new.DisposableModelSha256
    if((Get-FileHash $new.DisposableModelPath -Algorithm SHA256).Hash -ine $preparedHash){throw 'Replacement model is not byte-identical to the authenticated prepared model.'}
    $side=Get-Content -LiteralPath ($new.DisposableModelPath+'.fixture.json') -Raw|ConvertFrom-Json
    if($side.fixtureId -cne 'CreatePlanViewsEmpty' -or $side.sourceSha256 -ine $sourceHash -or $side.preparedModelSha256 -ine $preparedHash -or $side.fixturePreparationRequestSha256 -ine $prepEvidence.RequestSha256 -or $side.fixturePreparationResultSha256 -ine $prepEvidence.ResultSha256){throw 'Replacement sidecar does not satisfy the authenticated runner provenance contract.'}
    if($new.NativeProcessId -or $new.RequestPath -or $new.ClaimId -or $new.SideEffectsPerformed -or $inspectorState.Calls -ne 1){throw 'Recovery unexpectedly dispatched a native QA request or retained execution claim state.'}
    [pscustomobject]@{Success=$true;FailedReceiptPreserved=$true;FailedReportPreserved=$true;PreparedModelReused=$true;PreparationEvidenceReused=$true;DisposableFixtureProvenanceValid=$true;InvalidPreOpenReportRejected=$true;MismatchedRequestModelRejected=$true;NativeLaunchPerformed=$false;ProcessInspectorCalls=$inspectorState.Calls}|ConvertTo-Json -Compress
} finally {if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
