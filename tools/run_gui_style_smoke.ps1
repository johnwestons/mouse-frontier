param([string]$LovePath='C:\Program Files\LOVE\lovec.exe', [int]$TimeoutSeconds=45, [switch]$Desktop)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$reportRoot=Join-Path $projectRoot $(if ($Desktop) { '.stabilization\gui-style-desktop' } else { '.stabilization\gui-style' })
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('mouse-frontier-gui-style-'+[guid]::NewGuid().ToString('N'))
$oldAppData=$env:APPDATA; $oldMobile=$env:MOUSE_FRONTIER_MOBILE; $oldSmoke=$env:MOUSE_FRONTIER_SMOKE
$process=$null
try {
    New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    foreach ($name in @('game','assets','sounds')) {
        New-Item -ItemType Junction -Path (Join-Path $fixtureRoot $name) -Target (Join-Path $projectRoot $name) | Out-Null
    }
    foreach ($name in @('main.lua','conf.lua')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('gui-style-smoke\'+$name)) -Destination (Join-Path $fixtureRoot $name)
    }
    $env:APPDATA=Join-Path $fixtureRoot 'appdata'
    New-Item -ItemType Directory -Path $env:APPDATA | Out-Null
    $env:MOUSE_FRONTIER_MOBILE=$(if ($Desktop) { '0' } else { '1' }); $env:MOUSE_FRONTIER_SMOKE='1'
    $log=Join-Path $reportRoot 'run.log'; $errorLog=Join-Path $reportRoot 'run.err'
    $process=Start-Process -FilePath $LovePath -ArgumentList ('"'+$fixtureRoot+'"') -PassThru -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError $errorLog
    $null=$process.Handle
    if (-not $process.WaitForExit($TimeoutSeconds*1000)) { throw 'GUI style validation timed out.' }
    $process.WaitForExit()
    $report=[IO.File]::ReadAllText($log)
    if ($process.ExitCode -ne 0 -or $report -notmatch 'GUI_STYLE_OK') { throw ($report+[IO.File]::ReadAllText($errorLog)) }
    $images=Join-Path $env:APPDATA 'LOVE\mouse-frontier-gui-style-smoke'
    Get-ChildItem -LiteralPath $images -Filter '*.png' -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $reportRoot $_.Name) -Force }
    if (@(Get-ChildItem -LiteralPath $images -Filter '*.png' -File).Count -ne 15) { throw 'Missing GUI style screenshots.' }
    Write-Output $report.Trim()
    Write-Output ('Screenshots: '+$reportRoot)
} finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    $env:APPDATA=$oldAppData; $env:MOUSE_FRONTIER_MOBILE=$oldMobile; $env:MOUSE_FRONTIER_SMOKE=$oldSmoke
    # Delete only this fresh fixture, unlinking source junctions non-recursively.
    $resolved=[IO.Path]::GetFullPath($fixtureRoot)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if ($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('mouse-frontier-gui-style-')) {
        foreach ($name in @('game','assets','sounds')) {
            $link=Join-Path $resolved $name
            if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        }
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
