$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$events=[System.Collections.Generic.List[string]]::new();$task='synthetic-task';$workflow='synthetic-workflow';$qa='create-plan-views-v1';$claim='synthetic-claim'
$request={param($s,$u,$b,$p)$events.Add('request');[pscustomobject]@{Stage='handoff-ready';TaskId=$task;WorkflowId=$workflow;QaWorkflowId=$qa;RunId='synthetic-run';Handoff=[pscustomobject]@{HandoffId='synthetic-handoff';AttemptId='synthetic-attempt';NativeTestId='create-plan-views-elevations-v1';ArtifactPath='artifact';ArtifactSha256=('a'*64);ManifestPath='manifest';ManifestSha256=('b'*64);ModelPath='model';ModelSha256=('c'*64);Isolation=[pscustomobject]@{PolicyPath='policy';PolicySha256=('d'*64);Allowed=$true}}}}
$record={param($s,$id,$preflight)$events.Add('execution');if($id -cne $task -or $preflight.WorkflowId -cne $workflow -or $preflight.QaWorkflowId -cne $qa){throw 'Identity was not propagated to execution preparation.'};[pscustomobject]@{TaskId=$id;WorkflowId=$workflow;QaWorkflowId=$qa;AttemptId='synthetic-attempt';RunId='synthetic-run';ClaimId=$null}}
$claimFn={param($s,$id,$owner,$execution)$events.Add('claim');if($owner -cne 'Tara' -or $execution.AttemptId -cne 'synthetic-attempt'){throw 'Claim contract failed.'};$execution|Add-Member NoteProperty ClaimId $claim -Force;$execution}
$native={param($s,$id,$idClaim)$events.Add('native-core');if($id -cne $task -or $idClaim -cne $claim){throw 'Native core identity failed.'};[pscustomobject]@{Success=$true;Stage='completed'}}
$out=Invoke-MayaQaCanonicalTransaction -StoreRoot ([IO.Path]::GetTempPath()) -UserRequest 'synthetic' -RequestInvoker $request -ExecutionRecordInvoker $record -ClaimInvoker $claimFn -NativeCoreInvoker $native
if(($events -join '|') -cne 'request|execution|claim|native-core'){throw "Unexpected stage order: $($events -join '|')"}
if($out.TaskId -cne $task -or $out.WorkflowId -cne $workflow -or $out.QaWorkflowId -cne $qa -or !$out.Result.Success){throw 'Bridge result identity or success contract failed.'}
'Canonical bridge contract passed: 6'
