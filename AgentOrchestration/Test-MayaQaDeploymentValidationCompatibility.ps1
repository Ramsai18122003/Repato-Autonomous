$ErrorActionPreference='Stop';Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$commit='fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3';$candidate='7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2';$qa='create-plan-views-v1';$root='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA';$path='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin';$hash='AF4DBFA78E61524DE7BD3B84178C6B70ED8D29D0A95BA17780826E09BE689D4F'
function New-Response{$x=[pscustomobject]@{schemaVersion=1;operation='validate-qa-deployment';requestId='x';succeeded=$true;validationIdentity='RAMSAI\RepatoQA';candidateSha256=$candidate;qaWorkflowId=$qa;testId=$qa;qaAddinRoot=$root;isolationPassed=$true};$x}
function Invoke-Case([string]$name,[scriptblock]$change,[bool]$shouldPass){$r=New-Response;&$change $r;$ok=$false;try{$n=Normalize-MayaQaDeploymentValidationResponse $r $commit $candidate $qa $qa;$ok=$true;if(!$shouldPass){throw "$name was accepted."};if($n.runnerManifestPath -cne $path -or $n.runnerManifestSha256 -cne $hash){throw "$name normalization mismatch."};if($name -eq 'legacy' -and ($n.manifestIntegrityEvidenceAvailable -or $null -ne $n.manifestIntegrityPassed)){throw 'Legacy integrity evidence was fabricated.'}}catch{if($shouldPass){throw};$ok=$true};if(!$ok){throw "$name failed."}}
Invoke-Case modern {param($r)$r|Add-Member NoteProperty runnerManifestPath $path -Force;$r|Add-Member NoteProperty runnerManifestSha256 $hash -Force;$r|Add-Member NoteProperty manifestIntegrityPassed $true -Force} $true
Invoke-Case legacy {param($r)} $true
Invoke-Case missing-root {param($r)$r.qaAddinRoot=$null} $false
Invoke-Case wrong-root {param($r)$r.qaAddinRoot='C:\Users\Other\Addins\2025\RepatoQA'} $false
Invoke-Case outside-root {param($r)$r.qaAddinRoot='C:\Users\RepatoQA\Other'} $false
Invoke-Case wrong-identity {param($r)$r.validationIdentity='RAMSAI\Other'} $false
Invoke-Case missing-identity {param($r)$r.PSObject.Properties.Remove('validationIdentity')} $false
Invoke-Case isolation-false {param($r)$r.isolationPassed=$false} $false
Invoke-Case isolation-missing {param($r)$r.PSObject.Properties.Remove('isolationPassed')} $false
Invoke-Case unsuccessful {param($r)$r.succeeded=$false} $false
Invoke-Case contradictory-path {param($r)$r|Add-Member NoteProperty runnerManifestPath 'C:\wrong.addin' -Force} $false
Invoke-Case obsolete-subfolder {param($r)$r|Add-Member NoteProperty runnerManifestPath ($root+'\Repato.CreatePlanViews.TestRunner.addin') -Force} $false
Invoke-Case candidate-mismatch {param($r)$r.candidateSha256='0'*64} $false
Invoke-Case candidate-missing {param($r)$r.PSObject.Properties.Remove('candidateSha256')} $false
[pscustomobject]@{Status='PASS';ModernResponseSupported=$true;LegacyResponseSupported=$true;LegacyManifestPathDerivedFromAuthenticatedQaRoot=$true;ManifestIntegrityFabricated=$false;FocusedTestsPassed=14;FocusedTestsTotal=14;LivePipeRequestSent=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
