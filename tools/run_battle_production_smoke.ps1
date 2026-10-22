param([int]$TimeoutSeconds=90,[switch]$Mobile,[switch]$Profile,[string]$GameRoot)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runtimeRoot=if($GameRoot){(Resolve-Path -LiteralPath $GameRoot).Path}else{$projectRoot}
$runId=[guid]::NewGuid().ToString('N')
$runRoot=Join-Path $projectRoot ('output\battle-terrain\production-run-'+$runId)
$oldAppData=$env:APPDATA
$oldMobile=$env:MOUSE_FRONTIER_MOBILE
$oldProfile=$env:MOUSE_FRONTIER_BATTLE_PROFILE
$process=$null
try {
    New-Item -ItemType Directory -Path $runRoot | Out-Null
    foreach ($name in @('game','assets','sounds')) {
        New-Item -ItemType Junction -Path (Join-Path $runRoot $name) -Target (Join-Path $runtimeRoot $name) | Out-Null
    }
    foreach ($name in @('main.lua','conf.lua','profile.lua')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('battle-production-smoke\'+$name)) -Destination (Join-Path $runRoot $name) }
    $env:APPDATA=Join-Path $runRoot 'appdata'
    New-Item -ItemType Directory -Path $env:APPDATA | Out-Null
    if ($Mobile) { $env:MOUSE_FRONTIER_MOBILE='1' } else { Remove-Item Env:MOUSE_FRONTIER_MOBILE -ErrorAction SilentlyContinue }
    if ($Profile) { $env:MOUSE_FRONTIER_BATTLE_PROFILE='1' } else { Remove-Item Env:MOUSE_FRONTIER_BATTLE_PROFILE -ErrorAction SilentlyContinue }
    $log=Join-Path $runRoot 'result.txt'
    $process=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' -ArgumentList ('"'+$runRoot+'"') -PassThru -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError (Join-Path $runRoot 'errors.txt')
    if (-not $process.WaitForExit($TimeoutSeconds*1000)) { throw 'Production battle smoke timed out' }
    $process.WaitForExit()
    $result=Get-Content -LiteralPath $log -Raw
    Write-Output $result
    if ($process.ExitCode -ne 0 -or $result -notmatch 'BATTLE_PRODUCTION_SMOKE_OK') { throw 'Production battle smoke failed' }
    $captures=Join-Path $env:APPDATA 'LOVE\mouse-frontier-battle-production-smoke'
    Get-ChildItem -LiteralPath $captures -Filter '*.png' | ForEach-Object {
        $prefix=if ($Mobile) {'mobile-'} else {''}
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $projectRoot ('output\battle-terrain\'+$prefix+$_.Name))
    }
    Get-ChildItem -LiteralPath $captures -Filter '*.json' | ForEach-Object {
        $prefix=if ($Mobile) {'mobile-'} else {''}
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $projectRoot ('output\battle-terrain\'+$prefix+$_.Name))
    }
    Write-Output ('BATTLE_PRODUCTION_REPORT='+$runRoot)
} finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    foreach ($name in @('game','assets','sounds')) {
        $link=Join-Path $runRoot $name
        if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
    }
    if ($null -eq $oldAppData) { Remove-Item Env:APPDATA -ErrorAction SilentlyContinue } else { $env:APPDATA=$oldAppData }
    if ($null -eq $oldMobile) { Remove-Item Env:MOUSE_FRONTIER_MOBILE -ErrorAction SilentlyContinue } else { $env:MOUSE_FRONTIER_MOBILE=$oldMobile }
    if ($null -eq $oldProfile) { Remove-Item Env:MOUSE_FRONTIER_BATTLE_PROFILE -ErrorAction SilentlyContinue } else { $env:MOUSE_FRONTIER_BATTLE_PROFILE=$oldProfile }
}
