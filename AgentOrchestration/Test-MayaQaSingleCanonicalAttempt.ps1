$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$script:events=@();$script:native=0;$task='task-synthetic-single';$workflow='workflow-synthetic-single';$attempt='attempt-synthetic-single';$claim='claim-synthetic-single'
$request={param($s,$u,$b,$p)$script:events+=@('request');[pscustomobject]@{Stage='approval-required';TaskId=$task;WorkflowId=$workflow;RunId='run-synthetic-single';QaWorkflowId='create-plan-views-v1';QaApprovalId='approval-synthetic';QaApprovalStatus='pending'}}
$approval={param($s,$t,$d,$a,$r)$script:events+=@('approval');[pscustomobject]@{status='approved'}}
$prep={param($s,$t,$w,$q)$script:events+=@('preparation');[pscustomobject]@{TaskId=$task;WorkflowId=$workflow;QaWorkflowId=$q;Attempt=[pscustomobject]@{AttemptId=$attempt};Handoff=[pscustomobject]@{HandoffId='handoff-synthetic';AttemptId=$attempt;NativeTestId=$q;ArtifactPath='artifact';ArtifactSha256=('a'*64);ManifestPath='manifest';ManifestSha256=('b'*64);RunnerManifestPath='manifest';RunnerManifestSha256=('b'*64);ValidatedRunnerManifestPath='manifest';ModelPath='model';ModelSha256=('c'*64);Isolation=[pscustomobject]@{Allowed=$true}}}}
$tx={param($p,$s)$script:events+=@('transaction');$script:native++;[pscustomobject]@{Claim=[pscustomobject]@{ClaimId=$claim};Result=[pscustomobject]@{Started=$true}}}
$r=Invoke-MayaQaSingleCanonicalAttempt -StoreRoot synthetic -UserRequest 'Create Plan Views' -ApprovalDecision approve -RequestInvoker $request -ApprovalInvoker $approval -PreparationInvoker $prep -TransactionInvoker $tx
if(!$r.Success -or $r.TaskId -cne $task -or $r.AttemptId -cne $attempt -or $r.ClaimId -cne $claim -or $script:native -ne 1){throw 'single-attempt identity/count failed'}
$failed=$false;try{Invoke-MayaQaSingleCanonicalAttempt -StoreRoot synthetic -UserRequest 'Create Plan Views' -ApprovalDecision approve -RequestInvoker $request -ApprovalInvoker $approval -PreparationInvoker $prep -TransactionInvoker {throw 'native failure'}|Out-Null}catch{$failed=$true}
if(!$failed -or $script:native -ne 1){throw 'native failure retry guard failed'}
Write-Output 'Maya single canonical attempt synthetic checks passed: 5'
