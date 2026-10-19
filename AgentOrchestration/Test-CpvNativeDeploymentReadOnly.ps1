[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReleaseRoot,[Parameter(Mandatory)][string]$ManifestSha256)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$logs=Join-Path $repo 'QA\Engineering\CPV-NativeEngineering127-20261019'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if($identity.Name -ine 'RAMSAI\RepatoQA' -or $identity.User.Value -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015'){throw 'Interactive QA identity mismatch.'}
$baseline=Get-Content -LiteralPath (Join-Path $logs 'protected-before.json') -Raw|ConvertFrom-Json
function Assert-Protected {
    foreach($file in $baseline){if((Get-FileHash -LiteralPath $file.Path -ErrorAction Stop).Hash -cne $file.Sha256){throw ('Protected evidence changed: '+$file.Path)}}
}
Assert-Protected
$maya=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -PassThru -WarningAction SilentlyContinue
$state=& $maya {
    param($repo)
    $task=Find-RepatoTask (Read-RepatoTaskStore (Join-Path $repo 'QA\MayaRuns')) 'task-bf61fe7f22d74df7a92599681da5919e'
    $workflow=@($task.deploymentWorkflows|Where-Object workflowId -ceq 'fa2c2f578cbc40cbacac45c96313ca4c')[0]
    $binding=New-CpvNativeContinuationBinding -Task $task -Workflow $workflow -ExpectedTaskRevision 127
    $health=Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 10000
    if(!$health.Ready -or !$health.UserInteractive){throw 'Authenticated agent health unavailable.'}
    [pscustomobject]@{TaskRevision=$task.revision;Recovery=$task.cpvPreparationRecovery.Status;HistoricalExpiry=$binding.HistoricalPreparationExpiresUtc;ContinuationValid=$true;Health=$health}
} $repo
try {
    # This is the supported deployment guard only. There is no Execute parameter here.
    $json=& (Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1') -ReleaseRoot $ReleaseRoot -ManifestSha256 $ManifestSha256 -RecoveredNativeContinuation -ExpectedTaskRevision 127 -PreflightOnly
    $preflight=($json -join [Environment]::NewLine)|ConvertFrom-Json
    if(!$preflight.UpgradeAccepted -or $preflight.SideEffectsPerformed -or $preflight.InstallationPerformed -or $preflight.RevitLaunched){throw 'Read-only deployment guard did not pass.'}
    [pscustomobject]@{State=$state;DeploymentPreflight=$preflight;ProtectedFilesUnchanged=$true;ProtectedFileCount=$baseline.Count}|ConvertTo-Json -Depth 12
} finally {Assert-Protected}
