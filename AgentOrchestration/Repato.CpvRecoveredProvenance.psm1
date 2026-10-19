Set-StrictMode -Version Latest

function Read-CpvFixtureProvenance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SidecarPath,[string]$ExpectedRecoveredProvenanceSha256)
    $path=[IO.Path]::GetFullPath($SidecarPath)
    $side=Get-Content -LiteralPath $path -Raw -ErrorAction Stop|ConvertFrom-Json
    if(!$path.EndsWith('.rvt.fixture.json',[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected fixture sidecar path.'}
    $model=$path.Substring(0,$path.Length-'.fixture.json'.Length)
    $recoveredPath=$model+'.recovered.fixture.json'
    if(!(Test-Path -LiteralPath $recoveredPath -PathType Leaf)){
        if($ExpectedRecoveredProvenanceSha256){throw 'Required recovered provenance is missing.'}
        return $side
    }
    # A distinct attestation never replaces or upgrades the historical sidecar.
    foreach($p in @($path,$model,$recoveredPath)){
        for($part=$p;$part;$part=[IO.Path]::GetDirectoryName($part)){
            if((Get-Item -LiteralPath $part -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Recovered provenance reparse point rejected.'}
        }
    }
    $recoveredHash=(Get-FileHash -LiteralPath $recoveredPath -Algorithm SHA256).Hash
    if($ExpectedRecoveredProvenanceSha256 -and $recoveredHash -ine $ExpectedRecoveredProvenanceSha256){throw 'Recovered provenance hash mismatch.'}
    $r=Get-Content -LiteralPath $recoveredPath -Raw -ErrorAction Stop|ConvertFrom-Json
    if(!$r.PSObject.Properties['schemaVersion'] -or $r.schemaVersion -ne 1){throw 'Recovered provenance schema version mismatch.'}
    $fields=@('fixtureId','sourceSha256','preparedModelSha256','fixturePreparationRequestPath','fixturePreparationRequestSha256','fixturePreparationResultPath','fixturePreparationResultSha256','fixturePreparationAttemptId','fixturePreparationRunId')
    foreach($name in ($fields+@('historicalSidecarPath','historicalSidecarSha256','requestId','taskId','workflowId','recoveryApprovalId','approvalBindingHash','originalReceiptSha256','activeMarkerSha256','failureEvidenceSha256','requestSha256'))){
        if(!$r.PSObject.Properties[$name] -or $r.$name -isnot [string] -or [string]::IsNullOrWhiteSpace($r.$name)){throw "Recovered provenance required field missing: $name"}
    }
    foreach($name in @('sourceSha256','preparedModelSha256','fixturePreparationRequestSha256','fixturePreparationResultSha256','historicalSidecarSha256','approvalBindingHash','originalReceiptSha256','activeMarkerSha256','failureEvidenceSha256','requestSha256')){
        if($r.$name -cnotmatch '^[A-Fa-f0-9]{64}$'){throw "Recovered provenance invalid hash: $name"}
    }
    foreach($name in @('requestId','taskId','workflowId','fixturePreparationAttemptId','fixturePreparationRunId','recoveryApprovalId')){
        $value=$r.$name;if($name -ceq 'taskId'){$value=$value -replace '^task-',''}
        if($value -cnotmatch '^[a-f0-9]{32}$'){throw "Recovered provenance invalid identity: $name"}
    }
    if(!$r.PSObject.Properties['recoveredFromOutcomeUnknown'] -or $r.recoveredFromOutcomeUnknown -isnot [bool] -or $r.recoveredFromOutcomeUnknown -ne $true -or
        $r.fixtureId -cne 'CreatePlanViewsEmpty' -or $side.fixtureId -cne $r.fixtureId -or $side.sourceSha256 -ine $r.sourceSha256 -or
        [IO.Path]::GetFullPath($r.historicalSidecarPath) -ine $path -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $r.historicalSidecarSha256 -or
        (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine $r.preparedModelSha256){throw 'Recovered provenance historical sidecar/model mismatch.'}
    $names=@($side.PSObject.Properties.Name)
    if($names.Count -ne 2 -or @($names|Where-Object {$_ -cnotin @('fixtureId','sourceSha256')}).Count){
        if($names.Count -ne $fields.Count){throw 'Recovered provenance historical sidecar schema mismatch.'}
        foreach($name in $fields){if(!$side.PSObject.Properties[$name] -or [string]$side.$name -cne [string]$r.$name){throw 'Recovered provenance conflicts with historical prepared sidecar.'}}
    }
    $directory=[IO.Path]::GetDirectoryName($model)
    $requestPath=Join-Path $directory ('tara-'+$r.fixturePreparationAttemptId+'.request.json')
    $resultPath=$requestPath+'.preparation.json'
    if([IO.Path]::GetFullPath($r.fixturePreparationRequestPath) -ine $requestPath -or [IO.Path]::GetFullPath($r.fixturePreparationResultPath) -ine $resultPath){throw 'Recovered provenance request/result path mismatch.'}
    foreach($pair in @(@($requestPath,$r.fixturePreparationRequestSha256),@($resultPath,$r.fixturePreparationResultSha256))){
        if(!(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or (Get-Item -LiteralPath $pair[0] -Force).Attributes -band [IO.FileAttributes]::ReparsePoint -or (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw 'Recovered provenance request/result evidence missing or hash mismatch.'}
    }
    $q=Get-Content -LiteralPath $requestPath -Raw|ConvertFrom-Json
    $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
    if($q.operation -cne 'prepare-disposable-create-plan-views-fixture' -or $result.Operation -cne $q.operation -or $result.Status -cne 'Passed' -or
        $q.taskId -cne $r.taskId -or $q.workflowId -cne $r.workflowId -or $q.attemptId -cne $r.fixturePreparationAttemptId -or $q.runId -cne $r.fixturePreparationRunId -or
        $result.TaskId -cne $q.taskId -or $result.WorkflowId -cne $q.workflowId -or $result.AttemptId -cne $q.attemptId -or $result.RunId -cne $q.runId -or
        [IO.Path]::GetFullPath($q.modelPath) -ine $model -or [IO.Path]::GetFullPath($result.ModelPath) -ine $model -or
        [IO.Path]::GetFullPath($q.requestPath) -ine $requestPath -or [IO.Path]::GetFullPath($q.outputPath) -ine $resultPath -or
        $q.modelSha256 -ine $r.sourceSha256 -or $result.SourceModelSha256 -ine $r.sourceSha256 -or $result.PreparedModelSha256 -ine $r.preparedModelSha256){throw 'Recovered provenance request/result correlation mismatch.'}
    $r
}

Export-ModuleMember -Function Read-CpvFixtureProvenance
