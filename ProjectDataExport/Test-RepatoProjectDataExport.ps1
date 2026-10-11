$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$exporter = Join-Path $root 'Export-RepatoProjectData.ps1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('repato-export-test-' + [guid]::NewGuid().ToString('N'))
$store = Join-Path $scratch 'store'
$output = Join-Path $scratch 'output\payload.json'
New-Item -ItemType Directory -Path $store -Force | Out-Null
try {
    $synthetic = [pscustomobject]@{
        schemaVersion = 1
        tasks = @(
            [pscustomobject]@{taskId='SYN-TASK-001';title='Synthetic safe task';description='Review C:\Users\private\project.rvt; contact private@example.com; token=abc123';assignedAgent='Neil';status='in-progress';workflowStage='implementation';logs=@('C:\Users\private\secret.log');reportPaths=@();approvalRequests=@();executorRuns=@();history=@()},
            [pscustomobject]@{taskId='SYN-TASK-002';title='Approval pending task';description='Source reports approval pending';assignedAgent='Tara';status='awaiting-approval';workflowStage='approval';logs=@();reportPaths=@();approvalRequests=@();executorRuns=@();history=@()},
            [pscustomobject]@{taskId='SYN-TASK-003';title='Source completed task';description='Source explicitly reports completed';assignedAgent='Maya';status='completed';workflowStage='completed';logs=@();reportPaths=@();approvalRequests=@();executorRuns=@();history=@()},
            [pscustomobject]@{taskId='SYN-TASK-004';title='Unknown status task';description='No invented outcome';assignedAgent='Codex CLI';status='custom-state';workflowStage='unknown-stage';logs=@();reportPaths=@();approvalRequests=@();executorRuns=@();history=@()},
            [pscustomobject]@{taskId='SYN-TASK-005';title='Unsupported assignment';description='Do not invent ownership';assignedAgent='someone-private';status='in-progress';workflowStage='implementation';logs=@();reportPaths=@();approvalRequests=@();executorRuns=@();history=@()},
            [pscustomobject]@{title='Malformed row';status='completed'}
        )
    }
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),($synthetic | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    $summary = (& $exporter -SourceStoreRoot $store -OutputPath $output | ConvertFrom-Json)
    if ($summary.exportedTaskCount -ne 4 -or $summary.omittedRecordCount -ne 2) { throw 'Unexpected exported or omitted record count.' }
    $payload = [IO.File]::ReadAllText($output) | ConvertFrom-Json
    if ($payload.sourceSystem -cne 'Repato Maya Task Store' -or $payload.milestones -isnot [array]) { throw 'Root import metadata was not preserved.' }
    $group = $payload.milestones[0]
    if ($group.title -cne ('Imported Tasks ' + [char]0x2014 + ' Not a Project Milestone') -or $group.provenance -cne 'Synthetic' -or $group.verificationStatus -cne 'Unverified') { throw 'Synthetic grouping metadata was not preserved.' }
    if ($group.tasks.Count -ne 4) { throw 'Expected all supported synthetic tasks.' }
    foreach ($task in $group.tasks) {
        foreach ($field in @('id','title','assignedAgent','status')) { if ($task.PSObject.Properties.Name -notcontains $field) { throw "Task missing required field: $field" } }
        if ($task.assignedAgent -notin @('Maya','Neil','Tara','Codex CLI','PowerShell')) { throw 'Task has an invalid assignedAgent enum.' }
    }
    if ($group.tasks[0].assignedAgent -cne 'Neil' -or $group.tasks[1].assignedAgent -cne 'Tara' -or $group.tasks[2].assignedAgent -cne 'Maya') { throw 'Recorded assignees were not preserved.' }
    if ($group.tasks[1].status -cne 'In Review' -or $group.tasks[1].sourceStatus -cne 'awaiting-approval' -or $group.tasks[1].verificationStatus -cne 'Unverified') { throw 'Awaiting Approval mapping or verification distinction failed.' }
    if ($group.tasks[2].status -cne 'Done' -or $group.tasks[2].sourceStatus -cne 'completed' -or $group.tasks[2].verificationStatus -cne 'Unverified') { throw 'Completed status mapping or evidence distinction failed.' }
    if ($group.tasks[3].status -cne 'Unverified' -or $group.tasks[3].workflowStage -cne 'Unverified') { throw 'Unsupported statuses were not marked unverified.' }
    $json = [IO.File]::ReadAllText($output)
    if ($json -match 'C:\\Users|private\\secret|project\.rvt|private@example\.com|abc123|someone-private|raw log') { throw 'Sensitive path, username, credential-like value, or log content leaked.' }
    if ($group.tasks[0].evidenceReferences.Count -ne 1 -or $group.tasks[0].evidenceReferences[0].verificationStatus -cne 'Unverified') { throw 'Evidence reference mapping failed.' }
    'Synthetic exporter regression checks passed.'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
