param([ValidateRange(7200,86400)][int]$ResultTimeoutSeconds=7200)
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -PassThru -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
$store=Join-Path (Split-Path $PSScriptRoot -Parent) 'QA/MayaRuns'
$id='task-bf61fe7f22d74df7a92599681da5919e';$attempt='d609705ad1bb46f9b5eddc4a81fd1872';$approval='c01a2efa2d704d64ac0a03bca155ffc2'
$t=Find-RepatoTask (Read-RepatoTaskStore $store) $id;$x=$t.mayaTaraExecution;$a=$t.mayaTaraAttempt
$q=@($t.approvalRequests|Where-Object {$_.requestId -ceq $approval -and $_.status -ceq 'approved'})
if($t.revision -ne 34 -or $q.Count -ne 1 -or $q[0].decidedBy -cne 'user' -or $q[0].approvedRevision -ne 34 -or $a.AttemptId -cne $attempt -or $x.AttemptId -cne $attempt -or $x.RunId -cne $a.RunId -or $x.Stage -cne 'prepared' -or $x.ClaimId -or $x.NativeProcessId -or $x.RequestPath -or $x.SideEffectsPerformed){throw 'Exact approved and unlaunched canonical attempt required.'}
$q=$q[0];$b=$q.recoveryBinding
if([DateTimeOffset]::Parse($q.expiresUtc) -le [DateTimeOffset]::UtcNow -or [DateTimeOffset]::Parse($a.RequestExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Approval or attempt expired; launch prohibited.'}
$sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $b -Depth 20 -Compress))))).Replace('-','')}finally{$sha.Dispose()}
$w=Get-DeployWorkflow $store $id $x.WorkflowId;$e=$w.qaBuildEvidence
if($q.bindingHash -cne $hash -or $b.TaskId -cne $id -or $b.WorkflowId -cne $x.WorkflowId -or $b.AttemptId -cne $attempt -or $b.RunId -cne $a.RunId -or $b.CandidateSha256 -ine $e.ArtifactSha256 -or $b.CandidateSourceCommit -cne $e.CandidateSourceCommit -or $b.SourceRunnerManifestPath -cne $e.RunnerManifestPath -or $b.SourceRunnerManifestSha256 -ine $e.RunnerManifestSha256 -or $b.DeployedRunnerManifestPath -cne $x.ValidatedRunnerManifestPath -or $b.DeployedRunnerManifestSha256 -ine $x.ValidatedRunnerManifestSha256){throw 'Approved recovery binding mismatch.'}
$null=Test-MayaQaFrozenCandidate -CandidateDirectory $e.CandidateDirectory -CandidateDllPath $e.ArtifactPath -ExpectedSha256 $e.ArtifactSha256 -ExpectedSourceCommit $e.CandidateSourceCommit -QaWorkflowId $x.QaWorkflowId
$null=& $module {param($x)Test-MayaQaFixturePreparationRecord -QaRoot (Get-MayaQaRoot) -TaskId $x.TaskId -WorkflowId $x.WorkflowId -SourcePath $x.AuthoritativeFixturePath -SourceSha256 $x.AuthoritativeFixtureSha256 -Evidence $x.FixturePreparationEvidence} $x
foreach($pair in @(@($x.DisposableModelPath,$x.DisposableModelSha256),@($x.IsolationPolicyPath,$x.IsolationPolicySha256),@($x.RunnerManifestPath,$x.RunnerManifestSha256),@($x.ValidatedRunnerManifestPath,$x.ValidatedRunnerManifestSha256),@((Join-Path $e.QaAddinRoot 'Repato.Revit.dll'),$e.ArtifactSha256))){if((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw 'Approved execution file hash mismatch.'}}
if($x.DisposableModelSha256 -ine $x.FixturePreparationEvidence.PreparedModelSha256 -or !(Test-Path ($x.DisposableModelPath+'.fixture.json'))){throw 'Prepared model evidence mismatch.'}
$health=Invoke-MayaQaLaunchAgentHealth;$preflight=Invoke-MayaQaLaunchAgentPreflightReadonly
if(!$health.Ready -or !$health.UserInteractive -or !$preflight.Succeeded -or @($preflight.Checks|Where-Object passed -ne $true).Count -or $preflight.RunnerManifestPath -cne $x.ValidatedRunnerManifestPath -or $preflight.ExpectedRunnerManifestSha256 -ine $x.ValidatedRunnerManifestSha256){throw 'Live launch-agent safety preflight failed.'}
$evidence=Join-Path $x.DisposableRuntimeRoot 'maya-approved-execution-preflight.json'
[pscustomobject]@{VerifiedUtc=[DateTimeOffset]::UtcNow.ToString('O');Approval=$q;Health=$health;Preflight=$preflight;ResultTimeoutSeconds=$ResultTimeoutSeconds}|ConvertTo-Json -Depth 20|Set-Content $evidence -Encoding UTF8
$claim=Claim-MayaQaExecutionRecord -StoreRoot $store -TaskId $id -ClaimOwner Tara -Preflight $x
Write-Output ('Tara claim established: '+$claim.ClaimId)
# Exactly one dispatch. An exception exits; this script cannot resume or retry a claimed attempt.
$launch=Invoke-MayaQaCanonicalNativeCore -StoreRoot $store -TaskId $id -ClaimId $claim.ClaimId -Executable 'E:\revit\Revit 2025\Revit.exe'
$launch|ConvertTo-Json -Depth 8
Write-Output 'Single canonical native dispatch accepted. Waiting for correlated result.'
Resume-MayaQaCanonicalExecution -StoreRoot $store -TaskId $id -ClaimId $claim.ClaimId -TimeoutSeconds $ResultTimeoutSeconds|ConvertTo-Json -Depth 10
