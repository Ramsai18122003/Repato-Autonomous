$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('repato-continuation-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
try {
 Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
 Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
 $task='task-synthetic';$wf='workflow-synthetic';$commit='A'*40;$hash='B'*64;$build='build-synthetic';$qa='create-plan-views-v1';$test=$qa
 Initialize-RepatoTaskStore $root|Out-Null;New-RepatoTask $root $task 'synthetic' 'synthetic' 'qa/maya-qa-workflow' 'maya'|Out-Null
 Invoke-RepatoStoreMutation $root {param($d,$p)$t=Find-RepatoTask $d $task;$t|Add-Member NoteProperty deploymentWorkflows ([object[]]@([pscustomobject]@{workflowId=$wf;taskId=$task})) -Force;$t}
 $rev=[long](Find-RepatoTask (Read-RepatoTaskStore $root) $task).revision
 $op=New-MayaQaDeploymentValidationOperation $root $task $wf $rev $build $commit $hash $qa $test
 $r=Continue-MayaQaDeploymentValidation $root $task $wf $op.OperationId $rev $build $commit $hash $qa $test -RequestInvoker { [pscustomobject]@{schemaVersion=1;operation='validate-qa-deployment';succeeded=$true;candidateSha256=$hash} }
 if($r.Status -ne 'Completed'){throw 'confirmed-unsent continuation failed'}
 $again=Continue-MayaQaDeploymentValidation $root $task $wf $op.OperationId $rev $build $commit $hash $qa $test
 if($again.Status -ne 'Completed'){throw 'idempotent completed validation failed'}
 $unknown=New-MayaQaDeploymentValidationOperation $root $task $wf $rev $build $commit $hash $qa $test
 Invoke-RepatoStoreMutation $root {param($d,$p)$t=Find-RepatoTask $d $task;$t.deploymentValidationOperations[-1].RequestDisposition='unknown';$t}
 $blocked=$false;try{Continue-MayaQaDeploymentValidation $root $task $wf $unknown.OperationId $rev $build $commit $hash $qa $test}catch{$blocked=$true};if(!$blocked){throw 'unknown state was retryable'}
 $conflict=$false;try{Continue-MayaQaDeploymentValidation $root $task $wf $op.OperationId ($rev+1) $build $commit $hash $qa $test}catch{$conflict=$true};if(!$conflict){throw 'revision conflict was accepted'}
 $conflict=$false;try{Continue-MayaQaDeploymentValidation $root $task $wf $op.OperationId $rev $build ('C'*40) $hash $qa $test}catch{$conflict=$true};if(!$conflict){throw 'candidate identity conflict was accepted'}
 $d=Read-RepatoTaskStore $root;$t=Find-RepatoTask $d $task;if(@($t.deploymentValidationOperations).Count -ne 2){throw 'duplicate lifecycle prevention failed'}
 [pscustomobject]@{ConfirmedUnsent='PASS';UnknownRejected='PASS';IdempotentCompleted='PASS';DuplicateLifecycle='PASS';IdentityRevisionConflicts='PASS';NoNativeExecution='PASS';ApprovalBoundary='PASS';RealStoreTouched=$false}|ConvertTo-Json -Compress
} finally {Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue}
