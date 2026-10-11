Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -WarningAction SilentlyContinue
. (Join-Path $PSScriptRoot 'MayaQa.TaraExecution.ps1')
Import-Module (Join-Path $PSScriptRoot 'Repato.CandidateEvidence.psm1') -Force -WarningAction SilentlyContinue
$script:Definitions = @{
    'welcome-smoke' = @{ FixtureId='CreateLevelsEmpty'; Source='CreateLevelsEmpty.rvt'; Prep=$null; TestId='welcome-supervised-dialog-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'welcome-supervised-dialog-v1' = @{ FixtureId='CreateLevelsEmpty'; Source='CreateLevelsEmpty.rvt'; Prep=$null; TestId='welcome-supervised-dialog-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'create-grids-world-axis-v1' = @{ FixtureId='CreateGridsEmptyPlan'; Source='CreateGridsEmptyPlan.rvt'; Prep='Prepare-CreateGridsQaRun.ps1'; TestId='create-grids-world-axis-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
        'create-levels' = @{ FixtureId='CreateLevelsEmpty'; Source='CreateLevelsEmpty.rvt'; Prep='Prepare-CreateLevelsQaRun.ps1'; TestId='create-levels-elevations-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'create-levels-elevations-v1' = @{ FixtureId='CreateLevelsEmpty'; Source='CreateLevelsEmpty.rvt'; Prep='Prepare-CreateLevelsQaRun.ps1'; TestId='create-levels-elevations-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'grid-bubble-visibility-v1' = @{ FixtureId='GridBubbleVisibilityEmpty'; Source='GridBubbleVisibilityEmpty.rvt'; Prep='Prepare-GridBubbleVisibilityQaRun.ps1'; TestId='grid-bubble-visibility-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'grid-bubble-offset-v1' = @{ FixtureId='GridBubbleOffsetEmpty'; Source='GridBubbleOffsetEmpty.rvt'; Prep='Prepare-GridBubbleOffsetQaRun.ps1'; TestId='grid-bubble-offset-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'grid-resequence-v1' = @{ FixtureId='GridResequenceEmpty'; Source='GridResequenceEmpty.rvt'; Prep='Prepare-GridResequenceQaRun.ps1'; TestId='grid-resequence-v1'; NativeTestId='grid-resequence-all-directions-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'grid-resequence-all-directions-v1' = @{ FixtureId='GridResequenceEmpty'; Source='GridResequenceEmpty.rvt'; Prep='Prepare-GridResequenceQaRun.ps1'; TestId='grid-resequence-v1'; NativeTestId='grid-resequence-all-directions-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'create-plan-views-v1' = @{ FixtureId='CreatePlanViewsEmpty'; Source='CreatePlanViewsEmpty.rvt'; Prep='Prepare-CreatePlanViewsQaRun.ps1'; TestId='create-plan-views-v1'; NativeTestId='create-plan-views-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
}
function Get-MayaQaWorkflowDefinition { param([Parameter(Mandatory)][string]$WorkflowId)
    if (-not $script:Definitions.ContainsKey($WorkflowId)) { throw "Unsupported QA workflow ID: $WorkflowId" }
    [pscustomobject]$script:Definitions[$WorkflowId]
}
function Resolve-MayaQaWorkflowId {
    param([Parameter(Mandatory)][string]$WorkflowId)
    return [string](Get-MayaQaWorkflowDefinition $WorkflowId).TestId
}
function Get-MayaQaNativeTestId {
    param([Parameter(Mandatory)][object]$Definition)
    if ($Definition.PSObject.Properties.Name -contains 'NativeTestId' -and $Definition.NativeTestId) { return [string]$Definition.NativeTestId }
    return [string]$Definition.TestId
}
function Get-MayaQaRequestIntent {
    param([Parameter(Mandatory)][string]$Request)
    $text = $Request.Trim().ToLowerInvariant()
    $offset = $null
    if ($text -match '(?<value>-?\d+(?:\.\d+)?)\s*mm\b') { $offset = [decimal]$Matches.value }
    $direction = $null
    $directionMap = @{
        'bottom\s+to\s+top' = 'BottomToTop'
        'top\s+to\s+bottom' = 'TopToBottom'
        'left\s+to\s+right' = 'LeftToRight'
        'right\s+to\s+left' = 'RightToLeft'
    }
    foreach ($pattern in $directionMap.Keys) { if ($text -match $pattern) { $direction = $directionMap[$pattern]; break } }
    $levels=@();if($text -match '\blevels?\s+(?<list>.*?)(?:\s+at\s|\s+using\s|\s+named\s|$)'){$levels=@([regex]::Matches($Matches.list,'\d+')|ForEach-Object{[int]$_.Value})}
    $scale=if($text -match '(?<scale>\d+\s*:\s*\d+)'){$Matches.scale -replace '\s',''}else{$null}
    [pscustomobject]@{
        GridSelection = if ($text -match 'selected\s+grids?|selected\s+grid') { 'selected-grids' } else { $null }
        BubbleSides = @(@('left','right','top','bottom') | Where-Object { $text -match "\b$_\b" })
        OffsetMillimetres = $offset
        ResequenceDirection = $direction
        CustomNamingIntent = if ($text -match 'custom\s+naming|name|naming|label|prefix|number') { $Request } else { $null }
        SelectedLevels = $levels
        ViewType = if ($text -match 'floor\s+plan') { 'floor-plan' } elseif ($text -match 'ceiling\s+plan') { 'ceiling-plan' } else { $null }
        Scale = $scale
        TemplateIntent = if ($text -match 'template|using\s+the') { $Request } else { $null }
    }
}
function Get-MayaQaWorkflowCatalog {
    @($script:Definitions.GetEnumerator() | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{WorkflowId=$_.Key;FixtureId=$_.Value.FixtureId;TestId=$_.Value.TestId;PreparationScript=$_.Value.Prep;Capabilities=@($_.Value.Capabilities);SupervisedExecutionRequired=$true;RevitLaunchByCoordinator=$false;RealDeploymentByCoordinator=$false;DryRunSupported=$true}
    })
}
function Resolve-MayaQaTaskStoreIdentity {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    $data = $null
    try { $data = Read-RepatoTaskStore $StoreRoot } catch { $errors.Add("Task store read failed: $($_.Exception.Message)") }
    $tasks = if ($data -and $data.PSObject.Properties.Name -contains 'tasks') { @($data.tasks) } else { @() }
    $taskMatches = @($tasks | Where-Object { $_.PSObject.Properties.Name -contains 'taskId' -and $_.taskId -ceq $TaskId })
    if ($taskMatches.Count -ne 1) {
        $ids = @($taskMatches | ForEach-Object { [string]$_.taskId }) -join ', '
        $errors.Add("Exact TaskId '$TaskId' matched $($taskMatches.Count) records: [$ids]")
    }
    $workflowMatches = @()
    if ($taskMatches.Count -eq 1) {
        $task = $taskMatches[0]
        if ($task.PSObject.Properties.Name -contains 'mayaPlan') {
            $workflowMatches = @($task | Where-Object { $_.mayaPlan.WorkflowId -ceq $WorkflowId })
        }
        if ($workflowMatches.Count -ne 1) {
            $errors.Add("Exact orchestration WorkflowId '$WorkflowId' did not resolve within TaskId '$TaskId'; matches=$($workflowMatches.Count)")
        }
    }
    $catalogMatches = @($script:Definitions.GetEnumerator() | Where-Object { $_.Key -ceq $QaWorkflowId } | ForEach-Object {
        [pscustomobject]@{ WorkflowId = $_.Key; TestId = $_.Value.TestId }
    })
    if ($catalogMatches.Count -ne 1) {
        $errors.Add("Exact QA catalog QaWorkflowId/TestId '$QaWorkflowId' matched $($catalogMatches.Count) definitions")
    }
    $handoffMatches=@();$attemptMatches=@();$runMatches=@()
    if($taskMatches.Count -eq 1){
        $task=$taskMatches[0]
        $packet=if($task.PSObject.Properties.Name -contains 'mayaTaraQaPacket'){$task.mayaTaraQaPacket}else{$null}
        $attempt=if($task.PSObject.Properties.Name -contains 'mayaTaraAttempt'){$task.mayaTaraAttempt}else{$null}
        if($packet -and $packet.HandoffId -ceq $packet.HandoffId){$handoffMatches=@($packet|Where-Object{$_.TaskId -ceq $TaskId -and $_.WorkflowId -ceq $WorkflowId -and $_.QaWorkflowId -ceq $QaWorkflowId})}
        if($attempt){$attemptMatches=@($attempt|Where-Object{$_.TaskId -ceq $TaskId -and $_.WorkflowId -ceq $WorkflowId -and $_.RunId -ceq $attempt.RunId})}
        if($attemptMatches.Count -eq 1){$runMatches=@($attemptMatches|Where-Object{$_.RunId -ceq $attempt.RunId})}
        if($handoffMatches.Count -ne 1){$errors.Add("Exact persisted Handoff link matched $($handoffMatches.Count) records")}
        if($attemptMatches.Count -ne 1){$errors.Add("Exact persisted Attempt link matched $($attemptMatches.Count) records")}
        if($runMatches.Count -ne 1){$errors.Add("Exact persisted Run link matched $($runMatches.Count) records")}
    }
    [pscustomobject]@{
        TaskMatchCount = $taskMatches.Count
        WorkflowMatchCount = $workflowMatches.Count
        QaCatalogMatchCount = $catalogMatches.Count
        HandoffMatchCount = $handoffMatches.Count
        AttemptMatchCount = $attemptMatches.Count
        RunMatchCount = $runMatches.Count
        SelectedTaskId = if ($taskMatches.Count -eq 1) { $TaskId } else { $null }
        SelectedWorkflowId = if ($workflowMatches.Count -eq 1) { $WorkflowId } else { $null }
        SelectedQaWorkflowId = if ($catalogMatches.Count -eq 1) { $catalogMatches[0].WorkflowId } else { $null }
        SelectedHandoffId = if($handoffMatches.Count -eq 1){$taskMatches[0].mayaTaraQaPacket.HandoffId}else{$null}
        SelectedAttemptId = if($attemptMatches.Count -eq 1){$taskMatches[0].mayaTaraAttempt.AttemptId}else{$null}
        SelectedRunId = if($runMatches.Count -eq 1){$taskMatches[0].mayaTaraAttempt.RunId}else{$null}
        Errors = @($errors)
    }
}
function Assert-MayaQaExecutionIdentity {
    param([object]$Record,[object]$Resolved)
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','HandoffId','AttemptId','RunId') { if([string]$Record.$n -cne [string]$Resolved.('Selected'+$n)) { throw "Execution identity mismatch: $n" } }
    if($Record.QaWorkflowId -cne $Record.TestId){throw 'Execution QA catalog identity mismatch.'}
}
function New-MayaQaExecutionRecord {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][object]$Preflight,[switch]$DryRun)
    $expected=@{TaskId=$TaskId;WorkflowId=$Preflight.WorkflowId;QaWorkflowId=$Preflight.QaWorkflowId}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $Preflight.WorkflowId $Preflight.QaWorkflowId
    if(@($resolved.Errors).Count){throw ('Canonical execution identity invalid: '+(@($resolved.Errors)-join '; '))}
    foreach($n in 'HandoffId','AttemptId','RunId'){if([string]$Preflight.$n -cne [string]$resolved.('Selected'+$n)){throw "Canonical execution identity mismatch: $n"}}
    $record=[ordered]@{SchemaVersion='maya-tara-execution-v1';TaskId=$resolved.SelectedTaskId;WorkflowId=$resolved.SelectedWorkflowId;QaWorkflowId=$resolved.SelectedQaWorkflowId;TestId=$Preflight.TestId;HandoffId=$resolved.SelectedHandoffId;AttemptId=$resolved.SelectedAttemptId;RunId=$resolved.SelectedRunId;ArtifactPath=$Preflight.ArtifactPath;ArtifactSha256=$Preflight.ArtifactSha256;RunnerManifestPath=$Preflight.RunnerManifest;ValidatedRunnerManifestPath=$Preflight.ValidatedRunnerManifestPath;RunnerManifestSha256=$Preflight.RunnerManifestSha256;ValidatedRunnerManifestSha256=$Preflight.ValidatedRunnerManifestSha256;AuthoritativeFixturePath=$Preflight.FixturePath;AuthoritativeFixtureSha256=$Preflight.FixtureSha256;DisposableRuntimeRoot=([IO.Path]::GetDirectoryName($Preflight.DisposableFixturePath));DisposableModelPath=$Preflight.DisposableFixturePath;DisposableModelSha256=$Preflight.DisposableFixtureSha256;IsolationPolicyPath=$Preflight.Isolation.PolicyPath;IsolationPolicySha256=$Preflight.Isolation.PolicySha256;IsolationAllowed=[bool]$Preflight.Isolation.Allowed;ClaimOwner=$null;ClaimId=$null;ClaimedUtc=$null;ClaimStatus='unclaimed';Stage='prepared';ExecutionStatus='Prepared';PreparedUtc=Get-RepatoUtc;LaunchingUtc=$null;LaunchedUtc=$null;ExecutingUtc=$null;EvidenceCollectedUtc=$null;RollbackStartedUtc=$null;RollbackVerifiedUtc=$null;VerifiedUtc=$null;CompletedUtc=$null;FailedUtc=$null;NativeProcessId=$null;RequestPath=$null;ResultPath=$null;ReportPath=$null;EvidencePath=$null;ReceiptPath=$null;RollbackStatus='Required';VerificationStatus='Pending';CompletionStatus='Pending';FailureCode=$null;FailureDetails=$null;TaskRevisionAtPrepare=$null;TaskRevisionAtClaim=$null;SideEffectsPerformed=$false}
    $record.FixturePreparationEvidence=$Preflight.FixturePreparationEvidence
    if($DryRun){$record.SideEffectsPerformed=$false;return [pscustomobject]$record}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$existing=if($task.PSObject.Properties.Name -contains 'mayaTaraExecution'){$task.mayaTaraExecution}else{$null};if($existing){Assert-MayaQaExecutionIdentity $existing $resolved;if($existing.Stage -cne 'prepared' -or $existing.ExecutionStatus -cne 'Prepared'){throw 'Existing Maya Tara execution is not reusable.'};foreach($n in 'ArtifactSha256','RunnerManifestSha256','AuthoritativeFixtureSha256','DisposableModelSha256'){if([string]$existing.$n -cne [string]$record.$n){throw "Existing execution hash mismatch: $n"}};return $existing};$record.TaskRevisionAtPrepare=[long]$task.revision;$task|Add-Member NoteProperty mayaTaraExecution ([pscustomobject]$record) -Force;Add-RepatoHistory $task 'maya-tara-execution-prepared' 'Maya' "attempt=$($record.AttemptId); run=$($record.RunId)";$task.mayaTaraExecution} -DryRun:$DryRun
}
function Claim-MayaQaExecutionRecord {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimOwner,[Parameter(Mandatory)][object]$Preflight)
    if($ClaimOwner -cne 'Tara'){throw 'Canonical native execution claims must be owned by Tara.'}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;if($task.PSObject.Properties.Name -notcontains 'mayaTaraExecution'){throw 'Maya Tara execution is not prepared.'};$r=$task.mayaTaraExecution;foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId'){if([string]$r.$n -cne [string]$Preflight.$n){throw "Execution identity mismatch: $n"}};$attempt=if($task.PSObject.Properties.Name -contains 'mayaTaraAttempt'){$task.mayaTaraAttempt}else{$null};if(!$attempt -or $attempt.AttemptId -cne $r.AttemptId -or $attempt.RunId -cne $r.RunId){throw 'Maya Tara attempt is not current.'};$approvedRoot=[IO.Path]::GetFullPath((Get-MayaQaRuntimeRoot)).TrimEnd('\');$candidate=[string]$attempt.RuntimeRoot;if([string]::IsNullOrWhiteSpace($candidate) -or ![IO.Path]::IsPathRooted($candidate)){throw 'Maya Tara RuntimeRoot is missing or relative.'};try{$candidate=[IO.Path]::GetFullPath($candidate)}catch{throw 'Maya Tara RuntimeRoot normalization failed.'};$inside=($candidate -ieq $approvedRoot) -or $candidate.StartsWith($approvedRoot+'\',[StringComparison]::OrdinalIgnoreCase);if(!$inside){throw 'Maya Tara RuntimeRoot escaped the approved QA runtime root.'};if([DateTimeOffset]::Parse($attempt.RequestExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Maya Tara attempt is expired.'};if([long]$task.revision -ne ([long]$r.TaskRevisionAtPrepare+1)){throw 'Prepared execution revision is stale or task changed after preparation.'};if($r.Stage -ne 'prepared' -or $r.ExecutionStatus -ne 'Prepared' -or $r.ClaimStatus -ne 'unclaimed'){throw 'Maya Tara execution is not claimable.'};$r.ClaimId=[guid]::NewGuid().ToString('N');$r.ClaimOwner=$ClaimOwner;$r.ClaimedUtc=Get-RepatoUtc;$r.ClaimStatus='claimed';$r.Stage='claimed';$r.ExecutionStatus='Claimed';$r.TaskRevisionAtClaim=[long]$task.revision;Add-RepatoHistory $task 'maya-tara-execution-claimed' $ClaimOwner "claim=$($r.ClaimId); attempt=$($r.AttemptId); run=$($r.RunId)";$r}
}
function Get-MayaQaAttemptDurationMinutes { 30 }
function Recover-MayaQaExpiredExecutionRecord {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[ValidateRange(1,1440)][Nullable[int]]$AttemptDurationMinutes,[string]$RuntimeRoot,[switch]$DryRun)
    if($null -eq $AttemptDurationMinutes){$AttemptDurationMinutes=Get-MayaQaAttemptDurationMinutes}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if($task.PSObject.Properties.Name -notcontains 'mayaTaraExecution' -or $task.PSObject.Properties.Name -notcontains 'mayaTaraAttempt'){throw 'Canonical Maya Tara execution and attempt are required.'}
    $old=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt;$resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Canonical recovery identity invalid: '+(@($resolved.Errors)-join '; '))}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','HandoffId','AttemptId','RunId'){if([string]$old.$n -cne [string]$resolved.('Selected'+$n)){throw "Recovery identity mismatch: $n"}}
    $claimedRecovery=($old.Stage -ceq 'claimed' -and $old.ExecutionStatus -ceq 'Claimed' -and $old.ClaimStatus -ceq 'claimed')
    $preparedRecovery=($old.Stage -ceq 'prepared' -and $old.ExecutionStatus -ceq 'Prepared' -and $old.ClaimStatus -ceq 'unclaimed' -and !$old.ClaimId -and !$old.ClaimOwner)
    if(!$claimedRecovery -and !$preparedRecovery){throw 'Execution is not eligible for automatic recovery.'}
    if($claimedRecovery -and ($old.ClaimOwner -cne 'Tara' -or [string]::IsNullOrWhiteSpace([string]$old.ClaimId))){throw 'Claimed execution has invalid ownership or claim identity.'}
    foreach($n in 'NativeProcessId','LaunchingUtc','LaunchedUtc','ExecutingUtc','RequestPath','ResultPath','ReportPath','EvidencePath','ReceiptPath'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw "Execution contains launch evidence: $n"}}
    if($old.SideEffectsPerformed){throw 'Execution has side effects and requires reconciliation.'}
    if([DateTimeOffset]::Parse($attempt.RequestExpiresUtc) -gt [DateTimeOffset]::UtcNow){throw 'Current Maya Tara attempt is not expired.'}
    foreach($n in 'RequestPath','ResultPath','ReportPath','EvidencePath','ReceiptPath'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw 'Execution contains native evidence and cannot be auto-recovered.'}}
    if($task.PSObject.Properties.Name -contains 'mayaTaraExecutionHistory' -and @($task.mayaTaraExecutionHistory|Where-Object{$_.AttemptId -ceq $attempt.AttemptId}).Count){throw 'Expired attempt was already recovered.'}
    $qa=[IO.Path]::GetFullPath((Get-MayaQaRoot));$source=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);$fixtures=[IO.Path]::GetFullPath((Join-Path $qa 'Fixtures'));$runs=[IO.Path]::GetFullPath($(if($RuntimeRoot){$RuntimeRoot}else{Get-MayaQaRuntimeRoot}));$prefix=$fixtures.TrimEnd('\')+'\';if(!$source.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Authoritative fixture escaped approved fixture root.'};$sourceHash=(Get-FileHash $source -Algorithm SHA256).Hash;if($sourceHash -ine $old.AuthoritativeFixtureSha256){throw 'Authoritative fixture hash mismatch.'}
    $newAttempt=[guid]::NewGuid().ToString('N');$newRun=[guid]::NewGuid().ToString('N');$runtime=[IO.Path]::GetFullPath((Join-Path $runs ($newRun+'-recovery')));$runPrefix=$runs.TrimEnd('\')+'\';if(!$runtime.StartsWith($runPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Recovery runtime escaped approved QA root.'};if($runtime -ieq ([IO.Path]::GetDirectoryName($old.DisposableModelPath))){throw 'Historical runtime cannot be reused.'}
    $model=Join-Path $runtime 'model.rvt';$sidecar=$model+'.fixture.json';$def=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId
    if(!$DryRun){New-Item -ItemType Directory -Path $runtime -Force|Out-Null;Copy-Item $source $model -Force;$modelHash=(Get-FileHash $model -Algorithm SHA256).Hash;if($modelHash -ine $sourceHash){throw 'Recovered disposable model hash mismatch.'};$side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$sourceHash};if($resolved.SelectedQaWorkflowId -eq 'grid-bubble-visibility-v1' -or $resolved.SelectedQaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')};if($resolved.SelectedQaWorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')};$side|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $sidecar -Encoding UTF8;$check=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json;if(!(Test-Path -LiteralPath $model -PathType Leaf) -or !(Test-Path -LiteralPath $sidecar -PathType Leaf) -or $check.fixtureId -cne $def.FixtureId -or $check.sourceSha256 -ine $sourceHash -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine $sourceHash){throw 'Recovered disposable model or fixture sidecar validation failed.'}}else{$modelHash=$sourceHash}
    $newExpiry=[DateTimeOffset]::UtcNow.AddMinutes($AttemptDurationMinutes).ToString('O');$newAttemptRecord=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$newAttempt;TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;RunId=$newRun;RuntimeRoot=$runtime;RequestExpiresUtc=$newExpiry;Stage='prepared';Success=$false;RequestPath=$null}
    $newExec=[ordered]@{};foreach($p in $old.PSObject.Properties){$newExec[$p.Name]=$p.Value};$newExec.AttemptId=$newAttempt;$newExec.RunId=$newRun;$newExec.DisposableRuntimeRoot=$runtime;$newExec.DisposableModelPath=$model;$newExec.DisposableModelSha256=$modelHash;$newExec.Stage='prepared';$newExec.ExecutionStatus='Prepared';$newExec.ClaimStatus='unclaimed';$newExec.ClaimOwner=$null;$newExec.ClaimId=$null;$newExec.ClaimedUtc=$null;$newExec.TaskRevisionAtPrepare=$null;$newExec.TaskRevisionAtClaim=$null;$newExec.NativeProcessId=$null;$newExec.SideEffectsPerformed=$false;$newExec.PreparedUtc=Get-RepatoUtc;$newExec.FailureCode=$null;$newExec.FailureDetails=$null
    if($DryRun){return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;QaWorkflowId=$resolved.SelectedQaWorkflowId;HandoffId=$resolved.SelectedHandoffId;OldAttemptId=$attempt.AttemptId;OldRunId=$attempt.RunId;NewAttemptId=$newAttempt;NewRunId=$newRun;RuntimeRoot=$runtime;DisposableModelPath=$model;DisposableModelSha256=$modelHash;SideEffectsPerformed=$false}}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$nowAttempt=$t.mayaTaraAttempt;$nowExec=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $nowAttempt.AttemptId -cne $attempt.AttemptId -or $nowAttempt.RunId -cne $attempt.RunId -or $nowExec.AttemptId -cne $old.AttemptId -or $nowExec.RunId -cne $old.RunId){throw 'Recovery compare-and-swap failed: task changed.'};if([DateTimeOffset]::Parse($nowAttempt.RequestExpiresUtc)-gt[DateTimeOffset]::UtcNow){throw 'Current attempt is no longer expired.'};$archived=[pscustomobject]$old;$archived|Add-Member NoteProperty Stage 'expired' -Force;$archived|Add-Member NoteProperty ExecutionStatus 'Expired' -Force;$archived|Add-Member NoteProperty ClaimStatus 'expired' -Force;$archived|Add-Member NoteProperty FailureCode 'attempt-expired' -Force;$archived|Add-Member NoteProperty FailureDetails 'Unclaimed prepared attempt expired before native launch.' -Force;$archived|Add-Member NoteProperty ExpiredUtc (Get-RepatoUtc) -Force;$archived|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;$archived|Add-Member NoteProperty ReplacementRunId $newRun -Force;if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$archived;$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$nowAttempt;$t.mayaTaraAttempt=$newAttemptRecord;$newExec.TaskRevisionAtPrepare=[long]$t.revision;$t.mayaTaraExecution=[pscustomobject]$newExec;Add-RepatoHistory $t 'maya-tara-attempt-recovered' 'Maya' "expiredAttempt=$($attempt.AttemptId); expiredRun=$($attempt.RunId); replacementAttempt=$newAttempt; replacementRun=$newRun";$t.mayaTaraExecution}
}
function Recover-MayaQaTerminalLaunchFailure {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[string]$RuntimeRoot,[ValidateRange(1,1440)][Nullable[int]]$AttemptDurationMinutes,[scriptblock]$ManifestValidationBoundary,[switch]$DryRun)
    if($null -eq $AttemptDurationMinutes){$AttemptDurationMinutes=Get-MayaQaAttemptDurationMinutes}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$old=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$old -or !$attempt){throw 'Canonical Maya Tara execution and attempt are required.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Canonical retry identity invalid: '+(@($resolved.Errors)-join '; '))}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','HandoffId','AttemptId','RunId'){if([string]$old.$n -cne [string]$resolved.('Selected'+$n)){throw "Retry identity mismatch: $n"}}
    if($old.TestId -cne $resolved.SelectedQaWorkflowId -or $attempt.AttemptId -cne $old.AttemptId -or $attempt.RunId -cne $old.RunId){throw 'Retry current attempt identity mismatch.'}
    if($old.Stage -cne 'launch-failed' -or $old.ExecutionStatus -cne 'LaunchFailed' -or $old.FailureCode -cne 'native-process-start-failed'){throw 'Execution is not an eligible terminal launch failure.'}
    foreach($n in 'NativeProcessId','LaunchedUtc','ExecutingUtc','ResultPath','ReportPath','ReceiptPath'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw "Launch-failure retry contains prohibited evidence: $n"}}
    if($old.SideEffectsPerformed){throw 'Launch-failure retry has side effects and requires reconciliation.'}
    $qa=[IO.Path]::GetFullPath((Get-MayaQaRoot));$fixtures=[IO.Path]::GetFullPath((Join-Path $qa 'Fixtures'));$source=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);$fixturePrefix=$fixtures.TrimEnd('\')+'\';if(!$source.StartsWith($fixturePrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Authoritative fixture escaped approved fixture root.'};if(!(Test-Path -LiteralPath $source -PathType Leaf) -or (Get-FileHash $source -Algorithm SHA256).Hash -ine $old.AuthoritativeFixtureSha256){throw 'Authoritative fixture hash mismatch.'}
    foreach($pair in @(@('ArtifactPath','ArtifactSha256'),@('IsolationPolicyPath','IsolationPolicySha256'))){$p=[string]$old.($pair[0]);$h=[string]$old.($pair[1]);if(!$p -or !$h -or !(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash $p -Algorithm SHA256).Hash -ine $h){throw "Canonical $($pair[0]) hash validation failed."}}
    $manifestValidation=if($ManifestValidationBoundary){& $ManifestValidationBoundary $old.RunnerManifestPath $old.RunnerManifestSha256}else{try{$item=Get-Item -LiteralPath $old.RunnerManifestPath -ErrorAction Stop;if(!$item.PSIsContainer){[pscustomobject]@{Accessible=$true;HashMatches=((Get-FileHash -LiteralPath $old.RunnerManifestPath -Algorithm SHA256).Hash -ieq [string]$old.RunnerManifestSha256)}}else{[pscustomobject]@{Accessible=$false;HashMatches=$false}}}catch [System.UnauthorizedAccessException]{[pscustomobject]@{Accessible=$false;HashMatches=$false}}catch{throw 'Canonical RunnerManifestPath is missing.'}}
    if($manifestValidation.Accessible){if(!$manifestValidation.HashMatches){throw 'Canonical RunnerManifestPath hash validation failed.'}}else{ $evidencePath=[string]$old.EvidencePath;$evidenceHash=[string]$old.EvidenceSha256;if([string]::IsNullOrWhiteSpace($evidencePath) -or [string]::IsNullOrWhiteSpace($evidenceHash) -or !(Test-Path -LiteralPath $evidencePath -PathType Leaf)){throw 'Canonical prepared manifest evidence is missing.'};if((Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash -ine $evidenceHash){throw 'Canonical prepared manifest evidence hash mismatch.'};try{$ev=Get-Content -LiteralPath $evidencePath -Raw|ConvertFrom-Json}catch{throw 'Canonical prepared manifest evidence is malformed.'};foreach($n in 'EvidenceVersion','EvidencePurpose','ValidationStatus','TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','CanonicalRunId','DeployedRunnerManifestPath','DeployedRunnerManifestSha256','IsolationPolicySha256','ValidatedUtc'){if($ev.PSObject.Properties.Name -notcontains $n){throw "Canonical prepared manifest evidence is missing: $n"}};foreach($n in 'ClaimId','NativeRunId'){if($ev.PSObject.Properties.Name -contains $n -and -not [string]::IsNullOrWhiteSpace([string]$ev.$n)){throw "Canonical prepared manifest evidence contains prohibited field: $n"}};if([int]$ev.EvidenceVersion -ne 1 -or [string]$ev.EvidencePurpose -cne 'PreparedManifestAttestation' -or [string]$ev.ValidationStatus -cne 'Passed'){throw 'Canonical prepared manifest evidence did not pass validation.'};foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId'){if([string]$ev.$n -cne [string]$old.$n){throw "Canonical prepared manifest evidence identity mismatch: $n"}};if([string]$ev.CanonicalRunId -cne [string]$old.RunId -or [string]$ev.DeployedRunnerManifestPath -cne [string]$old.RunnerManifestPath -or [string]$ev.DeployedRunnerManifestSha256 -ine [string]$old.RunnerManifestSha256 -or [string]$ev.IsolationPolicySha256 -ine [string]$old.IsolationPolicySha256){throw 'Canonical prepared manifest evidence identity or hash mismatch.'};try{$null=[DateTimeOffset]::Parse([string]$ev.ValidatedUtc)}catch{throw 'Canonical prepared manifest evidence timestamp is invalid.'}}
    if(!$old.IsolationAllowed){throw 'Canonical isolation policy is not allowed.'}
    if($task.PSObject.Properties.Name -contains 'mayaTaraExecutionHistory' -and @($task.mayaTaraExecutionHistory|Where-Object{$_.AttemptId -ceq $old.AttemptId}).Count){throw 'Terminal launch failure was already archived.'}
    $runs=[IO.Path]::GetFullPath($(if($RuntimeRoot){$RuntimeRoot}else{Get-MayaQaRuntimeRoot}));$runPrefix=$runs.TrimEnd('\')+'\';$newAttempt=[guid]::NewGuid().ToString('N');$newRun=[guid]::NewGuid().ToString('N');$runtime=[IO.Path]::GetFullPath((Join-Path $runs ($newRun+'-retry')));if(!$runtime.StartsWith($runPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Retry runtime escaped approved runtime root.'};$model=Join-Path $runtime 'model.rvt';$sidecar=$model+'.fixture.json';$modelHash=$old.AuthoritativeFixtureSha256;$def=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId
    if(!$DryRun){New-Item -ItemType Directory -Path $runtime -Force|Out-Null;Copy-Item $source $model -Force;if((Get-FileHash $model -Algorithm SHA256).Hash -ine $modelHash){throw 'Retry disposable model hash mismatch.'};$side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$modelHash};if($resolved.SelectedQaWorkflowId -eq 'grid-bubble-visibility-v1' -or $resolved.SelectedQaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')};if($resolved.SelectedQaWorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')};$side|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $sidecar -Encoding UTF8;$check=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json;if(!(Test-Path -LiteralPath $model -PathType Leaf) -or !(Test-Path -LiteralPath $sidecar -PathType Leaf) -or $check.fixtureId -cne $def.FixtureId -or $check.sourceSha256 -ine $modelHash -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine $modelHash){throw 'Retry disposable model or fixture sidecar validation failed.'}}
    $expiry=[DateTimeOffset]::UtcNow.AddMinutes($AttemptDurationMinutes).ToString('O');$newAttemptRecord=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$newAttempt;TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;RunId=$newRun;RuntimeRoot=$runtime;RequestExpiresUtc=$expiry;Stage='prepared';Success=$false;RequestPath=$null}
    $newExec=[ordered]@{};foreach($p in $old.PSObject.Properties){$newExec[$p.Name]=$p.Value};$newExec.AttemptId=$newAttempt;$newExec.RunId=$newRun;$newExec.DisposableRuntimeRoot=$runtime;$newExec.DisposableModelPath=$model;$newExec.DisposableModelSha256=$modelHash;$newExec.ClaimId=$null;$newExec.ClaimOwner=$null;$newExec.ClaimedUtc=$null;$newExec.ClaimStatus='unclaimed';$newExec.Stage='prepared';$newExec.ExecutionStatus='Prepared';$newExec.PreparedUtc=Get-RepatoUtc;$newExec.LaunchingUtc=$null;$newExec.LaunchedUtc=$null;$newExec.ExecutingUtc=$null;$newExec.EvidenceCollectedUtc=$null;$newExec.RollbackVerifiedUtc=$null;$newExec.VerifiedUtc=$null;$newExec.CompletedUtc=$null;$newExec.FailedUtc=$null;$newExec.NativeProcessId=$null;$newExec.RequestPath=$null;$newExec.ResultPath=$null;$newExec.ReportPath=$null;$newExec.EvidencePath=$null;$newExec|Add-Member NoteProperty EvidenceSha256 $null -Force;$newExec.ReceiptPath=$null;$newExec.RollbackStatus='Required';$newExec.VerificationStatus='Pending';$newExec.CompletionStatus='Pending';$newExec.FailureCode=$null;$newExec.FailureDetails=$null;$newExec.TaskRevisionAtPrepare=$null;$newExec.TaskRevisionAtClaim=$null;$newExec.SideEffectsPerformed=$false
    $newExec.EvidenceSha256=$null;$newExec.NativeRequestId=$null
    if($DryRun){return [pscustomobject]@{Mode='DryRun';OldAttemptId=$old.AttemptId;OldRunId=$old.RunId;NewAttemptId=$newAttempt;NewRunId=$newRun;RuntimeRoot=$runtime;SideEffectsPerformed=$false}}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$now=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $now.AttemptId -cne $old.AttemptId -or $now.RunId -cne $old.RunId -or $now.Stage -cne 'launch-failed' -or $now.FailureCode -cne 'native-process-start-failed'){throw 'Terminal launch-failure retry compare-and-swap failed.'};if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};$archived=[pscustomobject]$now;$archived|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force;$archived|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;$archived|Add-Member NoteProperty ReplacementRunId $newRun -Force;$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$archived;if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$t.mayaTaraAttempt;$t.mayaTaraAttempt=$newAttemptRecord;$newExec.TaskRevisionAtPrepare=[long]$t.revision;$t.mayaTaraExecution=[pscustomobject]$newExec;Add-RepatoHistory $t 'maya-tara-terminal-launch-failure-recovered' 'Maya' "failedAttempt=$($old.AttemptId); failedRun=$($old.RunId); replacementAttempt=$newAttempt; replacementRun=$newRun";$t.mayaTaraExecution}
}

function Complete-MayaQaTerminalLaunchFailureCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$AttemptId,
        [Parameter(Mandatory)][string]$ClaimId,
        [scriptblock]$ProcessInspector,
        [switch]$DryRun
    )
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task){throw 'Cleanup task was not found.'};$execution=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$execution -or !$attempt){throw 'Canonical terminal execution and attempt are required.'}
    if($execution.TaskId -cne $TaskId -or $execution.AttemptId -cne $AttemptId -or $attempt.AttemptId -cne $AttemptId){throw 'Cleanup identity mismatch.'}
    if($execution.Stage -ceq 'rollback-verified' -and $execution.RollbackStatus -ceq 'Verified' -and $execution.ClaimStatus -ceq 'released'){
        if($execution.PSObject.Properties.Name -notcontains 'ReleasedClaimId' -or [string]$execution.ReleasedClaimId -cne $ClaimId){throw 'Cleanup idempotency claim identity mismatch.'}
        return [pscustomobject]@{Mode='AlreadyCompleted';TaskId=$TaskId;AttemptId=$AttemptId;ClaimId=$ClaimId;RollbackStatus='Verified';ClaimStatus='released';RequestEvidencePreserved=$true;ReplacementAttemptCreated=$false;SideEffectsPerformed=$false}
    }
    if($execution.ClaimId -cne $ClaimId -or $execution.ClaimOwner -ne 'Tara' -or $execution.ClaimStatus -cne 'claimed'){throw 'Cleanup claim identity mismatch.'}
    if($execution.Stage -cne 'launch-failed' -or $execution.ExecutionStatus -cne 'LaunchFailed' -or $execution.FailureCode -cne 'native-process-start-failed' -or $execution.RollbackStatus -cne 'Required'){throw 'Execution is not an eligible terminal launch failure.'}
    foreach($n in 'NativeProcessId','LaunchedUtc','ExecutingUtc','ResultPath','ReportPath','ReceiptPath','EvidencePath'){if($execution.PSObject.Properties.Name -contains $n -and $execution.$n){throw "Cleanup found prohibited terminal evidence: $n"}}
    if($execution.SideEffectsPerformed){throw 'Cleanup found recorded side effects.'}
    $live=if($ProcessInspector){& $ProcessInspector $execution}else{if($execution.NativeProcessId){try{Get-Process -Id ([int]$execution.NativeProcessId) -ErrorAction Stop}catch{$null}}else{$null}}
    if($live){throw 'Cleanup is fail-closed while an attempt process is live or ambiguous.'}
    $fixture=[IO.Path]::GetFullPath([string]$execution.AuthoritativeFixturePath);if(!(Test-Path -LiteralPath $fixture -PathType Leaf) -or (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash -ine [string]$execution.AuthoritativeFixtureSha256){throw 'Authoritative fixture integrity failed.'}
    $model=[string]$execution.DisposableModelPath;$runtime=[IO.Path]::GetFullPath([string]$execution.DisposableRuntimeRoot);if(!(Test-Path -LiteralPath $model -PathType Leaf) -or !(Test-Path -LiteralPath $runtime -PathType Container)){throw 'Disposable runtime is missing.'};if((Get-FileHash -LiteralPath $execution.AuthoritativeFixturePath -Algorithm SHA256).Hash -ine [string]$execution.AuthoritativeFixtureSha256 -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine [string]$execution.DisposableModelSha256){throw 'Authoritative source fixture or disposable model hash validation failed.'};if(!$execution.FixturePreparationEvidence -and [string]$execution.DisposableModelSha256 -ine [string]$execution.AuthoritativeFixtureSha256){throw 'Disposable model differs from source fixture without correlated preparation evidence.'};if($execution.FixturePreparationEvidence -and ([string]$execution.FixturePreparationEvidence.PreparedModelSha256 -ine [string]$execution.DisposableModelSha256 -or [string]$execution.FixturePreparationEvidence.SourceSha256 -ine [string]$execution.AuthoritativeFixtureSha256)){throw 'Disposable model or source fixture does not match correlated preparation evidence.'}
    $request=[string]$execution.RequestPath;if([string]::IsNullOrWhiteSpace($request) -or !(Test-Path -LiteralPath $request -PathType Leaf)){throw 'Request evidence cannot be safely preserved.'};$requestFull=[IO.Path]::GetFullPath($request);$runtimeFull=[IO.Path]::GetFullPath($runtime);if(!$requestFull.StartsWith($runtimeFull.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Request evidence is outside the disposable runtime contract.'}
    $archiveRoot=[IO.Path]::GetFullPath((Join-Path (Join-Path $StoreRoot 'archives') ('terminal-launch-failures\'+$TaskId+'\'+$AttemptId)));if(!$archiveRoot.StartsWith([IO.Path]::GetFullPath((Join-Path $StoreRoot 'archives')).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Cleanup archive escaped the approved store archive root.'}
    if($DryRun){return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;AttemptId=$AttemptId;ClaimId=$ClaimId;ArchiveRoot=$archiveRoot;RequestEvidencePreserved=$true;ReplacementAttemptCreated=$false;SideEffectsPerformed=$false}}
    if(Test-Path -LiteralPath $archiveRoot){throw 'Cleanup archive already exists; refusing duplicate destructive cleanup.'}
    New-Item -ItemType Directory -Path (Split-Path $archiveRoot -Parent) -Force|Out-Null;Move-Item -LiteralPath $runtime -Destination $archiveRoot
    $archivedRequest=Join-Path $archiveRoot (Split-Path $request -Leaf)
    $null=Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if([long]$t.revision -ne [long]$task.revision -or $x.AttemptId -cne $AttemptId -or $x.ClaimId -cne $ClaimId -or $x.Stage -cne 'launch-failed' -or $x.RollbackStatus -cne 'Required'){throw 'Cleanup compare-and-swap failed.'};$x|Add-Member NoteProperty OriginalDisposableRuntimeRoot $runtime -Force;$x|Add-Member NoteProperty ArchivedRuntimeRoot $archiveRoot -Force;$x|Add-Member NoteProperty ReleasedClaimId $ClaimId -Force;$x.RequestPath=$archivedRequest;$x.ClaimStatus='released';$x.ClaimOwner=$null;$x.ClaimId=$null;$x.Stage='rollback-verified';$x.ExecutionStatus='RollbackVerified';$x.RollbackStatus='Verified';$x.RollbackVerifiedUtc=Get-RepatoUtc;$x|Add-Member NoteProperty CleanupCompletedUtc (Get-RepatoUtc) -Force;$x.SideEffectsPerformed=$false;Add-RepatoHistory $t 'maya-tara-terminal-launch-failure-cleanup-completed' 'Maya' "attempt=$AttemptId; archivedRuntime=$archiveRoot";$x}
    [pscustomobject]@{Mode='Completed';TaskId=$TaskId;AttemptId=$AttemptId;ClaimId=$ClaimId;RollbackStatus='Verified';ClaimStatus='released';ArchiveRoot=$archiveRoot;RequestEvidencePath=$archivedRequest;RequestEvidencePreserved=$true;ReplacementAttemptCreated=$false;ReplacementRuntimeCreated=$false;SideEffectsPerformed=$false}
}

function Complete-MayaQaRunnerStartupFailureReconciliation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$AttemptId,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ClaimId,
        [Parameter(Mandatory)][string]$NativeRequestId,
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$ProcessStartedUtc,
        [Parameter(Mandatory)][string]$RequestPath,
        [Parameter(Mandatory)][string]$RequestSha256,
        [Parameter(Mandatory)][string]$JournalPath,
        [Parameter(Mandatory)][string]$JournalSha256,
        [Parameter(Mandatory)][string]$AgentLedgerPath,
        [Parameter(Mandatory)][string]$AgentPayloadHash,
        [Parameter(Mandatory)][string]$FailureDetails,
        [Parameter(Mandatory)][string]$ManualPromptEvidence,
        [switch]$ManualLoadOnceAcknowledged,
        [scriptblock]$ProcessInspector,
        [switch]$DryRun
    )
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$x=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$x -or !$attempt -or $task.taskId -cne $TaskId -or $x.TaskId -cne $TaskId -or $x.AttemptId -cne $AttemptId -or $attempt.AttemptId -cne $AttemptId -or $x.RunId -cne $RunId -or $attempt.RunId -cne $RunId -or $x.ClaimId -cne $ClaimId -or $x.NativeRequestId -cne $NativeRequestId){throw 'Runner-startup reconciliation identity mismatch.'}
    if($x.Stage -cne 'launch-failed' -or $x.ExecutionStatus -cne 'LaunchFailed' -or $x.FailureCode -cne 'native-process-start-failed'){throw 'Execution is not the expected client launch-failed record.'}
    foreach($n in 'NativeProcessId','LaunchedUtc','ExecutingUtc','ResultPath','ReportPath','ReceiptPath','EvidencePath','RunnerStartupEvidence'){if($x.PSObject.Properties.Name -contains $n -and $x.$n){throw "Runner-startup reconciliation found preexisting evidence: $n"}}
    if($x.SideEffectsPerformed){throw 'Runner-startup reconciliation found reported QA side effects.'}
    if(!$ManualLoadOnceAcknowledged -or [string]::IsNullOrWhiteSpace($ManualPromptEvidence)){throw 'Explicit manual Load Once evidence is required.'}
    try{$started=[DateTimeOffset]::Parse($ProcessStartedUtc)}catch{throw 'Observed Revit process start time is invalid.'}
    if($ProcessId -le 0 -or $ProcessId -ne 44920){throw 'Observed Revit PID does not match the authorized attempt evidence.'}
    $requestFull=[IO.Path]::GetFullPath($RequestPath);if($requestFull -ine [IO.Path]::GetFullPath([string]$x.RequestPath) -or !(Test-Path -LiteralPath $requestFull -PathType Leaf)){throw 'Request evidence path does not match the persisted operation.'}
    if((Get-FileHash -LiteralPath $requestFull -Algorithm SHA256).Hash -ine $RequestSha256){throw 'Request evidence hash mismatch.'}
    try{$request=Get-Content -LiteralPath $requestFull -Raw|ConvertFrom-Json}catch{throw 'Request evidence is malformed.'}
    foreach($pair in @(@('taskId',$TaskId),@('workflowId',[string]$x.WorkflowId),@('qaWorkflowId',[string]$x.QaWorkflowId),@('testId',[string]$x.TestId),@('attemptId',$AttemptId),@('runId',$RunId),@('claimId',$ClaimId),@('requestId',$NativeRequestId))){if([string]$request.($pair[0]) -cne [string]$pair[1]){throw "Request binding mismatch: $($pair[0])"}}
    if([IO.Path]::GetFullPath([string]$request.requestPath) -ine $requestFull -or [string]$request.requestSha256 -notmatch '^[a-fA-F0-9]{64}$' -or (Get-MayaQaCanonicalRequestSha256 $request) -ine [string]$request.requestSha256){throw 'Request path or embedded integrity binding is invalid.'}
    $resultPath=$requestFull+'.result.json';if(Test-Path -LiteralPath $resultPath){throw 'A request-bound result exists; startup-failure reconciliation is not eligible.'}
    $journalFull=[IO.Path]::GetFullPath($JournalPath);if(!(Test-Path -LiteralPath $journalFull -PathType Leaf) -or (Get-FileHash -LiteralPath $journalFull -Algorithm SHA256).Hash -ine $JournalSha256){throw 'Revit journal evidence is missing or has changed.'}
    $journal=Get-Content -LiteralPath $journalFull -Raw
    foreach($needle in @('API_ERROR { Starting External Application: Repato Create Plan Views QA','Repato.Revit.TestRunner.CreatePlanViewsQaApplication','TaskDialog "Revit cannot run the external application "Repato Create Plan Views QA"','TaskDialog_Security_Unsigned_File_Loading','AddInCodeSigningStatus: Unsigned','AddInLoadFailureMessage: NoError')){if(!$journal.Contains($needle)){throw "Journal does not prove expected startup evidence: $needle"}}
    try{$ledger=Get-Content -LiteralPath $AgentLedgerPath -Raw|ConvertFrom-Json}catch{throw 'Launch Agent replay ledger is missing or malformed.'}
    $ledgerMatches=@($ledger|Where-Object{$_.RequestId -ceq $NativeRequestId -and $_.RunId -ceq $RunId -and $_.PayloadHash -ceq $AgentPayloadHash})
    if($ledgerMatches.Count -ne 1 -or $AgentPayloadHash -notmatch '^[a-fA-F0-9]{64}$'){throw 'Launch Agent ledger does not conclusively bind the received request.'}
    $ledgerSeen=[DateTimeOffset]::Parse([string]$ledgerMatches[0].SeenUtc);if([Math]::Abs(($started-$ledgerSeen).TotalSeconds) -gt 10){throw 'Observed Revit start time is not bound closely to Launch Agent receipt time.'}
    $live=if($ProcessInspector){& $ProcessInspector $ProcessId $started}else{Get-Process -Id $ProcessId -ErrorAction SilentlyContinue};if($live){throw 'Observed Revit process is still live; reconciliation is fail-closed.'}
    $evidence=[pscustomobject][ordered]@{Disposition='Revit launched; runner startup failed; no QA result';TaskId=$TaskId;AttemptId=$AttemptId;RunId=$RunId;ClaimId=$ClaimId;NativeRequestId=$NativeRequestId;ProcessId=$ProcessId;ProcessStartedUtc=$started.ToUniversalTime().ToString('O');ProcessExitConfirmed=$true;RequestPath=$requestFull;RequestFileSha256=$RequestSha256;RequestEmbeddedSha256=$request.requestSha256;ResultPath=$resultPath;ResultAbsent=$true;ReportPath=$null;JournalPath=$journalFull;JournalSha256=$JournalSha256;AgentLedgerPath=[IO.Path]::GetFullPath($AgentLedgerPath);AgentPayloadHash=$AgentPayloadHash;AgentSeenUtc=$ledgerMatches[0].SeenUtc;ManualLoadOnceAcknowledged=$true;ManualPromptEvidence=$ManualPromptEvidence;RunnerFailureDetails=$FailureDetails;RecordedUtc=Get-RepatoUtc}
    if($DryRun){return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;AttemptId=$AttemptId;RunId=$RunId;RequestId=$NativeRequestId;Disposition=$evidence.Disposition;Evidence=$evidence;ReplacementAttemptCreated=$false;StoreRevision=$task.revision}}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$z=$t.mayaTaraExecution;if([long]$t.revision -ne [long]$task.revision -or $z.AttemptId -cne $AttemptId -or $z.RunId -cne $RunId -or $z.ClaimId -cne $ClaimId -or $z.NativeRequestId -cne $NativeRequestId -or $z.Stage -cne 'launch-failed' -or $z.FailureCode -cne 'native-process-start-failed'){throw 'Runner-startup reconciliation compare-and-swap failed.'};$z.NativeProcessId=$ProcessId;$z.LaunchedUtc=$evidence.ProcessStartedUtc;$z.Stage='runner-startup-failed';$z.ExecutionStatus='RunnerStartupFailed';$z.ClaimStatus='runner-startup-failed';$z.FailureCode='runner-startup-failed';$z.FailureDetails=$FailureDetails;$z.FailedUtc=Get-RepatoUtc;$z.ResultPath=$resultPath;$z.ReportPath=$null;$z.ReceiptPath=$null;$z|Add-Member NoteProperty RunnerStartupEvidence $evidence -Force;$t.mayaTaraAttempt.Stage='runner-startup-failed';$t.mayaTaraAttempt.Success=$false;Add-RepatoHistory $t 'maya-tara-runner-startup-failed' 'Tara' "attempt=$AttemptId; run=$RunId; request=$NativeRequestId; pid=$ProcessId; manualLoadOnce=true; resultAbsent=true";$z}
}

function Complete-MayaQaPreAttemptOrphanRuntimeCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$RunId,
        [switch]$DryRun
    )
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    $workflows=@($task.deploymentWorkflows|Where-Object{$_.taskId -ceq $TaskId -and $_.qaRunId -ceq $RunId})
    if($workflows.Count -ne 1){throw 'Pre-attempt cleanup RunId did not resolve to exactly one persisted QA workflow.'}
    $workflow=$workflows[0]
    $attempt=if($task.PSObject.Properties.Name -contains 'mayaTaraAttempt'){$task.mayaTaraAttempt}else{$null}
    $execution=if($task.PSObject.Properties.Name -contains 'mayaTaraExecution'){$task.mayaTaraExecution}else{$null}
    if($attempt -and (! [string]::IsNullOrWhiteSpace([string]$attempt.AttemptId) -or ($attempt.PSObject.Properties.Name -contains 'ClaimId' -and ![string]::IsNullOrWhiteSpace([string]$attempt.ClaimId)))){throw 'Pre-attempt cleanup requires no canonical AttemptId or ClaimId.'}
    if($execution){throw 'Pre-attempt cleanup requires no canonical Maya Tara execution.'}
    if($task.PSObject.Properties.Name -contains 'mayaTaraQaPacket' -and $task.mayaTaraQaPacket){throw 'Pre-attempt cleanup requires no QA handoff.'}
    foreach($item in @($task.executorRuns)){
        if($item -and (($item.PSObject.Properties.Name -contains 'RunId' -and [string]$item.RunId -ceq $RunId) -or ($item.PSObject.Properties.Name -contains 'RequestPath' -and $item.RequestPath))){throw 'Pre-attempt cleanup found native execution evidence.'}
    }
    foreach($p in 'qaReportPath','qaReceiptPath','qaEvidencePath','qaResultPath'){
        if($workflow.PSObject.Properties.Name -contains $p -and ![string]::IsNullOrWhiteSpace([string]$workflow.$p)){throw "Pre-attempt cleanup found native evidence: $p."}
    }
    $model=[IO.Path]::GetFullPath([string]$workflow.qaModelPath);$sidecar=[IO.Path]::GetFullPath([string]$workflow.qaSidecarPath)
    $runtime=[IO.Path]::GetFullPath((Split-Path $model -Parent));$canonical=[IO.Path]::GetFullPath((Get-MayaQaRuntimeRoot));$prefix=$canonical.TrimEnd('\')+'\'
    if(!$runtime.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $runtime -ieq $canonical){throw 'Persisted disposable runtime is outside the canonical QA TestRuns root.'}
    if([IO.Path]::GetDirectoryName($sidecar) -ine $runtime -or [IO.Path]::GetFileName($model) -cne 'model.rvt' -or [IO.Path]::GetFileName($sidecar) -cne 'model.rvt.fixture.json'){throw 'Persisted model or sidecar escapes the exact disposable runtime.'}
    $fixture=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) 'Fixtures'));$candidate=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) '..\DeploymentCandidates'));$source=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) '..'))
    foreach($p in @($model,$sidecar,$runtime)){if($p -ieq $fixture -or $p.StartsWith($fixture.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($candidate.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $p -ieq $source){throw 'Pre-attempt cleanup target overlaps fixture, candidate, or source data.'}}
    $auditName='PreAttemptRuntimeCleanupStatus';$existingStatus=if($task.PSObject.Properties.Name -contains $auditName){[string]$task.$auditName}else{$null}
    if($existingStatus -ceq 'Completed' -and !(Test-Path -LiteralPath $runtime)){return [pscustomobject]@{Mode='AlreadyCleaned';TaskId=$TaskId;RunId=$RunId;RuntimePath=$runtime;SideEffectsPerformed=$false}}
    if($DryRun){return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;RunId=$RunId;RuntimePath=$runtime;RuntimeExists=(Test-Path -LiteralPath $runtime -PathType Container);SideEffectsPerformed=$false}}
    $revision=[long]$task.revision
    $pending=Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;if([long]$t.revision -ne $revision){throw 'Pre-attempt cleanup compare-and-swap failed.'};if($t.PSObject.Properties.Name -contains 'PreAttemptRuntimeCleanupStatus' -and $t.PreAttemptRuntimeCleanupStatus -ceq 'Completed'){return $t};$t|Add-Member NoteProperty PreAttemptRuntimeCleanupStatus 'Pending' -Force;$t|Add-Member NoteProperty PreAttemptRuntimeCleanupUtc (Get-RepatoUtc) -Force;$t|Add-Member NoteProperty CleanedRunId $RunId -Force;$t|Add-Member NoteProperty CleanedRuntimePath $runtime -Force;Add-RepatoHistory $t 'maya-qa-pre-attempt-runtime-cleanup-started' 'Maya' "run=$RunId; runtime=$runtime";$t}
    if(Test-Path -LiteralPath $runtime){Remove-Item -LiteralPath $runtime -Recurse -Force}
    if(Test-Path -LiteralPath $runtime){throw 'Pre-attempt disposable runtime could not be removed.'}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;if([string]$t.PreAttemptRuntimeCleanupStatus -cne 'Pending' -or [string]$t.CleanedRunId -cne $RunId -or [string]$t.CleanedRuntimePath -ine $runtime){throw 'Pre-attempt cleanup completion compare-and-swap failed.'};$t.PreAttemptRuntimeCleanupStatus='Completed';$t.PreAttemptRuntimeCleanupUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-qa-pre-attempt-runtime-cleanup-completed' 'Maya' "run=$RunId; runtime=$runtime";$t}|Out-Null
    [pscustomobject]@{Mode='Completed';TaskId=$TaskId;RunId=$RunId;RuntimePath=$runtime;RuntimeRemoved=$true;SideEffectsPerformed=$false}
}

function Complete-MayaQaPreparedAttemptCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$AttemptId,[switch]$DryRun)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if($task.PSObject.Properties.Name -contains 'PreAttemptCleanup' -and [string]$task.PreAttemptCleanup.Status -ceq 'Completed'){$oldPath=[string]$task.PreAttemptCleanup.RuntimePath;if(!(Test-Path -LiteralPath $oldPath)){return [pscustomobject]@{Mode='AlreadyCompleted';TaskId=$TaskId;WorkflowId=$WorkflowId;RunId=$RunId;AttemptId=$AttemptId;RuntimePath=$oldPath;ReplacementAttemptCreated=$false;SideEffectsPerformed=$false}};throw 'Prepared-attempt cleanup is already completed but its runtime still exists.'}
    if($task.PSObject.Properties.Name -notcontains 'mayaTaraAttempt' -or !$task.mayaTaraAttempt){throw 'Prepared-attempt cleanup requires one current canonical attempt.'};$attempt=$task.mayaTaraAttempt
    foreach($n in 'TaskId','WorkflowId','RunId','AttemptId'){if($attempt.PSObject.Properties.Name -notcontains $n -or [string]$attempt.$n -cne [string]$(if($n -eq 'TaskId'){$TaskId}elseif($n -eq 'WorkflowId'){$WorkflowId}elseif($n -eq 'RunId'){$RunId}else{$AttemptId})){throw "Prepared-attempt cleanup identity mismatch: $n"}}
    $attemptHistory=if($task.PSObject.Properties.Name -contains 'mayaTaraAttemptHistory'){@($task.mayaTaraAttemptHistory)}else{@()};$attempts=@($attemptHistory|Where-Object{$_.AttemptId -ceq $AttemptId});if($attempts.Count){throw 'Prepared-attempt cleanup found ambiguous historical attempt evidence.'}
    if($task.PSObject.Properties.Name -contains 'mayaTaraExecution' -and $task.mayaTaraExecution){throw 'Prepared-attempt cleanup rejects an execution record.'}
    $packet=if($task.PSObject.Properties.Name -contains 'mayaTaraQaPacket'){$task.mayaTaraQaPacket}else{$null};if(!$packet){throw 'Prepared-attempt cleanup requires the prepared QA handoff.'}
    foreach($n in 'TaskId','WorkflowId','RunId','AttemptId'){if($packet.PSObject.Properties.Name -notcontains $n -or [string]$packet.$n -cne [string]$(if($n -eq 'TaskId'){$TaskId}elseif($n -eq 'WorkflowId'){$WorkflowId}elseif($n -eq 'RunId'){$RunId}else{$AttemptId})){throw "Prepared-attempt handoff identity mismatch: $n"}}
    foreach($obj in @($attempt,$packet)){$names=@($obj.PSObject.Properties.Name);foreach($n in 'ClaimId','NativeProcessId','RequestPath','ResultPath','ReportPath','ReceiptPath','LaunchAgentAccepted','NativeRequestSent','RevitLaunched','QaRunnerStarted'){if($names -contains $n -and $obj.$n){throw "Prepared-attempt cleanup found prohibited evidence: $n"}}}
    $runtime=[IO.Path]::GetFullPath([string]$attempt.RuntimeRoot);$canonical=[IO.Path]::GetFullPath((Get-MayaQaRuntimeRoot));$prefix=$canonical.TrimEnd('\')+'\';if(!$runtime.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $runtime -ieq $canonical){throw 'Prepared-attempt runtime escaped canonical QA TestRuns.'}
    $model=[IO.Path]::GetFullPath([string]$packet.ModelPath);$side=[IO.Path]::GetFullPath([string]$packet.SidecarPath);if([IO.Path]::GetDirectoryName($model) -ine $runtime -or [IO.Path]::GetDirectoryName($side) -ine $runtime -or [IO.Path]::GetFileName($model) -cne 'model.rvt' -or [IO.Path]::GetFileName($side) -cne 'model.rvt.fixture.json'){throw 'Prepared-attempt runtime ownership/path validation failed.'}
    $ownerMatches=@($data.tasks|Where-Object{$attemptProperty=$_.PSObject.Properties['mayaTaraAttempt'];$candidate=if($null -ne $attemptProperty){$attemptProperty.Value}else{$null};if($null -ne $candidate -and $candidate.PSObject.Properties.Name -contains 'RuntimeRoot' -and -not [string]::IsNullOrWhiteSpace([string]$candidate.RuntimeRoot) -and [IO.Path]::GetFullPath([string]$candidate.RuntimeRoot) -ieq $runtime){$true}else{$false}});if($ownerMatches.Count -ne 1 -or $ownerMatches[0].taskId -cne $TaskId){throw 'Prepared-attempt runtime ownership is ambiguous.'}
    $fixture=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) 'Fixtures'));$candidate=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) '..\DeploymentCandidates'));$source=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) '..'));$store=[IO.Path]::GetFullPath($StoreRoot);foreach($p in @($runtime,$model,$side)){if($p -ieq $store -or $p.StartsWith($store.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $p -ieq $fixture -or $p.StartsWith($fixture.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($candidate.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $p -ieq $source){throw 'Prepared-attempt cleanup target overlaps protected data.'}}
    $revision=[long]$task.revision;if($DryRun){return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;RunId=$RunId;AttemptId=$AttemptId;RuntimePath=$runtime;SideEffectsPerformed=$false}}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;if([long]$t.revision -ne $revision -or $t.mayaTaraAttempt.AttemptId -cne $AttemptId -or $t.mayaTaraAttempt.RunId -cne $RunId -or ($t.PSObject.Properties.Name -contains 'mayaTaraExecution' -and $t.mayaTaraExecution)){throw 'Prepared-attempt cleanup compare-and-swap failed.'};$t|Add-Member NoteProperty PreAttemptCleanup ([pscustomobject]@{Status='Pending';Mode='PreparedAttemptCleanup';TaskId=$TaskId;WorkflowId=$WorkflowId;RunId=$RunId;AttemptId=$AttemptId;RuntimePath=$runtime;StartedUtc=Get-RepatoUtc}) -Force;Add-RepatoHistory $t 'maya-qa-prepared-attempt-cleanup-started' 'Maya' "attempt=$AttemptId; runtime=$runtime";$t}|Out-Null
    if(Test-Path -LiteralPath $runtime){Remove-Item -LiteralPath $runtime -Recurse -Force};if(Test-Path -LiteralPath $runtime){throw 'Prepared-attempt runtime removal failed.'}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;if([string]$t.PreAttemptCleanup.Status -cne 'Pending' -or [string]$t.PreAttemptCleanup.AttemptId -cne $AttemptId -or [string]$t.PreAttemptCleanup.RuntimePath -ine $runtime){throw 'Prepared-attempt cleanup completion compare-and-swap failed.'};$archived=[pscustomobject]$t.mayaTaraAttempt;$archived|Add-Member NoteProperty Stage 'abandoned-preparation' -Force;$archived|Add-Member NoteProperty CleanupReason 'Preparation failed before execution record, claim, or native boundary.' -Force;$archived|Add-Member NoteProperty CleanupCompletedUtc (Get-RepatoUtc) -Force;if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$archived;$t.mayaTaraAttempt=$null;$t.PreAttemptCleanup.Status='Completed';$t.PreAttemptCleanup|Add-Member NoteProperty RuntimeRemoved $true -Force;$t.PreAttemptCleanup|Add-Member NoteProperty CompletedUtc (Get-RepatoUtc) -Force;Add-RepatoHistory $t 'maya-qa-prepared-attempt-cleanup-completed' 'Maya' "attempt=$AttemptId; runtime=$runtime";$t}|Out-Null
    [pscustomobject]@{Mode='Completed';TaskId=$TaskId;WorkflowId=$WorkflowId;RunId=$RunId;AttemptId=$AttemptId;RuntimePath=$runtime;RuntimeRemoved=$true;ReplacementAttemptCreated=$false;ClaimCreated=$false;NativeRequestSent=$false;RevitLaunched=$false;SideEffectsPerformed=$false}
}
function Archive-MayaQaUnlaunchedPreparedExecution {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$AttemptId,[Parameter(Mandatory)][string]$RunId,[scriptblock]$ProcessProvider,[switch]$DryRun)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    $attempt=$task.mayaTaraAttempt;$execution=$task.mayaTaraExecution
    if(!$attempt -or !$execution){throw 'Unlaunched prepared execution and attempt are required.'}
    foreach($pair in @(@('TaskId',$TaskId),@('WorkflowId',$WorkflowId),@('AttemptId',$AttemptId),@('RunId',$RunId))){if([string]$attempt.($pair[0]) -cne $pair[1] -or [string]$execution.($pair[0]) -cne $pair[1]){throw "Prepared execution archive identity mismatch: $($pair[0])."}}
    if($attempt.Stage -cne 'prepared' -or $execution.Stage -cne 'prepared' -or $execution.ExecutionStatus -cne 'Prepared' -or $execution.ClaimStatus -cne 'unclaimed'){throw 'Only an unclaimed prepared execution may be archived.'}
    foreach($n in 'ClaimOwner','ClaimId','ClaimedUtc','NativeProcessId','RequestPath','ResultPath','ReportPath','ReceiptPath','LaunchingUtc','LaunchedUtc','ExecutingUtc'){if($attempt.PSObject.Properties.Name -contains $n -and $attempt.$n -or $execution.PSObject.Properties.Name -contains $n -and $execution.$n){throw "Prepared execution archive found launch evidence: $n."}}
    $inheritedApproval=$execution.ManualLoadOnceEvidence
    if($inheritedApproval){$prior=@($task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq [string]$inheritedApproval.AttemptId -and $_.RunId -ceq [string]$inheritedApproval.RunId -and $_.ManualLoadOnceEvidence -and $_.ManualLoadOnceEvidence.NativeRequestId -ceq [string]$inheritedApproval.NativeRequestId});if([string]$inheritedApproval.AttemptId -ceq $AttemptId -or [string]$inheritedApproval.RunId -ceq $RunId -or [string]$inheritedApproval.ConfirmedBy -cne 'user' -or [string]$inheritedApproval.Action -cne 'Load Once' -or $prior.Count -ne 1){throw 'Prepared execution archive found approval not correlated to an archived prior attempt.'}}
    if($execution.SideEffectsPerformed -or $execution.VerificationStatus -ceq 'Verified' -or $execution.CompletionStatus -ceq 'Completed'){throw 'Prepared execution archive found side effects or terminal evidence.'}
    $revits=if($ProcessProvider){@(& $ProcessProvider)}else{@(Get-Process -Name Revit -ErrorAction SilentlyContinue)};if(@($revits).Count){throw 'Prepared execution archive is blocked while Revit is running.'}
    $runtime=[IO.Path]::GetFullPath([string]$execution.DisposableRuntimeRoot);$runs=[IO.Path]::GetFullPath((Get-MayaQaRuntimeRoot));$prefix=$runs.TrimEnd('\')+'\'
    if(!$runtime.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $runtime -ieq $runs){throw 'Prepared execution archive runtime is outside canonical QA TestRuns.'}
    $model=[IO.Path]::GetFullPath([string]$execution.DisposableModelPath);if([IO.Path]::GetDirectoryName($model) -ine $runtime -or !(Test-Path -LiteralPath $model -PathType Leaf) -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine [string]$execution.DisposableModelSha256){throw 'Prepared execution archive model identity/hash validation failed.'}
    if(-not [string]::IsNullOrWhiteSpace([string]$execution.RequestPath) -and (Test-Path -LiteralPath ([string]$execution.RequestPath))){throw 'Prepared execution archive found a native request.'}
    $revision=[long]$task.revision
    if($DryRun){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;AttemptId=$AttemptId;RunId=$RunId;RuntimePreserved=$true;NativeLaunchAbsent=$true;SideEffectsPerformed=$false}}
    Invoke-RepatoStoreMutation $StoreRoot {
        param($current,$preview)
        $t=Find-RepatoTask $current $TaskId
        if([long]$t.revision -ne $revision -or $t.mayaTaraAttempt.AttemptId -cne $AttemptId -or $t.mayaTaraExecution.AttemptId -cne $AttemptId -or $t.mayaTaraExecution.RunId -cne $RunId){throw 'Prepared execution archive compare-and-swap failed.'}
        $archivedAttempt=[pscustomobject]$t.mayaTaraAttempt;$archivedAttempt.Stage='abandoned-preparation';$archivedAttempt|Add-Member NoteProperty CleanupReason 'Superseded before claim/native launch so frozen-candidate and deployment gates can run.' -Force;$archivedAttempt|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force
        $archivedExecution=[pscustomobject]$t.mayaTaraExecution;$archivedExecution.Stage='abandoned-preparation';$archivedExecution.ExecutionStatus='PreparedAttemptSuperseded';$archivedExecution.FailureCode='prepared-candidate-superseded';$archivedExecution.FailureDetails='Unlaunched preparation archived before required candidate/deployment validation.';$archivedExecution|Add-Member NoteProperty RuntimePreserved $true -Force;$archivedExecution|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force;if($inheritedApproval){$archivedExecution|Add-Member NoteProperty InheritedApprovalNotApplicableToPreparedAttempt $true -Force}
        if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$archivedAttempt
        if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$archivedExecution
        foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){$t.PSObject.Properties.Remove($n)}
        $w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($w.Count -ne 1){throw 'Prepared execution archive workflow identity is ambiguous.'}
        foreach($n in 'qaHandoffId','qaHandoff','qaRunId','qaModelPath','qaSidecarPath','qaFixtureId','qaFixtureSha256','qaTestId','qaReportPath','qaReportSha256','qaEvidence','qaVerificationStatus','qaCompletionStatus','qaCompletedUtc'){$w[0].PSObject.Properties.Remove($n)}
        Add-RepatoHistory $t 'maya-tara-unlaunched-preparation-archived' 'Maya' "attempt=$AttemptId; run=$RunId; runtimePreserved=true; nativeLaunch=false"
        [pscustomobject]@{Status='Archived';TaskId=$TaskId;WorkflowId=$WorkflowId;AttemptId=$AttemptId;RunId=$RunId;RuntimePreserved=$true;NativeLaunchAbsent=$true;SideEffectsPerformed=$true}
    }
}
function Accept-MayaQaPreparedManifestAttestation {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$AttemptId,[Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$EvidencePath,[Parameter(Mandatory)][string]$EvidenceSha256,[scriptblock]$StoreMutationBoundary)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$execution=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$task -or !$execution -or !$attempt){throw 'Canonical terminal execution and attempt are required.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Canonical attestation identity invalid: '+(@($resolved.Errors)-join '; '))}
    if($execution.TaskId -cne $TaskId -or $execution.AttemptId -cne $AttemptId -or $execution.RunId -cne $RunId -or $attempt.AttemptId -cne $AttemptId -or $attempt.RunId -cne $RunId){throw 'Attestation canonical identity mismatch.'}
    if($execution.Stage -cne 'launch-failed' -or $execution.ExecutionStatus -cne 'LaunchFailed' -or $execution.FailureCode -cne 'native-process-start-failed'){throw 'Execution is not eligible for prepared manifest attestation.'}
    if($execution.SideEffectsPerformed){throw 'Terminal execution has side effects.'};foreach($n in 'NativeProcessId','ResultPath','ReportPath','ReceiptPath','EvidencePath','EvidenceSha256'){if($execution.PSObject.Properties.Name -contains $n -and $execution.$n){throw "Terminal execution already contains $n."}}
    if(!$execution.IsolationAllowed){throw 'Isolation is not allowed.'};if(!(Test-Path -LiteralPath $EvidencePath -PathType Leaf)){throw 'Prepared manifest evidence is missing.'};if((Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash -ine $EvidenceSha256){throw 'Prepared manifest evidence hash mismatch.'};try{$e=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json}catch{throw 'Prepared manifest evidence is malformed.'}
    foreach($n in 'EvidenceVersion','EvidencePurpose','ValidationStatus','TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','CanonicalRunId','DeployedRunnerManifestPath','DeployedRunnerManifestSha256','IsolationPolicySha256','ValidatedUtc'){if($e.PSObject.Properties.Name -notcontains $n){throw "Prepared manifest evidence is missing: $n"}};foreach($n in 'ClaimId','NativeRunId'){if($e.PSObject.Properties.Name -contains $n -and -not [string]::IsNullOrWhiteSpace([string]$e.$n)){throw "Prepared manifest evidence contains prohibited field: $n"}}
    if([int]$e.EvidenceVersion -ne 1 -or [string]$e.EvidencePurpose -cne 'PreparedManifestAttestation' -or [string]$e.ValidationStatus -cne 'Passed'){throw 'Prepared manifest evidence did not pass validation.'};foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId'){if([string]$e.$n -cne [string]$execution.$n){throw "Prepared manifest evidence identity mismatch: $n"}};if([string]$e.CanonicalRunId -cne [string]$execution.RunId -or [string]$e.DeployedRunnerManifestPath -cne [string]$execution.RunnerManifestPath -or [string]$e.DeployedRunnerManifestSha256 -ine [string]$execution.RunnerManifestSha256 -or [string]$e.IsolationPolicySha256 -ine [string]$execution.IsolationPolicySha256){throw 'Prepared manifest evidence identity or hash mismatch.'};try{$null=[DateTimeOffset]::Parse([string]$e.ValidatedUtc)}catch{throw 'Prepared manifest evidence timestamp is invalid.'}
    $cas={param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $x.TaskId -cne $execution.TaskId -or $x.AttemptId -cne $AttemptId -or $x.RunId -cne $RunId -or $x.Stage -cne 'launch-failed' -or $x.ExecutionStatus -cne 'LaunchFailed' -or $x.FailureCode -cne 'native-process-start-failed' -or $x.SideEffectsPerformed -or $x.NativeProcessId -or $x.ResultPath -or $x.ReportPath -or $x.ReceiptPath -or $x.EvidencePath -or $x.EvidenceSha256){throw 'Prepared manifest attestation compare-and-swap failed.'};$x|Add-Member NoteProperty EvidencePath $EvidencePath -Force;$x|Add-Member NoteProperty EvidenceSha256 $EvidenceSha256 -Force;Add-RepatoHistory $t 'maya-tara-prepared-manifest-attestation-accepted' 'Tara' "attempt=$AttemptId; run=$RunId";$x}
    if($StoreMutationBoundary){& $StoreMutationBoundary $StoreRoot $cas}else{Invoke-RepatoStoreMutation $StoreRoot $cas}
}
function Recover-MayaQaAbandonedNativeExecution {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[string]$RuntimeRoot,[ValidateRange(1,1440)][Nullable[int]]$AttemptDurationMinutes,[switch]$DryRun)
    if($null -eq $AttemptDurationMinutes){$AttemptDurationMinutes=Get-MayaQaAttemptDurationMinutes}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$old=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$old -or !$attempt){throw 'Canonical Maya Tara execution and attempt are required.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Canonical abandoned-execution identity invalid: '+(@($resolved.Errors)-join '; '))}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','HandoffId','AttemptId','RunId'){if([string]$old.$n -cne [string]$resolved.('Selected'+$n)){throw "Abandoned-execution identity mismatch: $n"}}
    if($old.Stage -cne 'executing' -or $old.ExecutionStatus -cne 'Executing' -or $old.ClaimOwner -cne 'Tara' -or [string]::IsNullOrWhiteSpace([string]$old.ClaimId)){throw 'Execution is not an eligible executing Tara claim.'}
    if(!$old.NativeProcessId -or [int]$old.NativeProcessId -le 0){throw 'Executing record has no native process identity.'}
    try{$live=Get-Process -Id ([int]$old.NativeProcessId) -ErrorAction Stop}catch{$live=$null}
    if($live){throw "Recorded native PID $($old.NativeProcessId) is still present; recovery is fail-closed for live, reused, or ambiguous processes."}
    if([DateTimeOffset]::Parse($attempt.RequestExpiresUtc) -gt [DateTimeOffset]::UtcNow){throw 'Executing attempt is not expired.'}
    foreach($n in 'ResultPath','ReportPath','EvidencePath','ReceiptPath','CompletedUtc','VerifiedUtc','RollbackVerifiedUtc'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw "Abandoned execution contains prohibited terminal evidence: $n"}}
    if($old.VerificationStatus -eq 'Verified' -or $old.CompletionStatus -eq 'Completed' -or $old.SideEffectsPerformed){throw 'Abandoned execution has terminal or side-effect evidence and requires reconciliation.'}
    if($task.PSObject.Properties.Name -contains 'mayaTaraExecutionHistory' -and @($task.mayaTaraExecutionHistory|Where-Object{$_.AttemptId -ceq $old.AttemptId}).Count){throw 'Abandoned execution was already archived.'}
    $qa=[IO.Path]::GetFullPath((Get-MayaQaRoot));$source=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);$fixtures=[IO.Path]::GetFullPath((Join-Path $qa 'Fixtures'));$prefix=$fixtures.TrimEnd('\')+'\';if(!$source.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $source -PathType Leaf)){throw 'Authoritative fixture is outside the approved fixture root or missing.'};$sourceHash=(Get-FileHash $source -Algorithm SHA256).Hash;if($sourceHash -ine $old.AuthoritativeFixtureSha256){throw 'Authoritative fixture hash mismatch.'}
    $runs=[IO.Path]::GetFullPath($(if($RuntimeRoot){$RuntimeRoot}else{Get-MayaQaRuntimeRoot}));$runPrefix=$runs.TrimEnd('\')+'\';$newAttempt=[guid]::NewGuid().ToString('N');$newRun=[guid]::NewGuid().ToString('N');$runtime=[IO.Path]::GetFullPath((Join-Path $runs ($newRun+'-recovery')));if(!$runtime.StartsWith($runPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Recovery runtime escaped approved QA root.'};$model=Join-Path $runtime 'model.rvt';
    $sidecar=$model+'.fixture.json';$def=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId
    if(!$DryRun){New-Item -ItemType Directory -Path $runtime -Force|Out-Null;Copy-Item $source $model -Force;if((Get-FileHash $model -Algorithm SHA256).Hash -ine $sourceHash){throw 'Recovered disposable model hash mismatch.'};$side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$sourceHash};if($resolved.SelectedQaWorkflowId -eq 'grid-bubble-visibility-v1' -or $resolved.SelectedQaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')};if($resolved.SelectedQaWorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')};$side|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $sidecar -Encoding UTF8;$check=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json;if(!(Test-Path -LiteralPath $model -PathType Leaf) -or !(Test-Path -LiteralPath $sidecar -PathType Leaf) -or $check.fixtureId -cne $def.FixtureId -or $check.sourceSha256 -ine $sourceHash -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine $sourceHash){throw 'Recovered disposable model or fixture sidecar validation failed.'}}
    $expiry=[DateTimeOffset]::UtcNow.AddMinutes($AttemptDurationMinutes).ToString('O');$newAttemptRecord=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$newAttempt;TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;RunId=$newRun;RuntimeRoot=$runtime;RequestExpiresUtc=$expiry;Stage='prepared';Success=$false;RequestPath=$null};$newExec=[ordered]@{};foreach($p in $old.PSObject.Properties){$newExec[$p.Name]=$p.Value};$newExec.AttemptId=$newAttempt;$newExec.RunId=$newRun;$newExec.DisposableRuntimeRoot=$runtime;$newExec.DisposableModelPath=$model;$newExec.DisposableModelSha256=$sourceHash;$newExec.PreparedUtc=Get-RepatoUtc;$newExec.LaunchingUtc=$null;$newExec.LaunchedUtc=$null;$newExec.ExecutingUtc=$null;$newExec.EvidenceCollectedUtc=$null;$newExec.RollbackStartedUtc=$null;$newExec.RollbackVerifiedUtc=$null;$newExec.VerifiedUtc=$null;$newExec.CompletedUtc=$null;$newExec.FailedUtc=$null;$newExec.ClaimId=$null;$newExec.ClaimOwner=$null;$newExec.ClaimedUtc=$null;$newExec.ClaimStatus='unclaimed';$newExec.Stage='prepared';$newExec.ExecutionStatus='Prepared';$newExec.NativeProcessId=$null;$newExec.RequestPath=$null;$newExec.ResultPath=$null;$newExec.ReportPath=$null;$newExec.EvidencePath=$null;$newExec.ReceiptPath=$null;$newExec.RollbackStatus='Required';$newExec.VerificationStatus='Pending';$newExec.CompletionStatus='Pending';$newExec.FailureCode=$null;$newExec.FailureDetails=$null;$newExec.SideEffectsPerformed=$false;$newExec.TaskRevisionAtPrepare=$null;$newExec.TaskRevisionAtClaim=$null
    if($DryRun){return [pscustomobject]@{Mode='DryRun';OldAttemptId=$old.AttemptId;OldRunId=$old.RunId;NewAttemptId=$newAttempt;NewRunId=$newRun;RuntimeRoot=$runtime;SideEffectsPerformed=$false}}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $x.AttemptId -cne $old.AttemptId -or $x.RunId -cne $old.RunId -or $x.Stage -cne 'executing' -or $x.NativeProcessId -ne $old.NativeProcessId){throw 'Abandoned-execution recovery compare-and-swap failed.'};$archived=[pscustomobject]$x;$archived|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force;$archived|Add-Member NoteProperty Stage 'abandoned' -Force;$archived|Add-Member NoteProperty ExecutionStatus 'Abandoned' -Force;$archived|Add-Member NoteProperty ClaimStatus 'abandoned' -Force;$archived|Add-Member NoteProperty FailureCode 'native-process-exited-before-result' -Force;$archived|Add-Member NoteProperty FailureDetails 'Recorded native process disappeared before correlated native result or evidence was produced.' -Force;$archived|Add-Member NoteProperty AbandonedUtc (Get-RepatoUtc) -Force;$archived|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;$archived|Add-Member NoteProperty ReplacementRunId $newRun -Force;if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$archived;if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$t.mayaTaraAttempt;$t.mayaTaraAttempt=$newAttemptRecord;$newExec.TaskRevisionAtPrepare=[long]$t.revision;$t.mayaTaraExecution=[pscustomobject]$newExec;Add-RepatoHistory $t 'maya-tara-abandoned-native-recovered' 'Maya' "abandonedAttempt=$($old.AttemptId); abandonedRun=$($old.RunId); replacementAttempt=$newAttempt; replacementRun=$newRun";$t.mayaTaraExecution}
}
function Repair-MayaQaPreparedExecutionLifecycle {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$AttemptId,[Parameter(Mandatory)][string]$RunId,[string]$EvidencePath,[string]$EvidenceSha256,[scriptblock]$ManifestValidationBoundary,[scriptblock]$StoreMutationBoundary)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$x=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$x -or !$attempt){throw 'Canonical Maya Tara execution and attempt are required.'}
    if($x.TaskId -cne $TaskId -or $x.AttemptId -cne $AttemptId -or $x.RunId -cne $RunId -or $attempt.AttemptId -cne $AttemptId -or $attempt.RunId -cne $RunId){throw 'Prepared lifecycle repair identity mismatch.'}
    foreach($pair in @(@('Stage','prepared'),@('ExecutionStatus','Prepared'),@('ClaimStatus','unclaimed'))){if([string]$x.($pair[0]) -cne $pair[1]){throw 'Prepared lifecycle repair requires an unclaimed prepared execution.'}}
    foreach($n in 'ClaimOwner','ClaimId','ClaimedUtc','NativeProcessId','RequestPath','ResultPath','ReportPath','EvidencePath','ReceiptPath'){if($x.PSObject.Properties.Name -contains $n -and $null -ne $x.$n -and [string]$x.$n){throw "Prepared lifecycle repair found prohibited state: $n"}}
    foreach($n in 'CompletedUtc','VerifiedUtc','RollbackVerifiedUtc'){if($x.PSObject.Properties.Name -contains $n -and $x.$n){throw "Prepared lifecycle repair found terminal state: $n"}}
    if($x.SideEffectsPerformed -or $x.VerificationStatus -eq 'Verified' -or $x.CompletionStatus -eq 'Completed'){throw 'Prepared lifecycle repair found side effects or terminal status.'}
    if($x.PSObject.Properties.Name -contains 'LifecycleRepairUtc' -and $x.LifecycleRepairUtc){throw 'Prepared lifecycle repair was already performed.'}
    if($x.PSObject.Properties.Name -contains 'LaunchingUtc' -and $null -eq $x.LaunchingUtc -and $x.PreparedUtc -and [long]$task.revision -eq ([long]$x.TaskRevisionAtPrepare+1) -and [string]::IsNullOrWhiteSpace([string]$x.EvidenceSha256)){throw 'Prepared lifecycle repair was already performed or state is already clean.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Prepared lifecycle repair identity invalid: '+(@($resolved.Errors)-join '; '))}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','HandoffId','AttemptId','RunId'){if([string]$x.$n -cne [string]$resolved.('Selected'+$n)){throw "Prepared lifecycle repair canonical identity mismatch: $n"}}
    foreach($pair in @(@('ArtifactPath','ArtifactSha256'),@('AuthoritativeFixturePath','AuthoritativeFixtureSha256'),@('DisposableModelPath','DisposableModelSha256'),@('IsolationPolicyPath','IsolationPolicySha256'))){$p=[string]$x.($pair[0]);$h=[string]$x.($pair[1]);if(!$p -or !$h -or !(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash $p -Algorithm SHA256).Hash -ine $h){throw "Prepared lifecycle repair hash validation failed: $($pair[0])"}}
    $manifestValidation=if($ManifestValidationBoundary){& $ManifestValidationBoundary $x.RunnerManifestPath $x.RunnerManifestSha256}else{$accessible=Test-Path -LiteralPath $x.RunnerManifestPath -PathType Leaf;if($accessible){[pscustomobject]@{Accessible=$true;HashMatches=((Get-FileHash -LiteralPath $x.RunnerManifestPath -Algorithm SHA256).Hash -ieq [string]$x.RunnerManifestSha256)}}else{[pscustomobject]@{Accessible=$false;HashMatches=$false}}}
    if($manifestValidation.Accessible){if(!$manifestValidation.HashMatches){throw 'Prepared lifecycle repair hash validation failed: RunnerManifestPath'}}else{if([string]::IsNullOrWhiteSpace($EvidencePath) -or [string]::IsNullOrWhiteSpace($EvidenceSha256)){throw 'Prepared lifecycle repair requires authenticated manifest evidence.'};if(!(Test-Path -LiteralPath $EvidencePath -PathType Leaf) -or (Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash -ine $EvidenceSha256){throw 'Prepared lifecycle repair evidence hash validation failed.'};try{$ev=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json}catch{throw 'Prepared lifecycle repair evidence is malformed.'};$preparedPurpose=($ev.PSObject.Properties.Name -contains 'EvidencePurpose' -and [string]$ev.EvidencePurpose -ceq 'PreparedManifestAttestation');if($preparedPurpose){$required=@('EvidenceVersion','EvidencePurpose','ValidationStatus','TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','CanonicalRunId','DeployedRunnerManifestPath','DeployedRunnerManifestSha256','IsolationPolicySha256','ValidatedUtc');foreach($n in $required){if($ev.PSObject.Properties.Name -notcontains $n){throw "Prepared lifecycle repair evidence is missing: $n"}};foreach($n in 'ClaimId','NativeRunId'){if($ev.PSObject.Properties.Name -contains $n -and -not [string]::IsNullOrWhiteSpace([string]$ev.$n)){throw "Prepared lifecycle repair prepared evidence contains prohibited field: $n"}}}else{$required=@('EvidenceVersion','ValidationStatus','TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','CanonicalRunId','ClaimId','NativeRunId','DeployedRunnerManifestPath','DeployedRunnerManifestSha256','IsolationPolicySha256','ValidatedUtc');foreach($n in $required){if($ev.PSObject.Properties.Name -notcontains $n){throw "Prepared lifecycle repair evidence is missing: $n"}}};if([int]$ev.EvidenceVersion -ne 1 -or [string]$ev.ValidationStatus -cne 'Passed'){throw 'Prepared lifecycle repair evidence did not pass validation.'};foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId'){if([string]$ev.$n -cne [string]$x.$n){throw "Prepared lifecycle repair evidence identity mismatch: $n"}};if(!$preparedPurpose -and -not [string]::IsNullOrWhiteSpace([string]$ev.ClaimId)){throw 'Prepared lifecycle repair evidence contains a fabricated claim identity.'};if([string]$ev.CanonicalRunId -cne [string]$x.RunId -or [string]$ev.DeployedRunnerManifestPath -cne [string]$x.RunnerManifestPath -or [string]$ev.DeployedRunnerManifestSha256 -ine [string]$x.RunnerManifestSha256 -or [string]$ev.IsolationPolicySha256 -ine [string]$x.IsolationPolicySha256){throw 'Prepared lifecycle repair evidence identity or hash mismatch.'};try{$null=[DateTimeOffset]::Parse([string]$ev.ValidatedUtc)}catch{throw 'Prepared lifecycle repair evidence timestamp is invalid.'}}    if(!$x.IsolationAllowed){throw 'Prepared lifecycle repair requires allowed isolation.'}
    $oldRevision=[long]$task.revision;$now=Get-RepatoUtc;$expiry=([DateTimeOffset]::Parse($now)).AddMinutes((Get-MayaQaAttemptDurationMinutes)).ToString('O')
    $cas={param($current,$preview)$t=Find-RepatoTask $current $TaskId;$r=$t.mayaTaraExecution;$a=$t.mayaTaraAttempt;if([long]$t.revision -ne $oldRevision -or $r.AttemptId -cne $AttemptId -or $r.RunId -cne $RunId -or $a.AttemptId -cne $AttemptId -or $a.RunId -cne $RunId){throw 'Prepared lifecycle repair compare-and-swap failed.'};if($r.Stage -cne 'prepared' -or $r.ExecutionStatus -cne 'Prepared' -or $r.ClaimStatus -cne 'unclaimed' -or $r.ClaimId -or $r.ClaimOwner -or $r.NativeProcessId -or $r.RequestPath -or $r.ResultPath -or $r.ReportPath -or $r.EvidencePath -or $r.SideEffectsPerformed){throw 'Prepared lifecycle repair state changed before mutation.'};$r.PreparedUtc=$now;$r.LaunchingUtc=$null;$r.LaunchedUtc=$null;$r.ExecutingUtc=$null;$r.EvidenceCollectedUtc=$null;$r.RollbackStartedUtc=$null;$r.RollbackVerifiedUtc=$null;$r.VerifiedUtc=$null;$r.CompletedUtc=$null;$r.FailedUtc=$null;$r.NativeProcessId=$null;$r.ClaimOwner=$null;$r.ClaimId=$null;$r.ClaimedUtc=$null;$r.RequestPath=$null;$r.ResultPath=$null;$r.ReportPath=$null;$r.EvidencePath=$null;$r|Add-Member NoteProperty EvidenceSha256 $null -Force;$r.ReceiptPath=$null;$r.FailureCode=$null;$r.FailureDetails=$null;$r.Stage='prepared';$r.ExecutionStatus='Prepared';$r.ClaimStatus='unclaimed';$r.RollbackStatus='Required';$r.VerificationStatus='Pending';$r.CompletionStatus='Pending';$r.SideEffectsPerformed=$false;$a.RequestExpiresUtc=$expiry;$a.Stage='prepared';$a.Success=$false;$a.RequestPath=$null;Add-RepatoHistory $t 'maya-tara-prepared-lifecycle-repaired' 'Maya' "attempt=$AttemptId; run=$RunId";$r};if($StoreMutationBoundary){& $StoreMutationBoundary $StoreRoot $cas}else{Invoke-RepatoStoreMutation $StoreRoot $cas}
}
function Recover-MayaQaInvalidNativeClaim {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[string]$RuntimeRoot,[ValidateRange(1,1440)][Nullable[int]]$AttemptDurationMinutes)
    if($null -eq $AttemptDurationMinutes){$AttemptDurationMinutes=Get-MayaQaAttemptDurationMinutes};$data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$old=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$old -or !$attempt -or $old.Stage -cne 'claimed' -or $old.ExecutionStatus -cne 'Claimed' -or $old.ClaimStatus -cne 'claimed' -or $old.ClaimOwner -ceq 'Tara'){throw 'Execution is not an eligible invalid native claim.'}
    foreach($n in 'NativeProcessId','LaunchingUtc','LaunchedUtc','ExecutingUtc','RequestPath','ResultPath','ReportPath','EvidencePath','ReceiptPath','CompletedUtc','VerifiedUtc','RollbackVerifiedUtc'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw "Invalid claim contains launch or terminal evidence: $n"}};if($old.SideEffectsPerformed -or $old.VerificationStatus -eq 'Verified' -or $old.CompletionStatus -eq 'Completed'){throw 'Invalid claim has side effects or terminal verification evidence.'};if([string]::IsNullOrWhiteSpace([string]$old.ClaimId)){throw 'Invalid claim has no claim identity.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Invalid claim identity invalid: '+(@($resolved.Errors)-join '; '))};$qa=[IO.Path]::GetFullPath((Get-MayaQaRoot));$source=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);$fixtures=[IO.Path]::GetFullPath((Join-Path $qa 'Fixtures'));if(!$source.StartsWith($fixtures.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $source -PathType Leaf) -or (Get-FileHash $source -Algorithm SHA256).Hash -ine $old.AuthoritativeFixtureSha256){throw 'Authoritative fixture validation failed.'};foreach($pair in @(@('ArtifactPath','ArtifactSha256'),@('RunnerManifestPath','RunnerManifestSha256'),@('IsolationPolicyPath','IsolationPolicySha256'))){$p=[string]$old.($pair[0]);if(!$p -or !(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash $p -Algorithm SHA256).Hash -ine $old.($pair[1])){throw "Canonical $($pair[0]) validation failed."}};if(!$old.IsolationAllowed){throw 'Isolation is not allowed.'}
    $runs=[IO.Path]::GetFullPath($(if($RuntimeRoot){$RuntimeRoot}else{Get-MayaQaRuntimeRoot}));$newAttempt=[guid]::NewGuid().ToString('N');$newRun=[guid]::NewGuid().ToString('N');$runtime=[IO.Path]::GetFullPath((Join-Path $runs ($newRun+'-invalid-claim-recovery')));$model=Join-Path $runtime 'model.rvt';if(!$runtime.StartsWith($runs.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Recovery runtime escaped root.'};New-Item -ItemType Directory -Path $runtime -Force|Out-Null;Copy-Item $source $model -Force;$hash=(Get-FileHash $model -Algorithm SHA256).Hash;$newExpiry=[DateTimeOffset]::UtcNow.AddMinutes($AttemptDurationMinutes).ToString('O');$newAttemptRecord=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$newAttempt;TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;RunId=$newRun;RuntimeRoot=$runtime;RequestExpiresUtc=$newExpiry;Stage='prepared';Success=$false;RequestPath=$null};$newExec=[ordered]@{};foreach($p in $old.PSObject.Properties){$newExec[$p.Name]=$p.Value};$newExec.AttemptId=$newAttempt;$newExec.RunId=$newRun;$newExec.DisposableRuntimeRoot=$runtime;$newExec.DisposableModelPath=$model;$newExec.DisposableModelSha256=$hash;$newExec.ClaimOwner=$null;$newExec.ClaimId=$null;$newExec.ClaimedUtc=$null;$newExec.ClaimStatus='unclaimed';$newExec.Stage='prepared';$newExec.ExecutionStatus='Prepared';$newExec.PreparedUtc=Get-RepatoUtc;$newExec.TaskRevisionAtPrepare=$null;$newExec.TaskRevisionAtClaim=$null;$newExec.NativeProcessId=$null;$newExec.RequestPath=$null;$newExec.ResultPath=$null;$newExec.ReportPath=$null;$newExec.EvidencePath=$null;$newExec.ReceiptPath=$null;$newExec.RollbackStatus='Required';$newExec.VerificationStatus='Pending';$newExec.CompletionStatus='Pending';$newExec.FailureCode=$null;$newExec.FailureDetails=$null;$newExec.SideEffectsPerformed=$false
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $x.AttemptId -cne $old.AttemptId -or $x.RunId -cne $old.RunId -or $x.ClaimId -cne $old.ClaimId -or $x.ClaimOwner -ceq 'Tara' -or $x.Stage -cne 'claimed' -or $x.NativeProcessId -or $x.RequestPath -or $x.SideEffectsPerformed){throw 'Invalid-claim recovery compare-and-swap failed.'};$arch=[pscustomobject]$x;$arch|Add-Member NoteProperty Stage 'invalid-claim' -Force;$arch|Add-Member NoteProperty ExecutionStatus 'InvalidClaim' -Force;$arch|Add-Member NoteProperty FailureCode 'invalid-native-claim-owner' -Force;$arch|Add-Member NoteProperty FailureDetails 'Claim was created by a non-Tara owner and no native launch occurred.' -Force;$arch|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force;$arch|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;$arch|Add-Member NoteProperty ReplacementRunId $newRun -Force;if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$arch;if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$t.mayaTaraAttempt;$t.mayaTaraAttempt=$newAttemptRecord;$newExec.TaskRevisionAtPrepare=[long]$t.revision;$t.mayaTaraExecution=[pscustomobject]$newExec;Add-RepatoHistory $t 'maya-tara-invalid-claim-recovered' 'Tara' "invalidClaim=$($old.ClaimId); replacementAttempt=$newAttempt; replacementRun=$newRun";$t.mayaTaraExecution}
}
function Recover-MayaQaInvalidNativeClaim {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[string]$RuntimeRoot,[ValidateRange(1,1440)][Nullable[int]]$AttemptDurationMinutes)
    if($null -eq $AttemptDurationMinutes){$AttemptDurationMinutes=Get-MayaQaAttemptDurationMinutes};$data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$old=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$old -or !$attempt -or $old.Stage -cne 'claimed' -or $old.ExecutionStatus -cne 'Claimed' -or $old.ClaimStatus -cne 'claimed' -or $old.ClaimOwner -ceq 'Tara'){throw 'Execution is not an eligible invalid native claim.'}
    foreach($n in 'NativeProcessId','LaunchingUtc','LaunchedUtc','ExecutingUtc','RequestPath','ResultPath','ReportPath','EvidencePath','ReceiptPath','CompletedUtc','VerifiedUtc','RollbackVerifiedUtc'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw "Invalid claim contains launch or terminal evidence: $n"}};if($old.SideEffectsPerformed -or $old.VerificationStatus -eq 'Verified' -or $old.CompletionStatus -eq 'Completed'){throw 'Invalid claim has side effects or terminal verification evidence.'};if([string]::IsNullOrWhiteSpace([string]$old.ClaimId)){throw 'Invalid claim has no claim identity.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Invalid claim identity invalid: '+(@($resolved.Errors)-join '; '))};$qa=[IO.Path]::GetFullPath((Get-MayaQaRoot));$source=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);$fixtures=[IO.Path]::GetFullPath((Join-Path $qa 'Fixtures'));if(!$source.StartsWith($fixtures.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $source -PathType Leaf)){throw 'Authoritative fixture validation failed.'};$sourceHash=(Get-FileHash $source -Algorithm SHA256).Hash;if($sourceHash -ine $old.AuthoritativeFixtureSha256){throw 'Authoritative fixture hash mismatch.'};foreach($pair in @(@('ArtifactPath','ArtifactSha256'),@('RunnerManifestPath','RunnerManifestSha256'),@('IsolationPolicyPath','IsolationPolicySha256'))){$p=[string]$old.($pair[0]);if(!$p -or !(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash $p -Algorithm SHA256).Hash -ine $old.($pair[1])){throw "Canonical $($pair[0]) validation failed."}};if(!$old.IsolationAllowed){throw 'Isolation is not allowed.'}
    $runs=[IO.Path]::GetFullPath($(if($RuntimeRoot){$RuntimeRoot}else{Get-MayaQaRuntimeRoot}));$newAttempt=[guid]::NewGuid().ToString('N');$newRun=[guid]::NewGuid().ToString('N');$runtime=[IO.Path]::GetFullPath((Join-Path $runs ($newRun+'-invalid-claim-recovery')));if(!$runtime.StartsWith($runs.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Recovery runtime escaped root.'};$model=Join-Path $runtime 'model.rvt';$sidecar=$model+'.fixture.json';New-Item -ItemType Directory -Path $runtime -Force|Out-Null;Copy-Item $source $model -Force;$modelHash=(Get-FileHash $model -Algorithm SHA256).Hash;if($modelHash -ine $sourceHash){throw 'Recovered disposable model hash mismatch.'};$def=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId;$side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$sourceHash};if($resolved.SelectedQaWorkflowId -eq 'grid-bubble-visibility-v1' -or $resolved.SelectedQaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')};if($resolved.SelectedQaWorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')};$side|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $sidecar -Encoding UTF8;$check=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json;if($check.fixtureId -cne $def.FixtureId -or $check.sourceSha256 -ine $sourceHash){throw 'Recovered fixture sidecar validation failed.'}
    $expiry=[DateTimeOffset]::UtcNow.AddMinutes($AttemptDurationMinutes).ToString('O');$newAttemptRecord=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$newAttempt;TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;RunId=$newRun;RuntimeRoot=$runtime;RequestExpiresUtc=$expiry;Stage='prepared';Success=$false;RequestPath=$null};$newExec=[ordered]@{};foreach($p in $old.PSObject.Properties){$newExec[$p.Name]=$p.Value};$newExec.AttemptId=$newAttempt;$newExec.RunId=$newRun;$newExec.DisposableRuntimeRoot=$runtime;$newExec.DisposableModelPath=$model;$newExec.DisposableModelSha256=$modelHash;$newExec.ClaimOwner=$null;$newExec.ClaimId=$null;$newExec.ClaimedUtc=$null;$newExec.ClaimStatus='unclaimed';$newExec.Stage='prepared';$newExec.ExecutionStatus='Prepared';$newExec.PreparedUtc=Get-RepatoUtc;$newExec.TaskRevisionAtPrepare=$null;$newExec.TaskRevisionAtClaim=$null;$newExec.NativeProcessId=$null;$newExec.RequestPath=$null;$newExec.ResultPath=$null;$newExec.ReportPath=$null;$newExec.EvidencePath=$null;$newExec.ReceiptPath=$null;$newExec.RollbackStatus='Required';$newExec.VerificationStatus='Pending';$newExec.CompletionStatus='Pending';$newExec.FailureCode=$null;$newExec.FailureDetails=$null;$newExec.SideEffectsPerformed=$false
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $x.AttemptId -cne $old.AttemptId -or $x.RunId -cne $old.RunId -or $x.ClaimId -cne $old.ClaimId -or $x.ClaimOwner -ceq 'Tara' -or $x.Stage -cne 'claimed' -or $x.NativeProcessId -or $x.RequestPath -or $x.SideEffectsPerformed){throw 'Invalid-claim recovery compare-and-swap failed.'};$arch=[pscustomobject]$x;$arch|Add-Member NoteProperty Stage 'invalid-claim' -Force;$arch|Add-Member NoteProperty ExecutionStatus 'InvalidClaim' -Force;$arch|Add-Member NoteProperty FailureCode 'invalid-native-claim-owner' -Force;$arch|Add-Member NoteProperty FailureDetails 'Claim was created by a non-Tara owner and no native launch occurred.' -Force;$arch|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force;$arch|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;$arch|Add-Member NoteProperty ReplacementRunId $newRun -Force;if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$arch;if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$t.mayaTaraAttempt;$t.mayaTaraAttempt=$newAttemptRecord;$newExec.TaskRevisionAtPrepare=[long]$t.revision;$t.mayaTaraExecution=[pscustomobject]$newExec;Add-RepatoHistory $t 'maya-tara-invalid-claim-recovered' 'Tara' "invalidClaim=$($old.ClaimId); replacementAttempt=$newAttempt; replacementRun=$newRun";$t.mayaTaraExecution}
}
function Recover-MayaQaCorrelatedNativeFailure {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[string]$RuntimeRoot,[scriptblock]$ProcessInspector,[ValidateRange(1,1440)][Nullable[int]]$AttemptDurationMinutes)
    if($null -eq $AttemptDurationMinutes){$AttemptDurationMinutes=Get-MayaQaAttemptDurationMinutes};
    $data=Read-RepatoTaskStore $StoreRoot;
    $task=Find-RepatoTask $data $TaskId;
    $old=$task.mayaTaraExecution;
    $attempt=$task.mayaTaraAttempt
    if(!$old -or !$attempt -or $old.Stage -cne 'executing' -or $old.ExecutionStatus -cne 'Executing' -or $old.ClaimOwner -cne 'Tara' -or [string]::IsNullOrWhiteSpace([string]$old.ClaimId) -or !$old.NativeProcessId -or !$old.RequestPath){throw 'Execution is not an eligible executing Tara failure.'};
    foreach($n in 'ResultPath','ReportPath','ReceiptPath','VerifiedUtc','CompletedUtc','RollbackVerifiedUtc'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw "Failure recovery found consumed evidence: $n"}};
    if($old.EvidencePath -and [string]::IsNullOrWhiteSpace([string]$old.EvidenceSha256)){throw 'Failure recovery found unauthenticated evidence.'}
    if($old.VerificationStatus -ceq 'Verified'){throw 'Already-verified execution is not eligible for correlated native-failure recovery.'};
    if($old.CompletionStatus -ceq 'Completed'){throw 'Already-completed execution is not eligible for correlated native-failure recovery.'};
    if($old.SideEffectsPerformed){throw 'Failure recovery found side effects.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;
    if(@($resolved.Errors).Count){throw ('Failure identity invalid: '+(@($resolved.Errors)-join ';
     '))};
    $identity=[pscustomobject]@{NativeRequestId=$old.NativeRequestId;
    TaskId=$old.TaskId;
    WorkflowId=$old.WorkflowId;
    QaWorkflowId=$old.QaWorkflowId;
    TestId=$old.TestId;
    HandoffId=$old.HandoffId;
    AttemptId=$old.AttemptId;
    RunId=$old.RunId;
    ClaimId=$old.ClaimId};
    if(![IO.Path]::GetFileName($old.RequestPath)){throw 'Request path is invalid.'};
    $resultPath=$old.RequestPath+'.result.json';
    if(!(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'Correlated native result is missing.'};
    try{$request=Get-Content $old.RequestPath -Raw|ConvertFrom-Json;
    $receipt=Get-Content $resultPath -Raw|ConvertFrom-Json}catch{throw 'Correlated native request/result is malformed.'};
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId','ClaimId'){$v=if($request.PSObject.Properties.Name -contains ('canonical'+$n)){$request.('canonical'+$n)}else{$request.$n};
    if([string]$v -cne [string]$identity.$n){throw "Request identity mismatch: $n"}};
    if([string]$request.requestId -cne [string]$old.NativeRequestId -or [string]$receipt.RequestId -cne [string]$old.NativeRequestId -or [string]$receipt.RunId -cne [string]$old.RunId -or [string]$receipt.Status -cne 'Failed'){throw 'Native result correlation/status failed.'};
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','AttemptId','RunId','ClaimId'){if([string]$receipt.$n -cne [string]$identity.$n){throw "Native receipt identity mismatch: $n"}};
    if([string]::IsNullOrWhiteSpace([string]$receipt.ReportPath) -or !(Test-Path -LiteralPath $receipt.ReportPath -PathType Leaf)){throw 'Correlated native report is missing.'};
    try{$report=Get-Content $receipt.ReportPath -Raw|ConvertFrom-Json}catch{throw 'Correlated native report is malformed.'};
    if($report.TestId -cne $old.TestId -or [string]$report.RunId -cne [string]$receipt.RunId -or $report.Status -cne 'Failed'){throw 'Native report identity/status failed.'};
    foreach($n in 'RequestId','TaskId','WorkflowId','AttemptId','ClaimId'){if([string]$report.$n -cne [string]$(if($n -ceq 'RequestId'){$old.NativeRequestId}else{$identity.$n})){throw "Native report identity mismatch: $n"}};
    $failureDetails = 'Native QA report returned Failed without failure details.'
    $failureDetailsProperty = $report.PSObject.Properties['FailureDetails']
    if ($null -ne $failureDetailsProperty) {
        $candidateFailureDetails = [string]$failureDetailsProperty.Value
        if (-not [string]::IsNullOrWhiteSpace($candidateFailureDetails)) {
            $failureDetails = $candidateFailureDetails
        }
    }
    if([string]$failureDetails -eq 'Native QA report returned Failed without failure details.' -and @($report.Errors).Count -gt 0){$failureDetails=[string]$report.Errors[0]}
    $requestExpired=($failureDetails -match 'QA request expired before execution' -and $report.RollbackStatus -ceq 'NotStarted' -and [string]::IsNullOrWhiteSpace([string]$report.DocumentPath) -and @($report.CreatedIds).Count -eq 0 -and @($report.ChangedIds).Count -eq 0 -and @($report.DeletedIds).Count -eq 0 -and @($report.Assertions|Where-Object {$_.Id -cne 'request-identity' -or $_.Passed -ne $true}).Count -eq 0 -and @($report.Assertions|Where-Object {$_.Id -ceq 'request-identity' -and $_.Passed -eq $true}).Count -eq 1)
    if($ProcessInspector){$live=&$ProcessInspector ([int]$old.NativeProcessId) $old}else{try{$live=Get-Process -Id ([int]$old.NativeProcessId) -ErrorAction Stop}catch{$live=$null}};
    if($live){throw 'Recorded native PID is live or ambiguous;
     failure recovery is fail-closed.'}
    $recordedSource=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);
    $oldRuntime=[IO.Path]::GetFullPath($old.DisposableRuntimeRoot);$oldModel=[IO.Path]::GetFullPath($old.DisposableModelPath);$oldRuntimePrefix=$oldRuntime.TrimEnd('\')+'\';
    if($recordedSource -ine $oldModel -or !$recordedSource.StartsWith($oldRuntimePrefix,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $recordedSource -PathType Leaf) -or (Get-FileHash $recordedSource -Algorithm SHA256).Hash -ine $old.AuthoritativeFixtureSha256){throw 'Recorded disposable fixture identity/hash validation failed.'};
    $fixtures=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) 'Fixtures'));$definition=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId;$source=[IO.Path]::GetFullPath((Join-Path $fixtures $definition.Source));
    if(!$source.StartsWith($fixtures.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $source -PathType Leaf) -or (Get-FileHash $source -Algorithm SHA256).Hash -ine $old.AuthoritativeFixtureSha256){throw 'Approved source fixture validation failed.'};
    foreach($pair in @(@('ArtifactPath','ArtifactSha256'),@('DisposableModelPath','DisposableModelSha256'),@('IsolationPolicyPath','IsolationPolicySha256'))){if(!(Test-Path $old.($pair[0])) -or (Get-FileHash $old.($pair[0]) -Algorithm SHA256).Hash -ine $old.($pair[1])){throw "Hash validation failed: $($pair[0])"}};
    $manifestValidated=$false
    $writer=$null;$reader=$null
    try {
        if(!(Test-Path -LiteralPath $old.RunnerManifestPath -PathType Leaf)){throw 'Runner manifest is inaccessible or missing.'}
        if((Get-FileHash -LiteralPath $old.RunnerManifestPath -Algorithm SHA256).Hash -ine $old.RunnerManifestSha256){throw 'Hash validation failed: RunnerManifestPath'}
        $manifestValidated=$true
    } catch {
        if($_.Exception.Message -eq 'Hash validation failed: RunnerManifestPath'){throw}
        $evidencePath=[string]$old.EvidencePath;$evidenceHash=[string]$old.EvidenceSha256
        if([string]::IsNullOrWhiteSpace($evidencePath) -or [string]::IsNullOrWhiteSpace($evidenceHash) -or !(Test-Path -LiteralPath $evidencePath -PathType Leaf)){throw 'Correlated Tara manifest evidence is missing or invalid.'}
        if((Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash -ine $evidenceHash){throw 'Correlated Tara manifest evidence hash mismatch.'}
        try{$evidencePayload=Get-Content -LiteralPath $evidencePath -Raw|ConvertFrom-Json}catch{throw 'Correlated Tara manifest evidence is malformed.'}
        foreach($n in 'EvidenceVersion','ValidationStatus','TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','CanonicalRunId','ClaimId','NativeRunId','DeployedRunnerManifestPath','DeployedRunnerManifestSha256','IsolationPolicySha256','ValidatedUtc'){if($evidencePayload.PSObject.Properties.Name -notcontains $n){throw "Correlated Tara manifest evidence is missing: $n"}}
        if([int]$evidencePayload.EvidenceVersion -ne 1 -or [string]$evidencePayload.ValidationStatus -cne 'Passed'){throw 'Correlated Tara manifest validation did not pass.'}
        foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','ClaimId'){if([string]$evidencePayload.$n -cne [string]$old.$n){throw "Tara manifest evidence identity mismatch: $n"}}
        if([string]$evidencePayload.CanonicalRunId -cne [string]$old.RunId -or [string]$evidencePayload.DeployedRunnerManifestPath -cne [string]$old.RunnerManifestPath -or [string]$evidencePayload.DeployedRunnerManifestSha256 -ine [string]$old.RunnerManifestSha256 -or [string]$evidencePayload.IsolationPolicySha256 -ine [string]$old.IsolationPolicySha256){throw 'Correlated Tara manifest evidence identity or hash mismatch.'}
        try{$null=[DateTimeOffset]::Parse([string]$evidencePayload.ValidatedUtc)}catch{throw 'Correlated Tara manifest evidence timestamp is invalid.'}
        if([string]$evidencePayload.NativeRunId -cne [string]$receipt.RunId){throw 'Correlated Tara native RunId evidence mismatch.'}
        $manifestValidated=$true
    }
    if(!$manifestValidated){throw 'Runner manifest validation failed.'}
    if(!$old.IsolationAllowed){throw 'Isolation is not allowed.'}
    $runs=[IO.Path]::GetFullPath($(if($RuntimeRoot){$RuntimeRoot}else{Get-MayaQaRuntimeRoot}));
    $newAttempt=[guid]::NewGuid().ToString('N');
    $newRun=[guid]::NewGuid().ToString('N');
    $runtime=Join-Path $runs ($newRun+'-qa-failure-recovery');
    $model=Join-Path $runtime 'model.rvt';
    $sidecar=$model+'.fixture.json';
    New-Item $runtime -ItemType Directory -Force|Out-Null;
    Copy-Item $source $model -Force;
    $hash=(Get-FileHash $model -Algorithm SHA256).Hash;
    $def=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId;
    [ordered]@{fixtureId=$def.FixtureId;
    sourceSha256=$hash}|ConvertTo-Json|Set-Content $sidecar -Encoding UTF8;
    if(!(Test-Path $model) -or !(Test-Path $sidecar)){throw 'Replacement model/sidecar preparation failed.'}
    $expiry=[DateTimeOffset]::UtcNow.AddMinutes($AttemptDurationMinutes).ToString('O');
    $newAttemptRecord=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';
    AttemptId=$newAttempt;
    TaskId=$TaskId;
    WorkflowId=$resolved.SelectedWorkflowId;
    RunId=$newRun;
    RuntimeRoot=$runtime;
    RequestExpiresUtc=$expiry;
    Stage='prepared';
    Success=$false;
    RequestPath=$null};
    $newExec=[ordered]@{};
    foreach($p in $old.PSObject.Properties){$newExec[$p.Name]=$p.Value};
    $newExec.AttemptId=$newAttempt;
    $newExec.RunId=$newRun;
    $newExec.DisposableRuntimeRoot=$runtime;
    $newExec.DisposableModelPath=$model;
    $newExec.DisposableModelSha256=$hash;
    $newExec.ClaimOwner=$null;
    $newExec.ClaimId=$null;
    $newExec.ClaimedUtc=$null;
    $newExec.ClaimStatus='unclaimed';
    $newExec.Stage='prepared';
    $newExec.ExecutionStatus='Prepared';
    $newExec.PreparedUtc=Get-RepatoUtc;
    foreach($n in 'LaunchingUtc','LaunchedUtc','ExecutingUtc','EvidenceCollectedUtc','RollbackStartedUtc','RollbackVerifiedUtc','VerifiedUtc','CompletedUtc','FailedUtc'){$newExec[$n]=$null}
    $newExec.TaskRevisionAtPrepare=$null;
    $newExec.TaskRevisionAtClaim=$null;
    $newExec.NativeProcessId=$null;
    $newExec.RequestPath=$null;
    $newExec.ResultPath=$null;
    $newExec.ReportPath=$null;
    $newExec.EvidencePath=$null;
    $newExec.EvidenceSha256=$null;
    if($newExec.Contains('EvidenceValidationStatus')){$newExec.EvidenceValidationStatus=$null}
    $newExec.ReceiptPath=$null;
    $newExec.RollbackStatus='Required';
    $newExec.VerificationStatus='Pending';
    $newExec.CompletionStatus='Pending';
    $newExec.FailureCode=$null;
    $newExec.FailureDetails=$null;
    $newExec.SideEffectsPerformed=$false
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;
    $x=$t.mayaTaraExecution;
    if($t.revision -ne $task.revision -or $x.AttemptId -cne $old.AttemptId -or $x.RunId -cne $old.RunId -or $x.ClaimId -cne $old.ClaimId -or $x.Stage -cne 'executing' -or $x.NativeProcessId -ne $old.NativeProcessId){throw 'QA failure recovery compare-and-swap failed.'};
    $arch=[pscustomobject]$x;
    $arch|Add-Member NoteProperty Stage 'qa-failed' -Force;
    $arch|Add-Member NoteProperty ExecutionStatus 'QaFailed' -Force;
    $arch|Add-Member NoteProperty ClaimStatus 'qa-failed' -Force;
    $arch|Add-Member NoteProperty FailureCode $(if($requestExpired){'request-expired'}else{'native-qa-failed'}) -Force;
    $arch|Add-Member NoteProperty FailureDetails $failureDetails -Force;
    $arch|Add-Member NoteProperty FailedUtc (Get-RepatoUtc) -Force;
    $arch|Add-Member NoteProperty ResultPath $resultPath -Force;
    $arch|Add-Member NoteProperty ReportPath $receipt.ReportPath -Force;
    $arch|Add-Member NoteProperty ReceiptPath $resultPath -Force;
    $arch|Add-Member NoteProperty ResultSha256 (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash -Force;
    $arch|Add-Member NoteProperty ReportSha256 (Get-FileHash -LiteralPath $receipt.ReportPath -Algorithm SHA256).Hash -Force;
    $arch|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;
    $arch|Add-Member NoteProperty ReplacementRunId $newRun -Force;
    if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};
    $t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$arch;
    if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};
    $t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$t.mayaTaraAttempt;
    $t.mayaTaraAttempt=$newAttemptRecord;
    $newExec.TaskRevisionAtPrepare=[long]$t.revision;
    $t.mayaTaraExecution=[pscustomobject]$newExec;
    Add-RepatoHistory $t 'maya-tara-correlated-native-failure-recovered' 'Tara' "failedAttempt=$($old.AttemptId);
     failedRun=$($old.RunId);
     replacementAttempt=$newAttempt;
     failureCode=$arch.FailureCode";
    $t.mayaTaraExecution}
}

function Prepare-MayaQaAfterExpiredFailureRecovery {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$FailedAttemptId,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedCandidateSha256,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$ExpectedCandidateSourceCommit,[switch]$DryRun)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    $archives=@($task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $FailedAttemptId -and $_.FailureCode -ceq 'request-expired'})
    if($archives.Count -ne 1){throw 'Exact terminal request-expired attempt archive is required.'}
    $failed=$archives[0];$attempt=$task.mayaTaraAttempt;$execution=$task.mayaTaraExecution
    if(!$attempt -or !$execution -or $attempt.AttemptId -cne $failed.ReplacementAttemptId -or $attempt.RunId -cne $failed.ReplacementRunId -or $execution.AttemptId -cne $attempt.AttemptId -or $execution.RunId -cne $attempt.RunId -or $execution.Stage -cne 'prepared' -or $execution.ExecutionStatus -cne 'Prepared' -or $execution.ClaimId -or $execution.NativeProcessId -or $execution.RequestPath -or $execution.SideEffectsPerformed){throw 'Request-expired recovery replacement is not an exact unlaunched prepared identity.'}
    if($failed.ManualLoadOnceEvidence.AttemptId -cne $FailedAttemptId -or $failed.ManualLoadOnceEvidence.RunId -cne $failed.RunId -or $failed.ManualLoadOnceEvidence.NativeRequestId -cne $failed.NativeRequestId){throw 'Archived manual approval identity does not match the failed attempt.'}
    foreach($pair in @(@($failed.ResultPath,$failed.ResultSha256),@($failed.ReportPath,$failed.ReportSha256))){if(!$pair[0] -or !$pair[1] -or !(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw 'Archived request-expired result/report hash validation failed.'}}
    $receipt=Get-Content -LiteralPath $failed.ResultPath -Raw|ConvertFrom-Json;$report=Get-Content -LiteralPath $failed.ReportPath -Raw|ConvertFrom-Json
    if($receipt.Status -cne 'Failed' -or $receipt.RequestId -cne $failed.NativeRequestId -or $receipt.TaskId -cne $TaskId -or $receipt.WorkflowId -cne $failed.WorkflowId -or $receipt.AttemptId -cne $FailedAttemptId -or $receipt.RunId -cne $failed.RunId -or $receipt.ClaimId -cne $failed.ClaimId -or $receipt.ReportPath -cne $failed.ReportPath -or $report.Status -cne 'Failed' -or $report.RollbackStatus -cne 'NotStarted' -or $report.Errors.Count -ne 1 -or $report.Errors[0] -notmatch 'QA request expired before execution' -or ![string]::IsNullOrWhiteSpace([string]$report.DocumentPath) -or @($report.CreatedIds).Count -or @($report.ChangedIds).Count -or @($report.DeletedIds).Count -or @($report.Assertions|Where-Object {$_.Id -cne 'request-identity' -or $_.Passed -ne $true}).Count){throw 'Archived terminal expiry evidence failed exact request/report correlation.'}
    if(Get-Process -Id ([int]$failed.NativeProcessId) -ErrorAction SilentlyContinue){throw 'Failed native Revit process is still present.'}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $failed.WorkflowId;$e=$workflow.qaBuildEvidence
    if(!$e -or !$e.DeploymentValidation -or !$e.ManifestIntegrityValidation -or !$e.QaIsolation -or $e.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit -or $e.ArtifactSha256 -ine $ExpectedCandidateSha256 -or $execution.ArtifactSha256 -ine $ExpectedCandidateSha256){throw 'Fresh canonical preparation gates or candidate identity are not satisfied.'}
    $snapshot=[pscustomobject][ordered]@{ArchivedUtc=Get-RepatoUtc;Reason='Unlaunched recovery record superseded by canonical re-preparation after exact request-expired failure';Attempt=$attempt;Execution=$execution;Plan=$task.mayaPlan;QaPacket=$task.mayaTaraQaPacket;WorkflowRunId=$workflow.qaRunId;WorkflowModelPath=$workflow.qaModelPath;WorkflowHandoffId=$workflow.qaHandoffId;WorkflowHandoff=$workflow.qaHandoff;FailedAttemptId=$FailedAttemptId}
    if($DryRun){return [pscustomobject]@{Status='DryRun';FailedAttemptId=$FailedAttemptId;ReplacementAttemptId=$attempt.AttemptId;ReplacementRunId=$attempt.RunId;ResultPath=$failed.ResultPath;ReportPath=$failed.ReportPath;EvidencePreserved=$true;RevitProcessAbsent=$true;QaLaunchPerformed=$false;SideEffectsPerformed=$false}}
    $taskRevision=[long]$task.revision;$workflowRevision=[long]$workflow.workflowRevision
    Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)
        $t=Find-RepatoTask $d $TaskId;$ws=@($t.deploymentWorkflows|Where-Object workflowId -ceq $failed.WorkflowId)
        if([long]$t.revision -ne $taskRevision -or $ws.Count -ne 1 -or [long]$ws[0].workflowRevision -ne $workflowRevision -or $t.mayaTaraAttempt.AttemptId -cne $attempt.AttemptId -or $t.mayaTaraExecution.AttemptId -cne $attempt.AttemptId){throw 'Expired-failure continuation compare-and-swap failed.'}
        if($t.PSObject.Properties.Name -notcontains 'mayaTaraRecoveryPreparationHistory'){$t|Add-Member NoteProperty mayaTaraRecoveryPreparationHistory ([object[]]@()) -Force};$t.mayaTaraRecoveryPreparationHistory=[object[]]@($t.mayaTaraRecoveryPreparationHistory)+$snapshot
        foreach($n in 'mayaPlan','mayaTaraQaPacket','mayaTaraAttempt','mayaTaraExecution','mayaTaraExecutionEvidence'){$t.PSObject.Properties.Remove($n)}
        $w=$ws[0];if($w.PSObject.Properties.Name -notcontains 'qaHandoffHistory'){$w|Add-Member NoteProperty qaHandoffHistory ([object[]]@()) -Force};if($w.qaHandoff){$w.qaHandoffHistory=[object[]]@($w.qaHandoffHistory)+[pscustomobject]@{HandoffId=$w.qaHandoffId;Handoff=$w.qaHandoff;RunId=$w.qaRunId;ArchivedUtc=Get-RepatoUtc;Reason='Superseded before any fresh QA launch after prior request expired'}}
        foreach($n in 'qaHandoffId','qaHandoff','qaApprovalId','qaApprovalStatus','qaRunId','qaModelPath','qaSidecarPath','qaFixtureId','qaFixtureSha256','qaTestId','qaReportPath','qaReportSha256','qaEvidence','qaVerificationStatus','qaCompletionStatus','qaCompletedUtc'){$w.PSObject.Properties.Remove($n)};$w.workflowRevision=[long]$w.workflowRevision+1
        foreach($q in @($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -in @('pending','approved')})){$q.status='superseded';$q.reason='Replaced after archived request-expired attempt before fresh canonical preparation.'}
        Add-RepatoHistory $t 'maya-tara-expired-failure-preparation-reset' 'Maya' "failedAttempt=$FailedAttemptId; unlaunchedRecoveryAttempt=$($attempt.AttemptId); result=$($failed.ResultPath); report=$($failed.ReportPath)"
        [pscustomobject]@{TaskId=$TaskId;WorkflowId=$failed.WorkflowId;FailedAttemptId=$FailedAttemptId;EvidencePreserved=$true;ApprovalRefreshRequired=$true;QaLaunchPerformed=$false}
    }
}
function Get-MayaQaCanonicalNativeResult {
    param([Parameter(Mandatory)][string]$RequestPath,[string]$ResultPath,[Parameter(Mandatory)][object]$Identity,[ValidateRange(1,3600)][int]$TimeoutSeconds=900)
    if(!(Test-Path -LiteralPath $RequestPath -PathType Leaf)){throw 'Canonical request is missing.'}
    try{$request=Get-Content -LiteralPath $RequestPath -Raw|ConvertFrom-Json}catch{throw 'Canonical request JSON is malformed.'}
    if($request.PSObject.Properties.Name -contains 'requestId' -and [string]$request.requestId -cne [string]$Identity.NativeRequestId){throw 'Native request identity mismatch: requestId'}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId','ClaimId'){$rp=if($request.PSObject.Properties.Name -contains ('canonical'+$n)){[string]$request.('canonical'+$n)}elseif($request.PSObject.Properties.Name -contains $n){[string]$request.$n}else{$null};$legacyV2HandoffOmission=($n -ceq 'HandoffId' -and [int]$request.schemaVersion -eq 2 -and [string]::IsNullOrWhiteSpace($rp));if(!$legacyV2HandoffOmission -and $rp -cne [string]$Identity.$n){throw "Canonical request identity mismatch: $n"}}
    $result=if($ResultPath){$ResultPath}else{$RequestPath+'.result.json'};$deadline=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    while(!(Test-Path -LiteralPath $result -PathType Leaf)){if([DateTimeOffset]::UtcNow -ge $deadline){throw 'Canonical native result wait timed out.'};Start-Sleep -Milliseconds 250}
    try{$receipt=Get-Content -LiteralPath $result -Raw|ConvertFrom-Json}catch{throw 'Canonical native result JSON is malformed.'}
    if(!$receipt -or $receipt.PSObject.Properties.Name -notcontains 'RequestId' -or $receipt.RequestId -cne $Identity.NativeRequestId -or $receipt.RunId -cne $Identity.RunId){throw 'Canonical native result identity mismatch.'}
    if($receipt.PSObject.Properties.Name -contains 'ExpiresUtc' -and [DateTimeOffset]::Parse($receipt.ExpiresUtc) -lt [DateTimeOffset]::UtcNow){throw 'Canonical native result is stale or expired.'}
    if([string]::IsNullOrWhiteSpace([string]$receipt.ReportPath) -or !(Test-Path -LiteralPath $receipt.ReportPath -PathType Leaf)){throw 'Canonical native report is missing.'}
    try{$report=Get-Content -LiteralPath $receipt.ReportPath -Raw|ConvertFrom-Json}catch{throw 'Canonical native report JSON is malformed.'}
    if($report.TestId -cne $Identity.TestId -or $report.Status -cne 'Passed'){throw 'Canonical native report identity/status failed.'}
    $assertions=@($report.Assertions);$verified=($assertions.Count -gt 0 -and @($assertions|Where-Object{$_.Passed -isnot [bool] -or !$_.Passed}).Count -eq 0)
    $ep=if($receipt.PSObject.Properties.Name -contains 'EvidencePath' -and $receipt.EvidencePath){$receipt.EvidencePath}else{$receipt.ReportPath};$eh=$null;if(Test-Path -LiteralPath $ep -PathType Leaf){$eh=(Get-FileHash -LiteralPath $ep -Algorithm SHA256).Hash};[pscustomobject]@{RequestId=$Identity.RequestId;TaskId=$Identity.TaskId;WorkflowId=$Identity.WorkflowId;QaWorkflowId=$Identity.QaWorkflowId;TestId=$Identity.TestId;HandoffId=$Identity.HandoffId;AttemptId=$Identity.AttemptId;RunId=$Identity.RunId;ClaimId=$Identity.ClaimId;ResultPath=$result;ReportPath=$receipt.ReportPath;EvidencePath=$ep;EvidenceSha256=$eh;EvidenceValidationStatus=$(if($receipt.Status -ceq 'Passed' -and $report.Status -ceq 'Passed'){'Passed'}else{$null});ReceiptPath=$result;EvidenceAccepted=($receipt.Status -ceq 'Passed' -and $report.Status -ceq 'Passed');RollbackProven=($report.RollbackStatus -ceq 'RolledBack');Verified=$verified}
}
function Resume-MayaQaCanonicalExecution {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId,[string]$ResultPath,[ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$DryRun)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$r=$task.mayaTaraExecution
    if(!$r -or $r.Stage -cne 'executing' -or $r.ExecutionStatus -cne 'Executing'){throw 'Canonical execution is not resumable from its current stage.'}
    if(!$r.NativeProcessId){throw 'Canonical executing execution has no native process ID.'};if($r.ClaimId -cne $ClaimId -or $r.ClaimOwner -cne 'Tara'){throw 'Canonical resume claim identity mismatch.'};if(!$r.RequestPath){throw 'Canonical executing execution has no request path.'};if([string]$r.NativeRequestId -notmatch '^[a-fA-F0-9]{32}$'){throw 'Canonical executing execution has no valid persisted native request ID.'}
    $identity=[pscustomobject]@{RequestId=[IO.Path]::GetFileName($r.RequestPath);NativeRequestId=$r.NativeRequestId;TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;TestId=$r.TestId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;ClaimId=$r.ClaimId}
    if($DryRun){return [pscustomobject]@{Mode='DryRun';Stage=$r.Stage;NativeProcessId=$r.NativeProcessId;RequestPath=$r.RequestPath;ResultPath=$(if($ResultPath){$ResultPath}else{$r.RequestPath+'.result.json'});SideEffectsPerformed=$false}}
    $result=Get-MayaQaCanonicalNativeResult $r.RequestPath $ResultPath $identity $TimeoutSeconds
    if(!$result.EvidenceAccepted){throw 'Native evidence was not accepted.'};Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'executing' -or $x.ClaimId -cne $ClaimId -or $x.NativeProcessId -ne $r.NativeProcessId){throw 'Canonical resume compare-and-swap failed.'};$x.Stage='evidence-collected';$x.ExecutionStatus='EvidenceCollected';$x.ResultPath=$result.ResultPath;$x.ReportPath=$result.ReportPath;$x.EvidencePath=$result.EvidencePath;$x|Add-Member NoteProperty EvidenceSha256 $result.EvidenceSha256 -Force;$x|Add-Member NoteProperty EvidenceValidationStatus $result.EvidenceValidationStatus -Force;$x.ReceiptPath=$result.ReceiptPath;Add-RepatoHistory $t 'maya-tara-evidence-collected' 'Tara' 'resumed correlated native evidence accepted';$x}
    if(!$result.RollbackProven){throw 'Rollback proof is required.'};Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'evidence-collected'){throw 'Canonical rollback transition out of order.'};$x.Stage='rollback-verified';$x.ExecutionStatus='RollbackVerified';$x.RollbackStatus='Verified';$x.RollbackVerifiedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-rollback-verified' 'Tara' 'resumed native rollback evidence accepted';$x}
    if(!$result.Verified){throw 'QA verification failed.'};Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'rollback-verified'){throw 'Canonical verification transition out of order.'};$x.Stage='verified';$x.ExecutionStatus='Verified';$x.VerificationStatus='Verified';$x.VerifiedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-verified' 'Tara' 'resumed QA verification accepted';$x}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'verified'){throw 'Canonical completion transition out of order.'};$x.Stage='completed';$x.ExecutionStatus='Completed';$x.CompletionStatus='Completed';$x.CompletedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-completed' 'Tara' 'resumed canonical execution completed';$x}
}
function Get-MayaQaCatalogDryRun { param([string]$WorkflowId)
    $items=if($WorkflowId){$null=Get-MayaQaWorkflowDefinition $WorkflowId; @(Get-MayaQaWorkflowCatalog | Where-Object WorkflowId -ceq $WorkflowId)}else{@(Get-MayaQaWorkflowCatalog)}
    $items=@($items); [pscustomobject]@{Workflows=$items;SupportedWorkflowCount=$items.Count;SideEffectsPerformed=$false;RevitLaunchPerformed=$false;DeploymentPerformed=$false;StoreWritePerformed=$false}
}
function Invoke-MayaQaProcessLauncher {
    param([Parameter(Mandatory)][string]$Executable,[string]$Arguments,[scriptblock]$Launcher,[hashtable]$EnvironmentVariables,[object]$LaunchRequest)
    if($Launcher){$p=& $Launcher $Executable $Arguments;if(!$p -or !$p.Pid){throw 'Injected process launcher returned no PID.'};return [pscustomobject]@{Pid=[int]$p.Pid;StartedUtc=$(if($p.StartedUtc){$p.StartedUtc}else{Get-RepatoUtc})}}
    if($Arguments){throw 'QA launch agent does not accept arbitrary Revit arguments.'}
    if(!$LaunchRequest){throw 'RepatoQA v2 launch request is required.'}
    Invoke-MayaQaLaunchAgentRequest -Request $LaunchRequest -Executable $Executable
}
function Invoke-MayaQaLaunchAgentRequest {
    param([Parameter(Mandatory)][object]$Request,[Parameter(Mandatory)][string]$Executable,[ValidateRange(100,30000)][int]$TimeoutMilliseconds=5000,[ValidateRange(1024,32768)][int]$MaxResponseBytes=32768,[scriptblock]$ResponseProvider,[int]$ExpectedSessionId)
    $pipe=$null;$writer=$null;$reader=$null;$original=$null
    try {
        if([string]$Request.operation -cne 'launch-revit-qa' -or [int]$Request.schemaVersion -ne 2){throw 'Invalid v2 launch request.'}
        if($ResponseProvider){$response=& $ResponseProvider $Request}
        else {
            if([string]$Request.requestPath -notlike '*.request.json' -or !(Test-Path -LiteralPath $Request.requestPath -PathType Leaf)){throw 'Launch request path is missing.'}
            $pipe=[IO.Pipes.NamedPipeClientStream]::new('.', 'Repato\QaLaunch', [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::WriteThrough)
            $pipe.Connect($TimeoutMilliseconds)
            $json=$Request|ConvertTo-Json -Compress -Depth 10
            if([Text.Encoding]::UTF8.GetByteCount($json) -gt 32768){throw 'Launch request is oversized.'}
            $writer=[IO.StreamWriter]::new($pipe,[Text.Encoding]::UTF8,1024,$true);$writer.AutoFlush=$true
            $writeTask=$writer.WriteLineAsync($json);if(!$writeTask.Wait($TimeoutMilliseconds)){throw 'Launch request write timed out.'};$reader=[IO.StreamReader]::new($pipe,[Text.Encoding]::UTF8,$false,1024,$true)
            $readTask=$reader.ReadLineAsync();if(!$readTask.Wait($TimeoutMilliseconds)){throw 'Launch response read timed out.'};$line=$readTask.Result
            if([string]::IsNullOrWhiteSpace($line) -or [Text.Encoding]::UTF8.GetByteCount($line) -gt $MaxResponseBytes){throw 'Launch response is missing or oversized.'}
            try{$response=$line|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Launch response JSON is malformed.'}
        }
        foreach($n in 'schemaVersion','operation','requestId','correlationId','accepted','pid','user','sid','sessionId','launchUtc','imagePath','requestPath','taskId','workflowId','qaWorkflowId','testId','attemptId','runId','failureCode'){if($response.PSObject.Properties.Name -notcontains $n){throw "Launch response missing $n."}}
        if([int]$response.schemaVersion -ne 2 -or [string]$response.operation -cne 'launch-revit-qa'){throw 'Unexpected launch response contract.'}
        if([string]$response.requestId -cne [string]$Request.requestId -or [string]$response.correlationId -cne [string]$Request.requestId){throw 'Launch response correlation mismatch.'}
        foreach($n in 'taskId','workflowId','qaWorkflowId','testId','attemptId','runId','requestPath'){if([string]$response.$n -cne [string]$Request.$n){throw "Launch response identity mismatch: $n."}}
        if(-not [bool]$response.accepted){if([string]::IsNullOrWhiteSpace([string]$response.failureCode)){throw 'Rejected launch response has no failure code.'};throw "RepatoQA launch rejected: $($response.failureCode)"}
        if([int]$response.pid -le 0 -or [string]$response.user -ine 'RAMSAI\RepatoQA' -or [string]$response.sid -ine 'S-1-5-21-1031246752-3872016183-2454652381-1015'){throw 'Accepted launch identity is invalid.'}
        $expectedSession=if($ExpectedSessionId){@($ExpectedSessionId)}else{$currentIdentity=[Security.Principal.WindowsIdentity]::GetCurrent().Name;if($currentIdentity -ine 'RAMSAI\RepatoQA'){throw 'Launch response validation must run as RAMSAI\RepatoQA.'};@((Get-Process -Id $PID -ErrorAction Stop).SessionId)}
        if(!$expectedSession -or !(@($expectedSession) -contains ([int]$response.sessionId))){throw 'Accepted launch session is not the authenticated RepatoQA session.'}
        if([IO.Path]::GetFullPath([string]$response.imagePath) -ine [IO.Path]::GetFullPath($Executable)){throw 'Accepted launch image mismatch.'}
        if([string]$response.failureCode){throw 'Accepted launch response contains a failure code.'}
        [pscustomobject]@{Pid=[int]$response.pid;StartedUtc=[string]$response.launchUtc;Response=$response}
    } catch { $original=$_.Exception;throw } finally {
        try{if($reader){$reader.Dispose()}}catch{}
        try{if($writer){$writer.Dispose()}}catch{}
        try{if($pipe){$pipe.Dispose()}}catch{}
    }
}
function Invoke-MayaQaLaunchAgentHealth {
    param([ValidateRange(100,10000)][int]$TimeoutMilliseconds=3000)
    $pipe=[IO.Pipes.NamedPipeClientStream]::new('.', 'Repato\QaLaunch', [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::WriteThrough)
    $writer=$null;$reader=$null
    try {
        $pipe.Connect($TimeoutMilliseconds)
          $writer=[IO.StreamWriter]::new($pipe,[Text.Encoding]::UTF8,1024,$true);$writer.AutoFlush=$true
        $writeTask=$writer.WriteLineAsync((@{schemaVersion=1;operation='health'}|ConvertTo-Json -Compress))
        if(!$writeTask.Wait($TimeoutMilliseconds)){throw 'Health request write timed out.'}
          $reader=[IO.StreamReader]::new($pipe,[Text.Encoding]::UTF8,$false,1024,$true)
        $readTask=$reader.ReadLineAsync()
        if(!$readTask.Wait($TimeoutMilliseconds)){throw 'Health response read timed out.'}
        $line=$readTask.Result
        if([string]::IsNullOrWhiteSpace($line) -or $line.Length -gt 32768){throw 'Invalid health response.'}
        $h=$line|ConvertFrom-Json
        foreach($n in 'schemaVersion','operation','ready','user','sid','sessionId','interactive'){if($h.PSObject.Properties.Name -notcontains $n){throw "Health response missing $n."}}
        if([int]$h.schemaVersion -ne 1 -or [string]$h.operation -cne 'health'){throw 'Unexpected health response.'}
        [pscustomobject]@{ProtocolVersion=[int]$h.schemaVersion;Operation=[string]$h.operation;Ready=[bool]$h.ready;User=[string]$h.user;SID=[string]$h.sid;SessionId=[int]$h.sessionId;UserInteractive=[bool]$h.interactive}
      } finally {
          try { if($reader){$reader.Dispose()} } catch { }
          try { if($writer){$writer.Dispose()} } catch { }
          try { if($pipe){$pipe.Dispose()} } catch { }
      }
}
function Invoke-MayaQaLaunchAgentPreflightReadonly {
    param([ValidateRange(100,30000)][int]$TimeoutMilliseconds=5000,[ValidateRange(1024,32768)][int]$MaxResponseBytes=32768,[scriptblock]$ResponseProvider)
    $request=[ordered]@{schemaVersion=1;operation='preflight-readonly'};$pipe=$null;$writer=$null;$reader=$null
    try {
        if($ResponseProvider){$response=& $ResponseProvider ([pscustomobject]$request)}
        else {
            $pipe=[IO.Pipes.NamedPipeClientStream]::new('.', 'Repato\QaLaunch', [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::WriteThrough);$pipe.Connect($TimeoutMilliseconds)
            $json=$request|ConvertTo-Json -Compress;$writer=[IO.StreamWriter]::new($pipe,[Text.Encoding]::UTF8,1024,$true);$writer.AutoFlush=$true;$writeTask=$writer.WriteLineAsync($json);if(!$writeTask.Wait($TimeoutMilliseconds)){throw 'Preflight request write timed out.'};$reader=[IO.StreamReader]::new($pipe,[Text.Encoding]::UTF8,$false,1024,$true);$readTask=$reader.ReadLineAsync();if(!$readTask.Wait($TimeoutMilliseconds)){throw 'Preflight response read timed out.'};$line=$readTask.Result;if([string]::IsNullOrWhiteSpace($line) -or [Text.Encoding]::UTF8.GetByteCount($line) -gt $MaxResponseBytes){throw 'Preflight response is missing or oversized.'};try{$response=$line|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Preflight response JSON is malformed.'}
        }
        foreach($n in 'schemaVersion','operation','succeeded','executionIdentity','qaAddinRoot','runnerManifestPath','expectedRunnerManifestSha256','checks'){if($response.PSObject.Properties.Name -notcontains $n){throw "Preflight response missing $n."}}
        if([int]$response.schemaVersion -ne 1 -or [string]$response.operation -cne 'preflight-readonly'){throw 'Unexpected preflight response contract.'}
        if([string]$response.executionIdentity -ine 'RAMSAI\RepatoQA'){throw 'Preflight execution identity is invalid.'}
        [pscustomobject]@{Succeeded=[bool]$response.succeeded;ExecutionIdentity=[string]$response.executionIdentity;QaAddinRoot=[string]$response.qaAddinRoot;RunnerManifestPath=[string]$response.runnerManifestPath;ExpectedRunnerManifestSha256=[string]$response.expectedRunnerManifestSha256;Checks=@($response.checks);FailureCode=[string]$response.failureCode;Response=$response}
    } finally {try{if($reader){$reader.Dispose()}}catch{};try{if($writer){$writer.Dispose()}}catch{};try{if($pipe){$pipe.Dispose()}}catch{}}
}
function Read-MayaQaBoundedPipeLine {
    param([Parameter(Mandatory)][IO.StreamReader]$Reader,[ValidateRange(100,30000)][int]$TimeoutMilliseconds=5000,[ValidateRange(1024,32768)][int]$MaxResponseBytes=32768,[Parameter(Mandatory)][string]$Operation)
    $readTask=$Reader.ReadLineAsync()
    if(!$readTask.Wait($TimeoutMilliseconds)){throw "$Operation response read timed out; request disposition is ambiguous."}
    $line=$readTask.Result
    if([string]::IsNullOrWhiteSpace($line)){throw "$Operation response is missing."}
    if([Text.Encoding]::UTF8.GetByteCount($line) -gt $MaxResponseBytes){throw "$Operation response is oversized."}
    $line
}
function Invoke-MayaQaLaunchAgentFrozenCandidateStaging {
    param([Parameter(Mandatory)][string]$CandidateCommit,[Parameter(Mandatory)][string]$ExpectedCandidateSha256,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId,[ValidateRange(100,30000)][int]$TimeoutMilliseconds=5000,[object]$CandidateEvidence,[string]$TaskId,[string]$WorkflowId)
    if($CandidateEvidence){if(!$TaskId -or !$WorkflowId){throw 'Generic staging requires canonical task and workflow identity.'};$request=[ordered]@{schemaVersion=1;operation='stage-frozen-candidate-for-qa';requestId=[guid]::NewGuid().ToString('N');candidateCommit=$CandidateCommit;expectedCandidateSha256=$ExpectedCandidateSha256;taskId=$TaskId;workflowId=$WorkflowId;qaWorkflowId=$QaWorkflowId;testId=$TestId;candidateEvidence=$CandidateEvidence}}else{
        if($CandidateCommit -cne 'fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3' -or $ExpectedCandidateSha256 -cne '7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2' -or $QaWorkflowId -cne 'create-plan-views-v1' -or $TestId -cne $QaWorkflowId){throw 'Frozen candidate staging identity is not authoritative.'}
        $request=[ordered]@{schemaVersion=1;operation='stage-frozen-candidate-for-qa';requestId=[guid]::NewGuid().ToString('N');candidateCommit=$CandidateCommit;expectedCandidateSha256=$ExpectedCandidateSha256;qaWorkflowId=$QaWorkflowId;testId=$TestId}
    }
    $pipe=[IO.Pipes.NamedPipeClientStream]::new('.', 'Repato\QaLaunch', [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::WriteThrough);$writer=$null;$reader=$null
    try{$pipe.Connect($TimeoutMilliseconds);$writer=[IO.StreamWriter]::new($pipe,[Text.Encoding]::UTF8,1024,$true);$writer.AutoFlush=$true;$writeTask=$writer.WriteLineAsync(($request|ConvertTo-Json -Compress));if(!$writeTask.Wait($TimeoutMilliseconds)){throw 'Staging request write timed out; request disposition is ambiguous.'};$reader=[IO.StreamReader]::new($pipe,[Text.Encoding]::UTF8,$false,1024,$true);$line=Read-MayaQaBoundedPipeLine -Reader $reader -TimeoutMilliseconds $TimeoutMilliseconds -MaxResponseBytes 32768 -Operation 'Staging';$r=$line|ConvertFrom-Json;if([int]$r.schemaVersion -ne 1 -or [string]$r.operation -cne $request.operation -or [string]$r.requestId -cne $request.requestId){throw 'Staging response identity mismatch.'};if(!$r.succeeded -or [string]$r.candidateCommit -cne $CandidateCommit -or [string]$r.candidateSha256 -ine $ExpectedCandidateSha256 -or [string]$r.qaWorkflowId -cne $QaWorkflowId -or [string]$r.testId -cne $TestId -or [string]$r.stagingIdentity -ine 'RAMSAI\RepatoQA' -or !$r.isolationPassed){throw "Frozen candidate staging rejected: $($r.errorCode)"};$r}finally{try{if($reader){$reader.Dispose()}}catch{};try{if($writer){$writer.Dispose()}}catch{};try{$pipe.Dispose()}catch{}}
}
function Normalize-MayaQaDeploymentValidationResponse {
    param([Parameter(Mandatory)][object]$Response,[Parameter(Mandatory)][string]$CandidateCommit,[Parameter(Mandatory)][string]$ExpectedCandidateSha256,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId,[string]$ExpectedRequestId)
    foreach($n in 'schemaVersion','operation','requestId','succeeded','validationIdentity','qaWorkflowId','testId','candidateSha256','isolationPassed','qaAddinRoot'){if($Response.PSObject.Properties.Name -notcontains $n){throw "Deployment validation response missing $n."}}
    if($ExpectedRequestId -and [string]$Response.requestId -cne $ExpectedRequestId){throw 'Deployment validation response request identity mismatch.'}
    $integrityProperty=$Response.PSObject.Properties['manifestIntegrityPassed'];if($integrityProperty -and !$integrityProperty.Value){throw 'Runtime manifest integrity evidence rejected deployment.'}
    foreach($n in 'runnerManifestPath','runnerManifestSha256','manifestIntegrityPassed'){if($Response.PSObject.Properties.Name -notcontains $n -or $null -eq $Response.$n){throw "Deployment validation response missing $n."}}
    if($Response.manifestIntegrityPassed -isnot [bool] -or !$Response.manifestIntegrityPassed){throw 'Runtime manifest integrity evidence rejected deployment.'}
    if([int]$Response.schemaVersion -ne 1 -or [string]$Response.operation -cne 'validate-qa-deployment' -or [string]$Response.validationIdentity -ine 'RAMSAI\RepatoQA' -or !$Response.succeeded -or [string]$Response.qaWorkflowId -cne $QaWorkflowId -or [string]$Response.testId -cne $TestId -or [string]$Response.candidateSha256 -ine $ExpectedCandidateSha256 -or !$Response.isolationPassed){throw "RepatoQA deployment validation rejected: $($Response.errorCode)"}
    $expectedRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA';$qaRoot=[IO.Path]::GetFullPath([string]$Response.qaAddinRoot);if($qaRoot -ine $expectedRoot -or $qaRoot.Contains('..')){throw 'Deployment validation returned a non-canonical QA add-in root.'}
    $sourceManifest=[IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..\QA') 'Repato.CreatePlanViews.TestRunner.addin'));if(!(Test-Path -LiteralPath $sourceManifest -PathType Leaf)){throw 'Trusted QA runner source manifest is missing.'};$trustedHash=(Get-FileHash -LiteralPath $sourceManifest -Algorithm SHA256).Hash;$canonicalPath=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($qaRoot)) 'Repato.CreatePlanViews.TestRunner.addin'))
    $pathProperty=$Response.PSObject.Properties['runnerManifestPath'];if([string]::IsNullOrWhiteSpace([string]$pathProperty.Value) -or [IO.Path]::GetFullPath([string]$pathProperty.Value) -ine $canonicalPath){throw 'Deployment validation returned a non-canonical runner manifest path.'}
    $hashProperty=$Response.PSObject.Properties['runnerManifestSha256'];if([string]$hashProperty.Value -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$hashProperty.Value -ine $trustedHash){throw 'Runtime runner manifest hash conflicts with trusted source evidence.'}
    $Response|Add-Member NoteProperty runnerManifestPath $canonicalPath -Force;$Response|Add-Member NoteProperty runnerManifestSha256 $trustedHash -Force;$Response|Add-Member NoteProperty validatedRunnerManifestPath $canonicalPath -Force;$Response|Add-Member NoteProperty manifestIntegrityEvidenceAvailable ([bool]$integrityProperty) -Force;$Response|Add-Member NoteProperty manifestIntegrityPassed ($(if($integrityProperty){[bool]$integrityProperty.Value}else{$null})) -Force;$Response
}
function Assert-MayaQaDeploymentValidationResponseEnvelope {
    param([Parameter(Mandatory)][object]$Response,[Parameter(Mandatory)][string]$ExpectedRequestId)
    foreach($n in 'schemaVersion','operation','requestId','succeeded','validationIdentity','qaWorkflowId','testId','candidateSha256','isolationPassed','qaAddinRoot'){if($Response.PSObject.Properties.Name -notcontains $n){throw "Deployment validation response missing $n."}}
    if([int]$Response.schemaVersion -ne 1 -or [string]$Response.operation -cne 'validate-qa-deployment'){throw 'Deployment validation response contract is invalid.'}
    if([string]$Response.requestId -cne $ExpectedRequestId){throw 'Deployment validation response request identity mismatch.'}
    $Response
}
function Invoke-MayaQaLaunchAgentDeploymentValidation {
    param([Parameter(Mandatory)][string]$CandidateCommit,[Parameter(Mandatory)][string]$ExpectedCandidateSha256,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId,[ValidateRange(100,30000)][int]$TimeoutMilliseconds=5000,[object]$CandidateEvidence,[string]$TaskId,[string]$WorkflowId,[string]$RequestId)
    if([string]::IsNullOrWhiteSpace($RequestId)){$RequestId=[guid]::NewGuid().ToString('N')}else{$parsedRequestId=[guid]::Empty;if(![guid]::TryParse($RequestId,[ref]$parsedRequestId)){throw 'Deployment validation request identity is invalid.'}}
    if($CandidateEvidence){if(!$TaskId -or !$WorkflowId){throw 'Generic deployment validation requires canonical task and workflow identity.'};$request=[ordered]@{schemaVersion=1;operation='validate-qa-deployment';requestId=$RequestId;candidateCommit=$CandidateCommit;expectedCandidateSha256=$ExpectedCandidateSha256;taskId=$TaskId;workflowId=$WorkflowId;qaWorkflowId=$QaWorkflowId;testId=$TestId;candidateEvidence=$CandidateEvidence}}else{
        if($CandidateCommit -cne 'fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3' -or $ExpectedCandidateSha256 -cne '7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2' -or $QaWorkflowId -cne 'create-plan-views-v1' -or $TestId -cne $QaWorkflowId){throw 'Deployment validation identity is not authoritative.'}
        $request=[ordered]@{schemaVersion=1;operation='validate-qa-deployment';requestId=$RequestId;candidateCommit=$CandidateCommit;expectedCandidateSha256=$ExpectedCandidateSha256;qaWorkflowId=$QaWorkflowId;testId=$TestId}
    };$pipe=[IO.Pipes.NamedPipeClientStream]::new('.', 'Repato\QaLaunch', [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::WriteThrough);$writer=$null;$reader=$null
    try{$pipe.Connect($TimeoutMilliseconds);$writer=[IO.StreamWriter]::new($pipe,[Text.Encoding]::UTF8,1024,$true);$writer.AutoFlush=$true;$writeTask=$writer.WriteLineAsync(($request|ConvertTo-Json -Compress));if(!$writeTask.Wait($TimeoutMilliseconds)){throw 'Deployment validation request write timed out; request disposition is ambiguous.'};$reader=[IO.StreamReader]::new($pipe,[Text.Encoding]::UTF8,$false,1024,$true);$r=(Read-MayaQaBoundedPipeLine -Reader $reader -TimeoutMilliseconds $TimeoutMilliseconds -MaxResponseBytes 32768 -Operation 'Deployment validation')|ConvertFrom-Json;Assert-MayaQaDeploymentValidationResponseEnvelope -Response $r -ExpectedRequestId $RequestId}finally{try{if($reader){$reader.Dispose()}}catch{};try{if($writer){$writer.Dispose()}}catch{};try{$pipe.Dispose()}catch{}}
}
function ConvertTo-MayaQaCanonicalRequestJson {
    param([Parameter(Mandatory)][object]$Request)
    $ordered=[ordered]@{}
    $properties=if($Request -is [System.Collections.IDictionary]){@($Request.GetEnumerator()|ForEach-Object{[pscustomobject]@{Name=$_.Key;Value=$_.Value}})}else{@($Request.PSObject.Properties|ForEach-Object{[pscustomobject]@{Name=$_.Name;Value=$_.Value}})}
    foreach($p in @($properties|Sort-Object Name)){$ordered[$p.Name]=$p.Value}
    ($ordered|ConvertTo-Json -Compress -Depth 20).Replace('+','\u002B')
}
function Get-MayaQaCanonicalRequestSha256 {
    param([Parameter(Mandatory)][object]$Request)
    $placeholder=[ordered]@{}
    $properties=if($Request -is [System.Collections.IDictionary]){@($Request.GetEnumerator()|ForEach-Object{[pscustomobject]@{Name=$_.Key;Value=$_.Value}})}else{@($Request.PSObject.Properties|ForEach-Object{[pscustomobject]@{Name=$_.Name;Value=$_.Value}})}
    foreach($p in @($properties|Sort-Object Name)){$placeholder[$p.Name]=if($p.Name -ceq 'requestSha256'){('0'*64)}else{$p.Value}}
    $json=ConvertTo-MayaQaCanonicalRequestJson $placeholder
    $sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$sha.Dispose()}
}
function Invoke-MayaQaCanonicalNativeCore {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId,[object]$Result,[Parameter(Mandatory)][string]$Executable,[string]$Arguments,[scriptblock]$ProcessLauncher,[switch]$DryRun)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$r=$task.mayaTaraExecution
    if(!$r){throw 'Canonical execution is missing.'};if($r.Stage -cne 'claimed' -or $r.ExecutionStatus -cne 'Claimed' -or $r.ClaimStatus -cne 'claimed'){throw 'Execution is not claimed.'};if($r.ClaimOwner -cne 'Tara' -or $r.ClaimId -cne $ClaimId){throw 'Claim identity mismatch.'};if([DateTimeOffset]::Parse($task.mayaTaraAttempt.RequestExpiresUtc)-le[DateTimeOffset]::UtcNow){throw 'Attempt expired before native launch.'};if([long]$task.revision -ne ([long]$r.TaskRevisionAtClaim+1)){throw 'Claimed execution revision is stale.'}
    if($null -ne $Result){foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId','ClaimId'){if($Result.PSObject.Properties.Name -contains $n -and [string]$Result.$n -cne [string]$r.$n){throw "Result identity mismatch: $n"}}}
    if($DryRun){return [pscustomobject]@{Stage='claimed';ProcessStarted=$false;NativeProcessId=$null;TaskRevision=$task.revision}}
    $requestId=[guid]::NewGuid().ToString('N');$request=Join-Path $r.DisposableRuntimeRoot ('maya-tara-'+$r.RunId+'.request.json');if($r.QaWorkflowId -cne 'create-plan-views-v1'){throw 'Canonical native startup contract is not supported for the selected QA workflow.'};if($r.PSObject.Properties.Name -notcontains 'ValidatedRunnerManifestPath' -or [string]$r.ValidatedRunnerManifestPath -ine [string]$r.RunnerManifestPath){throw 'Validated runner-manifest path does not match the canonical execution path.'};$prep=$r.FixturePreparationEvidence;if(!$prep){throw 'Canonical Create Plan Views launch requires correlated fixture-preparation evidence.'};$requestObject=[ordered]@{schemaVersion=2;operation='launch-revit-qa';requestId=$requestId;taskId=$r.TaskId;workflowId=$r.WorkflowId;qaWorkflowId=$r.QaWorkflowId;testId=$r.TestId;handoffId=$r.HandoffId;attemptId=$r.AttemptId;runId=$r.RunId;claimId=$r.ClaimId;requestPath=$request;requestSha256=('0'*64);modelPath=$r.DisposableModelPath;modelSha256=$r.DisposableModelSha256;fixtureSha256=$r.AuthoritativeFixtureSha256;fixturePreparationRequestPath=$prep.RequestPath;fixturePreparationRequestSha256=$prep.RequestSha256;fixturePreparationResultPath=$prep.ResultPath;fixturePreparationResultSha256=$prep.ResultSha256;fixturePreparationAttemptId=$prep.AttemptId;fixturePreparationRunId=$prep.RunId;manifestPath=$r.RunnerManifestPath;manifestSha256=$r.RunnerManifestSha256;expiresUtc=$task.mayaTaraAttempt.RequestExpiresUtc};$canonicalJson=ConvertTo-MayaQaCanonicalRequestJson $requestObject;[IO.File]::WriteAllText($request,$canonicalJson,[Text.UTF8Encoding]::new($false));$requestObject.requestSha256=Get-MayaQaCanonicalRequestSha256 $requestObject
    $null=Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'claimed' -or $x.ClaimId -cne $ClaimId -or [long]$t.revision -ne ([long]$x.TaskRevisionAtClaim+1)){throw 'Launch transition compare-and-swap failed.'};$x.Stage='launching';$x.ExecutionStatus='Launching';$x.LaunchingUtc=Get-RepatoUtc;$x.RequestPath=$request;$x|Add-Member NoteProperty NativeRequestId $requestId -Force;Add-RepatoHistory $t 'maya-tara-native-launching' 'Tara' "claim=$ClaimId; request=$requestId";$x}
    $finalJson=$requestObject|ConvertTo-Json -Compress -Depth 20;[IO.File]::WriteAllText($request,$finalJson,[Text.UTF8Encoding]::new($false))
    try{$started=Invoke-MayaQaProcessLauncher $Executable $Arguments $ProcessLauncher $null $requestObject}catch{Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;$x.Stage='launch-failed';$x.ExecutionStatus='LaunchFailed';$x.FailureCode='native-process-start-failed';$x.FailureDetails=$_.Exception.Message;$x.FailedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-native-launch-failed' 'Tara' $x.FailureDetails;$x};throw}
    $transition=Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'launching' -or $x.NativeProcessId){throw 'Duplicate native launch rejected.'};$x.NativeProcessId=[int]$started.Pid;$x.LaunchedUtc=$started.StartedUtc;$x.ExecutingUtc=$started.StartedUtc;$x.Stage='executing';$x.ExecutionStatus='Executing';Add-RepatoHistory $t 'maya-tara-native-executing' 'Tara' "pid=$($started.Pid)";$x}
    $currentResult=Read-RepatoTaskStore $StoreRoot;$currentTask=Find-RepatoTask $currentResult $TaskId;$x=$currentTask.mayaTaraExecution
    if($null -eq $Result){return [pscustomobject]@{Stage=$x.Stage;ExecutionStatus=$x.ExecutionStatus;NativeProcessId=$x.NativeProcessId;RequestPath=$x.RequestPath;RequestId=$x.RequestPath;ProcessStarted=$true;ResultAccepted=$false;Completed=$false}}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId','ClaimId'){if($Result.PSObject.Properties.Name -notcontains $n -or [string]$Result.$n -cne [string]$x.$n){throw "Result identity mismatch: $n"}}
    if(!$Result.EvidenceAccepted){throw 'Native evidence was not accepted.'};Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'executing'){throw 'Evidence transition out of order.'};$x.Stage='evidence-collected';$x.ExecutionStatus='EvidenceCollected';$x.ResultPath=$Result.ResultPath;$x.ReportPath=$Result.ReportPath;$x.EvidencePath=$Result.EvidencePath;Add-RepatoHistory $t 'maya-tara-evidence-collected' 'Tara' 'correlated evidence accepted';$x}
    if(!$Result.RollbackProven){throw 'Rollback proof is required.'};Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'evidence-collected'){throw 'Rollback transition out of order.'};$x.Stage='rollback-verified';$x.ExecutionStatus='RollbackVerified';$x.RollbackStatus='Verified';$x.RollbackVerifiedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-rollback-verified' 'Tara' 'rollback evidence accepted';$x}
    if(!$Result.Verified){throw 'QA verification failed.'};Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'rollback-verified'){throw 'Verification transition out of order.'};$x.Stage='verified';$x.ExecutionStatus='Verified';$x.VerificationStatus='Verified';$x.VerifiedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-verified' 'Tara' 'QA verification accepted';$x}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'verified'){throw 'Completion transition out of order.'};$x.Stage='completed';$x.ExecutionStatus='Completed';$x.CompletionStatus='Completed';$x.CompletedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-completed' 'Tara' 'canonical execution completed';$x}
}
function Prepare-MayaQaCanonicalNativeLaunch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId,[Parameter(Mandatory)][string]$ReportDirectory,[string]$RevitInstallDir='E:\revit\Revit 2025',[Parameter(Mandatory)][string]$QaAddinRoot,[ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$DryRun,[scriptblock]$SessionValidationInvoker,[scriptblock]$PlanPreflightInvoker)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task -or $task.PSObject.Properties.Name -notcontains 'mayaTaraExecution'){throw 'Canonical Maya Tara execution is missing.'}
    $r=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if($r.Stage -cne 'claimed' -or $r.ExecutionStatus -cne 'Claimed' -or $r.ClaimStatus -cne 'claimed'){throw 'Canonical execution is not claimed.'}
    if($r.ClaimOwner -cne 'Tara' -or $r.ClaimId -cne $ClaimId){throw 'Canonical Tara claim identity mismatch.'}
    if(!$attempt -or $attempt.AttemptId -cne $r.AttemptId -or $attempt.RunId -cne $r.RunId){throw 'Canonical attempt/run is not current.'}
    if([DateTimeOffset]::Parse($attempt.RequestExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Canonical Maya Tara attempt is expired.'}
    if([long]$task.revision -ne ([long]$r.TaskRevisionAtClaim+1)){throw 'Claimed execution revision is stale.'}
    if($r.NativeProcessId -or $r.SideEffectsPerformed){throw 'Canonical execution already has native side effects.'}
    foreach($n in 'ArtifactPath','RunnerManifestPath','AuthoritativeFixturePath','DisposableModelPath','IsolationPolicyPath'){$p=[string]$r.$n;if([string]::IsNullOrWhiteSpace($p)){throw "Canonical execution is missing $n."}}
    foreach($pair in @(@('ArtifactPath','ArtifactSha256'),@('RunnerManifestPath','RunnerManifestSha256'),@('AuthoritativeFixturePath','AuthoritativeFixtureSha256'),@('DisposableModelPath','DisposableModelSha256'),@('IsolationPolicyPath','IsolationPolicySha256'))){$p=[string]$r.($pair[0]);$expected=[string]$r.($pair[1]);if(!(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ine $expected){throw "Canonical $($pair[0]) hash validation failed."}}
    if(!$r.IsolationAllowed){throw 'Canonical isolation policy is not allowed.'}
    Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -WarningAction SilentlyContinue
    $qaRoot=Get-MayaQaRoot;$def=Get-MayaQaWorkflowDefinition $r.QaWorkflowId
    $context=[pscustomobject]@{QaRoot=$qaRoot;SourceFixturePath=$r.AuthoritativeFixturePath;FixtureId=$def.FixtureId;FixtureSha256=$r.AuthoritativeFixtureSha256;ModelSha256=$r.DisposableModelSha256;FixturePreparationEvidence=$r.FixturePreparationEvidence;TestId=$r.TestId;ArtifactPath=$r.ArtifactPath;ArtifactSha256=$r.ArtifactSha256;ManifestPath=$r.RunnerManifestPath;ManifestSha256=$r.RunnerManifestSha256;TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;ClaimId=$r.ClaimId}
    $plan=if($PlanPreflightInvoker){& $PlanPreflightInvoker $StoreRoot $r $ReportDirectory $RevitInstallDir $QaAddinRoot $TimeoutSeconds $context $DryRun}else{New-TaraRevitQaPlan -StoreRoot $StoreRoot -TaskId $r.TaskId -WorkflowId $r.WorkflowId -QaWorkflowId $r.QaWorkflowId -RunId $r.RunId -ModelPath $r.DisposableModelPath -SidecarPath ($r.DisposableModelPath+'.fixture.json') -ReportDirectory $ReportDirectory -RevitInstallDir $RevitInstallDir -QaAddinRoot $QaAddinRoot -TimeoutSeconds $TimeoutSeconds -Context $context -DryRun -SessionValidationInvoker $SessionValidationInvoker}
    $request=[ordered]@{requestId=$plan.RequestId;claimId=$r.ClaimId;testId=$r.TestId;modelPath=$r.DisposableModelPath;TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;createdUtc=(Get-RepatoUtc);expiresUtc=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds).ToString('O');selectedManifestPath=$plan.QaRunnerManifestPath;selectedManifestSha256=$plan.QaRunnerManifestSha256;addinIsolation=$plan.Isolation;fixtureSha256=$r.AuthoritativeFixtureSha256;fixturePreparationRequestPath=$r.FixturePreparationEvidence.RequestPath;fixturePreparationRequestSha256=$r.FixturePreparationEvidence.RequestSha256;fixturePreparationResultPath=$r.FixturePreparationEvidence.ResultPath;fixturePreparationResultSha256=$r.FixturePreparationEvidence.ResultSha256;fixturePreparationAttemptId=$r.FixturePreparationEvidence.AttemptId;fixturePreparationRunId=$r.FixturePreparationEvidence.RunId}
    if($DryRun){return [pscustomobject]@{Mode='DryRun';Stage='claimed';ReadyToLaunch=$true;ProcessStarted=$false;SideEffectsPerformed=$false;TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;ClaimId=$r.ClaimId;Request=$request;Plan=$plan}}
    Write-TaraJsonNew $plan.RequestPath ([pscustomobject]$request)
    $started=Get-RepatoUtc
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'claimed' -or $x.ClaimId -cne $ClaimId -or [long]$t.revision -ne ([long]$x.TaskRevisionAtClaim+1) -or $x.NativeProcessId -or $x.SideEffectsPerformed){throw 'Canonical launch compare-and-swap failed.'};$x.Stage='launching';$x.ExecutionStatus='Launching';$x.LaunchingUtc=$started;$x.RequestPath=$plan.RequestPath;$x|Add-Member NoteProperty NativeRequestId $plan.RequestId -Force;Add-RepatoHistory $t 'maya-tara-native-launching' 'Tara' "claim=$ClaimId; request=$($plan.RequestId)";$x}
    [pscustomobject]@{Mode='Prepared';Stage='launching';ProcessStarted=$false;SideEffectsPerformed=$true;RequestPath=$plan.RequestPath;Request=$request;Plan=$plan}
}
function Prepare-MayaQaCanonicalLaunchPhase {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId)
    $data=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $data $TaskId;$r=$t.mayaTaraExecution
    if(!$r -or $r.Stage -cne 'claimed' -or $r.ExecutionStatus -cne 'Claimed' -or $r.ClaimStatus -cne 'claimed'){throw 'Canonical execution is not claimed.'}
    if($r.ClaimOwner -cne 'Tara' -or $r.ClaimId -cne $ClaimId){throw 'Canonical claim identity mismatch.'}
    if(!$t.mayaTaraAttempt -or $t.mayaTaraAttempt.AttemptId -cne $r.AttemptId -or $t.mayaTaraAttempt.RunId -cne $r.RunId){throw 'Canonical attempt/run is not current.'}
    if([DateTimeOffset]::Parse($t.mayaTaraAttempt.RequestExpiresUtc)-le [DateTimeOffset]::UtcNow){throw 'Attempt expired before native launch.'}
    if([long]$t.revision -ne ([long]$r.TaskRevisionAtClaim+1)){throw 'Claimed execution revision is stale.'}
    [pscustomobject]@{Stage='claimed';TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;TestId=$r.TestId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;ClaimId=$r.ClaimId;ResultRequired=$false;ProcessStarted=$false}
}
function Start-MayaQaCanonicalProcessPhase {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId,[Parameter(Mandatory)][string]$Executable,[string]$Arguments,[scriptblock]$ProcessLauncher)
    $null=Prepare-MayaQaCanonicalLaunchPhase $StoreRoot $TaskId $ClaimId
    Invoke-MayaQaCanonicalNativeCore -StoreRoot $StoreRoot -TaskId $TaskId -ClaimId $ClaimId -Executable $Executable -Arguments $Arguments -ProcessLauncher $ProcessLauncher
}
function Accept-MayaQaCanonicalEvidencePhase { param([Parameter(Mandatory)]$Result) if(!$Result.EvidenceAccepted){throw 'Native evidence was not accepted.'};$Result }
function Verify-MayaQaCanonicalRollbackPhase { param([Parameter(Mandatory)]$Result) if(!$Result.RollbackProven){throw 'Rollback proof is required.'};$Result }
function Verify-MayaQaCanonicalExecutionPhase { param([Parameter(Mandatory)]$Result) if(!$Result.Verified){throw 'QA verification failed.'};$Result }
function Wait-MayaQaCanonicalResultPhase {
    param([Parameter(Mandatory)][object]$Launch,[Parameter(Mandatory)][object]$Identity,[Parameter(Mandatory)][scriptblock]$ResultProvider)
    if(!$Launch.NativeProcessId -or !$Launch.RequestId){throw 'Native launch has no process or request identity.'}
    $result=& $ResultProvider $Launch
    if(!$result){throw 'Native result was not produced.'}
    foreach($n in 'RequestId','TaskId','WorkflowId','QaWorkflowId','AttemptId','RunId','ClaimId'){
        if($result.PSObject.Properties.Name -notcontains $n -or [string]$result.$n -cne [string]$Identity.$n){throw "Native result identity mismatch: $n"}
    }
    if($result.PSObject.Properties.Name -contains 'ExpiresUtc' -and [DateTimeOffset]::Parse($result.ExpiresUtc) -lt [DateTimeOffset]::UtcNow){throw 'Native result is expired.'}
    $result
}
function Complete-MayaQaCanonicalExecutionPhase {
    param([Parameter(Mandatory)][object]$Result)
    $e=Accept-MayaQaCanonicalEvidencePhase $Result;$r=Verify-MayaQaCanonicalRollbackPhase $e;$v=Verify-MayaQaCanonicalExecutionPhase $r
    if(!$v){throw 'Canonical execution verification did not pass.'}
    [pscustomobject]@{Result=$v;Completed=$true;CleanupAllowed=$true}
}
function Invoke-MayaQaIntake {
    param([Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$UserRequest,[switch]$DryRun)
    if ($TaskId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') { throw 'Invalid task identity.' }
    if ($WorkflowId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') { throw 'Invalid workflow identity.' }
    $resolved = Resolve-MayaQaRequestWorkflow $UserRequest
    $canonical = Resolve-MayaQaWorkflowId $QaWorkflowId
    if($resolved -cne $canonical){ throw "User request resolves to '$resolved', not '$canonical'." }
    $QaWorkflowId = $canonical
    $def = Get-MayaQaWorkflowDefinition $QaWorkflowId
    $intent = Get-MayaQaRequestIntent $UserRequest
    if ([string]::IsNullOrWhiteSpace($UserRequest)) { throw 'User request is required.' }
    [pscustomobject]@{
        TaskId = $TaskId
        WorkflowId = $WorkflowId
        OriginalUserRequest = $UserRequest
        RequestIntent = $intent
        QaWorkflowId = $QaWorkflowId
        FixtureId = $def.FixtureId
        NativeTestId = Get-MayaQaNativeTestId $def
        PreparationScript = $def.Prep
        RequiredApprovalStage = 'Maya approval after Tara QA passed'
        NextAllowedOperation = 'qa-run-plan'
        SideEffectsPerformed = $false
        DryRun = [bool]$DryRun
    }
}function New-MayaQaBuildRequest {
    param(
        [Parameter(Mandatory)]
        [string]$StoreRoot,

        [Parameter(Mandatory)]
        [string]$TaskId,

        [Parameter(Mandatory)]
        [string]$WorkflowId,

        [Parameter(Mandatory)]
        [string]$QaWorkflowId,

        [string]$UserRequest = '',

        [string]$SourceBranch = 'current',

        [string]$ProjectPath = 'Forma.RevitConnector.csproj',
        [object]$AuthenticatedBuildSource,

        [switch]$DryRun
    )

    if ([string]::IsNullOrWhiteSpace($SourceBranch)) {
        $SourceBranch = 'current'
    }

    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        $ProjectPath = 'Forma.RevitConnector.csproj'
    }
    if ($AuthenticatedBuildSource) { $null = Resolve-MayaQaAuthenticatedBuildSource $AuthenticatedBuildSource }

    if ([string]::IsNullOrWhiteSpace($UserRequest)) {
        $UserRequest = "Please run QA workflow $QaWorkflowId"
    }

    $null = Invoke-MayaQaIntake `
        $TaskId `
        $WorkflowId `
        $QaWorkflowId `
        $UserRequest `
        -DryRun:$true
    $QaWorkflowId = Resolve-MayaQaWorkflowId $QaWorkflowId
    $requestIntent = Get-MayaQaRequestIntent $UserRequest

    $requestId = 'build-' + [guid]::NewGuid().ToString('N')
    $requestedArtifact = 'bin\Release\net8.0-windows\Repato.Revit.dll'

    if ($DryRun) {
        return [pscustomobject]@{
            BuildRequestId = $requestId
            TaskId = $TaskId
            WorkflowId = $WorkflowId
            QaWorkflowId = $QaWorkflowId
            BuildStatus = 'requested'
            SourceBranch = $SourceBranch
            ProjectPath = $ProjectPath
            RequestedArtifact = $requestedArtifact
            SideEffectsPerformed = $false
        }
    }

    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId

    if ($workflow.PSObject.Properties.Name -contains 'qaWorkflowId' -and
        $workflow.qaWorkflowId -cne $QaWorkflowId) {
        throw 'Valid QA intake record is missing.'
    }

    if ($workflow.PSObject.Properties.Name -contains 'qaBuildRequestId' -and
        $workflow.qaBuildRequestId) {
        throw 'Build request already exists.'
    }

    $data = Read-RepatoTaskStore $StoreRoot
    $task = Find-RepatoTask $data $TaskId

    $mutation = @(Invoke-RepatoWorkflowMutation `
        $StoreRoot `
        $TaskId `
        $WorkflowId `
        $workflow.workflowRevision `
        $task.revision {

        param($current)

        $current | Add-Member `
            -NotePropertyName qaWorkflowId `
            -NotePropertyValue $QaWorkflowId `
            -Force

        $current | Add-Member `
            -NotePropertyName qaBuildRequestId `
            -NotePropertyValue $requestId `
            -Force

        $current | Add-Member `
            -NotePropertyName qaBuildRequest `
            -NotePropertyValue ([pscustomobject]@{
                BuildRequestId = $requestId
                SourceBranch = $SourceBranch
                ProjectPath = $ProjectPath
                AuthenticatedBuildSource = $AuthenticatedBuildSource
                RequestedArtifact = $requestedArtifact
                BuildStatus = 'requested'
                RequestedUtc = (Get-Date).ToUniversalTime().ToString('O')
            }) `
            -Force
        $current | Add-Member -NotePropertyName qaRequestIntent -NotePropertyValue $requestIntent -Force

        return $current
    })[-1]

    [pscustomobject]@{
        BuildRequestId = $requestId
        TaskId = $TaskId
        WorkflowId = $WorkflowId
        QaWorkflowId = $QaWorkflowId
        BuildStatus = 'requested'
        SourceBranch = $SourceBranch
        ProjectPath = $ProjectPath
        AuthenticatedBuildSource = $AuthenticatedBuildSource
        RequestedArtifact = $requestedArtifact
        WorkflowRevision = $mutation.Workflow.workflowRevision
        TaskRevision = $mutation.TaskRevision
        SideEffectsPerformed = $true
    }
}
function New-MayaQaCandidateReplacementBuildRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [object]$AuthenticatedBuildSource,
        [string]$SourceBranch='current',
        [string]$ProjectPath='Forma.RevitConnector.csproj',
        [string]$Reason='Scoped Create Plan Views fixture-preparation runner change',
        [switch]$DryRun
    )
    $QaWorkflowId=Resolve-MayaQaWorkflowId $QaWorkflowId
    $source=Resolve-MayaQaAuthenticatedBuildSource $AuthenticatedBuildSource
    $commit=Get-MayaQaTrustedBuildSourceCommit -RepositoryRoot $source.RepositoryRoot -ProjectPath $source.ProjectPath
    if($source.ExpectedSourceCommit -and $commit -ine $source.ExpectedSourceCommit){throw 'Authenticated replacement source commit mismatch.'}
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $activeAttempt=($task.PSObject.Properties.Name -contains 'mayaTaraAttempt') -and [bool]$task.mayaTaraAttempt
    $activeExecution=($task.PSObject.Properties.Name -contains 'mayaTaraExecution') -and [bool]$task.mayaTaraExecution
    if($workflow.qaWorkflowId -cne $QaWorkflowId -or $task.status -cne 'passed' -or $task.workflowStage -cne 'approval' -or $activeAttempt -or $activeExecution){throw 'Candidate replacement build requires the approved QA workflow with no active attempt or execution.'}
    if(@(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count){throw 'Revit is running; candidate replacement build request is blocked.'}
    if($workflow.qaBuildStatus -cne 'succeeded' -or !$workflow.qaBuildEvidence -or !$workflow.qaBuildRequest){throw 'Existing authenticated candidate evidence is required before replacement.'}
    if($workflow.qaBuildRequest.PSObject.Properties.Name -contains 'ReplacementSourceCommit' -and $workflow.qaBuildRequest.ReplacementSourceCommit -ceq $commit -and $workflow.qaBuildStatus -eq 'requested'){
        return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;SourceCommit=$commit;BuildStatus='requested';Reused=$true;SideEffectsPerformed=$false}
    }
    $requestId='build-'+[guid]::NewGuid().ToString('N')
    $replacement=[pscustomobject][ordered]@{BuildRequestId=$requestId;SourceBranch=$SourceBranch;ProjectPath=$ProjectPath;AuthenticatedBuildSource=$AuthenticatedBuildSource;RequestedArtifact='bin\Release\net8.0-windows\Repato.Revit.dll';BuildStatus='requested';RequestedUtc=(Get-Date).ToUniversalTime().ToString('O');ReplacementSourceCommit=$commit;ReplacementReason=$Reason}
    if($DryRun){return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$requestId;SourceCommit=$commit;BuildStatus='planned';SideEffectsPerformed=$false}}
    $prior=[pscustomobject][ordered]@{BuildRequest=$workflow.qaBuildRequest;BuildEvidence=$workflow.qaBuildEvidence;SupersededByBuildRequestId=$requestId;SupersededUtc=(Get-Date).ToUniversalTime().ToString('O');Reason=$Reason}
    $mutation=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        if($current.qaBuildRequest.BuildRequestId -cne $workflow.qaBuildRequest.BuildRequestId -or $current.qaBuildEvidence.ArtifactSha256 -ine $workflow.qaBuildEvidence.ArtifactSha256 -or $current.qaBuildStatus -cne 'succeeded'){throw 'Candidate replacement compare-and-swap failed.'}
        if($current.PSObject.Properties.Name -notcontains 'qaBuildHistory'){$current|Add-Member NoteProperty qaBuildHistory ([object[]]@()) -Force}
        $current.qaBuildHistory=[object[]]@($current.qaBuildHistory)+$prior
        $current.qaBuildRequestId=$requestId
        $current.qaBuildRequest=$replacement
        $current.qaBuildStatus='requested'
        $current.qaBuildEvidence=$null
        return $current
    })[-1]
    [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$requestId;PreviousBuildRequestId=$prior.BuildRequest.BuildRequestId;SourceCommit=$commit;WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;PriorCandidateEvidencePreserved=$true;BuildStatus='requested';SideEffectsPerformed=$true}
}
function Resolve-MayaQaRequestWorkflow {
    param([Parameter(Mandatory)][string]$Request)
    $text=$Request.Trim().ToLowerInvariant()
    if (($text -match 'create[- ]levels' -or $text -match 'create\s+(?:one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+levels') -and $text -match 'grid[- ]resequence|resequence') { throw 'User request is ambiguous.' }
    $map=@{
        'welcome-smoke'='welcome-supervised-dialog-v1';
        'create-grids-world-axis-v1'='create-grids-world-axis-v1';'create grids'='create-grids-world-axis-v1';'create grids world axis'='create-grids-world-axis-v1';
        'create-levels-elevations-v1'='create-levels-elevations-v1';'create-levels'='create-levels-elevations-v1';'create levels'='create-levels-elevations-v1';'create-plan-views-v1'='create-plan-views-v1';
        'grid-bubble-visibility-v1'='grid-bubble-visibility-v1';'grid bubble visibility'='grid-bubble-visibility-v1';
        'grid-bubble-offset-v1'='grid-bubble-offset-v1';'grid bubble offset'='grid-bubble-offset-v1';
        'grid-resequence-v1'='grid-resequence-v1';'grid-resequence-all-directions-v1'='grid-resequence-v1';'grid resequence'='grid-resequence-v1'
    }
    if($map.ContainsKey($text)){return $map[$text]}
    if($text -match 'eight grids|create grids|world axis'){return 'create-grids-world-axis-v1'}
    if($text -match 'create[- ]levels' -or $text -match 'create\s+(?:one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+levels'){return 'create-levels-elevations-v1'}
    if($text -match 'bubble visibility' -or ($text -match '(show|display|hide|turn)\b' -and $text -match 'bubbles?' -and $text -match 'selected\s+grids?')){return 'grid-bubble-visibility-v1'}
    if($text -match 'bubble offset' -or ($text -match '(offset|move|shift)' -and $text -match 'bubbles?' -and $text -match '\b(?:-?\d+(?:\.\d+)?)\s*mm\b')){return 'grid-bubble-offset-v1'}
    if($text -match 'plan\s+views?|floor\s+plan|ceiling\s+plan'){
        return 'create-plan-views-v1'
    }
    if($text -match 'resequence'){
        if($text -notmatch '\bgrids?\b'){throw 'User request does not identify a supported QA workflow.'}
        return 'grid-resequence-v1'
    }
    throw 'User request does not identify a supported QA workflow.'
}
function New-MayaQaRequestFoundation {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$UserRequest,
        [string]$SourceBranch='main',
        [string]$ProjectPath,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [object]$AuthenticatedBuildSource
    )
    $qaId=Resolve-MayaQaRequestWorkflow $UserRequest
    if($qaId -cne (Resolve-MayaQaWorkflowId $QaWorkflowId)){throw 'QA workflow identity mismatch.'}
    $def=Get-MayaQaWorkflowDefinition $qaId
    $taskId='task-'+[guid]::NewGuid().ToString('N');$workflowId='workflow-'+[guid]::NewGuid().ToString('N')
    if([string]::IsNullOrWhiteSpace($ProjectPath)){$ProjectPath='Forma.RevitConnector.csproj'}
    $null=Initialize-RepatoTaskStore $StoreRoot
    New-RepatoTask $StoreRoot $taskId 'Maya QA request' $UserRequest 'qa/maya-qa-workflow' 'maya'|Out-Null
    $taskNow=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $taskId
    if($taskNow.workflowStage -eq 'queued'){Claim-RepatoTask $StoreRoot $taskId 'Neil'|Out-Null;Update-RepatoTask $StoreRoot $taskId 'in-progress' 'implementation' 'Neil' $null $null|Out-Null;Update-RepatoTask $StoreRoot $taskId 'in-progress' 'build-checks' 'Neil' $null $null|Out-Null}
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$plan=New-DeployPlan $StoreRoot $taskId (Join-Path $root 'bin\Release\net8.0-windows\Repato.Revit.dll') (Join-Path $root 'Repato.addin');$workflow=New-DeployWorkflow $StoreRoot $plan
    $intake=Invoke-MayaQaIntake $taskId $workflow.workflowId $qaId $UserRequest
    $buildRequest=New-MayaQaBuildRequest -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflow.workflowId -QaWorkflowId $qaId -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath -AuthenticatedBuildSource $AuthenticatedBuildSource
    [pscustomobject]@{TaskId=$taskId;WorkflowId=$workflow.workflowId;QaWorkflowId=$qaId;NativeTestId=(Get-MayaQaNativeTestId $def);Intake=$intake;BuildRequest=$buildRequest}
}
function New-MayaQaDeploymentValidationOperation {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,[Parameter(Mandatory)][string]$BuildRequestId,[Parameter(Mandatory)][string]$CandidateSourceCommit,[Parameter(Mandatory)][string]$CandidateSha256,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId)
    $id=[guid]::NewGuid().ToString('N');$requestId=[guid]::NewGuid().ToString('N');$now=Get-RepatoUtc
    $op=[pscustomobject][ordered]@{SchemaVersion=1;OperationId=$id;RequestId=$requestId;TaskId=$TaskId;WorkflowId=$WorkflowId;ExpectedTaskRevision=([long]$ExpectedTaskRevision+1);BuildRequestId=$BuildRequestId;CandidateSourceCommit=$CandidateSourceCommit;CandidateSha256=$CandidateSha256;QaWorkflowId=$QaWorkflowId;TestId=$TestId;RequestDisposition='confirmed-unsent';CreatedUtc=$now;TransmittingTaskRevision=$null;Response=$null}
    $null=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;if(!$t){throw 'Continuation task was not found.'};if([long]$t.revision -ne $ExpectedTaskRevision){throw 'Cannot create deployment-validation operation for a stale task revision.'};$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($w.Count -ne 1 -or $w[0].taskId -cne $TaskId){throw 'Cannot create deployment-validation operation for an unbound workflow.'};if($t.PSObject.Properties.Name -notcontains 'deploymentValidationOperations'){$t|Add-Member NoteProperty deploymentValidationOperations ([object[]]@()) -Force};if(@($t.deploymentValidationOperations|Where-Object {$_.RequestDisposition -in @('confirmed-unsent','transmitting','unknown')}).Count){throw 'An unresolved deployment-validation operation already exists.'};if(@($t.deploymentValidationOperations|Where-Object OperationId -ceq $id).Count){throw 'Deployment-validation operation already exists.'};Add-RepatoHistory $t 'deployment-validation-operation-created' 'Maya' "operation=$id; request=$requestId; disposition=confirmed-unsent";$t.deploymentValidationOperations=[object[]]@($t.deploymentValidationOperations)+$op;$t}
    $stored=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;@($stored.deploymentValidationOperations|Where-Object OperationId -ceq $id)[0]
}
function Continue-MayaQaDeploymentValidation {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,
        [Parameter(Mandatory)][string]$ExpectedBuildRequestId,
        [Parameter(Mandatory)][string]$ExpectedCandidateSourceCommit,
        [Parameter(Mandatory)][string]$ExpectedCandidateSha256,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$TestId,
        [scriptblock]$DispositionResolver,
        [scriptblock]$RequestInvoker
    )
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task){throw 'Continuation task was not found.'}
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
    if($workflows.Count -ne 1 -or $workflows[0].taskId -cne $TaskId){throw 'Continuation task/workflow identity mismatch.'}
    $op=$null;if($task.PSObject.Properties.Name -contains 'deploymentValidationOperations'){$op=@($task.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId)[0]}
    if(!$op){throw 'Deployment-validation operation was not found.'}
    foreach($pair in @(@('TaskId',$TaskId),@('WorkflowId',$WorkflowId),@('BuildRequestId',$ExpectedBuildRequestId),@('CandidateSourceCommit',$ExpectedCandidateSourceCommit),@('CandidateSha256',$ExpectedCandidateSha256),@('QaWorkflowId',$QaWorkflowId),@('TestId',$TestId))){if([string]$op.($pair[0]) -cne [string]$pair[1]){throw "Deployment-validation operation binding mismatch: $($pair[0])."}}
    if([long]$op.ExpectedTaskRevision -ne $ExpectedTaskRevision){throw 'Deployment-validation operation revision binding mismatch.'}
    if($op.RequestDisposition -ceq 'completed') {[pscustomobject]@{Status='Completed';OperationId=$OperationId;RequestDisposition='completed';Validation=$op.Response;RevitLaunched=$false;ApprovalBoundaryPreserved=$true};return}
    if($op.RequestDisposition -ceq 'completed-failed'){throw "Deployment validation previously failed: $($op.FailureReason)"}
    $requiredCurrentRevision=if($op.RequestDisposition -in @('unknown','transmitting')){[long]$op.TransmittingTaskRevision}else{$ExpectedTaskRevision}
    if($null -eq $requiredCurrentRevision -or [long]$task.revision -ne [long]$requiredCurrentRevision){throw 'Continuation task revision changed.'}
    if($op.RequestDisposition -in @('unknown','transmitting')){
        if(!$DispositionResolver){throw 'Ambiguous deployment-validation transmission is not retryable without authoritative completion evidence.'}
        if($null -eq $op.TransmittingTaskRevision){throw 'Ambiguous deployment-validation operation has no durable transmission revision.'}
        $resolved=& $DispositionResolver $op
        if(!$resolved -or [string]$resolved.OperationId -cne $OperationId -or [string]$resolved.Disposition -cne 'completed'){throw 'Authoritative deployment-validation disposition did not confirm completion.'}
        if(!$resolved.Response){throw 'Authoritative deployment-validation disposition did not include a response.'}
        $responseRequestId=if($op.PSObject.Properties.Name -contains 'RequestId'){[string]$op.RequestId}else{$null}
        $op.Response=Assert-MayaQaDeploymentValidationResponseEnvelope -Response $resolved.Response -ExpectedRequestId $responseRequestId;$op.RequestDisposition='response-received'
    } elseif($op.RequestDisposition -ne 'confirmed-unsent'){throw 'Legacy or incompatible deployment-validation operation state is not retryable.'}
    if($op.RequestDisposition -ceq 'response-received'){$response=$op.Response}else{
        if(!$RequestInvoker){throw 'A request invoker is required for confirmed-unsent continuation.'}
        $null=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;if([long]$t.revision -ne $ExpectedTaskRevision){throw 'Deployment-validation operation revision changed before transmission.'};$x=@($t.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId)[0];if(!$x -or $x.RequestDisposition -cne 'confirmed-unsent' -or [string]$x.BuildRequestId -cne $ExpectedBuildRequestId -or [string]$x.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit -or [string]$x.CandidateSha256 -cne $ExpectedCandidateSha256){throw 'Deployment-validation operation changed before transmission.'};$x.RequestDisposition='transmitting';Add-RepatoHistory $t 'deployment-validation-transmitting' 'Maya' "operation=$OperationId";$x.TransmittingTaskRevision=[long]$t.revision;$t}
        $response=$null;try{$response=& $RequestInvoker $op}catch{throw 'Deployment-validation transmission is ambiguous; retry is blocked.'}
        if(!$response){throw 'Deployment-validation response was not received; retry is blocked.'}
        $responseRequestId=if($op.PSObject.Properties.Name -contains 'RequestId'){[string]$op.RequestId}else{$null}
        $response=Assert-MayaQaDeploymentValidationResponseEnvelope -Response $response -ExpectedRequestId $responseRequestId
    }
    try{$result=Normalize-MayaQaDeploymentValidationResponse -Response $response -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $QaWorkflowId -TestId $TestId -ExpectedRequestId $responseRequestId}catch{
        $failureReason=$_.Exception.Message
        $null=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;$x=@($t.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId)[0];if(!$x -or $x.RequestDisposition -notin @('transmitting','unknown')){throw 'Deployment-validation failed completion state changed.'};if([long]$t.revision -ne [long]$x.TransmittingTaskRevision -or [string]$x.RequestId -cne $responseRequestId){throw 'Deployment-validation failed completion binding changed.'};$x.RequestDisposition='completed-failed';$x.Response=$response;$x|Add-Member NoteProperty ValidationStatus 'failed' -Force;$x|Add-Member NoteProperty FailureReason $failureReason -Force;$x|Add-Member NoteProperty CompletedUtc (Get-RepatoUtc) -Force;Add-RepatoHistory $t 'deployment-validation-failed' 'Maya' "operation=$OperationId; request=$responseRequestId; reason=$failureReason";$t}
        throw $failureReason
    }
    $op.Response=$result
    $null=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;$x=@($t.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId)[0];if(!$x -or $x.RequestDisposition -notin @('transmitting','unknown','completed')){throw 'Deployment-validation operation disappeared or is not completing.'};if($x.RequestDisposition -in @('transmitting','unknown') -and [long]$t.revision -ne [long]$x.TransmittingTaskRevision){throw 'Deployment-validation completion revision changed.'};if([string]$x.TaskId -cne $TaskId -or [string]$x.WorkflowId -cne $WorkflowId -or [string]$x.BuildRequestId -cne $ExpectedBuildRequestId -or [string]$x.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit -or [string]$x.CandidateSha256 -cne $ExpectedCandidateSha256){throw 'Deployment-validation completion binding changed.'};$x.RequestDisposition='completed';$x.Response=$op.Response;Add-RepatoHistory $t 'deployment-validation-completed' 'Maya' "operation=$OperationId";$t}
    [pscustomobject]@{Status='Completed';OperationId=$OperationId;RequestDisposition='completed';Validation=$result;RevitLaunched=$false;ApprovalBoundaryPreserved=$true}
}
function Abandon-MayaQaUnresolvedDeploymentValidation {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,[Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][switch]$ConfirmReadOnlyValidationPath,[scriptblock]$RevitProcessProvider,[switch]$DryRun
    )
    if([string]::IsNullOrWhiteSpace($Reason)){throw 'Deployment-validation abandonment reason is required.'}
    if(!$ConfirmReadOnlyValidationPath){throw 'Explicit confirmation of the audited read-only validation path is required.'}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task){throw 'Deployment-validation abandonment task was not found.'}
    if([long]$task.revision -ne $ExpectedTaskRevision){throw 'Deployment-validation abandonment task revision changed.'}
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
    if($workflows.Count -ne 1 -or [string]$workflows[0].taskId -cne $TaskId){throw 'Deployment-validation abandonment workflow identity mismatch.'}
    $ops=@($task.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId);if($ops.Count -ne 1){throw 'Deployment-validation abandonment operation identity is not unique.'};$op=$ops[0]
    if([string]$op.TaskId -cne $TaskId -or [string]$op.WorkflowId -cne $WorkflowId){throw 'Deployment-validation abandonment binding mismatch.'}
    if([string]$op.RequestDisposition -notin @('transmitting','unknown') -or $op.Response){throw 'Only an unresolved ambiguous deployment-validation operation can be abandoned.'}
    if([long]$op.TransmittingTaskRevision -ne $ExpectedTaskRevision){throw 'Deployment-validation abandonment transmission revision mismatch.'}
    if($op.PSObject.Properties.Name -contains 'RequestId' -and ![string]::IsNullOrWhiteSpace([string]$op.RequestId)){throw 'Request-bound deployment validation must use authoritative reconciliation, not legacy abandonment.'}
    foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($task.PSObject.Properties.Name -contains $n -and $task.$n){throw 'Deployment-validation abandonment found Tara execution state.'}}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)};if(@($revit).Count){throw 'Deployment-validation abandonment requires Revit to be stopped.'}
    $workflow=$workflows[0];$e=$workflow.qaBuildEvidence
    if(!$e -or [string]$e.BuildRequestId -cne [string]$op.BuildRequestId -or [string]$e.CandidateSourceCommit -cne [string]$op.CandidateSourceCommit -or [string]$e.ArtifactSha256 -ine [string]$op.CandidateSha256){throw 'Deployment-validation abandonment candidate evidence mismatch.'}
    $sourceFiles=@('QaLaunchAgent\NamedPipeServer.cs','QaLaunchAgent\LaunchCoordinator.cs','QaLaunchAgent\StagingAdapter.cs','AgentOrchestration\Invoke-RepatoQaDeploymentValidation.ps1','AgentOrchestration\Repato.QaAddinDeployment.psm1');$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$sourceHashes=[ordered]@{};foreach($relative in $sourceFiles){$path=[IO.Path]::GetFullPath((Join-Path $repo $relative));if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Audited validation source is missing: $relative"};$sourceHashes[$relative]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
    $audit=[pscustomobject][ordered]@{SchemaVersion=1;Outcome='AbandonedUnresolved';SuccessClaimed=$false;OriginalDisposition=[string]$op.RequestDisposition;LegacyRequestIdMissing=$true;ResponsePresent=$false;ValidationPathReadOnlyConfirmed=$true;DeploymentMutationPerformed=$false;RevitLaunched=$false;Reason=$Reason;SourceSha256=$sourceHashes;RecordedUtc=Get-RepatoUtc}
    if($DryRun -or !$PSCmdlet.ShouldProcess("$TaskId/$OperationId",'Terminally abandon unresolved read-only deployment validation')){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;OperationId=$OperationId;ExpectedTaskRevision=$ExpectedTaskRevision;NewDisposition='abandoned';Audit=$audit;FreshValidationPermittedAfterApply=$false;SideEffectsPerformed=$false}}
    $result=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;if([long]$t.revision -ne $ExpectedTaskRevision){throw 'Deployment-validation abandonment compare-and-swap revision changed.'};$x=@($t.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId);if($x.Count -ne 1 -or [string]$x[0].RequestDisposition -notin @('transmitting','unknown') -or $x[0].Response -or [long]$x[0].TransmittingTaskRevision -ne $ExpectedTaskRevision -or ($x[0].PSObject.Properties.Name -contains 'RequestId' -and ![string]::IsNullOrWhiteSpace([string]$x[0].RequestId))){throw 'Deployment-validation abandonment compare-and-swap failed.'};$x[0].RequestDisposition='abandoned';$x[0]|Add-Member NoteProperty TerminalStatus 'AbandonedUnresolved' -Force;$x[0]|Add-Member NoteProperty AbandonmentEvidence $audit -Force;$x[0]|Add-Member NoteProperty AbandonedUtc (Get-RepatoUtc) -Force;Add-RepatoHistory $t 'deployment-validation-abandoned' 'Maya' "operation=$OperationId; outcome=AbandonedUnresolved; success=false";$x[0]}
    [pscustomobject]@{Status='AbandonedUnresolved';TaskId=$TaskId;WorkflowId=$WorkflowId;OperationId=$OperationId;PreviousDisposition=$audit.OriginalDisposition;NewDisposition=$result.RequestDisposition;TaskRevision=([long]$ExpectedTaskRevision+1);SuccessClaimed=$false;EvidenceRetained=$true;FreshValidationPermittedAfterApply=$true;RevitLaunched=$false;SideEffectsPerformed=$true}
}
function Set-MayaQaDeploymentValidationOutcomeUnknown {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,
        [Parameter(Mandatory)][string]$ReplayLedgerPath,[Parameter(Mandatory)][int]$AgentProcessId,
        [Parameter(Mandatory)][DateTime]$AgentProcessStartTime,[Parameter(Mandatory)][object]$HealthResponse,
        [Parameter(Mandatory)][DateTimeOffset]$HealthObservedUtc,[scriptblock]$AgentProcessProvider,[scriptblock]$RevitProcessProvider,[switch]$DryRun
    )
    $parsed=[guid]::Empty;if(![guid]::TryParse($RequestId,[ref]$parsed)){throw 'Outcome-unknown request identity is invalid.'}
    if(!$HealthResponse -or $HealthResponse.Operation -cne 'health' -or !$HealthResponse.Ready -or !$HealthResponse.UserInteractive -or $HealthResponse.User -ine 'RAMSAI\RepatoQA' -or $HealthResponse.Sid -ine 'S-1-5-21-1031246752-3872016183-2454652381-1015'){throw 'Fresh correlated Launch Agent health evidence is required.'}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task -or [long]$task.revision -ne $ExpectedTaskRevision){throw 'Outcome-unknown task revision changed.'}
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($workflows.Count -ne 1 -or [string]$workflows[0].taskId -cne $TaskId){throw 'Outcome-unknown workflow binding mismatch.'}
    $ops=@($task.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId);if($ops.Count -ne 1){throw 'Outcome-unknown operation is not unique.'};$op=$ops[0]
    $lastHistory=@($task.history|Sort-Object timestampUtc)[-1];$transmitEvent=($lastHistory.event -ceq 'deployment-validation-transmitting' -and [string]$lastHistory.details -match [regex]::Escape([string]$op.OperationId));$workflowEvent=($lastHistory.event -ceq 'deployment-workflow-mutated' -and [string]$lastHistory.details -ceq $WorkflowId)
    if([string]$op.RequestId -cne $RequestId -or [string]$op.RequestDisposition -notin @('transmitting','unknown') -or $op.Response -or (($transmitEvent -and [long]$op.TransmittingTaskRevision -ne $ExpectedTaskRevision) -or ($workflowEvent -and [long]$op.TransmittingTaskRevision -ne ($ExpectedTaskRevision-1)) -or (!$transmitEvent -and !$workflowEvent))){throw 'Only the exact transmitted response-missing request can become outcome-unknown.'}
    if([DateTimeOffset]::Parse($lastHistory.timestampUtc) -lt [DateTimeOffset]::Parse($op.CreatedUtc)){throw 'Task changed after transmission outside the bound validation or workflow.'}
    if($HealthObservedUtc -lt [DateTimeOffset]::Parse($op.CreatedUtc)){throw 'Health observation predates the ambiguous request.'}
    foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($task.PSObject.Properties.Name -contains $n -and $task.$n){throw 'Outcome-unknown recovery found Tara execution state.'}}
    $e=$workflows[0].qaBuildEvidence;if(!$e -or [string]$e.BuildRequestId -cne [string]$op.BuildRequestId -or [string]$e.CandidateSourceCommit -cne [string]$op.CandidateSourceCommit -or [string]$e.ArtifactSha256 -ine [string]$op.CandidateSha256 -or $e.DeploymentValidation){throw 'Outcome-unknown candidate binding mismatch.'}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)};if(@($revit).Count){throw 'Outcome-unknown recovery requires Revit to be stopped.'}
    $agent=@();if($AgentProcessProvider){$agent=@(& $AgentProcessProvider $AgentProcessId)}else{$agent=@(Get-Process -Id $AgentProcessId -ErrorAction Stop)};if(@($agent).Count -ne 1 -or $agent[0].ProcessName -cne 'Repato.QaLaunchAgent' -or $agent[0].Id -ne $AgentProcessId -or $agent[0].StartTime -ne $AgentProcessStartTime){throw 'Launch Agent process identity changed since health probe.'}
    $ledgerFull=[IO.Path]::GetFullPath($ReplayLedgerPath);if(!(Test-Path -LiteralPath $ledgerFull -PathType Leaf)){throw 'Launch Agent replay ledger is missing.'};$raw=Get-Content -LiteralPath $ledgerFull -Raw;$ledger=$raw|ConvertFrom-Json
    if(@($ledger|Where-Object {[string]$_.RequestId -ceq $RequestId}).Count){throw 'Request now has a replay receipt; use bound response reconciliation.'}
    $audit=[pscustomobject][ordered]@{SchemaVersion=1;Outcome='OutcomeUnknown';SuccessClaimed=$false;RequestId=$RequestId;OperationId=$OperationId;ReplayLedgerPath=$ledgerFull;ReplayLedgerSha256=(Get-FileHash -LiteralPath $ledgerFull -Algorithm SHA256).Hash;MatchingReceiptCount=0;HealthResponse=$HealthResponse;HealthObservedUtc=$HealthObservedUtc.ToString('O');AgentProcessId=$AgentProcessId;AgentProcessStartTime=$AgentProcessStartTime.ToString('O');ObservedUtc=(Get-Date).ToUniversalTime().ToString('O');AutomaticRetryPermitted=$false;RevitLaunched=$false}
    if($DryRun -or !$PSCmdlet.ShouldProcess("$TaskId/$OperationId",'Terminally record deployment-validation outcome unknown')){return [pscustomobject]@{Status='DryRun';Audit=$audit;SideEffectsPerformed=$false}}
    $result=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;if([long]$t.revision -ne $ExpectedTaskRevision){throw 'Outcome-unknown compare-and-swap revision changed.'};$x=@($t.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId);if($x.Count -ne 1 -or [string]$x[0].RequestId -cne $RequestId -or [string]$x[0].RequestDisposition -notin @('transmitting','unknown') -or $x[0].Response){throw 'Outcome-unknown compare-and-swap binding changed.'};$x[0].RequestDisposition='outcome-unknown';$x[0]|Add-Member NoteProperty TerminalStatus 'OutcomeUnknown' -Force;$x[0]|Add-Member NoteProperty OutcomeUnknownEvidence $audit -Force;$x[0]|Add-Member NoteProperty CompletedUtc (Get-RepatoUtc) -Force;Add-RepatoHistory $t 'deployment-validation-outcome-unknown' 'Maya' "operation=$OperationId; request=$RequestId; success=false; retry=false";$x[0]}
    [pscustomobject]@{Status='OutcomeUnknown';OperationId=$OperationId;RequestId=$RequestId;EvidenceRetained=$true;SuccessClaimed=$false;OldRequestReusePermitted=$false;SideEffectsPerformed=$true}
}
function Fail-MayaQaBoundDeploymentValidationWithoutResponse {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,
        [Parameter(Mandatory)][string]$ObservedFailure,[Parameter(Mandatory)][string]$ReplayLedgerPath,
        [scriptblock]$RevitProcessProvider,[switch]$DryRun
    )
    if([string]::IsNullOrWhiteSpace($ObservedFailure)){throw 'Observed deployment-validation failure is required.'}
    $parsed=[guid]::Empty;if(![guid]::TryParse($RequestId,[ref]$parsed)){throw 'Bound deployment-validation request identity is invalid.'}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;if(!$task){throw 'Bound deployment-validation task was not found.'}
    if([long]$task.revision -ne $ExpectedTaskRevision){throw 'Bound deployment-validation task revision changed.'}
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($workflows.Count -ne 1 -or [string]$workflows[0].taskId -cne $TaskId){throw 'Bound deployment-validation workflow identity mismatch.'}
    $ops=@($task.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId);if($ops.Count -ne 1){throw 'Bound deployment-validation operation identity is not unique.'};$op=$ops[0]
    if([string]$op.TaskId -cne $TaskId -or [string]$op.WorkflowId -cne $WorkflowId -or [string]$op.RequestId -cne $RequestId){throw 'Bound deployment-validation operation binding mismatch.'}
    if([string]$op.RequestDisposition -notin @('transmitting','unknown') -or $op.Response -or [long]$op.TransmittingTaskRevision -ne $ExpectedTaskRevision){throw 'Only a response-missing transmitted deployment validation can be terminally failed.'}
    foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($task.PSObject.Properties.Name -contains $n -and $task.$n){throw 'Bound deployment-validation failure recovery found Tara execution state.'}}
    $e=$workflows[0].qaBuildEvidence;if(!$e -or [string]$e.BuildRequestId -cne [string]$op.BuildRequestId -or [string]$e.CandidateSourceCommit -cne [string]$op.CandidateSourceCommit -or [string]$e.ArtifactSha256 -ine [string]$op.CandidateSha256 -or $e.DeploymentValidation){throw 'Bound deployment-validation failure candidate evidence mismatch.'}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)};if(@($revit).Count){throw 'Bound deployment-validation failure recovery requires Revit to be stopped.'}
    $ledgerFull=[IO.Path]::GetFullPath($ReplayLedgerPath);if(!(Test-Path -LiteralPath $ledgerFull -PathType Leaf)){throw 'Launch Agent replay ledger is missing.'}
    $ledgerRaw=Get-Content -LiteralPath $ledgerFull -Raw;$ledger=$ledgerRaw|ConvertFrom-Json;$receipts=@($ledger|Where-Object {[string]$_.RequestId -ceq $RequestId});if($receipts.Count -ne 1){throw 'Launch Agent replay ledger does not contain exactly one bound receipt.'}
    $receipt=$receipts[0];if([string]$receipt.RunId -cne $RequestId -or [string]$receipt.PayloadHash -notmatch '^[A-Fa-f0-9]{64}$' -or [string]::IsNullOrWhiteSpace([string]$receipt.SeenUtc)){throw 'Launch Agent replay ledger receipt is structurally invalid.'}
    $audit=[pscustomobject][ordered]@{SchemaVersion=1;Outcome='FailedResponseUnavailable';SuccessClaimed=$false;RequestId=$RequestId;LedgerReceipt=$receipt;ReplayLedgerPath=$ledgerFull;ReplayLedgerSha256=(Get-FileHash -LiteralPath $ledgerFull -Algorithm SHA256).Hash;ObservedFailure=$ObservedFailure;ResponsePresent=$false;AutomaticRetryPermitted=$false;DeploymentValidationPassed=$false;RevitLaunched=$false;RecordedUtc=Get-RepatoUtc}
    if($DryRun -or !$PSCmdlet.ShouldProcess("$TaskId/$OperationId",'Terminally fail request-bound deployment validation without a persisted response')){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;OperationId=$OperationId;RequestId=$RequestId;ExpectedTaskRevision=$ExpectedTaskRevision;NewDisposition='completed-failed';Audit=$audit;SideEffectsPerformed=$false}}
    $result=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;if([long]$t.revision -ne $ExpectedTaskRevision){throw 'Bound deployment-validation failure compare-and-swap revision changed.'};$x=@($t.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId);if($x.Count -ne 1 -or [string]$x[0].RequestId -cne $RequestId -or [string]$x[0].RequestDisposition -notin @('transmitting','unknown') -or $x[0].Response -or [long]$x[0].TransmittingTaskRevision -ne $ExpectedTaskRevision){throw 'Bound deployment-validation failure compare-and-swap failed.'};$x[0].RequestDisposition='completed-failed';$x[0]|Add-Member NoteProperty TerminalStatus 'FailedResponseUnavailable' -Force;$x[0]|Add-Member NoteProperty ValidationStatus 'failed' -Force;$x[0]|Add-Member NoteProperty FailureReason $ObservedFailure -Force;$x[0]|Add-Member NoteProperty FailureEvidence $audit -Force;$x[0]|Add-Member NoteProperty CompletedUtc (Get-RepatoUtc) -Force;Add-RepatoHistory $t 'deployment-validation-failed-response-unavailable' 'Maya' "operation=$OperationId; request=$RequestId; success=false; retry=false";$x[0]}
    [pscustomobject]@{Status='FailedResponseUnavailable';TaskId=$TaskId;WorkflowId=$WorkflowId;OperationId=$OperationId;RequestId=$RequestId;NewDisposition=$result.RequestDisposition;TaskRevision=([long]$ExpectedTaskRevision+1);SuccessClaimed=$false;EvidenceRetained=$true;AutomaticRetryPermitted=$false;RevitLaunched=$false;SideEffectsPerformed=$true}
}
function Invoke-MayaQaCanonicalFrozenCandidateStagingValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$TestId,
        [Parameter(Mandatory)][string]$ExpectedBuildRequestId,
        [Parameter(Mandatory)][string]$ExpectedCandidateSourceCommit,
        [Parameter(Mandatory)][string]$ExpectedCandidateSha256,
        [Parameter(Mandatory)][string]$ExpectedRunnerManifestPath,
        [Parameter(Mandatory)][string]$ExpectedRunnerManifestSha256,
        [scriptblock]$HealthInvoker,
        [scriptblock]$PreflightInvoker,
        [scriptblock]$StagingInvoker,
        [scriptblock]$DeploymentValidationInvoker,
        [scriptblock]$PersistenceInvoker,
        [scriptblock]$RevitProcessProvider
    )
    $state={
        $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
        if(!$task){throw 'Canonical task was not found.'}
        $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
        if($workflows.Count -ne 1 -or $workflows[0].taskId -cne $TaskId){throw 'Canonical task/workflow identity mismatch.'}
        [pscustomobject]@{Task=$task;Workflow=$workflows[0]}
    }
    $s=& $state;$w=$s.Workflow;$e=$w.qaBuildEvidence
    if($w.qaBuildStatus -cne 'succeeded'){throw 'Authenticated build status is not succeeded.'}
    if(!$e -or $e.BuildRequestId -cne $ExpectedBuildRequestId -or $e.SourceCommit -cne $ExpectedCandidateSourceCommit -or $e.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit){throw 'Authenticated build evidence identity is invalid.'}
    if($e.EvidenceSource -cne 'FrozenCandidate' -or [string]::IsNullOrWhiteSpace([string]$e.CandidateProvenancePath)){throw 'Frozen candidate evidence is missing or not adopted.'}
    if($e.ArtifactSha256 -ine $ExpectedCandidateSha256){throw 'Frozen candidate hash is invalid.'}
    if($e.PSObject.Properties.Name -contains 'DeploymentValidation' -and $e.DeploymentValidation){throw 'Historical deployment validation evidence is already present.'}
    $approval=@($s.Task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
    if($approval.Count -ne 1){throw 'QA approval is not exactly pending.'}
    foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($s.Task.PSObject.Properties.Name -contains $n){throw 'Tara state already exists.'}}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)}
    if(@($revit).Count){throw 'Revit is running.'}
    $null=Resolve-MayaQaSourceRunnerManifestEvidence -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -TestId $TestId
    $candidate=New-MayaQaPersistedCandidateEvidence -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -TestId $TestId
    if($candidate.RunnerManifestSha256 -ine $ExpectedRunnerManifestSha256){throw 'Authenticated runner source evidence is invalid.'}
    $health=if($HealthInvoker){& $HealthInvoker}else{Invoke-MayaQaLaunchAgentHealth}
    if(!$health.Ready -or $health.User -ine 'RAMSAI\RepatoQA' -or $health.SID -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or [int]$health.SessionId -le 0 -or !$health.UserInteractive){throw 'Launch Agent health contract failed.'}
    $pre=if($PreflightInvoker){& $PreflightInvoker}else{Invoke-MayaQaLaunchAgentPreflightReadonly}
    if(!$pre.Succeeded -or $pre.ExecutionIdentity -ine 'RAMSAI\RepatoQA' -or [IO.Path]::GetFullPath($pre.RunnerManifestPath) -ine [IO.Path]::GetFullPath($ExpectedRunnerManifestPath) -or $pre.ExpectedRunnerManifestSha256 -ine $ExpectedRunnerManifestSha256){throw 'Launch Agent preflight contract failed.'}
    $stage=if($StagingInvoker){& $StagingInvoker $candidate}else{Invoke-MayaQaLaunchAgentFrozenCandidateStaging -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $QaWorkflowId -TestId $TestId -CandidateEvidence $candidate -TaskId $TaskId -WorkflowId $WorkflowId}
    if(!$stage.succeeded -or $stage.candidateCommit -cne $ExpectedCandidateSourceCommit -or $stage.candidateSha256 -ine $ExpectedCandidateSha256 -or $stage.qaWorkflowId -cne $QaWorkflowId -or $stage.testId -cne $TestId -or !$stage.isolationPassed -or ($stage.PSObject.Properties.Name -contains 'taskId' -and $stage.taskId -cne $TaskId) -or ($stage.PSObject.Properties.Name -contains 'workflowId' -and $stage.workflowId -cne $WorkflowId)){throw 'Fresh staging response failed canonical validation.'}
    $currentTask=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    $operation=New-MayaQaDeploymentValidationOperation -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -ExpectedTaskRevision ([long]$currentTask.revision) -BuildRequestId $ExpectedBuildRequestId -CandidateSourceCommit $ExpectedCandidateSourceCommit -CandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $QaWorkflowId -TestId $TestId
    $validation=(Continue-MayaQaDeploymentValidation -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -OperationId $operation.OperationId -ExpectedTaskRevision ([long]$operation.ExpectedTaskRevision) -ExpectedBuildRequestId $ExpectedBuildRequestId -ExpectedCandidateSourceCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $QaWorkflowId -TestId $TestId -RequestInvoker {param($pendingOperation)if($DeploymentValidationInvoker){& $DeploymentValidationInvoker $candidate $pendingOperation}else{Invoke-MayaQaLaunchAgentDeploymentValidation -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $QaWorkflowId -TestId $TestId -CandidateEvidence $candidate -TaskId $TaskId -WorkflowId $WorkflowId -RequestId $pendingOperation.RequestId}}).Validation
    if(!$validation.succeeded -or $validation.qaWorkflowId -cne $QaWorkflowId -or $validation.testId -cne $TestId -or $validation.candidateSha256 -ine $ExpectedCandidateSha256 -or !$validation.isolationPassed -or ($validation.PSObject.Properties.Name -contains 'taskId' -and $validation.taskId -cne $TaskId) -or ($validation.PSObject.Properties.Name -contains 'workflowId' -and $validation.workflowId -cne $WorkflowId) -or ($validation.PSObject.Properties.Name -contains 'runnerManifestPath' -and [IO.Path]::GetFullPath($validation.runnerManifestPath) -ine [IO.Path]::GetFullPath($ExpectedRunnerManifestPath)) -or ($validation.PSObject.Properties.Name -contains 'runnerManifestSha256' -and $validation.runnerManifestSha256 -ine $ExpectedRunnerManifestSha256)){throw 'Deployment validation response failed canonical validation.'}
    $persisted=if($PersistenceInvoker){& $PersistenceInvoker $validation $candidate}else{Invoke-MayaQaFrozenCandidateEvidence -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -CandidateDirectory $e.CandidateDirectory -CandidateDllPath $e.ArtifactPath -ExpectedSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit -DeploymentEvidence $validation}
    $after=& $state;$afterE=$after.Workflow.qaBuildEvidence
    if($afterE.BuildRequestId -cne $ExpectedBuildRequestId -or $afterE.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit -or $afterE.ArtifactSha256 -ine $ExpectedCandidateSha256 -or !$afterE.DeploymentValidation -or @($after.Task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count -ne 1){throw 'Persisted deployment evidence failed canonical verification.'}
    $revitAfter=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)};if(@($revitAfter).Count){throw 'Revit started during boundary.'}
    [pscustomobject]@{Succeeded=$true;TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$ExpectedBuildRequestId;QaWorkflowId=$QaWorkflowId;TestId=$TestId;CandidateSourceCommit=$ExpectedCandidateSourceCommit;CandidateSha256=$ExpectedCandidateSha256;RunnerManifestPath=$ExpectedRunnerManifestPath;RunnerManifestSha256=$ExpectedRunnerManifestSha256;Staging=$stage;DeploymentValidation=$validation;PersistedEvidence=$persisted;Approval='pending';TaraState='absent';RevitLaunched=$false;StoppedBeforeApproval=$true;StoppedBeforeTara=$true;StoppedBeforeRevit=$true}
}

function New-MayaQaPersistentPreBuildRequest {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$UserRequest,
        [string]$SourceBranch='main',
        [string]$ProjectPath='Forma.RevitConnector.csproj',
        [Parameter(Mandatory)][object]$AuthenticatedBuildSource
    )
    $foundation=New-MayaQaRequestFoundation -StoreRoot $StoreRoot -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath -QaWorkflowId (Resolve-MayaQaRequestWorkflow $UserRequest) -AuthenticatedBuildSource $AuthenticatedBuildSource
    $taskData=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $taskData $foundation.TaskId
    Update-RepatoTask $StoreRoot $foundation.TaskId 'in-progress' 'qa' 'Tara' $null $null|Out-Null
    Update-RepatoTask $StoreRoot $foundation.TaskId 'passed' 'qa' 'Tara' $null $null|Out-Null
    Request-RepatoTaskApproval $StoreRoot $foundation.TaskId 'qa-run' 'maya'|Out-Null
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $foundation.TaskId
    $approval=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})[-1]
    if(!$approval){throw 'Persisted qa-run approval request is missing requestId.'}
    [pscustomobject]@{Success=$false;Mode='Real';TaskId=$foundation.TaskId;WorkflowId=$foundation.WorkflowId;QaWorkflowId=$foundation.QaWorkflowId;NativeTestId=$foundation.NativeTestId;Stage='approval-required';NextOperation='Resolve-RepatoTaskApproval';QaApprovalId=$approval.requestId;QaApprovalStatus=$approval.status;BuildRequest=$foundation.BuildRequest;Intake=$foundation.Intake;SideEffectsPerformed=$true;Error=$null}
}

function Invoke-MayaQaRequest {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$UserRequest,[string]$SourceBranch='main',[string]$ProjectPath,
        [ValidateSet('Build','FrozenCandidate')][string]$ArtifactMode='Build',[string]$CandidateDirectory,[string]$CandidateDllPath,
        [string]$ExpectedCandidateSha256,[string]$ExpectedCandidateSourceCommit,[object]$AuthenticatedBuildSource,[switch]$StageFrozenCandidateForQa,[switch]$ValidateExistingDeployment,[scriptblock]$QaStagingInvoker,[scriptblock]$DeploymentValidationInvoker,[scriptblock]$HealthInvoker,[scriptblock]$PreflightInvoker,[scriptblock]$RevitProcessProvider,[switch]$DryRun)
    $qaId=Resolve-MayaQaRequestWorkflow $UserRequest
    $def=Get-MayaQaWorkflowDefinition $qaId
    $qaStaging=$null
    if($ArtifactMode -ceq 'FrozenCandidate'){
        foreach($required in @(@('CandidateDirectory',$CandidateDirectory),@('ExpectedCandidateSha256',$ExpectedCandidateSha256),@('ExpectedCandidateSourceCommit',$ExpectedCandidateSourceCommit))){if([string]::IsNullOrWhiteSpace([string]$required[1])){throw "FrozenCandidate mode requires $($required[0])."}}
        $null=Test-MayaQaFrozenCandidate -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit -QaWorkflowId $qaId
    }
    $taskId='task-'+[guid]::NewGuid().ToString('N');$workflowId='workflow-'+[guid]::NewGuid().ToString('N');$runId=[guid]::NewGuid().ToString('N')
    if($DryRun){return [pscustomobject]@{Success=$true;Mode='DryRun';TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaId;RunId=$runId;FixtureId=$def.FixtureId;NativeTestId=(Get-MayaQaNativeTestId $def);QaStaging=$qaStaging;Stages=@('frozen-candidate-validation','qa-only-staging','isolation','intake','build-request','build-execute','handoff','tara-execute','report-verify','complete','receipt','dashboard');SideEffectsPerformed=$false;Error=$null}}
    $foundation=New-MayaQaRequestFoundation -StoreRoot $StoreRoot -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath -QaWorkflowId $qaId -AuthenticatedBuildSource $AuthenticatedBuildSource
    $taskId=$foundation.TaskId;$workflowId=$foundation.WorkflowId;$intake=$foundation.Intake;$buildRequest=$foundation.BuildRequest
    $deploymentEvidence=$null
    if($ArtifactMode -ceq 'FrozenCandidate'){
        $null=Bind-MayaQaFrozenCandidateBuildEvidence -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit
        $build=Invoke-MayaQaFrozenCandidateEvidence -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit -DeploymentEvidence $deploymentEvidence
    }else{
        $build=Invoke-MayaQaBuildExecute -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -SourceBranch $SourceBranch -ProjectPath $ProjectPath
    }
    if($build.BuildStatus -cne 'succeeded' -or [string]::IsNullOrWhiteSpace($build.ArtifactPath) -or [string]::IsNullOrWhiteSpace($build.ArtifactSha256) -or !(Test-Path -LiteralPath $build.ArtifactPath -PathType Leaf)){throw 'Neil build did not produce a verified artifact.'}
    if((Get-FileHash -LiteralPath $build.ArtifactPath -Algorithm SHA256).Hash -ine $build.ArtifactSha256){throw 'Neil artifact SHA-256 verification failed.'}
    if([string]::IsNullOrWhiteSpace($build.ManifestPath) -or (Get-FileHash -LiteralPath $build.ManifestPath -Algorithm SHA256).Hash -ine $build.ManifestSha256){throw 'Neil artifact manifest SHA-256 verification failed.'}
    if($ArtifactMode -ceq 'FrozenCandidate' -and ($StageFrozenCandidateForQa -or $ValidateExistingDeployment)){
        if(!$DryRun -and ($StageFrozenCandidateForQa -or $ValidateExistingDeployment)){
            $null=Resolve-MayaQaSourceRunnerManifestEvidence -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -TestId (Get-MayaQaNativeTestId $def)
            $candidateEvidence=New-MayaQaPersistedCandidateEvidence -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -TestId (Get-MayaQaNativeTestId $def)
            $nativeTestId=Get-MayaQaNativeTestId $def
            Update-RepatoTask $StoreRoot $taskId 'in-progress' 'qa' 'Tara' $null $null|Out-Null
            Update-RepatoTask $StoreRoot $taskId 'passed' 'qa' 'Tara' $null $null|Out-Null
            Request-RepatoTaskApproval $StoreRoot $taskId 'qa-run' 'maya'|Out-Null
            $runnerSource=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\QA\Repato.CreatePlanViews.TestRunner.addin'));$runnerHash=(Get-FileHash -LiteralPath $runnerSource -Algorithm SHA256).Hash;$runnerPath='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin'
            $stageInvoker={param($candidate)if($QaStagingInvoker){$x=& $QaStagingInvoker $CandidateDirectory $ExpectedCandidateSha256 $ExpectedCandidateSourceCommit $qaId $nativeTestId $false $taskId $workflowId $build;[pscustomobject]@{succeeded=[bool]$x.Success;candidateCommit=$x.CandidateSourceCommit;candidateSha256=$x.CandidateSha256;qaWorkflowId=$qaId;testId=$nativeTestId;isolationPassed=[bool]$x.Isolation.Allowed;taskId=$taskId;workflowId=$workflowId}}else{Invoke-MayaQaLaunchAgentFrozenCandidateStaging -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $qaId -TestId $nativeTestId -CandidateEvidence $candidate -TaskId $taskId -WorkflowId $workflowId}}
            $validationCallback={param($validationCandidate,$pendingOperation)if($DeploymentValidationInvoker){& $DeploymentValidationInvoker $ExpectedCandidateSourceCommit $ExpectedCandidateSha256 $qaId $nativeTestId $taskId $workflowId $build $validationCandidate $pendingOperation}else{Invoke-MayaQaLaunchAgentDeploymentValidation -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $qaId -TestId $nativeTestId -CandidateEvidence $validationCandidate -TaskId $taskId -WorkflowId $workflowId -RequestId $pendingOperation.RequestId}}.GetNewClosure()
            $canonical=Invoke-MayaQaCanonicalFrozenCandidateStagingValidation -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -TestId $nativeTestId -ExpectedBuildRequestId $buildRequest.BuildRequestId -ExpectedCandidateSourceCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -ExpectedRunnerManifestPath $runnerPath -ExpectedRunnerManifestSha256 $runnerHash -HealthInvoker $HealthInvoker -PreflightInvoker $PreflightInvoker -StagingInvoker $stageInvoker -DeploymentValidationInvoker $validationCallback -RevitProcessProvider $(if($RevitProcessProvider){$RevitProcessProvider}else{{ @() }})
            $deploymentEvidence=$canonical.DeploymentValidation
        }
    }
    $run=New-MayaQaRun -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -RunId $runId
    $current=Get-DeployWorkflow $StoreRoot $taskId $workflowId; $taskData=Read-RepatoTaskStore $StoreRoot; $taskNow=Find-RepatoTask $taskData $taskId
    if(@($taskNow.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved'}).Count -eq 0){
        if(@($taskNow.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count -eq 0){
            Update-RepatoTask $StoreRoot $taskId 'in-progress' 'qa' 'Tara' $null $null | Out-Null
            Update-RepatoTask $StoreRoot $taskId 'passed' 'qa' 'Tara' $null $null | Out-Null
            $null=Request-RepatoTaskApproval $StoreRoot $taskId 'qa-run' 'maya'
            $approval=@((Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $taskId).approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})[-1]
        } else {$approval=@($taskNow.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})[-1]}
        if($null -eq $approval -or [string]::IsNullOrWhiteSpace([string]$approval.requestId)){throw 'Persisted qa-run approval request is missing requestId.'}
        return [pscustomobject]@{Success=$false;Mode='Real';TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaId;RunId=$runId;Stage='approval-required';NextOperation='Resolve-RepatoTaskApproval';QaApprovalId=$approval.requestId;QaApprovalStatus=$approval.status;QaStaging=$qaStaging;SideEffectsPerformed=$true;Error=$null}
    }
    $canonical=New-MayaQaCanonicalPreparation -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId
    $handoff=$canonical.Handoff
    $handoffPath=Join-Path (Join-Path $StoreRoot 'handoffs') ($handoff.HandoffId+'.json'); New-Item -ItemType Directory -Path (Split-Path $handoffPath -Parent) -Force | Out-Null
    $approvedTask=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $taskId;$approved=@($approvedTask.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved'})[-1]
    [ordered]@{StoreRoot=$StoreRoot;TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaId;RunId=$runId;HandoffId=$handoff.HandoffId;QaApprovalId=$approved.requestId;QaApprovalStatus=$approved.status;ModelPath=$handoff.ModelPath;SidecarPath=$handoff.SidecarPath;ArtifactPath=$handoff.ArtifactPath;ArtifactSha256=$handoff.ArtifactSha256;ManifestPath=$handoff.ManifestPath;ManifestSha256=$handoff.ManifestSha256} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $handoffPath -Encoding UTF8
    [pscustomobject]@{Success=$true;Mode='Real';TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaId;RunId=$runId;AttemptId=$canonical.Attempt.AttemptId;HandoffPath=$handoffPath;Stage='handoff-ready';Intake=$intake;BuildRequest=$buildRequest;Build=$build;Run=$run;Handoff=$handoff;CanonicalPreparation=$canonical;QaStaging=$qaStaging;SideEffectsPerformed=$true;Error=$null}
}

function Invoke-MayaQaCanonicalTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$UserRequest,
        [string]$SourceBranch = 'current',
        [string]$ProjectPath = 'Forma.RevitConnector.csproj',
        [ValidateSet('Build','FrozenCandidate')][string]$ArtifactMode='Build',
        [string]$CandidateDirectory,[string]$CandidateDllPath,[string]$ExpectedCandidateSha256,[string]$ExpectedCandidateSourceCommit,[object]$AuthenticatedBuildSource,
        [switch]$StageFrozenCandidateForQa,
        [scriptblock]$RequestInvoker,
        [scriptblock]$ExecutionRecordInvoker,
        [scriptblock]$ClaimInvoker,
        [scriptblock]$NativeCoreInvoker
    )

    # These delegates are test seams only. In production the existing Maya,
    # canonical preparation, claim, and native-core implementations remain
    # the defaults and retain ownership of their validation/state transitions.
    if ($RequestInvoker) {
        $request = & $RequestInvoker $StoreRoot $UserRequest $SourceBranch $ProjectPath
    } else {
        $request = Invoke-MayaQaRequest -StoreRoot $StoreRoot -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath -ArtifactMode $ArtifactMode -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedCandidateSha256 $ExpectedCandidateSha256 -ExpectedCandidateSourceCommit $ExpectedCandidateSourceCommit -AuthenticatedBuildSource $AuthenticatedBuildSource -StageFrozenCandidateForQa:$StageFrozenCandidateForQa
    }
    if (!$request -or $request.Stage -notin @('handoff-ready','execution-ready')) {
        throw 'Canonical transaction requires an approved Tara handoff.'
    }

    $handoff = if ($request.PSObject.Properties.Name -contains 'Handoff') { $request.Handoff } else { $request }
    $taskData=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $taskData $request.TaskId
    if($task.PSObject.Properties.Name -notcontains 'mayaTaraAttempt' -or !$task.mayaTaraAttempt){throw 'Canonical persisted attempt is missing.'}
    $authoritativeAttempt=$task.mayaTaraAttempt
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','RunId'){if($authoritativeAttempt.PSObject.Properties.Name -notcontains $n){throw "Canonical persisted attempt is missing $n."};$actual=$authoritativeAttempt.$n;$expected=if($n -eq 'TaskId'){$request.TaskId}elseif($n -eq 'WorkflowId'){$request.WorkflowId}elseif($n -eq 'QaWorkflowId'){$request.QaWorkflowId}else{$request.RunId};if([string]$actual -cne [string]$expected){throw "Canonical persisted identity mismatch: $n"}}
    if([string]::IsNullOrWhiteSpace([string]$authoritativeAttempt.AttemptId) -or [string]$authoritativeAttempt.RunId -cne [string]$request.RunId){throw 'Canonical persisted attempt identity is missing or stale.'}
    if($handoff.PSObject.Properties.Name -contains 'AttemptId' -and ![string]::IsNullOrWhiteSpace([string]$handoff.AttemptId) -and [string]$handoff.AttemptId -cne [string]$authoritativeAttempt.AttemptId){throw 'Handoff AttemptId does not match the persisted canonical attempt.'}
    $workflow=Get-DeployWorkflow $StoreRoot $request.TaskId $request.WorkflowId
    $packet=if($task.PSObject.Properties.Name -contains 'mayaTaraQaPacket'){$task.mayaTaraQaPacket}else{$null}
    $evidence=if($workflow.PSObject.Properties.Name -contains 'qaBuildEvidence'){$workflow.qaBuildEvidence}else{$null}
    $fixturePath=if($packet -and $packet.PSObject.Properties.Name -contains 'FixturePath'){$packet.FixturePath}else{$null}
    $fixtureSha=if($packet -and $packet.PSObject.Properties.Name -contains 'FixtureSha256'){$packet.FixtureSha256}else{$workflow.qaFixtureSha256}
    $modelPath=if($packet -and $packet.PSObject.Properties.Name -contains 'ModelPath'){$packet.ModelPath}else{$workflow.qaModelPath}
    $modelSha=$null;if($modelPath -and (Test-Path -LiteralPath $modelPath -PathType Leaf)){$modelSha=(Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash}
    $runnerPath=if($evidence -and $evidence.PSObject.Properties.Name -contains 'RunnerManifestPath'){$evidence.RunnerManifestPath}elseif($handoff.PSObject.Properties.Name -contains 'RunnerManifestPath'){$handoff.RunnerManifestPath}elseif($packet -and $packet.PSObject.Properties.Name -contains 'RunnerManifestPath'){$packet.RunnerManifestPath}else{$null}
    $runnerSha=if($evidence -and $evidence.PSObject.Properties.Name -contains 'RunnerManifestSha256'){$evidence.RunnerManifestSha256}elseif($handoff.PSObject.Properties.Name -contains 'RunnerManifestSha256'){$handoff.RunnerManifestSha256}elseif($packet -and $packet.PSObject.Properties.Name -contains 'RunnerManifestSha256'){$packet.RunnerManifestSha256}else{$null}
    $validatedPath=if($evidence -and $evidence.PSObject.Properties.Name -contains 'ValidatedRunnerManifestPath'){$evidence.ValidatedRunnerManifestPath}elseif($handoff.PSObject.Properties.Name -contains 'ValidatedRunnerManifestPath'){$handoff.ValidatedRunnerManifestPath}else{$runnerPath}
    $isolation=if($evidence -and $evidence.PSObject.Properties.Name -contains 'Isolation'){$evidence.Isolation}elseif($handoff.PSObject.Properties.Name -contains 'Isolation'){$handoff.Isolation}else{$null}
    $preflight=[pscustomobject]@{TaskId=$request.TaskId;WorkflowId=$request.WorkflowId;QaWorkflowId=$request.QaWorkflowId;TestId=$(if($handoff.PSObject.Properties.Name -contains 'NativeTestId'){$handoff.NativeTestId}else{$packet.TestId});HandoffId=$handoff.HandoffId;AttemptId=$authoritativeAttempt.AttemptId;RunId=$request.RunId;ArtifactPath=$evidence.ArtifactPath;ArtifactSha256=$evidence.ArtifactSha256;CandidateDirectory=$evidence.CandidateDirectory;CandidateDllPath=$evidence.ArtifactPath;CandidateSha256=$evidence.ArtifactSha256;CandidateSourceCommit=$evidence.CandidateSourceCommit;FixturePath=$fixturePath;FixtureSha256=$fixtureSha;DisposableFixturePath=$modelPath;DisposableFixtureSha256=$modelSha;RunnerManifest=$runnerPath;RunnerManifestSha256=$runnerSha;ValidatedRunnerManifestPath=$validatedPath;ValidatedRunnerManifestSha256=$runnerSha;QaAddinRoot=$(if($evidence.PSObject.Properties.Name -contains 'QaAddinRoot'){$evidence.QaAddinRoot}else{$handoff.QaAddinRoot});Isolation=$isolation;RuntimeRoot=$authoritativeAttempt.RuntimeRoot;RequestExpiresUtc=$authoritativeAttempt.RequestExpiresUtc}
    $preparation=$packet.FixturePreparationEvidence;$preflight|Add-Member NoteProperty FixturePreparationEvidence $preparation -Force
    $missing=[Collections.Generic.List[string]]::new();foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId','ArtifactPath','ArtifactSha256','CandidateDirectory','CandidateDllPath','CandidateSha256','CandidateSourceCommit','FixturePath','FixtureSha256','DisposableFixturePath','DisposableFixtureSha256','RunnerManifest','RunnerManifestSha256','ValidatedRunnerManifestPath','QaAddinRoot','RuntimeRoot','RequestExpiresUtc'){if([string]::IsNullOrWhiteSpace([string]$preflight.$n)){$missing.Add($n)}};if(!$preflight.Isolation){$missing.Add('Isolation')}else{foreach($n in 'PolicyPath','PolicySha256'){if([string]::IsNullOrWhiteSpace([string]$preflight.Isolation.$n)){$missing.Add("Isolation.$n")}};if(!$preflight.Isolation.Allowed){$missing.Add('Isolation.Allowed')}};if($missing.Count){throw ('Canonical transaction preflight contract invalid; missing or invalid: '+($missing -join ', '))};if(!(Test-Path -LiteralPath $preflight.FixturePath -PathType Leaf) -or (Get-FileHash -LiteralPath $preflight.FixturePath -Algorithm SHA256).Hash -ine $preflight.FixtureSha256 -or !(Test-Path -LiteralPath $preflight.DisposableFixturePath -PathType Leaf) -or (Get-FileHash -LiteralPath $preflight.DisposableFixturePath -Algorithm SHA256).Hash -ine $preflight.DisposableFixtureSha256){throw 'Canonical source fixture or disposable model hash contract invalid.'};if(!$preparation -and $preflight.DisposableFixtureSha256 -ine $preflight.FixtureSha256){throw 'Canonical fixture/model hash contract invalid without preparation evidence.'};if($preparation){foreach($pair in @(@('RequestPath','RequestSha256'),@('ResultPath','ResultSha256'))){$p=[string]$preparation.($pair[0]);$h=[string]$preparation.($pair[1]);if(!$p -or !$h -or !(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ine $h){throw "Canonical fixture preparation $($pair[0]) hash mismatch."}};if($preparation.AttemptId -cnotmatch '^[A-Fa-f0-9]{32}$' -or $preparation.RunId -cnotmatch '^[A-Fa-f0-9]{32}$' -or $preparation.PreparedModelSha256 -ine $preflight.DisposableFixtureSha256){throw 'Canonical fixture preparation identity/model hash mismatch.'}};if([IO.Path]::GetFullPath($preflight.ValidatedRunnerManifestPath) -ine [IO.Path]::GetFullPath($preflight.RunnerManifest)){throw 'Canonical runner-manifest path contract mismatch before execution.'};if([string]$preflight.ValidatedRunnerManifestSha256 -ine [string]$preflight.RunnerManifestSha256){throw 'Canonical runner-manifest hash contract mismatch before execution.'}
    if ($ExecutionRecordInvoker) {
        $execution = & $ExecutionRecordInvoker $StoreRoot $request.TaskId $preflight
    } else {
        $execution = New-MayaQaExecutionRecord -StoreRoot $StoreRoot -TaskId $request.TaskId -Preflight $preflight
    }
    if (!$execution) { throw 'Canonical execution preparation returned no execution record.' }

    if ($ClaimInvoker) {
        $claimed = & $ClaimInvoker $StoreRoot $request.TaskId 'Tara' $execution
    } else {
        $claimed = Claim-MayaQaExecutionRecord -StoreRoot $StoreRoot -TaskId $request.TaskId -ClaimOwner 'Tara' -Preflight $execution
    }
    if (!$claimed -or [string]::IsNullOrWhiteSpace([string]$claimed.ClaimId)) {
        throw 'Canonical execution claim was not established.'
    }

    if ($NativeCoreInvoker) {
        $result = & $NativeCoreInvoker $StoreRoot $request.TaskId $claimed.ClaimId
    } else {
        $result = Invoke-MayaQaCanonicalNativeCore -StoreRoot $StoreRoot -TaskId $request.TaskId -ClaimId $claimed.ClaimId -Executable (Join-Path 'E:\revit\Revit 2025' 'Revit.exe') -Arguments ''
    }
    [pscustomobject]@{TaskId=$request.TaskId;WorkflowId=$request.WorkflowId;QaWorkflowId=$request.QaWorkflowId;Execution=$execution;Claim=$claimed;Result=$result}
}

function Invoke-MayaQaSingleCanonicalAttempt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$UserRequest,
        [ValidateSet('approve','reject')][string]$ApprovalDecision = 'reject',
        [string]$ApprovalReason = 'Explicit single-attempt QA authorization',
        [string]$SourceBranch = 'current',
        [string]$ProjectPath = 'Forma.RevitConnector.csproj',
        [ValidateSet('Build','FrozenCandidate')][string]$ArtifactMode = 'Build',
        [string]$CandidateDirectory,[string]$CandidateDllPath,
        [string]$ExpectedCandidateSha256,[string]$ExpectedCandidateSourceCommit,[object]$AuthenticatedBuildSource,
        [switch]$StageFrozenCandidateForQa,
        [scriptblock]$DeploymentValidationInvoker,
        [scriptblock]$RequestInvoker,[scriptblock]$ApprovalInvoker,
        [scriptblock]$PreparationInvoker,[scriptblock]$TransactionInvoker,
        [switch]$DryRun
    )
    if($ApprovalDecision -eq 'approve' -and [string]::IsNullOrWhiteSpace($ApprovalReason)){throw 'Approval reason is required.'}
    $request = if($RequestInvoker){& $RequestInvoker $StoreRoot $UserRequest $SourceBranch $ProjectPath}else{
        Invoke-MayaQaRequest -StoreRoot $StoreRoot -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath -ArtifactMode $ArtifactMode -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedCandidateSha256 $ExpectedCandidateSha256 -ExpectedCandidateSourceCommit $ExpectedCandidateSourceCommit -AuthenticatedBuildSource $AuthenticatedBuildSource -StageFrozenCandidateForQa:$StageFrozenCandidateForQa -ValidateExistingDeployment:($ArtifactMode -ceq 'FrozenCandidate') -DeploymentValidationInvoker $DeploymentValidationInvoker -DryRun:$DryRun
    }
    if(!$request){throw 'Canonical request returned no result.'}
    if($request.Stage -eq 'handoff-ready' -or $request.Stage -eq 'execution-ready'){throw 'Single-attempt wrapper received an already-prepared request; refusing to risk reuse.'}
    if($request.Stage -ne 'approval-required'){throw "Expected approval-required state, received '$($request.Stage)' without creating a continuation."}
    if($ApprovalDecision -ne 'approve'){return [pscustomobject]@{Success=$false;Stage='approval-required';TaskId=$request.TaskId;WorkflowId=$request.WorkflowId;RunId=$request.RunId;QaWorkflowId=$request.QaWorkflowId;QaApprovalId=$request.QaApprovalId;AttemptId=$null;NativeRequestCount=0;ReplacementAttemptCreated=$false;Error=$null}}
    $approval = if($ApprovalInvoker){& $ApprovalInvoker $StoreRoot $request.TaskId 'approve' 'user' $ApprovalReason}else{Resolve-RepatoTaskApproval $StoreRoot $request.TaskId 'approve' 'user' $ApprovalReason}
    if(!$approval){throw 'Approval resolution returned no result.'}
    $canonical = if($PreparationInvoker){& $PreparationInvoker $StoreRoot $request.TaskId $request.WorkflowId $request.QaWorkflowId}else{New-MayaQaCanonicalPreparation -StoreRoot $StoreRoot -TaskId $request.TaskId -WorkflowId $request.WorkflowId -QaWorkflowId $request.QaWorkflowId}
    if(!$canonical -or !$canonical.Attempt){throw 'Canonical preparation returned no attempt.'}
    $preparedRequest=[pscustomobject]@{Stage='handoff-ready';TaskId=$request.TaskId;WorkflowId=$request.WorkflowId;QaWorkflowId=$request.QaWorkflowId;RunId=$request.RunId;Handoff=$canonical.Handoff}
    $tx = if($TransactionInvoker){& $TransactionInvoker $preparedRequest $StoreRoot}else{
        Invoke-MayaQaCanonicalTransaction -StoreRoot $StoreRoot -UserRequest $UserRequest -RequestInvoker { param($s,$u,$b,$p) $preparedRequest }
    }
    if(!$tx){throw 'Canonical transaction returned no result.'}
    [pscustomobject]@{Success=$true;Stage='native-started';TaskId=$request.TaskId;WorkflowId=$request.WorkflowId;QaWorkflowId=$request.QaWorkflowId;RunId=$request.RunId;AttemptId=$canonical.Attempt.AttemptId;ClaimId=$tx.Claim.ClaimId;Approval=$approval;Preparation=$canonical;Transaction=$tx;NativeRequestCount=1;ReplacementAttemptCreated=$false;Error=$null}
}
function Invoke-MayaQaBuildExecute {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[string]$SourceBranch='current',[string]$ProjectPath='Forma.RevitConnector.csproj',[object]$AuthenticatedBuildSource,[scriptblock]$BuildProcessRunner,[switch]$DryRun)
    $QaWorkflowId = Resolve-MayaQaWorkflowId $QaWorkflowId
    if ([string]::IsNullOrWhiteSpace($SourceBranch)) { $SourceBranch = 'current' }
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = 'Forma.RevitConnector.csproj' }
    $def = Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ($DryRun) { return [pscustomobject]@{BuildRequestId=('build-' + [guid]::NewGuid().ToString('N'));TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;BuildStatus='planned';SideEffectsPerformed=$false} }
    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if ($workflow.PSObject.Properties.Name -notcontains 'qaBuildRequest' -or !$workflow.qaBuildRequest) { throw 'Persisted Neil build request is missing.' }
    if ($workflow.PSObject.Properties.Name -contains 'qaWorkflowId' -and $workflow.qaWorkflowId -cne $QaWorkflowId) { throw 'QA workflow identity mismatch.' }
    $normalize = {
        param([string]$Value,[string]$Base)
        if([string]::IsNullOrWhiteSpace($Value)){throw 'Persisted build path is empty.'}
        $clean=$Value.Trim().Trim('"') -replace '\\\\','\'
        if([IO.Path]::IsPathRooted($clean)){[IO.Path]::GetFullPath($clean)}else{[IO.Path]::GetFullPath((Join-Path $Base $clean))}
    }
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    if ($workflow.qaBuildRequest.PSObject.Properties.Name -contains 'AuthenticatedBuildSource' -and $workflow.qaBuildRequest.AuthenticatedBuildSource) { $AuthenticatedBuildSource = $workflow.qaBuildRequest.AuthenticatedBuildSource }
    $sourceBoundary = Resolve-MayaQaAuthenticatedBuildSource $AuthenticatedBuildSource
    $root = $sourceBoundary.RepositoryRoot
    $persistedProject = & $normalize ([string]$workflow.qaBuildRequest.ProjectPath) $root
    $requestedProjectInput = & $normalize $ProjectPath $root
    if ($workflow.qaBuildRequest.SourceBranch -cne $SourceBranch -or $persistedProject -ine $requestedProjectInput) { throw 'Build request parameters do not match the persisted request.' }
    $project = $sourceBoundary.ProjectPath
    if ($persistedProject -ine $project -or !(Test-Path -LiteralPath $persistedProject -PathType Leaf)) { throw 'Normalized project path is missing or outside the approved workspace.' }
    $artifact = [IO.Path]::GetFullPath((Join-Path $root 'bin\Release\net8.0-windows\Repato.Revit.dll'))
    $artifactManifest = [IO.Path]::GetFullPath((Join-Path $root 'Repato.addin'))
    $requestedArtifact = if($workflow.qaBuildRequest.PSObject.Properties.Name -contains 'RequestedArtifact') { & $normalize ([string]$workflow.qaBuildRequest.RequestedArtifact) $root } else { $artifact }
    if($requestedArtifact -ine $artifact){throw 'Normalized requested artifact is outside the approved Release artifact path.'}
    $sourceCommit=Get-MayaQaTrustedBuildSourceCommit -RepositoryRoot $root -ProjectPath $persistedProject
    $command = 'dotnet build "' + $project + '" -c Release -p:RevitInstallDir="E:\revit\Revit 2025"'
    if ($DryRun) { return [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus='planned';Command=$command;Configuration='Release';ArtifactPath=$artifact;SideEffectsPerformed=$false} }
    $started = (Get-Date).ToUniversalTime().ToString('O')
    if($BuildProcessRunner){$processResult=& $BuildProcessRunner $project $root}else{Push-Location $root;try{$processResult=[pscustomobject]@{Lines=@(& dotnet build $project -c Release '-p:RevitInstallDir=E:\revit\Revit 2025' 2>&1);ExitCode=$LASTEXITCODE}}finally{Pop-Location}}
    if(!$processResult -or $processResult.PSObject.Properties.Name -notcontains 'Lines' -or $processResult.PSObject.Properties.Name -notcontains 'ExitCode'){throw 'Build process runner returned an invalid result.'}
    $lines=@($processResult.Lines);$exit=[int]$processResult.ExitCode
    $finished = (Get-Date).ToUniversalTime().ToString('O')
    # Count compiler/MSBuild diagnostics only. Summary text such as "0 Error(s)" is not an error diagnostic.
    $warningLines = @($lines | Where-Object { [string]$_ -match '(?i):\s*warning\s+[A-Z]+\d+\b' })
    $errorLines = @($lines | Where-Object { [string]$_ -match '(?i):\s*error\s+[A-Z]+\d+\b' })
    $warningCount = $warningLines.Count
    $errorCount = $errorLines.Count
    $manifestValid=$false
    if(Test-Path -LiteralPath $artifactManifest -PathType Leaf){try{$manifestValid=([xml](Get-Content -LiteralPath $artifactManifest -Raw)).DocumentElement.Name -ceq 'RevitAddIns'}catch{$manifestValid=$false}}
    if ($exit -ne 0 -or $errorCount -gt 0 -or !(Test-Path -LiteralPath $artifact -PathType Leaf) -or !$manifestValid) { $status='failed' } else { $status='succeeded' }
    $data = Read-RepatoTaskStore $StoreRoot; $task = Find-RepatoTask $data $TaskId
    $mutation = @(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        $current | Add-Member -NotePropertyName qaBuildStatus -NotePropertyValue $status -Force
        $current | Add-Member -NotePropertyName qaBuildEvidence -NotePropertyValue ([pscustomobject]@{BuildRequestId=$current.qaBuildRequest.BuildRequestId;StartedUtc=$started;FinishedUtc=$finished;Command=$command;Configuration='Release';SourceCommit=$sourceCommit;ExitCode=$exit;ArtifactPath=$artifact;ArtifactSha256=$(if(Test-Path $artifact){(Get-FileHash $artifact -Algorithm SHA256).Hash}else{$null});ManifestPath=$artifactManifest;ManifestSha256=$(if(Test-Path $artifactManifest){(Get-FileHash $artifactManifest -Algorithm SHA256).Hash}else{$null});BuildStatus=$status;WarningCount=$warningCount;ErrorCount=$errorCount;ErrorLines=$errorLines}) -Force
        return $current
    })[-1]
    if ($status -ne 'succeeded') { throw "Release build failed with exit code $exit." }
    [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus=$status;Command=$command;Configuration='Release';SourceCommit=$mutation.Workflow.qaBuildEvidence.SourceCommit;ExitCode=$exit;ArtifactPath=$artifact;ArtifactSha256=$mutation.Workflow.qaBuildEvidence.ArtifactSha256;ArtifactManifestPath=$artifactManifest;ArtifactManifestSha256=$mutation.Workflow.qaBuildEvidence.ManifestSha256;ManifestPath=$artifactManifest;ManifestSha256=$mutation.Workflow.qaBuildEvidence.ManifestSha256;WarningCount=$warningCount;ErrorCount=$errorCount;WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;SideEffectsPerformed=$true}
}

function Get-MayaQaTrustedBuildSourceCommit {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProjectPath)
    $root=[IO.Path]::GetFullPath($RepositoryRoot);$project=[IO.Path]::GetFullPath($ProjectPath)
    $commit=(& git -C $root rev-parse HEAD 2>$null).Trim();if($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-fA-F]{40}$'){throw 'Trusted build source commit could not be resolved.'}
    $excluded=@('\QaLaunchAgent\','\QaLaunchAgent.ProtocolInteropTests\','\bin\','\obj\')
    $oldErrorAction=$ErrorActionPreference;$ErrorActionPreference='Continue';try{$statusOutput=@(& git -C $root status --porcelain --untracked-files=all 2>&1);$statusExit=$LASTEXITCODE}finally{$ErrorActionPreference=$oldErrorAction};if($statusExit -ne 0){throw 'Build input cleanliness could not be established.'}
    $diagnostics=@($statusOutput|Where-Object {[string]$_ -notmatch '^[ MADRCU?!]{2}\s'});foreach($diagnostic in $diagnostics){if([string]$diagnostic -notmatch '(?i)warning:\s+could not open directory .*QA[/\\]Quarantine[/\\].*Permission denied'){throw 'Build input cleanliness could not be established.'}}
    $dirty=@($statusOutput|Where-Object {[string]$_ -match '^[ MADRCU?!]{2}\s'})
    $inputs=@($dirty|ForEach-Object { $line=[string]$_;if($line.Length -lt 4){return};$path=$line.Substring(3).Trim('"');if($path -match ' -> '){$path=($path -split ' -> ')[-1]};$full=[IO.Path]::GetFullPath((Join-Path $root $path));$isExcluded=$false;foreach($x in $excluded){if($full -match [regex]::Escape($x)){$isExcluded=$true;break}};if(!$isExcluded -and $full -match '(?i)\.(cs|csproj|props|targets|resx)$|(?i)(^|\\)Directory\.Build\.(props|targets)$'){$full}})
    if($inputs.Count){throw ('Dirty build inputs prevent source-commit binding: '+($inputs -join '; '))}
    $commit
}

function Resolve-MayaQaAuthenticatedBuildSource {
    param([object]$AuthenticatedBuildSource)
    $primary=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    if($null -eq $AuthenticatedBuildSource){return [pscustomobject]@{RepositoryRoot=$primary;ProjectPath=[IO.Path]::GetFullPath((Join-Path $primary 'Forma.RevitConnector.csproj'));ExpectedSourceCommit=$null;Isolated=$false}}
    foreach($n in 'RepositoryRoot','ExpectedSourceCommit','ProjectRelativePath'){
        if($AuthenticatedBuildSource.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$AuthenticatedBuildSource.$n)){throw "AuthenticatedBuildSource is missing $n."}
    }
    $root=[IO.Path]::GetFullPath([string]$AuthenticatedBuildSource.RepositoryRoot);$approved=[IO.Path]::GetFullPath('C:\Repato-Autonomous\Worktrees').TrimEnd('\')+'\'
    if(!$root.StartsWith($approved,[StringComparison]::OrdinalIgnoreCase)){throw 'Authenticated build source is outside the approved worktree root.'}
    if([string]$AuthenticatedBuildSource.ExpectedSourceCommit -notmatch '^[0-9a-fA-F]{40}$'){throw 'Authenticated build source commit must be a 40-character SHA.'}
    if(!(Test-Path -LiteralPath $root -PathType Container)){throw 'Authenticated build source worktree is missing.'}
    $cursor=$root;while($cursor -and $cursor -ne [IO.Path]::GetPathRoot($cursor).TrimEnd('\')){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Authenticated build source contains a reparse point.'};$cursor=[IO.Path]::GetDirectoryName($cursor)}
    $top=(& git -C $root rev-parse --show-toplevel 2>$null).Trim();if($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($top) -ine $root){throw 'Authenticated build source is not a Git worktree.'}
    $common=(& git -C $root rev-parse --path-format=absolute --git-common-dir 2>$null).Trim();$primaryGit=[IO.Path]::GetFullPath((Join-Path $primary '.git'));if($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($common) -ine $primaryGit){throw 'Authenticated build source belongs to another repository.'}
    $head=(& git -C $root rev-parse HEAD 2>$null).Trim();if($LASTEXITCODE -ne 0 -or $head -ine [string]$AuthenticatedBuildSource.ExpectedSourceCommit){throw 'Authenticated build source HEAD does not match the requested commit.'}
    $projectRel=([string]$AuthenticatedBuildSource.ProjectRelativePath).TrimStart('\','/');if([IO.Path]::IsPathRooted($projectRel) -or $projectRel -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Authenticated project path must remain relative to the worktree.'}
    $project=[IO.Path]::GetFullPath((Join-Path $root $projectRel));$prefix=$root.TrimEnd('\')+'\';if(!$project.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $project -PathType Leaf)){throw 'Authenticated project path is outside or missing from the worktree.'}
    if((Get-Item -LiteralPath $project -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Authenticated project path is a reparse point.'}
    [pscustomobject]@{RepositoryRoot=$root;ProjectPath=$project;ExpectedSourceCommit=[string]$AuthenticatedBuildSource.ExpectedSourceCommit;Isolated=$true}
}

function Test-MayaQaFrozenCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [string]$CandidateDllPath,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{7,40}$')][string]$ExpectedSourceCommit,
        [Parameter(Mandatory)][string]$QaWorkflowId
    )
    $directory=[IO.Path]::GetFullPath($CandidateDirectory)
    if(!(Test-Path -LiteralPath $directory -PathType Container)){throw 'Frozen candidate directory is missing.'}
    $dll=if([string]::IsNullOrWhiteSpace($CandidateDllPath)){Join-Path $directory 'Repato.Revit.dll'}else{[IO.Path]::GetFullPath($CandidateDllPath)}
    $prefix=$directory.TrimEnd('\')+'\'
    if(!$dll.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Frozen candidate DLL must be inside the candidate directory.'}
    if(!(Test-Path -LiteralPath $dll -PathType Leaf)){throw 'Frozen candidate DLL is missing.'}
    $actual=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    if($actual -ine $ExpectedSha256){throw 'Frozen candidate DLL SHA-256 mismatch.'}
    $provenancePath=Join-Path $directory 'release-manifest.json'
    if(!(Test-Path -LiteralPath $provenancePath -PathType Leaf)){throw 'Frozen candidate provenance is missing.'}
    try{$provenance=Get-Content -LiteralPath $provenancePath -Raw|ConvertFrom-Json}catch{throw 'Frozen candidate provenance is invalid JSON.'}
    foreach($name in 'SourceCommit','FrozenArtifactSha256'){
        if($provenance.PSObject.Properties.Name -notcontains $name -or [string]::IsNullOrWhiteSpace([string]$provenance.$name)){throw "Frozen candidate provenance is missing $name."}
    }
    $source=[string]$provenance.SourceCommit
    if(!$source.StartsWith($ExpectedSourceCommit,[StringComparison]::OrdinalIgnoreCase) -or
       ($ExpectedSourceCommit.Length -eq 40 -and $source -ine $ExpectedSourceCommit)){throw 'Frozen candidate source commit mismatch.'}
    if([string]$provenance.FrozenArtifactSha256 -ine $actual){throw 'Frozen candidate provenance artifact hash mismatch.'}
    if($provenance.PSObject.Properties.Name -notcontains 'SupportedQaWorkflows' -or
       @($provenance.SupportedQaWorkflows|Where-Object{[string]$_ -ceq $QaWorkflowId}).Count -ne 1){throw 'Frozen candidate is not compatible with the requested QA workflow.'}
    $manifestPath=Join-Path $directory 'Repato.addin'
    if(!(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'Frozen candidate add-in manifest is missing.'}
    try{$manifestXml=[xml](Get-Content -LiteralPath $manifestPath -Raw)}catch{throw 'Frozen candidate add-in manifest is invalid XML.'}
    if($manifestXml.DocumentElement.Name -cne 'RevitAddIns'){throw 'Frozen candidate add-in manifest is invalid.'}
    [pscustomobject]@{CandidateDirectory=$directory;ArtifactPath=$dll;ArtifactSha256=$actual;ManifestPath=$manifestPath;ManifestSha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash;ProvenancePath=$provenancePath;ProvenanceSha256=(Get-FileHash -LiteralPath $provenancePath -Algorithm SHA256).Hash;SourceCommit=$source;QaWorkflowId=$QaWorkflowId}
}

function Invoke-MayaQaFrozenCandidateEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$CandidateDirectory,[string]$CandidateDllPath,
        [Parameter(Mandatory)][string]$ExpectedSha256,[Parameter(Mandatory)][string]$ExpectedSourceCommit,[object]$DeploymentEvidence,
        [switch]$DryRun
    )
    $verified=Test-MayaQaFrozenCandidate -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedSha256 -ExpectedSourceCommit $ExpectedSourceCommit -QaWorkflowId $QaWorkflowId
    if($DryRun){return $verified}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($workflow.PSObject.Properties.Name -notcontains 'qaBuildRequest' -or !$workflow.qaBuildRequest){throw 'Persisted Neil build request is missing.'}
    if($workflow.qaWorkflowId -cne $QaWorkflowId){throw 'QA workflow identity mismatch.'}
    if($workflow.PSObject.Properties.Name -notcontains 'qaBuildEvidence' -or $workflow.qaBuildEvidence.PSObject.Properties.Name -notcontains 'SourceCommit' -or [string]::IsNullOrWhiteSpace([string]$workflow.qaBuildEvidence.SourceCommit)){throw 'Source-bound Neil build evidence is required.'}
    if([string]$verified.SourceCommit -cne [string]$workflow.qaBuildEvidence.SourceCommit){throw 'Frozen candidate source commit does not match Neil build evidence.'}
    $now=(Get-Date).ToUniversalTime().ToString('O');$deploymentRunnerManifestPath=if($DeploymentEvidence){$DeploymentEvidence.runnerManifestPath}else{$null};$deploymentRunnerManifestSha256=if($DeploymentEvidence){$DeploymentEvidence.runnerManifestSha256}else{$null};$deploymentValidation=if($DeploymentEvidence){[bool]$DeploymentEvidence.succeeded}else{$false};$deploymentManifestIntegrity=if($DeploymentEvidence){if($DeploymentEvidence.PSObject.Properties.Name -contains 'manifestIntegrityEvidenceAvailable' -and $DeploymentEvidence.manifestIntegrityEvidenceAvailable){[bool]$DeploymentEvidence.manifestIntegrityPassed}else{'Unavailable'}}else{$false};$deploymentIsolation=$null;if($DeploymentEvidence){if($DeploymentEvidence.PSObject.Properties.Name -contains 'Isolation'){$deploymentIsolation=$DeploymentEvidence.Isolation}elseif($DeploymentEvidence.PSObject.Properties.Name -contains 'isolationPassed'){$policy=[IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..\QA') 'MachineWideAddins.allowlist.json'));if(!(Test-Path -LiteralPath $policy -PathType Leaf)){throw 'Canonical QA isolation policy is missing.'};$deploymentIsolation=[pscustomobject]@{PolicyPath=$policy;PolicySha256=(Get-FileHash -LiteralPath $policy -Algorithm SHA256).Hash;Allowed=[bool]$DeploymentEvidence.isolationPassed}}else{throw 'Deployment validation isolation evidence is missing.'};if(!$deploymentIsolation -or $deploymentIsolation.PSObject.Properties.Name -notcontains 'Allowed' -or [string]::IsNullOrWhiteSpace([string]$deploymentIsolation.PolicyPath) -or [string]$deploymentIsolation.PolicySha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Deployment validation isolation evidence is malformed.'};if(!(Test-Path -LiteralPath $deploymentIsolation.PolicyPath -PathType Leaf) -or (Get-FileHash -LiteralPath $deploymentIsolation.PolicyPath -Algorithm SHA256).Hash -ine [string]$deploymentIsolation.PolicySha256){throw 'Deployment validation isolation policy identity is invalid.'};if(!$deploymentIsolation.Allowed){throw 'Deployment validation isolation failed.'}};$deploymentQaIsolation=if($deploymentIsolation){[bool]$deploymentIsolation.Allowed}else{$false};$data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    $mutation=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        $e=[pscustomobject]@{BuildRequestId=$current.qaBuildRequest.BuildRequestId;StartedUtc=$now;FinishedUtc=$now;Command='FrozenCandidate integrity and provenance validation (no compilation)';Configuration='Release';SourceCommit=$current.qaBuildEvidence.SourceCommit;ExitCode=0;ArtifactPath=$verified.ArtifactPath;ArtifactSha256=$verified.ArtifactSha256;ManifestPath=$verified.ManifestPath;ManifestSha256=$verified.ManifestSha256;BuildStatus='succeeded';WarningCount=0;ErrorCount=0;ErrorLines=@();EvidenceSource='FrozenCandidate';CandidateDirectory=$verified.CandidateDirectory;CandidateProvenancePath=$verified.ProvenancePath;CandidateProvenanceSha256=$verified.ProvenanceSha256;CandidateSourceCommit=$verified.SourceCommit;QaWorkflowId=$verified.QaWorkflowId;RunnerManifestPath=$deploymentRunnerManifestPath;RunnerManifestSha256=$deploymentRunnerManifestSha256;DeploymentValidation=$deploymentValidation;ManifestIntegrityValidation=$deploymentManifestIntegrity;QaIsolation=$deploymentQaIsolation;QaAddinRoot=$(if($DeploymentEvidence){$DeploymentEvidence.qaAddinRoot}else{$null});Isolation=$deploymentIsolation}
        $current|Add-Member NoteProperty qaBuildStatus 'succeeded' -Force
        $current|Add-Member NoteProperty qaBuildEvidence $e -Force
        return $current
    })[-1]
    [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus='succeeded';Command='FrozenCandidate integrity and provenance validation (no compilation)';Configuration='Release';ExitCode=0;ArtifactPath=$verified.ArtifactPath;ArtifactSha256=$verified.ArtifactSha256;ArtifactManifestPath=$verified.ManifestPath;ArtifactManifestSha256=$verified.ManifestSha256;ManifestPath=$verified.ManifestPath;ManifestSha256=$verified.ManifestSha256;WarningCount=0;ErrorCount=0;EvidenceSource='FrozenCandidate';CandidateProvenancePath=$verified.ProvenancePath;CandidateProvenanceSha256=$verified.ProvenanceSha256;CandidateSourceCommit=$verified.SourceCommit;WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;SideEffectsPerformed=$true}
}

function Bind-MayaQaFrozenCandidateBuildEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [string]$CandidateDllPath,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{7,40}$')][string]$ExpectedSourceCommit
    )
    $verified=Test-MayaQaFrozenCandidate -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedSha256 -ExpectedSourceCommit $ExpectedSourceCommit -QaWorkflowId $QaWorkflowId
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($workflow.qaWorkflowId -cne $QaWorkflowId){throw 'QA workflow identity mismatch.'}
    if($workflow.PSObject.Properties.Name -notcontains 'qaBuildRequest' -or !$workflow.qaBuildRequest.BuildRequestId){throw 'Persisted Neil build request is missing.'}
    $existing=if($workflow.PSObject.Properties.Name -contains 'qaBuildEvidence'){$workflow.qaBuildEvidence}else{$null}
    if($existing){
        foreach($n in 'BuildRequestId','SourceCommit','ArtifactPath','ArtifactSha256','ManifestPath','ManifestSha256'){
            if([string]$existing.$n -cne [string]$(if($n -eq 'BuildRequestId'){$workflow.qaBuildRequest.BuildRequestId}elseif($n -eq 'SourceCommit'){$verified.SourceCommit}elseif($n -eq 'ArtifactPath'){$verified.ArtifactPath}elseif($n -eq 'ArtifactSha256'){$verified.ArtifactSha256}elseif($n -eq 'ManifestPath'){$verified.ManifestPath}else{$verified.ManifestSha256})){throw "Frozen candidate evidence conflict: $n"}
        }
        return $existing
    }
    $now=(Get-Date).ToUniversalTime().ToString('O');$bound=[pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;StartedUtc=$now;FinishedUtc=$now;Command='FrozenCandidate integrity and provenance validation (no compilation)';Configuration='Release';SourceCommit=$verified.SourceCommit;ExitCode=0;ArtifactPath=$verified.ArtifactPath;ArtifactSha256=$verified.ArtifactSha256;ManifestPath=$verified.ManifestPath;ManifestSha256=$verified.ManifestSha256;BuildStatus='succeeded';WarningCount=0;ErrorCount=0;ErrorLines=@();EvidenceSource='FrozenCandidate';CandidateDirectory=$verified.CandidateDirectory;CandidateProvenancePath=$verified.ProvenancePath;CandidateProvenanceSha256=$verified.ProvenanceSha256;CandidateSourceCommit=$verified.SourceCommit;QaWorkflowId=$verified.QaWorkflowId}
    $mutation=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {param($current)$current|Add-Member NoteProperty qaBuildStatus 'succeeded' -Force;$current|Add-Member NoteProperty qaBuildEvidence $bound -Force;return $current})[-1]
    $mutation.Workflow.qaBuildEvidence
}

function New-MayaQaCanonicalCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$TestId
    )
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($workflow.PSObject.Properties.Name -contains 'qaWorkflowId' -and [string]$workflow.qaWorkflowId -cne $QaWorkflowId){throw 'QA workflow identity mismatch.'}
    if($TestId -cne $QaWorkflowId){throw 'QA test identity mismatch.'}
    if($workflow.PSObject.Properties.Name -notcontains 'qaBuildEvidence' -or $workflow.PSObject.Properties.Name -notcontains 'qaBuildStatus' -or $workflow.qaBuildStatus -cne 'succeeded'){throw 'Successful authenticated Neil build evidence is required.'}
    $e=$workflow.qaBuildEvidence
    foreach($n in 'BuildRequestId','SourceCommit','ArtifactPath','ArtifactSha256','ManifestPath','ManifestSha256'){if($e.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$e.$n)){throw "Authenticated build evidence is missing $n."}}
    if([string]$e.SourceCommit -notmatch '^[A-Fa-f0-9]{40}$' -or [string]$e.ArtifactSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$e.ManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Authenticated build evidence identity or hash is invalid.'}
    $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$artifact=[IO.Path]::GetFullPath([string]$e.ArtifactPath);$expected=[IO.Path]::GetFullPath((Join-Path $repo 'bin\Release\net8.0-windows\Repato.Revit.dll'))
    if($artifact -ine $expected -or [IO.Path]::GetFileName($artifact) -cne 'Repato.Revit.dll'){throw 'Authenticated artifact is not the approved Release Repato.Revit.dll.'}
    if(!(Test-Path -LiteralPath $artifact -PathType Leaf)){throw 'Authenticated Neil artifact is missing.'}
    $actual=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash;if($actual -ine [string]$e.ArtifactSha256){throw 'Authenticated Neil artifact hash mismatch.'}
    $manifest=[IO.Path]::GetFullPath([string]$e.ManifestPath);$expectedManifest=[IO.Path]::GetFullPath((Join-Path $repo 'Repato.addin'))
    if($manifest -ine $expectedManifest -or !(Test-Path -LiteralPath $manifest -PathType Leaf) -or (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -ine [string]$e.ManifestSha256){throw 'Authenticated add-in manifest hash mismatch.'}
    $root=[IO.Path]::GetFullPath((Join-Path $repo 'DeploymentCandidates\AgentBuilds'));$name='ReleaseCandidate-'+([string]$e.SourceCommit).Substring(0,12);$dir=[IO.Path]::GetFullPath((Join-Path $root $name));$prefix=$root.TrimEnd('\')+'\'
    if(!$dir.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($dir) -ne $name){throw 'Canonical candidate path escaped the approved root.'}
    $dll=Join-Path $dir 'Repato.Revit.dll';$addin=Join-Path $dir 'Repato.addin';$prov=Join-Path $dir 'release-manifest.json'
    if(Test-Path -LiteralPath $dir){
        if(!(Test-Path -LiteralPath $dll -PathType Leaf) -or !(Test-Path -LiteralPath $addin -PathType Leaf) -or !(Test-Path -LiteralPath $prov -PathType Leaf)){throw 'Conflicting canonical candidate is incomplete.'}
        $p=try{Get-Content -LiteralPath $prov -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Conflicting canonical candidate provenance is invalid.'}
        if((Get-FileHash $dll -Algorithm SHA256).Hash -ine [string]$e.ArtifactSha256 -or (Get-FileHash $addin -Algorithm SHA256).Hash -ine [string]$e.ManifestSha256 -or [string]$p.SourceCommit -cne [string]$e.SourceCommit -or [string]$p.FrozenArtifactSha256 -ine [string]$e.ArtifactSha256 -or [string]$p.ManifestSha256 -ine [string]$e.ManifestSha256 -or [string]$p.TaskId -cne $TaskId -or [string]$p.WorkflowId -cne $WorkflowId -or [string]$p.QaWorkflowId -cne $QaWorkflowId -or [string]$p.TestId -cne $TestId -or [string]$p.BuildRequestId -cne [string]$e.BuildRequestId){throw 'Conflicting canonical candidate identity or provenance.'}
        return [pscustomobject]@{CandidateDirectory=$dir;CandidateDllPath=$dll;CandidateProvenancePath=$prov;CandidateSourceCommit=$e.SourceCommit;NeilArtifactSha256=$e.ArtifactSha256;CandidateSha256=(Get-FileHash $dll -Algorithm SHA256).Hash;Reused=$true;SideEffectsPerformed=$false}
    }
    $tmp=$dir+'.tmp-'+[guid]::NewGuid().ToString('N');New-Item -ItemType Directory -Path $tmp -Force|Out-Null
    try { Copy-Item -LiteralPath $artifact -Destination (Join-Path $tmp 'Repato.Revit.dll');Copy-Item -LiteralPath $manifest -Destination (Join-Path $tmp 'Repato.addin');$p=[ordered]@{SchemaVersion=1;CandidateType='SyntheticReleaseCandidate';TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;TestId=$TestId;BuildRequestId=$e.BuildRequestId;SourceCommit=$e.SourceCommit;NeilArtifactSha256=$e.ArtifactSha256;ManifestSha256=$e.ManifestSha256;FrozenArtifactSha256=(Get-FileHash (Join-Path $tmp 'Repato.Revit.dll') -Algorithm SHA256).Hash;CandidateDllSha256=(Get-FileHash (Join-Path $tmp 'Repato.Revit.dll') -Algorithm SHA256).Hash;CandidateDirectory=$dir;CandidateDllPath=$dll;SupportedQaWorkflows=@($QaWorkflowId)};$p|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $tmp 'release-manifest.json') -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $dir
    } catch {Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue;throw}
    $candidateHash=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash;if($candidateHash -ine [string]$e.ArtifactSha256){throw 'Created candidate hash mismatch.'}
    [pscustomobject]@{CandidateDirectory=$dir;CandidateDllPath=$dll;CandidateProvenancePath=$prov;CandidateSourceCommit=$e.SourceCommit;NeilArtifactSha256=$e.ArtifactSha256;CandidateSha256=$candidateHash;Reused=$false;SideEffectsPerformed=$true}
}
function Resolve-MayaQaSourceRunnerManifestEvidence {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId)
    $names=@{'create-plan-views-v1'='Repato.CreatePlanViews.TestRunner.addin';'create-levels-elevations-v1'='Repato.CreateLevels.TestRunner.addin';'create-grids-world-axis-v1'='Repato.CreateGrids.TestRunner.addin';'grid-bubble-visibility-v1'='Repato.GridBubbleVisibility.TestRunner.addin';'grid-bubble-offset-v1'='Repato.GridBubbleOffset.TestRunner.addin';'grid-resequence-v1'='Repato.GridResequence.TestRunner.addin'}
    if(!$names.ContainsKey($QaWorkflowId)-or $TestId -cne $QaWorkflowId){throw 'Source runner manifest identity is not compatible with the QA workflow.'}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$e=$workflow.qaBuildEvidence
    foreach($n in 'EvidenceSource','CandidateDirectory','CandidateSourceCommit','ArtifactSha256','CandidateProvenancePath'){if(!$e -or $e.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$e.$n)){throw "Frozen candidate evidence is missing $n."}}
    if([string]$e.EvidenceSource -cne 'FrozenCandidate' -or $workflow.qaBuildStatus -cne 'succeeded'){throw 'Authenticated frozen-candidate evidence is required before source manifest attestation.'}
    $candidate=Test-MayaQaFrozenCandidate -CandidateDirectory $e.CandidateDirectory -ExpectedSha256 $e.ArtifactSha256 -ExpectedSourceCommit $e.CandidateSourceCommit -QaWorkflowId $QaWorkflowId
    if([string]$candidate.SourceCommit -cne [string]$e.CandidateSourceCommit -or [string]$candidate.ArtifactSha256 -ine [string]$e.ArtifactSha256){throw 'Source manifest candidate binding failed.'}
    $qaRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\QA'));$manifest=[IO.Path]::GetFullPath((Join-Path $qaRoot $names[$QaWorkflowId]));$root=$qaRoot.TrimEnd('\')+'\'
    if(!$manifest.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Source runner manifest escaped the approved QA root.'};if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'Trusted source runner manifest is missing.'}
    try{$xml=[xml](Get-Content -LiteralPath $manifest -Raw -ErrorAction Stop)}catch{throw 'Trusted source runner manifest is malformed.'}
    if(@($xml.RevitAddIns.AddIn|Where-Object Type -eq 'Application').Count -ne 1){throw 'Trusted source runner manifest application contract is invalid.'}
    $hash=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash;$data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    $mutation=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {param($current)
        $old=$current.qaBuildEvidence;if($old.PSObject.Properties.Name -contains 'RunnerManifestPath' -and $old.RunnerManifestPath){if([string]$old.RunnerManifestPath -ine $manifest -or [string]$old.RunnerManifestSha256 -ine $hash -or [string]$old.RunnerManifestQaWorkflowId -cne $QaWorkflowId){throw 'Conflicting persisted source runner manifest evidence.'};return $current}
        $old|Add-Member NoteProperty RunnerManifestPath $manifest -Force;$old|Add-Member NoteProperty RunnerManifestSha256 $hash -Force;$old|Add-Member NoteProperty RunnerManifestQaWorkflowId $QaWorkflowId -Force;$old|Add-Member NoteProperty RunnerManifestTestId $TestId -Force;$old|Add-Member NoteProperty RunnerManifestEvidenceStatus 'authenticated-source' -Force;$old|Add-Member NoteProperty DeploymentValidation $false -Force;$current.qaBuildEvidence=$old;return $current
    })[-1]
    $mutation.Workflow.qaBuildEvidence
}
function New-MayaQaPersistedCandidateEvidence {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$e=$w.qaBuildEvidence
    foreach($n in 'CandidateSourceCommit','SourceCommit','CandidateDirectory','ArtifactPath','ArtifactSha256','RunnerManifestPath','RunnerManifestSha256','CandidateProvenancePath'){if(!$e -or $e.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$e.$n)){throw "Authenticated candidate evidence is missing $n."}}
    if($w.qaBuildStatus -cne 'succeeded' -or [string]$e.EvidenceSource -cne 'FrozenCandidate' -or [string]$e.SourceCommit -cne [string]$e.CandidateSourceCommit -or [string]$e.RunnerManifestQaWorkflowId -cne $QaWorkflowId -or [string]$e.RunnerManifestTestId -cne $TestId){throw 'Persisted candidate evidence identity or status is invalid.'}
    $candidate=New-RepatoCandidateEvidence -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -TestId $TestId -CandidateSourceCommit $e.CandidateSourceCommit -CandidateDirectory $e.CandidateDirectory -CandidateDllPath $e.ArtifactPath -CandidateDllSha256 $e.ArtifactSha256 -NeilBuildArtifactSha256 $e.ArtifactSha256 -RunnerManifestPath $e.RunnerManifestPath -RunnerManifestSha256 $e.RunnerManifestSha256 -CandidateProvenancePath $e.CandidateProvenancePath
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\DeploymentCandidates\AgentBuilds'));$runnerRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\QA'))
    $null=Resolve-RepatoCandidateEvidence -Evidence $candidate -AuthenticatedEvidence $candidate -ApprovedCandidateRoot $root -ApprovedRunnerManifestRoot $runnerRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -TestId $TestId
    $candidate
}
function New-MayaQaHandoff {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [switch]$DryRun
    )

    $QaWorkflowId = Resolve-MayaQaWorkflowId $QaWorkflowId
    $definition = Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ($DryRun) {
        return [pscustomobject]@{
            HandoffId = 'handoff-' + [guid]::NewGuid().ToString('N')
            TaskId = $TaskId
            WorkflowId = $WorkflowId
            QaWorkflowId = $QaWorkflowId
            NativeTestId = Get-MayaQaNativeTestId $definition
            HandoffStatus = 'planned'
            SideEffectsPerformed = $false
        }
    }

    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $properties = @($workflow.PSObject.Properties.Name)
    if ($properties -notcontains 'qaBuildRequest' -or $null -eq $workflow.qaBuildRequest) {
        throw 'Completed Neil build request is missing.'
    }
    if ($properties -notcontains 'qaBuildEvidence' -or $properties -notcontains 'qaBuildStatus' -or $workflow.qaBuildStatus -ne 'succeeded' -or $workflow.qaBuildEvidence.PSObject.Properties.Name -notcontains 'SourceCommit' -or [string]::IsNullOrWhiteSpace([string]$workflow.qaBuildEvidence.SourceCommit)) {
        throw 'Successful Neil build execution is required.'
    }
    if ($properties -contains 'qaHandoffId' -and $workflow.qaHandoffId) {
        throw 'Tara QA handoff already exists.'
    }

    $evidence = $workflow.qaBuildEvidence
    if($evidence.PSObject.Properties.Name -contains 'EvidenceSource' -and $evidence.EvidenceSource -ceq 'FrozenCandidate'){
        if([string]::IsNullOrWhiteSpace([string]$evidence.CandidateDirectory) -or [string]::IsNullOrWhiteSpace([string]$evidence.CandidateSourceCommit)){throw 'Frozen candidate handoff evidence is incomplete.'}
        $provenancePath=Join-Path $evidence.CandidateDirectory 'release-manifest.json'
        if(!(Test-Path -LiteralPath $provenancePath -PathType Leaf)){throw 'Frozen candidate handoff provenance is missing.'}
        $provenance=Get-Content -LiteralPath $provenancePath -Raw|ConvertFrom-Json
        $candidate=Test-MayaQaFrozenCandidate -CandidateDirectory $evidence.CandidateDirectory -ExpectedSha256 ([string]$provenance.FrozenArtifactSha256) -ExpectedSourceCommit $evidence.CandidateSourceCommit -QaWorkflowId $QaWorkflowId
        if($candidate.SourceCommit -ine [string]$evidence.CandidateSourceCommit){throw 'Frozen candidate handoff provenance mismatch.'}
        if($evidence.PSObject.Properties.Name -contains 'DeploymentValidation'){
            if([string]::IsNullOrWhiteSpace([string]$evidence.RunnerManifestPath) -or [string]$evidence.RunnerManifestPath -notmatch '\\Repato\.CreatePlanViews\.TestRunner\.addin$' -or [string]$evidence.RunnerManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or !$evidence.DeploymentValidation -or !$evidence.ManifestIntegrityValidation -or !$evidence.QaIsolation){throw 'Validated RepatoQA runner manifest evidence is missing or invalid.'}
            $evidence=[pscustomobject]@{ArtifactPath=$candidate.ArtifactPath;ArtifactSha256=$candidate.ArtifactSha256;ManifestPath=$candidate.ManifestPath;ManifestSha256=$candidate.ManifestSha256;CandidateDirectory=$candidate.CandidateDirectory;CandidateProvenancePath=$candidate.ProvenancePath;CandidateSourceCommit=$candidate.SourceCommit;EvidenceSource='FrozenCandidate';RunnerManifestPath=$evidence.RunnerManifestPath;RunnerManifestSha256=$evidence.RunnerManifestSha256;DeploymentValidation=$evidence.DeploymentValidation;ManifestIntegrityValidation=$evidence.ManifestIntegrityValidation;QaIsolation=$evidence.QaIsolation;QaAddinRoot=$evidence.QaAddinRoot;Isolation=$evidence.Isolation}
        }
    }
    $taskData=Read-RepatoTaskStore $StoreRoot; $task=Find-RepatoTask $taskData $TaskId
    $approvedApproval=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved'})[-1]
    if($null -eq $approvedApproval){throw 'Approved qa-run approval is required before Tara handoff.'}
    foreach ($item in @(
        @('artifact', $evidence.ArtifactPath, $evidence.ArtifactSha256),
        @('manifest', $evidence.ManifestPath, $evidence.ManifestSha256)
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$item[1]) -or !(Test-Path -LiteralPath $item[1] -PathType Leaf)) {
            throw "Built $($item[0]) is missing."
        }
        $actualHash = (Get-FileHash -LiteralPath $item[1] -Algorithm SHA256).Hash
        if ($actualHash -ine [string]$item[2]) {
            throw "Built $($item[0]) hash mismatch."
        }
    }
    $artifactHash = (Get-FileHash -LiteralPath $evidence.ArtifactPath -Algorithm SHA256).Hash
    $manifestHash = (Get-FileHash -LiteralPath $evidence.ManifestPath -Algorithm SHA256).Hash
    $handoffId = 'handoff-' + [guid]::NewGuid().ToString('N')
    if($properties -notcontains 'qaRunId' -or [string]::IsNullOrWhiteSpace([string]$workflow.qaRunId)){throw 'Canonical workflow qaRunId is required before Tara handoff.'}
    $coordinatorRunId = [string]$workflow.qaRunId
    $data = Read-RepatoTaskStore $StoreRoot
    $mutation = @(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        $handoff = [pscustomobject]@{
            HandoffId = $handoffId
            TaskId = $TaskId
            BuildRequestId = $current.qaBuildRequest.BuildRequestId
            ArtifactPath = $evidence.ArtifactPath
            ArtifactSha256 = $artifactHash
            ManifestPath = $evidence.ManifestPath
            ManifestSha256 = $manifestHash
            RunnerManifestPath = $evidence.RunnerManifestPath
            ValidatedRunnerManifestPath = $evidence.RunnerManifestPath
            RunnerManifestSha256 = $evidence.RunnerManifestSha256
            QaAddinRoot = $evidence.QaAddinRoot
            Isolation = $evidence.Isolation
            QaWorkflowId = $QaWorkflowId
            FixtureId = $definition.FixtureId
            NativeTestId = Get-MayaQaNativeTestId $definition
            PreparationScript = $definition.Prep
            ModelPath = $(if($current.PSObject.Properties.Name -contains 'qaModelPath'){$current.qaModelPath}else{$null})
            SidecarPath = $(if($current.PSObject.Properties.Name -contains 'qaSidecarPath'){$current.qaSidecarPath}else{$null})
            CoordinatorRunId = $coordinatorRunId
            HandoffStatus = 'ready'
            QaApprovalId = $approvedApproval.requestId
            QaApprovalStatus = 'approved'
            RequestIntent = $(if($current.PSObject.Properties.Name -contains 'qaRequestIntent'){$current.qaRequestIntent}else{$null})
            CreatedUtc = (Get-Date).ToUniversalTime().ToString('O')
        }
        $current | Add-Member -NotePropertyName qaHandoffId -NotePropertyValue $handoffId -Force
        $current | Add-Member -NotePropertyName qaHandoff -NotePropertyValue $handoff -Force
        $current | Add-Member -NotePropertyName qaApprovalId -NotePropertyValue $approvedApproval.requestId -Force
        $current | Add-Member -NotePropertyName qaApprovalStatus -NotePropertyValue 'approved' -Force
        return $current
    })[-1]
    $handoffPath=Join-Path (Join-Path $StoreRoot 'handoffs') ($handoffId+'.json');New-Item -ItemType Directory -Path (Split-Path $handoffPath -Parent) -Force|Out-Null
    [ordered]@{StoreRoot=$StoreRoot;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;RunId=$workflow.qaRunId;HandoffId=$handoffId;NativeTestId=(Get-MayaQaNativeTestId $definition);QaApprovalId=$approvedApproval.requestId;QaApprovalStatus='approved';ModelPath=$workflow.qaModelPath;SidecarPath=$workflow.qaSidecarPath;ArtifactPath=$evidence.ArtifactPath;ArtifactSha256=$artifactHash;ManifestPath=$evidence.ManifestPath;ManifestSha256=$manifestHash}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $handoffPath -Encoding UTF8
    [pscustomobject]@{
        HandoffId = $handoffId
        TaskId = $TaskId
        WorkflowId = $WorkflowId
        BuildRequestId = $workflow.qaBuildRequest.BuildRequestId
        ArtifactPath = $evidence.ArtifactPath
        ArtifactSha256 = $artifactHash
        ManifestPath = $evidence.ManifestPath
        ManifestSha256 = $manifestHash
        RunnerManifestPath = $evidence.RunnerManifestPath
        ValidatedRunnerManifestPath = $evidence.RunnerManifestPath
        RunnerManifestSha256 = $evidence.RunnerManifestSha256
        QaAddinRoot = $evidence.QaAddinRoot
        Isolation = $evidence.Isolation
        QaWorkflowId = $QaWorkflowId
        FixtureId = $definition.FixtureId
        NativeTestId = Get-MayaQaNativeTestId $definition
        PreparationScript = $definition.Prep
        ModelPath = $(if($properties -contains 'qaModelPath'){$workflow.qaModelPath}else{$null})
        SidecarPath = $(if($properties -contains 'qaSidecarPath'){$workflow.qaSidecarPath}else{$null})
        CoordinatorRunId = $coordinatorRunId
        HandoffStatus = 'ready'
        HandoffPath = $handoffPath
        QaApprovalId = $approvedApproval.requestId
        QaApprovalStatus = 'approved'
        RequestIntent = $(if($properties -contains 'qaRequestIntent'){$workflow.qaRequestIntent}else{$null})
        WorkflowRevision = $mutation.Workflow.workflowRevision
        TaskRevision = $mutation.TaskRevision
        SideEffectsPerformed = $true
    }
}

function Request-MayaQaCanonicalApprovalRefresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$BuildRequestId,[int]$ExpiryMinutes=30
    )
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if([string]$workflow.qaWorkflowId -cne $QaWorkflowId -or [string]$workflow.qaBuildRequest.BuildRequestId -cne $BuildRequestId){throw 'Canonical QA identity mismatch.'}
    $e=$workflow.qaBuildEvidence
    if([string]$workflow.qaBuildStatus -cne 'succeeded' -or !$e -or [string]$e.BuildRequestId -cne $BuildRequestId -or [string]$e.BuildStatus -cne 'succeeded' -or [string]$e.EvidenceSource -cne 'FrozenCandidate'){throw 'Canonical build evidence is invalid.'}
    foreach($n in 'SourceCommit','CandidateSourceCommit','ArtifactSha256','CandidateProvenancePath','RunnerManifestPath','RunnerManifestSha256'){if($e.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$e.$n)){throw "Canonical candidate evidence is missing $n."}}
    if([string]$e.SourceCommit -cne [string]$e.CandidateSourceCommit -or [string]$e.CandidateSourceCommit -notmatch '^[A-Fa-f0-9]{40}$' -or [string]$e.ArtifactSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$e.RunnerManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Canonical candidate evidence identity or hash is invalid.'}
    if(!$e.DeploymentValidation -or !$e.ManifestIntegrityValidation -or !$e.QaIsolation){throw 'Canonical deployment evidence is missing or failed.'}
    $d=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $d $TaskId
    if($task.status -cne 'awaiting-approval' -or $task.workflowStage -cne 'approval'){throw 'Canonical task is not awaiting approval.'}
    if($task.PSObject.Properties.Name -contains 'mayaTaraExecution' -and $task.mayaTaraExecution){throw 'Tara execution has begun.'}
    if($task.PSObject.Properties.Name -contains 'mayaTaraAttempt' -and $task.mayaTaraAttempt){throw 'Tara attempt already exists.'}
    if($task.PSObject.Properties.Name -contains 'taraRuns' -and @($task.taraRuns|Where-Object {$_ -and $_.status -in @('running','passed','completed')}).Count){throw 'Native QA has already begun.'}
    $pending=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
    if($pending.Count -ne 1){throw 'Exactly one pending QA approval is required.'}
    $old=$pending[0];$expired=[DateTimeOffset]::Parse($old.expiresUtc) -le [DateTimeOffset]::UtcNow;$stale=[long]$old.requestedRevision -ne [long]$task.revision
    if(!$expired -and !$stale){throw 'Current QA approval request is still valid.'}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)
        $t=Find-RepatoTask $data $TaskId;$current=@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
        if($current.Count -ne 1){throw 'Approval changed during refresh.'};$current[0].status='superseded';$current[0].reason='Replaced by canonical approval refresh.'
        $q=[pscustomobject]@{requestId=[guid]::NewGuid().ToString('N');action='qa-run';requiredLevel='maya';status='pending';bindingHash='';previousStatus='passed';requestedRevision=[long]0;approvedRevision=$null;requestedUtc=Get-RepatoUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes($ExpiryMinutes).ToString('O');decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null}
        $t.approvalRequests=[object[]]@($t.approvalRequests)+$q;$t.status='awaiting-approval';$t.workflowStage='approval';Add-RepatoHistory $t 'approval-refreshed' 'Maya' 'qa-run';$q.requestedRevision=[long]$t.revision;$t
    }
}

function Repair-MayaQaCanonicalRunIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$ExpectedBuildRequestId,[string]$RuntimeRoot,[string]$FixturePreparationResultPath
    )
    $qaId=Resolve-MayaQaWorkflowId $QaWorkflowId;$w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if([string]$w.qaWorkflowId -cne $qaId -or [string]$w.qaBuildRequest.BuildRequestId -cne $ExpectedBuildRequestId){throw 'Canonical QA identity mismatch.'}
    if([string]$w.qaBuildStatus -cne 'succeeded' -or !$w.qaBuildEvidence -or [string]$w.qaBuildEvidence.BuildRequestId -cne $ExpectedBuildRequestId -or [string]$w.qaBuildEvidence.BuildStatus -cne 'succeeded' -or [string]$w.qaBuildEvidence.EvidenceSource -cne 'FrozenCandidate'){throw 'Canonical build evidence is invalid.'}
    $e=$w.qaBuildEvidence;foreach($n in 'SourceCommit','CandidateSourceCommit','ArtifactPath','ArtifactSha256','CandidateProvenancePath','RunnerManifestPath','RunnerManifestSha256'){if($e.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$e.$n)){throw "Canonical evidence is missing $n."}}
    if([string]$e.SourceCommit -cne [string]$e.CandidateSourceCommit -or [string]$e.CandidateSourceCommit -notmatch '^[A-Fa-f0-9]{40}$' -or [string]$e.ArtifactSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$e.RunnerManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Canonical evidence identity or hash is invalid.'}
    $legacyUnavailable=[string]$e.ManifestIntegrityValidation -ceq 'Unavailable'
    if(!$e.DeploymentValidation -or !$e.QaIsolation -or (!$legacyUnavailable -and $e.ManifestIntegrityValidation -ne $true)){throw 'Canonical staging or deployment evidence is missing or failed.'}
    if($legacyUnavailable){
        if(!(Test-Path -LiteralPath $e.ManifestPath -PathType Leaf) -or (Get-FileHash -LiteralPath $e.ManifestPath -Algorithm SHA256).Hash -ine [string]$e.ManifestSha256){throw 'Legacy manifest integrity evidence is invalid.'}
        if(!(Test-Path -LiteralPath $e.CandidateProvenancePath -PathType Leaf)){throw 'Legacy candidate provenance is missing.'}
        $provenance=Get-Content -LiteralPath $e.CandidateProvenancePath -Raw|ConvertFrom-Json
        $supportedQa=@(if($provenance.PSObject.Properties.Name -contains 'SupportedQaWorkflows'){$provenance.SupportedQaWorkflows})
        $eQa=if($e.PSObject.Properties.Name -contains 'QaWorkflowId'){[string]$e.QaWorkflowId}else{$qaId}
        if([string]$provenance.SourceCommit -cne [string]$e.SourceCommit -or [string]$provenance.FrozenArtifactSha256 -ine [string]$e.ArtifactSha256 -or ($supportedQa.Count -and $eQa -notin $supportedQa)){throw 'Legacy candidate provenance binding is invalid.'}
    }
    $d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId
    if($t.status -cne 'passed' -or $t.workflowStage -cne 'approval'){throw 'Canonical task is not approved for QA run recovery.'}
    $approved=@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved'})
    if($approved.Count -ne 1){throw 'Canonical QA approval is missing or stale.'}
    $approvalRevisionValid=([long]$approved[0].approvedRevision -eq [long]$t.revision)
    $failedPreparationContinuity=([long]$approved[0].approvedRevision -eq ([long]$t.revision-1) -and @($t.history)[-1].event -ceq 'deployment-workflow-mutated' -and @($t.history)[-1].actor -ceq 'Maya')
    if(!$approvalRevisionValid -and !$failedPreparationContinuity){throw 'Canonical QA approval is missing or stale.'}
    if($w.PSObject.Properties.Name -contains 'qaRunId' -and -not [string]::IsNullOrWhiteSpace([string]$w.qaRunId)){throw 'Canonical qaRunId already exists.'}
    if($w.PSObject.Properties.Name -notcontains 'qaHandoff' -or !$w.qaHandoff -or [string]$w.qaHandoffId -cne [string]$w.qaHandoff.HandoffId -or [string]$w.qaHandoff.TaskId -cne $TaskId -or [string]$w.qaHandoff.QaWorkflowId -cne $qaId){throw 'Canonical partial handoff is missing or inconsistent.'}
    if($w.qaHandoff.PSObject.Properties.Name -contains 'WorkflowId'){if([string]::IsNullOrWhiteSpace([string]$w.qaHandoff.WorkflowId) -or [string]$w.qaHandoff.WorkflowId -cne $WorkflowId){throw 'Canonical partial handoff WorkflowId is inconsistent.'}}
    if($w.qaHandoff.PSObject.Properties.Name -contains 'BuildRequestId' -and [string]$w.qaHandoff.BuildRequestId -cne [string]$ExpectedBuildRequestId){throw 'Canonical partial handoff BuildRequestId is inconsistent.'}
    if([string]$w.qaHandoff.ArtifactSha256 -ine [string]$e.ArtifactSha256 -or [string]$w.qaHandoff.ManifestSha256 -ine [string]$e.ManifestSha256 -or [string]$w.qaHandoff.RunnerManifestSha256 -ine [string]$e.RunnerManifestSha256){throw 'Canonical partial handoff evidence is inconsistent.'}
    if([string]$w.qaApprovalId -cne [string]$approved[0].requestId -or [string]$w.qaApprovalStatus -cne 'approved' -or [string]$w.qaHandoff.QaApprovalId -cne [string]$approved[0].requestId){throw 'Canonical partial approval is missing or inconsistent.'}
    if($t.PSObject.Properties.Name -contains 'mayaTaraQaPacket' -or $t.PSObject.Properties.Name -contains 'mayaTaraAttempt' -or $t.PSObject.Properties.Name -contains 'mayaTaraExecution'){throw 'Tara preparation has already begun.'}
    if($t.PSObject.Properties.Name -contains 'nativeAttemptCount' -and [int]$t.nativeAttemptCount -gt 0){throw 'Native QA has already begun.'}
    if($t.PSObject.Properties.Name -contains 'taraRuns' -and @($t.taraRuns|Where-Object {$_ -and $_.status -in @('running','passed','completed')}).Count){throw 'Native QA has already begun.'}
    if($t.PSObject.Properties.Name -contains 'finishedUtc' -and $t.finishedUtc){throw 'Canonical task is terminal.'}
    $runId='MAYA-'+[guid]::NewGuid().ToString('N');New-MayaQaRun -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $qaId -RunId $runId -RuntimeRoot $RuntimeRoot -FixturePreparationResultPath $FixturePreparationResultPath
}

function New-MayaQaCanonicalPreparation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [switch]$DryRun
    )
    $QaWorkflowId=Resolve-MayaQaWorkflowId $QaWorkflowId
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $handoff=if($workflow.PSObject.Properties.Name -contains 'qaHandoff' -and $workflow.qaHandoff){$workflow.qaHandoff}else{New-MayaQaHandoff -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -DryRun:$DryRun}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $runId=[string]$workflow.qaRunId
    if([string]::IsNullOrWhiteSpace($runId)){throw 'Canonical QA run identity is missing.'}
    $attemptId=[guid]::NewGuid().ToString('N')
    $runtimeRoot=[IO.Path]::GetDirectoryName([string]$workflow.qaModelPath)
    $attempt=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$attemptId;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;RunId=$runId;RuntimeRoot=$runtimeRoot;RequestExpiresUtc=[DateTimeOffset]::UtcNow.AddMinutes((Get-MayaQaAttemptDurationMinutes)).ToString('O');Stage='prepared';Success=$false;RequestPath=$null}
    $plan=[pscustomobject][ordered]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;Stage='qa-prepared';ActiveAgent='Maya';NextAgent='Tara';NextOperation='canonical-execution-record';SideEffectsPerformed=$false}
    $packet=[pscustomobject][ordered]@{SchemaVersion='maya-tara-qa-packet-v3';HandoffId=$handoff.HandoffId;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;TestId=$handoff.NativeTestId;RunId=$runId;AttemptId=$attemptId;ArtifactPath=$handoff.ArtifactPath;ArtifactSha256=$handoff.ArtifactSha256;ManifestPath=$handoff.ManifestPath;ManifestSha256=$handoff.ManifestSha256;RunnerManifestPath=$handoff.RunnerManifestPath;RunnerManifestSha256=$handoff.RunnerManifestSha256;ModelPath=$workflow.qaModelPath;SidecarPath=$workflow.qaSidecarPath;FixturePath=(Join-Path (Join-Path (Get-MayaQaRoot) 'Fixtures') (Get-MayaQaWorkflowDefinition $QaWorkflowId).Source);FixtureSha256=$workflow.qaFixtureSha256;DisposableModelSha256=$(if($workflow.PSObject.Properties.Name -contains 'qaDisposableModelSha256'){$workflow.qaDisposableModelSha256}else{$workflow.qaFixtureSha256});FixturePreparationEvidence=$(if($workflow.PSObject.Properties.Name -contains 'qaFixturePreparationEvidence'){$workflow.qaFixturePreparationEvidence}else{$null});RequestExpiresUtc=$attempt.RequestExpiresUtc;Stage='prepared';SideEffectsPerformed=$false;StoreRoot=$StoreRoot}
    if($DryRun){return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;Handoff=$handoff;Attempt=$attempt;Plan=$plan;Packet=$packet;SideEffectsPerformed=$false}}
    $result=Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        $task=Find-RepatoTask $data $TaskId
        foreach($name in 'mayaPlan','mayaTaraQaPacket','mayaTaraAttempt'){if($task.PSObject.Properties.Name -contains $name -and $task.$name){throw "Canonical preparation already contains $name."}}
        $task|Add-Member NoteProperty mayaPlan $plan -Force
        $task|Add-Member NoteProperty mayaTaraQaPacket $packet -Force
        $task|Add-Member NoteProperty mayaTaraAttempt $attempt -Force
        Add-RepatoHistory $task 'maya-tara-canonical-prepared' 'Maya' "workflow=$WorkflowId; handoff=$($handoff.HandoffId); attempt=$attemptId; run=$runId"
        [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;Handoff=$handoff;Attempt=$attempt;Plan=$plan;Packet=$packet;SideEffectsPerformed=$true}
    }
    $result
}
function Get-MayaQaWorkflowStatus { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId; $qaId=if($w.PSObject.Properties.Name -contains 'qaWorkflowId'){$w.qaWorkflowId}else{$null}; $def=if($qaId){Get-MayaQaWorkflowDefinition $qaId}else{$null}
    [pscustomobject]@{WorkflowId=$WorkflowId;TaskId=$TaskId;QaWorkflowId=$qaId;Stage=$w.stage;DeploymentStatus=$w.status;QaRunId=$(if($w.PSObject.Properties.Name -contains 'qaRunId'){$w.qaRunId}else{$null});QaVerificationStatus=$(if($w.PSObject.Properties.Name -contains 'qaVerificationStatus'){$w.qaVerificationStatus}else{$null});QaCompletionStatus=$(if($w.PSObject.Properties.Name -contains 'qaCompletionStatus'){$w.qaCompletionStatus}else{$null});Capabilities=$(if($def){@($def.Capabilities)}else{@()});SupervisedExecutionRequired=$true;RevitLaunchByCoordinator=$false;RealDeploymentByCoordinator=$false;DryRunSupported=$true}
}
function Get-MayaQaRoot { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Source\QA')) }
function Get-MayaQaRuntimeRoot { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Source\QA\TestRuns')) }
function New-MayaQaBootstrap { param([Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$RunId,[string]$StoreRoot,[string]$TaskId,[switch]$DryRun)
    $QaWorkflowId = Resolve-MayaQaWorkflowId $QaWorkflowId
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId
    if($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'Invalid QA run ID.'}
    if(!$StoreRoot){$StoreRoot=Join-Path $env:TEMP ('maya-qa-store-'+[guid]::NewGuid().ToString('N'))}
    $store=[IO.Path]::GetFullPath($StoreRoot);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$store.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){throw 'Bootstrap store must be temporary.'}
    if(!$TaskId){$TaskId='maya-qa-'+[guid]::NewGuid().ToString('N').Substring(0,16)}
    if($DryRun){return [pscustomobject]@{StoreRoot=$store;TaskId=$TaskId;WorkflowId=([guid]::NewGuid().ToString('N'));QaWorkflowId=$QaWorkflowId;RunId=$RunId;SideEffectsPerformed=$false}}
    New-RepatoTask $store $TaskId 'Maya QA fixture workflow' "QA workflow $QaWorkflowId" 'qa/maya-qa-workflow' 'maya'|Out-Null
    Claim-RepatoTask $store $TaskId 'Neil'|Out-Null
    Update-RepatoTask $store $TaskId 'in-progress' 'implementation' 'Neil' $null $null|Out-Null
    Update-RepatoTask $store $TaskId 'in-progress' 'build-checks' 'Neil' $null $null|Out-Null
    Update-RepatoTask $store $TaskId 'passed' 'qa' 'Tara' $null $null|Out-Null
    $null=Request-RepatoTaskApproval $store $TaskId 'qa-run' 'maya';$null=Resolve-RepatoTaskApproval $store $TaskId approve 'Maya' 'Tara QA passed; Maya authorized supervised QA run';$qaData=Read-RepatoTaskStore $store;$qaTask=Find-RepatoTask $qaData $TaskId;$qaApproval=@($qaTask.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved'})[-1];if(!$qaApproval){throw 'QA approval was not persisted.'}
    $target=Join-Path $store 'TargetRoot';New-Item -ItemType Directory -Path $target -Force|Out-Null;$artifact=Join-Path $target 'artifact.bin';$manifest=Join-Path $target 'manifest.addin';Set-Content $artifact 'fixture artifact';Set-Content $manifest 'fixture manifest'
    $nativeTestId=Get-MayaQaNativeTestId $def;$plan=New-DeployPlan $store $TaskId $artifact $manifest -TargetRoot $target;$w=New-DeployWorkflow $store $plan;$d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $TaskId;$w=@(Invoke-RepatoWorkflowMutation $store $TaskId $w.workflowId $w.workflowRevision $t.revision {param($x)$x|Add-Member -NotePropertyName qaWorkflowId -NotePropertyValue $QaWorkflowId -Force;$x|Add-Member -NotePropertyName qaNativeTestId -NotePropertyValue $nativeTestId -Force;$x|Add-Member -NotePropertyName qaRunId -NotePropertyValue $RunId -Force;$x|Add-Member -NotePropertyName qaApprovalId -NotePropertyValue $qaApproval.requestId -Force;$x|Add-Member -NotePropertyName qaApprovalStatus -NotePropertyValue 'approved' -Force;return $x})[-1];$w=$w.Workflow
    [pscustomobject]@{StoreRoot=$store;TaskId=$TaskId;WorkflowId=$w.workflowId;QaWorkflowId=$QaWorkflowId;NativeTestId=(Get-MayaQaNativeTestId $def);RunId=$RunId;Stage=$w.stage;PlanId=$plan.planId;PlanHash=(Get-DeployPlanHash $plan);SideEffectsPerformed=$true}
}
function Assert-MayaQaPath { param([string]$Path,[string]$Root)
    $p=[IO.Path]::GetFullPath($Path); $r=([IO.Path]::GetFullPath($Root)).TrimEnd('\')+'\'
    if (-not $p.StartsWith($r,[StringComparison]::OrdinalIgnoreCase)) { throw "Path is outside approved QA root: $Path" }; $p
}
function New-MayaQaRun { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$RunId,[string]$RuntimeRoot,[string]$FixturePreparationResultPath,[switch]$DryRun)
    $QaWorkflowId = Resolve-MayaQaWorkflowId $QaWorkflowId
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId; if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'Invalid QA run ID.'}
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if ($DryRun) { return [pscustomobject]@{WorkflowId=$WorkflowId;RunId=$RunId;Stage=$w.stage;SideEffectsPerformed=$false} }
    if ($w.PSObject.Properties.Name -notcontains 'qaBuildEvidence' -or $w.PSObject.Properties.Name -notcontains 'qaBuildStatus' -or $w.qaBuildStatus -ne 'succeeded') { throw 'Valid Neil build evidence is required before QA run planning.' }
    foreach($pair in @(@($w.qaBuildEvidence.ArtifactPath,$w.qaBuildEvidence.ArtifactSha256),@($w.qaBuildEvidence.ManifestPath,$w.qaBuildEvidence.ManifestSha256))){if(!(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw 'Neil build evidence hash validation failed.'}}
    $qa=Get-MayaQaRoot; $runs=if([string]::IsNullOrWhiteSpace($RuntimeRoot)){Get-MayaQaRuntimeRoot}else{[IO.Path]::GetFullPath($RuntimeRoot)}; if(!(Test-Path -LiteralPath $runs)){New-Item -ItemType Directory -Path $runs -Force|Out-Null}; $run=[IO.Path]::GetFullPath((Join-Path $runs ($WorkflowId+'-'+$RunId))); $runsPrefix=([IO.Path]::GetFullPath($runs)).TrimEnd('\')+'\'; if(!$run.StartsWith($runsPrefix,[StringComparison]::OrdinalIgnoreCase)){throw "Run path escaped QA runtime root: $run"}
    if (Test-Path -LiteralPath $run) { throw 'QA run directory already exists.' }
    $source=Join-Path (Join-Path $qa 'Fixtures') $def.Source; if (!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Approved fixture missing: $source"}
    $fixtureHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash; $preparation=$null
    if($FixturePreparationResultPath){
        if($QaWorkflowId -cne 'create-plan-views-v1'){throw 'Prepared-fixture provenance is supported only for Create Plan Views.'}
        $prepResultPath=Assert-MayaQaPath $FixturePreparationResultPath (Join-Path $qa 'TestRuns');if(!(Test-Path -LiteralPath $prepResultPath -PathType Leaf)){throw 'Fixture preparation result is missing.'}
        if(!$prepResultPath.EndsWith('.request.json.preparation.json',[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture preparation result path is not a supported canonical result name.'}
        $prepRequestPath=$prepResultPath.Substring(0,$prepResultPath.Length-('.preparation.json'.Length));if(!(Test-Path -LiteralPath $prepRequestPath -PathType Leaf)){throw 'Correlated fixture preparation request is missing.'}
        $prepRequest=Get-Content -LiteralPath $prepRequestPath -Raw|ConvertFrom-Json;$prepResult=Get-Content -LiteralPath $prepResultPath -Raw|ConvertFrom-Json
        $prepRequestHash=(Get-FileHash -LiteralPath $prepRequestPath -Algorithm SHA256).Hash;$prepResultHash=(Get-FileHash -LiteralPath $prepResultPath -Algorithm SHA256).Hash
        foreach($pair in @(@('operation','prepare-disposable-create-plan-views-fixture'),@('taskId',$TaskId),@('workflowId',$WorkflowId))){if([string]$prepRequest.($pair[0]) -cne [string]$pair[1]){throw "Fixture preparation request identity mismatch: $($pair[0])."}}
        if([string]$prepResult.Status -cne 'Passed' -or [string]$prepResult.Operation -cne 'prepare-disposable-create-plan-views-fixture' -or [string]$prepResult.TaskId -cne $TaskId -or [string]$prepResult.WorkflowId -cne $WorkflowId -or [string]$prepResult.AttemptId -cne [string]$prepRequest.AttemptId -or [string]$prepResult.RunId -cne [string]$prepRequest.RunId -or [IO.Path]::GetFullPath([string]$prepResult.ModelPath) -ine [IO.Path]::GetFullPath([string]$prepRequest.modelPath)){throw 'Fixture preparation result identity does not correlate to its request.'}
        if([string]$prepRequest.modelSha256 -ine $fixtureHash -or [string]$prepResult.SourceModelSha256 -ine $fixtureHash -or [string]$prepResult.PreparedModelSha256 -notmatch '^[a-fA-F0-9]{64}$' -or !(Test-Path -LiteralPath $prepRequest.modelPath -PathType Leaf) -or (Get-FileHash -LiteralPath $prepRequest.modelPath -Algorithm SHA256).Hash -ine [string]$prepResult.PreparedModelSha256){throw 'Fixture preparation source/prepared model hash validation failed.'}
        if([IO.Path]::GetFullPath([string]$prepRequest.outputPath) -ine $prepResultPath -or [string]$prepRequest.attemptId -notmatch '^[a-fA-F0-9]{32}$' -or [string]$prepRequest.runId -notmatch '^[a-fA-F0-9]{32}$'){throw 'Fixture preparation request/result path or identity binding failed.'}
        $preparation=[pscustomobject]@{RequestPath=$prepRequestPath;RequestSha256=$prepRequestHash;ResultPath=$prepResultPath;ResultSha256=$prepResultHash;AttemptId=[string]$prepRequest.attemptId;RunId=[string]$prepRequest.runId;SourceSha256=$fixtureHash;PreparedModelPath=[IO.Path]::GetFullPath([string]$prepRequest.modelPath);PreparedModelSha256=[string]$prepResult.PreparedModelSha256}
    }
    New-Item -ItemType Directory -Path $run -Force | Out-Null; $model=Join-Path $run 'model.rvt'; if($preparation){Copy-Item -LiteralPath $preparation.PreparedModelPath -Destination $model}else{Copy-Item -LiteralPath $source -Destination $model}
    $modelHash=(Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash;if($preparation -and $modelHash -ine $preparation.PreparedModelSha256){throw 'Canonical disposable model does not match the prepared-model result hash.'};$sidecar=Join-Path $run 'model.rvt.fixture.json'
    $side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$fixtureHash};if($preparation){$side.preparedModelSha256=$preparation.PreparedModelSha256;$side.fixturePreparationRequestPath=$preparation.RequestPath;$side.fixturePreparationRequestSha256=$preparation.RequestSha256;$side.fixturePreparationResultPath=$preparation.ResultPath;$side.fixturePreparationResultSha256=$preparation.ResultSha256;$side.fixturePreparationAttemptId=$preparation.AttemptId;$side.fixturePreparationRunId=$preparation.RunId}; if($QaWorkflowId -eq 'grid-bubble-visibility-v1' -or $QaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')}; if($QaWorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')}
    $side | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sidecar -Encoding UTF8
    if($WorkflowId -eq 'grid-bubble-visibility-v1'){$check=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json;$expected=@('A','B','C','D','1','2','3','4');if($check.fixtureId -cne 'GridBubbleVisibilityEmpty' -or $check.sourceSha256 -ine $fixtureHash -or (@($check.requiredGridNames)-join '|') -cne ($expected -join '|')){throw 'Grid Bubble Visibility sidecar identity is invalid.'}}    $d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId
    $nativeTestId=Get-MayaQaNativeTestId $def;$m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision { param($x) foreach($v in @(@('qaWorkflowId',$QaWorkflowId),@('qaRunId',$RunId),@('qaModelPath',$model),@('qaSidecarPath',$sidecar),@('qaFixtureId',$def.FixtureId),@('qaFixtureSha256',$fixtureHash),@('qaFixturePreparationEvidence',$preparation),@('qaDisposableModelSha256',$modelHash),@('qaTestId',$nativeTestId),@('qaReportPath',$null),@('qaReportSha256',$null),@('qaEvidence',$null),@('qaVerificationStatus',$null),@('qaCompletionStatus',$null),@('qaCompletedUtc',$null))){$x|Add-Member -NotePropertyName $v[0] -NotePropertyValue $v[1] -Force}; if($x.PSObject.Properties.Name -contains 'qaHandoff' -and $x.qaHandoff){$x.qaHandoff | Add-Member -NotePropertyName ModelPath -NotePropertyValue $model -Force;$x.qaHandoff | Add-Member -NotePropertyName SidecarPath -NotePropertyValue $sidecar -Force}; return $x })[-1]
    [pscustomobject]@{WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;RunId=$RunId;ModelPath=$model;SidecarPath=$sidecar;FixtureId=$def.FixtureId;FixtureSha256=$fixtureHash;ModelSha256=$modelHash;FixturePreparation=$preparation;Stage=$m.Workflow.stage;WorkflowRevision=$m.Workflow.workflowRevision;TaskRevision=$m.TaskRevision;SideEffectsPerformed=$true}
}
function Register-MayaQaReport { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$ReportPath,[string]$ReportRoot,[switch]$DryRun)
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId; $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($DryRun){return [pscustomobject]@{WorkflowId=$WorkflowId;Valid=$false;SideEffectsPerformed=$false}}
    if([string]::IsNullOrWhiteSpace($ReportRoot)){$ReportRoot=Join-Path (Get-MayaQaRuntimeRoot) 'Reports'}else{$ReportRoot=[IO.Path]::GetFullPath($ReportRoot)}
    $report=Assert-MayaQaPath $ReportPath $ReportRoot; if(!(Test-Path -LiteralPath $report -PathType Leaf)){throw 'QA report does not exist.'}
    $j=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
    if($j.TestId -cne (Get-MayaQaNativeTestId $def) -or $j.Status -cne 'Passed' -or $j.RollbackStatus -cne 'RolledBack'){throw 'QA report identity/status failed.'}
    if(!$j.Assertions -or @($j.Assertions|Where-Object {$_.Passed -ne $true}).Count){throw 'QA report contains failed assertions.'}
    if([string]::IsNullOrWhiteSpace([string]$j.DocumentPath) -or ([IO.Path]::GetFullPath($j.DocumentPath) -ine [IO.Path]::GetFullPath($w.qaModelPath))){throw 'QA report model identity failed.'}
    if($j.FixtureId -cne $w.qaFixtureId -or $j.FixtureSha256 -ine $w.qaFixtureSha256){throw 'QA report fixture identity failed.'}
    if([string]::IsNullOrWhiteSpace([string]$j.FinishedUtc)){throw 'QA report timestamp is missing.'};try { if(([DateTimeOffset]::Parse($j.FinishedUtc)) -lt ([DateTimeOffset]::Parse($w.startedUtc))){throw 'QA report is stale.'} } catch { if($_.Exception.Message -eq 'QA report is stale.'){throw}; throw 'QA report timestamp is invalid.' }
    $side=Get-Content -LiteralPath $w.qaSidecarPath -Raw|ConvertFrom-Json; if($side.sourceSha256 -ine $w.qaFixtureSha256){throw 'Fixture sidecar hash mismatch.'}
    $rh=(Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash; $d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId
    $m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision {param($x)$tara=if($x.PSObject.Properties.Name -contains 'qaTaraExecutionEvidence'){$x.qaTaraExecutionEvidence}else{$null};$e=[pscustomobject]@{CoordinatorRunId=$x.qaRunId;NativeRunId=$j.RunId;TestId=$j.TestId;Status=$j.Status;RollbackStatus=$j.RollbackStatus;Assertions=@($j.Assertions).Count;DocumentPath=[IO.Path]::GetFullPath($j.DocumentPath);FixtureId=$j.FixtureId;FixtureSha256=$j.FixtureSha256;RequestIntent=$(if($x.PSObject.Properties.Name -contains 'qaRequestIntent'){$x.qaRequestIntent}else{$null});PromptDetected=$(if($tara){$tara.PromptDetected}else{$null});PromptAction=$(if($tara){$tara.PromptAction}else{$null});ApprovedManifest=$(if($tara){$tara.ApprovedManifest}else{$null});PromptFree=$(if($tara){$tara.PromptFree}else{$null});VerifiedUtc=(Get-Date).ToUniversalTime().ToString('O')};$x|Add-Member -NotePropertyName qaReportPath -NotePropertyValue $report -Force;$x|Add-Member -NotePropertyName qaReportSha256 -NotePropertyValue $rh -Force;$x|Add-Member -NotePropertyName qaEvidence -NotePropertyValue $e -Force;$x|Add-Member -NotePropertyName qaVerificationStatus -NotePropertyValue 'verified' -Force;return $x})[-1]
    [pscustomobject]@{WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;ReportPath=$report;ReportSha256=$rh;Valid=$true;WorkflowRevision=$m.Workflow.workflowRevision;TaskRevision=$m.TaskRevision;SideEffectsPerformed=$true}
}
function Submit-MayaQaReport {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$HandoffId,
        [Parameter(Mandatory)][string]$ReportPath,
        [string]$ReportRoot,
        [switch]$DryRun
    )
    $definition = Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ($DryRun) {
        return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;HandoffId=$HandoffId;ReportPath=$ReportPath;Valid=$false;SubmissionStatus='planned';SideEffectsPerformed=$false}
    }
    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $properties = @($workflow.PSObject.Properties.Name)
    if ($properties -notcontains 'qaHandoff' -or $properties -notcontains 'qaHandoffId' -or $workflow.qaHandoffId -cne $HandoffId) {
        throw 'Tara QA handoff identity is invalid.'
    }
    if ($workflow.qaHandoff.HandoffStatus -cne 'ready' -or $workflow.qaHandoff.QaWorkflowId -cne $QaWorkflowId -or $workflow.qaHandoff.TaskId -cne $TaskId) {
        throw 'Tara QA handoff is not valid for this workflow.'
    }
    foreach ($item in @(
        @('artifact', $workflow.qaHandoff.ArtifactPath, $workflow.qaHandoff.ArtifactSha256),
        @('manifest', $workflow.qaHandoff.ManifestPath, $workflow.qaHandoff.ManifestSha256)
    )) {
        if (!(Test-Path -LiteralPath $item[1] -PathType Leaf)) { throw "Handoff $($item[0]) is missing." }
        if ((Get-FileHash -LiteralPath $item[1] -Algorithm SHA256).Hash -ine [string]$item[2]) { throw "Handoff $($item[0]) hash mismatch." }
    }
    if ($properties -contains 'qaReportPath' -and $workflow.qaReportPath) {
        throw 'QA report has already been submitted.'
    }
    if([string]::IsNullOrWhiteSpace($ReportRoot)){$ReportRoot=Join-Path (Get-MayaQaRuntimeRoot) 'Reports'}else{$ReportRoot=[IO.Path]::GetFullPath($ReportRoot)}
    $reportsRoot = $ReportRoot.TrimEnd('\') + '\'
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    if (!$resolvedReport.StartsWith($reportsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Path is outside approved QA root: $ReportPath" }
    if (!(Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'QA report does not exist.' }
    $result = Register-MayaQaReport $StoreRoot $TaskId $WorkflowId $QaWorkflowId $resolvedReport -ReportRoot $ReportRoot
    [pscustomobject]@{
        TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;HandoffId=$HandoffId
        ReportPath=$result.ReportPath;ReportSha256=$result.ReportSha256;NativeRunId=$workflow.qaRunId
        Valid=$result.Valid;SubmissionStatus='submitted';WorkflowRevision=$result.WorkflowRevision
        TaskRevision=$result.TaskRevision;SideEffectsPerformed=$true
    }
}
function Complete-MayaQaWorkflow { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[switch]$DryRun)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $completion = if($w.PSObject.Properties.Name -contains 'qaCompletionStatus'){[string]$w.qaCompletionStatus}else{$null}
    $verification = if($w.PSObject.Properties.Name -contains 'qaVerificationStatus'){[string]$w.qaVerificationStatus}else{$null}
    if($DryRun){return [pscustomobject]@{WorkflowId=$WorkflowId;QaVerificationStatus=$verification;QaCompletionStatus=$completion;SideEffectsPerformed=$false}}
    if($completion -eq 'completed'){throw 'QA workflow is already completed.'}
    if(($verification -and $verification -ne 'verified') -or !$w.qaEvidence -or $w.qaEvidence.Status -ne 'Passed' -or $w.qaEvidence.RollbackStatus -ne 'RolledBack'){throw 'Verified QA evidence is required.'}
    if(!(Test-Path -LiteralPath $w.qaReportPath -PathType Leaf)){throw 'Verified QA report is missing.'}
    if((Get-FileHash -LiteralPath $w.qaReportPath -Algorithm SHA256).Hash -ine $w.qaReportSha256){throw 'Verified QA report hash changed.'}
    $d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId
    $m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision {param($x)$x|Add-Member -NotePropertyName qaVerificationStatus -NotePropertyValue 'verified' -Force;$x|Add-Member -NotePropertyName qaCompletionStatus -NotePropertyValue 'completed' -Force;$x|Add-Member -NotePropertyName qaCompletedUtc -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('O')) -Force;return $x})[-1]
    $updated=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    [pscustomobject]@{WorkflowId=$WorkflowId;QaVerificationStatus=$updated.qaVerificationStatus;QaCompletionStatus=$updated.qaCompletionStatus;CoordinatorRunId=$updated.qaEvidence.CoordinatorRunId;NativeRunId=$updated.qaEvidence.NativeRunId;WorkflowRevision=$m.Workflow.workflowRevision;TaskRevision=$m.TaskRevision;SideEffectsPerformed=$true}
}
function New-MayaQaReceipt {
    param(
        [Parameter(Mandatory)]
        [string]$StoreRoot,

        [Parameter(Mandatory)]
        [string]$TaskId,

        [Parameter(Mandatory)]
        [string]$WorkflowId,

        [string]$ReportRoot,

        [switch]$DryRun
    )

    $w = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId

    if($DryRun){
        return [pscustomobject]@{
            WorkflowId = $WorkflowId
            SideEffectsPerformed = $false
        }
    }

    $qaId = if(
        $w.PSObject.Properties.Name -contains 'qaWorkflowId'
    ){
        $w.qaWorkflowId
    }
    else {
        $null
    }

    if(!$qaId){
        throw 'QA workflow identity is missing.'
    }

    $def = Get-MayaQaWorkflowDefinition $qaId

    if(
        $w.PSObject.Properties.Name -notcontains 'qaCompletionStatus' -or
        $w.qaCompletionStatus -ne 'completed' -or
        $w.qaVerificationStatus -ne 'verified'
    ){
        throw 'QA workflow is incomplete.'
    }

    if(
        !$w.qaEvidence -or
        $w.qaEvidence.Status -ne 'Passed' -or
        $w.qaEvidence.RollbackStatus -ne 'RolledBack'
    ){
        throw 'QA evidence is incomplete.'
    }

    $build = $w.qaBuildEvidence

    $tara = if(
        $w.PSObject.Properties.Name -contains 'qaTaraExecutionEvidence'
    ){
        $w.qaTaraExecutionEvidence
    }
    else {
        [pscustomobject]@{
            QaRunnerManifestPath = $null
            QaRunnerManifestSha256 = $null
        }
    }

    $artifactPath = $build.ArtifactPath
    $artifactHash = $build.ArtifactSha256
    $artifactManifestPath = $build.ManifestPath
    $artifactManifestHash = $build.ManifestSha256
    $runnerPath = $tara.QaRunnerManifestPath
    $runnerHash = $tara.QaRunnerManifestSha256

    # Verify immutable evidence before reading values from the native report.
    $immutableEvidencePairs = @(
        ,@($artifactPath, $artifactHash)
        ,@($artifactManifestPath, $artifactManifestHash)
        ,@($w.qaReportPath, $w.qaReportSha256)
    )

    if($runnerPath){
        $immutableEvidencePairs += ,@($runnerPath, $runnerHash)
    }

    foreach($pair in $immutableEvidencePairs){
        if(!(Test-Path -LiteralPath $pair[0] -PathType Leaf)){
            throw "Evidence file is missing: $($pair[0])"
        }

        $actualHash = (
            Get-FileHash `
                -LiteralPath $pair[0] `
                -Algorithm SHA256
        ).Hash

        if($actualHash -ine $pair[1]){
            throw "Evidence hash mismatch: $($pair[0])"
        }
    }

    $nativeReport = Get-Content `
        -LiteralPath $w.qaReportPath `
        -Raw |
        ConvertFrom-Json

    if(
        $nativeReport.Status -cne 'Passed' -or
        $nativeReport.RollbackStatus -cne 'RolledBack' -or
        $nativeReport.FixtureSha256 -ine $w.qaFixtureSha256
    ){
        throw 'Native report status, rollback, or fixture identity mismatch.'
    }

    $runtimeModelHash = if(
        $nativeReport.PSObject.Properties.Name -contains 'RuntimeModelSha256' -and
        $nativeReport.RuntimeModelSha256 -match '^[A-Fa-f0-9]{64}$'
    ){
        $nativeReport.RuntimeModelSha256
    }
    else {
        # Compatibility for older QA reports whose runtime model remained
        # byte-identical to the source fixture.
        $w.qaFixtureSha256
    }

    if(!(Test-Path -LiteralPath $w.qaModelPath -PathType Leaf)){
        throw "Evidence file is missing: $($w.qaModelPath)"
    }

    $actualRuntimeModelHash = (
        Get-FileHash `
            -LiteralPath $w.qaModelPath `
            -Algorithm SHA256
    ).Hash

    if($actualRuntimeModelHash -ine $runtimeModelHash){
        throw "Evidence hash mismatch: $($w.qaModelPath)"
    }

    if([string]::IsNullOrWhiteSpace($ReportRoot)){
        $ReportRoot = Join-Path (Get-MayaQaRuntimeRoot) 'Reports'
    }
    else {
        $ReportRoot = [IO.Path]::GetFullPath($ReportRoot)
    }

    if(!(Test-Path -LiteralPath $ReportRoot)){
        New-Item `
            -ItemType Directory `
            -Path $ReportRoot `
            -Force |
            Out-Null
    }

    $receiptPath = Join-Path `
        $ReportRoot `
        ('maya-qa-receipt-' + $w.qaRunId + '.json')

    $base = [ordered]@{
        SchemaVersion = '1'
        TaskId = $TaskId
        DeploymentWorkflowId = $WorkflowId
        QaWorkflowId = $qaId

        QaApprovalId = if(
            $w.PSObject.Properties.Name -contains 'qaApprovalId'
        ){
            $w.qaApprovalId
        }
        else {
            $null
        }

        QaApprovalStatus = if(
            $w.PSObject.Properties.Name -contains 'qaApprovalStatus'
        ){
            $w.qaApprovalStatus
        }
        else {
            $null
        }

        CoordinatorRunId = $w.qaEvidence.CoordinatorRunId
        NativeRunId = $w.qaEvidence.NativeRunId

        ArtifactPath = $artifactPath
        ArtifactSha256 = $artifactHash
        ArtifactManifestPath = $artifactManifestPath
        ArtifactManifestSha256 = $artifactManifestHash

        QaRunnerManifestPath = $runnerPath
        QaRunnerManifestSha256 = $runnerHash

        ManifestPath = $build.ManifestPath
        ManifestSha256 = $build.ManifestSha256

        QaModelPath = $w.qaModelPath
        FixtureSha256 = $w.qaFixtureSha256
        RuntimeModelSha256 = $runtimeModelHash

        QaReportPath = $w.qaReportPath
        QaReportSha256 = $w.qaReportSha256

        ReportStatus = $w.qaEvidence.Status
        AssertionCount = $w.qaEvidence.Assertions
        RollbackStatus = $w.qaEvidence.RollbackStatus
        QaVerificationStatus = $w.qaVerificationStatus
        QaCompletionStatus = $w.qaCompletionStatus
        CompletionTimestamp = $w.qaCompletedUtc

        RequestIntent = if(
            $w.PSObject.Properties.Name -contains 'qaRequestIntent'
        ){
            $w.qaRequestIntent
        }
        else {
            $null
        }

        PromptDetected = $w.qaEvidence.PromptDetected
        PromptAction = $w.qaEvidence.PromptAction
        ApprovedManifest = $w.qaEvidence.ApprovedManifest
        PromptFree = $w.qaEvidence.PromptFree
    }

    $json = $base | ConvertTo-Json -Compress -Depth 12
    $hasher = [Security.Cryptography.SHA256]::Create()

    try {
        $final = (
            [BitConverter]::ToString(
                $hasher.ComputeHash(
                    [Text.Encoding]::UTF8.GetBytes($json)
                )
            )
        ).Replace('-', '')
    }
    finally {
        $hasher.Dispose()
    }

    $receipt = [ordered]@{}

    $base.GetEnumerator() |
        ForEach-Object {
            $receipt[$_.Key] = $_.Value
        }

    $receipt.FinalReceiptSha256 = $final
    $serialized = $receipt | ConvertTo-Json -Compress -Depth 12

    if(Test-Path -LiteralPath $receiptPath){
        $existing = (
            Get-Content `
                -LiteralPath $receiptPath `
                -Raw
        ).Trim()

        if($existing -ne $serialized){
            throw 'Receipt already exists with different evidence.'
        }

        return [pscustomobject]@{
            ReceiptPath = $receiptPath
            FinalReceiptSha256 = $final
            Duplicate = $true
            SideEffectsPerformed = $false
        }
    }

    $serialized |
        Set-Content `
            -LiteralPath $receiptPath `
            -Encoding UTF8

    $data = Read-RepatoTaskStore $StoreRoot
    $task = Find-RepatoTask $data $TaskId

    $mutation = @(
        Invoke-RepatoWorkflowMutation `
            $StoreRoot `
            $TaskId `
            $WorkflowId `
            $w.workflowRevision `
            $task.revision {

            param($current)

            $current |
                Add-Member `
                    -NotePropertyName qaReceiptPath `
                    -NotePropertyValue $receiptPath `
                    -Force

            $current |
                Add-Member `
                    -NotePropertyName qaReceiptSha256 `
                    -NotePropertyValue $final `
                    -Force

            return $current
        }
    )[-1]

    [pscustomobject]@{
        ReceiptPath = $receiptPath
        FinalReceiptSha256 = $final
        Duplicate = $false
        WorkflowRevision = $mutation.Workflow.workflowRevision
        TaskRevision = $mutation.TaskRevision
        SideEffectsPerformed = $true
    }
}
function Get-MayaQaBuildEvidenceStatus {
    param([object]$Workflow)
    if ($Workflow.PSObject.Properties.Name -notcontains 'qaBuildEvidence' -or $Workflow.PSObject.Properties.Name -notcontains 'qaBuildStatus' -or $Workflow.qaBuildStatus -ne 'succeeded') { throw 'Neil build evidence is missing or failed.' }
    $e = $Workflow.qaBuildEvidence
    $checks = @()
    foreach ($pair in @(@('Artifact',$e.ArtifactPath,$e.ArtifactSha256),@('Manifest',$e.ManifestPath,$e.ManifestSha256))) {
        $valid = Test-Path -LiteralPath $pair[1] -PathType Leaf
        if ($valid) { $valid = (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2] }
        $checks += [pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$valid}
        if (-not $valid) { throw "Neil build evidence hash mismatch: $($pair[0])" }
    }
    [pscustomobject]@{BuildStatus=$Workflow.qaBuildStatus;ArtifactPath=$e.ArtifactPath;ArtifactSha256=$e.ArtifactSha256;ManifestPath=$e.ManifestPath;ManifestSha256=$e.ManifestSha256;SourceBranch=$e.SourceBranch;CommitId=$e.CommitId;HashVerification=$checks}
}function Get-MayaQaReceiptStatus { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[switch]$DryRun)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;if($DryRun){return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;SideEffectsPerformed=$false}}
    if($w.PSObject.Properties.Name -notcontains 'qaReceiptPath' -or [string]::IsNullOrWhiteSpace([string]$w.qaReceiptPath)){throw 'QA receipt is missing.'}
    $receiptPath=[IO.Path]::GetFullPath($w.qaReceiptPath);if(!(Test-Path -LiteralPath $receiptPath -PathType Leaf)){throw 'QA receipt is missing.'};$receipt=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
    if($receipt.TaskId -cne $TaskId -or $receipt.DeploymentWorkflowId -cne $WorkflowId -or $receipt.QaWorkflowId -cne $QaWorkflowId){throw 'QA receipt identity mismatch.'}
    $stored=$receipt.FinalReceiptSha256;$copy=[ordered]@{};$receipt.PSObject.Properties|Where-Object Name -ne 'FinalReceiptSha256'|ForEach-Object{$copy[$_.Name]=$_.Value};$json=$copy|ConvertTo-Json -Compress -Depth 12;$h=[Security.Cryptography.SHA256]::Create();try{$computed=([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$h.Dispose()};if($computed -ine $stored -or ($w.PSObject.Properties.Name -contains 'qaReceiptSha256' -and $w.qaReceiptSha256 -ine $stored)){throw 'QA receipt hash mismatch.'}
    $modelExpectedHash=if($receipt.PSObject.Properties.Name -contains 'RuntimeModelSha256' -and $receipt.RuntimeModelSha256 -match '^[A-Fa-f0-9]{64}$'){$receipt.RuntimeModelSha256}else{$receipt.FixtureSha256}
    $checks=@();foreach($pair in @(@('Artifact',$receipt.ArtifactPath,$receipt.ArtifactSha256),@('Manifest',$receipt.ManifestPath,$receipt.ManifestSha256),@('Model',$receipt.QaModelPath,$modelExpectedHash),@('Report',$receipt.QaReportPath,$receipt.QaReportSha256))){$ok=Test-Path -LiteralPath $pair[1] -PathType Leaf;if($ok){$ok=(Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2]};$checks+=[pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$ok};if(!$ok){throw "$($pair[0]) hash verification failed."}}
    [pscustomobject]@{ReceiptStatus='Valid';TaskId=$receipt.TaskId;WorkflowId=$receipt.DeploymentWorkflowId;QaWorkflowId=$receipt.QaWorkflowId;RequestIntent=$receipt.RequestIntent;CoordinatorRunId=$receipt.CoordinatorRunId;NativeRunId=$receipt.NativeRunId;ReportStatus=$receipt.ReportStatus;RollbackStatus=$receipt.RollbackStatus;QaVerificationStatus=$receipt.QaVerificationStatus;QaCompletionStatus=$receipt.QaCompletionStatus;CompletionTimestamp=$receipt.CompletionTimestamp;ReceiptSha256=$stored;ReceiptHashValid=$true;ReferencedHashes=$checks;SideEffectsPerformed=$false}
}
function Get-MayaQaDashboard { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[switch]$DryRun)
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId;$catalog=Get-MayaQaWorkflowCatalog
    if($DryRun){return [pscustomobject]@{Catalog=$catalog;SelectedWorkflowId=$QaWorkflowId;CapabilityFlags=$def.Capabilities;DeploymentWorkflowStatus='unread';QaApprovalStatus='unread';QaPlanStatus='unread';ReportVerificationStatus='unread';QaCompletionStatus='unread';ReceiptStatus='unread';SideEffectsPerformed=$false}}
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$plan=Get-DeployWorkflowPlan $StoreRoot $TaskId $WorkflowId;$plan.artifactPath=$w.qaBuildEvidence.ArtifactPath;$plan.artifactSha256=$w.qaBuildEvidence.ArtifactSha256;$plan.manifestPath=$w.qaBuildEvidence.ManifestPath;$plan.manifestSha256=$w.qaBuildEvidence.ManifestSha256
    $hashes=@();foreach($pair in @(@('Artifact',$plan.artifactPath,$plan.artifactSha256),@('Manifest',$plan.manifestPath,$plan.manifestSha256))){$ok=Test-Path -LiteralPath $pair[1] -PathType Leaf;if($ok){$ok=(Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2]};$hashes+=[pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$ok};if(!$ok){throw "$($pair[0]) hash verification failed."}}
    $taraEvidence=if($w.PSObject.Properties.Name -contains 'qaTaraExecutionEvidence'){$w.qaTaraExecutionEvidence}else{[pscustomobject]@{QaRunnerManifestPath=$null;QaRunnerManifestSha256=$null}};$runnerOk=$true;if($taraEvidence.QaRunnerManifestPath){$runnerOk=Test-Path -LiteralPath $taraEvidence.QaRunnerManifestPath -PathType Leaf;if($runnerOk){$runnerOk=(Get-FileHash -LiteralPath $taraEvidence.QaRunnerManifestPath -Algorithm SHA256).Hash -ieq $taraEvidence.QaRunnerManifestSha256}};$hashes+=[pscustomobject]@{Name='QaRunnerManifest';Path=$taraEvidence.QaRunnerManifestPath;ExpectedSha256=$taraEvidence.QaRunnerManifestSha256;Valid=$runnerOk};if(!$runnerOk -and $w.qaCompletionStatus -eq 'completed'){throw 'QA runner manifest hash verification failed.'}
    $qaFields=@('qaModelPath','qaFixtureSha256','qaReportPath','qaReportSha256');foreach($n in $qaFields){if($w.PSObject.Properties.Name -notcontains $n){$hashes+=[pscustomobject]@{Name=$n;Valid=$false};continue}}
    if($w.PSObject.Properties.Name -contains 'qaModelPath'){$dashboardModelHash=$w.qaFixtureSha256;if(Test-Path -LiteralPath $w.qaReportPath -PathType Leaf){$dashboardReport=Get-Content -LiteralPath $w.qaReportPath -Raw|ConvertFrom-Json;if($dashboardReport.PSObject.Properties.Name -contains 'RuntimeModelSha256' -and $dashboardReport.RuntimeModelSha256 -match '^[A-Fa-f0-9]{64}$'){$dashboardModelHash=$dashboardReport.RuntimeModelSha256}};$qaPairs=@(@('Model',$w.qaModelPath,$dashboardModelHash),@('Report',$w.qaReportPath,$w.qaReportSha256));foreach($pair in $qaPairs){$ok=Test-Path -LiteralPath $pair[1] -PathType Leaf;if($ok){$ok=(Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2]};$hashes+=[pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$ok};if(!$ok -and $w.qaCompletionStatus -eq 'completed'){throw "$($pair[0]) hash verification failed."}}}
    $receiptStatus='Missing';if($w.PSObject.Properties.Name -contains 'qaReceiptPath' -and $w.qaReceiptPath){$receipt=Get-MayaQaReceiptStatus $StoreRoot $TaskId $WorkflowId $QaWorkflowId;$receiptStatus='Valid'}elseif($w.PSObject.Properties.Name -contains 'qaCompletionStatus' -and $w.qaCompletionStatus -eq 'completed'){throw 'Completed QA workflow is missing its receipt.'}
    [pscustomobject]@{Catalog=$catalog;SelectedWorkflowId=$QaWorkflowId;CapabilityFlags=$def.Capabilities;RequestIntent=$(if($w.PSObject.Properties.Name -contains 'qaRequestIntent'){$w.qaRequestIntent}else{$null});DeploymentWorkflowStatus=$w.status;QaApprovalStatus=$(if($w.PSObject.Properties.Name -contains 'qaApprovalStatus'){$w.qaApprovalStatus}else{$null});QaPlanStatus=$w.stage;ReportVerificationStatus=$(if($w.PSObject.Properties.Name -contains 'qaVerificationStatus'){$w.qaVerificationStatus}else{$null});QaCompletionStatus=$(if($w.PSObject.Properties.Name -contains 'qaCompletionStatus'){$w.qaCompletionStatus}else{$null});ReceiptStatus=$receiptStatus;CoordinatorRunId=$(if($w.PSObject.Properties.Name -contains 'qaEvidence'){$w.qaEvidence.CoordinatorRunId}else{$null});NativeRunId=$(if($w.PSObject.Properties.Name -contains 'qaEvidence'){$w.qaEvidence.NativeRunId}else{$null});HashVerification=$hashes;CompletionTimestamp=$(if($w.PSObject.Properties.Name -contains 'qaCompletedUtc'){$w.qaCompletedUtc}else{$null});SideEffectsPerformed=$false}
}
function Invoke-MayaQaOverview { param([Parameter(Mandatory)][ValidateSet('qa-catalog-dry-run','qa-status','qa-receipt-status','qa-dashboard')][string]$Route,[string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$QaWorkflowId,[switch]$DryRun)
    $result=switch($Route){'qa-catalog-dry-run'{Get-MayaQaCatalogDryRun $WorkflowId};'qa-status'{Get-MayaQaWorkflowStatus $StoreRoot $TaskId $WorkflowId};'qa-receipt-status'{Get-MayaQaReceiptStatus $StoreRoot $TaskId $WorkflowId $QaWorkflowId -DryRun:$DryRun};'qa-dashboard'{Get-MayaQaDashboard $StoreRoot $TaskId $WorkflowId $QaWorkflowId -DryRun:$DryRun}}
    [pscustomobject]@{Operation=$Route;TimestampUtc=(Get-Date).ToUniversalTime().ToString('O');WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;ResultStatus='ok';SideEffectsPerformed=$false;Result=$result}
}
Export-ModuleMember -Function Prepare-MayaQaCanonicalLaunchPhase,Start-MayaQaCanonicalProcessPhase,Accept-MayaQaCanonicalEvidencePhase,Verify-MayaQaCanonicalRollbackPhase,Verify-MayaQaCanonicalExecutionPhase
Export-ModuleMember -Function Wait-MayaQaCanonicalResultPhase,Complete-MayaQaCanonicalExecutionPhase
Export-ModuleMember -Function Invoke-MayaQaTaraExecute,Resolve-MayaQaRequestWorkflow,Resolve-MayaQaWorkflowId,Resolve-MayaQaTaskStoreIdentity,New-MayaQaExecutionRecord,Claim-MayaQaExecutionRecord,Prepare-MayaQaCanonicalNativeLaunch,Invoke-MayaQaCanonicalNativeCore,Get-MayaQaAttemptDurationMinutes,Recover-MayaQaExpiredExecutionRecord,Recover-MayaQaTerminalLaunchFailure,Recover-MayaQaAbandonedNativeExecution,Repair-MayaQaPreparedExecutionLifecycle,Get-MayaQaCanonicalNativeResult,Resume-MayaQaCanonicalExecution,Get-MayaQaNativeTestId,Invoke-MayaQaRequest,New-MayaQaPersistentPreBuildRequest,Invoke-MayaQaCanonicalTransaction,Invoke-MayaQaSingleCanonicalAttempt,Get-MayaQaWorkflowDefinition,Get-MayaQaWorkflowCatalog,Get-MayaQaCatalogDryRun,Get-MayaQaWorkflowStatus,Invoke-MayaQaIntake,New-MayaQaBuildRequest,New-MayaQaCandidateReplacementBuildRequest,Invoke-MayaQaBuildExecute,New-MayaQaHandoff,Submit-MayaQaReport,Get-MayaQaDashboard,Invoke-MayaQaOverview,New-MayaQaBootstrap,New-MayaQaRun,Register-MayaQaReport,Complete-MayaQaWorkflow,New-MayaQaReceipt,Get-MayaQaReceiptStatus
Export-ModuleMember -Function Recover-MayaQaInvalidNativeClaim
Export-ModuleMember -Function Recover-MayaQaCorrelatedNativeFailure
Export-ModuleMember -Function Prepare-MayaQaAfterExpiredFailureRecovery
Export-ModuleMember -Function Complete-MayaQaTerminalLaunchFailureCleanup
Export-ModuleMember -Function Complete-MayaQaRunnerStartupFailureReconciliation
Export-ModuleMember -Function Complete-MayaQaPreAttemptOrphanRuntimeCleanup
Export-ModuleMember -Function Complete-MayaQaPreparedAttemptCleanup
Export-ModuleMember -Function Archive-MayaQaUnlaunchedPreparedExecution
Export-ModuleMember -Function Invoke-MayaQaLaunchAgentHealth,Invoke-MayaQaLaunchAgentPreflightReadonly,Invoke-MayaQaLaunchAgentFrozenCandidateStaging,Invoke-MayaQaLaunchAgentDeploymentValidation
Export-ModuleMember -Function New-MayaQaDeploymentValidationOperation,Continue-MayaQaDeploymentValidation,Abandon-MayaQaUnresolvedDeploymentValidation,Fail-MayaQaBoundDeploymentValidationWithoutResponse
Export-ModuleMember -Function Set-MayaQaDeploymentValidationOutcomeUnknown
Export-ModuleMember -Function New-MayaQaPersistedCandidateEvidence
Export-ModuleMember -Function Invoke-MayaQaCanonicalFrozenCandidateStagingValidation
Export-ModuleMember -Function Normalize-MayaQaDeploymentValidationResponse
Export-ModuleMember -Function Test-MayaQaFrozenCandidate,New-MayaQaCanonicalCandidate,Invoke-MayaQaFrozenCandidateEvidence,Get-MayaQaTrustedBuildSourceCommit,Resolve-MayaQaAuthenticatedBuildSource
Export-ModuleMember -Function New-MayaQaCanonicalPreparation
Export-ModuleMember -Function Request-MayaQaCanonicalApprovalRefresh
Export-ModuleMember -Function Repair-MayaQaCanonicalRunIdentity

function Accept-MayaQaLegacyManifestAttestation {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId,[Parameter(Mandatory)][string]$EvidencePath,[Parameter(Mandatory)][string]$EvidenceSha256,[scriptblock]$StoreMutationBoundary)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$r=$task.mayaTaraExecution
    if(!$r -or $r.Stage -cne 'executing' -or $r.ExecutionStatus -cne 'Executing' -or $r.ClaimOwner -cne 'Tara' -or $r.ClaimId -cne $ClaimId){throw 'Legacy attestation execution is not eligible.'}
    if($r.SideEffectsPerformed -or $r.VerificationStatus -ceq 'Verified' -or $r.CompletionStatus -ceq 'Completed' -or $r.VerifiedUtc -or $r.CompletedUtc){throw 'Legacy attestation execution is terminal or has side effects.'}
    $epProp=$r.PSObject.Properties['EvidencePath'];$ehProp=$r.PSObject.Properties['EvidenceSha256'];if(($epProp -and $epProp.Value) -or ($ehProp -and $ehProp.Value)){throw 'Legacy attestation evidence already exists.'}
    if(!(Test-Path -LiteralPath $EvidencePath -PathType Leaf)){throw 'Legacy attestation evidence is missing.'};if((Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash -ine $EvidenceSha256){throw 'Legacy attestation evidence hash mismatch.'}
    try{$e=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json}catch{throw 'Legacy attestation evidence is malformed.'}
    foreach($n in @('EvidenceVersion','ValidationStatus','TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','CanonicalRunId','ClaimId','NativeRunId','DeployedRunnerManifestPath','DeployedRunnerManifestSha256','IsolationPolicySha256','ValidatedUtc')){if($e.PSObject.Properties.Name -notcontains $n){throw "Legacy attestation evidence is missing: $n"}}
    if([int]$e.EvidenceVersion -ne 1 -or [string]$e.ValidationStatus -cne 'Passed'){throw 'Legacy attestation evidence did not pass validation.'}
    foreach($n in @('TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','ClaimId')){if([string]$e.$n -cne [string]$r.$n){throw "Legacy attestation identity mismatch: $n"}}
    if([string]$e.CanonicalRunId -cne [string]$r.RunId -or [string]$e.DeployedRunnerManifestPath -cne [string]$r.RunnerManifestPath -or [string]$e.DeployedRunnerManifestSha256 -ine [string]$r.RunnerManifestSha256 -or [string]$e.IsolationPolicySha256 -ine [string]$r.IsolationPolicySha256){throw 'Legacy attestation manifest identity or hash mismatch.'}
    try{$null=[DateTimeOffset]::Parse([string]$e.ValidatedUtc)}catch{throw 'Legacy attestation timestamp is invalid.'}
    $resultPath=$r.RequestPath+'.result.json';if(!(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'Legacy attestation native result is missing.'};try{$receipt=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json}catch{throw 'Legacy attestation native result is malformed.'}
    if([string]$receipt.RequestId -cne [string]$r.RunId -or [string]$receipt.Status -cne 'Failed' -or [string]$receipt.RunId -cne [string]$e.NativeRunId -or [string]::IsNullOrWhiteSpace([string]$receipt.ReportPath)){throw 'Legacy attestation native result correlation failed.'}
    if(!(Test-Path -LiteralPath $receipt.ReportPath -PathType Leaf)){throw 'Legacy attestation native report is missing.'};try{$report=Get-Content -LiteralPath $receipt.ReportPath -Raw|ConvertFrom-Json}catch{throw 'Legacy attestation native report is malformed.'}
    if([string]$report.RunId -cne [string]$e.NativeRunId -or [string]$report.TestId -cne [string]$r.TestId -or [string]$report.Status -cne 'Failed'){throw 'Legacy attestation native report correlation failed.'}
    $oldAttempt=[string]$r.AttemptId;$oldRun=[string]$r.RunId;$oldClaim=[string]$r.ClaimId
    $cas={param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;$xEp=$x.PSObject.Properties['EvidencePath'];$xEh=$x.PSObject.Properties['EvidenceSha256'];if($x.Stage -cne 'executing' -or $x.ExecutionStatus -cne 'Executing' -or $x.AttemptId -cne $oldAttempt -or $x.RunId -cne $oldRun -or $x.ClaimId -cne $oldClaim -or ($xEp -and $xEp.Value) -or ($xEh -and $xEh.Value)){throw 'Legacy attestation compare-and-swap failed.'};$x|Add-Member NoteProperty EvidencePath $EvidencePath -Force;$x|Add-Member NoteProperty EvidenceSha256 $EvidenceSha256 -Force;$x}
    if($StoreMutationBoundary){& $StoreMutationBoundary $StoreRoot $cas}else{Invoke-RepatoStoreMutation $StoreRoot $cas}
    [pscustomobject]@{TaskId=$TaskId;ClaimId=$ClaimId;EvidencePath=$EvidencePath;EvidenceSha256=$EvidenceSha256;Accepted=$true}
}
Export-ModuleMember -Function Accept-MayaQaLegacyManifestAttestation
Export-ModuleMember -Function Accept-MayaQaPreparedManifestAttestation
