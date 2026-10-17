[CmdletBinding()]
param()
$ErrorActionPreference='Stop'

$repoRoot=Split-Path $PSScriptRoot -Parent
$bundleModule=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvInstallerBundle.psm1') -Force -PassThru
$sourceFiles=@(& $bundleModule {$script:SourceFiles})
if($sourceFiles.Count -ne 13){throw "Expected 13 pinned installer source dependencies, found $($sourceFiles.Count)."}
foreach($relative in $sourceFiles){if(!(Test-Path -LiteralPath (Join-Path $repoRoot ($relative.Replace('/','\'))) -PathType Leaf)){throw "Pinned installer dependency is missing: $relative"}}

$platformDependencies=@(& $bundleModule {$script:PlatformDependencies})
if($platformDependencies.Count -ne 7){throw "Expected 7 declared platform dependencies, found $($platformDependencies.Count)."}

$installerPath=Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1'
$installer=Get-Content -LiteralPath $installerPath -Raw
$bootstrapImport=$installer.IndexOf("Import-Module (Join-Path `$PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1')")
$recoveryImport=$installer.IndexOf("Import-Module (Join-Path `$PSScriptRoot 'Repato.CpvPreparationRecovery.psm1')")
$upgradeImport=$installer.IndexOf("Import-Module (Join-Path `$PSScriptRoot 'Repato.CpvPreparationUpgrade.psm1')")
 $mayaImport=$installer.IndexOf("Import-Module (Join-Path `$PSScriptRoot 'Repato.MayaQaWorkflow.psm1')")
if($bootstrapImport -lt 0 -or $recoveryImport -lt 0 -or $upgradeImport -lt 0 -or $mayaImport -lt 0 -or !($bootstrapImport -lt $recoveryImport -and $recoveryImport -lt $upgradeImport -and $upgradeImport -lt $mayaImport)){
    throw 'Installer must load Maya after recovery and upgrade modules so their forced nested import cannot hide the health API.'
}

Import-Module (Join-Path $repoRoot 'QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationRecovery.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationUpgrade.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
. (Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1')

$entrypoints=@(
    (Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1'),
    (Join-Path $PSScriptRoot 'Invoke-CpvPreparationRecovery.ps1'),
    (Join-Path $PSScriptRoot 'Recover-CpvPreparationAgentInstall.ps1'),
    (Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1')
)
$commands=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($path in $entrypoints){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "Installer dependency source does not parse: $path ($($errors[0].Message))"}
    foreach($command in $ast.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst]},$true)){
        if($command.CommandElements[0] -is [Management.Automation.Language.StringConstantExpressionAst]){[void]$commands.Add($command.GetCommandName())}
    }
}
if($commands.Count -ne 49){throw "Installer entrypoints now contain $($commands.Count) unique command references; review the documented dependency count."}

$bootstrap=Get-Module 'Repato.QaLaunchAgent.Bootstrap'
$privateBootstrapCommands=@('Test-TaskSpec','Read-ValidatedManifest','Get-InstallJournal','Set-InstallJournalState','Invoke-InstallJournalRecoveryCore','New-RealBootstrapContext','Close-InstallJournalLease')
foreach($name in $privateBootstrapCommands){
    & $bootstrap {param($commandName)if(!(Get-Command $commandName -ErrorAction SilentlyContinue)){throw "Bootstrap private dependency is missing: $commandName"}} $name
    [void]$commands.Remove($name)
}
[void]$commands.Remove('Get-CpvRevitProcesses')
foreach($name in $commands){if(!(Get-Command $name -ErrorAction SilentlyContinue)){throw "Installer command dependency is not visible after the production import sequence: $name"}}
if(!(Get-Command Invoke-MayaQaLaunchAgentHealth -ErrorAction SilentlyContinue)){throw 'Maya authenticated health command is not exported to the installer scope.'}
$signatures=@{
    'Invoke-MayaQaLaunchAgentHealth'=@('TimeoutMilliseconds')
    'Stop-RepatoQaLaunchAgentForUpdate'=@('ExpectedAgentPid','ExpectedAgentStartTime','ExpectedSessionId','AgentExe','TaskPath','TaskName')
    'Install-RepatoQaLaunchAgentBootstrap'=@('SourceRoot','ManifestPath','ManifestSha256','RetainRollback','DurableJournal')
    'Invoke-CpvPreparationTransport'=@('Request')
}
foreach($entry in $signatures.GetEnumerator()){
    $command=Get-Command $entry.Key -ErrorAction Stop
    foreach($parameter in $entry.Value){if(!$command.Parameters.ContainsKey($parameter)){throw "Installer API signature mismatch: $($entry.Key) is missing -$parameter."}}
}

[pscustomobject]@{
    Test='CpvInstallerDependencies'
    SourceDependencies=$sourceFiles.Count
    PlatformDependencies=$platformDependencies.Count
    UniqueCommandReferences=49
    ResolvedVisibleCommands=$commands.Count
    BootstrapPrivateCommands=$privateBootstrapCommands.Count
    CommandSignaturesValidated=$signatures.Count
    AuthenticatedHealthCommandVisible=$true
    InstallerOperationsInvoked=$false
    RevitLaunched=$false
}|ConvertTo-Json -Compress
