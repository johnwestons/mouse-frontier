param(
    [ValidateRange(10,180)][int]$TimeoutSeconds=75,
    [string]$LovePath='C:\Program Files\LOVE\lovec.exe',
    [string]$GameRoot,
    [string]$ReportDirectory=(Join-Path $PSScriptRoot '..\.stabilization\coop-companion-management-native')
)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$gameRootPath=if($GameRoot){(Resolve-Path -LiteralPath $GameRoot).Path}else{$projectRoot}
$reportRoot=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory)
$runId=[guid]::NewGuid().ToString('N')
$runRoot=Join-Path $reportRoot ('run-'+$runId)
$harnessRoot=Join-Path $runRoot 'fixture'
$isolatedAppData=Join-Path $runRoot 'appdata'
$process=$null
$names=@('APPDATA','MOUSE_FRONTIER_MANAGEMENT_PORT','MOUSE_FRONTIER_MANAGEMENT_DISCOVERY_PORT')
$previous=@{}
foreach($name in $names){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
function Get-UnusedUdpPort {
    $socket=[Net.Sockets.UdpClient]::new(0)
    try{return ([Net.IPEndPoint]$socket.Client.LocalEndPoint).Port}finally{$socket.Dispose()}
}
try {
    if(-not(Test-Path -LiteralPath $LovePath -PathType Leaf)){throw 'LOVE runtime missing; pass -LovePath.'}
    if(-not(Test-Path -LiteralPath (Join-Path $gameRootPath 'game') -PathType Container)){throw 'GameRoot must contain game.'}
    New-Item -ItemType Directory -Force -Path $harnessRoot,$isolatedAppData | Out-Null
    foreach($name in @('game','assets')){
        New-Item -ItemType Junction -Path (Join-Path $harnessRoot $name) -Target (Join-Path $gameRootPath $name) | Out-Null
    }
    New-Item -ItemType Junction -Path (Join-Path $harnessRoot 'tools') -Target (Join-Path $projectRoot 'tools') | Out-Null
    foreach($name in @('main.lua','conf.lua','scenario.lua')){
        Copy-Item -LiteralPath (Join-Path (Join-Path $PSScriptRoot 'coop-companion-management-smoke') $name) -Destination (Join-Path $harnessRoot $name)
    }
    $gamePort=Get-UnusedUdpPort
    do {$discoveryPort=Get-UnusedUdpPort}while($discoveryPort -eq $gamePort)
    $env:APPDATA=$isolatedAppData
    $env:MOUSE_FRONTIER_MANAGEMENT_PORT=[string]$gamePort
    $env:MOUSE_FRONTIER_MANAGEMENT_DISCOVERY_PORT=[string]$discoveryPort
    $stdout=Join-Path $runRoot 'process.log';$stderr=Join-Path $runRoot 'process.err'
    $process=Start-Process -FilePath $LovePath -ArgumentList ('"'+$harnessRoot+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $null=$process.Handle
    if(-not $process.WaitForExit($TimeoutSeconds*1000)){throw 'Companion management native acceptance timed out.'}
    $process.WaitForExit()
    $log=[IO.File]::ReadAllText($stdout);$errors=[IO.File]::ReadAllText($stderr)
    if($process.ExitCode -ne 0 -or $log -notmatch 'COOP_COMPANION_MANAGEMENT_OK .*actualENet=true .*nativeDeferred=1'){
        throw ('Companion management native acceptance failed.'+[Environment]::NewLine+$log+$errors)
    }
    $captureRoot=Join-Path (Join-Path $isolatedAppData 'LOVE') 'mouse-frontier-coop-companion-management-smoke'
    $expected=@('01-first-approval.png','02-connected-host.png','03-disconnect-confirmation.png','04-checkpoint-pending.png',
        '05-kicked-client.png','06-traveler-selection.png','07-traveler-confirmation.png','08-rejoined-client.png','result.rpt')
    foreach($name in $expected){
        $path=Join-Path $captureRoot $name
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('Missing native result artifact: '+$name)}
        Copy-Item -LiteralPath $path -Destination (Join-Path $runRoot $name)
    }
    [IO.File]::WriteAllText((Join-Path $runRoot 'summary.rpt'),('COMPANION_MANAGEMENT_NATIVE result=passed run='+$runId+' exit=0 gamePort='+$gamePort+' discoveryPort='+$discoveryPort+[Environment]::NewLine+$log),[Text.UTF8Encoding]::new($false))
    Write-Output $log.Trim();Write-Output ('NATIVE_RUN='+$runId);Write-Output ('NATIVE_REPORT='+$runRoot)
} finally {
    if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
    foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
}
