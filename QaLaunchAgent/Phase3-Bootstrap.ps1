param([ValidateSet('Show','Install')][string]$Mode='Show')
$ErrorActionPreference='Stop'
if($Mode -eq 'Install'){ throw 'Phase 3 installation is intentionally disabled during Phase 2.' }
[pscustomobject]@{
    AgentPath='C:\Program Files\Repato\QaLaunchAgent\Repato.QaLaunchAgent.exe'
    PipeName='Repato\QaLaunch'
    ExpectedUser='RAMSAI\RepatoQA'
    RevitExe='E:\revit\Revit 2025\Revit.exe'
    QaProfileRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025'
    RuntimeRoot='C:\Repato-Autonomous\Source\QA\TestRuns'
    Startup='RepatoQA logon only; fixed agent executable; no arbitrary arguments'
    Credentials='none'
}
