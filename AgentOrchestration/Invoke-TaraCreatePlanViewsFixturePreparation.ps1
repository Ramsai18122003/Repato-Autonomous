param(
    [string]$StoreRoot='C:\Repato-Autonomous\Source\QA\MayaRuns',
    [string]$TaskId='task-41cfec12ef3e406990d36c9997cf6591',
    [string]$WorkflowId='78b5a11ab95e4cac86dcf45a1cb9cfdc'
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Force -WarningAction SilentlyContinue
if(@(Get-Process Revit -ErrorAction SilentlyContinue).Count){throw 'An existing Revit process is present; fixture preparation launch is refused.'}
$task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
$workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
$evidence=$workflow.qaBuildEvidence
if($task.status -cne 'passed' -or !$evidence -or !$evidence.DeploymentValidation -or !$evidence.ManifestIntegrityValidation -or !$evidence.QaIsolation){throw 'Frozen candidate approval, validation, manifest integrity, or isolation gate is not satisfied.'}
$qa=Join-Path (Split-Path $PSScriptRoot -Parent) 'QA'
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
$plan=New-TaraRevitQaPlan -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId 'create-plan-views-v1' -RunId $runId -ModelPath $model -SidecarPath $sidecar -ReportDirectory (Join-Path $qa 'Reports') -RevitInstallDir 'E:\revit\Revit 2025' -QaAddinRoot 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA' -TimeoutSeconds 900 -FixturePreparation -ManualLoadOnce -Context $context
$result=Invoke-TaraRevitQa -Plan $plan
[pscustomobject]@{Success=$result.Success;Status=$result.Status;TaskId=$TaskId;WorkflowId=$WorkflowId;AttemptId=$plan.RequestId;RunId=$runId;ProcessId=$result.ProcessId;PromptDetected=$result.PromptDetected;PromptAction=$result.PromptAction;ModelPath=$model;SourceModelSha256=$sourceHash;PreparedModelSha256=(Get-FileHash $model -Algorithm SHA256).Hash;RequestPath=$plan.RequestPath;PreparationPath=$plan.ResultPath;EvidencePath=$plan.EvidencePath;Failure=$result.FailureReason;Preparation=$result.Preparation}|ConvertTo-Json -Depth 8
if(!$result.Success){throw "Disposable fixture preparation failed: $($result.FailureReason)"}
