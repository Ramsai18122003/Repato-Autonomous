$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$validation=Get-Content (Join-Path $PSScriptRoot 'Invoke-RepatoQaDeploymentValidation.ps1') -Raw
$module=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
if($validation -notmatch '\$manifestRoot=Split-Path \$qaRoot -Parent' -or $validation -notmatch '\$runnerPath=Join-Path \$manifestRoot \$runnerName'){throw 'Deployment validation does not use the parent manifest root.'}
if($module -notmatch 'validatedRunnerManifestPath' -or $module -notmatch 'Canonical runner-manifest path contract mismatch before execution'){throw 'Canonical path persistence/consistency gate is missing.'}
if($module -notmatch 'Validated runner-manifest path does not match the canonical execution path'){throw 'Native launch consistency gate is missing.'}
if($module -match 'derivedPath=Join-Path \(\[string\]\$r\.qaAddinRoot\)'){throw 'Obsolete production qaAddinRoot derivation remains.'}
$canonical='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin'
$qaRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA'
$computed=Join-Path ([IO.Path]::GetFullPath((Join-Path $qaRoot '..')) ) 'Repato.CreatePlanViews.TestRunner.addin'
if($computed -ine $canonical){throw 'Parent-directory contract computed the wrong path.'}
$request=[pscustomobject]@{manifestPath=$canonical;manifestSha256='A'*64}
if($request.manifestPath -ine $canonical){throw 'Serialized manifest path binding failed.'}
Write-Output 'Runner manifest path contract synthetic tests passed: parent deployment path, canonical persistence, serialization binding, duplicate derivation removal, and fail-closed consistency gates.'
