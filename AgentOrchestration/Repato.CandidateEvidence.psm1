Set-StrictMode -Version Latest

function New-RepatoCandidateEvidence {
    param(
        [Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId,
        [Parameter(Mandatory)][string]$CandidateSourceCommit,[Parameter(Mandatory)][string]$CandidateDirectory,
        [Parameter(Mandatory)][string]$CandidateDllPath,[Parameter(Mandatory)][string]$CandidateDllSha256,
        [Parameter(Mandatory)][string]$NeilBuildArtifactSha256,[Parameter(Mandatory)][string]$RunnerManifestPath,
        [Parameter(Mandatory)][string]$RunnerManifestSha256,[Parameter(Mandatory)][string]$CandidateProvenancePath
    )
    [pscustomobject][ordered]@{
        SchemaVersion=1;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;TestId=$TestId
        CandidateSourceCommit=$CandidateSourceCommit;CandidateDirectory=$CandidateDirectory
        CandidateDllPath=$CandidateDllPath;CandidateDllSha256=$CandidateDllSha256
        NeilBuildArtifactSha256=$NeilBuildArtifactSha256;RunnerManifestPath=$RunnerManifestPath
        RunnerManifestSha256=$RunnerManifestSha256;CandidateProvenancePath=$CandidateProvenancePath
    }
}

function ConvertTo-RepatoCandidateEvidenceJson {
    param([Parameter(Mandatory)]$Evidence)
    $Evidence | ConvertTo-Json -Depth 10 -Compress
}

function ConvertFrom-RepatoCandidateEvidenceJson {
    param([Parameter(Mandatory)][string]$Json)
    try { $value=$Json | ConvertFrom-Json -ErrorAction Stop } catch { throw 'Candidate evidence is not valid JSON.' }
    $null=Assert-RepatoCandidateEvidenceShape $value
    $value
}

function Assert-RepatoCandidateEvidenceShape {
    param([Parameter(Mandatory)]$Evidence)
    if($null -eq $Evidence -or $Evidence.PSObject.Properties.Name -notcontains 'SchemaVersion' -or [int]$Evidence.SchemaVersion -ne 1){throw 'Candidate evidence schema version is invalid.'}
    foreach($name in 'TaskId','WorkflowId','QaWorkflowId','TestId','CandidateSourceCommit','CandidateDirectory','CandidateDllPath','CandidateDllSha256','NeilBuildArtifactSha256','RunnerManifestPath','RunnerManifestSha256','CandidateProvenancePath'){
        if($Evidence.PSObject.Properties.Name -notcontains $name -or [string]::IsNullOrWhiteSpace([string]$Evidence.$name)){throw "Candidate evidence is missing $name."}
    }
    foreach($name in 'CandidateDllSha256','NeilBuildArtifactSha256','RunnerManifestSha256'){
        if([string]$Evidence.$name -notmatch '^[0-9A-Fa-f]{64}$'){throw "Candidate evidence has an invalid $name."}
    }
    if([string]$Evidence.TestId -cne [string]$Evidence.QaWorkflowId){throw 'Candidate evidence TestId must equal QaWorkflowId.'}
    if([string]$Evidence.CandidateSourceCommit -notmatch '^[0-9A-Fa-f]{40}$'){throw 'Candidate source commit is invalid.'}
    $Evidence
}

function Resolve-RepatoCandidateEvidence {
    param(
        [Parameter(Mandatory)]$Evidence,[Parameter(Mandatory)]$AuthenticatedEvidence,
        [Parameter(Mandatory)][string]$ApprovedCandidateRoot,[Parameter(Mandatory)][string]$ApprovedRunnerManifestRoot,
        [Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId
    )
    $null=Assert-RepatoCandidateEvidenceShape $Evidence
    $null=Assert-RepatoCandidateEvidenceShape $AuthenticatedEvidence
    foreach($name in 'TaskId','WorkflowId','QaWorkflowId','TestId'){if([string]$Evidence.$name -cne (Get-Variable $name -ValueOnly)){throw "Candidate evidence identity mismatch: $name."}}
    foreach($name in 'TaskId','WorkflowId','QaWorkflowId','TestId','CandidateSourceCommit','CandidateDllSha256','NeilBuildArtifactSha256','RunnerManifestPath','RunnerManifestSha256'){
        if([string]$Evidence.$name -cne [string]$AuthenticatedEvidence.$name){throw "Authenticated candidate evidence mismatch: $name."}
    }
    if([string]$Evidence.CandidateDllSha256 -ine [string]$AuthenticatedEvidence.NeilBuildArtifactSha256){throw 'Candidate DLL hash does not match authenticated Neil build artifact hash.'}
    $root=[IO.Path]::GetFullPath($ApprovedCandidateRoot).TrimEnd('\')+'\'
    $dir=[IO.Path]::GetFullPath([string]$Evidence.CandidateDirectory)
    if(!$dir.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Candidate directory is outside the approved candidate root.'}
    $dll=[IO.Path]::GetFullPath([string]$Evidence.CandidateDllPath)
    if(!$dll.StartsWith($dir.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Candidate DLL is outside the validated candidate directory.'}
    $manifestRoot=[IO.Path]::GetFullPath($ApprovedRunnerManifestRoot).TrimEnd('\')+'\'
    $runner=[IO.Path]::GetFullPath([string]$Evidence.RunnerManifestPath)
    if(!$runner.StartsWith($manifestRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Runner manifest is outside the approved manifest root.'}
    $provenance=[IO.Path]::GetFullPath([string]$Evidence.CandidateProvenancePath)
    if(!$provenance.StartsWith($dir.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Candidate provenance is outside the candidate directory.'}
    foreach($path in @($dll,$runner,$provenance)){if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Candidate evidence file is missing: $path"}}
    $actualDll=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    if($actualDll -ine [string]$Evidence.CandidateDllSha256){throw 'Candidate DLL filesystem hash mismatch.'}
    $actualRunner=(Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash
    if($actualRunner -ine [string]$Evidence.RunnerManifestSha256){throw 'Runner manifest filesystem hash mismatch.'}
    $p=try{Get-Content -LiteralPath $provenance -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Candidate provenance is invalid JSON.'}
    if([string]$p.SourceCommit -cne [string]$Evidence.CandidateSourceCommit -or [string]$p.FrozenArtifactSha256 -ine [string]$Evidence.CandidateDllSha256){throw 'Candidate provenance does not match authenticated evidence.'}
    [pscustomobject]@{Evidence=$Evidence;CandidateDirectory=$dir;CandidateDllPath=$dll;CandidateDllSha256=$actualDll;RunnerManifestPath=$runner;RunnerManifestSha256=$actualRunner;CandidateProvenancePath=$provenance;CandidateSourceCommit=[string]$p.SourceCommit}
}

Export-ModuleMember -Function New-RepatoCandidateEvidence,ConvertTo-RepatoCandidateEvidenceJson,ConvertFrom-RepatoCandidateEvidenceJson,Assert-RepatoCandidateEvidenceShape,Resolve-RepatoCandidateEvidence
