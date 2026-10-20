param([int]$TimeoutSeconds = 60, [string]$GameRoot, [string]$ReportPath,
    [ValidateSet('Both','Desktop','Mobile')][string]$Mode = 'Both',
    [ValidateSet('Home','Identity')][string]$Scenario = 'Home')

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runtimeRoot = if ($GameRoot) { (Resolve-Path -LiteralPath $GameRoot).Path } else { $projectRoot }
$reportRoot = Join-Path $projectRoot '.stabilization'
$runId = [guid]::NewGuid().ToString('N')
$prefix = if ($Scenario -eq 'Identity') { 'npc-identity-smoke' } else { 'home-stop-smoke' }
$harnessName = $prefix
$successMarker = if ($Scenario -eq 'Identity') { 'NPC_IDENTITY_SMOKE_OK' } else { 'HOME_STOP_SMOKE_OK' }
$runRoot = Join-Path (Join-Path $reportRoot ($prefix + '-runs')) $runId
$screenshotRoot = Join-Path (Join-Path $reportRoot ($prefix + '-screenshots')) $runId
$loveExe = if ($env:LOVE_EXE) { $env:LOVE_EXE } else { 'C:\Program Files\LOVE\lovec.exe' }
$oldMobile = $env:MOUSE_FRONTIER_MOBILE
$oldAppData = $env:APPDATA
$modes = if ($Mode -eq 'Both') { @('Desktop','Mobile') } else { @($Mode) }
$process = $null
$reports = @()
$expectedScreenshots = @('01-opening.png','02-office.png','02-briefing.png','03-supplies.png','04-repaired.png','05-farewell.png','06-train.png','07-arrival.png','fox-supplies.png','fox-workbench.png','fox-near-engine.png','fox-far-engine.png','fox-talk.png','fox-talk-prompt.png','office-walkmask.png','office-upper-floor.png')
if ($Scenario -eq 'Identity') { $expectedScreenshots = @('sender-card.png','mail-task.png','named-journal.png','passenger-card.png','recipient-directions.png','recipient-map.png','recipient-card.png','deliveries-complete.png') }

try {
    if (-not (Test-Path -LiteralPath $loveExe -PathType Leaf)) { throw 'Set LOVE_EXE to the installed lovec.exe.' }
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    foreach ($currentMode in $modes) {
        $modeName = $currentMode.ToLowerInvariant()
        $harnessRoot = Join-Path $runRoot $modeName
        $isolatedAppData = Join-Path $harnessRoot 'appdata'
        $reportFile = Join-Path $reportRoot ($prefix + '-' + $modeName + '.rpt')
        $errorFile = $reportFile + '.err'
        New-Item -ItemType Directory -Path $harnessRoot | Out-Null
        New-Item -ItemType Directory -Path $isolatedAppData | Out-Null
        foreach ($name in @('game','assets','sounds')) {
            New-Item -ItemType Junction -Path (Join-Path $harnessRoot $name) -Target (Join-Path $runtimeRoot $name) | Out-Null
        }
        foreach ($name in @('main.lua','conf.lua')) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot ($harnessName + '\' + $name)) -Destination (Join-Path $harnessRoot $name)
        }
        $env:MOUSE_FRONTIER_MOBILE = if ($currentMode -eq 'Mobile') { '1' } else { '0' }
        $env:APPDATA = $isolatedAppData
        $process = Start-Process -FilePath $loveExe -ArgumentList ('"' + $harnessRoot + '"') -PassThru -WindowStyle Hidden -RedirectStandardOutput $reportFile -RedirectStandardError $errorFile
        $null = $process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { throw ('Home stop ' + $currentMode + ' validation timed out.') }
        $process.WaitForExit()
        $report = [IO.File]::ReadAllText($reportFile)
        $errors = [IO.File]::ReadAllText($errorFile)
        $source = Join-Path $isolatedAppData ('LOVE\mouse-frontier-' + $prefix)
        $screenshots = if (Test-Path -LiteralPath $source) { @(Get-ChildItem -LiteralPath $source -Filter '*.png' -File) } else { @() }
        $destination = Join-Path $screenshotRoot $modeName
        if ($screenshots.Count -gt 0) {
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            foreach ($shot in $screenshots) { Copy-Item -LiteralPath $shot.FullName -Destination $destination }
            Write-Output ('Screenshots: ' + $destination)
        }
        if ($process.ExitCode -ne 0 -or $report -notmatch $successMarker) { throw ($report + $errors) }
        $freshNames = @($screenshots | ForEach-Object { $_.Name })
        $missing = @($expectedScreenshots | Where-Object { $_ -notin $freshNames })
        if ($screenshots.Count -ne $expectedScreenshots.Count -or $missing.Count -gt 0 -or @($screenshots | Where-Object Length -LE 0).Count -gt 0) {
            throw "Home stop validation requires $($expectedScreenshots.Count) fresh screenshots; found $($screenshots.Count), missing: $($missing -join ', ')."
        }
        $reports += $report.Trim()
        Write-Output $report.Trim()
    }
    $combinedPath = if ($ReportPath) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath) } else { Join-Path $reportRoot ($prefix + '.rpt') }
    New-Item -ItemType Directory -Path (Split-Path -Parent $combinedPath) -Force | Out-Null
    [IO.File]::WriteAllText($combinedPath, ($reports -join [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    $captureLabel = if ($Scenario -eq 'Identity') { 'NPC_IDENTITY_FRESH_SCREENSHOTS=' } else { 'HOME_STOP_FRESH_SCREENSHOTS=' }
    Write-Output ($captureLabel + ($expectedScreenshots.Count * $modes.Count))
}
finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if ($null -eq $oldMobile) { Remove-Item Env:MOUSE_FRONTIER_MOBILE -ErrorAction SilentlyContinue } else { $env:MOUSE_FRONTIER_MOBILE=$oldMobile }
    if ($null -eq $oldAppData) { Remove-Item Env:APPDATA -ErrorAction SilentlyContinue } else { $env:APPDATA=$oldAppData }
    $expectedParent = [IO.Path]::GetFullPath((Join-Path $reportRoot ($prefix + '-runs')))
    $resolvedRun = [IO.Path]::GetFullPath($runRoot)
    if ((Split-Path -Parent $resolvedRun) -eq $expectedParent -and (Split-Path -Leaf $resolvedRun) -eq $runId) {
        foreach ($currentMode in $modes) {
            $harnessRoot = Join-Path $resolvedRun $currentMode.ToLowerInvariant()
            foreach ($name in @('game','assets','sounds')) {
                $link = Join-Path $harnessRoot $name
                if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
            }
        }
        if ((Test-Path -LiteralPath $resolvedRun) -and -not ((Get-Item -LiteralPath $resolvedRun).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Remove-Item -LiteralPath $resolvedRun -Recurse -Force
        }
    }
}
