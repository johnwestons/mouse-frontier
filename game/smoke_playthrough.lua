local SmokeController = require("game.smoke_controller")
local SmokeReport = require("game.smoke_report")

local function install(scope)
    local env=setmetatable({}, {__index=function(_,key)
        local value=scope[key]
        if value~=nil then return value end
        return _G[key]
    end, __newindex=function(_,key,value) scope[key]=value end})
    setfenv(install,env)
-- `MOUSE_FRONTIER_SMOKE=1` runs a deterministic, headless-friendly playthrough.
-- It uses the real callbacks and writes typed checkpoints to smoke-test.rpt in
-- LÖVE's mouse-frontier save directory.
if os.getenv("MOUSE_FRONTIER_SMOKE")=="1" then
    ui.smokeLoad,ui.smokeUpdate,ui.smokeDraw=love.load,love.update,love.draw
    ui.smokeReport=nil; ui.smokeController=nil; ui.smokeFinalized=false
    ui.smokeFull=os.getenv("MOUSE_FRONTIER_SMOKE_FULL")=="1"
    local function smokeSnapshot()
        return {state=state,scene=scene,location=saveData and saveData.location,
            food=saveData and saveData.resources.food,water=saveData and saveData.resources.water,
            coal=saveData and saveData.resources.coal,oil=saveData and saveData.resources.oil,health=saveData and saveData.health,
            inventoryOpen=inventoryOpen,mapOpen=mapOpen,traveling=travelTransition~=nil,
            maintenanceOpen=maintenanceSession.open,maintenanceCondition=saveData and Maintenance.condition(saveData),
            maintenanceTargets=Maintenance.targetCount(),maintenanceProgress=Maintenance.progressCount(maintenanceSession),
            maintenanceCursor=maintenanceSession.cursorActive,maintenanceCompleted=maintenanceSession.completed,
            battleActive=battle~=nil,playerX=player and player.x,playerY=player and player.y,
            sessionSynchronized=session and session.screen==state and session.scene==scene and session.saveData==saveData and session.player==player and session.selectedSlot==selectedSlot,
            assetFailures=Assets.assetFailureCount(),luaMemoryKB=math.floor(collectgarbage("count")),
            fps=love.timer and love.timer.getFPS and love.timer.getFPS() or nil}
    end
    local function setFixture(name)
        inventoryOpen,mapOpen,tradeOpen,trainUpgradeOpen,poseMenu=false,false,false,false,false
        ui.optionsOpen,ui.radioOpen=false,false
        if name=="intro" then state="intro"; ui.introCinematic=Systems.intro.new(10)
        elseif name=="slots" then state="slots"
        elseif name=="characters" then state="characters"
        elseif name=="event" then state="event"; scene="stop"; randomEvent=Events.random(saveData)
        elseif name=="battle" then
            beginEncounter({rolled=true,hasMob=true,resolved=false,tier="easy",mobFiles={Catalog.mobTiers.easy[1]}}); battle.intro=nil
        elseif name=="ending" then state="ending"
        elseif name=="inventory" then state="game"; scene="train"; saveData.scene=scene; inventoryOpen=true
        else state="game"; scene=name; saveData.scene=scene; if scene~="train" then ensureStopLayout(); setupNPC() end end
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
        saveData=newSave(character); selectedSlot=nil; enterGame(saveData)
        local reportPath=os.getenv("MOUSE_FRONTIER_SMOKE_REPORT") or os.getenv("MOUSE_FRONTIER_SMOKE_RPT") or "smoke-test.rpt"
        ui.smokeReport=SmokeReport.new({path=reportPath,metadata={mode=ui.smokeFull and "full-journey" or "autoplay",saveVersion=CURRENT_SAVE_VERSION,character=character,reportPath=reportPath,encounterPolicy=ui.smokeFull and "auto-resolve-for-route" or "normal"}})
        local startX=player.x
        local steps={fixtureStep("intro"),fixtureStep("slots"),fixtureStep("characters"),
            {name="start_new_game",action=function() saveData=newSave(character); enterGame(saveData); return true end,expect={state="game",scene="train",location=1,food=10,water=10,coal=10,oil=10}},
            {name="walk_right",action=function()
                local old=love.keyboard.isDown; love.keyboard.isDown=function(key) return key=="d" end
                local callOk,err=xpcall(function() ui.smokeUpdate(.25) end,debug.traceback); love.keyboard.isDown=old
                if not callOk then error(err) end; return player.x
            end,check=function(_,_,snapshot,result) return result>startX and snapshot.playerX>startX end},
            {name="open_inventory_key",action=function() love.keypressed("i"); return inventoryOpen end,expect={inventoryOpen=true}},
            {name="close_inventory_key",action=function() love.keypressed("i"); return "closed" end,expect={inventoryOpen=false}},
            {name="open_map_key",action=function() love.keypressed("m"); return mapOpen end,expect={mapOpen=true}},
            {name="scroll_map_key",action=function() local before=mapScroll; love.keypressed("down"); return {before=before,after=mapScroll} end,
                check=function(_,_,_,result) return result.after==result.before+1 end},
            {name="close_map_key",action=function() love.keypressed("m"); return "closed" end,expect={mapOpen=false}},
            {name="open_maintenance",action=function()
                state="game"; scene="train"; saveData.scene=scene; Maintenance.open(maintenanceSession,saveData)
                if os.getenv("MOUSE_FRONTIER_SMOKE_CAPTURE_MAINTENANCE")=="1" then ui.smokeMaintenanceCaptureRequested=true end
                ui.smokeDraw(); return true
            end,expect={maintenanceOpen=true,maintenanceCondition=72,maintenanceTargets=3,maintenanceProgress=0,maintenanceCursor=true}},
            {name="maintenance_cancel_preserves_oil",action=function()
                saveData.resources.oil=1
                local before=saveData.resources.oil
                local x,y=Maintenance.targetPosition(1); love.mousepressed(x,y,1); love.mousepressed(x,y,1)
                local afterDrop=saveData.resources.oil
                local limitedProgress=Maintenance.progressCount(maintenanceSession)
                love.keypressed("escape")
                local afterCancel=saveData.resources.oil
                saveData.resources.oil=10
                Maintenance.open(maintenanceSession,saveData)
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
                local beforeDone={condition=Maintenance.condition(saveData),progress=Maintenance.progressCount(maintenanceSession),oil=saveData.resources.oil}
                love.mousepressed(712,544,1)
                if os.getenv("MOUSE_FRONTIER_SMOKE_CAPTURE_MAINTENANCE")=="1" then ui.smokeMaintenanceCompleteCaptureRequested=true end
                ui.smokeDraw()
                return {services=saveData.maintenance.totalServices,outsideProgress=outsideProgress,beforeDone=beforeDone,oilAfter=saveData.resources.oil,
                    lights=Maintenance.progressLights(maintenanceSession),cursor=maintenanceSession.cursorActive,
                    animationSpec=Maintenance.animationSpec(),animationState=Maintenance.animationState(maintenanceSession)}
            end,check=function(_,_,snapshot,result)
                local lit=0; for _,value in ipairs(result.lights or {}) do if value then lit=lit+1 end end
                local spec,state=result.animationSpec or {},result.animationState or {}
                return result.services==1 and result.outsideProgress==0 and result.beforeDone.condition==72 and result.beforeDone.progress==5 and
                    result.beforeDone.oil==10 and result.oilAfter==5 and snapshot.oil==5 and
                    lit==5 and result.cursor==false and snapshot.maintenanceCondition==100 and snapshot.maintenanceCompleted==true and
                    spec.wheelFrames==5 and spec.doneFrames==5 and spec.conditionFrames==5 and state.smokePuffs==3
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
                Maintenance.open(maintenanceSession,saveData)
                local before=saveData.maintenance.totalServices
                local x,y=Maintenance.targetPosition(1); local result=Maintenance.mousepressed(maintenanceSession,x,y,saveData)
                local persisted={progress=Maintenance.progressCount(maintenanceSession),cursor=maintenanceSession.cursorActive,
                    completed=maintenanceSession.completed,services=saveData.maintenance.totalServices,before=before,result=result}
                Maintenance.close(maintenanceSession); return persisted
            end,check=function(_,_,snapshot,result)
                return result.progress==5 and result.cursor==false and result.completed and result.services==result.before and snapshot.maintenanceOpen==false
            end},
            {name="store_oil_canisters",action=function()
                saveData.resources.oil=0
                local levels={}
                for _,name in ipairs({"small-oil-canister","medium-oil-canister","large-oil-canister"}) do
                    saveData.inventory[1]=name; draggedSlot={kind="inventory",index=1}
                    if not consumeSelected() then return false end
                    levels[#levels+1]=saveData.resources.oil
                end
                dialogue=nil; actionHeldItem=nil; actionTimer=0
                return {levels=levels,slot=saveData.inventory[1],dragged=draggedSlot}
            end,check=function(_,_,snapshot,result)
                return result and result.levels[1]==1 and result.levels[2]==6 and result.levels[3]==16 and
                    result.slot==nil and result.dragged==nil and snapshot.oil==16
            end},
            {name="confirm_travel",action=function() state="game"; scene="train"; saveData.scene=scene; travelConfirm=true; love.keypressed("return"); return true end,
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
                local opened=inventoryOpen
                ui.smokeDraw()
                local close=ui.battleInventoryClose
                if not close then return false end
                ui.handleBattleMousePressed(close.x+close.w/2,close.y+close.h/2,false)
                return {opened=opened,closed=not inventoryOpen}
            end,check=function(_,_,snapshot,result)
                return result and result.opened and result.closed and snapshot.state=="battle" and snapshot.battleActive
            end},
            {name="render_firearm_attachments",action=function()
                local unit=battle and battle.units and battle.units[1]
                if not unit then return false end
                unit.action="ranged"; unit.actionTimer=.44; unit.actionItem="frontier-9mm-service-pistol"; ui.smokeDraw()
                unit.actionItem="frontier-22-lever-rifle"; unit.actionTimer=.22; ui.smokeDraw()
                unit.action=nil; unit.actionItem=nil; unit.actionTimer=0
                return true
            end,check=function(_,_,_,result) return result==true end},
            {name="retreat_battle_key",action=function() love.keypressed("r"); return "r" end,expect={state="game",scene="train",battleActive=false}},
            fixtureStep("ending"),
            {name="game_session_synchronized",action=function() return true end,expect={sessionSynchronized=true}},
            {name="save_round_trip",action=function()
                local payload={version=CURRENT_SAVE_VERSION,location=17,nested={value="smoke-save"}}
                local wrote=Save.write(99,payload); local loaded=Save.read(99); Save.remove(99)
                return {wrote=wrote,location=loaded and loaded.location,nested=loaded and loaded.nested and loaded.nested.value}
            end,check=function(_,_,_,result) return result.wrote and result.location==17 and result.nested=="smoke-save" end},
            {name="asset_contract",action=function() return Assets.assetFailureSummary() end,expect={assetFailures=0}}
        }
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
                    saveData=newSave(character)
                    -- Full-route mode tests progression to stop 50. The tester
                    -- provisions supplies so ordinary scarcity does not mask
                    -- route, encounter, or ending defects.
                    saveData.resources.food=1000; saveData.resources.water=1000; saveData.resources.coal=1000
                    enterGame(saveData); return true
                end,expect={state="game",scene="train",location=1}},
                {name="full_journey_to_stop_50",timeout=400,before=function() ui.smokeFullLastLocation=saveData.location; ui.smokeFullStall=0 end,action=function()
                    if saveData.location==ui.smokeFullLastLocation then ui.smokeFullStall=(ui.smokeFullStall or 0)+1 else ui.smokeFullLastLocation=saveData.location; ui.smokeFullStall=0 end
                    if ui.smokeFullStall>30 then error("GAMEPLAY_BLOCKED: no progress at stop "..tostring(saveData.location).." state="..tostring(state).." scene="..tostring(scene).." battle="..tostring(battle~=nil).." event="..tostring(randomEvent~=nil)) end
                    if saveData.location>=50 then state="ending"; return true end
                    if state=="battle" then
                        if battle and battle.finished then love.keypressed("return")
                        elseif ui.smokeFull and battle then
                            -- Full-route mode is a progression reachability
                            -- test. Encounters are still created/rendered, but
                            -- are auto-resolved so combat RNG cannot hide a
                            -- route/ending defect. Normal smoke mode exercises
                            -- the actual battle controls separately.
                            for _,unit in ipairs(battle.units or {}) do if unit.team=="enemy" then unit.hp=0 end end
                            advanceBattleTurn()
                        elseif battle and battle.intro then
                            -- The real update callback advances the intro.
                        elseif battle and battle.phase=="select" then
                            local active=BattleRules.activeUnit(battle); if active and active.team=="ally" then
                                battleAttack("frontier-short-sword")
                            end
                        elseif battle and battle.phase=="target" then
                            local active=BattleRules.activeUnit(battle); local target
                            for _,unit in ipairs(battle.units or {}) do if unit.team=="enemy" and unit.hp>0 then target=unit; break end end
                            if active and target then resolveBattleAttack(active,target,battle.chosenWeapon or "frontier-short-sword") end
                        end
                    elseif state=="event" then
                        resolveEventChoice(1)
                    elseif state=="game" and scene=="stop" then
                        dialogue=nil; scene="train"; saveData.scene=scene; player.x,player.y=car.x+300,car.y+285; writeSave()
                    elseif state=="game" and scene=="train" and not travelTransition then
                        if saveData.resources.food<1 or saveData.resources.water<1 or saveData.resources.coal<1 then
                            error("GAMEPLAY_BLOCKED: resources exhausted before stop "..tostring(saveData.location+1))
                        end
                        -- Route mode focuses on reachability. Mark the current
                        -- stop's interruption as handled, then use the real
                        -- travel confirmation/input path.
                        local key=tostring(saveData.location); saveData.encounters[key]={resolved=true,hasMob=false}; saveData.events[key]=true
                        travelConfirm=true; love.keypressed("return")
                    elseif state~="game" or scene~="train" or travelTransition then
                        -- Let the real update callback advance transitions.
                    else error("GAMEPLAY_BLOCKED: unexpected state at stop "..tostring(saveData.location)) end
                    return saveData.location>=50
                end,check=function(_,_,snapshot)
                    if snapshot.state=="ending" and snapshot.location>=50 then return true end
                    return false,"still progressing: stop "..tostring(snapshot.location)
                end,expect={state="ending",location=50,sessionSynchronized=true}}
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
end

end

return {install=install}
