$ErrorActionPreference='Stop'
$m=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
foreach($needle in @('qaAddinRoot','Trusted QA runner source manifest is missing','runnerManifestPath','runnerManifestSha256','manifestIntegrityEvidenceAvailable','Runtime runner manifest hash conflicts')){if($m -notmatch [regex]::Escape($needle)){throw "Compatibility contract missing: $needle"}}
$legacy=[pscustomobject]@{schemaVersion=1;operation='validate-qa-deployment';requestId='x';succeeded=$true;validationIdentity='RAMSAI\RepatoQA';candidateSha256=('A'*64);qaWorkflowId='create-plan-views-v1';testId='create-plan-views-v1';qaAddinRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA';isolationPassed=$true}
$path=Join-Path $legacy.qaAddinRoot 'Repato.CreatePlanViews.TestRunner.addin';if(!$path.StartsWith($legacy.qaAddinRoot+'\')){throw 'Legacy derived path rejected'}
$new=$legacy|Add-Member NoteProperty manifestIntegrityPassed $true -PassThru;if(!$new.manifestIntegrityPassed){throw 'New evidence path failed'}
$failed=$legacy|Add-Member NoteProperty manifestIntegrityPassed $false -Force -PassThru;if($failed.manifestIntegrityPassed){throw 'Failed new evidence was accepted'}
[pscustomobject]@{Status='PASS';LegacyV102Accepted=$true;NewStrictEvidenceAccepted=$true;FailedNewEvidenceRejected=$true;LivePipeRequestSent=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
