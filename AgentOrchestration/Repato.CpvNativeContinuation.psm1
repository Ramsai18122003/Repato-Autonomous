Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-CpvContinuationHash {
    param($Value)
    $s=[Security.Cryptography.SHA256]::Create()
    try {([BitConverter]::ToString($s.ComputeHash([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 40 -Compress))))).Replace('-','')} finally {$s.Dispose()}
}
function Assert-CpvContinuationFile {
    param([string]$Path,[string]$Sha256)
    if(!$Path -or ![IO.Path]::IsPathRooted($Path) -or $Sha256 -cnotmatch '^[A-Fa-f0-9]{64}$' -or !(Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $Sha256){throw 'CPV continuation immutable file binding mismatch.'}
}
function New-CpvNativeContinuationBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Task,[Parameter(Mandatory)]$Workflow,[Parameter(Mandatory)][long]$ExpectedTaskRevision)
    if([long]$Task.revision -ne $ExpectedTaskRevision -or $Workflow.taskId -cne $Task.taskId -or $Workflow.qaWorkflowId -cne 'create-plan-views-v1'){throw 'CPV continuation task/workflow revision mismatch.'}
    $r=$Task.cpvPreparationRecovery;$q=$r.Request;$c=$r.OutcomeRecoveryReceipt;$p=$Workflow.qaFixturePreparationEvidence;$e=$Workflow.qaBuildEvidence
    if($r.Status -cne 'RecoveredVerified' -or !$c -or !$p -or !$e){throw 'Verified recovered preparation is required.'}
    $original=$r.PreparationBinding;$historical=$q.candidateEvidence
    if($original.TaskId -cne $Task.taskId -or $original.WorkflowId -cne $Workflow.workflowId -or $original.CandidateSourceCommit -cne $historical.CandidateSourceCommit -or $original.CandidateSha256 -ine $historical.CandidateDllSha256 -or $original.CandidateProvenancePath -ine $historical.CandidateProvenancePath -or $original.RunnerManifestPath -ine $historical.RunnerManifestPath -or $original.RunnerManifestSha256 -ine $historical.RunnerManifestSha256 -or $original.FixtureSha256 -ine $p.SourceSha256){throw 'Historical candidate or fixture approval binding mismatch.'}
    Assert-CpvContinuationFile $historical.CandidateDllPath $historical.CandidateDllSha256
    Assert-CpvContinuationFile $historical.RunnerManifestPath $historical.RunnerManifestSha256
    Assert-CpvContinuationFile $historical.CandidateProvenancePath $original.CandidateProvenanceSha256
    Assert-CpvContinuationFile $original.FixturePath $original.FixtureSha256
    Assert-CpvContinuationFile $original.FixtureProvenancePath $original.FixtureProvenanceSha256
    $a=@($Task.approvalRequests|Where-Object requestId -ceq $c.RecoveryApprovalId)
    if($a.Count -ne 1 -or $a[0].status -cne 'approved' -or !$a[0].consumedUtc -or $a[0].bindingHash -ine $c.ApprovalBindingHash -or [DateTimeOffset]::Parse($a[0].consumedUtc) -gt [DateTimeOffset]::Parse($a[0].expiresUtc)){throw 'Historical recovery authorization binding mismatch.'}
    $z=$c.Receipt
    if($z.user -ine 'RAMSAI\RepatoQA' -or $z.sid -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or [int]$z.sessionId -lt 1){throw 'Historical recovered receipt execution identity mismatch.'}
    if($z.status -cne 'Passed' -or $z.operation -cne 'prepare-cpv-fixture' -or $z.cleanupVerified -ne $true -or $z.rollbackStatus -cne 'CommittedDisposableFixtureOnly' -or $z.taskId -cne $Task.taskId -or $z.workflowId -cne $Workflow.workflowId -or $z.candidateSha256 -ine $q.candidateEvidence.CandidateDllSha256 -or $z.manifestSha256 -ine $q.candidateEvidence.RunnerManifestSha256){throw 'Historical recovered receipt identity mismatch.'}
    foreach($n in 'requestId','taskId','workflowId','attemptId','runId'){if($z.$n -cne $q.$n){throw 'Historical recovery request identity changed.'}}
    if($p.AttemptId -cne $z.attemptId -or $p.RunId -cne $z.runId -or $Workflow.qaRunId -cne $z.runId -or $p.PreparedModelPath -ine $z.modelPath -or $Workflow.qaModelPath -ine $z.modelPath -or $Workflow.qaDisposableModelSha256 -ine $z.modelSha256 -or $p.PreparedModelSha256 -ine $z.modelSha256 -or [DateTimeOffset]::Parse($p.ExpiresUtc) -ne [DateTimeOffset]::Parse($q.expiresUtc) -or [DateTimeOffset]::Parse($z.expiresUtc) -ne [DateTimeOffset]::Parse($q.expiresUtc)){throw 'Historical preparation identity or original expiry changed.'}
    foreach($pair in @(@('RequestPath','requestPath'),@('RequestSha256','requestSha256'),@('ResultPath','resultPath'),@('ResultSha256','resultSha256'))){if($p.($pair[0]) -ine $z.($pair[1])){throw 'Historical preparation evidence changed.'}}
    Assert-CpvContinuationFile $z.modelPath $z.modelSha256
    Assert-CpvContinuationFile $z.requestPath $z.requestSha256
    Assert-CpvContinuationFile $z.resultPath $z.resultSha256
    if($p.RecoveredProvenancePath -ine $c.RecoveredProvenancePath -or $p.RecoveredProvenanceSha256 -ine $c.RecoveredProvenanceSha256 -or $c.RecoveredProvenancePath -ine ($z.modelPath+'.recovered.fixture.json')){throw 'Recovered companion binding changed.'}
    Assert-CpvContinuationFile $c.RecoveredProvenancePath $c.RecoveredProvenanceSha256
    $s=Get-Content -LiteralPath $c.RecoveredProvenancePath -Raw|ConvertFrom-Json
    if($s.recoveredFromOutcomeUnknown -ne $true -or $s.taskId -cne $Task.taskId -or $s.workflowId -cne $Workflow.workflowId -or $s.requestId -cne $q.requestId -or $s.preparedModelSha256 -ine $z.modelSha256 -or $s.approvalBindingHash -ine $c.ApprovalBindingHash -or $s.recoveryApprovalId -cne $c.RecoveryApprovalId -or $s.fixturePreparationAttemptId -cne $p.AttemptId -or $s.fixturePreparationRunId -cne $p.RunId -or $s.sourceSha256 -ine $p.SourceSha256 -or $s.fixturePreparationRequestSha256 -ine $p.RequestSha256 -or $s.fixturePreparationResultSha256 -ine $p.ResultSha256){throw 'Recovered companion lineage mismatch.'}
    if($Workflow.qaSidecarPath -ine ($z.modelPath+'.fixture.json') -or $s.historicalSidecarPath -ine $Workflow.qaSidecarPath){throw 'Historical sidecar path mismatch.'}
    Assert-CpvContinuationFile $s.historicalSidecarPath $s.historicalSidecarSha256
    if($q.candidateEvidence.CandidateSourceCommit -cnotmatch '^[A-Fa-f0-9]{40}$' -or $e.ArtifactSha256 -cnotmatch '^[A-Fa-f0-9]{64}$' -or $e.CandidateSourceCommit -cnotmatch '^[A-Fa-f0-9]{40}$' -or $e.BuildStatus -cne 'succeeded' -or $e.EvidenceSource -cne 'FrozenCandidate'){throw 'Native or historical candidate identity is incomplete.'}
    Assert-CpvContinuationFile $e.ArtifactPath $e.ArtifactSha256
    [pscustomobject][ordered]@{SchemaVersion='cpv-native-continuation-v1';SourceTaskRevision=$ExpectedTaskRevision;TaskId=$Task.taskId;WorkflowId=$Workflow.workflowId;HistoricalPreparationExpiresUtc=$p.ExpiresUtc;HistoricalPreparationCandidateSha256=$q.candidateEvidence.CandidateDllSha256;HistoricalPreparationCandidateCommit=$q.candidateEvidence.CandidateSourceCommit;HistoricalCandidateEvidenceSha256=(Get-CpvContinuationHash $historical);HistoricalPreparationBindingSha256=(Get-CpvContinuationHash $original);RecoveryCommitSha256=(Get-CpvContinuationHash $c);PreparationEvidenceSha256=(Get-CpvContinuationHash $p);RecoveryApprovalId=$c.RecoveryApprovalId;RecoveryApprovalBindingHash=$c.ApprovalBindingHash;AttemptId=$p.AttemptId;RunId=$p.RunId;ModelPath=$z.modelPath;ModelSha256=$z.modelSha256;HistoricalSidecarPath=$s.historicalSidecarPath;HistoricalSidecarSha256=$s.historicalSidecarSha256;RecoveredProvenancePath=$c.RecoveredProvenancePath;RecoveredProvenanceSha256=$c.RecoveredProvenanceSha256;NativeCandidateSha256=$e.ArtifactSha256;NativeCandidateCommit=$e.CandidateSourceCommit;NativeBuildRequestId=$e.BuildRequestId}
}
function Assert-CpvNativeContinuationBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Task,[Parameter(Mandatory)]$Workflow,[Parameter(Mandatory)]$Binding)
    if([long]$Binding.SourceTaskRevision -gt [long]$Task.revision -or [long]$Binding.SourceTaskRevision -lt 1){throw 'Continuation source revision is invalid.'}
    $actual=New-CpvNativeContinuationBinding -Task $Task -Workflow $Workflow -ExpectedTaskRevision $Task.revision
    $actual.SourceTaskRevision=$Binding.SourceTaskRevision
    if((Get-CpvContinuationHash $actual) -cne (Get-CpvContinuationHash $Binding)){throw 'Native continuation binding changed.'}
}
function Resolve-CpvNativeContinuationExpiry {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Task,[Parameter(Mandatory)]$Workflow,[Parameter(Mandatory)]$Approval,[DateTimeOffset]$NowUtc=[DateTimeOffset]::UtcNow,[ValidateRange(1,240)][int]$AttemptDurationMinutes=30)
    $stored=@($Task.approvalRequests|Where-Object requestId -ceq $Approval.requestId)
    if($stored.Count -ne 1 -or (Get-CpvContinuationHash $stored[0]) -cne (Get-CpvContinuationHash $Approval)){throw 'Fresh native approval must be the exact current task request.'}
    if($Approval.action -cne 'qa-run' -or $Approval.requiredLevel -cne 'user' -or $Approval.status -cne 'approved' -or $Approval.decidedBy -cne 'user' -or !$Approval.decidedUtc -or $Approval.consumedUtc -or [DateTimeOffset]::Parse($Approval.expiresUtc) -le $NowUtc -or [DateTimeOffset]::Parse($Approval.decidedUtc) -gt $NowUtc -or [DateTimeOffset]::Parse($Approval.decidedUtc) -ge [DateTimeOffset]::Parse($Approval.expiresUtc)){throw 'Fresh unconsumed user native QA approval is required.'}
    $b=$Approval.executionBinding
    if($b.TaskId -cne $Task.taskId -or $b.WorkflowId -cne $Workflow.workflowId -or $b.CandidateSha256 -ine $Workflow.qaBuildEvidence.ArtifactSha256 -or $b.CandidateSourceCommit -cne $Workflow.qaBuildEvidence.CandidateSourceCommit -or (Get-CpvContinuationHash $b) -ine $Approval.bindingHash){throw 'Native QA approval binding hash or candidate mismatch.'}
    Assert-CpvNativeContinuationBinding -Task $Task -Workflow $Workflow -Binding $b.NativeContinuation
    $expiry=$NowUtc.AddMinutes($AttemptDurationMinutes);$approved=[DateTimeOffset]::Parse($Approval.expiresUtc)
    if($approved -lt $expiry){$expiry=$approved};$expiry
}
function Add-CpvNativeCompanionRequestBinding {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Request,[Parameter(Mandatory)]$Preparation)
    $path=$Preparation.PSObject.Properties['RecoveredProvenancePath'];$hash=$Preparation.PSObject.Properties['RecoveredProvenanceSha256']
    if(!$path -and !$hash){return}
    if(!$path -or !$hash){throw 'Recovered companion requires both request path and hash.'}
    Assert-CpvContinuationFile ([string]$path.Value) ([string]$hash.Value)
    $Request['recoveredProvenancePath']=[string]$path.Value;$Request['recoveredProvenanceSha256']=[string]$hash.Value
}
Export-ModuleMember -Function New-CpvNativeContinuationBinding,Assert-CpvNativeContinuationBinding,Resolve-CpvNativeContinuationExpiry,Add-CpvNativeCompanionRequestBinding
