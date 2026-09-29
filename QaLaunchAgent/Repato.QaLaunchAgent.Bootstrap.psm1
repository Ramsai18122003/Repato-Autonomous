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

function Invoke-InstallCore($Validated,$Context,[string]$TargetRoot,[switch]$AllowTestRoot) {
    & $Context.IsAdministrator
    & $Context.ResolveIdentity $script:Contract.Account $script:Contract.Sid
    if (-not $AllowTestRoot -and [IO.Path]::GetFullPath($TargetRoot).TrimEnd('\') -cne $script:Contract.InstallRoot) { throw 'Install root must be the fixed protected Program Files path.' }
    if (Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue) { throw 'Refusing update while the launch agent is running.' }
    $parent=Split-Path $TargetRoot -Parent; New-Item -ItemType Directory -Path $parent -Force|Out-Null
    $stage=Join-Path $parent ('.QaLaunchAgent.stage.'+[guid]::NewGuid().ToString('N')); $backup=Join-Path $parent ('.QaLaunchAgent.backup.'+[guid]::NewGuid().ToString('N'))
    $oldTask=& $Context.GetTask; $oldXml=& $Context.ExportTask $oldTask
    $hadTarget=Test-Path -LiteralPath $TargetRoot
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
        if(Test-Path -LiteralPath $backup){Remove-Item -LiteralPath $backup -Recurse -Force}
        [pscustomobject]@{Installed=$true;Updated=$hadTarget;Task=(New-TaskSpec);ProductVersion=$Validated.Manifest.productVersion;ManifestSha256=$Validated.ManifestSha256}
    } catch {
        & $Context.RestoreTask $oldXml
        if(Test-Path -LiteralPath $TargetRoot){Remove-Item -LiteralPath $TargetRoot -Recurse -Force}
        if(Test-Path -LiteralPath $backup){Move-Item -LiteralPath $backup -Destination $TargetRoot}
        if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}
        throw
    }
}

function Install-RepatoQaLaunchAgentBootstrap {
    [CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ManifestSha256,[string]$Account=$script:Contract.Account,[string]$ExpectedSid=$script:Contract.Sid)
    Assert-Administrator; Assert-Identity $Account $ExpectedSid
    $v=Read-ValidatedManifest $SourceRoot $ManifestPath $ManifestSha256.ToUpperInvariant()
    if($PSCmdlet.ShouldProcess($script:Contract.InstallRoot,'Atomically install launch-agent runtime and reconcile its logon task')){Invoke-InstallCore $v (New-RealBootstrapContext) $script:Contract.InstallRoot}
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

Export-ModuleMember -Function Get-RepatoQaLaunchAgentBootstrapContract,Install-RepatoQaLaunchAgentBootstrap,Test-RepatoQaLaunchAgentBootstrap,Uninstall-RepatoQaLaunchAgentBootstrap,Get-TaskSpecComparison,Get-RepatoQaLaunchAgentRuntimeIntegrity
