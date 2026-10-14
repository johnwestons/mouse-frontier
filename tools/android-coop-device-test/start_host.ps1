param(
    [string]$GameRoot='output/windows/coop-candidate/game-stage',
    [string]$LovePath='output/windows/coop-candidate/portable/lovec.exe',
    [string]$ResumeRoot
)
$ErrorActionPreference='Stop'
$workspace=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$stage=(Resolve-Path -LiteralPath (Join-Path $workspace $GameRoot)).Path
$runtime=(Resolve-Path -LiteralPath (Join-Path $workspace $LovePath)).Path
if($ResumeRoot){
    $run=(Resolve-Path -LiteralPath $ResumeRoot).Path
    $allowed=[IO.Path]::GetFullPath((Join-Path $workspace '.stabilization/android-coop-device'))+[IO.Path]::DirectorySeparatorChar
    if(-not $run.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'ResumeRoot must be an existing isolated Android co-op test run.'}
    if(-not (Test-Path -LiteralPath (Join-Path $run 'ready.txt') -PathType Leaf)){throw 'ResumeRoot has no completed desktop host startup.'}
}else{
    $run=Join-Path $workspace ('.stabilization/android-coop-device/run-'+[guid]::NewGuid().ToString('N'))
}
$fixture=Join-Path $run 'host-app'
$appdata=Join-Path $run 'host-appdata'
if($ResumeRoot){
    foreach($name in @('game','assets','sounds')){
        $link=Get-Item -LiteralPath (Join-Path $fixture $name)
        $expected=[IO.Path]::GetFullPath((Join-Path $stage $name))
        $target=@($link.Target)[0]
        if($link.LinkType -ne 'Junction' -or -not $target -or -not [IO.Path]::GetFullPath($target).Equals($expected,[StringComparison]::OrdinalIgnoreCase)){throw "ResumeRoot immutable $name target differs from GameRoot."}
    }
    $save=Join-Path $appdata 'LOVE/mouse-frontier-android-device-host/saves/slot1.lua'
    if(-not (Test-Path -LiteralPath $save -PathType Leaf)){throw 'ResumeRoot isolated saved slot1 is missing.'}
}else{
    New-Item -ItemType Directory -Path $fixture,$appdata -Force | Out-Null
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'main.lua') -Destination $fixture
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'conf.lua') -Destination $fixture
foreach($name in $(if($ResumeRoot){@()}else{@('game','assets','sounds')})){
    $target=Join-Path $stage $name
    if(-not (Test-Path -LiteralPath $target -PathType Container)){throw "Missing packaged folder $name"}
    New-Item -ItemType Junction -Path (Join-Path $fixture $name) -Target $target | Out-Null
}
$names=@('APPDATA','MOUSE_FRONTIER_DEVICE_TEST_ROOT','MOUSE_FRONTIER_DEVICE_TEST_RESUME','MOUSE_FRONTIER_MOBILE')
$names+=@(Get-ChildItem Env: | Where-Object Name -Match '^MOUSE_FRONTIER_SMOKE' | ForEach-Object Name)
$prior=@{}
foreach($name in $names){$prior[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
try{
    $env:APPDATA=$appdata;$env:MOUSE_FRONTIER_DEVICE_TEST_ROOT=$run
    $env:MOUSE_FRONTIER_DEVICE_TEST_RESUME=if($ResumeRoot){'1'}else{'0'}
    Remove-Item Env:MOUSE_FRONTIER_MOBILE -ErrorAction SilentlyContinue
    foreach($name in $names){if($name -match '^MOUSE_FRONTIER_SMOKE'){Remove-Item -LiteralPath ('Env:'+ $name) -ErrorAction SilentlyContinue}}
    $logPrefix=if($ResumeRoot){'host-resume-'+[guid]::NewGuid().ToString('N')}else{'host'}
    $process=Start-Process -FilePath $runtime -ArgumentList @('"'+$fixture+'"') -WorkingDirectory $stage -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $run ($logPrefix+'.log')) -RedirectStandardError (Join-Path $run ($logPrefix+'.error.log'))
    [pscustomobject]@{processId=$process.Id;root=$run;gameRoot=$stage;lovePath=$runtime;resume=[bool]$ResumeRoot;log=(Join-Path $run ($logPrefix+'.log'));status=(Join-Path $run 'status.json');actions=(Join-Path $run 'action.txt')} | ConvertTo-Json
}finally{
    foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$prior[$name],'Process')}
}
