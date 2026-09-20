param([string]$LoveExecutable='C:\Program Files\LOVE\lovec.exe')
$ErrorActionPreference='Stop'
$repositoryPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testStage=Join-Path $env:TEMP ('mouse-frontier-player-tools-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testStage | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'main.lua'),(Join-Path $PSScriptRoot 'conf.lua') -Destination $testStage
foreach($directory in @('game','assets','sounds')) {
    New-Item -ItemType Junction -Path (Join-Path $testStage $directory) -Target (Join-Path $repositoryPath $directory) | Out-Null
}
$logPath=Join-Path $testStage 'stdout.txt'
$errorPath=Join-Path $testStage 'stderr.txt'
$process=Start-Process -FilePath $LoveExecutable -ArgumentList ('"'+$testStage+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput $logPath -RedirectStandardError $errorPath
if(-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Player tools test timed out.' }
Get-Content -LiteralPath $logPath
Get-Content -LiteralPath $errorPath
if($process.ExitCode -ne 0) { throw 'Player tools test failed.' }
