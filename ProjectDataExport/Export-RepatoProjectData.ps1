[CmdletBinding()]
param(
    [string]$SourceStoreRoot = 'C:\Repato-Autonomous\AgentWork\AgentOrchestration\Store',
    [string]$OutputPath,
    [string]$SchemaPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $PSScriptRoot 'exports\repato-project-import.json' }

function Protect-ExportText([object]$Value) {
    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    $text = $text -replace '(?i)\b(password|passwd|token|secret|api[_-]?key|authorization)\b\s*[:=]\s*[^\s,;]+', '$1=[REDACTED]'
    $text = $text -replace '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[REDACTED_EMAIL]'
    $text = $text -replace '(?i)(?:[A-Z]:\\|\\\\[^\\\s]+\\[^\\\s]+\\)[^\s"''<>]*', '[REDACTED_PATH]'
    return $text
}

function Get-StatusMapping([object]$SourceStatus) {
    $raw = [string]$SourceStatus
    $map = @{
        'queued' = 'Not Started'
        'in-progress' = 'In Progress'
        'blocked' = 'Blocked'
        'failed' = 'Failed'
        'passed' = 'Unverified'
        'awaiting-approval' = 'In Review'
        'completed' = 'Done'
    }
    if ($map.ContainsKey($raw)) {
        return [pscustomobject]@{ Status=$map[$raw]; SourceStatus=$raw; VerificationStatus='Unverified' }
    }
    [pscustomobject]@{ Status='Unverified'; SourceStatus=(Protect-ExportText $raw); VerificationStatus='Unverified' }
}

function Add-EvidenceReference([System.Collections.Generic.List[object]]$Target,[string]$Kind,[object]$Value,[string]$TaskId) {
    foreach ($candidate in @($Value)) {
        if ($candidate -isnot [string] -or [string]::IsNullOrWhiteSpace($candidate)) { continue }
        $Target.Add([pscustomobject]@{
            id = ('evidence-' + $TaskId + '-' + ($Target.Count + 1))
            kind = $Kind
            availability = 'Not Checked'
            verificationStatus = 'Unverified'
        })
    }
}

function Get-TaskEvidence($Task) {
    $refs = [System.Collections.Generic.List[object]]::new()
    $id = [string]$Task.taskId
    Add-EvidenceReference $refs 'log' $Task.logs $id
    Add-EvidenceReference $refs 'report' $Task.reportPaths $id
    foreach ($field in @('ReportPath','ReportIntegrityPath','mayaTaraPacketPath')) {
        $value = $Task.PSObject.Properties[$field]
        if ($null -ne $value) { Add-EvidenceReference $refs 'report' $value.Value $id }
    }
    foreach ($propertyName in @('mayaTaraExecution','mayaTaraAttempt','mayaTaraQaPacket','neilChangeReport','neilBuildRequest')) {
        $property = $Task.PSObject.Properties[$propertyName]
        if ($null -eq $property -or $null -eq $property.Value) { continue }
        foreach ($field in @('ReportPath','EvidencePath','ReceiptPath','Path')) {
            $value = $property.Value.PSObject.Properties[$field]
            if ($null -ne $value) { Add-EvidenceReference $refs ($field -replace 'Path$','' -replace '^$','evidence') $value.Value $id }
        }
    }
    foreach ($workflow in @($Task.deploymentWorkflows)) {
        if ($null -eq $workflow) { continue }
        foreach ($field in @('qaReportPath','qaEvidence')) {
            $value = $workflow.PSObject.Properties[$field]
            if ($null -ne $value) { Add-EvidenceReference $refs 'qa-evidence' $value.Value $id }
        }
    }
    return @($refs)
}

function Get-ProjectionText([object]$Object,[string]$Field) {
    $property = $Object.PSObject.Properties[$Field]
    if ($null -eq $property -or $null -eq $property.Value) { return $null }
    return Protect-ExportText $property.Value
}

function Get-ReferencePresence([object]$Object,[string]$Field) {
    $property = $Object.PSObject.Properties[$Field]
    if ($null -eq $property) { return $null }
    if ($null -eq $property.Value) { return $false }
    if ($property.Value -is [array]) { return $property.Value.Count -gt 0 }
    return -not [string]::IsNullOrWhiteSpace([string]$property.Value)
}

function New-TaskOrchestrationProjection([object]$Task,[string]$AsOfUtc) {
    $projection = [ordered]@{ exportAsOfUtc=$AsOfUtc }
    $errorDetails = Get-ProjectionText $Task 'errorDetails'
    if ($errorDetails) { $projection.errorDetails = $errorDetails }

    $approvals = [System.Collections.Generic.List[object]]::new()
    foreach ($request in @($Task.approvalRequests)) {
        if ($null -eq $request) { continue }
        $item = [ordered]@{}
        foreach ($field in @('action','requiredLevel','status','expiresUtc','reason')) {
            $value = Get-ProjectionText $request $field
            if ($null -ne $value) { $item[$field] = $value }
        }
        $approvals.Add([pscustomobject]$item)
    }
    if ($null -ne $Task.PSObject.Properties['approvalRequests']) { $projection.approvalRequests = @($approvals) }

    $runs = [System.Collections.Generic.List[object]]::new()
    foreach ($run in @($Task.executorRuns)) {
        if ($null -eq $run) { continue }
        $item = [ordered]@{}
        foreach ($field in @('agent','phase','status','error')) {
            $value = Get-ProjectionText $run $field
            if ($null -ne $value) { $item[$field] = $value }
        }
        $runs.Add([pscustomobject]$item)
    }
    if ($null -ne $Task.PSObject.Properties['executorRuns']) { $projection.executorRuns = @($runs) }

    $plan = $Task.PSObject.Properties['mayaPlan']
    if ($null -ne $plan -and $null -ne $plan.Value) {
        $item = [ordered]@{}
        foreach ($field in @(@('NextAgent','nextAgent'),@('NextOperation','nextOperation'),@('Stage','stage'),@('Approval','approval'))) {
            $value = Get-ProjectionText $plan.Value $field[0]
            if ($null -ne $value) { $item[$field[1]] = $value }
        }
        if ($item.Count -gt 0) { $projection.plan = [pscustomobject]$item }
    }

    $buildRequest = $Task.PSObject.Properties['neilBuildRequest']
    if ($null -ne $buildRequest -and $null -ne $buildRequest.Value) {
        $buildStatus = Get-ProjectionText $buildRequest.Value 'Status'
        if ($buildStatus) { $projection.buildRequestStatus = $buildStatus }
    }

    $executionProperty = $Task.PSObject.Properties['mayaTaraExecution']
    if ($null -ne $executionProperty -and $null -ne $executionProperty.Value) {
        $execution = [ordered]@{}
        foreach ($field in @(@('Stage','stage'),@('ExecutionStatus','status'),@('FailureCode','failureCode'),@('FailureDetails','failureDetails'),@('RollbackStatus','rollbackStatus'),@('VerificationStatus','verificationStatus'),@('CompletionStatus','completionStatus'))) {
            $value = Get-ProjectionText $executionProperty.Value $field[0]
            if ($null -ne $value) { $execution[$field[1]] = $value }
        }
        $references = [ordered]@{}
        foreach ($field in @(@('RequestPath','request'),@('ResultPath','result'),@('ReportPath','report'),@('ReceiptPath','receipt'),@('EvidencePath','evidence'))) {
            $present = Get-ReferencePresence $executionProperty.Value $field[0]
            if ($null -ne $present) { $references[$field[1]] = $present }
        }
        if ($references.Count -gt 0) { $execution.references = [pscustomobject]$references }
        if ($execution.Count -gt 0) { $projection.execution = [pscustomobject]$execution }
    }

    $workflows = [System.Collections.Generic.List[object]]::new()
    foreach ($workflow in @($Task.deploymentWorkflows)) {
        if ($null -eq $workflow) { continue }
        $item = [ordered]@{}
        foreach ($field in @(@('stage','stage'),@('status','status'),@('approvalStatus','approvalStatus'),@('qaBuildStatus','qaBuildStatus'),@('qaVerificationStatus','qaVerificationStatus'),@('qaCompletionStatus','qaCompletionStatus'))) {
            $value = Get-ProjectionText $workflow $field[0]
            if ($null -ne $value) { $item[$field[1]] = $value }
        }
        if ($item.Count -gt 0) { $workflows.Add([pscustomobject]$item) }
    }
    if ($workflows.Count -gt 0) { $projection.workflowStates = @($workflows) }

    $references = [ordered]@{}
    foreach ($field in @(@('ReportPath','report'),@('ReportIntegrityPath','reportIntegrity'),@('mayaTaraPacketPath','qaPacket'))) {
        $present = Get-ReferencePresence $Task $field[0]
        if ($null -ne $present) { $references[$field[1]] = $present }
    }
    if ($references.Count -gt 0) { $projection.references = [pscustomobject]$references }
    return [pscustomobject]$projection
}
function Assert-StructuralPayload($Payload) {
    if ([string]$Payload.schemaVersion -ne '1.0') { throw 'Structural check failed: schemaVersion must be 1.0.' }
    if ([string]$Payload.sourceSystem -cne 'Repato Maya Task Store') { throw 'Structural check failed: sourceSystem is required.' }
    if ($Payload.milestones -isnot [array] -or $Payload.milestones.Count -ne 1) { throw 'Structural check failed: exactly one root milestones grouping container is required.' }
    $group = $Payload.milestones[0]
    if ($group.id -cne 'synthetic-import-task-group' -or $group.title -cne ('Imported Tasks ' + [char]0x2014 + ' Not a Project Milestone') -or $group.provenance -cne 'Synthetic' -or $group.verificationStatus -cne 'Unverified') { throw 'Structural check failed: synthetic grouping labels are missing or changed.' }
    foreach ($field in @('id','title','provenance','verificationStatus','tasks')) {
        if ($group.PSObject.Properties.Name -notcontains $field) { throw "Structural check failed: milestone group is missing $field." }
    }
    if ($group.tasks -isnot [array]) { throw 'Structural check failed: milestone group tasks must be an array.' }
    foreach ($task in $group.tasks) {
        foreach ($field in @('id','title','assignedAgent','status','sourceStatus','verificationStatus','evidenceReferences')) {
            if ($task.PSObject.Properties.Name -notcontains $field) { throw "Structural check failed: task is missing $field." }
        }
        if ([string]$task.assignedAgent -notin @('Maya','Neil','Tara','Codex CLI','PowerShell')) { throw 'Structural check failed: assignedAgent is outside the v1.0 enum.' }
        if ([string]$task.status -notin @('Not Started','In Progress','In Review','Done','Blocked','Failed','Unverified')) { throw 'Structural check failed: status is outside the v1.0 enum.' }
    }
    $json = $Payload | ConvertTo-Json -Depth 50
    if ($json -match '(?i)(?:[A-Z]:\\|\\\\[^\\\s]+\\[^\\\s]+\\)[^\s"''<>]*|\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b|\b(password|passwd|token|secret|api[_-]?key|authorization)\b\s*[:=]\s*(?!\[REDACTED\])[^\s,;]+') {
        throw 'Structural check failed: output contains a path, email address, or credential-like value.'
    }
    return $json
}

$storeRoot = [IO.Path]::GetFullPath($SourceStoreRoot)
$queuePath = Join-Path $storeRoot 'tasks.json'
if (!(Test-Path -LiteralPath $queuePath -PathType Leaf)) { throw "Task source is not readable or tasks.json is missing: $queuePath" }

$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
if ($outputFullPath.StartsWith($storeRoot.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase) -or $outputFullPath -ieq $queuePath) {
    throw 'OutputPath must be outside the source task store.'
}

try { $store = Get-Content -LiteralPath $queuePath -Raw | ConvertFrom-Json } catch { throw 'Task source JSON is unreadable or malformed.' }
if ($store.schemaVersion -ne 1 -or $store.tasks -isnot [array]) { throw 'Task source must contain schemaVersion 1 and a tasks array.' }

$exportAsOfUtc = [DateTime]::UtcNow.ToString('o')
$tasks = [System.Collections.Generic.List[object]]::new()
$omitted = [System.Collections.Generic.List[object]]::new()
foreach ($record in $store.tasks) {
    $taskId = [string]$record.taskId
    if ($taskId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$' -or [string]::IsNullOrWhiteSpace([string]$record.title)) {
        $omitted.Add([pscustomobject]@{ reason='Missing taskId or title'; recordIndex=$tasks.Count + $omitted.Count })
        continue
    }
    $status = Get-StatusMapping $record.status
    $assignee = [string]$record.assignedAgent
    if ($assignee -notin @('Maya','Neil','Tara','Codex CLI','PowerShell')) {
        $omitted.Add([pscustomobject]@{ reason='No supported explicit assignee'; recordIndex=$tasks.Count + $omitted.Count })
        continue
    }
    $stage = if ([string]$record.workflowStage -match '^(queued|assigned|implementation|build-checks|qa|approval|completed)$') { [string]$record.workflowStage } else { 'Unverified' }
    $tasks.Add([pscustomobject]@{
        id = $taskId
        title = Protect-ExportText $record.title
        description = Protect-ExportText $record.description
        assignedAgent = $assignee
        status = $status.Status
        sourceStatus = $status.SourceStatus
        workflowStage = $stage
        verificationStatus = $status.VerificationStatus
        evidenceReferences = @(Get-TaskEvidence $record)
        repatoOrchestration = (New-TaskOrchestrationProjection $record $exportAsOfUtc)
    })
}

$payload = [pscustomobject]@{
    schemaVersion = '1.0'
    sourceSystem = 'Repato Maya Task Store'
    exportedAt = $exportAsOfUtc
    milestones = @([pscustomobject]@{
        id = 'synthetic-import-task-group'
        title = ('Imported Tasks ' + [char]0x2014 + ' Not a Project Milestone')
        name = ('Imported Tasks ' + [char]0x2014 + ' Not a Project Milestone')
        provenance = 'Synthetic'
        verificationStatus = 'Unverified'
        tasks = @($tasks)
    })
}

$json = Assert-StructuralPayload $payload
$validation = 'Structural checks passed; v1.0 schema file was not supplied.'
if ($SchemaPath) {
    if (!(Test-Path -LiteralPath $SchemaPath -PathType Leaf)) { throw 'SchemaPath was supplied but the schema file is unavailable.' }
    if (!(Get-Command Test-Json -ErrorAction SilentlyContinue)) { throw 'A schema was supplied, but this PowerShell runtime has no Test-Json schema validator.' }
    $schemaResult = Test-Json -Json $json -SchemaFile $SchemaPath -ErrorAction Stop
    if (!$schemaResult) { throw 'JSON Schema v1.0 validation failed.' }
    $validation = 'JSON Schema v1.0 validation passed.'
}

$parent = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$temporaryPath = $outputFullPath + '.partial'
try {
    [IO.File]::WriteAllText($temporaryPath,$json + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
} finally {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
}

[pscustomobject]@{
    outputPath = $outputFullPath
    exportedTaskCount = $tasks.Count
    omittedRecordCount = $omitted.Count
    omittedRecords = @($omitted)
    validation = $validation
    sourceStoreReadOnly = $true
    sensitiveLogContentsIncluded = $false
    absolutePathsIncluded = $false
} | ConvertTo-Json -Depth 8
