local SmokeController = require("game.smoke_controller")
local SmokeReport = require("game.smoke_report")

local function required(context,name,expected)
    local value=context[name]
    assert(value~=nil,"smoke playthrough requires "..name)
    if expected then assert(type(value)==expected,"smoke playthrough "..name.." must be a "..expected) end
    return value
end

local function install(context)
    assert(type(context)=="table","smoke playthrough requires an explicit context")
    if os.getenv("MOUSE_FRONTIER_SMOKE")~="1" then return false end
    local game=required(context,"runtime","table")
    local ui=required(context,"ui","table")
    local characters=required(context,"characters","table")
    local maintenanceSession=required(context,"maintenanceSession","table")
    local session=required(context,"session","table")
    local screens=required(context,"screens","table")
    local car=required(context,"car","table")
    local CURRENT_SAVE_VERSION=required(context,"currentSaveVersion","number")
    local SaveSchema=required(context,"saveSchema","table")
    local Catalog=required(context,"catalog","table")
    local Assets=required(context,"assets","table")
    local Save=required(context,"save","table")
    local Maintenance=required(context,"maintenance","table")
    local Events=required(context,"events","table")
    local BattleRules=required(context,"battleRules","table")
    local FirstAid=required(context,"firstAid","table")
    local presentationRuntime=required(context,"presentationRuntime","table")
    local startupRuntime=required(context,"startupRuntime","table")
    local persistenceRuntime=required(context,"persistenceRuntime","table")
    local audioRuntime=required(context,"audioRuntime","table")
    local screenFlow=required(context,"screenFlow","table")
    local contentRegistry=required(context,"contentRegistry","table")
    local viewComposition=required(context,"viewComposition","table")
    local adventureComposition=required(context,"adventureComposition","table")
    local platformComposition=required(context,"platformComposition","table")
    local inputComposition=required(context,"inputComposition","table")
    local worldSessionComposition=required(context,"worldSessionComposition","table")
    local startupComposition=required(context,"startupComposition","table")
    local serviceRegistry=required(context,"serviceRegistry","table")
    local smokeComposition=required(context,"smokeComposition","table")
    local applicationComposition=required(context,"applicationComposition","table")
    local getMobileControls=required(context,"getMobileControls","function")
    local createIntro=required(context,"createIntro","function")
    local newSave=required(context,"newSave","function")
    local enterGame=required(context,"enterGame","function")
    local ensureStopLayout=required(context,"ensureStopLayout","function")
    local setupNPC=required(context,"setupNPC","function")
    local beginEncounter=required(context,"beginEncounter","function")
    local consumeSelected=required(context,"consumeSelected","function")
    local beginRandomEvent=required(context,"beginRandomEvent","function")
    local resolveEventChoice=required(context,"resolveEventChoice","function")
    local advanceBattleTurn=required(context,"advanceBattleTurn","function")
    local battleAttack=required(context,"battleAttack","function")
    local resolveBattleAttack=required(context,"resolveBattleAttack","function")
    local balanceAudit=required(context,"balanceAudit","function")
    local combatBalanceAudit=required(context,"combatBalanceAudit","function")
    local battleGridAudit=required(context,"battleGridAudit","function")
    local playerBalanceAudit=required(context,"playerBalanceAudit","function")
    local eventBalanceAudit=required(context,"eventBalanceAudit","function")
    local upgradeBalanceAudit=required(context,"upgradeBalanceAudit","function")
    local lootBalanceAudit=required(context,"lootBalanceAudit","function")
    local questBalanceAudit=required(context,"questBalanceAudit","function")
    local audioAudit=required(context,"audioAudit","function")
    local finaleAudit=required(context,"finaleAudit","function")
    local helpBalanceAudit=required(context,"helpBalanceAudit","function")
    local trainPresentationAudit=required(context,"trainPresentationAudit","function")
    local writeSave=persistenceRuntime.schedule
-- `MOUSE_FRONTIER_SMOKE=1` runs a deterministic, headless-friendly playthrough.
-- It uses the real callbacks and writes typed checkpoints to smoke-test.rpt in
-- LÖVE's mouse-frontier save directory.
    ui.smokeLoad,ui.smokeUpdate,ui.smokeDraw=love.load,love.update,love.draw
    ui.smokeReport=nil; ui.smokeController=nil; ui.smokeFinalized=false
    ui.smokeFull=os.getenv("MOUSE_FRONTIER_SMOKE_FULL")=="1"
    local function smokeSnapshot()
        return {state=game.state,scene=game.scene,location=game.saveData and game.saveData.location,
            food=game.saveData and game.saveData.resources.food,water=game.saveData and game.saveData.resources.water,
            coal=game.saveData and game.saveData.resources.coal,oil=game.saveData and game.saveData.resources.oil,health=game.saveData and game.saveData.health,
            inventoryOpen=game.inventoryOpen,mapOpen=game.mapOpen,traveling=game.travelTransition~=nil,
            maintenanceOpen=maintenanceSession.open,maintenanceCondition=game.saveData and Maintenance.condition(game.saveData),
            maintenanceTargets=Maintenance.targetCount(),maintenanceProgress=Maintenance.progressCount(maintenanceSession),
            maintenanceCursor=maintenanceSession.cursorActive,maintenanceCompleted=maintenanceSession.completed,
            battleActive=game.battle~=nil,playerX=game.player and game.player.x,playerY=game.player and game.player.y,
            activeCar=game.saveData and game.saveData.activeCar,carTransitioning=game.carTransition~=nil,
            sessionSynchronized=session and session.screen==game.state and session.scene==game.scene and session.saveData==game.saveData and session.player==game.player and session.selectedSlot==game.selectedSlot,
            screenManagerSynchronized=screens and screens.current==game.state and screens.current==session.screen,
            runtimeSynchronized=game:isSynchronized(screens),
            assetFailures=Assets.assetFailureCount(),luaMemoryKB=math.floor(collectgarbage("count")),
            fps=love.timer and love.timer.getFPS and love.timer.getFPS() or nil}
    end
    local function setFixture(name)
        game.inventoryOpen,game.mapOpen,game.tradeOpen,game.trainUpgradeOpen,game.poseMenu=false,false,false,false,false
        ui.optionsOpen,ui.radioOpen=false,false
        if name=="intro" then game.state="intro"; ui.introCinematic=createIntro()
        elseif name=="slots" then game.state="slots"
        elseif name=="characters" then game.state="characters"
        elseif name=="event" then game.scene="stop"; game.randomEvent=beginRandomEvent()
        elseif name=="battle" then
            beginEncounter({rolled=true,hasMob=true,resolved=false,tier="easy",mobFiles={Catalog.mobTiers.easy[1]}}); game.battle.intro=nil
        elseif name=="ending" then game.state="ending"
        elseif name=="inventory" then game.state="game"; game.scene="train"; game.saveData.scene=game.scene; game.inventoryOpen=true
        else game.state="game"; game.scene=name; game.saveData.scene=game.scene; if game.scene~="train" then ensureStopLayout(); setupNPC() end end
        return name
    end
    local function fixtureStep(name)
        return {name="render_"..name,action=function() return setFixture(name) end,
            expect=name=="slots" and {state="slots"} or (name=="characters" and {state="characters"} or nil),
            check=function(_,_,snapshot) ui.smokeDraw(); return snapshot.state~=nil end}
    end
    function love.load(...)
        local ok,message=xpcall(ui.smokeLoad,debug.traceback,...)
        if not ok then io.stderr:write("LOAD_ERROR: "..tostring(message).."\n"); io.stderr:flush(); os.exit(1) end
        local character=characters[1]
        if not character then io.stderr:write("LOAD_ERROR: no playable character assets found\n"); io.stderr:flush(); os.exit(1) end
        game.saveData=newSave(character); game.selectedSlot=nil; enterGame(game.saveData)
        local mobileControls=getMobileControls()
        local reportPath=os.getenv("MOUSE_FRONTIER_SMOKE_REPORT") or os.getenv("MOUSE_FRONTIER_SMOKE_RPT") or "smoke-test.rpt"
        ui.smokeReport=SmokeReport.new({path=reportPath,metadata={mode=ui.smokeFull and "full-journey" or "autoplay",saveVersion=CURRENT_SAVE_VERSION,character=character,reportPath=reportPath,encounterPolicy=ui.smokeFull and "auto-resolve-for-route" or "normal"}})
        local startX=game.player.x
        local steps={fixtureStep("intro"),fixtureStep("slots"),fixtureStep("characters"),
            {name="startup_runtime_ready",action=function()
                return {loaded=startupRuntime.isLoaded(),secondLoad=startupRuntime.load(),animations=type(startupRuntime.characterAnimations())=="table",clouds=type(startupRuntime.cloudLayer())=="table",streamer=ui.assetStreamer~=nil}
            end,check=function(_,_,_,result) return result.loaded and result.secondLoad==false and result.animations and result.clouds and result.streamer end},
            {name="content_registry_hydrated",action=function()
                local status=contentRegistry.status()
                status.furnitureLookup=contentRegistry.isFurnitureItem("woven-frontier-rug")
                return status
            end,check=function(_,_,_,result)
                return result.hydrated and result.targetsLinked and result.targetCount==19 and result.legacyAnimationCount==11 and result.furnitureLookup
            end},
            {name="view_layer_composed",action=viewComposition.status,
                check=function(_,_,_,result) return result.ready and result.componentCount==4 end},
            {name="view_dependencies_explicit",action=viewComposition.status,
                check=function(_,_,_,result) return result.explicitDependencies end},
            {name="adventure_services_composed",action=adventureComposition.status,
                check=function(_,_,_,result) return result.ready and result.componentCount==4 end},
            {name="platform_services_composed",action=platformComposition.status,
                check=function(_,_,_,result) return result.ready and result.componentCount==5 end},
            {name="input_commands_composed",action=inputComposition.status,
                check=function(_,_,_,result) return result.ready and result.commandGroups==9 end},
            {name="world_session_composed",action=worldSessionComposition.status,
                check=function(_,_,_,result) return result.ready and result.componentCount==2 end},
            {name="startup_context_composed",action=startupComposition.status,
                check=function(_,_,_,result) return result.ready and result.componentCount==2 end},
            {name="service_manifest_immutable",action=serviceRegistry.status,
                check=function(_,_,_,result)
                    return result.immutable and result.separated and result.serviceCount==18 and result.factoryCount>result.serviceCount
                end},
            {name="smoke_context_composed",action=smokeComposition.status,
                check=function(_,_,_,result) return result.ready and result.groupCount==4 end},
            {name="application_graph_composed",action=applicationComposition.status,
                check=function(_,_,_,result)
                    return result.ready and result.compositionCount==7 and result.serviceCount==18
                end},
            {name="progression_balance_curve",action=balanceAudit,
                check=function(_,_,_,result)
                    return result.ready and result.shortageDetected and result.legs==49 and result.resourceCap==30
                        and result.maximum.food==5 and result.maximum.water==7 and result.maximum.coal==7
                end},
            {name="combat_balance_curve",action=combatBalanceAudit,
                check=function(_,_,_,result)
                    return result.ready and result.tierCounts.easy==12 and result.tierCounts.medium==18
                        and result.tierCounts.hard==20 and result.hardEnd.maxHP==34 and result.hardEnd.armor==5
                        and result.groupHardReward.xp>result.singleHardReward.xp and result.bossHardReward.xp>result.groupHardReward.xp
                end},
            {name="global_camera_input",action=presentationRuntime.cameraAudit,
                check=function(_,_,_,result)
                    return result.inverse and result.bounded and result.isolated and result.restored
                        and result.minZoom==1 and result.maxZoom==2.25 and result.curve=="global-camera-v1"
                end},
            {name="responsive_train_presentation",action=trainPresentationAudit,
                check=function(_,_,_,result)
                    return result.ready and result.aligned and result.tabsFit and result.tabs==7
                        and result.engineLeft==23 and result.carRight==935 and result.transitionDistance==960
                        and result.curve=="train-presentation-v1"
                end},
            {name="maintenance_route_balance",action=Maintenance.audit,
                check=function(_,_,_,result)
                    return result.ready and result.baseWear==5 and result.expandedWear==10 and result.upgradedWear==8
                        and result.oilCapacity==30 and result.serviceCost==5 and result.serviceRestore==40
                        and result.lowCoalPenalty==2 and result.lowSpeed==.82 and result.curve=="maintenance-v1"
                end},
            {name="tactical_grid_expansion",action=battleGridAudit,
                check=function(_,_,_,result)
                    return result.ready and result.curve=="battle-grid-v1" and result.columns==10 and result.rows==6
                        and result.spaces==60 and result.obstacles==7 and result.pathing and result.lineOfSight and result.zoomHitTest
                end},
            {name="player_progression_curve",action=playerBalanceAudit,
                check=function(_,_,_,result)
                    return result.ready and result.curve=="player-v2" and result.maxLevel==12
                        and result.cumulativeXP==1210 and result.sampleLevel==4 and result.sampleHealth==29
                        and result.sampleNextXP==46 and result.cappedLevel==12 and result.abilityCount==12
                        and result.finalBonuses.attack==5 and result.finalBonuses.armor==2 and result.finalBonuses.move==1
                        and result.strongProfiles.heal.heal>result.baseProfiles.heal.heal
                        and result.strongProfiles.volley.damage>result.baseProfiles.volley.damage
                end},
            {name="event_balance_curve",action=eventBalanceAudit,
                check=function(_,_,_,result)
                    return result.ready and result.eventCount==40 and result.choiceCount==120
                        and #result.blockedEvents==0 and result.encounterChance.easy==.48
                        and result.encounterChance.hard==.64 and result.earlyWeights.fortune>result.lateWeights.fortune
                        and result.lateWeights.mishap>result.earlyWeights.mishap and result.repeatAvoided
                end},
            {name="train_upgrade_balance",action=upgradeBalanceAudit,
                check=function(_,_,_,result)
                    return result.ready and result.carCount==6 and result.carCost==158 and result.engineCost==158
                        and result.baseCapacity==20 and result.expandedCapacity.food==30
                        and result.expandedCapacity.water==30 and result.expandedCapacity.coal==30 and result.expandedCapacity.oil==30
                        and result.passengerLoad==2 and result.arrival.food==2 and result.arrival.health==3
                        and result.navigatorSavings==1 and result.firstCarPurchase and result.firstEnginePurchase
                        and result.legacyOverflowPreserved and result.firstEngineUnlock==5
                end},
            {name="loot_equipment_balance",action=lootBalanceAudit,
                check=function(_,_,_,result)
                    return result.ready and result.valid and result.weaponCount==83 and result.familyCount>=6
                        and result.statusProfiles>=12 and result.damageReady and result.curve=="loot-v3"
                        and result.brokenMultiplier==0 and result.repairCost>0
                        and result.lateWeaponPrice>result.starterWeaponPrice
                        and result.legendaryPrice>result.commonPrice
                        and result.wornResale<result.soundResale
                end},
            {name="audio_engine_lifecycle",action=function() return audioAudit() end,
                check=function(_,_,_,result) return result.failedTrackSkipped and result.replacementReleased and result.shuffleBag and result.priority and result.focus and result.titleSilent end},
            {name="quest_passenger_balance",action=questBalanceAudit,
                check=function(_,_,_,result)
                    return result.ready and result.earlyWeights.mail>result.lateWeights.mail
                        and result.lateWeights.trade>result.earlyWeights.trade
                        and result.curve=="quest-v4" and result.earlyRequestRate<=.401 and result.lateRequestRate<=.361
                        and result.farReward.scrap>result.nearReward.scrap
                        and result.farReward.xp>result.nearReward.xp
                        and result.diplomatReward.scrap>result.farReward.scrap
                        and result.greenhousePreferred.amount>result.greenhouseBase.amount
                        and result.scavenger.kind=="scrap" and result.objectiveCount==8 and result.deliveryKinds==6
                        and result.stockedRide>result.lowSupplyRide and result.mailboxDelivery=="mailbox"
                        and result.ammoDelivery=="ammunition" and result.foodInventoryUsed==2 and result.foodStorageUsed==1
                        and result.atomicShortage and result.legacyStorageUsed==3 and result.waterMixed
                        and result.medicineReady and result.repairMixed and result.ammunitionReady and result.recoveryGated
                end},
            {name="stop_help_goodwill",action=function()
                    local result=helpBalanceAudit(); local previousState=game.state
                    game.state="game"; game.firstAid=FirstAid.new({location=2,itemName="field-bandage-roll",itemSlot=1})
                    ui.smokeDraw(); game.firstAid=nil; game.state=previousState; result.overlayRendered=true
                    return result
                end,
                check=function(_,_,_,result)
                    return result.ready and result.curve=="goodwill-v1" and result.policyVersion==3
                        and result.points==5 and result.helpCount==2 and result.itemGoodwill==2 and result.aidGoodwill==3
                        and result.noNegativeAlignment and result.firstAid.ready and result.firstAid.stages==3
                        and result.firstAid.maximumMisses==3 and result.firstAid.keyboard and result.firstAid.touch and result.overlayRendered
                end},
            {name="positive_finale_progression",action=finaleAudit,
                check=function(_,_,_,result)
                    return result.ready and result.curve=="finale-v1" and result.choiceCount==3 and result.selected=="lifeline"
                        and result.positiveOnly and result.low.tier=="HOME AT LAST"
                        and result.middle.tier=="RAILWAY OF HOPE" and result.high.tier=="FRONTIER BEACON"
                        and result.low.score<result.middle.score and result.middle.score<result.high.score
                        and result.high.storyClues==10 and result.high.condition==96 and result.high.cars==7
                end},
            {name="screen_flow_installed",action=function()
                return {installed=screenFlow.isInstalled(),routes=screenFlow.count(),current=screens.current}
            end,check=function(_,_,_,result) return result.installed and result.routes==7 and result.current~=nil end},
            {name="persistence_focus_flush",action=function()
                local previousSlot=game.selectedSlot; game.selectedSlot=99
                local revision=ui.itemOrderRevision or 0
                local scheduled=persistenceRuntime.schedule()
                local flushed=persistenceRuntime.focus(false)
                local suspended=audioRuntime.status().suspended
                persistenceRuntime.focus(true)
                local resumed=not audioRuntime.status().suspended
                local persisted=Save.read(99)
                Save.remove(99); game.selectedSlot=previousSlot
                return {scheduled=scheduled,flushed=flushed,persisted=persisted~=nil,revisionAdvanced=(ui.itemOrderRevision or 0)>revision,suspended=suspended,resumed=resumed}
            end,check=function(_,_,_,result) return result.scheduled and result.flushed and result.persisted and result.revisionAdvanced and result.suspended and result.resumed end},
            {name="start_new_game",action=function() game.saveData=newSave(character); enterGame(game.saveData); return true end,expect={state="game",scene="train",location=1,food=10,water=10,coal=10,oil=10,runtimeSynchronized=true}},
            {name="audio_priority_and_title_silence",action=function()
                local settings=game.saveData.audio
                settings.station="chill"; settings.rainEnabled=false; audioRuntime.resetMusic(); audioRuntime.update()
                local stationCategory=audioRuntime.status().category
                local oldState,oldBattle=game.state,game.battle
                game.state="battle"; game.battle={encounter={tier="hard",boss=true}}; audioRuntime.update()
                local battleCategory=audioRuntime.status().category
                game.state="slots"; audioRuntime.update()
                local titleStatus=audioRuntime.status()
                game.state,game.battle=oldState,oldBattle; settings.station="8bit"; audioRuntime.resetMusic(); audioRuntime.update()
                return {station=stationCategory,battle=battleCategory,titleSilent=titleStatus.nowPlaying==nil and titleStatus.rainPath==nil}
            end,check=function(_,_,_,result) return result.station=="chill" and result.battle=="bossFight" and result.titleSilent end},
            {name="radio_transport_render",action=function()
                ui.radioOpen=true; ui.smokeDraw()
                local controls={ui.radio8bit,ui.radioChill,ui.radioVibes,ui.radioRain,ui.radioClose,ui.radioPrevious,ui.radioPause,ui.radioNext,ui.radioMute}
                local complete=true
                for _,control in ipairs(controls) do complete=complete and control and control.w>0 and control.h>0 end
                ui.radioOpen=false
                return {complete=complete,count=#controls}
            end,check=function(_,_,_,result) return result.complete and result.count==9 end},
            {name="walk_right",action=function()
                local old=love.keyboard.isDown; love.keyboard.isDown=function(key) return key=="d" end
                local callOk,err=xpcall(function() ui.smokeUpdate(.25) end,debug.traceback); love.keyboard.isDown=old
                if not callOk then error(err) end; return game.player.x
            end,check=function(_,_,snapshot,result) return result>startX and snapshot.playerX>startX end},
            {name="presentation_coordinate_modes",action=function()
                presentationRuntime.setZoom(2)
                local baseX,baseY=presentationRuntime.viewportToGame(100,100)
                local worldX,worldY=presentationRuntime.screenToGame(100,100)
                local worldSurface=presentationRuntime.getSurface()
                ui.radioOpen=true
                presentationRuntime.setZoom(1.6)
                local radioX,radioY=presentationRuntime.screenToGame(100,100)
                local radioSurface=presentationRuntime.getSurface()
                ui.radioOpen=false; maintenanceSession.open=true
                presentationRuntime.setZoom(1.4)
                local maintenanceX,maintenanceY=presentationRuntime.screenToGame(100,100)
                local maintenanceSurface=presentationRuntime.getSurface()
                maintenanceSession.open=false
                local restored=presentationRuntime.getZoom()==2
                presentationRuntime.resetCamera(true)
                return {
                    worldShifted=math.abs(worldX-baseX)>.01 or math.abs(worldY-baseY)>.01,
                    radioShifted=math.abs(radioX-baseX)>.01 or math.abs(radioY-baseY)>.01,
                    maintenanceShifted=math.abs(maintenanceX-baseX)>.01 or math.abs(maintenanceY-baseY)>.01,
                    scoped=worldSurface~=radioSurface and radioSurface~=maintenanceSurface,
                    restored=restored,
                }
            end,check=function(_,_,_,result)
                return result.worldShifted and result.radioShifted and result.maintenanceShifted and result.scoped and result.restored
            end},
            {name="open_inventory_key",action=function() love.keypressed("i"); return game.inventoryOpen end,expect={inventoryOpen=true}},
            {name="close_inventory_key",action=function() love.keypressed("i"); return "closed" end,expect={inventoryOpen=false}},
            {name="open_map_key",action=function() love.keypressed("m"); return game.mapOpen end,expect={mapOpen=true}},
            {name="scroll_map_key",action=function() local before=game.mapScroll; love.keypressed("down"); return {before=before,after=game.mapScroll} end,
                check=function(_,_,_,result) return result.after==result.before+1 end},
            {name="close_map_key",action=function() love.keypressed("m"); return "closed" end,expect={mapOpen=false}},
            {name="begin_train_car_transition",action=function()
                game.state="game"; game.scene="train"; game.saveData.scene=game.scene
                game.saveData.trainCars={"living-car","coal-hauler","storage","greenhouse","sleeper","medical","navigator"}; game.saveData.activeCar=1
                game.dialogue=nil; ui.smokeDraw()
                local tabs=ui.trainCarTabs or {}; local target=tabs[7]
                if target then love.mousepressed(target.x+target.w/2,target.y+target.h/2,1) end
                return {transition=game.carTransition~=nil,to=game.carTransition and game.carTransition.to,tabs=#tabs,
                    first=tabs[1] and tabs[1].x,last=tabs[7] and tabs[7].x+tabs[7].w}
            end,check=function(_,_,snapshot,result)
                return result.transition and result.to==7 and result.tabs==7 and result.first>=0 and result.last<=960
                    and snapshot.activeCar==1 and snapshot.carTransitioning
            end},
            {name="complete_train_car_transition",action=function() return true end,
                expect={activeCar=7,carTransitioning=false},timeout=4,
                after=function() game.saveData.trainCars={"living-car"}; game.saveData.activeCar=1; ui.interaction=nil end},
            {name="open_maintenance",action=function()
                game.state="game"; game.scene="train"; game.saveData.scene=game.scene; Maintenance.open(maintenanceSession,game.saveData)
                if os.getenv("MOUSE_FRONTIER_SMOKE_CAPTURE_MAINTENANCE")=="1" then ui.smokeMaintenanceCaptureRequested=true end
                ui.smokeDraw(); return true
            end,expect={maintenanceOpen=true,maintenanceCondition=72,maintenanceTargets=3,maintenanceProgress=0,maintenanceCursor=true}},
            {name="maintenance_cancel_preserves_oil",action=function()
                game.saveData.resources.oil=1
                local before=game.saveData.resources.oil
                local x,y=Maintenance.targetPosition(1); love.mousepressed(x,y,1); love.mousepressed(x,y,1)
                local afterDrop=game.saveData.resources.oil
                local limitedProgress=Maintenance.progressCount(maintenanceSession)
                love.keypressed("escape")
                local afterCancel=game.saveData.resources.oil
                game.saveData.resources.oil=10
                Maintenance.open(maintenanceSession,game.saveData)
                return {before=before,afterDrop=afterDrop,afterCancel=afterCancel,limitedProgress=limitedProgress,
                    reopenedProgress=Maintenance.progressCount(maintenanceSession)}
            end,check=function(_,_,snapshot,result)
                return result.before==1 and result.afterDrop==1 and result.afterCancel==1 and result.limitedProgress==1 and result.reopenedProgress==0 and
                    snapshot.maintenanceOpen==true and snapshot.oil==10
            end},
            {name="service_running_gear",action=function()
                love.mousepressed(50,300,1)
                local outsideProgress=Maintenance.progressCount(maintenanceSession)
                local x1,y1=Maintenance.targetPosition(1); love.mousepressed(x1,y1,1); love.mousepressed(x1,y1,1); love.mousepressed(x1,y1,1)
                local x2,y2=Maintenance.targetPosition(2); love.mousepressed(x2,y2,1)
                local x3,y3=Maintenance.targetPosition(3); love.mousepressed(x3,y3,1); love.mousepressed(x3,y3,1)
                local beforeDone={condition=Maintenance.condition(game.saveData),progress=Maintenance.progressCount(maintenanceSession),oil=game.saveData.resources.oil}
                love.mousepressed(712,544,1)
                if os.getenv("MOUSE_FRONTIER_SMOKE_CAPTURE_MAINTENANCE")=="1" then ui.smokeMaintenanceCompleteCaptureRequested=true end
                ui.smokeDraw()
                return {services=game.saveData.maintenance.totalServices,outsideProgress=outsideProgress,beforeDone=beforeDone,oilAfter=game.saveData.resources.oil,
                    lights=Maintenance.progressLights(maintenanceSession),cursor=maintenanceSession.cursorActive,
                    animationSpec=Maintenance.animationSpec(),animationState=Maintenance.animationState(maintenanceSession)}
            end,check=function(_,_,snapshot,result)
                local lit=0; for _,value in ipairs(result.lights or {}) do if value then lit=lit+1 end end
                local spec,animationState=result.animationSpec or {},result.animationState or {}
                return result.services==1 and result.outsideProgress==0 and result.beforeDone.condition==72 and result.beforeDone.progress==5 and
                    result.beforeDone.oil==10 and result.oilAfter==5 and snapshot.oil==5 and
                    lit==5 and result.cursor==false and snapshot.maintenanceCondition==100 and snapshot.maintenanceCompleted==true and
                    spec.wheelFrames==5 and spec.doneFrames==5 and spec.conditionFrames==5 and animationState.smokePuffs==3
            end},
            {name="maintenance_animation_settles",action=function()
                Maintenance.update(maintenanceSession,1.1); ui.smokeDraw()
                return Maintenance.animationState(maintenanceSession)
            end,check=function(_,_,snapshot,result)
                return result.wheelFrame==1 and result.doneFrame==5 and result.conditionFrame==5 and result.smokePuffs==0 and
                    snapshot.maintenanceCondition==100 and snapshot.maintenanceCompleted==true
            end},
            {name="close_maintenance",action=function() love.keypressed("escape"); return true end,expect={maintenanceOpen=false}},
            {name="maintenance_persists_at_stop",action=function()
                Maintenance.open(maintenanceSession,game.saveData)
                local before=game.saveData.maintenance.totalServices
                local x,y=Maintenance.targetPosition(1); local result=Maintenance.mousepressed(maintenanceSession,x,y,game.saveData)
                local persisted={progress=Maintenance.progressCount(maintenanceSession),cursor=maintenanceSession.cursorActive,
                    completed=maintenanceSession.completed,services=game.saveData.maintenance.totalServices,before=before,result=result}
                Maintenance.close(maintenanceSession); return persisted
            end,check=function(_,_,snapshot,result)
                return result.progress==5 and result.cursor==false and result.completed and result.services==result.before and snapshot.maintenanceOpen==false
            end},
            {name="store_oil_canisters",action=function()
                game.saveData.resources.oil=0
                local levels={}
                for _,name in ipairs({"small-oil-canister","medium-oil-canister","large-oil-canister"}) do
                    game.saveData.inventory[1]=name; game.draggedSlot={kind="inventory",index=1}
                    if not consumeSelected() then return false end
                    levels[#levels+1]=game.saveData.resources.oil
                end
                game.dialogue=nil; game.actionHeldItem=nil; game.actionTimer=0
                return {levels=levels,slot=game.saveData.inventory[1],dragged=game.draggedSlot}
            end,check=function(_,_,snapshot,result)
                return result and result.levels[1]==1 and result.levels[2]==6 and result.levels[3]==16 and
                    result.slot==nil and result.dragged==nil and snapshot.oil==16
            end},
            {name="confirm_travel",action=function() game.state="game"; game.scene="train"; game.saveData.scene=game.scene; game.travelConfirm=true; love.keypressed("return"); return true end,
                expect={food=9,water=9,coal=9,traveling=true}},
            {name="complete_travel",action=function() return true end,expect={location=2,traveling=false},timeout=20},
            fixtureStep("stop"),
            {name="enter_house_key",action=function() ui.interaction={kind="house",index=1}; love.keypressed("q"); return "q" end,expect={state="game",scene="house"}},
            fixtureStep("house"),
            {name="exit_house_key",action=function() ui.interaction={kind="houseExit"}; love.keypressed("q"); return "q" end,expect={state="game",scene="stop"}},
            fixtureStep("inventory"),fixtureStep("event"),fixtureStep("battle"),
            {name="battle_ui_mouse_routes",action=function()
                ui.smokeDraw()
                local pack=ui.battleInventory
                if not pack then return false end
                ui.handleBattleMousePressed(pack.x+pack.w/2,pack.y+pack.h/2,false)
                local opened=game.inventoryOpen
                ui.smokeDraw()
                local close=ui.battleInventoryClose
                if not close then return false end
                ui.handleBattleMousePressed(close.x+close.w/2,close.y+close.h/2,false)
                return {opened=opened,closed=not game.inventoryOpen}
            end,check=function(_,_,snapshot,result)
                return result and result.opened and result.closed and snapshot.state=="battle" and snapshot.battleActive
            end},
            {name="render_weapon_hand_attachments",action=function()
                local unit=game.battle and game.battle.units and game.battle.units[1]
                if not unit then return false end
                unit.action="ranged"; unit.actionTimer=.44; unit.actionItem="frontier-9mm-service-pistol"; ui.smokeDraw()
                unit.actionItem="frontier-22-lever-rifle"; unit.actionTimer=.22; ui.smokeDraw()
                unit.action="melee"; unit.actionItem="frontier-executioner-axe"; unit.actionTimer=.44; ui.smokeDraw()
                unit.actionItem="wasteland-partisan"; unit.actionTimer=.22; ui.smokeDraw()
                unit.action=nil; unit.actionItem=nil; unit.actionTimer=0
                return true
            end,check=function(_,_,_,result) return result==true end},
            {name="retreat_battle_key",action=function() love.keypressed("r"); return "r" end,expect={state="game",scene="train",battleActive=false}},
            fixtureStep("ending"),
            {name="finale_keyboard_choice",action=function()
                ui.smokeDraw(); love.keypressed("3"); ui.smokeDraw()
                return game.saveData.finale and game.saveData.finale.choice
            end,check=function(_,_,snapshot,result) return snapshot.state=="ending" and result=="lifeline" and ui.endingButton~=nil end},
            {name="game_session_synchronized",action=function() return true end,expect={sessionSynchronized=true,screenManagerSynchronized=true}},
            {name="save_schema_migrates_legacy_copy",action=function()
                local legacy={version=1,character=character,location=7,resources={food=3},inventory={},equipment={},droppedItems={}}
                local migrated,metadata=SaveSchema.migrate(legacy)
                local valid=SaveSchema.validate(migrated)
                return {originalVersion=legacy.version,version=migrated and migrated.version,steps=metadata and metadata.steps,
                    food=migrated and migrated.resources.food,oil=migrated and migrated.resources.oil,
                    visited=migrated and migrated.visitedStops[7],valid=valid}
            end,check=function(_,_,_,result)
                return result.originalVersion==1 and result.version==CURRENT_SAVE_VERSION and
                    result.steps==CURRENT_SAVE_VERSION-1 and result.food==3 and result.oil==10 and result.visited and result.valid
            end},
            {name="save_schema_rejects_invalid_data",action=function()
                local future,futureError=SaveSchema.migrate({version=CURRENT_SAVE_VERSION+1})
                local corrupt,corruptError=SaveSchema.migrate({version=CURRENT_SAVE_VERSION,resources="broken"})
                local cyclic={version=CURRENT_SAVE_VERSION}; cyclic.self=cyclic
                local copied,cycleError=SaveSchema.migrate(cyclic)
                return {future=future,futureError=futureError,corrupt=corrupt,corruptError=corruptError,
                    copied=copied,cycleError=cycleError}
            end,check=function(_,_,_,result)
                return result.future==nil and result.futureError~=nil and result.corrupt==nil and result.corruptError~=nil and
                    result.copied==nil and result.cycleError~=nil
            end},
            {name="save_read_upgrades_legacy_slot",action=function()
                Save.remove(99)
                local path=Save.path(99)
                local raw="return {version=1,character="..string.format("%q",character)..",location=12,resources={food=4},inventory={},equipment={},droppedItems={}}"
                love.filesystem.createDirectory("saves")
                love.filesystem.write(path,raw)
                local loaded=Save.read(99)
                local primary=love.filesystem.read(path)
                local backup=love.filesystem.read(path..".bak")
                Save.remove(99)
                return {version=loaded and loaded.version,location=loaded and loaded.location,food=loaded and loaded.resources.food,
                    primaryCurrent=primary and primary:find('%["version"%] = '..CURRENT_SAVE_VERSION)~=nil,
                    backupLegacy=backup==raw}
            end,check=function(_,_,_,result)
                return result.version==CURRENT_SAVE_VERSION and result.location==12 and result.food==4 and
                    result.primaryCurrent and result.backupLegacy
            end},
            {name="save_round_trip",action=function()
                local payload={version=CURRENT_SAVE_VERSION,location=17,nested={value="smoke-save"}}
                local wrote=Save.write(99,payload); local loaded=Save.read(99); Save.remove(99)
                return {wrote=wrote,location=loaded and loaded.location,nested=loaded and loaded.nested and loaded.nested.value}
            end,check=function(_,_,_,result) return result.wrote and result.location==17 and result.nested=="smoke-save" end},
            {name="save_recovers_corrupt_primary",action=function()
                Save.remove(99)
                local wrote=Save.write(99,{version=CURRENT_SAVE_VERSION,location=23,nested={value="known-good"}})
                local path=Save.path(99)
                local good=love.filesystem.read(path)
                love.filesystem.write(path..".bak",good)
                love.filesystem.write(path,"return {version=25, resources='broken'}")
                local recovered=Save.read(99)
                local primary=love.filesystem.read(path)
                local backup=love.filesystem.read(path..".bak")
                Save.remove(99)
                return {wrote=wrote,location=recovered and recovered.location,nested=recovered and recovered.nested and recovered.nested.value,
                    primaryGood=primary and primary:find("known%-good")~=nil,backupGood=backup and backup:find("known%-good")~=nil}
            end,check=function(_,_,_,result)
                return result.wrote and result.location==23 and result.nested=="known-good" and result.primaryGood and result.backupGood
            end},
            {name="asset_contract",action=function() return Assets.assetFailureSummary() end,expect={assetFailures=0}}
        }
        if mobileControls and mobileControls:isEnabled() then
            local mobileSteps={
                {name="mobile_joystick_move_and_run",action=function()
                    game.saveData=newSave(character); enterGame(game.saveData)
                    local before=game.player.x
                    love.touchpressed("smoke-stick",116,604)
                    love.touchmoved("smoke-stick",192,604,76,0)
                    local sprinting=mobileControls:isSprinting()
                    ui.smokeUpdate(.25)
                    love.touchreleased("smoke-stick",192,604)
                    local axisX,axisY=mobileControls:movement()
                    return {before=before,after=game.player.x,sprinting=sprinting,axisX=axisX,axisY=axisY,stickX=mobileControls.joystick.x,actionX=mobileControls.primary.x}
                end,check=function(_,_,_,result)
                    return result.after>result.before and result.sprinting and result.axisX==0 and result.axisY==0 and result.stickX<=100 and result.actionX>=884
                end},
                {name="mobile_action_press_release",action=function()
                    ui.interaction=nil; game.dialogue=nil
                    love.touchpressed("smoke-action",855,615)
                    local held=mobileControls:isHeld("e")
                    local action=game.actionKind
                    love.touchreleased("smoke-action",855,615)
                    return {held=held,released=not mobileControls:isHeld("e"),action=action}
                end,check=function(_,_,_,result) return result.held and result.released and result.action=="use" end},
                {name="mobile_menu_touch",action=function()
                    ui.smokeDraw()
                    love.touchpressed("smoke-menu-open",866,100); love.touchreleased("smoke-menu-open",866,100)
                    ui.smokeDraw()
                    local menuOpened=ui.mobileMenuOpen and ui.backpack and ui.backpack.h>=64
                    love.touchpressed("smoke-pack-open",437,259); love.touchreleased("smoke-pack-open",437,259)
                    local opened=game.inventoryOpen and not ui.mobileMenuOpen
                    ui.smokeDraw()
                    love.touchpressed("smoke-back",80,101); love.touchreleased("smoke-back",80,101)
                    return {menuOpened=menuOpened,opened=opened,closed=not game.inventoryOpen}
                end,check=function(_,_,_,result) return result.menuOpened and result.opened and result.closed end},
                {name="mobile_pinch_zoom",action=function()
                    ui.mobileMenuOpen=false; game.inventoryOpen=false; game.mapOpen=false; game.dialogue=nil; presentationRuntime.setZoom(1)
                    love.touchpressed("smoke-pinch-a",400,350)
                    love.touchpressed("smoke-pinch-b",560,350)
                    love.touchmoved("smoke-pinch-b",640,350,80,0)
                    local zoomed=presentationRuntime.getZoom()
                    love.touchreleased("smoke-pinch-b",640,350)
                    love.touchreleased("smoke-pinch-a",400,350)
                    local clean=mobileControls.pinch==nil and next(mobileControls.touches)==nil
                    love.touchpressed("smoke-pinch-c",400,350)
                    love.touchpressed("smoke-pinch-d",640,350)
                    love.touchmoved("smoke-pinch-d",420,350,-220,0)
                    local clamped=presentationRuntime.getZoom()
                    love.touchreleased("smoke-pinch-d",420,350); love.touchreleased("smoke-pinch-c",400,350)
                    game.inventoryOpen=true; presentationRuntime.setZoom(1)
                    love.touchpressed("smoke-pinch-overlay-a",400,350); love.touchpressed("smoke-pinch-overlay-b",560,350)
                    love.touchmoved("smoke-pinch-overlay-b",640,350,80,0)
                    local overlayZoom=presentationRuntime.getZoom()
                    love.touchreleased("smoke-pinch-overlay-b",640,350); love.touchreleased("smoke-pinch-overlay-a",400,350)
                    local beforePanX,beforePanY=presentationRuntime.screenToGame(480,360)
                    love.touchpressed("smoke-pan-overlay-a",400,350); love.touchpressed("smoke-pan-overlay-b",560,350)
                    love.touchmoved("smoke-pan-overlay-a",440,350,40,0); love.touchmoved("smoke-pan-overlay-b",600,350,40,0)
                    local afterPanX,afterPanY=presentationRuntime.screenToGame(480,360)
                    love.touchreleased("smoke-pan-overlay-b",600,350); love.touchreleased("smoke-pan-overlay-a",440,350)
                    local panned=math.abs(afterPanX-beforePanX)>.01 or math.abs(afterPanY-beforePanY)>.01
                    local finalClean=mobileControls.pinch==nil and next(mobileControls.touches)==nil
                    game.inventoryOpen=false; presentationRuntime.resetCamera(true)
                    return {zoomed=zoomed,clamped=clamped,clean=clean,overlayZoom=overlayZoom,panned=panned,finalClean=finalClean}
                end,check=function(_,_,_,result)
                    return result.zoomed>1.45 and result.zoomed<1.55 and result.clamped==1 and result.clean
                        and result.overlayZoom>1.45 and result.overlayZoom<1.55 and result.panned and result.finalClean
                end},
            }
            for _,step in ipairs(mobileSteps) do steps[#steps+1]=step end
        end
        for _,step in ipairs(steps) do
            local originalAfter=step.after
            step.after=function(controller,current,record)
                ui.smokeReport:step(record.name,"passed",{elapsed=record.elapsed})
                ui.smokeReport:value(record.name..".return",record.value)
                ui.smokeReport:value(record.name..".variables",record.state)
                ui.smokeReport:checkpoint(record.name,true,record.state); ui.smokeReport:flush()
                if originalAfter then originalAfter(controller,current,record) end
            end
        end
        if ui.smokeFull then
            local fullSteps={
                {name="full_run_initialize",action=function()
                    game.saveData=newSave(character)
                    -- Full-route mode tests progression to stop 50. The tester
                    -- provisions supplies so ordinary scarcity does not mask
                    -- route, encounter, or ending defects.
                    game.saveData.resources.food=1000; game.saveData.resources.water=1000; game.saveData.resources.coal=1000
                    enterGame(game.saveData); return true
                end,expect={state="game",scene="train",location=1}},
                {name="full_journey_to_stop_50",timeout=500,before=function() ui.smokeFullLastLocation=game.saveData.location; ui.smokeFullStall=0 end,action=function()
                    if game.saveData.location==ui.smokeFullLastLocation then ui.smokeFullStall=(ui.smokeFullStall or 0)+1 else ui.smokeFullLastLocation=game.saveData.location; ui.smokeFullStall=0 end
                    if ui.smokeFullStall>30 then error("GAMEPLAY_BLOCKED: no progress at stop "..tostring(game.saveData.location).." state="..tostring(game.state).." scene="..tostring(game.scene).." battle="..tostring(game.battle~=nil).." event="..tostring(game.randomEvent~=nil)) end
                    if game.saveData.location>=50 then game.state="ending"; return true end
                    if game.state=="battle" then
                        if game.battle and game.battle.finished then love.keypressed("return")
                        elseif ui.smokeFull and game.battle then
                            -- Full-route mode is a progression reachability
                            -- test. Encounters are still created/rendered, but
                            -- are auto-resolved so combat RNG cannot hide a
                            -- route/ending defect. Normal smoke mode exercises
                            -- the actual battle controls separately.
                            for _,unit in ipairs(game.battle.units or {}) do if unit.team=="enemy" then unit.hp=0 end end
                            advanceBattleTurn()
                        elseif game.battle and game.battle.intro then
                            -- The real update callback advances the intro.
                        elseif game.battle and game.battle.phase=="select" then
                            local active=BattleRules.activeUnit(game.battle); if active and active.team=="ally" then
                                battleAttack("frontier-short-sword")
                            end
                        elseif game.battle and game.battle.phase=="target" then
                            local active=BattleRules.activeUnit(game.battle); local target
                            for _,unit in ipairs(game.battle.units or {}) do if unit.team=="enemy" and unit.hp>0 then target=unit; break end end
                            if active and target then resolveBattleAttack(active,target,game.battle.chosenWeapon or "frontier-short-sword") end
                        end
                    elseif game.state=="event" then
                        resolveEventChoice(1)
                    elseif game.state=="game" and game.scene=="stop" then
                        game.dialogue=nil; game.scene="train"; game.saveData.scene=game.scene; game.player.x,game.player.y=car.x+300,car.y+285; writeSave()
                    elseif game.state=="game" and game.scene=="train" and not game.travelTransition then
                        if game.saveData.resources.food<1 or game.saveData.resources.water<1 or game.saveData.resources.coal<1 then
                            error("GAMEPLAY_BLOCKED: resources exhausted before stop "..tostring(game.saveData.location+1))
                        end
                        -- Route mode focuses on reachability. Mark the current
                        -- stop's interruption as handled, then use the real
                        -- travel confirmation/input path.
                        local key=tostring(game.saveData.location); game.saveData.encounters[key]={resolved=true,hasMob=false}; game.saveData.events[key]=true
                        game.travelConfirm=true; love.keypressed("return")
                    elseif game.state~="game" or game.scene~="train" or game.travelTransition then
                        -- Let the real update callback advance transitions.
                    else error("GAMEPLAY_BLOCKED: unexpected state at stop "..tostring(game.saveData.location)) end
                    return game.saveData.location>=50
                end,check=function(_,_,snapshot)
                    if snapshot.state=="ending" and snapshot.location>=50 then return true end
                    return false,"still progressing: stop "..tostring(snapshot.location)
                end,expect={state="ending",location=50,sessionSynchronized=true,screenManagerSynchronized=true,runtimeSynchronized=true}}
            }
            steps=fullSteps
            for _,step in ipairs(steps) do
                local originalAfter=step.after
                step.after=function(controller,current,record)
                    ui.smokeReport:step(record.name,"passed",{elapsed=record.elapsed})
                    ui.smokeReport:value(record.name..".return",record.value)
                    ui.smokeReport:value(record.name..".variables",record.state)
                    ui.smokeReport:checkpoint(record.name,true,record.state); ui.smokeReport:flush()
                    if originalAfter then originalAfter(controller,current,record) end
                end
            end
        end
        ui.smokeController=SmokeController.new({name=ui.smokeFull and "mouse-frontier-full-journey" or "mouse-frontier-autoplay",timeout=ui.smokeFull and 10 or 4,steps=steps,hooks={snapshot=smokeSnapshot}})
    end
    function love.update(dt)
        if not ui.smokeController or ui.smokeFinalized then return end
        local status=ui.smokeController:getStatus()
        -- Fixed simulation time keeps the playthrough deterministic and lets
        -- transitions finish quickly even when the hidden window is throttled.
        if status.current~="walk_right" then ui.smokeUpdate(ui.smokeFull and 5 or .25) end
        status=ui.smokeController:update(ui.smokeFull and 5 or .25)
        if status.finished then
            ui.smokeFinalized=true
            local summary=ui.smokeController:getSummary()
            if status.failed then for _,message in ipairs(summary.errors) do ui.smokeReport:error(message) end end
            ui.smokeReport:value("controller.summary",summary); ui.smokeReport:finish(status.failed and "failed" or "passed")
            if status.failed then io.stderr:write("SMOKE_ERROR: "..table.concat(summary.errors," | ").."\n"); io.stderr:flush(); love.event.quit(1); return end
            print("SMOKE_OK: autonomous playthrough completed "..status.passed.." checkpoints"); io.flush(); love.event.quit(0); return
        end
    end
    function love.draw()
        if ui.smokeMaintenanceCaptureRequested and maintenanceSession.open and love.mouse and love.mouse.setPosition then love.mouse.setPosition(313,365) end
        if ui.smokeMaintenanceCompleteCaptureRequested and maintenanceSession.open and love.mouse and love.mouse.setPosition then
            love.mouse.setPosition(712,544); Maintenance.update(maintenanceSession,.34)
        end
        local ok,message=xpcall(ui.smokeDraw,debug.traceback)
        if not ok then if ui.smokeReport then ui.smokeReport:error("draw: "..tostring(message)); ui.smokeReport:finish("failed") end; io.stderr:write("DRAW_ERROR: "..tostring(message).."\n"); io.stderr:flush(); love.event.quit(1); return end
        if ui.smokeMaintenanceCaptureRequested and maintenanceSession.open then
            ui.smokeMaintenanceCaptureRequested=false
            love.graphics.captureScreenshot("maintenance-smoke-preview.png")
        end
        if ui.smokeMaintenanceCompleteCaptureRequested and maintenanceSession.open then
            ui.smokeMaintenanceCompleteCaptureRequested=false
            love.graphics.captureScreenshot("maintenance-smoke-complete-preview.png")
        end
    end

    return true
end

return {install=install}
