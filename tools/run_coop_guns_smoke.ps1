param([int]$TimeoutSeconds=60,[string]$ReportDirectory='.stabilization/coop-guns-native',[switch]$LastStand)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$reportRoot=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory)
$runId=[guid]::NewGuid().ToString('N')
$harnessRoot=Join-Path ([IO.Path]::GetTempPath()) ('mouse-frontier-coop-guns-smoke-'+$runId)
$isolatedAppData=Join-Path $harnessRoot 'appdata'
$loveExe=if($env:LOVE_EXE){$env:LOVE_EXE}else{'C:\Program Files\LOVE\lovec.exe'}
$oldAppData=$env:APPDATA
$process=$null
$fixtureName=if($LastStand){'coop-last-stand-state-smoke'}else{'coop-guns-smoke'}
$resultTag=if($LastStand){'COOP_LAST_STAND_STATE'}else{'COOP_GUNS'}
$expectedImages=if($LastStand){@('01-native-shared-targets.png','02-native-restored-cover.png','03-native-host-authority-cover.png')}else{@('01-native-host-cover.png','02-native-host-full-cover.png')}
try {
    if(-not(Test-Path -LiteralPath $loveExe -PathType Leaf)){throw 'Set LOVE_EXE to the installed lovec.exe.'}
    New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $harnessRoot,$isolatedAppData | Out-Null
    foreach($name in @('game','assets','sounds')){
        New-Item -ItemType Junction -Path (Join-Path $harnessRoot $name) -Target (Join-Path $projectRoot $name) | Out-Null
    }
    foreach($name in @('main.lua','conf.lua')){
        Copy-Item -LiteralPath (Join-Path (Join-Path $PSScriptRoot $fixtureName) $name) -Destination (Join-Path $harnessRoot $name)
    }
    $env:APPDATA=$isolatedAppData
    $process=Start-Process -FilePath $loveExe -ArgumentList ('"'+$harnessRoot+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $reportRoot 'process.log') -RedirectStandardError (Join-Path $reportRoot 'process.err')
    $null=$process.Handle
    if(-not $process.WaitForExit($TimeoutSeconds*1000)){throw ('Native '+$fixtureName+' validation timed out.')}
    $process.WaitForExit()
    $report=[IO.File]::ReadAllText((Join-Path $reportRoot 'process.log'))
    $errors=[IO.File]::ReadAllText((Join-Path $reportRoot 'process.err'))
    if($process.ExitCode -ne 0 -or $report -notmatch ($resultTag+'_OK')){throw ($report+$errors)}
    $screenshots=Join-Path (Join-Path $isolatedAppData 'LOVE') ('mouse-frontier-'+$fixtureName)
    foreach($name in $expectedImages){
        $imagePath=Join-Path $screenshots $name
        if(-not(Test-Path -LiteralPath $imagePath -PathType Leaf)){throw ('Native screenshot missing: '+$name)}
        Copy-Item -LiteralPath $imagePath -Destination (Join-Path $reportRoot $name)
    }
    [IO.File]::WriteAllText((Join-Path $reportRoot 'summary.rpt'),($resultTag+'_NATIVE result=passed run='+$runId+' exit='+$process.ExitCode+' appdata="'+$isolatedAppData+'"'+[Environment]::NewLine+$report),[Text.UTF8Encoding]::new($false))
    Write-Output $report.Trim()
    Write-Output ('NATIVE_RUN='+$runId)
} finally {
    if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
    $env:APPDATA=$oldAppData
}
