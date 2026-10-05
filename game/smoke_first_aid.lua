local StopHelp=require("game.stop_help_progression")
local HelpQuest=require("game.help_quest_session")
local Viewport=require("game.viewport")
local UIStyle=require("game.ui_layout")

local function required(context,name,kind)
    local value=context[name]
    assert(type(value)==kind,"first-aid smoke requires "..name.." ("..kind..")")
    return value
end

local function steps(context)
    local game=required(context,"runtime","table")
    local ui=required(context,"ui","table")
    local character=required(context,"character","string")
    local newSave=required(context,"newSave","function")
    local enterGame=required(context,"enterGame","function")
    local ensureStopLayout=required(context,"ensureStopLayout","function")
    local update=required(context,"update","function")
    local draw=required(context,"draw","function")
    local presentation=required(context,"presentationRuntime","table")
    local mobileEnabled=required(context,"mobileEnabled","function")
    local getMobileControls=required(context,"getMobileControls","function")
    local serial=0

    local function screenPoint(x,y,aid)
        if aid then
            local point=UIStyle.transformRectFor("firstAid",{x=105,y=40,w=750,h=635},{x=x,y=y,w=0,h=0})
            x,y=point.x,point.y
        end
        local ox,oy,sx,sy=Viewport.transform(960,720)
        return ox+x*sx,oy+y*sy
    end
    local function tap(x,y,aid)
        x,y=screenPoint(x,y,aid)
        if mobileEnabled() then
            serial=serial+1
            local id="smoke-aid-tap-"..serial
            love.touchpressed(id,x,y)
            local controls=getMobileControls()
            assert(aid or not controls.touches[id] or controls.touches[id].kind~="joystick",
                "dialogue Accept touch was captured by a movement control")
            love.touchreleased(id,x,y)
        else love.mousepressed(x,y,1);love.mousereleased(x,y,1) end
    end
    local function drag(startX,positions)
        local x,y=screenPoint(startX,370,true)
        serial=serial+1
        local id="smoke-aid-drag-"..serial
        local touch=mobileEnabled()
        if touch then love.touchpressed(id,x,y) else love.mousepressed(x,y,1) end
        for _,position in ipairs(positions) do
            local nx,ny=screenPoint(position,370,true)
            if touch then love.touchmoved(id,nx,ny,nx-x,ny-y)
            else love.mousemoved(nx,ny,nx-x,ny-y) end
            x,y=nx,ny
        end
        if touch then love.touchreleased(id,x,y) else love.mousereleased(x,y,1) end
    end
    local function accept(request)
        -- Use the existing neutral request UI, then its actual Accept control.
        game.questOffer={kind="aid"}
        game.dialogue={speaker="TASK",text=request.text,choice=true,timer=math.huge}
        draw()
        if mobileEnabled() then
            local controls=getMobileControls()
            assert(not controls:isMovementActive() and controls:isGameplayActive(),
                "dialogue must block joystick movement while retaining its contextual action")
        end
        local control=assert(ui.questAccept,"first-aid offer Accept control was not drawn")
        tap(control.x+control.w/2,control.y+control.h/2)
    end
    local function completed(data,request,health)
        local quest=assert(HelpQuest.get(data,request.sessionId))
        assert(game.firstAid==nil and request.complete and quest.state=="resolved" and quest.rewardClaimed,
            "successful treatment did not close and resolve the quest")
        assert(data.inventory[1]==nil and data.inventory[2]=="water-bottle","treatment did not consume exactly its medical supply")
        assert(data.goodwill==3 and #data.helpHistory==1,"treatment did not award exactly three goodwill once")
        assert(data.health==health,"NPC treatment unexpectedly changed player health")
        for _=1,10 do update(.05) end
        assert(data.goodwill==3 and #data.helpHistory==1,"treatment reward repeated during subsequent updates")
        return {completed=true,medicalItemsUsed=1,goodwill=3,rewardOnce=true,playerHealth=health}
    end

    local function fixture(seed,run)
        local previous={save=game.saveData,slot=game.selectedSlot,player=game.player,state=game.state,scene=game.scene,
            options=ui.optionsOpen,escape=ui.escMenuOpen,radio=ui.radioOpen,mobileMenu=ui.mobileMenuOpen}
        local randomState=love.math.getRandomState()
        local ok,result=xpcall(function()
            game.selectedSlot=nil
            ui.optionsOpen=false;ui.escMenuOpen=false;ui.radioOpen=false;ui.mobileMenuOpen=false
            love.math.setRandomSeed(seed)
            local data=newSave(character)
            data.location=2;data.scene="stop"
            enterGame(data);data=game.saveData
            data.health=10;data.inventory={"field-bandage-roll","water-bottle"}
            data.goodwill=0;data.helpHistory={};data.helpQuestSessions={}
            local layout=ensureStopLayout()
            local npc=assert(data.currentNPC,"first-aid fixture has no NPC")
            layout.npcOffers[npc]="aid";layout.offer="aid"
            local request=assert(StopHelp.ensureRequest(layout,npc,"aid",2,data))
            presentation.resetCamera(true)
            accept(request)
            assert(game.firstAid and game.firstAid.phase==1,"Accept did not open a fresh first-aid session"
                .." scene="..tostring(game.scene).." dialogue="..tostring(game.dialogue and game.dialogue.text)
                .." offer="..tostring(game.questOffer and game.questOffer.kind).." pose="..tostring(game.poseMenu)
                .." inventory="..tostring(game.inventoryOpen).." menu="..tostring(ui.mobileMenuOpen))
            assert(data.inventory[1]=="field-bandage-roll" and data.goodwill==0,"accepting treatment prematurely charged the item or awarded goodwill")
            local report=run(data,request,10)
            report.input=mobileEnabled() and "production touch callbacks" or "production mouse callbacks"
            report.ok=true
            return report
        end,debug.traceback)
        game.selectedSlot=nil
        local restored,restoreError=xpcall(function()
            local controls=getMobileControls()
            if controls then controls:cancelAll() end
            enterGame(previous.save)
            presentation.resetCamera(true)
        end,debug.traceback)
        game.saveData=previous.save;game.player=previous.player;game.scene=previous.scene;game.state=previous.state
        game.selectedSlot=previous.slot
        ui.optionsOpen=previous.options;ui.escMenuOpen=previous.escape
        ui.radioOpen=previous.radio;ui.mobileMenuOpen=previous.mobileMenu
        love.math.setRandomState(randomState)
        if not ok then error(result) end
        if not restored then error("first-aid fixture cleanup: "..tostring(restoreError)) end
        return result
    end
    local function scenario(name,seed,run)
        return {name=name,action=function() return fixture(seed,run) end,
            check=function(_,_,_,result) return type(result)=="table" and result.ok==true end}
    end

    return {
        scenario("first_aid_keyboard_treatment",501,function(data,request,health)
            love.keypressed("6")
            assert(game.firstAid and game.firstAid.phase==1,"wrong keyboard step advanced treatment")
            for phase=1,6 do
                assert(game.firstAid and game.firstAid.phase==phase,"keyboard treatment skipped or lost a phase")
                draw();love.keypressed(tostring(phase))
            end
            local report=completed(data,request,health)
            report.keyboard=true
            return report
        end),
        scenario("first_aid_physical_treatment",502,function(data,request,health)
            local session=game.firstAid
            tap(300,300,true)
            assert(session.phase==1,"click outside the injury advanced treatment")
            tap(512,420,true);tap(480,370,true)
            for _=1,20 do if session.phase~=2 then break end;update(.05) end
            assert(session.phase==3 and session.progress.pourTime>=.75,"timed disinfectant did not advance treatment")
            draw();drag(410,{550,410,550,410})
            assert(session.phase==4 and session.progress.rubTurns>=3,"rag gesture did not clean the injury")
            local swipes={};for i=1,12 do swipes[i]=i%2==0 and 410 or 550 end
            draw();drag(410,swipes)
            assert(session.phase==5 and #session.progress.ointmentTrail>=12,"ointment gestures did not cover the injury")
            draw();tap(480,370,true)
            assert(session.phase==6 and session.progress.gauzePlaced,"gauze input did not begin wrapping")
            draw();drag(398,{562,398,562})
            assert(session.progress.wrapPasses==3,"wrap gestures did not complete all three passes")
            local report=completed(data,request,health)
            report.gestures=true;report.touch=mobileEnabled()
            return report
        end),
        scenario("first_aid_pause_resume_is_free",503,function(data,request,health)
            love.keypressed("1");love.keypressed("2")
            draw();drag(410,{500})
            local progress=game.firstAid.progress
            assert(progress.phase==3 and progress.rubDistance>0,"partial treatment fixture did not make real gesture progress")
            tap(480,629,true)
            local quest=assert(HelpQuest.get(data,request.sessionId))
            assert(game.firstAid==nil and quest.paused and not request.complete,"Pause did not leave treatment retryable")
            assert(data.inventory[1]=="field-bandage-roll" and data.goodwill==0 and data.health==health,
                "pausing treatment consumed the item, awarded goodwill, or changed player health")
            local distance=progress.rubDistance
            accept(request)
            assert(game.firstAid and game.firstAid.phase==3 and game.firstAid.progress.rubDistance==distance,
                "accepting the paused request lost treatment progress")
            for phase=3,6 do draw();love.keypressed(tostring(phase)) end
            local report=completed(data,request,health)
            report.pausedWithoutCost=true;report.progressRestored=true
            return report
        end),
    }
end

return {steps=steps}
