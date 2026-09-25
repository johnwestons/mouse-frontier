local WorldView=require("game.world_view")
local Scene=require("game.last_stand_scene")
local Shootout=require("game.last_stand_shootout")
local FirstAid=require("game.first_aid")
local WorldPause=require("game.world_pause")
local FirstPerson=require("game.first_person_shooting")
local Tuning=require("game.last_stand_tuning")
local CharacterMotion=require("game.character_motion")

local Quest={}
local VERSION=1

local OFFER_LINES={
    "Objective: defend the farmhouse from the railway gang at the relay depot.",
    "Wounded defenders: backyard. Firing positions: two front windows.",
    "Accept to follow the scout to the farmhouse and begin the defense.",
    "Relay distance: 300 meters. Defense target: three minutes and reduced enemy morale.",
    "Loan weapon and ammunition available from Guard Fox. Press L to borrow during the shootout.",
}

local VALID_STATES={
    waiting=true,
    declined=true,
    paused=true,
    escort=true,
    backyard=true,
    interior=true,
    shootout=true,
    aftermath=true,
    returning=true,
    complete=true,
}

local function required(context,name,expected)
    local value=context[name]
    assert(value~=nil,"last stand quest requires "..name)
    if expected then assert(type(value)==expected,"last stand quest "..name.." must be a "..expected) end
    return value
end

local function pointIn(x,y,rx,ry,rw,rh)
    return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh
end

local function offerButtons(width,height)
    return width/2-230,height-118,210,50,width/2+20,height-118,210,50
end

local function mainButton(width,height)
    return width/2-170,height-118,340,50
end

local function modalPanel(title,text,width,height,accent)
    love.graphics.setColor(0,0,0,.62)
    love.graphics.rectangle("fill",0,0,width,height)
    local x,y,w,h=width/2-310,height/2-190,620,380
    love.graphics.setColor(.075,.048,.028,.97)
    love.graphics.rectangle("fill",x,y,w,h,14,14)
    love.graphics.setColor(accent or .82,.55,.23,1)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line",x,y,w,h,14,14)
    love.graphics.setColor(1,.84,.55,1)
    love.graphics.printf(title,x+28,y+30,w-56,"center")
    love.graphics.setColor(.93,.87,.75,1)
    love.graphics.printf(text,x+54,y+88,w-108,"center")
end

local function ensureQuest(data)
    if type(data.lastStand)~="table" then data.lastStand={} end
    local quest=data.lastStand
    quest.version=VERSION
    quest.state=VALID_STATES[quest.state] and quest.state or "waiting"
    quest.holdElapsed=math.max(0,tonumber(quest.holdElapsed) or 0)
    quest.kills=math.max(0,math.floor(tonumber(quest.kills) or 0))
    quest.enemyMorale=math.max(0,math.min(100,tonumber(quest.enemyMorale) or 100))
    quest.positionIntegrity=math.max(0,math.min(100,tonumber(quest.positionIntegrity) or 100))
    quest.loanAmmo=math.max(0,math.floor(tonumber(quest.loanAmmo) or 0))
    quest.loanActive=quest.loanActive==true
    quest.rewardClaimed=quest.rewardClaimed==true
    return quest
end

function Quest.new(context)
    assert(type(context)=="table","last stand quest requires an explicit context")
    local runtime=required(context,"runtime","table")
    local Catalog=required(context,"catalog","table")
    local writeSave=required(context,"writeSave","function")
    local characterImages=required(context,"characterImages","table")
    local characterWalkImages=context.characterWalkImages or {}
    local getCharacterAnimations=context.getCharacterAnimations or function() return {} end
    local mobileMovement=context.mobileMovement or function() return 0,0 end
    local mobileSprinting=context.mobileSprinting or function() return false end
    local width=required(context,"width","number")
    local height=required(context,"height","number")

    local service={}
    local resourcesActive=false

    local function releaseResources()
        if not resourcesActive then return end
        FirstPerson.release()
        Scene.release()
        resourcesActive=false
    end

    local function save() return writeSave() end

    local function busy()
        return WorldPause.isPaused(runtime,context.ui,context.maintenanceSession)
            or runtime.battle or runtime.encounter or runtime.sleeping
    end

    local function playerVisual()
        local data=runtime.saveData
        if not data then return nil end
        return {
            image=characterImages[data.character],
            character=data.character,
            animations=getCharacterAnimations(),
            walkImage=characterWalkImages[data.character],
            clock=runtime.animationClock or 0,
        }
    end

    local function needsLoan(quest)
        if quest.loanActive and quest.loanAmmo>0 then return false end
        return not Shootout.hasUsableFirearm(runtime.saveData,Catalog)
    end

    local function beginApproach(quest)
        local player=runtime.player
        if not player then return false end
        local direction=(player.x or width/2)<width/2 and 1 or -1
        runtime.lastStand={
            mode="approach",
            capture=false,
            quest=quest,
            clock=0,
            arrival=0,
            scout={
                x=(player.x or width/2)+direction*285,
                y=(player.y or height/2)+34,
            },
        }
        return true
    end

    local function showOffer(state)
        state.mode="offer"
        state.capture=true
        state.offerPage=state.offerPage or 1
        state.arrival=1
    end

    local function enterScene(state,mode)
        state.aimTouch=nil; state.aimTouchSession=nil
        state.mode=mode
        state.capture=true
        state.scene=state.scene or Scene.new(mode,state.quest)
        Scene.change(state.scene,mode)
        state.quest.state=mode
        state.notice=nil
        save()
    end

    local function accept(state)
        local quest=state.quest
        quest.state="escort"
        quest.originStop=runtime.saveData.location
        quest.returnX=runtime.player and runtime.player.x or width/2
        quest.returnY=runtime.player and runtime.player.y or height/2
        quest.holdElapsed=0
        quest.kills=0
        quest.enemyMorale=100
        quest.positionIntegrity=100
        quest.loanAmmo=0
        quest.loanActive=false
        quest.rewardClaimed=false
        quest.weaponSession=nil
        quest.weaponSessions=nil
        quest.targets=nil
        quest.impacts=nil
        quest.completedPhase=0
        quest.phaseCheckpoint=0
        quest.intermission=nil
        quest.victory=false
        quest.residentChecked=false
        quest.conversations={}
        state.mode="escort"
        state.capture=true
        state.clock=0
        state.reducedMotion=runtime.saveData.accessibility and runtime.saveData.accessibility.reducedMotion==true
        save()
    end

    local function decline(state)
        local quest=state.quest
        quest.state="declined"
        quest.declinedStop=runtime.saveData.location
        state.mode="approach"
        state.capture=false
        state.manualOffer=true
        runtime.dialogue={speaker="Otter Scout",text="Defense declined. The scout remains available.",timer=3}
        save()
    end

    local function grantLoan(state)
        local quest=state.quest
        local first=not quest.loanActive
        quest.loanActive=true
        quest.loanAmmo=math.max(quest.loanAmmo,first and 48 or 12)
        state.notice={
            text=first and "Guard Fox lends you a Frontier .22 lever rifle and 48 rounds." or "Guard Fox passes you another pouch of .22 ammunition.",
            timer=3.6,
        }
        save()
    end

    local function beginShootout(state,windowId)
        state.handoff=nil
        state.scene.handoff=nil
        state.quest.intermission=nil
        state.quest.lastWindow=windowId
        state.quest.state="shootout"
        state.mode="shootout"
        state.capture=true
        state.shootout=Shootout.new(state.quest,runtime.saveData,Catalog,windowId,width,height)
        save()
    end

    local function requestWindow(state,windowId)
        if state.handoff or state.quest.victory then return end
        state.handoff={window=windowId,elapsed=0}
        state.scene.handoff=state.handoff
        state.notice={text=windowId=="wide" and "Wide firing position selected."
            or "Narrow firing position selected.",timer=2.5}
    end

    local function finishTreatment(state,result)
        if not result then return end
        if result=="complete" then
            state.quest.woundedTreated=true
            state.quest.positionIntegrity=math.min(100,state.quest.positionIntegrity+12)
            state.notice={text="The dressing holds. The defender can rest, and another pair of paws is free to help.",timer=5}
        end
        if result=="complete" or result=="cancelled" then state.treatment=nil end
        save()
    end

    local awardVictory,beginReturn
    local function handleSceneAction(state)
        local action=Scene.action(state.scene,needsLoan(state.quest))
        if not action then return false end
        if action.id=="enter-interior" then enterScene(state,"interior")
        elseif action.id=="exit-backyard" then enterScene(state,"backyard")
        elseif action.id=="borrow-rifle" then grantLoan(state)
        elseif action.id=="window-wide" then requestWindow(state,"wide")
        elseif action.id=="window-tall" then requestWindow(state,"tall")
        elseif action.id=="talk-fox" then
            if state.quest.victory and not state.quest.rewardClaimed and state.quest.residentChecked then
                awardVictory(state)
            else
                state.notice={text=state.quest.victory and (state.quest.rewardClaimed
                    and "Defense complete. Return with the scout when ready."
                    or "Enemies retreating. Check on a resident, then return to Guard Fox.")
                    or "Both windows are available. Press L to borrow the spare rifle.",timer=5}
            end
        elseif action.id=="talk-gecko" then
            state.quest.residentChecked=state.quest.victory or state.quest.residentChecked
            state.notice={text=state.quest.victory and "Resident checked. Defense complete."
                or "The narrow window provides more cover. Duck to avoid incoming fire.",timer=5}
        elseif action.id=="talk-scout" then
            state.quest.residentChecked=state.quest.victory or state.quest.residentChecked
            state.notice={text=state.quest.victory and "Resident checked. Return route: backyard gate."
                or "Wounded defenders: backyard. Return route: backyard gate.",timer=5}
        elseif action.id=="help-wounded" then
            state.quest.residentChecked=state.quest.victory or state.quest.residentChecked
            if state.quest.woundedTreated then
                state.notice={text="The defender is resting comfortably. Your dressing is holding.",timer=4}
            else
                state.quest.treatmentProgress=state.quest.treatmentProgress or {}
                state.treatment=FirstAid.new({progress=state.quest.treatmentProgress,
                    location=state.quest.originStop,itemName="house medical supplies"})
            end
        elseif action.id=="return-stop" then
            if state.quest.victory then
                if state.quest.rewardClaimed then beginReturn(state)
                else state.notice={text="Check on a resident and speak to Guard Fox before leaving. They want to thank you.",timer=4} end
                return true
            end
            state.quest.state="paused"
            state.quest.loanActive=false
            state.quest.loanAmmo=0
            if state.quest.weaponSession and state.quest.weaponSession.borrowed then state.quest.weaponSession=nil end
            if state.quest.weaponSessions then state.quest.weaponSessions.loan=nil end
            runtime.lastStand=nil
            releaseResources()
            runtime.dialogue={speaker="Otter Scout",text="Defense paused. Return to the scout to resume.",timer=4}
            save()
        end
        state.quest.conversations=state.quest.conversations or {}
        state.quest.conversations[action.id]=true
        save()
        return true
    end

    awardVictory=function(state)
        local quest=state.quest
        if not quest.rewardClaimed then
            local bonus=quest.woundedTreated and quest.positionIntegrity>=40 and 8 or 0
            quest.rewardScrap=28+bonus
            runtime.saveData.scrap=math.max(0,tonumber(runtime.saveData.scrap) or 0)+quest.rewardScrap
            runtime.saveData.goodwill=math.max(0,math.floor(tonumber(runtime.saveData.goodwill) or 0))+3
            runtime.saveData.resources=runtime.saveData.resources or {}
            runtime.saveData.resources.food=math.max(0,tonumber(runtime.saveData.resources.food) or 0)+2
            quest.rewardClaimed=true
        end
        quest.loanActive=false
        quest.loanAmmo=0
        quest.weaponSession=nil
        quest.weaponSessions=nil
        quest.state="aftermath"
        state.mode="aftermath"
        state.capture=true
        state.scene=Scene.new("interior",quest)
        state.shootout=nil
        state.clock=0
        save()
    end

    beginReturn=function(state)
        state.quest.state="returning"
        state.mode="returning"
        state.capture=true
        state.clock=0
        save()
    end

    local function completeReturn(state)
        local quest=state.quest
        quest.state="complete"
        quest.completed=true
        quest.completedAtStop=runtime.saveData.location
        if runtime.player then
            runtime.player.x=tonumber(quest.returnX) or runtime.player.x
            runtime.player.y=tonumber(quest.returnY) or runtime.player.y
        end
        runtime.lastStand=nil
        releaseResources()
        runtime.dialogue={
            speaker="Otter Scout",
            text="Defense complete.",
            timer=4,
        }
        save()
    end

    local function restore(quest)
        local mode=quest.state
        if mode=="escort" then mode="backyard" end
        if mode=="shootout" then
            mode="interior"
            quest.state="interior"
        end
        if mode=="returning" then mode="aftermath"; quest.state="aftermath" end
        local state={
            mode=mode,
            capture=true,
            quest=quest,
            clock=0,
            scene=(mode=="backyard" or mode=="interior" or mode=="aftermath") and Scene.new(mode=="aftermath" and "interior" or mode,quest) or nil,
        }
        runtime.lastStand=state
        return state
    end

    local function canOffer(quest)
        if quest.state~="waiting" and quest.state~="declined" and quest.state~="paused" then return false end
        local data=runtime.saveData
        if runtime.state~="game" or runtime.scene~="stop" or not data or not data.stopped then return false end
        if data.location<4 or data.location>=50 or busy() then return false end
        if quest.state=="paused" and quest.originStop~=data.location then return false end
        return true
    end

    local controllerButtons={a="e",b="escape",x="r",y="l",start="p",back="tab",leftshoulder="c",rightshoulder="space"}
    local controllerHeld={}
    local controllerADS=false
    local controllerGun
    local function pollController(dt)
        local state=runtime.lastStand
        if not state or not love.joystick then return end
        local pads=love.joystick.getJoysticks()
        local pad=pads[1]
        if not pad or not pad:isGamepad() then
            if controllerADS and state.shootout then Shootout.setADS(state.shootout,false) end
            controllerADS=false; controllerGun=nil
            controllerHeld={}
            if state.scene then state.scene.axisX=0; state.scene.axisY=0 end
            return
        end
        for button,key in pairs(controllerButtons) do
            local down=pad:isGamepadDown(button)
            if down and not controllerHeld[button] then
                local action=key
                if button=="a" then
                    action=state.treatment and "return" or state.mode=="offer" and "y"
                        or (state.mode=="escort" or state.mode=="returning") and "space" or "e"
                end
                service:keypressed(action)
            end
            controllerHeld[button]=down
        end
        state=runtime.lastStand
        if not state then return end
        local function axis(name)
            local value=pad:getGamepadAxis(name)
            return math.abs(value)<.18 and 0 or value
        end
        if state.scene then
            state.scene.axisX=axis("leftx")+(pad:isGamepadDown("dpright") and 1 or 0)-(pad:isGamepadDown("dpleft") and 1 or 0)
            state.scene.axisY=axis("lefty")+(pad:isGamepadDown("dpdown") and 1 or 0)-(pad:isGamepadDown("dpup") and 1 or 0)
        end
        if state.mode=="shootout" and not state.paused then
            local gun=state.shootout.gun
            local aimDX,aimDY=axis("rightx"),axis("righty")
            if aimDX~=0 or aimDY~=0 then
                Shootout.setAim(state.shootout,math.max(0,math.min(width,gun.aimX+aimDX*340*dt)),
                    math.max(0,math.min(height,gun.aimY+aimDY*340*dt)))
            end
            local aiming=pad:getGamepadAxis("triggerleft")>.4
            if aiming~=controllerADS or (aiming and controllerGun~=gun) then Shootout.setADS(state.shootout,aiming) end
            controllerADS=aiming; controllerGun=gun
            if pad:getGamepadAxis("triggerright")>.4 then Shootout.fire(state.shootout,runtime.saveData,width,height,Catalog) end
        elseif state.mode~="shootout" then
            controllerADS=false; controllerGun=nil
        end
    end

    function service:update(dt)
        if runtime.state~="game" or not runtime.saveData then
            runtime.lastStand=nil
            releaseResources()
            return false
        end
        local quest=ensureQuest(runtime.saveData)
        local state=runtime.lastStand
        if not state then
            releaseResources()
            if quest.state=="complete" then return false end
            if quest.state=="escort" or quest.state=="backyard" or quest.state=="interior"
                or quest.state=="shootout" or quest.state=="aftermath" or quest.state=="returning" then
                state=restore(quest)
            elseif canOffer(quest) then
                beginApproach(quest)
                state=runtime.lastStand
                state.manualOffer=quest.state=="declined" or quest.state=="paused"
            else
                return false
            end
        end
        pollController(dt)
        state=runtime.lastStand
        if not state then return false end
        resourcesActive=true
        if state.paused then return true end
        state.clock=(state.clock or 0)+dt
        state.woundFlash=math.max(0,(state.woundFlash or 0)-dt)
        if state.treatment then
            finishTreatment(state,FirstAid.update(state.treatment,dt))
            return true
        end
        if state.notice then
            state.notice.timer=state.notice.timer-dt
            if state.notice.timer<=0 then state.notice=nil end
        end

        if state.mode=="approach" then
            if runtime.scene~="stop" or runtime.state~="game" then runtime.lastStand=nil; releaseResources(); return false end
            if busy() then return false end
            local player=runtime.player
            local dx,dy=(player.x or 0)-state.scout.x,(player.y or 0)-state.scout.y
            local distance=math.sqrt(dx*dx+dy*dy)
            if distance>82 then
                local step=math.min(distance-82,86*dt)
                state.scout.x=state.scout.x+dx/distance*step
                state.scout.y=state.scout.y+dy/distance*step
                state.walkDistance=(state.walkDistance or 0)+step
                state.arrival=0
            else
                state.arrival=(state.arrival or 0)+dt
                if state.arrival>=.55 and not state.manualOffer then showOffer(state) end
            end
            return state.capture
        end
        if state.mode=="offer" then return true end
        if state.mode=="escort" then
            if state.clock>=8 then enterScene(state,"backyard") end
            return true
        end
        if state.mode=="backyard" or state.mode=="interior" then
            state.scene.reducedMotion=runtime.saveData.accessibility and runtime.saveData.accessibility.reducedMotion==true
            state.scene.reducedFlashes=runtime.saveData.accessibility and runtime.saveData.accessibility.reducedFlashes==true
            local mobileX,mobileY=mobileMovement()
            local sprinting=love.keyboard.isDown("lshift","rshift") or mobileSprinting()
            local reports=Scene.update(state.scene,dt,{
                mobileX=mobileX,mobileY=mobileY,sprinting=sprinting,
                speed=runtime.player and runtime.player.speed or 185,
                profile=CharacterMotion.profileFor(runtime.saveData.character),
            })
            if reports>0 and not state.quest.victory then FirstPerson.playReport("frontier-22-lever-rifle",Catalog,runtime.saveData,true) end
            if state.handoff then
                state.handoff.elapsed=state.handoff.elapsed+dt
                if state.handoff.elapsed>=.75 then beginShootout(state,state.handoff.window) end
            end
            return true
        end
        if state.mode=="shootout" then
            local healthBefore=runtime.saveData.health
            local result=Shootout.update(state.shootout,dt,runtime.saveData,Catalog,width,height)
            if runtime.saveData.health~=healthBefore then save() end
            if result=="intermission" then
                local phase=state.shootout.stage
                state.quest.intermission=phase
                enterScene(state,"interior")
                state.notice={text=Tuning.phases[phase].line,timer=8}
                state.shootout=nil
            elseif result=="retreat" then
                local wounded=state.shootout.retreatReason=="wounded"
                if wounded then state.woundFlash=.45 end
                Shootout.retry(state.shootout)
                enterScene(state,"interior")
                state.quest.intermission=Tuning.phase(state.quest.holdElapsed)
                state.notice={text=wounded
                    and "Guard Fox pulls you below the window, badly wounded. Your health is still low. Return to the train to heal before trying again."
                    or "The defenders pull you back. The current phase will restart; earlier progress and eliminations are safe.",timer=7}
                state.shootout=nil
                save()
            elseif result=="victory" then
                state.quest.victory=true
                state.quest.loanActive=false
                state.quest.loanAmmo=0
                state.quest.weaponSession=nil
                state.quest.weaponSessions=nil
                enterScene(state,"interior")
                state.notice={text="Enemies retreating. Check on a resident, then return to Guard Fox.",timer=8}
                state.shootout=nil
                save()
            end
            state.saveTimer=(state.saveTimer or 0)+dt
            if state.saveTimer>=5 then state.saveTimer=0; save() end
            return true
        end
        if state.mode=="aftermath" then return true end
        if state.mode=="returning" then
            if state.clock>=5 then completeReturn(state); return false end
            return true
        end
        return state.capture==true
    end

    function service:keypressed(key)
        local state=runtime.lastStand
        if not state then return false end
        if state.capture and key=="p" then state.paused=not state.paused; save(); return true end
        if state.paused then
            if key=="escape" or key=="return" then state.paused=false end
            return true
        end
        if state.treatment then finishTreatment(state,FirstAid.keypressed(state.treatment,key)); return true end
        if state.handoff then
            if key=="escape" then state.handoff=nil; state.scene.handoff=nil; state.notice=nil end
            return true
        end
        if state.mode=="approach" then
            if key=="e" and state.arrival and state.arrival>0 and not busy() then
                if state.quest.state=="paused" then enterScene(state,"backyard") else showOffer(state) end
                return true
            end
            return false
        end
        if state.mode=="offer" then
            if key=="n" or key=="escape" then decline(state)
            elseif key=="y" then accept(state)
            elseif key=="q" then state.offerPage=4
            elseif key=="f" then state.offerPage=5
            elseif key=="return" or key=="space" then
                if state.offerPage<#OFFER_LINES then state.offerPage=state.offerPage+1 else accept(state) end
            end
            return true
        end
        if state.mode=="escort" or state.mode=="returning" then
            if key=="space" or key=="return" then
                if state.mode=="escort" then enterScene(state,"backyard") else completeReturn(state) end
            end
            return true
        end
        if state.mode=="backyard" or state.mode=="interior" then
            if key=="e" or key=="return" then handleSceneAction(state)
            elseif key=="escape" then
                state.notice={text="The pinned-down critters are counting on you. The back door remains open.",timer=2.5}
            end
            return true
        end
        if state.mode=="shootout" then
            if key=="escape" then
                state.quest.state="interior"
                enterScene(state,"interior")
            elseif key=="r" then Shootout.reload(state.shootout,runtime.saveData)
            elseif key=="l" then Shootout.supply(state.shootout,runtime.saveData,Catalog)
            elseif key=="tab" then Shootout.cycleWeapon(state.shootout,runtime.saveData,Catalog)
            elseif key=="c" then Shootout.setCover(state.shootout,not state.shootout.ducking)
            elseif key=="return" and state.shootout.result=="retreat" then Shootout.retry(state.shootout)
            elseif key=="space" then Shootout.fire(state.shootout,runtime.saveData,width,height,Catalog)
            end
            return true
        end
        if state.mode=="aftermath" and (key=="return" or key=="space" or key=="e") then
            beginReturn(state)
            return true
        end
        if state.mode=="aftermath" and (key=="t" or key=="escape") then enterScene(state,"interior"); return true end
        return state.capture==true
    end

    function service:keyreleased()
        return runtime.lastStand and runtime.lastStand.capture==true or false
    end

    function service:mousepressed(x,y,button,istouch)
        local state=runtime.lastStand
        if not state then return false end
        if state.mode=="approach" and button==1 and state.arrival and state.arrival>0 and not busy() then
            x,y=WorldView.toWorld(x,y)
            if math.abs(x-state.scout.x)<95 and math.abs(y-state.scout.y+60)<100 then return self:keypressed("e") end
        end
        if not state.capture then return false end
        if state.paused then state.paused=false; return true end
        if state.treatment then finishTreatment(state,FirstAid.mousepressed(state.treatment,x,y)); return true end
        if state.handoff then return true end
        if state.mode=="offer" and button==1 then
            local ax,ay,aw,ah,dx,dy,dw,dh=offerButtons(width,height)
            if pointIn(x,y,ax,ay,aw,ah) then accept(state)
            elseif pointIn(x,y,dx,dy,dw,dh) then decline(state)
            elseif pointIn(x,y,ax,ay-58,aw,44) then state.offerPage=4
            elseif pointIn(x,y,dx,dy-58,dw,44) then state.offerPage=5
            else state.offerPage=math.min(#OFFER_LINES,state.offerPage+1) end
            return true
        end
        if (state.mode=="backyard" or state.mode=="interior") and button==1 then
            local rx,ry,rw,rh=Scene.actionRect(height)
            if pointIn(x,y,rx,ry,rw,rh) and handleSceneAction(state) then return true end
            Scene.setDestination(state.scene,WorldView.toWorld(x,y))
            return true
        end
        if state.mode=="shootout" then
            if istouch then
                local action=Shootout.touchAction(x,y,width,height)
                if action then
                    if action=="fire" then Shootout.fire(state.shootout,runtime.saveData,width,height,Catalog)
                    elseif action=="ads" then Shootout.setADS(state.shootout,not state.shootout.gun.ads)
                    else self:keypressed(action) end
                    return true
                end
                if state.shootout.result=="retreat" or Shootout.needsSupply(state.shootout,runtime.saveData) then
                    return Shootout.mousepressed(state.shootout,x,y,1,runtime.saveData,Catalog,width,height)
                end
                Shootout.setTouchAim(state.shootout,x,y,width,height)
                return true
            end
            Shootout.setAim(state.shootout,x,y)
            return Shootout.mousepressed(state.shootout,x,y,button,runtime.saveData,Catalog,width,height)
        end
        if state.mode=="aftermath" and button==1 then
            local rx,ry,rw,rh=mainButton(width,height)
            if pointIn(x,y,rx,ry,rw,rh) then beginReturn(state) end
            if pointIn(x,y,rx,ry-58,rw,44) then enterScene(state,"interior") end
            return true
        end
        if (state.mode=="escort" or state.mode=="returning") and button==1 then return self:keypressed("space") end
        return true
    end

    function service:mousemoved(x,y)
        local state=runtime.lastStand
        if not state or not state.capture then return false end
        if state.paused then return true end
        if state.treatment then finishTreatment(state,FirstAid.mousemoved(state.treatment,x,y)); return true end
        if state.mode=="shootout" then Shootout.setAim(state.shootout,x,y) end
        return true
    end

    function service:mousereleased(x,y,button)
        local state=runtime.lastStand
        if not state or not state.capture then return false end
        if state.treatment then FirstAid.mousereleased(state.treatment,x,y); return true end
        if state.mode=="shootout" then return Shootout.mousereleased(state.shootout,button) end
        return true
    end

    function service:wheelmoved()
        return runtime.lastStand and runtime.lastStand.capture==true or false
    end

    function service:isCapturing()
        return runtime.lastStand and runtime.lastStand.capture==true or false
    end

    function service:zoomField(x,y)
        local state=runtime.lastStand
        if not state or not state.capture then return nil end
        if state.mode=="shootout" and not state.paused and not state.treatment and not state.handoff
            and state.shootout.result~="retreat" and not Shootout.needsSupply(state.shootout,runtime.saveData) then
            if Shootout.touchAction(x,y,width,height) then return nil end
            return state.shootout,true
        end
        return state,false
    end

    function service:touchpressed(id,x,y)
        local state=runtime.lastStand
        if not state then return false end
        state.touchControls=true
        if state.mode=="shootout" then
            state.shootout.touchControls=true
            if state.aimTouchSession~=state.shootout then state.aimTouch=nil; state.aimTouchSession=state.shootout end
            if not state.paused and not state.treatment and not state.handoff
                and not Shootout.touchAction(x,y,width,height) and state.shootout.result~="retreat"
                and not Shootout.needsSupply(state.shootout,runtime.saveData) then
                if state.aimTouch then
                    if state.aimTouch~=id then Shootout.fire(state.shootout,runtime.saveData,width,height,Catalog) end
                else
                    state.aimTouch=id
                    Shootout.setTouchAim(state.shootout,x,y,width,height)
                end
                return true
            end
        end
        return self:mousepressed(x,y,1,true)
    end

    function service:touchmoved(id,x,y)
        local state=runtime.lastStand
        if not state or not state.capture then return false end
        if state.mode=="shootout" and not state.treatment then
            if not state.paused and state.aimTouch==id and state.aimTouchSession==state.shootout then
                Shootout.setTouchAim(state.shootout,x,y,width,height)
            end
            return true
        end
        return self:mousemoved(x,y)
    end

    function service:touchreleased(id,x,y)
        local state=runtime.lastStand
        if not state then return false end
        if state.aimTouch==id then state.aimTouch=nil end
        return self:mousereleased(x,y,1)
    end

    function service:focus(focused)
        if not focused and runtime.lastStand and runtime.lastStand.capture then
            runtime.lastStand.aimTouch=nil
            runtime.lastStand.paused=true
            save()
        end
    end

    local function drawNotice(state)
        if not state.notice then return end
        love.graphics.setColor(.055,.035,.020,.94)
        love.graphics.rectangle("fill",width/2-285,height-126,570,48,8,8)
        love.graphics.setColor(.96,.84,.63,1)
        love.graphics.printf(state.notice.text,width/2-270,height-110,540,"center")
    end

    local function drawState()
        local state=runtime.lastStand
        if not state then return end
        if state.mode=="approach" then Scene.drawApproach(state); return end
        if state.mode=="offer" then
            Scene.drawApproach(state)
            modalPanel("A LIGHT IN THE WINDOWS",OFFER_LINES[state.offerPage],width,height)
            local ax,ay,aw,ah,dx,dy,dw,dh=offerButtons(width,height)
            love.graphics.setColor(.46,.25,.10,1)
            love.graphics.rectangle("fill",ax,ay,aw,ah,8,8)
            love.graphics.setColor(.27,.20,.16,1)
            love.graphics.rectangle("fill",dx,dy,dw,dh,8,8)
            love.graphics.setColor(1,.88,.64,1)
            love.graphics.printf("ACCEPT  [Y]",ax,ay+17,aw,"center")
            love.graphics.printf("NOT NOW  [N]",dx,dy+17,dw,"center")
            love.graphics.setColor(.18,.12,.075,1)
            love.graphics.rectangle("fill",ax,ay-58,aw,44,8,8)
            love.graphics.rectangle("fill",dx,dy-58,dw,44,8,8)
            love.graphics.setColor(1,.88,.64,1)
            love.graphics.printf("DEFENSE OBJECTIVE  [Q]",ax,ay-43,aw,"center")
            love.graphics.printf("WEAPON SUPPLIES  [F]",dx,dy-43,dw,"center")
            love.graphics.setColor(.82,.70,.52,1)
            love.graphics.printf("Page "..state.offerPage.." / "..#OFFER_LINES,width/2-80,height/2+116,160,"center")
            return
        end
        if state.mode=="escort" then Scene.drawTransition(state,width,height,false,playerVisual()); return end
        if state.mode=="backyard" or state.mode=="interior" then
            Scene.draw(state.scene,width,height,playerVisual(),needsLoan(state.quest))
            drawNotice(state)
            if state.treatment then
                local assets={}
                for name,value in pairs(context.scenery and context.scenery.firstAidAssets or {}) do assets[name]=value end
                assets.npc=context.npcImages and context.npcImages["guard-fox.png"]
                FirstAid.draw(state.treatment,{},assets)
            end
            return
        end
        if state.mode=="shootout" then
            Shootout.draw(state.shootout,runtime.saveData,width,height)
            return
        end
        if state.mode=="aftermath" then
            Scene.draw(state.scene,width,height,playerVisual(),false)
            modalPanel(
                "THE RELAY GOES QUIET",
                "The gang has withdrawn. The defenders lower their weapons one by one. Reward: "..(state.quest.rewardScrap or 28).." scrap, 3 goodwill, and 2 food.",
                width,height,.64
            )
            local rx,ry,rw,rh=mainButton(width,height)
            love.graphics.setColor(.48,.26,.10,1)
            love.graphics.rectangle("fill",rx,ry,rw,rh,8,8)
            love.graphics.setColor(1,.88,.64,1)
            love.graphics.printf("RETURN TO THE STOP  [E]",rx,ry+17,rw,"center")
            love.graphics.setColor(.27,.20,.16,1)
            love.graphics.rectangle("fill",rx,ry-58,rw,44,8,8)
            love.graphics.setColor(1,.88,.64,1)
            love.graphics.printf("STAY A LITTLE LONGER  [T]",rx,ry-43,rw,"center")
            return
        end
        if state.mode=="returning" then Scene.drawTransition(state,width,height,true,playerVisual()) end
    end

    function service:draw()
        drawState()
        local state=runtime.lastStand
        local accessibility=runtime.saveData and runtime.saveData.accessibility
        if state and (state.woundFlash or 0)>0
            and not (accessibility and (accessibility.reducedFlashes or accessibility.reducedMotion)) then
            love.graphics.push("all")
            love.graphics.setColor(.76,.045,.025,.27*state.woundFlash/.45)
            love.graphics.rectangle("fill",0,0,width,height)
            love.graphics.pop()
        end
        if runtime.lastStand and runtime.lastStand.paused then
            modalPanel("PAUSED","Press P, Enter, or tap to return to the defense.",width,height)
        end
    end

    return service
end

return {new=Quest.new,version=VERSION}
