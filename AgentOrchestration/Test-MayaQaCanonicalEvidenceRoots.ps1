$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
$taskId='synthetic-roots';$workflowId='synthetic-workflow';$qa='create-plan-views-v1';$test=$qa
$candidateRoot='C:\Repato-Autonomous\Worktrees\create-plan-views-buildfix-4f2cbba22ba9\DeploymentCandidates\AgentBuilds'
$candidate=Join-Path $candidateRoot 'ReleaseCandidate-4f2cbba22ba9';$dll=Join-Path $candidate 'Repato.Revit.dll';$provenance=Join-Path $candidate 'release-manifest.json'
$trustedRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\QA'));$trusted=Join-Path $trustedRoot 'Repato.CreatePlanViews.TestRunner.addin'
$external='C:\Repato-Autonomous\Worktrees\create-plan-views-buildfix-4f2cbba22ba9\QA\Repato.CreatePlanViews.TestRunner.addin'
$hash=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash;$manifestHash=(Get-FileHash -LiteralPath $trusted -Algorithm SHA256).Hash
if($hash -ine '8C3F6EF16790247B9949EADED8FF098B4D95598791011C418D003DAAC0680AB5'){throw 'Approved frozen candidate hash changed.'}
if((Get-FileHash -LiteralPath $external -Algorithm SHA256).Hash -ine $manifestHash){throw 'Candidate worktree manifest does not match trusted Source\QA.'}
$store=Join-Path ([IO.Path]::GetTempPath()) ('maya-roots-'+[guid]::NewGuid().ToString('N'))
try {
    $bootstrap=New-MayaQaBootstrap -StoreRoot $store -QaWorkflowId $qa -RunId 'synthetic-root-test' -TaskId $taskId
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $bootstrap.WorkflowId)[0];$w|Add-Member NoteProperty qaBuildStatus 'succeeded' -Force;$w|Add-Member NoteProperty qaBuildRequest ([pscustomobject]@{BuildRequestId='build-existing'}) -Force;$w|Add-Member NoteProperty qaBuildEvidence ([pscustomobject]@{BuildRequestId='build-existing';BuildStatus='succeeded';EvidenceSource='FrozenCandidate';SourceCommit='4f2cbba22ba9f4d6d3176e2d36daf2890bd1849c';CandidateSourceCommit='4f2cbba22ba9f4d6d3176e2d36daf2890bd1849c';CandidateDirectory=$candidate;CandidateProvenancePath=$provenance;ArtifactPath=$dll;ArtifactSha256=$hash;RunnerManifestPath=$external;RunnerManifestSha256=$manifestHash});$d}|Out-Null
    $workflowModule=Get-Module Repato.MayaQaWorkflow;$normalized=& $workflowModule {param($s,$t,$w,$q,$test)Resolve-MayaQaSourceRunnerManifestEvidence -StoreRoot $s -TaskId $t -WorkflowId $w -QaWorkflowId $q -TestId $test} $store $taskId $bootstrap.WorkflowId $qa $test
    if([IO.Path]::GetFullPath($normalized.RunnerManifestPath) -ine [IO.Path]::GetFullPath($trusted) -or [IO.Path]::GetFullPath($normalized.OriginalRunnerManifestPath) -ine [IO.Path]::GetFullPath($external)){throw 'External runner evidence was not safely normalized and retained.'}
    $e=New-MayaQaPersistedCandidateEvidence -StoreRoot $store -TaskId $taskId -WorkflowId $bootstrap.WorkflowId -QaWorkflowId $qa -TestId $test
    if([IO.Path]::GetFullPath($e.RunnerManifestPath) -ine [IO.Path]::GetFullPath($trusted)){throw 'Candidate evidence did not normalize to the trusted manifest path.'}
    if($e.CandidateSourceCommit -cne '4f2cbba22ba9f4d6d3176e2d36daf2890bd1849c' -or $e.CandidateDllSha256 -ine $hash){throw 'Canonical candidate identity changed.'}
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$w=$t.deploymentWorkflows[0];$w.qaBuildEvidence.RunnerManifestPath='C:\untrusted\runner.addin';$d}|Out-Null
    $rejected=$false;try{New-MayaQaPersistedCandidateEvidence -StoreRoot $store -TaskId $taskId -WorkflowId $bootstrap.WorkflowId -QaWorkflowId $qa -TestId $test|Out-Null}catch{$rejected=$true}
    if(!$rejected){throw 'Unauthorized runner-manifest path was accepted.'}
    $adapter='C:\Repato-Autonomous\Worktrees\create-plan-views-buildfix-4f2cbba22ba9\AgentOrchestration\Invoke-RepatoQaFrozenCandidateStaging.ps1'
    $adapterText=Get-Content -LiteralPath $adapter -Raw
    if($adapterText -notmatch [regex]::Escape("`$runnerRoot=[IO.Path]::GetFullPath(('C:\Repato-Autonomous\Source\QA'))") -or $adapterText -match "Join-Path `$PSScriptRoot '..\\QA'" -or $adapterText -notmatch '-QaSourceRoot \$runnerRoot'){throw 'Supported staging adapter is not bound to the trusted Source\QA root.'}
    $validationText=Get-Content -LiteralPath 'C:\Repato-Autonomous\Worktrees\create-plan-views-buildfix-4f2cbba22ba9\AgentOrchestration\Invoke-RepatoQaDeploymentValidation.ps1' -Raw
    if($validationText -notmatch [regex]::Escape("`$runnerRoot=[IO.Path]::GetFullPath(('C:\Repato-Autonomous\Source\QA'))") -or $validationText -notmatch '-QaSourceRoot \$runnerRoot'){throw 'Supported deployment validator is not bound to the trusted Source\QA root.'}
    $protocol=Get-Content -LiteralPath 'C:\Repato-Autonomous\Source\.worktrees\qa-launchagent-pin-4f2cbba22ba9\QaLaunchAgent\Protocol.cs' -Raw
    foreach($expected in @('ApprovedCandidateRoot = @"C:\Repato-Autonomous\Worktrees\create-plan-views-buildfix-4f2cbba22ba9\DeploymentCandidates\AgentBuilds"','ApprovedRunnerManifestRoot = @"C:\Repato-Autonomous\Source\QA"','StagingAdapterPath = @"C:\Repato-Autonomous\Worktrees\create-plan-views-buildfix-4f2cbba22ba9\AgentOrchestration\Invoke-RepatoQaFrozenCandidateStaging.ps1"')){if($protocol -notmatch [regex]::Escape($expected)){throw "Launch Agent protocol root contract mismatch: $expected"}}
    [pscustomobject]@{Status='PASS';Assertions=10;TaskStoreSynthetic=$true;TrustedRunnerManifest=$trusted;RunnerManifestSha256=$manifestHash;CandidateCommit='4f2cbba22ba9f4d6d3176e2d36daf2890bd1849c';CandidateDllSha256=$hash;ProtocolAndAdaptersAgree=$true;UnauthorizedRunnerPathRejected=$rejected;LiveStagingInvoked=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
} finally {if(Test-Path -LiteralPath $store){Remove-Item -LiteralPath $store -Recurse -Force -ErrorAction SilentlyContinue}}
