$ErrorActionPreference='Stop'
$here=$PSScriptRoot
Import-Module (Join-Path $here 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $here 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$root=Join-Path ([IO.Path]::GetTempPath()) ('maya-revit-graceful-shutdown-'+[guid]::NewGuid().ToString('N'))
$taskId='task-revit-graceful-shutdown';$workflowId='workflow-revit-graceful-shutdown'
function New-Fixture([string]$storeRoot,[hashtable]$overrides) {
    $modelDir=Join-Path $storeRoot 'Runtime';New-Item -ItemType Directory -Path $modelDir -Force|Out-Null
    $modelPath=Join-Path $modelDir 'model.rvt';[IO.File]::WriteAllBytes($modelPath,[byte[]](9,8,7,6,5))
    $modelSha=(Get-FileHash $modelPath -Algorithm SHA256).Hash
    $record=[pscustomobject][ordered]@{
        AttemptId='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';RunId='abcdef0123456789abcdef0123456789';WorkflowId=$workflowId;TaskId=$taskId
        NativeProcessId=4711;Stage='completed';ExecutionStatus='Completed';CompletionStatus='Completed'
        VerificationStatus='Verified';RollbackStatus='Verified';SideEffectsPerformed=$true
        LaunchedUtc='2026-10-20T12:30:00.0000000+00:00';CompletedUtc='2026-10-20T12:35:00.0000000+00:00'
        DisposableModelPath=$modelPath;DisposableModelSha256=$modelSha
    }
    foreach($name in @('NativeProcessId','Stage','ExecutionStatus','CompletionStatus','VerificationStatus','RollbackStatus','DisposableModelPath','DisposableModelSha256')){ if($overrides -and $overrides.Contains($name)){$record|Add-Member NoteProperty $name $overrides[$name] -Force} }
    New-RepatoTask $storeRoot $taskId 'Revit graceful shutdown' 'synthetic fixture' 'qa/revit-graceful-shutdown'|Out-Null
    Invoke-RepatoStoreMutation $storeRoot {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.revision=[long]11;$t.status='in-progress';$t.workflowStage='approval';$t|Add-Member NoteProperty mayaTaraExecution $record -Force;$t}|Out-Null
    @{StoreRoot=$storeRoot;ModelPath=$modelPath;ModelSha=$modelSha}
}
$state=[hashtable]@{TargetPid=4711;Exited=$false;CloseResult=$true;ExitAfterClose=$true;CloseCalls=0;Processes=$null}
$provider={ if($state.Processes){return @($state.Processes)}; if($state.Exited){return @()}; $object=New-Object PSObject; $object|Add-Member NoteProperty Id ([int]$state.TargetPid); $object|Add-Member NoteProperty ProcessName 'Revit'; $object|Add-Member NoteProperty MainWindowHandle ([IntPtr]8088); $object|Add-Member NoteProperty HasExited ([bool]$state.Exited); $object|Add-Member ScriptMethod CloseMainWindow { $state.CloseCalls++; if(-not $state.CloseResult){return $false}; if($state.ExitAfterClose){$state.Exited=$true}; return $true }.GetNewClosure(); return @($object) }
try {
    $state.Exited=$false;$state.CloseResult=$true;$state.CloseCalls=0;$state.Processes=$null
    $fixture=New-Fixture (Join-Path $root 'happy') $null
    $result=Invoke-MayaQaRevitGracefulShutdown -StoreRoot $fixture.StoreRoot -TaskId $taskId -WorkflowId $workflowId -GracefulTimeoutSeconds 3 -ProcessProvider $provider
    if($result.Status -cne 'Closed'){throw ('Happy path status was not Closed: ' + ($result|ConvertTo-Json -Compress))}
    if($result.SideEffectsPerformed -ne $true){throw 'Happy path did not record side effects.'}
    if($result.Detail -notmatch 'process-exited'){throw ('Happy path detail unexpected: ' + $result.Detail)}
    if($result.ModelUnlocked -ne $true -or $result.ModelShaMatch -ne $true){throw 'Happy path model verification failed.'}
    $t=Find-RepatoTask (Read-RepatoTaskStore $fixture.StoreRoot) $taskId
    if([string]$t.mayaTaraExecution.RevitShutdownStatus -cne 'Closed'){throw 'Shutdown status was not stamped.'}
    if(@($t.history|Where-Object {$_.event -ceq 'maya-tara-revit-graceful-shutdown'}).Count -ne 1){throw 'Shutdown history event missing.'}
    $revisionAfter=[long]$t.revision
    $state.Exited=$true
    $again=Invoke-MayaQaRevitGracefulShutdown -StoreRoot $fixture.StoreRoot -TaskId $taskId -WorkflowId $workflowId -GracefulTimeoutSeconds 3 -ProcessProvider $provider
    if($again.Status -cne 'AlreadyShutdown'){throw ("Shutdown was not idempotent: " + $again.Status)}
    $t2=Find-RepatoTask (Read-RepatoTaskStore $fixture.StoreRoot) $taskId
    if(@($t2.history|Where-Object {$_.event -ceq 'maya-tara-revit-graceful-shutdown'}).Count -ne 1 -or [long]$t2.revision -ne $revisionAfter){throw 'Idempotent shutdown mutated the store.'}

    $state.Exited=$false;$state.CloseResult=$false;$state.CloseCalls=0;$state.Processes=$null
    $fixture2=New-Fixture (Join-Path $root 'refused') $null
    $blocked=Invoke-MayaQaRevitGracefulShutdown -StoreRoot $fixture2.StoreRoot -TaskId $taskId -WorkflowId $workflowId -GracefulTimeoutSeconds 2 -ProcessProvider $provider
    if($blocked.Status -cne 'Blocked'){throw ('Refusal was not blocked. Got: ' + ($blocked | ConvertTo-Json -Compress -Depth 5))}
    if($blocked.Detail -notmatch 'window-close-refused'){throw 'Refusal detail missing.'}
    if($blocked.ProcessId -ne 4711){throw 'Blocked PID missing.'}
    if($state.CloseCalls -gt 1){throw 'Multiple close requests attempted on refusal.'}

    $state.Exited=$false;$state.CloseResult=$true;$state.ExitAfterClose=$false;$state.CloseCalls=0
    $fixture3=New-Fixture (Join-Path $root 'timeout') $null
    $timedOut=Invoke-MayaQaRevitGracefulShutdown -StoreRoot $fixture3.StoreRoot -TaskId $taskId -WorkflowId $workflowId -GracefulTimeoutSeconds 2 -ProcessProvider $provider
    if($timedOut.Status -cne 'Timeout'){throw ('Timeout not detected: ' + $timedOut.Status)}
    $t3=Find-RepatoTask (Read-RepatoTaskStore $fixture3.StoreRoot) $taskId
    if([string]$t3.mayaTaraExecution.RevitShutdownStatus -cne 'Timeout'){throw 'Timeout status was not stamped.'}

    $state.Exited=$true
    $fixture4=New-Fixture (Join-Path $root 'absent') $null
    $before4=[long](Invoke-RepatoStoreMutation $fixture4.StoreRoot {param($d,$preview)[long](Find-RepatoTask $d $taskId).revision})
    $absent=Invoke-MayaQaRevitGracefulShutdown -StoreRoot $fixture4.StoreRoot -TaskId $taskId -WorkflowId $workflowId -GracefulTimeoutSeconds 2 -ProcessProvider $provider
    if($absent.Status -cne 'Closed' -or $absent.Detail -notmatch 'process-already-exited'){throw 'Absent-process path failed: ' + $absent.Status + ' / ' + $absent.Detail}
    if($absent.SideEffectsPerformed){throw 'Absent-process path claimed side effects.'}
    if([long](Invoke-RepatoStoreMutation $fixture4.StoreRoot {param($d,$preview)[long](Find-RepatoTask $d $taskId).revision}) -ne $before4){throw 'Absent-process path mutated the store.'}

    $otherProc=New-Object PSObject
    $otherProc|Add-Member NoteProperty Id ([int]9999)
    $otherProc|Add-Member NoteProperty ProcessName 'Revit'
    $otherProc|Add-Member NoteProperty MainWindowHandle ([IntPtr]4100)
    $otherProc|Add-Member ScriptMethod CloseMainWindow { throw 'unrelated Revit process was targeted' }
    $state.Exited=$true;$state.Processes=@($otherProc)
    $fixture5=New-Fixture (Join-Path $root 'unrelated') $null
    $unrelated=Invoke-MayaQaRevitGracefulShutdown -StoreRoot $fixture5.StoreRoot -TaskId $taskId -WorkflowId $workflowId -GracefulTimeoutSeconds 2 -ProcessProvider $provider
    if($unrelated.Status -cne 'Closed' -or $unrelated.Detail -notmatch 'other-revit-instances-present=1'){throw ('Unrelated Revit instance was not reported without targeting it: ' + $unrelated.Status + ' / ' + $unrelated.Detail)}

    $fixture6=New-Fixture (Join-Path $root 'nonterminal') ([hashtable]@{CompletionStatus='Pending';ExecutionStatus='Executing'})
    $rejected6=$false
    try{Invoke-MayaQaRevitGracefulShutdown -StoreRoot $fixture6.StoreRoot -TaskId $taskId -WorkflowId $workflowId -GracefulTimeoutSeconds 2 -ProcessProvider $provider}catch{$rejected6=$_.Exception.Message -match 'pending Revit operations'}
    if(!$rejected6){throw 'Non-terminal record was not rejected.'}

    $fixture7=New-Fixture (Join-Path $root 'workflow-mismatch') $null
    $rejected7=$false
    try{Invoke-MayaQaRevitGracefulShutdown -StoreRoot $fixture7.StoreRoot -TaskId $taskId -WorkflowId 'other-workflow' -GracefulTimeoutSeconds 2 -ProcessProvider $provider}catch{$rejected7=$_.Exception.Message -match 'workflow identity mismatch'}
    if(!$rejected7){throw 'Workflow mismatch was not rejected.'}

    $fixture8=New-Fixture (Join-Path $root 'missing-pid') ([hashtable]@{NativeProcessId=$null})
    $rejected8=$false
    try{Invoke-MayaQaRevitGracefulShutdown -StoreRoot $fixture8.StoreRoot -TaskId $taskId -WorkflowId $workflowId -GracefulTimeoutSeconds 2 -ProcessProvider $provider}catch{$rejected8=$_.Exception.Message -match 'native process identity'}
    if(!$rejected8){throw 'Missing native PID was not rejected.'}

    $tampered=New-Fixture (Join-Path $root 'model-tampered') $null
    [IO.File]::WriteAllText($tampered.ModelPath,'tampered')
    Invoke-RepatoStoreMutation $tampered.StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.mayaTaraExecution.DisposableModelSha256='9'*64;$t}|Out-Null
    $state.Exited=$true;$state.Processes=$null
    $mismatch=Invoke-MayaQaRevitGracefulShutdown -StoreRoot $tampered.StoreRoot -TaskId $taskId -WorkflowId $workflowId -GracefulTimeoutSeconds 3 -ProcessProvider $provider
    if($mismatch.Status -cne 'Closed' -or $mismatch.ModelShaMatch -ne $false){throw 'Model SHA mismatch was not detected.'}
    if($mismatch.Detail -notmatch 'model-sha-mismatch'){throw 'Model SHA mismatch detail missing.'}

    $nonTempStore=Join-Path 'C:\Repato-Autonomous\Worktrees\cpv-native-retest-20261020\AgentOrchestration' ('.tmp-revit-shutdown-'+[guid]::NewGuid().ToString('N'))
    $fixtureNt=New-Fixture $nonTempStore $null
    $rejectedNt=$false
    try{Invoke-MayaQaRevitGracefulShutdown -StoreRoot $fixtureNt.StoreRoot -TaskId $taskId -WorkflowId $workflowId -GracefulTimeoutSeconds 5 -ProcessProvider $provider}catch{$rejectedNt=$_.Exception.Message -match 'at least 120 seconds'}
    if(!$rejectedNt){throw 'Short graceful timeout outside synthetic store was not rejected.'}

    [pscustomobject]@{Success=$true;ClosedOnce=$true;HistoryOnce=$true;RefusedBlocked=$true;TimeoutStamped=$true;AbsentNoSideEffects=$true;UnrelatedUntouched=$true;NonTerminalRejected=$true;WorkflowMismatchRejected=$true;MissingPidRejected=$true;ModelShaMismatchDetected=$true;ShortTimeoutGuard=$true}|ConvertTo-Json -Compress
} finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
    $leftover=Get-ChildItem -LiteralPath 'C:\Repato-Autonomous\Worktrees\cpv-native-retest-20261020\AgentOrchestration' -Filter '.tmp-revit-shutdown-*' -Directory -ErrorAction SilentlyContinue
    if($leftover){$leftover|ForEach-Object{Remove-Item -LiteralPath $_.FullName -Recurse -Force}}
}
