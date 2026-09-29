Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -WarningAction SilentlyContinue
. (Join-Path $PSScriptRoot 'MayaQa.TaraExecution.ps1')
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
    $record=[ordered]@{SchemaVersion='maya-tara-execution-v1';TaskId=$resolved.SelectedTaskId;WorkflowId=$resolved.SelectedWorkflowId;QaWorkflowId=$resolved.SelectedQaWorkflowId;TestId=$Preflight.TestId;HandoffId=$resolved.SelectedHandoffId;AttemptId=$resolved.SelectedAttemptId;RunId=$resolved.SelectedRunId;ArtifactPath=$Preflight.ArtifactPath;ArtifactSha256=$Preflight.ArtifactSha256;RunnerManifestPath=$Preflight.RunnerManifest;RunnerManifestSha256=$Preflight.RunnerManifestSha256;AuthoritativeFixturePath=$Preflight.FixturePath;AuthoritativeFixtureSha256=$Preflight.FixtureSha256;DisposableRuntimeRoot=([IO.Path]::GetDirectoryName($Preflight.DisposableFixturePath));DisposableModelPath=$Preflight.DisposableFixturePath;DisposableModelSha256=$Preflight.DisposableFixtureSha256;IsolationPolicyPath=$Preflight.Isolation.PolicyPath;IsolationPolicySha256=$Preflight.Isolation.PolicySha256;IsolationAllowed=[bool]$Preflight.Isolation.Allowed;ClaimOwner=$null;ClaimId=$null;ClaimedUtc=$null;ClaimStatus='unclaimed';Stage='prepared';ExecutionStatus='Prepared';PreparedUtc=Get-RepatoUtc;LaunchingUtc=$null;LaunchedUtc=$null;ExecutingUtc=$null;EvidenceCollectedUtc=$null;RollbackStartedUtc=$null;RollbackVerifiedUtc=$null;VerifiedUtc=$null;CompletedUtc=$null;FailedUtc=$null;NativeProcessId=$null;RequestPath=$null;ResultPath=$null;ReportPath=$null;EvidencePath=$null;ReceiptPath=$null;RollbackStatus='Required';VerificationStatus='Pending';CompletionStatus='Pending';FailureCode=$null;FailureDetails=$null;TaskRevisionAtPrepare=$null;TaskRevisionAtClaim=$null;SideEffectsPerformed=$false}
    if($DryRun){$record.SideEffectsPerformed=$false;return [pscustomobject]$record}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$existing=if($task.PSObject.Properties.Name -contains 'mayaTaraExecution'){$task.mayaTaraExecution}else{$null};if($existing){Assert-MayaQaExecutionIdentity $existing $resolved;if($existing.Stage -cne 'prepared' -or $existing.ExecutionStatus -cne 'Prepared'){throw 'Existing Maya Tara execution is not reusable.'};foreach($n in 'ArtifactSha256','RunnerManifestSha256','AuthoritativeFixtureSha256','DisposableModelSha256'){if([string]$existing.$n -cne [string]$record.$n){throw "Existing execution hash mismatch: $n"}};return $existing};$record.TaskRevisionAtPrepare=[long]$task.revision;$task|Add-Member NoteProperty mayaTaraExecution ([pscustomobject]$record) -Force;Add-RepatoHistory $task 'maya-tara-execution-prepared' 'Maya' "attempt=$($record.AttemptId); run=$($record.RunId)";$task.mayaTaraExecution} -DryRun:$DryRun
}
function Claim-MayaQaExecutionRecord {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimOwner,[Parameter(Mandatory)][object]$Preflight)
    if($ClaimOwner -cne 'Tara'){throw 'Canonical native execution claims must be owned by Tara.'}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;if($task.PSObject.Properties.Name -notcontains 'mayaTaraExecution'){throw 'Maya Tara execution is not prepared.'};$r=$task.mayaTaraExecution;foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId'){if([string]$r.$n -cne [string]$Preflight.$n){throw "Execution identity mismatch: $n"}};$attempt=if($task.PSObject.Properties.Name -contains 'mayaTaraAttempt'){$task.mayaTaraAttempt}else{$null};if(!$attempt -or $attempt.AttemptId -cne $r.AttemptId -or $attempt.RunId -cne $r.RunId){throw 'Maya Tara attempt is not current.'};if([DateTimeOffset]::Parse($attempt.RequestExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Maya Tara attempt is expired.'};if([long]$task.revision -ne ([long]$r.TaskRevisionAtPrepare+1)){throw 'Prepared execution revision is stale or task changed after preparation.'};if($r.Stage -ne 'prepared' -or $r.ExecutionStatus -ne 'Prepared' -or $r.ClaimStatus -ne 'unclaimed'){throw 'Maya Tara execution is not claimable.'};$r.ClaimId=[guid]::NewGuid().ToString('N');$r.ClaimOwner=$ClaimOwner;$r.ClaimedUtc=Get-RepatoUtc;$r.ClaimStatus='claimed';$r.Stage='claimed';$r.ExecutionStatus='Claimed';$r.TaskRevisionAtClaim=[long]$task.revision;Add-RepatoHistory $task 'maya-tara-execution-claimed' $ClaimOwner "claim=$($r.ClaimId); attempt=$($r.AttemptId); run=$($r.RunId)";$r}
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
    $newExec.EvidenceSha256=$null
    if($DryRun){return [pscustomobject]@{Mode='DryRun';OldAttemptId=$old.AttemptId;OldRunId=$old.RunId;NewAttemptId=$newAttempt;NewRunId=$newRun;RuntimeRoot=$runtime;SideEffectsPerformed=$false}}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$now=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $now.AttemptId -cne $old.AttemptId -or $now.RunId -cne $old.RunId -or $now.Stage -cne 'launch-failed' -or $now.FailureCode -cne 'native-process-start-failed'){throw 'Terminal launch-failure retry compare-and-swap failed.'};if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};$archived=[pscustomobject]$now;$archived|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force;$archived|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;$archived|Add-Member NoteProperty ReplacementRunId $newRun -Force;$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$archived;if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$t.mayaTaraAttempt;$t.mayaTaraAttempt=$newAttemptRecord;$newExec.TaskRevisionAtPrepare=[long]$t.revision;$t.mayaTaraExecution=[pscustomobject]$newExec;Add-RepatoHistory $t 'maya-tara-terminal-launch-failure-recovered' 'Maya' "failedAttempt=$($old.AttemptId); failedRun=$($old.RunId); replacementAttempt=$newAttempt; replacementRun=$newRun";$t.mayaTaraExecution}
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
    $identity=[pscustomobject]@{NativeRequestId=$old.RunId;
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
    if([string]$request.requestId -cne [string]$old.RunId -or [string]$receipt.RequestId -cne [string]$old.RunId -or [string]::IsNullOrWhiteSpace([string]$receipt.RunId) -or [string]$receipt.Status -cne 'Failed'){throw 'Native result correlation/status failed.'};
    if([string]::IsNullOrWhiteSpace([string]$receipt.ReportPath) -or !(Test-Path -LiteralPath $receipt.ReportPath -PathType Leaf)){throw 'Correlated native report is missing.'};
    try{$report=Get-Content $receipt.ReportPath -Raw|ConvertFrom-Json}catch{throw 'Correlated native report is malformed.'};
    if($report.TestId -cne $old.TestId -or [string]$report.RunId -cne [string]$receipt.RunId -or $report.Status -cne 'Failed'){throw 'Native report identity/status failed.'};
    $failureDetails = 'Native QA report returned Failed without failure details.'
    $failureDetailsProperty = $report.PSObject.Properties['FailureDetails']
    if ($null -ne $failureDetailsProperty) {
        $candidateFailureDetails = [string]$failureDetailsProperty.Value
        if (-not [string]::IsNullOrWhiteSpace($candidateFailureDetails)) {
            $failureDetails = $candidateFailureDetails
        }
    }
    if($ProcessInspector){$live=&$ProcessInspector ([int]$old.NativeProcessId) $old}else{try{$live=Get-Process -Id ([int]$old.NativeProcessId) -ErrorAction Stop}catch{$live=$null}};
    if($live){throw 'Recorded native PID is live or ambiguous;
     failure recovery is fail-closed.'}
    $source=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);
    $fixtures=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) 'Fixtures'));
    if(!$source.StartsWith($fixtures.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path $source) -or (Get-FileHash $source -Algorithm SHA256).Hash -ine $old.AuthoritativeFixtureSha256){throw 'Fixture validation failed.'};
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
    $arch|Add-Member NoteProperty FailureCode 'native-qa-failed' -Force;
    $arch|Add-Member NoteProperty FailureDetails $failureDetails -Force;
    $arch|Add-Member NoteProperty FailedUtc (Get-RepatoUtc) -Force;
    $arch|Add-Member NoteProperty ResultPath $resultPath -Force;
    $arch|Add-Member NoteProperty ReportPath $receipt.ReportPath -Force;
    $arch|Add-Member NoteProperty ReceiptPath $resultPath -Force;
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
     replacementAttempt=$newAttempt";
    $t.mayaTaraExecution}
}
function Get-MayaQaCanonicalNativeResult {
    param([Parameter(Mandatory)][string]$RequestPath,[string]$ResultPath,[Parameter(Mandatory)][object]$Identity,[ValidateRange(1,3600)][int]$TimeoutSeconds=900)
    if(!(Test-Path -LiteralPath $RequestPath -PathType Leaf)){throw 'Canonical request is missing.'}
    try{$request=Get-Content -LiteralPath $RequestPath -Raw|ConvertFrom-Json}catch{throw 'Canonical request JSON is malformed.'}
    if($request.PSObject.Properties.Name -contains 'requestId' -and [string]$request.requestId -cne [string]$Identity.NativeRequestId){throw 'Native request identity mismatch: requestId'}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId','ClaimId'){$rp=if($request.PSObject.Properties.Name -contains ('canonical'+$n)){[string]$request.('canonical'+$n)}elseif($request.PSObject.Properties.Name -contains $n){[string]$request.$n}else{$null};if($rp -cne [string]$Identity.$n){throw "Canonical request identity mismatch: $n"}}
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
    if(!$r.NativeProcessId){throw 'Canonical executing execution has no native process ID.'};if($r.ClaimId -cne $ClaimId -or $r.ClaimOwner -cne 'Tara'){throw 'Canonical resume claim identity mismatch.'};if(!$r.RequestPath){throw 'Canonical executing execution has no request path.'}
    $identity=[pscustomobject]@{RequestId=[IO.Path]::GetFileName($r.RequestPath);NativeRequestId=$r.RunId;TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;TestId=$r.TestId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;ClaimId=$r.ClaimId}
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
        $expectedSession=if($ExpectedSessionId){@($ExpectedSessionId)}else{@(Get-Process -IncludeUserName -ErrorAction SilentlyContinue|Where-Object UserName -ieq 'RAMSAI\RepatoQA'|Select-Object -ExpandProperty SessionId -Unique)}
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
    $request=Join-Path $r.DisposableRuntimeRoot ('maya-tara-'+$r.RunId+'.request.json');if($r.QaWorkflowId -cne 'create-plan-views-v1'){throw 'Canonical native startup contract is not supported for the selected QA workflow.'};$requestObject=[ordered]@{schemaVersion=2;operation='launch-revit-qa';requestId=$r.RunId;taskId=$r.TaskId;workflowId=$r.WorkflowId;qaWorkflowId=$r.QaWorkflowId;testId=$r.TestId;attemptId=$r.AttemptId;runId=$r.RunId;claimId=$r.ClaimId;requestPath=$request;requestSha256=('0'*64);modelPath=$r.DisposableModelPath;modelSha256=$r.DisposableModelSha256;manifestPath=$r.RunnerManifestPath;manifestSha256=$r.RunnerManifestSha256;expiresUtc=$task.mayaTaraAttempt.RequestExpiresUtc};$canonicalJson=ConvertTo-MayaQaCanonicalRequestJson $requestObject;[IO.File]::WriteAllText($request,$canonicalJson,[Text.UTF8Encoding]::new($false));$requestObject.requestSha256=Get-MayaQaCanonicalRequestSha256 $requestObject
    $null=Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'claimed' -or $x.ClaimId -cne $ClaimId -or [long]$t.revision -ne ([long]$x.TaskRevisionAtClaim+1)){throw 'Launch transition compare-and-swap failed.'};$x.Stage='launching';$x.ExecutionStatus='Launching';$x.LaunchingUtc=Get-RepatoUtc;$x.RequestPath=$request;Add-RepatoHistory $t 'maya-tara-native-launching' 'Tara' "claim=$ClaimId";$x}
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
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId,[Parameter(Mandatory)][string]$ReportDirectory,[string]$RevitInstallDir='E:\revit\Revit 2025',[Parameter(Mandatory)][string]$QaAddinRoot,[ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$DryRun)
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
    $context=[pscustomobject]@{QaRoot=$qaRoot;SourceFixturePath=$r.AuthoritativeFixturePath;FixtureId=$def.FixtureId;FixtureSha256=$r.AuthoritativeFixtureSha256;TestId=$r.TestId;ArtifactPath=$r.ArtifactPath;ArtifactSha256=$r.ArtifactSha256;ManifestPath=$r.RunnerManifestPath;ManifestSha256=$r.RunnerManifestSha256;TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;ClaimId=$r.ClaimId}
    $plan=New-TaraRevitQaPlan -StoreRoot $StoreRoot -TaskId $r.TaskId -WorkflowId $r.WorkflowId -QaWorkflowId $r.QaWorkflowId -RunId $r.RunId -ModelPath $r.DisposableModelPath -SidecarPath ($r.DisposableModelPath+'.fixture.json') -ReportDirectory $ReportDirectory -RevitInstallDir $RevitInstallDir -QaAddinRoot $QaAddinRoot -TimeoutSeconds $TimeoutSeconds -Context $context -DryRun
    $request=[ordered]@{requestId=$plan.RequestId;claimId=$r.ClaimId;testId=$r.TestId;modelPath=$r.DisposableModelPath;TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;createdUtc=(Get-RepatoUtc);expiresUtc=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds).ToString('O');selectedManifestPath=$plan.QaRunnerManifestPath;selectedManifestSha256=$plan.QaRunnerManifestSha256;addinIsolation=$plan.Isolation}
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
    foreach($n in 'RequestId','AttemptId','RunId','WorkflowId','ClaimId'){
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

        [switch]$DryRun
    )

    if ([string]::IsNullOrWhiteSpace($SourceBranch)) {
        $SourceBranch = 'current'
    }

    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        $ProjectPath = 'Forma.RevitConnector.csproj'
    }

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
        RequestedArtifact = $requestedArtifact
        WorkflowRevision = $mutation.Workflow.workflowRevision
        TaskRevision = $mutation.TaskRevision
        SideEffectsPerformed = $true
    }
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
function Invoke-MayaQaRequest {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$UserRequest,[string]$SourceBranch='main',[string]$ProjectPath,
        [ValidateSet('Build','FrozenCandidate')][string]$ArtifactMode='Build',[string]$CandidateDirectory,[string]$CandidateDllPath,
        [string]$ExpectedCandidateSha256,[string]$ExpectedCandidateSourceCommit,[switch]$StageFrozenCandidateForQa,[scriptblock]$QaStagingInvoker,[switch]$DryRun)
    $qaId=Resolve-MayaQaRequestWorkflow $UserRequest
    $def=Get-MayaQaWorkflowDefinition $qaId
    $qaStaging=$null
    if($ArtifactMode -ceq 'FrozenCandidate'){
        foreach($required in @(@('CandidateDirectory',$CandidateDirectory),@('ExpectedCandidateSha256',$ExpectedCandidateSha256),@('ExpectedCandidateSourceCommit',$ExpectedCandidateSourceCommit))){if([string]::IsNullOrWhiteSpace([string]$required[1])){throw "FrozenCandidate mode requires $($required[0])."}}
        $null=Test-MayaQaFrozenCandidate -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit -QaWorkflowId $qaId
        if($StageFrozenCandidateForQa){
            $nativeTestId=Get-MayaQaNativeTestId $def
            if($QaStagingInvoker){$qaStaging=& $QaStagingInvoker $CandidateDirectory $ExpectedCandidateSha256 $ExpectedCandidateSourceCommit $qaId $nativeTestId ([bool]$DryRun)}else{
                Import-Module (Join-Path $PSScriptRoot 'Repato.QaAddinDeployment.psm1') -Force -WarningAction SilentlyContinue
                $qaStaging=Install-TaraFrozenCandidateForQa -CandidateDirectory $CandidateDirectory -ExpectedArtifactSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit -QaWorkflowId $qaId -TestId $nativeTestId -DryRun:$DryRun
            }
            if(!$qaStaging -or !$qaStaging.Success -or [string]$qaStaging.CandidateSha256 -ine $ExpectedCandidateSha256 -or $qaStaging.BuildInvoked){throw 'Canonical QA-only frozen-candidate staging failed validation.'}
        }
    }
    $taskId='task-'+[guid]::NewGuid().ToString('N');$workflowId='workflow-'+[guid]::NewGuid().ToString('N');$runId=[guid]::NewGuid().ToString('N')
    if($DryRun){return [pscustomobject]@{Success=$true;Mode='DryRun';TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaId;RunId=$runId;FixtureId=$def.FixtureId;NativeTestId=(Get-MayaQaNativeTestId $def);QaStaging=$qaStaging;Stages=@('frozen-candidate-validation','qa-only-staging','isolation','intake','build-request','build-execute','handoff','tara-execute','report-verify','complete','receipt','dashboard');SideEffectsPerformed=$false;Error=$null}}
    if([string]::IsNullOrWhiteSpace($ProjectPath)){$ProjectPath='Forma.RevitConnector.csproj'}
    $null=Initialize-RepatoTaskStore $StoreRoot
    $existing=$null; try{$existing=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $taskId}catch{}
    if($null -eq $existing){ New-RepatoTask $StoreRoot $taskId 'Maya QA request' $UserRequest 'qa/maya-qa-workflow' 'maya' | Out-Null }
    $taskNow=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $taskId
    if($taskNow.workflowStage -eq 'queued'){ Claim-RepatoTask $StoreRoot $taskId 'Neil' | Out-Null; Update-RepatoTask $StoreRoot $taskId 'in-progress' 'implementation' 'Neil' $null $null | Out-Null; Update-RepatoTask $StoreRoot $taskId 'in-progress' 'build-checks' 'Neil' $null $null | Out-Null }
    $workflowExisting=$null; try{$workflowExisting=Get-DeployWorkflow $StoreRoot $taskId $workflowId}catch{}
    if($null -eq $workflowExisting){
        $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$plan=New-DeployPlan $StoreRoot $taskId (Join-Path $root 'bin\Release\net8.0-windows\Repato.Revit.dll') (Join-Path $root 'Repato.addin');
        $created=New-DeployWorkflow $StoreRoot $plan; $workflowId=$created.workflowId
    }
    $intake=Invoke-MayaQaIntake $taskId $workflowId $qaId $UserRequest
    $buildRequest=New-MayaQaBuildRequest -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath
    if($ArtifactMode -ceq 'FrozenCandidate'){
        $build=Invoke-MayaQaFrozenCandidateEvidence -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit
    }else{
        $build=Invoke-MayaQaBuildExecute -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -SourceBranch $SourceBranch -ProjectPath $ProjectPath
    }
    if($build.BuildStatus -cne 'succeeded' -or [string]::IsNullOrWhiteSpace($build.ArtifactPath) -or [string]::IsNullOrWhiteSpace($build.ArtifactSha256) -or !(Test-Path -LiteralPath $build.ArtifactPath -PathType Leaf)){throw 'Neil build did not produce a verified artifact.'}
    if((Get-FileHash -LiteralPath $build.ArtifactPath -Algorithm SHA256).Hash -ine $build.ArtifactSha256){throw 'Neil artifact SHA-256 verification failed.'}
    if([string]::IsNullOrWhiteSpace($build.ManifestPath) -or (Get-FileHash -LiteralPath $build.ManifestPath -Algorithm SHA256).Hash -ine $build.ManifestSha256){throw 'Neil artifact manifest SHA-256 verification failed.'}
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
        [string]$CandidateDirectory,[string]$CandidateDllPath,[string]$ExpectedCandidateSha256,[string]$ExpectedCandidateSourceCommit,
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
        $request = Invoke-MayaQaRequest -StoreRoot $StoreRoot -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath -ArtifactMode $ArtifactMode -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedCandidateSha256 $ExpectedCandidateSha256 -ExpectedCandidateSourceCommit $ExpectedCandidateSourceCommit -StageFrozenCandidateForQa:$StageFrozenCandidateForQa
    }
    if (!$request -or $request.Stage -notin @('handoff-ready','execution-ready')) {
        throw 'Canonical transaction requires an approved Tara handoff.'
    }

    $handoff = if ($request.PSObject.Properties.Name -contains 'Handoff') { $request.Handoff } else { $request }
    $preflight = [pscustomobject]@{
        TaskId = $request.TaskId; WorkflowId = $request.WorkflowId
        QaWorkflowId = $request.QaWorkflowId; TestId = $handoff.NativeTestId
        HandoffId = $handoff.HandoffId; AttemptId = $handoff.AttemptId
        RunId = $request.RunId; ArtifactPath = $handoff.ArtifactPath
        ArtifactSha256 = $handoff.ArtifactSha256; RunnerManifest = $handoff.ManifestPath
        RunnerManifestSha256 = $handoff.ManifestSha256; FixturePath = $handoff.ModelPath
        FixtureSha256 = $handoff.ModelSha256; DisposableFixturePath = $handoff.ModelPath
        DisposableFixtureSha256 = $handoff.ModelSha256
        Isolation = $handoff.Isolation
    }
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
function Invoke-MayaQaBuildExecute {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[string]$SourceBranch='current',[string]$ProjectPath='Forma.RevitConnector.csproj',[switch]$DryRun)
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
    $persistedProject = & $normalize ([string]$workflow.qaBuildRequest.ProjectPath) $root
    $requestedProjectInput = & $normalize $ProjectPath $root
    if ($workflow.qaBuildRequest.SourceBranch -cne $SourceBranch -or $persistedProject -ine $requestedProjectInput) { throw 'Build request parameters do not match the persisted request.' }
    $project = [IO.Path]::GetFullPath((Join-Path $root 'Forma.RevitConnector.csproj'))
    if ($persistedProject -ine $project -or !(Test-Path -LiteralPath $persistedProject -PathType Leaf)) { throw 'Normalized project path is missing or outside the approved workspace.' }
    $artifact = [IO.Path]::GetFullPath((Join-Path $root 'bin\Release\net8.0-windows\Repato.Revit.dll'))
    $artifactManifest = [IO.Path]::GetFullPath((Join-Path $root 'Repato.addin'))
    $requestedArtifact = if($workflow.qaBuildRequest.PSObject.Properties.Name -contains 'RequestedArtifact') { & $normalize ([string]$workflow.qaBuildRequest.RequestedArtifact) $root } else { $artifact }
    if($requestedArtifact -ine $artifact){throw 'Normalized requested artifact is outside the approved Release artifact path.'}
    $command = 'dotnet build "' + $project + '" -c Release -p:RevitInstallDir="E:\revit\Revit 2025"'
    if ($DryRun) { return [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus='planned';Command=$command;Configuration='Release';ArtifactPath=$artifact;SideEffectsPerformed=$false} }
    $started = (Get-Date).ToUniversalTime().ToString('O')
    Push-Location $root
    try { $lines = @(& dotnet build $project -c Release '-p:RevitInstallDir=E:\revit\Revit 2025' 2>&1); $exit = $LASTEXITCODE } finally { Pop-Location }
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
        $current | Add-Member -NotePropertyName qaBuildEvidence -NotePropertyValue ([pscustomobject]@{BuildRequestId=$current.qaBuildRequest.BuildRequestId;StartedUtc=$started;FinishedUtc=$finished;Command=$command;Configuration='Release';ExitCode=$exit;ArtifactPath=$artifact;ArtifactSha256=$(if(Test-Path $artifact){(Get-FileHash $artifact -Algorithm SHA256).Hash}else{$null});ManifestPath=$artifactManifest;ManifestSha256=$(if(Test-Path $artifactManifest){(Get-FileHash $artifactManifest -Algorithm SHA256).Hash}else{$null});BuildStatus=$status;WarningCount=$warningCount;ErrorCount=$errorCount;ErrorLines=$errorLines}) -Force
        return $current
    })[-1]
    if ($status -ne 'succeeded') { throw "Release build failed with exit code $exit." }
    [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus=$status;Command=$command;Configuration='Release';ExitCode=$exit;ArtifactPath=$artifact;ArtifactSha256=$mutation.Workflow.qaBuildEvidence.ArtifactSha256;ArtifactManifestPath=$artifactManifest;ArtifactManifestSha256=$mutation.Workflow.qaBuildEvidence.ManifestSha256;ManifestPath=$artifactManifest;ManifestSha256=$mutation.Workflow.qaBuildEvidence.ManifestSha256;WarningCount=$warningCount;ErrorCount=$errorCount;WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;SideEffectsPerformed=$true}
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
        [Parameter(Mandatory)][string]$ExpectedSha256,[Parameter(Mandatory)][string]$ExpectedSourceCommit,
        [switch]$DryRun
    )
    $verified=Test-MayaQaFrozenCandidate -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedSha256 -ExpectedSourceCommit $ExpectedSourceCommit -QaWorkflowId $QaWorkflowId
    if($DryRun){return $verified}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($workflow.PSObject.Properties.Name -notcontains 'qaBuildRequest' -or !$workflow.qaBuildRequest){throw 'Persisted Neil build request is missing.'}
    if($workflow.qaWorkflowId -cne $QaWorkflowId){throw 'QA workflow identity mismatch.'}
    $now=(Get-Date).ToUniversalTime().ToString('O');$data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    $mutation=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        $e=[pscustomobject]@{BuildRequestId=$current.qaBuildRequest.BuildRequestId;StartedUtc=$now;FinishedUtc=$now;Command='FrozenCandidate integrity and provenance validation (no compilation)';Configuration='Release';ExitCode=0;ArtifactPath=$verified.ArtifactPath;ArtifactSha256=$verified.ArtifactSha256;ManifestPath=$verified.ManifestPath;ManifestSha256=$verified.ManifestSha256;BuildStatus='succeeded';WarningCount=0;ErrorCount=0;ErrorLines=@();EvidenceSource='FrozenCandidate';CandidateDirectory=$verified.CandidateDirectory;CandidateProvenancePath=$verified.ProvenancePath;CandidateProvenanceSha256=$verified.ProvenanceSha256;CandidateSourceCommit=$verified.SourceCommit;QaWorkflowId=$verified.QaWorkflowId}
        $current|Add-Member NoteProperty qaBuildStatus 'succeeded' -Force
        $current|Add-Member NoteProperty qaBuildEvidence $e -Force
        return $current
    })[-1]
    [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus='succeeded';Command='FrozenCandidate integrity and provenance validation (no compilation)';Configuration='Release';ExitCode=0;ArtifactPath=$verified.ArtifactPath;ArtifactSha256=$verified.ArtifactSha256;ArtifactManifestPath=$verified.ManifestPath;ArtifactManifestSha256=$verified.ManifestSha256;ManifestPath=$verified.ManifestPath;ManifestSha256=$verified.ManifestSha256;WarningCount=0;ErrorCount=0;EvidenceSource='FrozenCandidate';CandidateProvenancePath=$verified.ProvenancePath;CandidateProvenanceSha256=$verified.ProvenanceSha256;CandidateSourceCommit=$verified.SourceCommit;WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;SideEffectsPerformed=$true}
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
    if ($properties -notcontains 'qaBuildEvidence' -or $properties -notcontains 'qaBuildStatus' -or $workflow.qaBuildStatus -ne 'succeeded') {
        throw 'Successful Neil build execution is required.'
    }
    if ($properties -contains 'qaHandoffId' -and $workflow.qaHandoffId) {
        throw 'Tara QA handoff already exists.'
    }

    $evidence = $workflow.qaBuildEvidence
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
    $coordinatorRunId = 'qa-run-' + [guid]::NewGuid().ToString('N')
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
    $attempt=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$attemptId;TaskId=$TaskId;WorkflowId=$WorkflowId;RunId=$runId;RuntimeRoot=$runtimeRoot;RequestExpiresUtc=[DateTimeOffset]::UtcNow.AddMinutes((Get-MayaQaAttemptDurationMinutes)).ToString('O');Stage='prepared';Success=$false;RequestPath=$null}
    $plan=[pscustomobject][ordered]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;Stage='qa-prepared';ActiveAgent='Maya';NextAgent='Tara';NextOperation='canonical-execution-record';SideEffectsPerformed=$false}
    $packet=[pscustomobject][ordered]@{SchemaVersion='maya-tara-qa-packet-v3';HandoffId=$handoff.HandoffId;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;TestId=$handoff.NativeTestId;RunId=$runId;AttemptId=$attemptId;ArtifactPath=$handoff.ArtifactPath;ArtifactSha256=$handoff.ArtifactSha256;ManifestPath=$handoff.ManifestPath;ManifestSha256=$handoff.ManifestSha256;ModelPath=$workflow.qaModelPath;SidecarPath=$workflow.qaSidecarPath;FixturePath=$workflow.qaModelPath;FixtureSha256=$workflow.qaFixtureSha256;RequestExpiresUtc=$attempt.RequestExpiresUtc;Stage='prepared';SideEffectsPerformed=$false;StoreRoot=$StoreRoot}
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
function New-MayaQaRun { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$RunId,[string]$RuntimeRoot,[switch]$DryRun)
    $QaWorkflowId = Resolve-MayaQaWorkflowId $QaWorkflowId
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId; if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'Invalid QA run ID.'}
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if ($DryRun) { return [pscustomobject]@{WorkflowId=$WorkflowId;RunId=$RunId;Stage=$w.stage;SideEffectsPerformed=$false} }
    if ($w.PSObject.Properties.Name -notcontains 'qaBuildEvidence' -or $w.PSObject.Properties.Name -notcontains 'qaBuildStatus' -or $w.qaBuildStatus -ne 'succeeded') { throw 'Valid Neil build evidence is required before QA run planning.' }
    foreach($pair in @(@($w.qaBuildEvidence.ArtifactPath,$w.qaBuildEvidence.ArtifactSha256),@($w.qaBuildEvidence.ManifestPath,$w.qaBuildEvidence.ManifestSha256))){if(!(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw 'Neil build evidence hash validation failed.'}}
    $qa=Get-MayaQaRoot; $runs=if([string]::IsNullOrWhiteSpace($RuntimeRoot)){Get-MayaQaRuntimeRoot}else{[IO.Path]::GetFullPath($RuntimeRoot)}; if(!(Test-Path -LiteralPath $runs)){New-Item -ItemType Directory -Path $runs -Force|Out-Null}; $run=[IO.Path]::GetFullPath((Join-Path $runs ($WorkflowId+'-'+$RunId))); $runsPrefix=([IO.Path]::GetFullPath($runs)).TrimEnd('\')+'\'; if(!$run.StartsWith($runsPrefix,[StringComparison]::OrdinalIgnoreCase)){throw "Run path escaped QA runtime root: $run"}
    if (Test-Path -LiteralPath $run) { throw 'QA run directory already exists.' }
    $source=Join-Path (Join-Path $qa 'Fixtures') $def.Source; if (!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Approved fixture missing: $source"}
    New-Item -ItemType Directory -Path $run -Force | Out-Null; $model=Join-Path $run 'model.rvt'; Copy-Item -LiteralPath $source -Destination $model
    $fixtureHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash; $sidecar=Join-Path $run 'model.rvt.fixture.json'
    $side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$fixtureHash}; if($QaWorkflowId -eq 'grid-bubble-visibility-v1' -or $QaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')}; if($QaWorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')}
    $side | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sidecar -Encoding UTF8
    if($WorkflowId -eq 'grid-bubble-visibility-v1'){$check=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json;$expected=@('A','B','C','D','1','2','3','4');if($check.fixtureId -cne 'GridBubbleVisibilityEmpty' -or $check.sourceSha256 -ine $fixtureHash -or (@($check.requiredGridNames)-join '|') -cne ($expected -join '|')){throw 'Grid Bubble Visibility sidecar identity is invalid.'}}    $d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId
    $nativeTestId=Get-MayaQaNativeTestId $def;$m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision { param($x) foreach($v in @(@('qaWorkflowId',$QaWorkflowId),@('qaRunId',$RunId),@('qaModelPath',$model),@('qaSidecarPath',$sidecar),@('qaFixtureId',$def.FixtureId),@('qaFixtureSha256',$fixtureHash),@('qaTestId',$nativeTestId),@('qaReportPath',$null),@('qaReportSha256',$null),@('qaEvidence',$null),@('qaVerificationStatus',$null),@('qaCompletionStatus',$null),@('qaCompletedUtc',$null))){$x|Add-Member -NotePropertyName $v[0] -NotePropertyValue $v[1] -Force}; if($x.PSObject.Properties.Name -contains 'qaHandoff' -and $x.qaHandoff){$x.qaHandoff | Add-Member -NotePropertyName ModelPath -NotePropertyValue $model -Force;$x.qaHandoff | Add-Member -NotePropertyName SidecarPath -NotePropertyValue $sidecar -Force}; return $x })[-1]
    [pscustomobject]@{WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;RunId=$RunId;ModelPath=$model;SidecarPath=$sidecar;FixtureId=$def.FixtureId;FixtureSha256=$fixtureHash;Stage=$m.Workflow.stage;WorkflowRevision=$m.Workflow.workflowRevision;TaskRevision=$m.TaskRevision;SideEffectsPerformed=$true}
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
Export-ModuleMember -Function Invoke-MayaQaTaraExecute,Resolve-MayaQaRequestWorkflow,Resolve-MayaQaWorkflowId,Resolve-MayaQaTaskStoreIdentity,New-MayaQaExecutionRecord,Claim-MayaQaExecutionRecord,Prepare-MayaQaCanonicalNativeLaunch,Invoke-MayaQaCanonicalNativeCore,Get-MayaQaAttemptDurationMinutes,Recover-MayaQaExpiredExecutionRecord,Recover-MayaQaTerminalLaunchFailure,Recover-MayaQaAbandonedNativeExecution,Repair-MayaQaPreparedExecutionLifecycle,Get-MayaQaCanonicalNativeResult,Resume-MayaQaCanonicalExecution,Get-MayaQaNativeTestId,Invoke-MayaQaRequest,Invoke-MayaQaCanonicalTransaction,Get-MayaQaWorkflowDefinition,Get-MayaQaWorkflowCatalog,Get-MayaQaCatalogDryRun,Get-MayaQaWorkflowStatus,Invoke-MayaQaIntake,New-MayaQaBuildRequest,Invoke-MayaQaBuildExecute,New-MayaQaHandoff,Submit-MayaQaReport,Get-MayaQaDashboard,Invoke-MayaQaOverview,New-MayaQaBootstrap,New-MayaQaRun,Register-MayaQaReport,Complete-MayaQaWorkflow,New-MayaQaReceipt,Get-MayaQaReceiptStatus
Export-ModuleMember -Function Recover-MayaQaInvalidNativeClaim
Export-ModuleMember -Function Recover-MayaQaCorrelatedNativeFailure
Export-ModuleMember -Function Invoke-MayaQaLaunchAgentHealth
Export-ModuleMember -Function Test-MayaQaFrozenCandidate,Invoke-MayaQaFrozenCandidateEvidence
Export-ModuleMember -Function New-MayaQaCanonicalPreparation

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
