$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force

$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$storeRoot=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('maya-single-attempt-'+[guid]::NewGuid().ToString('N'))))
$qaRuns=[IO.Path]::GetFullPath((Join-Path $root 'QA\TestRuns'))
$before=@(Get-ChildItem -LiteralPath $qaRuns -Force -ErrorAction SilentlyContinue|Select-Object -ExpandProperty FullName)
$fixture=Join-Path $root 'QA\Fixtures\CreatePlanViewsEmpty.rvt'
$candidateDir=Join-Path $root 'DeploymentCandidates\AgentBuilds\ReleaseCandidate-fcf624ee3ed1'
$candidateDll=Join-Path $candidateDir 'Repato.Revit.dll'
$fixtureHash=(Get-FileHash $fixture -Algorithm SHA256).Hash
$candidateHash=(Get-FileHash $candidateDll -Algorithm SHA256).Hash
$manifestPath='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin'
$manifestHash='AF4DBFA78E61524DE7BD3B84178C6B70ED8D29D0A95BA17780826E09BE689D4F'
$candidateExpected='7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2'
if($candidateHash -ine $candidateExpected){throw 'Frozen candidate precondition hash mismatch.'}
$results=[Collections.Generic.List[object]]::new();$syntheticIds=[Collections.Generic.List[string]]::new()

function Invoke-BoundaryCase {
 param([string]$Name,[object]$Validation)
 $caseStore=Join-Path $storeRoot $Name;New-Item -ItemType Directory -Path $caseStore -Force|Out-Null
 $injectedValidation=$Validation
 $validationInvoker={param($commit,$hash,$qa,$test)$callState.Count++|Out-Null;$injectedValidation}.GetNewClosure()
 if($Name -eq 'positive'){
  if($Validation.GetType().FullName -ne 'System.Management.Automation.PSCustomObject' -or @($Validation).Count -ne 1){throw "Positive validation fixture is not a scalar PSCustomObject: type=$($Validation.GetType().FullName); count=$(@($Validation).Count)"}
  foreach($property in @('runnerManifestPath','runnerManifestSha256','succeeded','isolationPassed','manifestIntegrityEvidenceAvailable','manifestIntegrityPassed')){if($Validation.PSObject.Properties.Name -notcontains $property){throw "Positive validation fixture is missing $property."}}
  $direct=@(& $validationInvoker fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3 7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2 create-plan-views-v1 create-plan-views-v1)
  if($direct.Count -ne 1 -or $direct[0].GetType().FullName -ne 'System.Management.Automation.PSCustomObject'){throw 'Positive validation closure did not return exactly one PSCustomObject.'}
  foreach($property in @('runnerManifestPath','runnerManifestSha256','succeeded','isolationPassed','manifestIntegrityEvidenceAvailable','manifestIntegrityPassed')){if($direct[0].PSObject.Properties.Name -notcontains $property){throw "Positive closure result is missing $property."}}
  $callState.Count=0
 }
 $beforeTasks=0;$attempt=$null;$claim=$null;$native=0;$revit=0;$handoff=$null;$request=$null;$error=$null
 try {
  $request=Invoke-MayaQaRequest -StoreRoot $caseStore -UserRequest 'Create Plan Views' -ArtifactMode FrozenCandidate -CandidateDirectory $candidateDir -CandidateDllPath $candidateDll -ExpectedCandidateSha256 $candidateExpected -ExpectedCandidateSourceCommit 'fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3' -ValidateExistingDeployment -DeploymentValidationInvoker $validationInvoker
  if($request.Stage -ne 'approval-required'){throw 'Expected approval-required result.'}
  $taskData=Read-RepatoTaskStore $caseStore;$task=Find-RepatoTask $taskData $request.TaskId
  $beforeTasks=@($taskData.tasks).Count
  if($Name -eq 'positive'){$null=Resolve-RepatoTaskApproval $caseStore $request.TaskId approve user 'synthetic approval';$handoff=New-MayaQaCanonicalPreparation -StoreRoot $caseStore -TaskId $request.TaskId -WorkflowId $request.WorkflowId -QaWorkflowId $request.QaWorkflowId;$attempt=$handoff.Attempt.AttemptId;$claim='not-claimed';$native=0;if($handoff.Handoff.RunnerManifestPath -cne $manifestPath -or $handoff.Handoff.RunnerManifestSha256 -cne $manifestHash){throw 'Validated manifest evidence did not reach the real handoff.'}}
 } catch {$error=$_.Exception.Message}
 $d=Read-RepatoTaskStore $caseStore;$t=if(@($d.tasks).Count){@($d.tasks)[0]}else{$null};if($t){foreach($w in @($t.deploymentWorkflows)){if($w.PSObject.Properties.Name -contains 'qaModelPath' -and $w.qaModelPath){$syntheticRuntimePaths.Add([IO.Path]::GetDirectoryName([string]$w.qaModelPath))|Out-Null}}};if($t -and $t.PSObject.Properties.Name -contains 'mayaTaraAttempt'){$attempt=$t.mayaTaraAttempt.AttemptId};if($t -and $t.PSObject.Properties.Name -contains 'mayaTaraExecution'){$claim=$t.mayaTaraExecution.ClaimId}
 [pscustomobject]@{Name=$Name;Request=$request;Handoff=$handoff;Attempt=$attempt;Claim=$claim;Native=$native;Revit=$revit;Error=$error;TaskCount=@($d.tasks).Count;Store=$caseStore}
}

$callState=[pscustomobject]@{Count=0}
$syntheticRuntimePaths=[Collections.Generic.List[string]]::new()
$valid=[pscustomobject]@{succeeded=$true;validationIdentity='RAMSAI\RepatoQA';qaWorkflowId='create-plan-views-v1';testId='create-plan-views-v1';candidateSha256=$candidateExpected;isolationPassed=$true;qaAddinRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA';runnerManifestPath=$manifestPath;runnerManifestSha256=$manifestHash;manifestIntegrityEvidenceAvailable=$true;manifestIntegrityPassed=$true}
$missing=[pscustomobject]@{succeeded=$true;candidateSha256=$candidateExpected;isolationPassed=$true}
$wrongPath=[pscustomobject]@{succeeded=$true;candidateSha256=$candidateExpected;isolationPassed=$true;qaAddinRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA';runnerManifestPath='C:\wrong.addin';runnerManifestSha256=$manifestHash;manifestIntegrityEvidenceAvailable=$true;manifestIntegrityPassed=$true}
$wrongHash=[pscustomobject]@{succeeded=$true;candidateSha256=$candidateExpected;isolationPassed=$true;qaAddinRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA';runnerManifestPath=$manifestPath;runnerManifestSha256=('0'*64);manifestIntegrityEvidenceAvailable=$true;manifestIntegrityPassed=$true}
$validationFailure=[pscustomobject]@{succeeded=$false;errorCode='synthetic-validation-failure'}
$cases=@(
 Invoke-BoundaryCase -Name 'positive' -Validation $valid
 Invoke-BoundaryCase -Name 'missing' -Validation $missing
 Invoke-BoundaryCase -Name 'wrong-path' -Validation $wrongPath
 Invoke-BoundaryCase -Name 'wrong-hash' -Validation $wrongHash
 Invoke-BoundaryCase -Name 'validation-failure' -Validation $validationFailure
)
$positive=$cases|? Name -eq positive
if(!$positive.Attempt){throw "Positive case did not create canonical attempt: $($positive.Error)"}
if($callState.Count -ne 5){throw "Expected five injected validation calls, got $($callState.Count)"}
foreach($bad in @($cases|? Name -ne positive)){if($bad.Attempt -or $bad.Claim -or $bad.Native -ne 0 -or $bad.Revit -ne 0){throw "Negative case crossed execution boundary: $($bad.Name)"}}
$new=@(Get-ChildItem -LiteralPath $qaRuns -Force -ErrorAction SilentlyContinue|? {$before -notcontains $_.FullName})
foreach($path in @($syntheticRuntimePaths|Select-Object -Unique)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force}}
$unowned=@($new|? {$syntheticRuntimePaths -notcontains $_.FullName});foreach($item in $unowned){throw "Unowned synthetic runtime artifact: $($item.FullName)"}
$after=@(Get-ChildItem -LiteralPath $qaRuns -Force -ErrorAction SilentlyContinue|Select-Object -ExpandProperty FullName)
if((Compare-Object $before $after).Count){throw 'Pre-existing QA TestRuns inventory changed.'}
if((Get-FileHash $fixture -Algorithm SHA256).Hash -ine $fixtureHash){throw 'Fixture hash changed.'}
if((Get-FileHash $candidateDll -Algorithm SHA256).Hash -ine $candidateHash){throw 'Candidate hash changed.'}
Write-Output 'Real frozen-candidate evidence/handoff boundary synthetic checks passed: positive + 4 negative cases'
