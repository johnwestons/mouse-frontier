param([int]$TimeoutSeconds = 45, [string]$GameRoot, [string]$ReportPath)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runtimeRoot = if ($GameRoot) { (Resolve-Path -LiteralPath $GameRoot).Path } else { $projectRoot }
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$harnessRoot = Join-Path $tempRoot ('mouse-frontier-zoom-smoke-' + [guid]::NewGuid().ToString('N'))
$reportRoot = Join-Path $projectRoot '.stabilization'
$reportPath = if ($ReportPath) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath) } else { Join-Path $reportRoot 'zoom-smoke.rpt' }
$errorPath = $reportPath + '.err'
$loveExe = if ($env:LOVE_EXE) { $env:LOVE_EXE } else { 'C:\Program Files\LOVE\lovec.exe' }
$oldMobile = $env:MOUSE_FRONTIER_MOBILE
$process = $null
try {
    if (-not (Test-Path -LiteralPath $loveExe -PathType Leaf)) { throw 'Set LOVE_EXE to the installed lovec.exe.' }
    New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportPath) -Force | Out-Null
    New-Item -ItemType Directory -Path $harnessRoot | Out-Null
    foreach ($name in @('game','assets','sounds')) {
        New-Item -ItemType Junction -Path (Join-Path $harnessRoot $name) -Target (Join-Path $runtimeRoot $name) | Out-Null
    }
    foreach ($name in @('main.lua','conf.lua')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('zoom-smoke\' + $name)) -Destination (Join-Path $harnessRoot $name)
    }
    $env:MOUSE_FRONTIER_MOBILE = '1'
    $process = Start-Process -FilePath $loveExe -ArgumentList ('"' + $harnessRoot + '"') -PassThru -WindowStyle Hidden -RedirectStandardOutput $reportPath -RedirectStandardError $errorPath
    $null = $process.Handle
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { throw 'Zoom validation timed out.' }
    $process.WaitForExit()
    $report = [IO.File]::ReadAllText($reportPath)
    $errors = [IO.File]::ReadAllText($errorPath)
    if ($process.ExitCode -ne 0 -or $report -notmatch 'ZOOM_SMOKE_OK') { throw ($report + $errors) }
    Write-Output $report.Trim()
    Write-Output ('Screenshots: ' + (Join-Path $env:APPDATA 'LOVE\mouse-frontier-zoom-smoke'))
}
finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if ($null -eq $oldMobile) { Remove-Item Env:MOUSE_FRONTIER_MOBILE -ErrorAction SilentlyContinue } else { $env:MOUSE_FRONTIER_MOBILE=$oldMobile }
    $resolved = [IO.Path]::GetFullPath($harnessRoot)
    if ($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('mouse-frontier-zoom-smoke-')) {
        foreach ($name in @('game','assets','sounds')) {
            $link = Join-Path $resolved $name
            if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        }
        foreach ($name in @('main.lua','conf.lua')) {
            $file = Join-Path $resolved $name
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        }
        if (Test-Path -LiteralPath $resolved) { [IO.Directory]::Delete($resolved) }
    }
}
