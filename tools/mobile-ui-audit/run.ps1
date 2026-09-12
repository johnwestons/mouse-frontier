param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '../../.stabilization/mobile-ui-audit'),
    [string]$LovePath = 'C:\Program Files\LOVE\lovec.exe',
    [switch]$Desktop,
    [switch]$Train,
    [switch]$Visible
)
$ErrorActionPreference = 'Stop'
if ($Desktop -and -not $PSBoundParameters.ContainsKey('OutputPath')) {
    $OutputPath = Join-Path $PSScriptRoot '../../.stabilization/desktop-ui-audit'
}
if ($Train -and -not $PSBoundParameters.ContainsKey('OutputPath')) {
    $OutputPath = Join-Path $PSScriptRoot $(if ($Desktop) { '../../.stabilization/desktop-train-audit' } else { '../../.stabilization/mobile-train-audit' })
}
$repoPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$auditPath = (Resolve-Path $PSScriptRoot).Path
$resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null
foreach ($name in @('assets', 'sounds')) {
    $linkPath = Join-Path $auditPath $name
    if (-not (Test-Path -LiteralPath $linkPath)) {
        New-Item -ItemType Junction -Path $linkPath -Target (Join-Path $repoPath $name) | Out-Null
    }
}
$previousMobile = $env:MOUSE_FRONTIER_MOBILE
$previousRoot = $env:MOBILE_UI_AUDIT_ROOT
$previousOutput = $env:MOBILE_UI_AUDIT_OUTPUT
$previousTrain = $env:MOBILE_UI_AUDIT_TRAIN
try {
    $env:MOUSE_FRONTIER_MOBILE = if ($Desktop) { '0' } else { '1' }
    $env:MOBILE_UI_AUDIT_ROOT = $repoPath
    $env:MOBILE_UI_AUDIT_OUTPUT = $resolvedOutput
    $env:MOBILE_UI_AUDIT_TRAIN = if ($Train) { '1' } else { '0' }
    $windowStyle = if ($Visible) { 'Normal' } else { 'Hidden' }
    $auditProcess = Start-Process -FilePath $LovePath -ArgumentList ('"' + $auditPath + '"') -WindowStyle $windowStyle -PassThru `
        -RedirectStandardOutput (Join-Path $resolvedOutput 'stdout.txt') -RedirectStandardError (Join-Path $resolvedOutput 'stderr.txt')
    $null = $auditProcess.Handle
    if (-not $auditProcess.WaitForExit(45000)) {
        Stop-Process -Id $auditProcess.Id -Force
        throw 'Mobile UI audit exceeded 45 seconds.'
    }
    $auditProcess.Refresh()
    Get-Content -LiteralPath (Join-Path $resolvedOutput 'report.txt')
    if ($auditProcess.ExitCode -ne 0) { throw "Mobile UI audit failed with exit code $($auditProcess.ExitCode)." }
} finally {
    $env:MOUSE_FRONTIER_MOBILE = $previousMobile
    $env:MOBILE_UI_AUDIT_ROOT = $previousRoot
    $env:MOBILE_UI_AUDIT_OUTPUT = $previousOutput
    $env:MOBILE_UI_AUDIT_TRAIN = $previousTrain
}
