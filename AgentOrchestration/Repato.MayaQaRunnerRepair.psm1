Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -WarningAction SilentlyContinue

function New-MayaQaRunnerRepairBuildRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$FailedAttemptId,
        [string]$UserRequest='Repair missing Create Plan Views QA runner',
        [switch]$DryRun
    )
    $data=Read-RepatoTaskStore $StoreRoot
    $task=Find-RepatoTask $data $TaskId
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $attempt=$task.mayaTaraAttempt
    $execution=$task.mayaTaraExecution
    if(!$task -or $task.status -cne 'blocked' -or $task.workflowStage -cne 'qa' -or !$attempt -or !$execution -or
       $attempt.AttemptId -cne $FailedAttemptId -or $execution.AttemptId -cne $FailedAttemptId -or
       $attempt.Stage -cne 'runner-startup-failed' -or $execution.Stage -cne 'runner-startup-failed' -or
       $execution.ExecutionStatus -cne 'RunnerStartupFailed' -or $execution.FailureCode -cne 'runner-startup-failed')
        { throw 'Repair build request requires the exact terminal runner-startup-failed attempt.' }
    $evidence=$execution.RunnerStartupEvidence
    if(!$evidence -or $evidence.Disposition -cne 'Revit launched; runner startup failed; no QA result' -or
       !$evidence.ProcessExitConfirmed -or !$evidence.ResultAbsent -or !$evidence.ManualLoadOnceAcknowledged -or
       [string]$evidence.AttemptId -cne $FailedAttemptId -or [string]$evidence.TaskId -cne $TaskId)
        { throw 'Audited startup-failure evidence is incomplete or not bound to this attempt.' }
    if($execution.ReportPath -or $execution.ReceiptPath -or (Test-Path -LiteralPath ([string]$execution.ResultPath)))
        { throw 'Request-bound QA result evidence exists; this repair-build path is not eligible.' }
    if(@(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count) { throw 'A Revit process is present; repair build preparation is blocked.' }

    $oldBuild=$workflow.qaBuildEvidence
    if($workflow.qaBuildStatus -cne 'succeeded' -or !$oldBuild -or $oldBuild.EvidenceSource -cne 'FrozenCandidate' -or
       $oldBuild.CandidateSourceCommit -cne 'fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3' -or
       $oldBuild.ArtifactSha256 -cne '7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2')
        { throw 'Persisted prior candidate is not the confirmed frozen candidate.' }
    if(!$workflow.qaBuildRequest -or !$workflow.qaBuildRequest.BuildRequestId -or
       !$workflow.qaBuildRequest.AuthenticatedBuildSource -or
       [string]$workflow.qaBuildRequest.AuthenticatedBuildSource.ExpectedSourceCommit -cne 'fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3')
        { throw 'Prior persisted build request is not bound to the confirmed frozen source.' }
    foreach($name in 'qaReportPath','qaReceiptPath','qaEvidence','qaVerificationStatus','qaCompletionStatus') {
        if($workflow.PSObject.Properties.Name -contains $name -and $workflow.$name) { throw "Repair build found terminal QA evidence: $name." }
    }

    $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $project=[IO.Path]::GetFullPath((Join-Path $repo 'Forma.RevitConnector.csproj'))
    $sourceCommit=Get-MayaQaTrustedBuildSourceCommit -RepositoryRoot $repo -ProjectPath $project
    $branch=(& git -C $repo branch --show-current 2>$null).Trim()
    if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) { throw 'Repair build source branch could not be resolved.' }
    $requestId='build-'+[guid]::NewGuid().ToString('N')
    $replacement=[pscustomobject][ordered]@{
        BuildRequestId=$requestId; SourceBranch=$branch; ProjectPath='Forma.RevitConnector.csproj'
        AuthenticatedBuildSource=$null; RequestedArtifact='bin\Release\net8.0-windows\Repato.Revit.dll'
        BuildStatus='requested'; RequestedUtc=(Get-Date).ToUniversalTime().ToString('O')
    }
    if($DryRun) {
        return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;FailedAttemptId=$FailedAttemptId;
            PreviousBuildRequestId=$workflow.qaBuildRequest.BuildRequestId;ReplacementBuildRequestId=$requestId;
            SourceBranch=$branch;SourceCommit=$sourceCommit;ProjectPath=$project;CandidateEvidencePreserved=$true;
            StoreMutationPerformed=$false;CandidateBuilt=$false;DeploymentPerformed=$false;QaAttemptCreated=$false}
    }
    $oldWorkflowRevision=[long]$workflow.workflowRevision
    $oldTaskRevision=[long]$task.revision
    $prior=[pscustomobject][ordered]@{BuildRequest=$workflow.qaBuildRequest;BuildEvidence=$oldBuild;
        SupersededByBuildRequestId=$requestId;SupersededUtc=(Get-Date).ToUniversalTime().ToString('O');
        Reason='Confirmed runner-startup-failed; rebuild source contains the restored manifest-bound runner.'}
    $mutation=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $oldWorkflowRevision $oldTaskRevision {
        param($current)
        if($current.qaBuildRequest.BuildRequestId -cne $workflow.qaBuildRequest.BuildRequestId -or
           $current.qaBuildStatus -cne 'succeeded' -or $current.qaBuildEvidence.CandidateSourceCommit -cne $oldBuild.CandidateSourceCommit)
            { throw 'Repair build request compare-and-swap failed.' }
        if($current.PSObject.Properties.Name -notcontains 'qaBuildHistory') { $current|Add-Member NoteProperty qaBuildHistory ([object[]]@()) -Force }
        $current.qaBuildHistory=[object[]]@($current.qaBuildHistory)+$prior
        $current.qaBuildRequestId=$requestId
        $current.qaBuildRequest=$replacement
        $current.qaBuildStatus='requested'
        $current.qaBuildEvidence=$null
        return $current
    })[-1]
    [pscustomobject]@{Mode='Superseded';TaskId=$TaskId;WorkflowId=$WorkflowId;FailedAttemptId=$FailedAttemptId;
        PreviousBuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildRequestId=$requestId;SourceBranch=$branch;
        SourceCommit=$sourceCommit;WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;
        PriorCandidateEvidenceRetained=$true;QaAttemptCreated=$false;DeploymentPerformed=$false}
}

Export-ModuleMember -Function New-MayaQaRunnerRepairBuildRequest
