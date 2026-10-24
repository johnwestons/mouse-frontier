param(
    [ValidateRange(1,360)][int]$TimeoutSeconds=40,
    [string]$LovePath='C:\Program Files\LOVE\lovec.exe',
    [string]$GameRoot,
    [string]$ReportDirectory=(Join-Path $PSScriptRoot '..\.stabilization\lan-smoke'),
    [switch]$Application,
    [switch]$Mobile,
    [switch]$Train,
    [switch]$Objects,
    [switch]$Activities,
    [switch]$Sewing,
    [switch]$FirstAid,
    [switch]$Quests,
    [switch]$Conversations,
    [switch]$QuestDecisions,
    [switch]$Events,
    [switch]$Finale,
    [switch]$Battles,
    [switch]$Roaming,
    [switch]$Hazards,
    [switch]$RoamingCues,
    [switch]$RoamingPressure,
    [switch]$ExpeditionAssistance,
    [switch]$Ambush,
    [switch]$LastStand,
    [switch]$LastStandShooter,
    [switch]$LastStandLifecycle,
    [switch]$LastStandHostRestart,
    [switch]$LastStandPressure,
    [switch]$Range,
    [switch]$Visits,
    [switch]$VisitCaravan,
    [switch]$Sharing,
    [switch]$TravelerHostRestart,
    [switch]$IndependentAreas,
    [switch]$Discovery,
    [ValidateSet('fight','withdraw')][string]$PressureOutcome,
    [ValidateSet('ordinary','expedition')][string]$BattleScene,
    [switch]$BattleLateJoin,
    [switch]$BattleBoss,
    [switch]$BattleHostRestart,
    [switch]$BattleSearch,
    [switch]$BattleActions,
    [switch]$AmbushPressure,
    [switch]$AmbushHostRestart,
    [switch]$Adventure,
    [switch]$AdventureHostRestart,
    [switch]$BossPressure,
    [switch]$BossHostRestart,
    [switch]$DeviceControls,
    [switch]$Travel,
    [ValidateSet('win','loss','retreat')][string]$BattleOutcome,
    [switch]$World,
    [ValidateSet('caravan','badlands','waystation')][string]$PartyScene,
    [ValidateSet('train','stop')][string]$PeopleScene,
    [ValidateSet('stop','caravan')][string]$TradeScene
)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$gameRootPath=$projectRoot
if($GameRoot){$gameRootPath=(Resolve-Path -LiteralPath $GameRoot).Path}
if(-not (Test-Path -LiteralPath (Join-Path $gameRootPath 'game') -PathType Container)){throw 'GameRoot must contain the game directory.'}
$reportRoot=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory)
$runId=[guid]::NewGuid().ToString('N')
$harnessRoot=Join-Path $reportRoot ('run-'+$runId)
$envNames=@('APPDATA','MOUSE_FRONTIER_LAN_SMOKE_ROLE','MOUSE_FRONTIER_LAN_SMOKE_PORT','MOUSE_FRONTIER_LAN_DISCOVERY_PORT','MOUSE_FRONTIER_LAN_SMOKE_ROOT','MOUSE_FRONTIER_MOBILE','MOUSE_FRONTIER_TRADE_SCENE','MOUSE_FRONTIER_PEOPLE_SCENE','MOUSE_FRONTIER_PARTY_SCENE','MOUSE_FRONTIER_BATTLE_SCENE','MOUSE_FRONTIER_BATTLE_LATE_JOIN','MOUSE_FRONTIER_BATTLE_OUTCOME','MOUSE_FRONTIER_BATTLE_BOSS','MOUSE_FRONTIER_BATTLE_HOST_RESTART','MOUSE_FRONTIER_BATTLE_RESUMED','MOUSE_FRONTIER_BATTLE_SEARCH','MOUSE_FRONTIER_PRESSURE_OUTCOME')
$envNames+=@(Get-ChildItem Env: | Where-Object {$_.Name -match '^MOUSE_FRONTIER_SMOKE'} | ForEach-Object {$_.Name})
$envNames=@($envNames | Select-Object -Unique)
$envNames+=@('MOUSE_FRONTIER_LAST_STAND_HOST_RESTART','MOUSE_FRONTIER_LAST_STAND_RESUMED')
$envNames+=@('MOUSE_FRONTIER_AMBUSH_HOST_RESTART','MOUSE_FRONTIER_AMBUSH_RESUMED')
$envNames+=@('MOUSE_FRONTIER_ADVENTURE_HOST_RESTART','MOUSE_FRONTIER_ADVENTURE_RESUMED')
$envNames+=@('MOUSE_FRONTIER_BOSS_HOST_RESTART','MOUSE_FRONTIER_BOSS_RESUMED')
$envNames+=@('MOUSE_FRONTIER_TRAVELER_HOST_RESTART','MOUSE_FRONTIER_TRAVELER_RESUMED')
$envNames+=@('MOUSE_FRONTIER_VISIT_CARAVAN')
$previous=@{}
foreach($name in $envNames){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$children=@(); $exitCode=1; $hostRestarts=0
function Read-SharedLog([string]$Path){
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader=[IO.StreamReader]::new($stream)
    try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
}
try {
    foreach($name in $envNames){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
    if($Mobile){$env:MOUSE_FRONTIER_MOBILE='1'}
    if($TradeScene){$Application=$true; $env:MOUSE_FRONTIER_TRADE_SCENE=$TradeScene}
    if($Train){$Application=$true}
    if($Objects){$Application=$true}
    if($Activities){$Application=$true}
    if($Sewing){$Application=$true}
    if($FirstAid){$Application=$true}
    if($Quests){$Application=$true}
    if($Conversations){$Application=$true}
    if($QuestDecisions){$Application=$true}
    if($Events){$Application=$true}
    if($Finale){$Application=$true}
    if($Battles){$Application=$true}
    if($Roaming){$Application=$true}
    if($Hazards){$Application=$true}
    if($RoamingCues){$Application=$true}
    if($RoamingPressure){$Application=$true}
    if($ExpeditionAssistance){$Application=$true}
    if($PressureOutcome){$RoamingPressure=$true; $Application=$true; $env:MOUSE_FRONTIER_PRESSURE_OUTCOME=$PressureOutcome}
    if($BattleScene){$Battles=$true; $Application=$true; $env:MOUSE_FRONTIER_BATTLE_SCENE=$BattleScene}
    if($BattleActions){$Battles=$true; $Application=$true}
    if($BattleLateJoin){$Battles=$true; $Application=$true; $env:MOUSE_FRONTIER_BATTLE_LATE_JOIN='1'}
    if($BattleBoss){$Battles=$true; $Application=$true; $env:MOUSE_FRONTIER_BATTLE_BOSS='1'}
    if($BattleHostRestart){$Battles=$true; $Application=$true; $env:MOUSE_FRONTIER_BATTLE_HOST_RESTART='1'}
    if($BattleSearch){$Battles=$true; $Application=$true; $env:MOUSE_FRONTIER_BATTLE_SEARCH='1'}
    if($BattleHostRestart -and $BattleLateJoin){throw 'Choose host restart or late admission for this fixture.'}
    if($BattleOutcome){$Battles=$true; $Application=$true; $env:MOUSE_FRONTIER_BATTLE_OUTCOME=$BattleOutcome}
    if($World){$Application=$true}
    if($Ambush){$Application=$true}
    if($AmbushPressure){$Application=$true}
    if($AmbushHostRestart){$AmbushPressure=$true; $Application=$true; $env:MOUSE_FRONTIER_AMBUSH_HOST_RESTART='1'}
    if($Adventure){$Application=$true}
    if($AdventureHostRestart){$Adventure=$true; $Application=$true; $env:MOUSE_FRONTIER_ADVENTURE_HOST_RESTART='1'}
    if($BossPressure){$Application=$true}
    if($BossHostRestart){$BossPressure=$true; $Application=$true; $env:MOUSE_FRONTIER_BOSS_HOST_RESTART='1'}
    if($DeviceControls){$Application=$true}
    if($Travel){$Application=$true}
    if($LastStand){$Application=$true}
    if($LastStandShooter){$Application=$true}
    if($LastStandLifecycle){$Application=$true}
    if($LastStandPressure){$Application=$true}
    if($Range){$Application=$true}
    if($VisitCaravan){$Visits=$true; $env:MOUSE_FRONTIER_VISIT_CARAVAN='1'}
    if($Visits){$Application=$true}
    if($TravelerHostRestart){$Sharing=$true; $env:MOUSE_FRONTIER_TRAVELER_HOST_RESTART='1'}
    if($Sharing){$Application=$true}
    if($IndependentAreas){$Application=$true}
    if($LastStandHostRestart){$LastStandLifecycle=$true; $Application=$true; $env:MOUSE_FRONTIER_LAST_STAND_HOST_RESTART='1'}
    if($LastStandHostRestart -and $BattleHostRestart){throw 'Choose Last Stand or battle host restart for this fixture.'}
    if($AmbushHostRestart -and ($LastStandHostRestart -or $BattleHostRestart)){throw 'Choose one host restart fixture per run.'}
    if($AdventureHostRestart -and ($LastStandHostRestart -or $BattleHostRestart -or $AmbushHostRestart)){throw 'Choose one host restart fixture per run.'}
    if($BossHostRestart -and ($LastStandHostRestart -or $BattleHostRestart -or $AmbushHostRestart -or $AdventureHostRestart)){throw 'Choose one host restart fixture per run.'}
    if($Discovery){$Application=$true}
    if($PartyScene){$Application=$true; $env:MOUSE_FRONTIER_PARTY_SCENE=$PartyScene}
    if($PeopleScene){$Application=$true; $env:MOUSE_FRONTIER_PEOPLE_SCENE=$PeopleScene}
    $otherFixtures=@($Train,$Objects,$TradeScene,$PeopleScene,$Activities,$Sewing,$FirstAid,$Quests,$Conversations,$QuestDecisions,$Events,$Finale,$Battles,$World,$PartyScene,$Roaming,$Hazards,$RoamingCues,$RoamingPressure,$ExpeditionAssistance,$Ambush,$AmbushPressure,$Adventure,$LastStand,$LastStandShooter,$LastStandLifecycle,$LastStandPressure,$Range,$Discovery) | Where-Object {[bool]$_}
    if($BossPressure -and $otherFixtures){throw 'Choose one application fixture per run.'}
    if($DeviceControls -and ($otherFixtures -or $BossPressure)){throw 'Choose one application fixture per run.'}
    if($Travel -and ($otherFixtures -or $BossPressure -or $DeviceControls)){throw 'Choose one application fixture per run.'}
    if((($Visits -or $Sharing -or $IndependentAreas) -and ($otherFixtures -or $BossPressure -or $DeviceControls -or $Travel)) -or ([int][bool]$Visits+[int][bool]$Sharing+[int][bool]$IndependentAreas -gt 1)){throw 'Choose one application fixture per run.'}
    if(([int][bool]$Train+[int][bool]$Objects+[int][bool]$TradeScene+[int][bool]$PeopleScene+[int][bool]$Activities+[int][bool]$Sewing+[int][bool]$FirstAid+[int][bool]$Quests+[int][bool]$Conversations+[int][bool]$QuestDecisions+[int][bool]$Events+[int][bool]$Finale+[int][bool]$Battles+[int][bool]$World+[int][bool]$PartyScene+[int][bool]$Roaming+[int][bool]$Hazards+[int][bool]$RoamingCues+[int][bool]$RoamingPressure+[int][bool]$ExpeditionAssistance+[int][bool]$Ambush+[int][bool]$AmbushPressure+[int][bool]$Adventure+[int][bool]$LastStand+[int][bool]$LastStandShooter+[int][bool]$LastStandLifecycle+[int][bool]$LastStandPressure+[int][bool]$Range+[int][bool]$Discovery) -gt 1){throw 'Choose one application fixture per run.'}
    if(-not (Test-Path -LiteralPath $LovePath -PathType Leaf)){throw 'LÖVE runtime is missing.'}
    New-Item -ItemType Directory -Force -Path $harnessRoot | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $harnessRoot 'game') -Target (Join-Path $gameRootPath 'game') | Out-Null
    $fixtureName=if($Application){'local-play-smoke'}else{'lan-smoke'}
    if($TradeScene){$fixtureName='guest-trade-smoke'}
    if($Train){$fixtureName='guest-train-smoke'}
    if($Objects){$fixtureName='guest-objects-smoke'}
    if($PeopleScene){$fixtureName='guest-people-smoke'}
    if($Activities){$fixtureName='guest-activities-smoke'}
    if($Sewing){$fixtureName='guest-sewing-smoke'}
    if($FirstAid){$fixtureName='guest-first-aid-smoke'}
    if($Quests){$fixtureName='guest-quests-smoke'}
    if($Conversations){$fixtureName='guest-conversations-smoke'}
    if($QuestDecisions){$fixtureName='guest-quest-decisions-smoke'}
    if($Events){$fixtureName='guest-events-smoke'}
    if($Finale){$fixtureName='guest-finale-smoke'}
    if($Battles){$fixtureName='guest-battles-smoke'}
    if($BattleActions){$fixtureName='guest-battle-actions-smoke'}
    if($Roaming){$fixtureName='guest-roaming-smoke'}
    if($Hazards){$fixtureName='guest-hazards-smoke'}
    if($RoamingCues){$fixtureName='guest-roaming-cues-smoke'}
    if($RoamingPressure){$fixtureName='guest-roaming-pressure-smoke'}
    if($ExpeditionAssistance){$fixtureName='guest-expedition-assistance-smoke'}
    if($Ambush){$fixtureName='guest-ambush-smoke'}
    if($AmbushPressure){$fixtureName='guest-ambush-pressure-smoke'}
    if($Adventure){$fixtureName='guest-adventure-smoke'}
    if($BossPressure){$fixtureName='guest-boss-pressure-smoke'}
    if($DeviceControls){$fixtureName='guest-device-controls-smoke'}
    if($Travel){$fixtureName='guest-travel-smoke'}
    if($LastStand){$fixtureName='guest-last-stand-smoke'}
    if($LastStandShooter){$fixtureName='guest-last-stand-shooter-smoke'}
    if($LastStandLifecycle){$fixtureName='guest-last-stand-lifecycle-smoke'}
    if($LastStandPressure){$fixtureName='guest-last-stand-pressure-smoke'}
    if($Range){$fixtureName='guest-range-smoke'}
    if($Visits){$fixtureName='guest-visits-smoke'}
    if($Sharing){$fixtureName='guest-sharing-smoke'}
    if($IndependentAreas){$fixtureName='guest-independent-area-smoke'}
    if($Discovery){$fixtureName='guest-discovery-smoke'}
    if($World){$fixtureName='guest-world-smoke'}
    if($PartyScene){$fixtureName='guest-party-smoke'}
    if($Application){
        foreach($name in @('assets','sounds')){
            if(-not (Test-Path -LiteralPath (Join-Path $gameRootPath $name) -PathType Container)){throw ('GameRoot is missing '+$name+'.')}
            New-Item -ItemType Junction -Path (Join-Path $harnessRoot $name) -Target (Join-Path $gameRootPath $name) | Out-Null
        }
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot ($fixtureName+'\main.lua')) -Destination $harnessRoot
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot ($fixtureName+'\conf.lua')) -Destination $harnessRoot
    if($BattleActions){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'guest-battle-actions-smoke\checkpoint.lua') -Destination (Join-Path $harnessRoot 'checkpoint.lua')}
    if($AmbushPressure){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'guest-ambush-pressure-smoke\checkpoint.lua') -Destination (Join-Path $harnessRoot 'checkpoint.lua')}
    if($BossPressure){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'guest-boss-pressure-smoke\boss_fixture.lua') -Destination (Join-Path $harnessRoot 'boss_fixture.lua')}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tests\lua\coop_fixtures.lua') -Destination (Join-Path $harnessRoot 'fixture.lua')
    $probe=[Net.Sockets.UdpClient]::new(0)
    try{$port=$probe.Client.LocalEndPoint.Port}finally{$probe.Dispose()}
    $env:MOUSE_FRONTIER_LAN_SMOKE_PORT=[string]$port
    if($Discovery){
        $discoveryProbe=[Net.Sockets.UdpClient]::new(0)
        try{$env:MOUSE_FRONTIER_LAN_DISCOVERY_PORT=[string]$discoveryProbe.Client.LocalEndPoint.Port}finally{$discoveryProbe.Dispose()}
    }
    $env:MOUSE_FRONTIER_LAN_SMOKE_ROOT=$harnessRoot
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    foreach($role in @('host','guest')){
        $env:APPDATA=Join-Path $harnessRoot ($role+'-appdata')
        New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
        $env:MOUSE_FRONTIER_LAN_SMOKE_ROLE=$role
        $outPath=Join-Path $harnessRoot ($role+'.log'); $errPath=Join-Path $harnessRoot ($role+'.err')
        $child=Start-Process -FilePath $LovePath -ArgumentList ('"'+$harnessRoot+'"') -WorkingDirectory $gameRootPath `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $outPath -RedirectStandardError $errPath
        $null=$child.Handle
        $children+=@{process=$child;role=$role;output=$outPath;error=$errPath;restartExpected=($role -eq 'host' -and ($BattleHostRestart -or $LastStandHostRestart -or $AmbushHostRestart -or $AdventureHostRestart -or $BossHostRestart -or $TravelerHostRestart));restarted=$false}
        if($role -eq 'host'){
            # No assumed startup delay: launch the guest only after the host's
            # real ENet socket and durable campaign preflight are ready.
            while([DateTime]::UtcNow -lt $deadline -and -not $child.HasExited){
                if((Test-Path -LiteralPath $outPath) -and (Read-SharedLog $outPath).Contains('LAN_SMOKE_LISTENING')){break}
                Start-Sleep -Milliseconds 50; $child.Refresh()
            }
            if($child.HasExited -or [DateTime]::UtcNow -ge $deadline){throw 'LAN host failed to start.'}
        }
    }
    while([DateTime]::UtcNow -lt $deadline){
        foreach($child in @($children)){
            if($child.restartExpected -and -not $child.restarted -and $child.process.HasExited){
                $child.process.WaitForExit()
                $report=[IO.File]::ReadAllText($child.output); $errors=[IO.File]::ReadAllText($child.error)
                $restartMarker=if($TravelerHostRestart){'LAN_SMOKE_RESTART role=host travelerSaved=true'}elseif($LastStandHostRestart){'LAN_SMOKE_RESTART role=host lastStandSaved=true'}elseif($AmbushHostRestart){'LAN_SMOKE_RESTART role=host ambushSaved=true'}elseif($AdventureHostRestart){'LAN_SMOKE_RESTART role=host adventureSaved=true'}elseif($BossHostRestart){'LAN_SMOKE_RESTART role=host bossSaved=true'}else{'LAN_SMOKE_RESTART role=host battleSaved=true'}
                if($child.process.ExitCode -ne 42 -or $report -notmatch $restartMarker -or $errors.Length -gt 0){throw ('LAN host restart checkpoint failed: '+$report+$errors)}
                $child.restarted=$true; $hostRestarts++
                $env:APPDATA=Join-Path $harnessRoot 'host-appdata'; $env:MOUSE_FRONTIER_LAN_SMOKE_ROLE='host'
                if($TravelerHostRestart){$env:MOUSE_FRONTIER_TRAVELER_RESUMED='1'}elseif($LastStandHostRestart){$env:MOUSE_FRONTIER_LAST_STAND_RESUMED='1'}elseif($AmbushHostRestart){$env:MOUSE_FRONTIER_AMBUSH_RESUMED='1'}elseif($AdventureHostRestart){$env:MOUSE_FRONTIER_ADVENTURE_RESUMED='1'}elseif($BossHostRestart){$env:MOUSE_FRONTIER_BOSS_RESUMED='1'}else{$env:MOUSE_FRONTIER_BATTLE_RESUMED='1'}
                $outPath=Join-Path $harnessRoot 'host-resumed.log'; $errPath=Join-Path $harnessRoot 'host-resumed.err'
                $resumed=Start-Process -FilePath $LovePath -ArgumentList ('"'+$harnessRoot+'"') -WorkingDirectory $gameRootPath `
                    -PassThru -WindowStyle Hidden -RedirectStandardOutput $outPath -RedirectStandardError $errPath
                $null=$resumed.Handle
                $children+=@{process=$resumed;role='host';output=$outPath;error=$errPath;restartExpected=$false;restarted=$false}
                while([DateTime]::UtcNow -lt $deadline -and -not $resumed.HasExited){
                    if((Test-Path -LiteralPath $outPath) -and (Read-SharedLog $outPath).Contains('LAN_SMOKE_LISTENING')){break}
                    Start-Sleep -Milliseconds 50; $resumed.Refresh()
                }
                if($resumed.HasExited -or [DateTime]::UtcNow -ge $deadline){throw 'LAN resumed host failed to start.'}
                Set-Content -LiteralPath (Join-Path $harnessRoot 'host-resumed.ready') -Value 'listening'
            }
            if(-not $child.restarted -and $child.process.HasExited){
                $child.process.WaitForExit()
                if($child.process.ExitCode -ne 0){throw ('LAN '+$child.role+' failed: '+(Read-SharedLog $child.output)+(Read-SharedLog $child.error))}
            }
        }
        $running=@($children | Where-Object {-not $_.process.HasExited})
        if($running.Count -eq 0){break}
        Start-Sleep -Milliseconds 100
        foreach($child in $children){$child.process.Refresh()}
    }
    foreach($child in $children){
        if(-not $child.process.HasExited){throw ('LAN '+$child.role+' timed out.')}
        $child.process.WaitForExit()
        $report=[IO.File]::ReadAllText($child.output); $errors=[IO.File]::ReadAllText($child.error)
        if($child.restarted){continue}
        if($child.process.ExitCode -ne 0 -or $report -notmatch ('LAN_SMOKE_OK role='+$child.role) -or $errors.Length -gt 0){
            throw ('LAN '+$child.role+' failed: '+$report+$errors)
        }
    }
    if(($BattleHostRestart -or $LastStandHostRestart -or $AmbushHostRestart -or $AdventureHostRestart -or $BossHostRestart -or $TravelerHostRestart) -and $hostRestarts -ne 1){throw 'LAN host did not complete exactly one disk restart.'}
    $exitCode=0
} catch {
    Write-Output ('LAN_SMOKE_ERROR '+$_.Exception.Message)
} finally {
    foreach($child in $children){
        if(-not $child.process.HasExited){Stop-Process -Id $child.process.Id -Force -ErrorAction SilentlyContinue}
        $child.process.WaitForExit(); $child.process.Dispose()
    }
    foreach($name in $envNames){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
    New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
    $summary='LAN_SMOKE exit='+$exitCode+' run='+$runId+' logs="'+$harnessRoot+'" scope=two-local-processes application='+[bool]$Application+' touchSimulation='+[bool]$Mobile+' tradeScene='+$TradeScene+' trainFixture='+[bool]$Train+' objectFixture='+[bool]$Objects+' peopleScene='+$PeopleScene+' activityFixture='+[bool]$Activities+' sewingFixture='+[bool]$Sewing+' firstAidFixture='+[bool]$FirstAid+' questFixture='+[bool]$Quests+' worldFixture='+[bool]$World+' partyScene='+$PartyScene
    $summary+=' conversationFixture='+[bool]$Conversations+' questDecisionsFixture='+[bool]$QuestDecisions+' eventFixture='+[bool]$Events
    $summary+=' finaleFixture='+[bool]$Finale
    $summary+=' battleFixture='+[bool]$Battles+' battleScene='+$BattleScene
    $summary+=' battleSearch='+[bool]$BattleSearch
    $summary+=' battleLateJoin='+[bool]$BattleLateJoin
    $summary+=' battleOutcome='+$BattleOutcome
    $summary+=' battleBoss='+[bool]$BattleBoss+' hostRestarts='+$hostRestarts+' hostProcessStarts='+(1+$hostRestarts)
    $summary+=' battleActionsFixture='+[bool]$BattleActions
    $summary+=' roamingFixture='+[bool]$Roaming
    $summary+=' hazardFixture='+[bool]$Hazards
    $summary+=' roamingCuesFixture='+[bool]$RoamingCues
    $summary+=' roamingPressureFixture='+[bool]$RoamingPressure
    $summary+=' pressureOutcome='+$PressureOutcome
    $summary+=' expeditionAssistanceFixture='+[bool]$ExpeditionAssistance
    $summary+=' ambushFixture='+[bool]$Ambush
    $summary+=' ambushPressureFixture='+[bool]$AmbushPressure+' ambushHostRestart='+[bool]$AmbushHostRestart
    $summary+=' adventureFixture='+[bool]$Adventure+' adventureHostRestart='+[bool]$AdventureHostRestart
    $summary+=' bossPressureFixture='+[bool]$BossPressure+' bossHostRestart='+[bool]$BossHostRestart
    $summary+=' deviceControlsFixture='+[bool]$DeviceControls
    $summary+=' travelFixture='+[bool]$Travel
    $summary+=' gameRoot="'+$gameRootPath+'"'
    $summary+=' lastStandFixture='+[bool]$LastStand
    $summary+=' lastStandShooterFixture='+[bool]$LastStandShooter
    $summary+=' lastStandLifecycleFixture='+[bool]$LastStandLifecycle+' lastStandHostRestart='+[bool]$LastStandHostRestart
    $summary+=' lastStandPressureFixture='+[bool]$LastStandPressure
    $summary+=' rangeFixture='+[bool]$Range
    $summary+=' discoveryFixture='+[bool]$Discovery
    $summary+=' visitsFixture='+[bool]$Visits+' visitCaravan='+[bool]$VisitCaravan
    $summary+=' sharingFixture='+[bool]$Sharing+' travelerHostRestart='+[bool]$TravelerHostRestart
    $summary+=' independentAreasFixture='+[bool]$IndependentAreas
    Set-Content -LiteralPath (Join-Path $reportRoot 'summary.rpt') -Value $summary
    Write-Output $summary
}
exit $exitCode
