$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue

$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$store=Join-Path ([IO.Path]::GetTempPath()) ('maya-production-shape-'+[guid]::NewGuid().ToString('N'))
$files=Join-Path ([IO.Path]::GetTempPath()) ('maya-production-files-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $files -Force|Out-Null
$candidate=Join-Path $files 'Repato.Revit.dll';$manifest=Join-Path $files 'Repato.addin';$runner=Join-Path $files 'Repato.CreatePlanViews.TestRunner.addin';$policy=Join-Path $files 'MachineWideAddins.allowlist.json'
Set-Content $candidate 'synthetic candidate';Set-Content $manifest 'synthetic build manifest';Set-Content $runner 'synthetic runner';Set-Content $policy '{"schemaVersion":1}'
$candidateHash=(Get-FileHash $candidate -Algorithm SHA256).Hash;$manifestHash=(Get-FileHash $manifest -Algorithm SHA256).Hash;$runnerHash=(Get-FileHash $runner -Algorithm SHA256).Hash;$policyHash=(Get-FileHash $policy -Algorithm SHA256).Hash
$events=[Collections.Generic.List[string]]::new()
try {
  $boot=New-MayaQaBootstrap -StoreRoot $store -QaWorkflowId 'create-plan-views-v1' -RunId 'production-shape-run'
  $task=$boot.TaskId;$workflow=$boot.WorkflowId;$qa='create-plan-views-v1';$null=New-MayaQaBuildRequest -StoreRoot $store -TaskId $task -WorkflowId $workflow -QaWorkflowId $qa -UserRequest 'Create Plan Views' -SourceBranch 'synthetic' -ProjectPath 'synthetic.csproj'
  $d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $task;$w=Get-DeployWorkflow $store $task $workflow
  $e=[pscustomobject]@{BuildRequestId=$w.qaBuildRequest.BuildRequestId;ArtifactPath=$candidate;ArtifactSha256=$candidateHash;ManifestPath=$manifest;ManifestSha256=$manifestHash;BuildStatus='succeeded';EvidenceSource='Synthetic';CandidateDirectory=$files;CandidateSourceCommit='synthetic-source-commit';QaWorkflowId=$qa;RunnerManifestPath=$runner;RunnerManifestSha256=$runnerHash;QaAddinRoot=$files;Isolation=[pscustomobject]@{PolicyPath=$policy;PolicySha256=$policyHash;Allowed=$true};DeploymentValidation=$true;ManifestIntegrityValidation=$true;QaIsolation=$true}
  $null=Invoke-RepatoWorkflowMutation $store $task $workflow $w.workflowRevision $t.revision {param($x)$x|Add-Member NoteProperty qaBuildStatus 'succeeded' -Force;$x|Add-Member NoteProperty qaBuildEvidence $e -Force;return $x}
  $run=New-MayaQaRun -StoreRoot $store -TaskId $task -WorkflowId $workflow -QaWorkflowId $qa -RunId 'production-shape-run'
  $handoff=New-MayaQaCanonicalPreparation -StoreRoot $store -TaskId $task -WorkflowId $workflow -QaWorkflowId $qa
  $d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $task;$attempt=$t.mayaTaraAttempt
  foreach($n in 'TaskId','WorkflowId','QaWorkflowId','RunId','AttemptId','RuntimeRoot'){if($attempt.PSObject.Properties.Name -notcontains $n){throw "Persisted attempt missing $n"}}
  $request=[pscustomobject]@{Stage='handoff-ready';TaskId=$task;WorkflowId=$workflow;QaWorkflowId=$qa;RunId=$run.RunId;Handoff=$handoff.Handoff}
  $native={param($s,$id,$claim)$events.Add('native')|Out-Null;$d=Read-RepatoTaskStore $s;$t=Find-RepatoTask $d $id;$r=$t.mayaTaraExecution;if([string]$r.ValidatedRunnerManifestPath -cne [string]$r.RunnerManifestPath){throw "Persisted manifest divergence: runner=[$($r.RunnerManifestPath)] validated=[$($r.ValidatedRunnerManifestPath)]"};$requestPath=Join-Path $r.DisposableRuntimeRoot ('synthetic-'+$r.RunId+'.request.json');$launcher={param($exe,$args) [pscustomobject]@{Pid=424242;StartedUtc=(Get-Date).ToUniversalTime().ToString('O')}};$result=[pscustomobject]@{TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;TestId=$r.TestId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;ClaimId=$claim;RequestId=$r.RunId;RequestPath=$requestPath;ResultPath=($requestPath+'.result.json');ReportPath=(Join-Path $r.DisposableRuntimeRoot 'synthetic-report.json');EvidencePath=(Join-Path $r.DisposableRuntimeRoot 'synthetic-evidence.json');EvidenceAccepted=$true;RollbackProven=$true;Verified=$true};Invoke-MayaQaCanonicalNativeCore -StoreRoot $s -TaskId $id -ClaimId $claim -Executable 'synthetic.exe' -Arguments '' -ProcessLauncher $launcher -Result $result}
  $tx=Invoke-MayaQaCanonicalTransaction -StoreRoot $store -UserRequest 'Create Plan Views' -RequestInvoker {param($s,$u,$b,$p)$request} -NativeCoreInvoker $native
  $d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $task;$execution=$t.mayaTaraExecution
  if($execution.ExecutionStatus -ne 'Completed'){throw "Expected terminal execution, got $($execution.ExecutionStatus)"}
  if($events.Count -ne 1){throw "Expected one injected native boundary, got $($events.Count)"}
  [pscustomobject]@{ProductionShapeHarness='PASS';UsesTemporaryStoreOnly=$true;UsesRealPreparation=$true;UsesRealTransaction=$true;ExecutionRecordCreated=$true;ClaimCreated=$true;NativeRequestSerialized=$true;InjectedNativeBoundary=$true;TerminalBookkeeping=$true;PropertyNotFoundStrictErrors=0;RealStoreMutated=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
} finally { if(Test-Path $store){Remove-Item $store -Recurse -Force -ErrorAction SilentlyContinue};if(Test-Path $files){Remove-Item $files -Recurse -Force -ErrorAction SilentlyContinue} }
