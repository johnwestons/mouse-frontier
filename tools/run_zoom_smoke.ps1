param([int]$TimeoutSeconds = 45, [string]$GameRoot, [string]$ReportPath)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runtimeRoot = if ($GameRoot) { (Resolve-Path -LiteralPath $GameRoot).Path } else { $projectRoot }
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$runId = [guid]::NewGuid().ToString('N')
$harnessRoot = Join-Path $tempRoot ('mouse-frontier-zoom-smoke-' + $runId)
$reportRoot = Join-Path $projectRoot '.stabilization'
$reportPath = if ($ReportPath) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath) } else { Join-Path $reportRoot 'zoom-smoke.rpt' }
$errorPath = $reportPath + '.err'
$loveExe = if ($env:LOVE_EXE) { $env:LOVE_EXE } else { 'C:\Program Files\LOVE\lovec.exe' }
$oldMobile = $env:MOUSE_FRONTIER_MOBILE
$oldAppData = $env:APPDATA
$isolatedAppData = Join-Path $harnessRoot 'appdata'
$screenshotOutput = Join-Path (Join-Path $reportRoot 'zoom-smoke-screenshots') $runId
$process = $null
try {
    if (-not (Test-Path -LiteralPath $loveExe -PathType Leaf)) { throw 'Set LOVE_EXE to the installed lovec.exe.' }
    New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportPath) -Force | Out-Null
    New-Item -ItemType Directory -Path $harnessRoot | Out-Null
    New-Item -ItemType Directory -Path $isolatedAppData | Out-Null
    foreach ($name in @('game','assets','sounds')) {
        New-Item -ItemType Junction -Path (Join-Path $harnessRoot $name) -Target (Join-Path $runtimeRoot $name) | Out-Null
    }
    foreach ($name in @('main.lua','conf.lua','hud_checks.lua')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('zoom-smoke\' + $name)) -Destination (Join-Path $harnessRoot $name)
    }
    $env:MOUSE_FRONTIER_MOBILE = '1'
    $env:APPDATA = $isolatedAppData
    $process = Start-Process -FilePath $loveExe -ArgumentList ('"' + $harnessRoot + '"') -PassThru -WindowStyle Hidden -RedirectStandardOutput $reportPath -RedirectStandardError $errorPath
    $null = $process.Handle
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { throw 'Zoom validation timed out.' }
    $process.WaitForExit()
    $report = [IO.File]::ReadAllText($reportPath)
    $errors = [IO.File]::ReadAllText($errorPath)
    $screenshotSource = Join-Path $isolatedAppData 'LOVE\mouse-frontier-zoom-smoke'
    $screenshots = if (Test-Path -LiteralPath $screenshotSource) { @(Get-ChildItem -LiteralPath $screenshotSource -Filter '*.png' -File) } else { @() }
    if ($screenshots.Count -gt 0) {
        New-Item -ItemType Directory -Path $screenshotOutput -Force | Out-Null
        $screenshots | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $screenshotOutput }
        Write-Output ('Screenshots: ' + $screenshotOutput)
    }
    if ($process.ExitCode -ne 0 -or $report -notmatch 'ZOOM_SMOKE_OK') { throw ($report + $errors) }
    if ($screenshots.Count -ne 20 -or @($screenshots | Where-Object Length -LE 0).Count -gt 0) {
        throw "Zoom validation must produce 20 fresh non-empty screenshots; found $($screenshots.Count)."
    }
    Write-Output $report.Trim()
}
finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if ($null -eq $oldMobile) { Remove-Item Env:MOUSE_FRONTIER_MOBILE -ErrorAction SilentlyContinue } else { $env:MOUSE_FRONTIER_MOBILE=$oldMobile }
    if ($null -eq $oldAppData) { Remove-Item Env:APPDATA -ErrorAction SilentlyContinue } else { $env:APPDATA=$oldAppData }
    $resolved = [IO.Path]::GetFullPath($harnessRoot)
    if ($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('mouse-frontier-zoom-smoke-')) {
        foreach ($name in @('game','assets','sounds')) {
            $link = Join-Path $resolved $name
            if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        }
        foreach ($name in @('main.lua','conf.lua','hud_checks.lua')) {
            $file = Join-Path $resolved $name
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        }
        $appData = Join-Path $resolved 'appdata'
        if (Test-Path -LiteralPath $appData) {
            $resolvedAppData = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $appData).Path)
            if ((Split-Path -Leaf $resolvedAppData) -eq 'appdata' -and (Split-Path -Parent $resolvedAppData) -eq $resolved -and
                -not ((Get-Item -LiteralPath $resolvedAppData).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Remove-Item -LiteralPath $resolvedAppData -Recurse -Force
            }
        }
        if (Test-Path -LiteralPath $resolved) { [IO.Directory]::Delete($resolved) }
    }
}
