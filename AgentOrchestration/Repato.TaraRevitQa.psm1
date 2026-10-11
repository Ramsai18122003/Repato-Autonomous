Set-StrictMode -Version Latest

function Assert-TaraPath {
    param([string]$Path,[string]$Root,[switch]$Leaf)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':') -or $Path -match '["\r\n]') { throw 'An absolute local path without alternate streams is required.' }
    $full=[IO.Path]::GetFullPath($Path)
    if($Root -and !$full.StartsWith(([IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw "Path outside approved QA root: $full"}
    if(([IO.DriveInfo]::new([IO.Path]::GetPathRoot($full))).DriveType -ne [IO.DriveType]::Fixed){throw 'A fixed local drive is required.'}
    for($part=$full;$part;$part=[IO.Path]::GetDirectoryName($part)){
        try { $exists=Test-Path -LiteralPath $part -ErrorAction Stop }
        catch { throw "Path inaccessible: $part. Access was denied while validating the QA path." }
        if($exists){
            try { $item=Get-Item -LiteralPath $part -Force -ErrorAction Stop }
            catch { throw "Path inaccessible: $part. Access was denied while validating the QA path." }
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Reparse point rejected: $part"}
        }
    }
    if($Leaf){
        try { $leafExists=Test-Path -LiteralPath $full -PathType Leaf -ErrorAction Stop }
        catch { throw "Path inaccessible: $full. Access was denied while validating the QA path." }
        if(!$leafExists){throw "Required file missing: $full"}
    }
    $full
}
function Get-TaraSha256([string]$Path){
    $s=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite);$h=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($h.ComputeHash($s))).Replace('-','')}finally{$h.Dispose();$s.Dispose()}
}
# Names required by the existing shared isolation policy, scoped to this module.
function Assert-ChildPath([string]$Path,[string]$Parent){Assert-TaraPath $Path $Parent}
function Get-Sha256([string]$Path){Get-TaraSha256 $Path}
. (Join-Path $PSScriptRoot '..\QA\AddinIsolation.ps1')
function Get-TaraRuntimeRoots {
    $profile='C:\Users\RepatoQA'
    if([Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1] -ieq 'RepatoQA'){$profile=[Environment]::GetFolderPath('UserProfile')}
    [pscustomobject]@{QaRoot='C:\Repato-Autonomous\Source\QA';UserAddinsRoot=(Join-Path $profile 'AppData\Roaming\Autodesk\Revit\Addins\2025');MachineRoot='C:\ProgramData\Autodesk\Revit\Addins\2025'}
}
function Assert-TaraInteractiveSession {
    if([Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1] -ine 'RepatoQA'){throw 'Real execution requires the dedicated RepatoQA Windows identity.'}
    if(![Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'An interactive RepatoQA desktop session is required; Session 0 is prohibited.'}
    if(!( 'Repato.TaraDesktop' -as [type])){
        Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace Repato { public static class TaraDesktop { [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access); [DllImport("user32.dll", SetLastError=true)] public static extern bool SwitchDesktop(IntPtr desktop); [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr desktop); } }'
    }
    $desktop=[Repato.TaraDesktop]::OpenInputDesktop(0,$false,0x0100)
    if($desktop -eq [IntPtr]::Zero){throw 'RepatoQA must be logged in with an unlocked interactive desktop.'}
    try{if(![Repato.TaraDesktop]::SwitchDesktop($desktop)){throw 'RepatoQA desktop is locked or inaccessible.'}}finally{[void][Repato.TaraDesktop]::CloseDesktop($desktop)}
    if(@(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count){throw 'A Revit process already exists; a fresh isolated QA session is required.'}
}
function Assert-TaraRevitExecutableVersion([string]$Path){
    if((Get-Item -LiteralPath $Path).VersionInfo.ProductMajorPart -ne 25){throw 'Configured executable must be Revit 2025 (product major version 25).'} 
}
function Get-TaraQaTrustConfiguration($QaAddinRoot,$QaRoot,$Inventory){
    $names=@('Repato.CreateLevels.TestRunner.addin','Repato.CreateGrids.TestRunner.addin','Repato.GridBubbleVisibility.TestRunner.addin','Repato.GridBubbleOffset.TestRunner.addin','Repato.GridResequence.TestRunner.addin','Repato.CreatePlanViews.TestRunner.addin')
    $records=@();foreach($n in $names){$p=Join-Path (Split-Path $QaAddinRoot -Parent) $n;$source=Join-Path $QaRoot $n;if(!(Test-Path $source -PathType Leaf)){continue};$h=Get-TaraSha256 $source;$records+=[pscustomobject]@{Name=$n;Path=$p;Sha256=$h}}
    $installed=@(Get-ChildItem -LiteralPath (Split-Path $QaAddinRoot -Parent) -Filter '*.addin' -File -ErrorAction Stop)
    $dllHash=Get-TaraSha256 (Join-Path $QaAddinRoot 'Repato.Revit.dll');$promptRecords=@();foreach($file in $installed){$match=$records|Where-Object Name -ceq $file.Name;if($null -eq $match){throw "Unexpected RepatoQA manifest installed: $($file.Name)"};$promptRecords+=[pscustomobject]@{ManifestName=$file.Name;ManifestPath=$file.FullName;ManifestSha256=$match.Sha256;DllPath=(Join-Path $QaAddinRoot 'Repato.Revit.dll');DllSha256=$dllHash;Approved=$true;PromptDetected=$false;PromptAction='Pending';Timestamp=(Get-Date).ToUniversalTime().ToString('O')}}
    [pscustomobject]@{Path=(Join-Path $QaAddinRoot 'RepatoQA.trust.json');ApprovedManifests=$records;PromptRecords=$promptRecords;PromptFree=$false;ProfileRoot=$QaAddinRoot;Diagnostic='Approved unsigned add-in prompt handler is required before Revit launch.'}
}
function Test-TaraLegacyDeploymentManifestCompatibility {
    param([Parameter(Mandatory)]$Deployment,[Parameter(Mandatory)][string]$ExpectedCandidateSha256,[Parameter(Mandatory)][string]$ExpectedQaAddinRoot,[Parameter(Mandatory)][string]$ExpectedRunnerManifestPath,[Parameter(Mandatory)][string]$ExpectedRunnerManifestSha256)
    $integrity=$Deployment.PSObject.Properties['manifestIntegrityPassed']
    if($integrity -and $null -ne $integrity.Value){ return [bool]$integrity.Value }
    $available=$Deployment.PSObject.Properties['manifestIntegrityEvidenceAvailable']
    if($available -and [bool]$available.Value){ return $false }
    if($Deployment.PSObject.Properties.Name -contains 'failureCode' -and -not [string]::IsNullOrWhiteSpace([string]$Deployment.failureCode)){ return $false }
    if($Deployment.PSObject.Properties.Name -contains 'errorCode' -and -not [string]::IsNullOrWhiteSpace([string]$Deployment.errorCode)){ return $false }
    foreach($name in 'succeeded','candidateSha256','isolationPassed','validationIdentity','qaAddinRoot','runnerManifestPath','runnerManifestSha256') { if($Deployment.PSObject.Properties.Name -notcontains $name){ return $false } }
    if(!$Deployment.succeeded -or [string]$Deployment.candidateSha256 -ine $ExpectedCandidateSha256 -or !$Deployment.isolationPassed -or [string]$Deployment.validationIdentity -ine 'RAMSAI\RepatoQA'){ return $false }
    if([IO.Path]::GetFullPath([string]$Deployment.qaAddinRoot) -ine [IO.Path]::GetFullPath($ExpectedQaAddinRoot)){ return $false }
    if([IO.Path]::GetFullPath([string]$Deployment.runnerManifestPath) -ine [IO.Path]::GetFullPath($ExpectedRunnerManifestPath)){ return $false }
    if([string]$Deployment.runnerManifestSha256 -ine $ExpectedRunnerManifestSha256){ return $false }
    $true
}
function New-TaraRevitQaPlan {
    param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$QaWorkflowId,[string]$RunId,[string]$ModelPath,[string]$SidecarPath,[string]$ReportDirectory,[string]$RevitInstallDir,[string]$QaAddinRoot,[ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$DryRun,[switch]$LevelInventory,[switch]$FixturePreparation,[switch]$ManualLoadOnce,[Parameter(Mandatory)]$Context,[scriptblock]$SessionValidationInvoker)
    if($LevelInventory -and $FixturePreparation){throw 'Level inventory and fixture preparation modes are mutually exclusive.'}
    $QaWorkflowId=$QaWorkflowId.Trim()
    $runners=@{
        'create-levels'=@('Repato.CreateLevels.TestRunner.addin','REPATO_QA_LEVELS_REQUEST','Invoke-CreateLevelsQA.ps1','Repato.Revit.TestRunner.CreateLevelsQaApplication')
        'grid-bubble-visibility-v1'=@('Repato.GridBubbleVisibility.TestRunner.addin','REPATO_QA_GRID_BUBBLE_REQUEST','Invoke-GridBubbleVisibilityQA.ps1','Repato.Revit.TestRunner.GridBubbleVisibilityQaApplication')
        'grid-bubble-offset-v1'=@('Repato.GridBubbleOffset.TestRunner.addin','REPATO_QA_GRID_BUBBLE_OFFSET_REQUEST','Invoke-GridBubbleOffsetQA.ps1','Repato.Revit.TestRunner.GridBubbleOffsetQaApplication')
          'grid-resequence-v1'=@('Repato.GridResequence.TestRunner.addin','REPATO_QA_GRID_RESEQUENCE_REQUEST','Invoke-GridResequenceQA.ps1','Repato.Revit.TestRunner.GridResequenceQaApplication')
          'create-grids-world-axis-v1'=@('Repato.CreateGrids.TestRunner.addin','REPATO_QA_CREATE_GRIDS_REQUEST','Invoke-CreateGridsQA.ps1','Repato.Revit.TestRunner.CreateGridsQaApplication')
          'create-plan-views-v1'=@('Repato.CreatePlanViews.TestRunner.addin','REPATO_QA_CREATE_PLAN_VIEWS_REQUEST','Invoke-CreatePlanViewsQA.ps1','Repato.Revit.TestRunner.CreatePlanViewsQaApplication')
    }
      $runners['create-levels-elevations-v1']=$runners['create-levels']
    if(!$runners.ContainsKey($QaWorkflowId)){throw 'Workflow has no supported unattended startup runner (Welcome requires supervision; Create Grids has no startup application).'}
    foreach($name in @('TaskId','WorkflowId','QaWorkflowId','RunId')){ $value=Get-Variable $name -ValueOnly;if($value -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$' -or $Context.$name -cne $value){throw "Wrong workflow identity: $name"} }
    $roots=Get-TaraRuntimeRoots
    if([IO.Path]::GetFullPath($Context.QaRoot) -ine $roots.QaRoot){throw 'Native runner requires the fixed Source QA root.'}
    $qa=Assert-TaraPath $Context.QaRoot
    $model=Assert-TaraPath $ModelPath (Join-Path $qa 'TestRuns') -Leaf
    if([IO.Path]::GetExtension($model) -ine '.rvt'){throw 'A disposable Revit fixture is required.'}
    $sidecar=Assert-TaraPath $SidecarPath (Join-Path $qa 'TestRuns') -Leaf
    if($sidecar -ine ($model+'.fixture.json')){throw 'Sidecar must be adjacent to the supplied model.'}
    $reportRoot=Assert-TaraPath $ReportDirectory $qa
    if($reportRoot -ine (Join-Path $qa 'Reports') -or !(Test-Path -LiteralPath $reportRoot -PathType Container)){throw 'ReportDirectory must be the existing native QA Reports directory.'}
    $source=Assert-TaraPath $Context.SourceFixturePath (Join-Path $qa 'Fixtures') -Leaf
    $side=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json
    if($side.fixtureId -cne $Context.FixtureId -or $side.sourceSha256 -ine $Context.FixtureSha256){throw 'Fixture sidecar identity or expected source hash mismatch.'}
    foreach($p in @($source,$model)){if((Get-TaraSha256 $p) -ine $Context.FixtureSha256){throw 'Fixture/model hash mismatch.'}}
    $addin=if([Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1] -ieq 'RepatoQA'){Assert-TaraPath $QaAddinRoot $roots.UserAddinsRoot}else{$QaAddinRoot}
    if($addin -ine (Join-Path $roots.UserAddinsRoot 'RepatoQA')){throw 'Production add-in path rejected: only the dedicated RepatoQA folder is allowed.'}
    $runner=$runners[$QaWorkflowId]
    $remoteDeployment=$null
    if([Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1] -ieq 'RepatoQA'){$manifest=Assert-TaraPath (Join-Path $roots.UserAddinsRoot $runner[0]) $roots.UserAddinsRoot -Leaf;$dll=Assert-TaraPath (Join-Path $addin 'Repato.Revit.dll') $addin -Leaf}else{if(!(Get-Command Invoke-MayaQaLaunchAgentDeploymentValidation -ErrorAction SilentlyContinue)){throw 'RepatoQA deployment validation boundary is unavailable.'};$remoteDeployment=Invoke-MayaQaLaunchAgentDeploymentValidation -CandidateCommit 'fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3' -ExpectedCandidateSha256 $Context.ArtifactSha256 -QaWorkflowId $QaWorkflowId -TestId $Context.TestId;$manifest=Join-Path $roots.UserAddinsRoot $runner[0];$dll=Join-Path $addin 'Repato.Revit.dll'}
    $artifactManifest=Assert-TaraPath $Context.ManifestPath -Leaf
    $qaRunnerSourceManifest=Assert-TaraPath (Join-Path $qa $runner[0]) $qa -Leaf
    $artifactPairs=@(@($dll,$Context.ArtifactSha256),@($Context.ArtifactPath,$Context.ArtifactSha256),@($artifactManifest,$Context.ManifestSha256))
    foreach($pair in $artifactPairs){$null=if($pair[0] -eq $dll -and $remoteDeployment){$pair[0]}else{Assert-TaraPath $pair[0] -Leaf};if($pair[1] -notmatch '^[a-fA-F0-9]{64}$' -or (!$remoteDeployment -and (Get-TaraSha256 $pair[0]) -ine $pair[1])){throw 'Artifact or artifact-manifest hash mismatch.'}}
    $qaRunnerManifestSha256=Get-TaraSha256 $qaRunnerSourceManifest
    if($remoteDeployment){if(-not (Test-TaraLegacyDeploymentManifestCompatibility $remoteDeployment $Context.ArtifactSha256 $addin $manifest $qaRunnerManifestSha256)){throw 'RepatoQA deployment manifest integrity validation failed.'}}elseif((Get-TaraSha256 $manifest) -ine $qaRunnerManifestSha256){throw 'QA runner manifest hash mismatch.'}
    $xml=[xml](Get-Content -LiteralPath $(if($remoteDeployment){$qaRunnerSourceManifest}else{$manifest}) -Raw)
    if(@($xml.RevitAddIns.AddIn|Where-Object Type -eq 'Application').Count -ne 1){throw 'QA startup application manifest is required.'}
    $appEntries=@($xml.RevitAddIns.AddIn|Where-Object Type -eq 'Application')
    if($appEntries.Count -ne 1 -or $appEntries[0].FullClassName -cne $runner[3]){throw 'QA runner startup class does not match the selected workflow.'}
    foreach($entry in $xml.RevitAddIns.AddIn){if([IO.Path]::GetFullPath((Join-Path $roots.UserAddinsRoot ([string]$entry.Assembly))) -ine $dll){throw 'Manifest assembly path is outside the QA deployment.'}}
    $inventory=if($remoteDeployment){[pscustomobject]@{Allowed=[bool]$remoteDeployment.isolationPassed;Errors=@()}}else{Get-AddinIsolationInventory -PolicyPath (Join-Path $qa 'MachineWideAddins.allowlist.json') -MachineRoot $roots.MachineRoot -UserRoot $roots.UserAddinsRoot -QaSourceRoot $qa -ApprovedUserManifestName $runner[0]}
    if(!$inventory.Allowed -or @($inventory.Errors).Count){throw ('Add-in allowlist rejected: '+(@($inventory.Errors)+@($inventory.DetectedAddins|Where-Object {!$_.Allowlisted}|ForEach-Object Reason)-join '; '))}
    $exe=Assert-TaraPath (Join-Path $RevitInstallDir 'Revit.exe') $RevitInstallDir -Leaf
    Assert-TaraRevitExecutableVersion $exe
    $verifier=Assert-TaraPath (Join-Path $qa $runner[2]) $qa -Leaf
    if(!$DryRun){if($SessionValidationInvoker){& $SessionValidationInvoker}else{Assert-TaraInteractiveSession}}
    $requestId=[guid]::NewGuid().ToString('N');$requestPath=Join-Path ([IO.Path]::GetDirectoryName($model)) ('tara-'+$requestId+'.request.json')
    $trust=if($remoteDeployment){$remoteDeployment}else{Get-TaraQaTrustConfiguration $addin $qa $inventory}
    $dispatchVariable=if($LevelInventory){'REPATO_QA_CREATE_PLAN_VIEWS_LEVEL_INVENTORY'}elseif($FixturePreparation){'REPATO_QA_CREATE_PLAN_VIEWS_FIXTURE_PREPARATION'}else{$runner[1]}
    $outputPath=$requestPath+$(if($LevelInventory){'.inventory.json'}elseif($FixturePreparation){'.preparation.json'}else{''})
    [pscustomobject]@{StoreRoot=$StoreRoot;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;RunId=$RunId;RequestExpiresUtc=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds);Context=$Context;ModelPath=$model;SidecarPath=$sidecar;SidecarSha256=(Get-TaraSha256 $sidecar);ReportDirectory=$reportRoot;RevitInstallDir=$RevitInstallDir;QaAddinRoot=$addin;TrustConfiguration=$trust;TimeoutSeconds=$TimeoutSeconds;Executable=$exe;ExecutableSha256=(Get-TaraSha256 $exe);Command=('"'+$exe+'"');Arguments='';EnvironmentVariable=$dispatchVariable;LevelInventory=[bool]$LevelInventory;FixturePreparation=[bool]$FixturePreparation;ManualLoadOnce=[bool]$ManualLoadOnce;OpenModelPath=$(if($LevelInventory -or $FixturePreparation){$model}else{$null});InventoryOutputPath=$outputPath;VerifierPath=$verifier;VerifierSha256=(Get-TaraSha256 $verifier);RequestId=$requestId;RequestPath=$requestPath;ResultPath=$(if($LevelInventory -or $FixturePreparation){$outputPath}else{$requestPath+'.result.json'});EvidencePath=(Join-Path $reportRoot ('tara-'+$requestId+'.json'));InstalledDll=$dll;ArtifactManifestPath=$artifactManifest;ArtifactManifestSha256=$Context.ManifestSha256;QaRunnerManifestPath=$manifest;QaRunnerManifestSha256=$qaRunnerManifestSha256;InstalledManifest=$manifest;Isolation=$inventory;SideEffectsPerformed=$false}
}
function Write-TaraJsonNew($Path,$Value){
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 30));$stream=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function New-TaraLevelInventoryRequest {
    param([Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$AttemptId,[Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$ModelPath,[Parameter(Mandatory)][string]$ModelSha256,[Parameter(Mandatory)][string]$OutputPath)
    if($AttemptId -notmatch '^[a-fA-F0-9]{32}$' -or $RunId -notmatch '^[a-fA-F0-9]{32}$'){throw 'Level inventory attempt/run identities must be GUID N format.'}
    foreach($path in @($ModelPath,$OutputPath)){if(-not [IO.Path]::IsPathRooted($path) -or [IO.Path]::GetFullPath($path) -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path)) -ine [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputPath))){throw 'Inventory model/request/output must be absolute and co-located.'}}
    if($ModelSha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Level inventory model SHA-256 is invalid.'}
    [ordered]@{taskId=$TaskId;attemptId=$AttemptId;runId=$RunId;modelPath=[IO.Path]::GetFullPath($ModelPath);modelSha256=$ModelSha256.ToUpperInvariant();outputPath=[IO.Path]::GetFullPath($OutputPath)}
}
function New-TaraFixturePreparationRequest {
    param([Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$AttemptId,[Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$RequestPath,[Parameter(Mandatory)][string]$ModelPath,[Parameter(Mandatory)][string]$ModelSha256,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][DateTimeOffset]$ExpiresUtc)
    if($AttemptId -notmatch '^[a-fA-F0-9]{32}$' -or $RunId -notmatch '^[a-fA-F0-9]{32}$'){throw 'Fixture preparation attempt/run identities must be GUID N format.'}
    if($ModelSha256 -notmatch '^[a-fA-F0-9]{64}$' -or $ExpiresUtc -le [DateTimeOffset]::UtcNow){throw 'Fixture preparation model hash or expiry is invalid.'}
    foreach($path in @($ModelPath,$OutputPath)){if(-not [IO.Path]::IsPathRooted($path) -or [IO.Path]::GetFullPath($path) -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path)) -ine [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputPath))){throw 'Fixture preparation model, request, and output must be absolute and co-located.'}}
    [ordered]@{operation='prepare-disposable-create-plan-views-fixture';taskId=$TaskId;workflowId=$WorkflowId;attemptId=$AttemptId;runId=$RunId;requestPath=[IO.Path]::GetFullPath($RequestPath);modelPath=[IO.Path]::GetFullPath($ModelPath);modelSha256=$ModelSha256.ToUpperInvariant();outputPath=[IO.Path]::GetFullPath($OutputPath);expiresUtc=$ExpiresUtc.ToString('O')}
}
function Start-TaraTrustPromptHandler($Plan){
    # Multiple approved QA manifests are handled sequentially; unknown prompts fail closed.
    [pscustomobject]@{Started=$true;StartedUtc=(Get-Date).ToUniversalTime().ToString('O');Handled=@();Rejected=@()}
}
function Stop-TaraTrustPromptHandler($Handler){
    if($null -eq $Handler){return}
    try {
        if($Handler.PSObject.Properties.Name -contains 'Stopped'){$Handler.Stopped=$true}
        if($Handler.PSObject.Properties.Name -contains 'StoppedUtc'){$Handler.StoppedUtc=(Get-Date).ToUniversalTime().ToString('O')}
    } finally {
        if($Handler -is [IDisposable]){try{$Handler.Dispose()}catch{}}
    }
}
function Start-TaraProcess($Plan){
    if($Plan.TrustConfiguration -and $Plan.TrustConfiguration.PromptFree){$Plan.TrustConfiguration|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $Plan.TrustConfiguration.Path -Encoding UTF8}
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Plan.Executable;$info.Arguments=if($Plan.OpenModelPath){'"'+$Plan.OpenModelPath+'"'}else{''};$info.UseShellExecute=$false;$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    # Environment changes are confined to this child. Clear every other QA dispatch.
    foreach($key in @($info.EnvironmentVariables.Keys)){if($key -like 'REPATO_QA_*_REQUEST' -or $key -like 'REPATO_QA_CREATE_PLAN_VIEWS_*'){$info.EnvironmentVariables.Remove($key)}}
    $info.EnvironmentVariables[$Plan.EnvironmentVariable]=$Plan.RequestPath
    if($Plan.LevelInventory -or $Plan.FixturePreparation){foreach($key in @($info.EnvironmentVariables.Keys)){if($key -like 'REPATO_QA_*_REQUEST' -or $key -like 'REPATO_QA_CREATE_PLAN_VIEWS_*'){$info.EnvironmentVariables.Remove($key)}};$info.EnvironmentVariables[$Plan.EnvironmentVariable]=$Plan.RequestPath}
    $info.EnvironmentVariables['REPATO_QA_REPOSITORY_ROOT']=(Split-Path (Split-Path $Plan.VerifierPath -Parent) -Parent)
    $child=[Diagnostics.Process]::Start($info);$null=$child.Handle;return $child
}
function Wait-TaraManualLoadOnce($Plan,$Process){
    if(!( 'TaraPromptNative' -as [type])){Add-Type -TypeDefinition 'using System; using System.Text; using System.Runtime.InteropServices; public static class TaraPromptNative { [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c,string t); [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p,IntPtr c,string n,string t); [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h,StringBuilder s,int n); }'}
    $detected=$false;$confirmedUtc=$null;$deadline=[DateTime]::UtcNow.AddSeconds($Plan.TimeoutSeconds)
    while([DateTime]::UtcNow -lt $deadline){$Process.Refresh();if($Process.HasExited -or (Test-Path -LiteralPath $Plan.ResultPath -PathType Leaf)){break};$dialog=[TaraPromptNative]::FindWindow($null,'Security - Unsigned Add-In');if($dialog -ne [IntPtr]::Zero){$detected=$true;$text=Get-TaraWindowText $dialog;$child=[TaraPromptNative]::FindWindowEx($dialog,[IntPtr]::Zero,$null,$null);while($child -ne [IntPtr]::Zero){$text+=' '+(Get-TaraWindowText $child);$child=[TaraPromptNative]::FindWindowEx($dialog,$child,$null,$null)};$manifest=$Plan.InstalledManifest;$dll=$Plan.InstalledDll;if($text -notmatch [regex]::Escape($manifest) -and $text -notmatch [regex]::Escape($dll)){throw 'Unexpected unsigned add-in prompt path; manual approval not recorded.'};if((Get-TaraSha256 $manifest) -ine $Plan.QaRunnerManifestSha256 -or (Get-TaraSha256 $dll) -ine $Plan.Context.ArtifactSha256){throw 'Load Once prompt manifest or candidate hash validation failed.'};Write-Host "LOAD_ONCE_REQUIRED attempt=$($Plan.RequestId) run=$($Plan.RunId) manifest=$manifest sha256=$($Plan.QaRunnerManifestSha256). Click Load Once; do not select Always Load.";while([DateTime]::UtcNow -lt $Plan.RequestExpiresUtc){$Process.Refresh();if($Process.HasExited){break};if([TaraPromptNative]::FindWindow($null,'Security - Unsigned Add-In') -eq [IntPtr]::Zero){break};Start-Sleep -Milliseconds 250};break};Start-Sleep -Milliseconds 250}
    $remaining=[TaraPromptNative]::FindWindow($null,'Security - Unsigned Add-In');if($remaining -ne [IntPtr]::Zero){throw 'Manual Load Once prompt did not close before timeout.'};if($detected){$confirmedUtc=[DateTimeOffset]::UtcNow.ToString('O')};[pscustomobject]@{PromptDetected=$detected;PromptAction=$(if($detected){'Load Once'}else{'None'});ApprovedManifest=$(if($detected){$Plan.InstalledManifest}else{$null});PromptRecords=@();ManualApprovalEvidence=$(if($detected){[pscustomobject]@{Action='Load Once';ConfirmedBy='user';ConfirmedUtc=$confirmedUtc;TaskId=$Plan.TaskId;WorkflowId=$Plan.WorkflowId;AttemptId=$Plan.RequestId;RunId=$Plan.RunId;ManifestPath=$Plan.InstalledManifest;ManifestSha256=$Plan.QaRunnerManifestSha256}}else{$null});PromptFree=$true}
}
function Get-TaraWindowText([IntPtr]$Window){$b=New-Object Text.StringBuilder 2048;[void][TaraPromptNative]::GetWindowText($Window,$b,$b.Capacity);$b.ToString()}
function Handle-TaraTrustPrompt($Plan,$Process,$Handler){
    if(!( 'TaraPromptNative' -as [type])){
        Add-Type -TypeDefinition 'using System; using System.Text; using System.Runtime.InteropServices; public static class TaraPromptNative { [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c,string t); [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p,IntPtr c,string n,string t); [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h,StringBuilder s,int n); [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,IntPtr l); }'
    }

    $records = @($Plan.TrustConfiguration.PromptRecords)
    $handled = @()
    $handledPaths = @{}
    $detected = $false

    # Revit commonly takes longer than three seconds to display its trust prompt.
    # Watch startup for up to two minutes or until the native QA result appears.
    $deadline = [DateTime]::UtcNow.AddSeconds(
        [Math]::Min([Math]::Max($Plan.TimeoutSeconds, 30), 120)
    )

    while([DateTime]::UtcNow -lt $deadline){
        $Process.Refresh()

        if($Process.HasExited){
            break
        }

        $dialog = [TaraPromptNative]::FindWindow(
            $null,
            'Security - Unsigned Add-In'
        )

        if($dialog -ne [IntPtr]::Zero){
            $detected = $true
            $text = Get-TaraWindowText $dialog

            $child = [TaraPromptNative]::FindWindowEx(
                $dialog,
                [IntPtr]::Zero,
                $null,
                $null
            )

            while($child -ne [IntPtr]::Zero){
                $text += ' ' + (Get-TaraWindowText $child)

                $child = [TaraPromptNative]::FindWindowEx(
                    $dialog,
                    $child,
                    $null,
                    $null
                )
            }

            $match = $records |
                Where-Object {
                    $text -match [regex]::Escape($_.ManifestPath) -or
                    $text -match [regex]::Escape($_.DllPath)
                } |
                Select-Object -First 1

            if($null -eq $match){
                throw 'Unexpected unsigned add-in prompt path; approval denied.'
            }

            if(
                (Get-TaraSha256 $match.ManifestPath) -ine $match.ManifestSha256 -or
                (Get-TaraSha256 $match.DllPath) -ine $match.DllSha256
            ){
                throw 'Unsigned add-in prompt hash validation failed.'
            }

            $button = [TaraPromptNative]::FindWindowEx(
                $dialog,
                [IntPtr]::Zero,
                $null,
                'Always Load'
            )

            if($button -eq [IntPtr]::Zero){
                throw 'Approved unsigned add-in prompt was detected but Always Load was unavailable.'
            }

            [void][TaraPromptNative]::SendMessage(
                $button,
                0x00F5,
                [IntPtr]::Zero,
                [IntPtr]::Zero
            )

            if(!$handledPaths.ContainsKey($match.ManifestPath)){
                $handledPaths[$match.ManifestPath] = $true

                $record = [pscustomobject]@{
                    Manifest = $match.ManifestPath
                    Action = 'Always Load'
                    Sha256 = $match.ManifestSha256
                }

                $handled += $record
                $Handler.Handled += $record
            }

            Start-Sleep -Milliseconds 500
            continue
        }

        # Once the runner publishes its result, startup prompts can no longer block it.
        if(Test-Path -LiteralPath $Plan.ResultPath -PathType Leaf){
            break
        }

        Start-Sleep -Milliseconds 250
    }

    $remainingDialog = [TaraPromptNative]::FindWindow(
        $null,
        'Security - Unsigned Add-In'
    )

    if($remainingDialog -ne [IntPtr]::Zero){
        throw 'Unsigned add-in prompt remained open after automatic handling.'
    }

    [pscustomobject]@{
        PromptDetected = $detected
        PromptAction = $(if($handled.Count){'Always Load'}else{'None'})
        ApprovedManifest = $(if($handled.Count){$handled[-1].Manifest}else{$null})
        PromptRecords = $handled
        PromptFree = $true
    }
}
function Stop-TaraOwnedProcess($Process){
    # Never discover/reacquire by PID or name. The original Process handle owns this termination.
    $Process.Refresh();if(!$Process.HasExited){$Process.Kill();[void]$Process.WaitForExit(5000)}
}
function Close-TaraOwnedProcess($Process,[int]$GraceSeconds=30){
    $Process.Refresh(); if($Process.HasExited){ return [pscustomobject]@{State='Exited';ExitCode=$Process.ExitCode;Forced=$false} }
    $requested=$false; try{$requested=$Process.CloseMainWindow()}catch{}
    $deadline=[DateTime]::UtcNow.AddSeconds($GraceSeconds)
    while(!$Process.HasExited -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Seconds 1;$Process.Refresh()}
    if(!$Process.HasExited){ Stop-TaraOwnedProcess $Process; return [pscustomobject]@{State='ForceTerminated';ExitCode=$Process.ExitCode;Forced=$true} }
    return [pscustomobject]@{State='Exited';ExitCode=$Process.ExitCode;Forced=$false}
}
function Assert-TaraModelUnlocked([string]$Path){
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None);$stream.Dispose()
}
function Wait-TaraResult($Plan,$Process){
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while(!(Test-Path -LiteralPath $Plan.ResultPath -PathType Leaf)){
        $Process.Refresh();if($Process.HasExited){throw 'QA Revit exited before publishing a result.'}
        if($timer.Elapsed.TotalSeconds -ge $Plan.TimeoutSeconds){Stop-TaraOwnedProcess $Process;throw [TimeoutException]::new('QA hard timeout; only the bridge-owned Revit process was terminated.')}
        Start-Sleep -Seconds 20
    }
}
function Assert-TaraResult($Plan){
    $request=Get-Content -LiteralPath $Plan.RequestPath -Raw|ConvertFrom-Json
    foreach($name in @('TaskId','WorkflowId','QaWorkflowId','RunId')){if($request.$name -cne $Plan.$name){throw "Stale or mismatched request $name."}}
    if($request.requestId -cne $Plan.RequestId){throw 'Request identity mismatch.'}
    $receipt=Get-Content -LiteralPath $Plan.ResultPath -Raw|ConvertFrom-Json
    $reportPath=Assert-TaraPath $receipt.ReportPath $Plan.ReportDirectory -Leaf
    $reportHash=Get-TaraSha256 $reportPath;$report=Get-Content -LiteralPath $reportPath -Raw|ConvertFrom-Json
    if($receipt.RequestId -cne $Plan.RequestId -or $receipt.RunId -cne $report.RunId -or $report.RunId -notmatch '^[a-fA-F0-9]{32}$' -or [IO.Path]::GetFileName($reportPath) -cne ($report.RunId+'.json')){throw 'NativeRunId or RequestId mismatch.'}
    foreach($value in @($receipt,$report)){foreach($name in @('TaskId','WorkflowId','QaWorkflowId')){if($value.PSObject.Properties.Name -contains $name -and $value.$name -cne $Plan.$name){throw "Result $name mismatch."}};if($value.PSObject.Properties.Name -contains 'NativeRunId' -and $value.NativeRunId -cne $report.RunId){throw 'NativeRunId mismatch.'}}
    if($receipt.Status -cne 'Passed' -or $report.Status -cne 'Passed' -or $report.RollbackStatus -cne 'RolledBack' -or @($report.Errors).Count -or !$report.Assertions -or @($report.Assertions|Where-Object {$_.Passed -isnot [bool] -or !$_.Passed}).Count){throw 'Failed report: Passed, RolledBack, successful assertions and no errors are required.'}
    $runtimeModelHash=if($report.PSObject.Properties.Name -contains 'RuntimeModelSha256'){$report.RuntimeModelSha256}else{$Plan.Context.FixtureSha256}
    if($report.TestId -cne $Plan.Context.TestId -or $report.DocumentPath -ine $Plan.ModelPath -or $report.FixtureId -cne $Plan.Context.FixtureId -or $report.FixtureSha256 -ine $Plan.Context.FixtureSha256 -or $runtimeModelHash -notmatch '^[A-Fa-f0-9]{64}$' -or ($Plan.QaWorkflowId -eq 'create-plan-views-v1' -and $report.PSObject.Properties.Name -notcontains 'RuntimeModelSha256') -or $report.AssemblyIdentity.Sha256 -ine $Plan.Context.ArtifactSha256){throw 'Report model, fixture, artifact or test identity mismatch.'}
    if([DateTimeOffset]::Parse($report.StartedUtc) -lt [DateTimeOffset]::Parse($request.createdUtc) -or [DateTimeOffset]::Parse($report.FinishedUtc) -lt [DateTimeOffset]::Parse($report.StartedUtc) -or [DateTimeOffset]::Parse($report.FinishedUtc) -gt [DateTimeOffset]::UtcNow.AddSeconds(5)){throw 'Report is stale or has invalid timestamps.'}
    if([DateTimeOffset]::Parse($report.FinishedUtc) -gt [DateTimeOffset]::Parse($request.expiresUtc)){throw 'Report completed after request expiry.'}
    if((Get-TaraSha256 $Plan.ModelPath) -ine $runtimeModelHash){throw 'Prepared runtime model hash mismatch.'}
    foreach($pair in @(@($Plan.Context.SourceFixturePath,$Plan.Context.FixtureSha256),@($Plan.SidecarPath,$Plan.SidecarSha256),@($Plan.InstalledDll,$Plan.Context.ArtifactSha256),@($Plan.InstalledManifest,$Plan.QaRunnerManifestSha256),@($Plan.Context.ManifestPath,$Plan.Context.ManifestSha256),@($Plan.Context.ArtifactPath,$Plan.Context.ArtifactSha256))){if((Get-TaraSha256 $pair[0]) -ine $pair[1]){throw 'Post-run evidence hash mismatch.'}}
    $repoRoot=[IO.Path]::GetDirectoryName($Plan.Context.QaRoot)
    Assert-ReportedAddinIsolation $Plan.Isolation $report.AddinIsolation
    # Existing runner verifier supplies workflow-specific assertions and input checks.
    if((Get-TaraSha256 $Plan.VerifierPath) -ine $Plan.VerifierSha256){throw 'Runner verifier changed since preflight.'}
    & $Plan.VerifierPath -Action Verify -ReceiptPath $Plan.ResultPath 6>$null | Out-Null
    if((Get-TaraSha256 $reportPath) -ine $reportHash){throw 'Report changed during verification.'}
    [pscustomobject]@{ReportPath=$reportPath;ReportSha256=$reportHash;NativeRunId=$report.RunId;ResultSha256=(Get-TaraSha256 $Plan.ResultPath)}
}
function Invoke-TaraRevitQa {
    param([Parameter(Mandatory)]$Plan,[switch]$DryRun)
    if($DryRun){
        return [pscustomobject]@{
            Success=$true;Status='DryRun';Mode='DryRun';Error=$null
            Command=$Plan.Command;RequestPath=$Plan.RequestPath;ResultPath=$Plan.ResultPath
            ExecutablePath=$Plan.Executable;ModelPath=$Plan.ModelPath;QaAddinRoot=$Plan.QaAddinRoot;ArtifactManifestPath=$Plan.ArtifactManifestPath;ArtifactManifestSha256=$Plan.ArtifactManifestSha256;QaRunnerManifestPath=$Plan.QaRunnerManifestPath;QaRunnerManifestSha256=$Plan.QaRunnerManifestSha256
            EnvironmentVariable=$Plan.EnvironmentVariable;EnvironmentValue=$Plan.RequestPath
            ValidationResults=[pscustomobject]@{FixtureId=$Plan.Context.FixtureId;FixtureSha256=$Plan.Context.FixtureSha256;ArtifactSha256=$Plan.Context.ArtifactSha256;ManifestSha256=$Plan.Context.ManifestSha256;PolicySha256=$Plan.Isolation.PolicySha256;Validated=$true}
            PromptDetected=$false;PromptAction='None';ApprovedManifest=$null;PromptFree=$false;SideEffectsPerformed=$false;ProcessStarted=$false;ProcessId=$null;ExitCode=$null
        }
    }
    Assert-TaraInteractiveSession
    $result=[ordered]@{Success=$false;Mode='Real';Status='Failed';TaskId=$Plan.TaskId;WorkflowId=$Plan.WorkflowId;QaWorkflowId=$Plan.QaWorkflowId;RunId=$Plan.RunId;RequestId=$Plan.RequestId;RequestPath=$Plan.RequestPath;ResultPath=$Plan.ResultPath;EvidencePath=$Plan.EvidencePath;ReportPath=$null;ReportSha256=$null;NativeRunId=$null;ResultSha256=$null;RequestSha256=$null;ModelPath=$Plan.ModelPath;SidecarPath=$Plan.SidecarPath;SidecarSha256=$Plan.SidecarSha256;FixtureId=$Plan.Context.FixtureId;FixtureSha256=$Plan.Context.FixtureSha256;ArtifactPath=$Plan.InstalledDll;ArtifactSha256=$Plan.Context.ArtifactSha256;ArtifactManifestPath=$Plan.ArtifactManifestPath;ArtifactManifestSha256=$Plan.ArtifactManifestSha256;QaRunnerManifestPath=$Plan.QaRunnerManifestPath;QaRunnerManifestSha256=$Plan.QaRunnerManifestSha256;ManifestPath=$Plan.InstalledManifest;ManifestSha256=$Plan.QaRunnerManifestSha256;ExecutableSha256=$Plan.ExecutableSha256;PolicySha256=$Plan.Isolation.PolicySha256;Command=$Plan.Command;EnvironmentVariable=$Plan.EnvironmentVariable;EnvironmentValue=$Plan.RequestPath;ModelSha256=$Plan.Context.FixtureSha256;ProcessStarted=$false;ProcessId=$null;ProcessStartUtc=$null;ProcessEndUtc=$null;StartedUtc=[DateTimeOffset]::UtcNow.ToString('O');FinishedUtc=$null;ExitState='NotStarted';ExitCode=$null;FailureReason=$null;Error=$null;SideEffectsPerformed=$false}
    $process=$null;$handler=$null
    try{
        # Revalidate the filesystem immediately before writing/launching; a dry plan is not authorization.
        $args=@{};foreach($name in @('StoreRoot','TaskId','WorkflowId','QaWorkflowId','RunId','ModelPath','SidecarPath','ReportDirectory','RevitInstallDir','QaAddinRoot','TimeoutSeconds','Context')){$args[$name]=$Plan.$name};if($Plan.LevelInventory){$args.LevelInventory=$true};if($Plan.FixturePreparation){$args.FixturePreparation=$true};if($Plan.ManualLoadOnce){$args.ManualLoadOnce=$true};$fresh=New-TaraRevitQaPlan @args
        if($fresh.ExecutableSha256 -ine $Plan.ExecutableSha256 -or $fresh.SidecarSha256 -ine $Plan.SidecarSha256 -or $fresh.Isolation.PolicySha256 -ine $Plan.Isolation.PolicySha256 -or $fresh.VerifierSha256 -ine $Plan.VerifierSha256){throw 'Preflight evidence changed before launch.'}
        if($Plan.LevelInventory){$request=New-TaraLevelInventoryRequest -TaskId $Plan.TaskId -AttemptId $Plan.RequestId -RunId $Plan.RunId -ModelPath $Plan.ModelPath -ModelSha256 $Plan.Context.FixtureSha256 -OutputPath $Plan.InventoryOutputPath}elseif($Plan.FixturePreparation){$request=New-TaraFixturePreparationRequest -TaskId $Plan.TaskId -WorkflowId $Plan.WorkflowId -AttemptId $Plan.RequestId -RunId $Plan.RunId -RequestPath $Plan.RequestPath -ModelPath $Plan.ModelPath -ModelSha256 $Plan.Context.FixtureSha256 -OutputPath $Plan.InventoryOutputPath -ExpiresUtc ([DateTimeOffset]::UtcNow.AddSeconds($Plan.TimeoutSeconds))}else{$request=[ordered]@{requestId=$Plan.RequestId;testId=$Plan.Context.TestId;modelPath=$Plan.ModelPath;assemblySha256=$Plan.Context.ArtifactSha256;selectedManifestPath=$Plan.QaRunnerManifestPath;selectedManifestSha256=$Plan.QaRunnerManifestSha256;createdUtc=$result.StartedUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddSeconds($Plan.TimeoutSeconds).ToString('O');addinIsolation=$Plan.Isolation;TaskId=$Plan.TaskId;WorkflowId=$Plan.WorkflowId;QaWorkflowId=$Plan.QaWorkflowId;RunId=$Plan.RunId}}
        Write-TaraJsonNew $Plan.RequestPath $request;$result.SideEffectsPerformed=$true;$result.RequestSha256=Get-TaraSha256 $Plan.RequestPath
        $handler=Start-TaraTrustPromptHandler $Plan;$process=Start-TaraProcess $Plan;$result.ProcessStarted=$true;$result.ProcessId=$process.Id;$result.ProcessStartUtc=$process.StartTime.ToUniversalTime().ToString('O');$result.ExitState='Running';$prompt=if($Plan.ManualLoadOnce){Wait-TaraManualLoadOnce $Plan $process}else{Handle-TaraTrustPrompt $Plan $process $handler};$result.PromptDetected=$prompt.PromptDetected;$result.PromptAction=$prompt.PromptAction;$result.ApprovedManifest=$prompt.ApprovedManifest;$result.PromptRecords=$prompt.PromptRecords;$result.ManualApprovalEvidence=$prompt.ManualApprovalEvidence;$result.PromptFree=$prompt.PromptFree;if(!$prompt.PromptFree){throw 'Tara trust prompt handling did not reach a prompt-free state.'}
        Wait-TaraResult $Plan $process
        if((Get-TaraSha256 $Plan.RequestPath) -ine $result.RequestSha256){throw 'Request changed during execution.'}
        $observed=Get-Content -LiteralPath $Plan.ResultPath -Raw|ConvertFrom-Json
        $result.ResultSha256=Get-TaraSha256 $Plan.ResultPath
        if($Plan.LevelInventory){if($observed.TaskId -cne $Plan.TaskId -or $observed.AttemptId -cne $Plan.RequestId -or $observed.RunId -cne $Plan.RunId -or [IO.Path]::GetFullPath($observed.ModelPath) -ine [IO.Path]::GetFullPath($Plan.ModelPath) -or $observed.ModelSha256 -ine $Plan.Context.FixtureSha256 -or !$observed.Levels){throw 'Revit level inventory identity/model evidence failed.'};if((Get-TaraSha256 $Plan.ModelPath) -ine $Plan.Context.FixtureSha256){throw 'Model changed during read-only level inventory.'};$result.Inventory=$observed;$result.Status='Passed'}elseif($Plan.FixturePreparation){$levels=@($observed.Levels|Sort-Object Name);$names=@($levels|ForEach-Object Name)-join '|';$levelsValid=$levels.Count -eq 3 -and $names -ceq '0|1|2' -and [Math]::Abs([double]$levels[0].ElevationMeters) -le 0.000001 -and [Math]::Abs(([double]$levels[1].ElevationMeters)-4.0) -le 0.000001 -and [Math]::Abs(([double]$levels[2].ElevationMeters)-7.8) -le 0.000001;if($observed.Status -cne 'Passed' -or $observed.TaskId -cne $Plan.TaskId -or $observed.WorkflowId -cne $Plan.WorkflowId -or $observed.AttemptId -cne $Plan.RequestId -or $observed.RunId -cne $Plan.RunId -or [IO.Path]::GetFullPath($observed.ModelPath) -ine [IO.Path]::GetFullPath($Plan.ModelPath) -or $observed.SourceModelSha256 -ine $Plan.Context.FixtureSha256 -or $observed.PreparedModelSha256 -ine (Get-TaraSha256 $Plan.ModelPath) -or !$levelsValid){throw 'Revit fixture preparation identity/hash/level/elevation evidence failed.'};$result.Preparation=$observed;$result.Status='Passed'}else{$result.ReportPath=Assert-TaraPath $observed.ReportPath $Plan.ReportDirectory -Leaf;$result.ReportSha256=Get-TaraSha256 $result.ReportPath;$result.NativeRunId=$observed.RunId;$verified=Assert-TaraResult $Plan;foreach($name in @('ReportPath','ReportSha256','NativeRunId','ResultSha256')){$result[$name]=$verified.$name};$result.Status='Passed'}
    }catch{$result.FailureReason=$_.Exception.Message;$result.Error=$_.Exception.Message;if($_.Exception -is [TimeoutException]){$result.Status='TimedOut'}}
    finally{
        $result.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('O');$result.Success=($result.Status -ceq 'Passed')
        if($handler){try{Stop-TaraTrustPromptHandler $handler}catch{$result.FailureReason=([string]$result.FailureReason+' Trust-handler cleanup failed: '+$_.Exception.Message);$result.Error=$result.FailureReason}}
        if($process){try{$cleanup=Close-TaraOwnedProcess $process;if($cleanup.Forced){$result.ExitState='ForceTerminated';$result.FailureReason=([string]$result.FailureReason+' Graceful Revit close timed out; bridge-owned process force-terminated.')}else{$result.ExitState='Exited'};$result.ExitCode=$cleanup.ExitCode;$process.Refresh();$result.ProcessEndUtc=$process.ExitTime.ToUniversalTime().ToString('O');Assert-TaraModelUnlocked $Plan.ModelPath}catch{$result.ExitState='CleanupFailed';$result.FailureReason=([string]$result.FailureReason+' Cleanup failed: '+$_.Exception.Message);$result.Error=$result.FailureReason};$process.Dispose()}
        $result.SideEffectsPerformed=$true
        try{Write-TaraJsonNew $Plan.EvidencePath ([pscustomobject]$result)}catch{$result.FailureReason=([string]$result.FailureReason+' Evidence persistence failed: '+$_.Exception.Message);$result.Status='Failed'}
    }
    [pscustomobject]$result
}
Export-ModuleMember -Function New-TaraRevitQaPlan,Invoke-TaraRevitQa,New-TaraLevelInventoryRequest,New-TaraFixturePreparationRequest
