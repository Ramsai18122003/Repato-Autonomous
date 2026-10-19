$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$store=Join-Path ([IO.Path]::GetTempPath()) ('repato-date-locale-'+[guid]::NewGuid().ToString('N'))
$thread=[Threading.Thread]::CurrentThread
$originalCulture=$thread.CurrentCulture
$originalUiCulture=$thread.CurrentUICulture
try {
    $culture=[Globalization.CultureInfo]::GetCultureInfo('en-IN')
    $thread.CurrentCulture=$culture
    $thread.CurrentUICulture=$culture
    Initialize-RepatoTaskStore $store|Out-Null
    New-RepatoTask $store 'task-date-locale' 'Timestamp locale regression' 'Read a task under a non-US culture' 'fix/task-store-date-locale' 'none'|Out-Null
    $task=Find-RepatoTask (Read-RepatoTaskStore $store) 'task-date-locale'
    if(!$task -or !$task.createdUtc){throw 'Task store did not preserve its creation timestamp.'}
    [pscustomobject]@{Status='PASS';Culture=$culture.Name;TaskId=$task.taskId;TaskRevision=$task.revision}|ConvertTo-Json -Compress
} finally {
    $thread.CurrentCulture=$originalCulture
    $thread.CurrentUICulture=$originalUiCulture
    if(Test-Path -LiteralPath $store){Remove-Item -LiteralPath $store -Recurse -Force}
}
