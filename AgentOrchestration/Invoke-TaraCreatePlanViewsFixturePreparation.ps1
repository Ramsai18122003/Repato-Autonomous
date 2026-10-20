param(
    [string]$StoreRoot='C:\Repato-Autonomous\Source\QA\MayaRuns',
    [string]$TaskId='task-41cfec12ef3e406990d36c9997cf6591',
    [string]$WorkflowId='78b5a11ab95e4cac86dcf45a1cb9cfdc'
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Force -WarningAction SilentlyContinue
if(@(Get-Process Revit -ErrorAction SilentlyContinue).Count){throw 'An existing Revit process is present; fixture preparation launch is refused.'}
$task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
$workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
$evidence=$workflow.qaBuildEvidence
$retirement=if($task.PSObject.Properties['mayaQaCandidateReplacementRetirement']){$task.mayaQaCandidateReplacementRetirement}else{$null}
$shapeB=$false;$shapeA=$false;$failedRunId=$null
if($retirement -and $retirement.WorkflowId -ceq $WorkflowId){
    $shapeB=($retirement.ReconciledNativeFailure -eq $true -and
        $retirement.HistoricalApprovalDisposition -ceq 'expired-unconsumed' -and
        $retirement.ReplacementNativeLaunchAbsent -eq $true)
    $shapeA=($retirement.PSObject.Properties['FailedAttemptId'] -and
        $retirement.PSObject.Properties['RecoveredAttemptId'] -and
        $retirement.PSObject.Properties['RecoveredRunId'] -and
        $retirement.ConsumedApprovalPreserved -eq $true -and
        $retirement.NativeLaunchAbsent -eq $true)
    if($shapeB){$failedRunId=$retirement.FailedRunId}
    if($shapeA){
        $consumedApprovals=@($task.approvalRequests|Where-Object {
            $_.PSObject.Properties['requestId'] -and $_.PSObject.Properties['action'] -and $_.PSObject.Properties['status'] -and
            $_.requestId -ceq [string]$retirement.ApprovalRequestId -and $_.action -ceq 'qa-run'
        })
        if($consumedApprovals.Count -eq 1 -and $consumedApprovals[0].status -ceq 'approved' -and $consumedApprovals[0].consumedUtc -and
            $consumedApprovals[0].PSObject.Properties['executionBinding'] -and $consumedApprovals[0].executionBinding -and
            $consumedApprovals[0].executionBinding.PSObject.Properties['RunId'] -and [string]$consumedApprovals[0].executionBinding.RunId){
            $failedRunId=[string]$consumedApprovals[0].executionBinding.RunId
        }
    }
}
$recoveredBuildCheck=($task.status -ceq 'in-progress' -and $task.workflowStage -ceq 'build-checks' -and
    ($shapeB -or $shapeA))
if(($task.status -cne 'passed' -and !$recoveredBuildCheck) -or !$evidence -or
    !$evidence.DeploymentValidation -or !$evidence.ManifestIntegrityValidation -or !$evidence.QaIsolation){
    throw 'Frozen candidate approval, validated deployment, manifest integrity, or isolation gate is not satisfied.'
}
$activeApprovals=@()
foreach($approval in @($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and
    ($_.status -ceq 'pending' -or ($_.status -ceq 'approved' -and !$_.consumedUtc))})) {
    $expiry=[DateTimeOffset]::MinValue
    if(![DateTimeOffset]::TryParse([string]$approval.expiresUtc,[ref]$expiry)){throw 'A QA approval has an invalid expiry; fixture preparation is blocked.'}
    if($expiry -gt [DateTimeOffset]::UtcNow){$activeApprovals+=,$approval}
}
if($activeApprovals.Count){throw 'An unexpired QA approval prevents fixture preparation.'}
if($recoveredBuildCheck){
    foreach($name in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){
        if($task.PSObject.Properties[$name] -and $null -ne $task.$name){throw 'Active Tara execution state prevents fixture preparation.'}
    }
    $archivedRunOk=$false
    if($shapeB){
        $archivedRunOk=(@($workflow.qaRunHistory|Where-Object {$_.RunId -ceq $retirement.FailedRunId}).Count -eq 1)
    }
    if($shapeA){
        $handoffHistory=@()
        if($workflow.PSObject.Properties['qaHandoffHistory']){$handoffHistory=@($workflow.qaHandoffHistory)}
        $archivedRunOk=((-not [string]::IsNullOrWhiteSpace([string]$failedRunId)) -and
            @($handoffHistory|Where-Object {$_ -and [string]$_.RunId -ceq $failedRunId}).Count -eq 1 -and
            @($task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $retirement.FailedAttemptId}).Count -ge 1)
    }
    if($workflow.qaRunId -or $workflow.qaModelPath -or $workflow.qaSidecarPath -or
        $workflow.qaFixturePreparationEvidence -or !$archivedRunOk){
        throw 'Recovered prior run was not safely archived before fixture preparation.'
    }
}
$primaryRepositoryRoot=(Resolve-MayaQaAuthenticatedBuildSource $null).PrimaryRepositoryRoot
$qa=[IO.Path]::GetFullPath((Join-Path $primaryRepositoryRoot 'QA'))
if($qa -ine [IO.Path]::GetFullPath('C:\Repato-Autonomous\Source\QA')){throw 'Fixture preparation must use the pinned primary Source\QA root.'}
$source=Join-Path $qa 'Fixtures\CreatePlanViewsEmpty.rvt'
$sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$provenance=Get-Content -LiteralPath (Join-Path $qa 'Fixtures\CreatePlanViewsEmpty.provenance.json') -Raw|ConvertFrom-Json
if($provenance.fixtureId -cne 'CreatePlanViewsEmpty' -or $provenance.sourceSha256 -ine $sourceHash){throw 'Original fixture/provenance mismatch; preparation refused.'}
$runId=[guid]::NewGuid().ToString('N')
$runRoot=Join-Path (Join-Path $qa 'TestRuns') ('fixture-preparation-'+$runId)
New-Item -ItemType Directory -Path $runRoot|Out-Null
$model=Join-Path $runRoot 'model.rvt'
Copy-Item -LiteralPath $source -Destination $model
$sidecar=$model+'.fixture.json'
[ordered]@{fixtureId='CreatePlanViewsEmpty';sourceSha256=$sourceHash}|ConvertTo-Json|Set-Content -LiteralPath $sidecar -Encoding UTF8
$context=[pscustomobject]@{QaRoot=$qa;SourceFixturePath=$source;FixtureId='CreatePlanViewsEmpty';FixtureSha256=$sourceHash;TestId='create-plan-views-v1';ArtifactPath=$evidence.ArtifactPath;ArtifactSha256=$evidence.ArtifactSha256;ManifestPath=$evidence.ManifestPath;ManifestSha256=$evidence.ManifestSha256;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId='create-plan-views-v1';RunId=$runId}
$plan=New-TaraRevitQaPlan -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId 'create-plan-views-v1' -RunId $runId -ModelPath $model -SidecarPath $sidecar -ReportDirectory (Join-Path $qa 'Reports') -RevitInstallDir 'E:\revit\Revit 2025' -QaAddinRoot 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA' -TimeoutSeconds 7200 -FixturePreparation -ManualLoadOnce -NoForceRevitClose -Context $context
$startedUtc=[DateTimeOffset]::UtcNow
$result=Invoke-TaraRevitQa -Plan $plan
$preparedHash=$null;$journalPath=$null;$journalSha256=$null;$journalPromptDetected=$null;$evidenceConsistent=$false
if($result.ExitState -eq 'Exited' -and @(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count -eq 0){
    $preparedHash=(Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash
    $journalRoot=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Autodesk\Revit\Autodesk Revit 2025\Journals'
    $journals=@(Get-ChildItem -LiteralPath $journalRoot -File -Filter 'journal.*.txt' -ErrorAction Stop|Where-Object {$_.LastWriteTimeUtc -ge $startedUtc.UtcDateTime}|Sort-Object LastWriteTimeUtc -Descending)
    $journal=@($journals|Where-Object {(Get-Content -LiteralPath $_.FullName -Raw) -match [regex]::Escape($model)}|Select-Object -First 1)
    if($journal.Count -eq 1){
        $journalPath=$journal[0].FullName
        $journalText=Get-Content -LiteralPath $journalPath -Raw
        $journalSha256=(Get-FileHash -LiteralPath $journalPath -Algorithm SHA256).Hash
        $journalPromptDetected=($journalText -match '(?i)TaskDialog_Security_Unsigned_File_Loading|publisher\s+of\s+this\s+add-in\s+could\s+not\s+be\s+verified')
        $evidenceConsistent=(!$journalPromptDetected -and !$result.PromptDetected -and $result.PromptFree -and $result.PromptObservationCount -gt 0 -and $preparedHash -ieq [string]$result.Preparation.PreparedModelSha256)
    }
}
$success=($result.Success -and $result.Status -ceq 'Passed' -and $result.ExitState -ceq 'Exited' -and $preparedHash -ieq [string]$result.Preparation.PreparedModelSha256 -and $evidenceConsistent)
[pscustomobject]@{Success=$success;Status=$(if($success){'Passed'}elseif($result.PromptDetected){'AwaitingHumanTrustDecision'}else{'Failed'});TaskId=$TaskId;WorkflowId=$WorkflowId;AttemptId=$plan.RequestId;RunId=$runId;ProcessId=$result.ProcessId;PromptDetected=$result.PromptDetected;PromptAction=$result.PromptAction;PromptFree=$result.PromptFree;PromptObservationCount=$result.PromptObservationCount;PromptEvidence=$result.PromptEvidence;ModelPath=$model;SourceModelSha256=$sourceHash;PreparedModelSha256=$preparedHash;RequestPath=$plan.RequestPath;PreparationPath=$plan.ResultPath;EvidencePath=$plan.EvidencePath;JournalPath=$journalPath;JournalSha256=$journalSha256;JournalPromptDetected=$journalPromptDetected;PromptEvidenceConsistent=$evidenceConsistent;ExitState=$result.ExitState;Failure=$result.FailureReason;Preparation=$result.Preparation}|ConvertTo-Json -Depth 10
if(!$result.Success){throw "Disposable fixture preparation failed: $($result.FailureReason)"}
if(!$success){throw 'Fixture preparation evidence is incomplete or inconsistent; it cannot be used for QA authorization.'}
