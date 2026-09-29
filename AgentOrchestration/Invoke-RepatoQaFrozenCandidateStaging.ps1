param([Parameter(Mandatory)][string]$RequestPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.QaAddinDeployment.psm1') -Force
$r=Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
if($r.schemaVersion -ne 1 -or $r.operation -cne 'stage-frozen-candidate-for-qa' -or [string]$r.candidateCommit -cne 'fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3' -or [string]$r.expectedCandidateSha256 -cne '7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2' -or [string]$r.qaWorkflowId -cne 'create-plan-views-v1' -or [string]$r.testId -cne $r.qaWorkflowId){throw 'Invalid fixed staging request.'}
$candidate='C:\Repato-Autonomous\Source\DeploymentCandidates\AgentBuilds\ReleaseCandidate-fcf624ee3ed1'
$x=Install-TaraFrozenCandidateForQa -CandidateDirectory $candidate -ExpectedArtifactSha256 $r.expectedCandidateSha256 -ExpectedSourceCommit $r.candidateCommit -QaWorkflowId $r.qaWorkflowId -TestId $r.testId
[pscustomobject]@{schemaVersion=1;operation=$r.operation;requestId=$r.requestId;succeeded=[bool]$x.Success;candidateCommit=$x.CandidateSourceCommit;candidateSha256=$x.CandidateSha256;qaWorkflowId=$x.QaWorkflowId;testId=$x.TestId;stagingIdentity=[Security.Principal.WindowsIdentity]::GetCurrent().Name;qaAddinRoot=$x.TargetRoot;isolationPassed=[bool]$x.Isolation.Allowed;receiptPath=$x.StagingEvidencePath;errorCode=$null;errorMessage=$null}|ConvertTo-Json -Compress
