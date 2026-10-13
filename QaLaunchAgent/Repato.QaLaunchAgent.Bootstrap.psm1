Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Contract = [ordered]@{
    SchemaVersion = 1
    Account = 'RAMSAI\RepatoQA'
    Sid = 'S-1-5-21-1031246752-3872016183-2454652381-1015'
    InstallRoot = 'C:\Program Files\Repato\QaLaunchAgent'
    Executable = 'C:\Program Files\Repato\QaLaunchAgent\Repato.QaLaunchAgent.exe'
    TaskPath = '\Repato\'
    TaskName = 'Repato QA Launch Agent'
    RuntimeFiles = @('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
}
$script:PendingInstallRollbacks=@{}

function Get-RepatoQaLaunchAgentBootstrapContract { [pscustomobject]$script:Contract }

function Assert-Administrator {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Bootstrap requires an elevated administrator PowerShell.' }
}

function Assert-Identity([string]$Account,[string]$ExpectedSid) {
    if ($Account -cne $script:Contract.Account -or $ExpectedSid -cne $script:Contract.Sid) { throw 'The fixed RepatoQA account or SID was changed.' }
    $actual = ([Security.Principal.NTAccount]$Account).Translate([Security.Principal.SecurityIdentifier]).Value
    if ($actual -cne $ExpectedSid) { throw "RepatoQA SID mismatch. Expected $ExpectedSid; resolved $actual." }
}

function Resolve-RepatoAccountSid([string]$Account) {
    if([string]::IsNullOrWhiteSpace($Account)){return $null}
    try { ([Security.Principal.NTAccount]$Account).Translate([Security.Principal.SecurityIdentifier]).Value } catch { $null }
}

function Read-ValidatedManifest([string]$SourceRoot,[string]$ManifestPath,[string]$ManifestSha256) {
    $source = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $manifestFull = [IO.Path]::GetFullPath($ManifestPath)
    if (-not (Test-Path -LiteralPath $manifestFull -PathType Leaf)) { throw 'Launch-agent provenance manifest is missing.' }
    if ((Get-FileHash -LiteralPath $manifestFull -Algorithm SHA256).Hash -cne $ManifestSha256) { throw 'Launch-agent provenance manifest hash mismatch.' }
    $m = Get-Content -LiteralPath $manifestFull -Raw | ConvertFrom-Json
    if ($m.schemaVersion -ne 1 -or $m.product -cne 'Repato.QaLaunchAgent' -or $m.account -cne $script:Contract.Account -or $m.sid -cne $script:Contract.Sid) { throw 'Launch-agent provenance contract mismatch.' }
    $names = @($m.files | ForEach-Object name)
    if ($names.Count -ne $script:Contract.RuntimeFiles.Count -or @($script:Contract.RuntimeFiles | Where-Object { $_ -cnotin $names }).Count) { throw 'Launch-agent runtime set is partial or contains unexpected files.' }
    foreach ($entry in $m.files) {
        if ($entry.name -notmatch '^Repato\.QaLaunchAgent\.(exe|dll|deps\.json|runtimeconfig\.json)$' -or $entry.sha256 -notmatch '^[A-F0-9]{64}$') { throw 'Invalid launch-agent manifest entry.' }
        $path = Join-Path $source $entry.name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing runtime file: $($entry.name)" }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $entry.sha256) { throw "Source hash mismatch: $($entry.name)" }
    }
    $exeVersion = (Get-Item -LiteralPath (Join-Path $source 'Repato.QaLaunchAgent.exe')).VersionInfo.ProductVersion
    $dllVersion = (Get-Item -LiteralPath (Join-Path $source 'Repato.QaLaunchAgent.dll')).VersionInfo.ProductVersion
    if ($exeVersion -cne $dllVersion -or $exeVersion -cne $m.productVersion) { throw 'Executable/DLL runtime versions do not match the provenance manifest.' }
    [pscustomobject]@{ SourceRoot=$source; Manifest=$m; ManifestPath=$manifestFull; ManifestSha256=$ManifestSha256 }
}

function New-TaskSpec {
    [pscustomobject]@{ TaskPath=$script:Contract.TaskPath; TaskName=$script:Contract.TaskName; Principal=$script:Contract.Account; Sid=$script:Contract.Sid; LogonType='Interactive'; RunLevel='Limited'; TriggerType='Logon'; TriggerUser=$script:Contract.Account; Execute=$script:Contract.Executable; Arguments=''; WorkingDirectory=$script:Contract.InstallRoot; MultipleInstances='IgnoreNew'; RestartCount=3; RestartInterval='PT1M' }
}

function Get-TaskSpecComparison($Actual) {
    $expected=New-TaskSpec
    foreach($name in $expected.PSObject.Properties.Name) {
        $e=[string]$expected.$name
        $a=if($null -eq $Actual){$null}else{[string]$Actual.$name}
        if($name -eq 'Principal') {
            $expectedSid=$expected.Sid; $actualSid=if($Actual -and $Actual.PSObject.Properties.Name -contains 'PrincipalResolvedSid'){$Actual.PrincipalResolvedSid}elseif($Actual){Resolve-RepatoAccountSid $a}else{$null}
            [pscustomobject]@{Property=$name;Expected=$e;Actual=$a;NormalizedExpected=$expectedSid;NormalizedActual=$actualSid;Match=($actualSid -cne $null -and $actualSid -ceq $expectedSid);ExpectedPrincipalDisplay=$e;ActualPrincipalDisplay=$a;ExpectedPrincipalSid=$expectedSid;ActualPrincipalResolvedSid=$actualSid}
        } elseif($name -eq 'TriggerUser') {
            $expectedSid=$expected.Sid; $actualSid=if($Actual -and $Actual.PSObject.Properties.Name -contains 'TriggerResolvedSid'){$Actual.TriggerResolvedSid}elseif($Actual){Resolve-RepatoAccountSid $a}else{$null}
            [pscustomobject]@{Property=$name;Expected=$e;Actual=$a;NormalizedExpected=$expectedSid;NormalizedActual=$actualSid;Match=($actualSid -cne $null -and $actualSid -ceq $expectedSid);ExpectedTriggerDisplay=$e;ActualTriggerDisplay=$a;ExpectedTriggerSid=$expectedSid;ActualTriggerResolvedSid=$actualSid}
        } else {
            [pscustomobject]@{Property=$name;Expected=$e;Actual=$a;NormalizedExpected=$e;NormalizedActual=$a;Match=($a -cne $null -and $a -ceq $e)}
        }
    }
}

function Test-TaskSpec($Actual) {
    -not @(Get-TaskSpecComparison $Actual | Where-Object { -not $_.Match }).Count
}

function Get-RepatoQaLaunchAgentDiagnosticRoot {
    $root=Join-Path $PSScriptRoot '..\QA\Reports\RepatoQaLaunchAgentBootstrap'
    [IO.Path]::GetFullPath($root)
}

function Write-RepatoQaLaunchAgentDiagnostics($Snapshot,$Comparison,$RuntimeIntegrity,$ErrorMessage) {
    $root=Get-RepatoQaLaunchAgentDiagnosticRoot
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $path=Join-Path $root ('failure-'+(Get-Date -Format 'yyyyMMdd-HHmmssfff')+'-'+[guid]::NewGuid().ToString('N')+'.json')
    [pscustomobject]@{SchemaVersion=1;CapturedAtUtc=[DateTime]::UtcNow.ToString('o');TaskSnapshot=$Snapshot;ContractComparison=@($Comparison);RuntimeIntegrity=$RuntimeIntegrity;Error=$ErrorMessage} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    $path
}

function Get-RepatoQaLaunchAgentRuntimeIntegrity([string]$TargetRoot,$Manifest) {
    foreach($entry in $Manifest.files) {
        $path=Join-Path $TargetRoot $entry.name
        $actual=if(Test-Path -LiteralPath $path -PathType Leaf){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}else{$null}
        [pscustomobject]@{File=$entry.name;ExpectedSha256=$entry.sha256;ActualSha256=$actual;Match=($actual -cne $null -and $actual -ceq $entry.sha256)}
    }
}

function Read-ValidatedRepatoQaLaunchAgentSnapshot([string]$SnapshotRoot,[string]$ManifestSha256,[string]$ExpectedRoot,[string]$ExpectedManifestSha256) {
    $root=[IO.Path]::GetFullPath($SnapshotRoot).TrimEnd('\')
    if($root -ine [IO.Path]::GetFullPath($ExpectedRoot).TrimEnd('\') -or $ManifestSha256 -ine $ExpectedManifestSha256){throw 'Recovery snapshot identity differs from the approved v1.0.10 handoff.'}
    $manifestPath=Join-Path $root 'Repato.QaLaunchAgent.snapshot.json'
    if(!(Test-Path -LiteralPath $manifestPath -PathType Leaf) -or (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ine $ExpectedManifestSha256){throw 'Recovery snapshot manifest hash validation failed.'}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    if($manifest.schemaVersion -ne 1 -or $manifest.kind -cne 'Repato.QaLaunchAgent.InstalledRuntimeSnapshot' -or $manifest.product -cne 'Repato.QaLaunchAgent' -or $manifest.productVersion -cne '1.0.10+50d5d752d9a8' -or $manifest.installRoot -ine $script:Contract.InstallRoot -or $manifest.observedByAccount -ine $script:Contract.Account -or $manifest.observedBySid -cne $script:Contract.Sid){throw 'Recovery snapshot metadata does not match the fixed RepatoQA runtime contract.'}
    $files=@($manifest.files);$names=@($files|ForEach-Object name)
    if($files.Count -ne $script:Contract.RuntimeFiles.Count -or $names.Count -ne (@($names|Select-Object -Unique)).Count -or @($script:Contract.RuntimeFiles|Where-Object{$_ -cnotin $names}).Count){throw 'Recovery snapshot runtime file set is incomplete or ambiguous.'}
    foreach($entry in $files){
        if($entry.name -notin $script:Contract.RuntimeFiles -or $entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Recovery snapshot contains an invalid runtime entry.'}
        $path=Join-Path $root $entry.name
        if(!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry.sha256){throw "Recovery snapshot file hash validation failed: $($entry.name)"}
    }
    [pscustomobject]@{Root=$root;ManifestPath=$manifestPath;ManifestSha256=$ExpectedManifestSha256;Manifest=$manifest}
}

function Test-RepatoQaLaunchAgentFileSet([string]$Root) {
    if(!(Test-Path -LiteralPath $Root -PathType Container)){return $false}
    $children=@(Get-ChildItem -LiteralPath $Root -Force)
    $children.Count -eq $script:Contract.RuntimeFiles.Count -and @($children|Where-Object{$_.PSIsContainer -or $_.Name -cnotin $script:Contract.RuntimeFiles}).Count -eq 0 -and @($script:Contract.RuntimeFiles|Where-Object{!(Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf)}).Count -eq 0
}

function Test-RepatoQaLaunchAgentSnapshotFiles([string]$Root,$Manifest) {
    $integrity=Get-RepatoQaLaunchAgentRuntimeIntegrity $Root $Manifest
    @($integrity).Count -eq $script:Contract.RuntimeFiles.Count -and @($integrity|Where-Object{!$_.Match}).Count -eq 0
}

function Invoke-RepatoQaLaunchAgentSnapshotRecoveryCore {
    param(
        [Parameter(Mandatory)][string]$SnapshotRoot,[Parameter(Mandatory)][string]$ManifestSha256,
        [Parameter(Mandatory)][string]$ExpectedSnapshotRoot,[Parameter(Mandatory)][string]$ExpectedManifestSha256,
        [Parameter(Mandatory)][string]$TargetRoot,[Parameter(Mandatory)]$Context,
        [switch]$AllowTestRoot,[scriptblock]$InterruptionHook
    )
    $snapshot=Read-ValidatedRepatoQaLaunchAgentSnapshot $SnapshotRoot $ManifestSha256 $ExpectedSnapshotRoot $ExpectedManifestSha256
    & $Context.AssertAdministrator
    & $Context.ResolveIdentity $script:Contract.Account $script:Contract.Sid
    $target=[IO.Path]::GetFullPath($TargetRoot).TrimEnd('\')
    if(!$AllowTestRoot -and $target -cne $script:Contract.InstallRoot){throw 'Snapshot recovery is restricted to the fixed protected install root.'}
    if($target -cne [IO.Path]::GetFullPath($script:Contract.InstallRoot).TrimEnd('\') -and !$AllowTestRoot){throw 'Snapshot recovery target identity mismatch.'}
    $parent=Split-Path $target -Parent
    $transactions=@(Get-ChildItem -LiteralPath $parent -Force -Directory|Where-Object{$_.Name -match '^\.QaLaunchAgent\.snapshot-recovery\.[A-Fa-f0-9]{32}$'})
    if($transactions.Count -gt 1){throw 'Multiple snapshot-recovery transactions exist; refusing ambiguous recovery.'}
    if(!(Test-Path -LiteralPath $target -PathType Container) -and !$transactions.Count){throw 'Installed runtime root is missing; refusing ambiguous recovery.'}
    $task=& $Context.GetTask
    if(!$task -or !(Test-TaskSpec $task)){throw 'Scheduled-task identity or interactive logon contract is invalid; refusing recovery.'}
    if([string](& $Context.GetTaskState) -cne 'Ready'){throw 'Scheduled task is not in the safe Ready state; refusing recovery.'}
    if(@(& $Context.GetProcesses).Count){throw 'Launch Agent is running; refusing snapshot recovery.'}

    if(!$transactions.Count -and (Test-RepatoQaLaunchAgentSnapshotFiles $target $snapshot.Manifest)){return [pscustomobject]@{Recovered=$true;AlreadyRestored=$true;ProductVersion=$snapshot.Manifest.productVersion;SnapshotManifestSha256=$snapshot.ManifestSha256;TaskChanged=$false;AclPolicyChanged=$false;RetainedEvidence=$true}}

    if(!$transactions.Count){
        if(!(Test-RepatoQaLaunchAgentFileSet $target)){throw 'Installed runtime file set is incomplete or contains unrelated files; refusing recovery.'}
        $transactionRoot=Join-Path $parent ('.QaLaunchAgent.snapshot-recovery.'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $transactionRoot|Out-Null
        & $Context.CopySecurity $target $transactionRoot
        $stage=Join-Path $transactionRoot 'stage';$backup=Join-Path $transactionRoot 'previous';$journalPath=Join-Path $transactionRoot 'recovery.json'
        New-Item -ItemType Directory -Path $stage|Out-Null
        & $Context.CopySecurity $target $stage
        $priorFiles=@()
        foreach($entry in $snapshot.Manifest.files){
            $installedFile=Join-Path $target $entry.name
            $priorFiles+=[pscustomobject]@{name=$entry.name;sha256=(Get-FileHash -LiteralPath $installedFile -Algorithm SHA256).Hash}
            Copy-Item -LiteralPath (Join-Path $snapshot.Root $entry.name) -Destination (Join-Path $stage $entry.name)
            & $Context.CopySecurity $installedFile (Join-Path $stage $entry.name)
        }
        if(!(Test-RepatoQaLaunchAgentSnapshotFiles $stage $snapshot.Manifest)){throw 'Staged recovery runtime failed snapshot hash verification.'}
        $journal=[pscustomobject]@{schemaVersion=1;targetRoot=$target;snapshotRoot=$snapshot.Root;snapshotManifestSha256=$snapshot.ManifestSha256;stageRoot=$stage;backupRoot=$backup;priorFiles=$priorFiles;createdUtc=[DateTime]::UtcNow.ToString('o')}
        $journal|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $journalPath -Encoding UTF8
        if($InterruptionHook){& $InterruptionHook 'Prepared'}
        $transaction=Get-Item -LiteralPath $transactionRoot
    } else {
        $transaction=$transactions[0];$transactionRoot=$transaction.FullName;$journalPath=Join-Path $transactionRoot 'recovery.json'
        if(!(Test-Path -LiteralPath $journalPath -PathType Leaf)){throw 'An incomplete snapshot-recovery directory has no journal; refusing ambiguous recovery.'}
        $journal=Get-Content -LiteralPath $journalPath -Raw|ConvertFrom-Json
        $stage=Join-Path $transactionRoot 'stage';$backup=Join-Path $transactionRoot 'previous'
        $priorNames=@($journal.priorFiles|ForEach-Object name)
        if($journal.schemaVersion -ne 1 -or [IO.Path]::GetFullPath($journal.targetRoot).TrimEnd('\') -cne $target -or [IO.Path]::GetFullPath($journal.snapshotRoot).TrimEnd('\') -ine $snapshot.Root -or $journal.snapshotManifestSha256 -ine $snapshot.ManifestSha256 -or [IO.Path]::GetFullPath($journal.stageRoot) -ine [IO.Path]::GetFullPath($stage) -or [IO.Path]::GetFullPath($journal.backupRoot) -ine [IO.Path]::GetFullPath($backup) -or $priorNames.Count -ne $script:Contract.RuntimeFiles.Count -or $priorNames.Count -ne (@($priorNames|Select-Object -Unique)).Count -or @($script:Contract.RuntimeFiles|Where-Object{$_ -cnotin $priorNames}).Count -or @($journal.priorFiles|Where-Object{$_.sha256 -notmatch '^[A-Fa-f0-9]{64}'}).Count){throw 'Snapshot-recovery journal identity is invalid; refusing recovery.'}
        if(Test-Path -LiteralPath $backup -PathType Container){if(!(Test-RepatoQaLaunchAgentFileSet $backup) -or !(Test-RepatoQaLaunchAgentSnapshotFiles $backup ([pscustomobject]@{files=@($journal.priorFiles)}))){throw 'Retained pre-recovery runtime failed integrity validation; refusing recovery.'}}
        if(Test-Path -LiteralPath $stage -PathType Container){if(!(Test-RepatoQaLaunchAgentFileSet $stage) -or !(Test-RepatoQaLaunchAgentSnapshotFiles $stage $snapshot.Manifest)){throw 'Interrupted recovery stage failed snapshot validation; refusing recovery.'}}
    }

    $hasStage=Test-Path -LiteralPath $stage -PathType Container
    $hasBackup=Test-Path -LiteralPath $backup -PathType Container
    $hasTarget=Test-Path -LiteralPath $target -PathType Container
    if($hasTarget -and (Test-RepatoQaLaunchAgentSnapshotFiles $target $snapshot.Manifest)){
        if($hasStage -or !$hasBackup){throw 'Snapshot runtime is present with an ambiguous recovery transaction; refusing cleanup.'}
        return [pscustomobject]@{Recovered=$true;AlreadyRestored=$true;ProductVersion=$snapshot.Manifest.productVersion;SnapshotManifestSha256=$snapshot.ManifestSha256;TaskChanged=$false;AclPolicyChanged=$false;RetainedEvidence=$true;RecoveryDirectory=$transactionRoot}
    }
    if($hasTarget -and $hasStage -and !$hasBackup){
        $prior=@($journal.priorFiles)
        if(!(Test-RepatoQaLaunchAgentFileSet $target) -or !(Test-RepatoQaLaunchAgentSnapshotFiles $target ([pscustomobject]@{files=$prior}))){throw 'Installed runtime changed after recovery staging; refusing to move it.'}
        if([string](& $Context.GetTaskState) -cne 'Ready' -or @(& $Context.GetProcesses).Count){throw 'Launch Agent or scheduled task changed before recovery; refusing to move the installed runtime.'}
        Move-Item -LiteralPath $target -Destination $backup
        if($InterruptionHook){& $InterruptionHook 'PreviousMoved'}
        $hasTarget=$false;$hasBackup=$true
    }
    if(!$hasTarget -and $hasStage -and $hasBackup){
        if([string](& $Context.GetTaskState) -cne 'Ready' -or @(& $Context.GetProcesses).Count){throw 'Launch Agent or scheduled task changed before recovery; refusing to install the snapshot runtime.'}
        Move-Item -LiteralPath $stage -Destination $target
        if($InterruptionHook){& $InterruptionHook 'SnapshotMoved'}
        $hasTarget=$true;$hasStage=$false
    }
    if(!$hasTarget -or !(Test-RepatoQaLaunchAgentSnapshotFiles $target $snapshot.Manifest) -or !$hasBackup){throw 'Snapshot recovery did not reach a verified, recoverable state; preserve the transaction directory for administrator review.'}
    [pscustomobject]@{Recovered=$true;AlreadyRestored=$false;ProductVersion=$snapshot.Manifest.productVersion;SnapshotManifestSha256=$snapshot.ManifestSha256;TaskChanged=$false;AclPolicyChanged=$false;RetainedEvidence=$true;RecoveryDirectory=$transactionRoot;PreviousRuntime=$backup}
}

function New-RealBootstrapContext {
    [pscustomobject]@{
        IsAdministrator = { Assert-Administrator }
        ResolveIdentity = { param($a,$s) Assert-Identity $a $s }
        PrepareAcl = { param($path)
            $acl=New-Object Security.AccessControl.DirectorySecurity
            $acl.SetAccessRuleProtection($true,$false)
            foreach($r in @(
                (New-Object Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow')),
                (New-Object Security.AccessControl.FileSystemAccessRule('Administrators','FullControl','ContainerInherit,ObjectInherit','None','Allow')),
                (New-Object Security.AccessControl.FileSystemAccessRule($script:Contract.Account,'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')))){$acl.AddAccessRule($r)|Out-Null}
            Set-Acl -LiteralPath $path -AclObject $acl
        }
        GetTask = {
            $t=Get-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -ErrorAction SilentlyContinue
            if(!$t){return $null}; $a=@($t.Actions)[0]; $g=@($t.Triggers)[0]
            [pscustomobject]@{TaskPath=$t.TaskPath;TaskName=$t.TaskName;Principal=$t.Principal.UserId;PrincipalResolvedSid=(Resolve-RepatoAccountSid $t.Principal.UserId);Sid=$script:Contract.Sid;LogonType=[string]$t.Principal.LogonType;RunLevel=[string]$t.Principal.RunLevel;TriggerType=if($g.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger'){'Logon'}else{$g.CimClass.CimClassName};TriggerUser=$g.UserId;TriggerResolvedSid=(Resolve-RepatoAccountSid $g.UserId);Execute=$a.Execute;Arguments=[string]$a.Arguments;WorkingDirectory=$a.WorkingDirectory;MultipleInstances=[string]$t.Settings.MultipleInstances;RestartCount=$t.Settings.RestartCount;RestartInterval=[string]$t.Settings.RestartInterval}
        }
        GetTaskSnapshot = {
            $t=Get-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -ErrorAction SilentlyContinue
            if(!$t){return $null}; $a=@($t.Actions)[0]; $g=@($t.Triggers)[0]
            $v=& $Context.GetTask
            [pscustomobject]@{TaskPath=$t.TaskPath;TaskName=$t.TaskName;State=$t.State;PrincipalUserId=$t.Principal.UserId;PrincipalLogonType=[string]$t.Principal.LogonType;PrincipalRunLevel=[string]$t.Principal.RunLevel;TriggerType=$g.CimClass.CimClassName;TriggerUserId=$g.UserId;ActionExecute=$a.Execute;ActionArguments=[string]$a.Arguments;ActionWorkingDirectory=$a.WorkingDirectory;MultipleInstances=[string]$t.Settings.MultipleInstances;RestartCount=$t.Settings.RestartCount;RestartInterval=[string]$t.Settings.RestartInterval;ExpectedPrincipalDisplay=$script:Contract.Account;ActualPrincipalDisplay=$t.Principal.UserId;ExpectedPrincipalSid=$script:Contract.Sid;ActualPrincipalResolvedSid=$v.PrincipalResolvedSid;ExpectedTriggerDisplay=$script:Contract.Account;ActualTriggerDisplay=$g.UserId;ExpectedTriggerSid=$script:Contract.Sid;ActualTriggerResolvedSid=$v.TriggerResolvedSid;AccountDisplayCanonicalizationObserved=(($t.Principal.UserId -cne $script:Contract.Account -or $g.UserId -cne $script:Contract.Account) -and $v.PrincipalResolvedSid -ceq $script:Contract.Sid -and $v.TriggerResolvedSid -ceq $script:Contract.Sid);ValidatorRepresentation=$v}
        }
        ExportTask = { param($task) if($task){ Export-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName } }
        SetTask = { param($spec)
            $action=New-ScheduledTaskAction -Execute $spec.Execute -WorkingDirectory $spec.WorkingDirectory
            $trigger=New-ScheduledTaskTrigger -AtLogOn -User $spec.Principal
            $principal=New-ScheduledTaskPrincipal -UserId $spec.Principal -LogonType Interactive -RunLevel Limited
            $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
            Register-ScheduledTask -TaskPath $spec.TaskPath -TaskName $spec.TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        }
        RestoreTask = { param($xml) if($xml){Register-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -Xml $xml -Force|Out-Null}else{Unregister-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -Confirm:$false -ErrorAction SilentlyContinue} }
        RemoveTask = { Unregister-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -Confirm:$false -ErrorAction SilentlyContinue }
    }
}

function New-RealSnapshotRecoveryContext {
    [pscustomobject]@{
        AssertAdministrator = { Assert-Administrator }
        ResolveIdentity = { param($a,$s) Assert-Identity $a $s }
        GetTask = { $context=New-RealBootstrapContext; & $context.GetTask }
        GetTaskState = { (Get-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -ErrorAction Stop).State.ToString() }
        GetProcesses = { @(Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue) }
        CopySecurity = { param($source,$destination) Set-Acl -LiteralPath $destination -AclObject (Get-Acl -LiteralPath $source) }
    }
}

function Restore-RepatoQaLaunchAgentSnapshot {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param()
    $snapshotRoot='C:\Repato-Autonomous\RecoveryHandoff\QaLaunchAgent-v1.0.10-50d5d752d9a8\Snapshot'
    $manifestSha256='F25A3DE088188E7ACB87CA950B199B89110813C4007FADB99AA27F81B5ACC738'
    Assert-Administrator
    Assert-Identity $script:Contract.Account $script:Contract.Sid
    if($PSCmdlet.ShouldProcess($script:Contract.InstallRoot,'Restore independently verified v1.0.10 Launch Agent snapshot')){
        Invoke-RepatoQaLaunchAgentSnapshotRecoveryCore -SnapshotRoot $snapshotRoot -ManifestSha256 $manifestSha256 -ExpectedSnapshotRoot $snapshotRoot -ExpectedManifestSha256 $manifestSha256 -TargetRoot $script:Contract.InstallRoot -Context (New-RealSnapshotRecoveryContext)
    }
}

function Invoke-InstallCore($Validated,$Context,[string]$TargetRoot,[switch]$AllowTestRoot,[scriptblock]$ProcessDetector,[switch]$RetainRollback) {
    & $Context.IsAdministrator
    & $Context.ResolveIdentity $script:Contract.Account $script:Contract.Sid
    if (-not $AllowTestRoot -and [IO.Path]::GetFullPath($TargetRoot).TrimEnd('\') -cne $script:Contract.InstallRoot) { throw 'Install root must be the fixed protected Program Files path.' }
    if (-not $ProcessDetector) { $ProcessDetector = { Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue } }
    if (& $ProcessDetector) { throw 'Refusing update while the launch agent is running.' }
    $parent=Split-Path $TargetRoot -Parent; New-Item -ItemType Directory -Path $parent -Force|Out-Null
    $stage=Join-Path $parent ('.QaLaunchAgent.stage.'+[guid]::NewGuid().ToString('N')); $backup=Join-Path $parent ('.QaLaunchAgent.backup.'+[guid]::NewGuid().ToString('N'))
    $oldTask=& $Context.GetTask; $oldXml=& $Context.ExportTask $oldTask
    $hadTarget=Test-Path -LiteralPath $TargetRoot
    $oldFiles=@()
    if($hadTarget){foreach($name in $script:Contract.RuntimeFiles){$path=Join-Path $TargetRoot $name;if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Existing runtime is incomplete: $name"};$oldFiles+= [pscustomobject]@{name=$name;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}}}
    try {
        New-Item -ItemType Directory -Path $stage|Out-Null
        foreach($e in $Validated.Manifest.files){Copy-Item -LiteralPath (Join-Path $Validated.SourceRoot $e.name) -Destination (Join-Path $stage $e.name)}
        & $Context.PrepareAcl $stage
        foreach($e in $Validated.Manifest.files){if((Get-FileHash -LiteralPath (Join-Path $stage $e.name) -Algorithm SHA256).Hash -cne $e.sha256){throw "Staged hash mismatch: $($e.name)"}}
        if($hadTarget){Move-Item -LiteralPath $TargetRoot -Destination $backup}
        Move-Item -LiteralPath $stage -Destination $TargetRoot
        & $Context.SetTask (New-TaskSpec)
        $actual=& $Context.GetTask
        $snapshot=if($Context.PSObject.Properties.Name -contains 'GetTaskSnapshot'){& $Context.GetTaskSnapshot}else{$actual}
        $comparison=@(Get-TaskSpecComparison $actual)
        if(-not (Test-TaskSpec $actual)) {
            $report=Write-RepatoQaLaunchAgentDiagnostics $snapshot $comparison (Get-RepatoQaLaunchAgentRuntimeIntegrity $TargetRoot $Validated.Manifest) 'Registered scheduled task does not match the security contract.'
            throw "Registered scheduled task does not match the security contract. Diagnostic report: $report"
        }
        foreach($e in $Validated.Manifest.files){if((Get-FileHash -LiteralPath (Join-Path $TargetRoot $e.name) -Algorithm SHA256).Hash -cne $e.sha256){throw "Installed hash mismatch: $($e.name)"}}
        $token=$null
        if($RetainRollback){$token=[pscustomobject]@{Id=[guid]::NewGuid().ToString('N');TargetRoot=[IO.Path]::GetFullPath($TargetRoot);BackupRoot=if(Test-Path -LiteralPath $backup){$backup}else{$null};PriorFiles=$oldFiles;InstalledFiles=@($Validated.Manifest.files);OldTaskXml=$oldXml;Updated=$hadTarget;CleanupRoot=$null;Restored=$false};$script:PendingInstallRollbacks[$token.Id]=$token}
        elseif(Test-Path -LiteralPath $backup){Remove-Item -LiteralPath $backup -Recurse -Force}
        [pscustomobject]@{Installed=$true;Updated=$hadTarget;Task=(New-TaskSpec);ProductVersion=$Validated.Manifest.productVersion;ManifestSha256=$Validated.ManifestSha256;RollbackToken=$token}
    } catch {
        & $Context.RestoreTask $oldXml
        if(Test-Path -LiteralPath $TargetRoot){Remove-Item -LiteralPath $TargetRoot -Recurse -Force}
        if(Test-Path -LiteralPath $backup){Move-Item -LiteralPath $backup -Destination $TargetRoot}
        if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}
        throw
    }
}

function Assert-InstallRollbackToken($Token,[string]$TargetRoot,[switch]$AllowTestRoot) {
    if(!$Token.Id -or !$script:PendingInstallRollbacks.ContainsKey([string]$Token.Id) -or ![object]::ReferenceEquals($script:PendingInstallRollbacks[[string]$Token.Id],$Token)){throw 'Rollback token is unknown or was modified.'}
    $target=[IO.Path]::GetFullPath($TargetRoot).TrimEnd('\');$expected=[IO.Path]::GetFullPath($Token.TargetRoot).TrimEnd('\')
    if($target -cne $expected -or (!$AllowTestRoot -and $target -cne $script:Contract.InstallRoot)){throw 'Rollback token does not match the fixed install root.'}
    foreach($path in @($Token.BackupRoot,$Token.CleanupRoot)|Where-Object{$_}) {
        $full=[IO.Path]::GetFullPath($path);$parent=Split-Path $target -Parent
        if((Split-Path $full -Parent) -ine $parent -or (Split-Path $full -Leaf) -notmatch '^\.QaLaunchAgent\.(backup\.[0-9a-fA-F]{32}|failed\.[0-9a-fA-F-]{36})$'){throw 'Rollback token contains an unsafe sibling path.'}
    }
}

function Restore-InstallCore($Token,$Context,[string]$TargetRoot,[switch]$AllowTestRoot,[scriptblock]$ProcessDetector) {
    Assert-InstallRollbackToken $Token $TargetRoot -AllowTestRoot:$AllowTestRoot
    if(!$ProcessDetector){$ProcessDetector={Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue}}
    if(& $ProcessDetector){throw 'Stop the Launch Agent before restoring its runtime.'}
    if($Token.Updated){
        if(!(Test-Path -LiteralPath $Token.BackupRoot -PathType Container)){throw 'Verified prior runtime backup is missing.'}
        $prior=Get-RepatoQaLaunchAgentRuntimeIntegrity $Token.BackupRoot ([pscustomobject]@{files=$Token.PriorFiles})
        if(@($prior|Where-Object{!$_.Match}).Count){throw 'Prior runtime backup integrity failed; refusing rollback.'}
    }
    & $Context.RestoreTask $Token.OldTaskXml
    $failed=if(Test-Path -LiteralPath $TargetRoot){Join-Path (Split-Path $TargetRoot -Parent) ('.QaLaunchAgent.failed.'+[guid]::NewGuid().ToString('D'))}else{$null}
    if($failed){Move-Item -LiteralPath $TargetRoot -Destination $failed}
    try {
        if($Token.Updated){Move-Item -LiteralPath $Token.BackupRoot -Destination $TargetRoot}
        $expected=if($Token.Updated){$Token.PriorFiles}else{@()}
        $integrity=if($Token.Updated){Get-RepatoQaLaunchAgentRuntimeIntegrity $TargetRoot ([pscustomobject]@{files=$expected})}else{@()}
        if(@($integrity|Where-Object{!$_.Match}).Count){throw 'Restored runtime integrity failed.'}
        $Token.Restored=$true;$Token.CleanupRoot=$failed
        $Token | Add-Member -NotePropertyName RuntimeIntegrity -NotePropertyValue $integrity -Force
        $Token | Add-Member -NotePropertyName RestoredTask -NotePropertyValue ($null -ne $Token.OldTaskXml) -Force
        $Token
    } catch {
        if($Token.Updated -and (Test-Path -LiteralPath $TargetRoot) -and !(Test-Path -LiteralPath $Token.BackupRoot)){Move-Item -LiteralPath $TargetRoot -Destination $Token.BackupRoot}
        if($failed -and (Test-Path -LiteralPath $failed) -and !(Test-Path -LiteralPath $TargetRoot)){Move-Item -LiteralPath $failed -Destination $TargetRoot}
        throw
    }
}

function Complete-InstallCore($Token,[string]$TargetRoot,[switch]$AllowTestRoot) {
    Assert-InstallRollbackToken $Token $TargetRoot -AllowTestRoot:$AllowTestRoot
    $expected=if($Token.Restored){$Token.PriorFiles}else{$Token.InstalledFiles}
    $integrity=if(@($expected).Count){Get-RepatoQaLaunchAgentRuntimeIntegrity $TargetRoot ([pscustomobject]@{files=$expected})}else{@()}
    if(@($integrity|Where-Object{!$_.Match}).Count){throw 'Runtime changed before rollback retention could be finalized.'}
    $cleanup=if($Token.Restored){$Token.CleanupRoot}else{$Token.BackupRoot}
    $cleanupComplete=$true;$cleanupError=$null
    if($cleanup -and (Test-Path -LiteralPath $cleanup)){try{Remove-Item -LiteralPath $cleanup -Recurse -Force -ErrorAction Stop}catch{$cleanupComplete=$false;$cleanupError=$_.Exception.Message}}
    [void]$script:PendingInstallRollbacks.Remove([string]$Token.Id)
    [pscustomobject]@{Completed=$true;Restored=[bool]$Token.Restored;RuntimeIntegrity=$integrity;CleanupComplete=$cleanupComplete;CleanupError=$cleanupError}
}

function Install-RepatoQaLaunchAgentBootstrap {
    [CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ManifestSha256,[string]$Account=$script:Contract.Account,[string]$ExpectedSid=$script:Contract.Sid,[switch]$RetainRollback)
    Assert-Administrator; Assert-Identity $Account $ExpectedSid
    $v=Read-ValidatedManifest $SourceRoot $ManifestPath $ManifestSha256.ToUpperInvariant()
    if($PSCmdlet.ShouldProcess($script:Contract.InstallRoot,'Atomically install launch-agent runtime and reconcile its logon task')){Invoke-InstallCore $v (New-RealBootstrapContext) $script:Contract.InstallRoot -RetainRollback:$RetainRollback}
}

function Restore-RepatoQaLaunchAgentBootstrapInstall {
    [CmdletBinding()]param([Parameter(Mandatory)]$RollbackToken,[string]$Account=$script:Contract.Account,[string]$ExpectedSid=$script:Contract.Sid)
    Assert-Administrator;Assert-Identity $Account $ExpectedSid
    Restore-InstallCore $RollbackToken (New-RealBootstrapContext) $script:Contract.InstallRoot
}

function Complete-RepatoQaLaunchAgentBootstrapInstall {
    [CmdletBinding()]param([Parameter(Mandatory)]$RollbackToken,[string]$Account=$script:Contract.Account,[string]$ExpectedSid=$script:Contract.Sid)
    Assert-Administrator;Assert-Identity $Account $ExpectedSid
    Complete-InstallCore $RollbackToken $script:Contract.InstallRoot
}

function Test-RepatoQaLaunchAgentBootstrap {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$ManifestSha256)
    $v=Read-ValidatedManifest $script:Contract.InstallRoot $ManifestPath $ManifestSha256.ToUpperInvariant(); $ctx=New-RealBootstrapContext; $task=& $ctx.GetTask
    [pscustomobject]@{ScheduledTaskRegistered=[bool]$task;TaskContractValid=($task -and (Test-TaskSpec $task));InstalledRuntimeIntegrity=[bool]$v;ProductVersion=$v.Manifest.productVersion}
}

function Uninstall-RepatoQaLaunchAgentBootstrap {
    [CmdletBinding(SupportsShouldProcess)]param()
    Assert-Administrator
    if($PSCmdlet.ShouldProcess($script:Contract.InstallRoot,'Remove launch-agent task and runtime')){$ctx=New-RealBootstrapContext;& $ctx.RemoveTask;if(Test-Path -LiteralPath $script:Contract.InstallRoot){Remove-Item -LiteralPath $script:Contract.InstallRoot -Recurse -Force}}
}

Export-ModuleMember -Function Get-RepatoQaLaunchAgentBootstrapContract,Install-RepatoQaLaunchAgentBootstrap,Restore-RepatoQaLaunchAgentBootstrapInstall,Restore-RepatoQaLaunchAgentSnapshot,Complete-RepatoQaLaunchAgentBootstrapInstall,Test-RepatoQaLaunchAgentBootstrap,Uninstall-RepatoQaLaunchAgentBootstrap,Get-TaskSpecComparison,Get-RepatoQaLaunchAgentRuntimeIntegrity
