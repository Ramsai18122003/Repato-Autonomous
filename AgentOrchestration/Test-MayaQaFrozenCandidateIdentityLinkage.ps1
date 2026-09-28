$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('maya-frozen-link-'+[guid]::NewGuid().ToString('N'));$store=Join-Path $scratch 'store';New-Item $scratch -ItemType Directory|Out-Null
$candidate='C:\Repato-Autonomous\Source\DeploymentCandidates\AgentBuilds\ReleaseCandidate-b888366d6ce5';$hash='0FC3E6AC17DB66B0D786F3731AC2A0DCD978DCE61B0F22F998FA422EF14F9565';$commit='b888366d6ce541d16f0daba30a5d18802eed7ccb'
$fixture='C:\Repato-Autonomous\Source\QA\Fixtures\CreatePlanViewsEmpty.rvt';$policy='C:\Repato-Autonomous\Source\QA\MachineWideAddins.allowlist.json';$passed=0
function Check([bool]$ok,[string]$name){if(!$ok){throw "FAILED: $name"};$script:passed++}
function Reject([scriptblock]$action,[string]$name){$ok=$false;try{&$action|Out-Null}catch{$ok=$true};Check $ok $name}
try{
 $r=Invoke-MayaQaRequest -StoreRoot $store -UserRequest 'create-plan-views-v1' -ArtifactMode FrozenCandidate -CandidateDirectory $candidate -ExpectedCandidateSha256 $hash -ExpectedCandidateSourceCommit $commit
 Check ($r.TaskId -and $r.Stage -ceq 'approval-required') 'TaskId created'
 Check (![string]::IsNullOrWhiteSpace([string]$r.WorkflowId)) 'WorkflowId created'
 $null=Resolve-RepatoTaskApproval $store $r.TaskId approve Maya 'synthetic canonical linkage approval'
 $c=New-MayaQaCanonicalPreparation $store $r.TaskId $r.WorkflowId $r.QaWorkflowId
 $d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $r.TaskId
 Check ($null-ne$t.mayaPlan) 'mayaPlan persisted'
 Check ($null-ne$t.mayaTaraQaPacket) 'handoff persisted'
 Check ($null-ne$t.mayaTaraAttempt) 'mayaTaraAttempt persisted'
 $resolved=Resolve-MayaQaTaskStoreIdentity $store $r.TaskId $r.WorkflowId 'create-plan-views-v1'
 Check ($resolved.WorkflowMatchCount -eq 1) 'exact workflow match'
 Check ($resolved.HandoffMatchCount -eq 1) 'exact handoff match'
 Check ($resolved.AttemptMatchCount -eq 1) 'exact attempt match'
 Check ($resolved.RunMatchCount -eq 1) 'exact run match'
 $pre=[pscustomobject]@{TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId='create-plan-views-v1';TestId='create-plan-views-v1';HandoffId=$resolved.SelectedHandoffId;AttemptId=$resolved.SelectedAttemptId;RunId=$resolved.SelectedRunId;ArtifactPath=$t.mayaTaraQaPacket.ArtifactPath;ArtifactSha256=$t.mayaTaraQaPacket.ArtifactSha256;RunnerManifest=$t.mayaTaraQaPacket.ManifestPath;RunnerManifestSha256=$t.mayaTaraQaPacket.ManifestSha256;FixturePath=$fixture;FixtureSha256=(Get-FileHash $fixture).Hash;DisposableFixturePath=$t.mayaTaraQaPacket.ModelPath;DisposableFixtureSha256=(Get-FileHash $t.mayaTaraQaPacket.ModelPath).Hash;Isolation=[pscustomobject]@{PolicyPath=$policy;PolicySha256=(Get-FileHash $policy).Hash;Allowed=$true}}
 $e=New-MayaQaExecutionRecord $store $r.TaskId $pre;Check ($e.Stage -ceq 'prepared') 'execution record accepted'
 $claim=Claim-MayaQaExecutionRecord $store $r.TaskId Tara $e;Check ($claim.ClaimStatus -ceq 'claimed') 'claim accepted'
 Check (![string]::IsNullOrWhiteSpace($claim.ClaimId)) 'ClaimId resolved'
 Check ($claim.AttemptId -ceq $resolved.SelectedAttemptId) 'AttemptId resolved'
 Check ($claim.RunId -ceq $resolved.SelectedRunId) 'RunId resolved'
 Check ($t.mayaTaraQaPacket.ArtifactSha256 -ceq $hash) 'frozen candidate hash linked'
 Reject {Resolve-MayaQaTaskStoreIdentity $store $r.TaskId 'wrong-workflow' 'create-plan-views-v1'|ForEach-Object{if(@($_.Errors).Count){throw 'rejected'}}} 'mismatched WorkflowId rejected'
 $badAttempt=$pre.PSObject.Copy();$badAttempt.AttemptId='stale-attempt';Reject {New-MayaQaExecutionRecord $store $r.TaskId $badAttempt} 'stale AttemptId rejected'
 $badRun=$pre.PSObject.Copy();$badRun.RunId='stale-run';Reject {New-MayaQaExecutionRecord $store $r.TaskId $badRun} 'stale RunId rejected'
 Reject {New-MayaQaCanonicalPreparation $store $r.TaskId $r.WorkflowId 'create-plan-views-v1'} 'duplicate canonical links rejected'
 [pscustomobject]@{Status='PASS';AssertionsPassed=$passed;AssertionsFailed=0;TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;HandoffId=$resolved.SelectedHandoffId;AttemptId=$resolved.SelectedAttemptId;RunId=$resolved.SelectedRunId;ClaimId=$claim.ClaimId;ExactWorkflowMatches=$resolved.WorkflowMatchCount;ExactHandoffMatches=$resolved.HandoffMatchCount;ExactAttemptMatches=$resolved.AttemptMatchCount;ExactRunMatches=$resolved.RunMatchCount;ManualCanonicalStateFabrication=$false;RealStoreTouched=$false}|ConvertTo-Json -Compress
}finally{
 if($t -and $t.mayaTaraQaPacket.ModelPath){$owned=[IO.Path]::GetFullPath((Split-Path $t.mayaTaraQaPacket.ModelPath -Parent));$root=[IO.Path]::GetFullPath('C:\Repato-Autonomous\Source\QA\TestRuns').TrimEnd('\')+'\';if($owned.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){Remove-Item $owned -Recurse -Force -ErrorAction SilentlyContinue}}
 Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
