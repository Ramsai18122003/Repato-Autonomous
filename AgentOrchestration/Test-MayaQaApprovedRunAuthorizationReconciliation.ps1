$ErrorActionPreference='Stop'
$here=$PSScriptRoot
Import-Module (Join-Path $here 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $here 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$root=Join-Path ([IO.Path]::GetTempPath()) ('maya-approved-run-authorization-'+[guid]::NewGuid().ToString('N'))
$taskId='task-approved-run-authorization';$workflowId='workflow-approved-run-authorization'
$run='abcdef01234567890abcdef012345678'
$binding=[pscustomobject][ordered]@{SchemaVersion='maya-qa-canonical-execution-approval-v1';TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId='create-plan-views-v1';RunId=$run;ModelSha256='9'*64;RequiredExecutor='Tara';RevitVersion='2025'}
$bindingJson=ConvertTo-Json -InputObject $binding -Depth 20 -Compress
$sha=[Security.Cryptography.SHA256]::Create();try{$bindingHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($bindingJson)))).Replace('-','')}finally{$sha.Dispose()}
function New-Approval {
    [pscustomobject][ordered]@{requestId='aaaabbbbccccddddeeeeffff00001111';action='qa-run';requiredLevel='user';status='approved';bindingHash=$bindingHash;executionBinding=$binding;previousStatus='in-progress';requestedRevision=8;approvedRevision=9;requestedUtc='2026-10-20T12:20:00.0000000+00:00';expiresUtc='2026-10-20T13:00:00.0000000+00:00';decidedUtc='2026-10-20T12:25:00.0000000+00:00';decidedBy='user';reason='synthetic canonical approved QA';consumedUtc=$null}
}
function New-Evidence {
    [pscustomobject][ordered]@{Status='Passed';RollbackStatus='RolledBack';CoordinatorRunId='MAYA-ee4a8b96942f4e85b47e9db12a21b40d';NativeRunId=$run}
}
function New-Fixture([string]$store) {
    New-RepatoTask $store $taskId 'Approved run authorization' 'contract fixture' 'qa/approved-run-authorization'|Out-Null
    Invoke-RepatoStoreMutation $store {param($d,$preview)
        $t=Find-RepatoTask $d $taskId;$t.revision=[long]9;$t.status='in-progress';$t.workflowStage='approval'
        $attempt=[pscustomobject][ordered]@{AttemptId='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';RunId=$run;RequestExpiresUtc='2026-10-20T14:00:00.0000000+00:00'}
        $execution=[pscustomobject][ordered]@{AttemptId='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';RunId=$run;Stage='completed';ExecutionStatus='Completed';CompletionStatus='Completed';VerificationStatus='Verified';RollbackStatus='Verified';SideEffectsPerformed=$true;LaunchedUtc='2026-10-20T12:30:00.0000000+00:00';VerifiedUtc='2026-10-20T12:34:00.0000000+00:00';CompletedUtc='2026-10-20T12:35:00.0000000+00:00'}
        $packet=[pscustomobject][ordered]@{RunId=$run;AttemptId='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'}
        $wrec=[pscustomobject][ordered]@{taskId=$taskId;workflowId=$workflowId;qaWorkflowId='create-plan-views-v1';stage='planned';workflowRevision=3;qaApprovalId=(New-Approval).requestId;qaApprovalStatus='approved';qaRunId=$run;qaVerificationStatus='verified';qaEvidence=(New-Evidence)}
        $t|Add-Member NoteProperty mayaTaraAttempt $attempt -Force
        $t|Add-Member NoteProperty mayaTaraExecution $execution -Force
        $t|Add-Member NoteProperty mayaTaraQaPacket $packet -Force
        $t|Add-Member NoteProperty approvalRequests ([object[]]@((New-Approval))) -Force
        $t|Add-Member NoteProperty deploymentWorkflows ([object[]]@($wrec)) -Force
        $t
    }|Out-Null
}
function Get-CaseStore([string]$name) {
    $store=Join-Path $root ('case-'+$name);New-Item -ItemType Directory -Path $store -Force|Out-Null;New-Fixture $store;return $store
}
try {
    $rejectedCases=@(
        @{Name='missing-evidence';Expect='registered passed QA evidence';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$w=@($t.deploymentWorkflows)[0];$w.PSObject.Properties.Remove('qaEvidence');0;$t}|Out-Null}},
        @{Name='failed-status';Expect='verified passed QA evidence';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;@($t.deploymentWorkflows)[0].qaEvidence.Status='Failed';$t}|Out-Null}},
        @{Name='rollback-not-proven';Expect='verified passed QA evidence';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;@($t.deploymentWorkflows)[0].qaEvidence.RollbackStatus='Required';$t}|Out-Null}},
        @{Name='wrong-run-identity';Expect='registered native run identity';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;@($t.deploymentWorkflows)[0].qaEvidence.NativeRunId='ffffffffffffffffffffffffffffffff';$t}|Out-Null}},
        @{Name='attempt-run-mismatch';Expect='completed native run for mayaTaraAttempt';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.mayaTaraAttempt.RunId='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';$t}|Out-Null}},
        @{Name='packet-run-mismatch';Expect='completed native run for mayaTaraQaPacket';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.mayaTaraQaPacket.RunId='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';$t}|Out-Null}},
        @{Name='uncompleted-execution';Expect='completed verified native execution';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.mayaTaraExecution.CompletionStatus='Verified';$t}|Out-Null}},
        @{Name='missing-launch-timestamp';Expect='native launch timestamp';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.mayaTaraExecution.LaunchedUtc=$null;$t}|Out-Null}},
        @{Name='duplicate-approval';Expect='exactly one approved human QA request';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.approvalRequests=[object[]]@($t.approvalRequests)+@((New-Approval));$t}|Out-Null}},
        @{Name='tampered-binding-hash';Expect='binding hash mismatch';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.approvalRequests[0].bindingHash='0'*64;$t}|Out-Null}},
        @{Name='self-approved';Expect='recorded human decision';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.approvalRequests[0].decidedBy='Maya';$t}|Out-Null}},
        @{Name='launch-after-expiry';Expect='after the human authorization expired';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.mayaTaraExecution.LaunchedUtc='2026-10-20T13:30:00.0000000+00:00';$t}|Out-Null}},
        @{Name='decision-after-launch';Expect='postdates the native launch';Mutate={param($store)Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.approvalRequests[0].decidedUtc='2026-10-20T12:31:00.0000000+00:00';$t}|Out-Null}}
    )
    foreach($case in $rejectedCases){
        $store=Get-CaseStore $case.Name
        & $case.Mutate $store
        $rejected=$false;$message=$null
        try{Complete-MayaQaApprovedRunAuthorization -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -DryRun|Out-Null}catch{$rejected=$true;$message=$_.Exception.Message}
        if(!$rejected){throw "Reconciliation guard '$($case.Name)' did not reject."}
        if($message -notmatch [regex]::Escape($case.Expect)){throw "Reconciliation guard '$($case.Name)' rejected with unexpected message: $message"}
    }
    $store=Get-CaseStore 'main'
    $revisionBefore=[long](Invoke-RepatoStoreMutation $store {param($d,$preview)[long](Find-RepatoTask $d $taskId).revision})
    $dry=Complete-MayaQaApprovedRunAuthorization -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -DryRun
    if($dry.Status -cne 'WouldReconcile' -or $dry.SideEffectsPerformed){throw 'Dry-run reconciliation contract failed.'}
    if([long](Invoke-RepatoStoreMutation $store {param($d,$preview)[long](Find-RepatoTask $d $taskId).revision}) -ne $revisionBefore){throw 'Dry-run reconciliation mutated the task store.'}
    $reconciled=Complete-MayaQaApprovedRunAuthorization -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId
    if($reconciled.Status -cne 'Reconciled' -or !$reconciled.SideEffectsPerformed -or $reconciled.RunId -cne $run -or $reconciled.ApprovalId -cne 'aaaabbbbccccddddeeeeffff00001111'){throw 'Reconciliation result contract failed.'}
    $t=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId
    $ap=@($t.approvalRequests|Where-Object {$_.requestId -ceq 'aaaabbbbccccddddeeeeffff00001111'})[0]
    if([string]$ap.runId -cne $run){throw 'Reconciliation did not bind the run identity.'}
    if($ap.consumedUtc -notmatch '2026-10-20T12:30:00'){throw 'Reconciliation consumedUtc is not the recorded launch timestamp.'}
    if([string]$ap.status -cne 'approved'){throw 'Reconciliation changed the approved status.'}
    if(@($t.history|Where-Object {$_.event -ceq 'maya-qa-approved-run-authorization-consumed' -and $_.actor -ceq 'Maya'}).Count -ne 1){throw 'Reconciliation history event was not recorded exactly once.'}
    $revisionAfter=[long]$t.revision
    $again=Complete-MayaQaApprovedRunAuthorization -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId
    if($again.Status -cne 'AlreadyReconciled' -or $again.SideEffectsPerformed -or $again.ConsumedUtc -cne $ap.consumedUtc){throw 'Repeated reconciliation was not idempotent.'}
    $t2=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId
    $ap2=@($t2.approvalRequests|Where-Object {$_.requestId -ceq 'aaaabbbbccccddddeeeeffff00001111'})[0]
    if([string]$ap2.runId -cne $run -or [string]$ap2.consumedUtc -cne [string]$ap.consumedUtc){throw 'Idempotent reconciliation mutated state.'}
    if([long]$t2.revision -ne $revisionAfter){throw 'Idempotent reconciliation changed the task revision.'}
    [pscustomobject]@{Success=$true;DryRunReadOnly=$true;ReconciledOnce=$true;ConsumedAtLaunch=$true;StatusPreserved=$true;HistoryRecordedOnce=$true;IdempotentReconcile=$true;RejectedGuards=$rejectedCases.Count}|ConvertTo-Json -Compress
} finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
