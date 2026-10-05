$ErrorActionPreference='Stop'
$tara=Get-Content (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Raw
$maya=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
if($tara -notmatch '\[scriptblock\]\$SessionValidationInvoker'){throw 'Session validation boundary is missing.'}
if($tara -notlike '*if(!$DryRun){if($SessionValidationInvoker){& $SessionValidationInvoker}else{Assert-TaraInteractiveSession}}*'){throw 'Session production default is missing.'}
if($maya -notmatch '\[scriptblock\]\$PlanPreflightInvoker'){throw 'Tara plan preflight boundary is missing.'}
if($maya -notmatch 'if\(\$PlanPreflightInvoker\)\{& \$PlanPreflightInvoker'){throw 'Plan injection is missing.'}
if($maya -notlike '*New-TaraRevitQaPlan*SessionValidationInvoker $SessionValidationInvoker*'){throw 'Plan production default is missing.'}
'Focused Tara boundary source-shape checks passed: 4'
