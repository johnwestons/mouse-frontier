local FirstPerson=require("game.first_person_shooting")
local WindowScene=require("game.window_scene")
local Tuning=require("game.last_stand_tuning")

local Shootout={}

local function randomRange(low,high)
    local value=love.math and love.math.random and love.math.random() or math.random()
    return low+(high-low)*value
end

local function clamp(value,low,high) return math.max(low,math.min(high,value)) end

local stageFor=Tuning.phase

local function targetFrame(target)
    if target.status=="appearing" or target.status=="hiding" then return 1 end
    if target.status=="exposed" then return 2 end
    if target.status=="firing" then return 3 end
    if target.status=="dying" then
        local progress=1-clamp(target.timer/.72,0,1)
        return math.min(7,4+math.floor(progress*4))
    end
    return 0
end

function Shootout.hasUsableFirearm(data,Catalog)
    return FirstPerson.hasUsableFirearm(data,Catalog)
end

function Shootout.needsSupply(state,data)
    return FirstPerson.needsSupply(state.gun,data,state.quest)
end

function Shootout.new(quest,data,Catalog,windowId,width,height)
    quest.holdElapsed=math.max(0,tonumber(quest.holdElapsed) or 0)
    quest.kills=math.max(0,math.floor(tonumber(quest.kills) or 0))
    quest.enemyMorale=clamp(tonumber(quest.enemyMorale) or 100,0,100)
    quest.positionIntegrity=clamp(tonumber(quest.positionIntegrity) or 100,0,100)
    quest.completedPhase=tonumber(quest.completedPhase) or math.max(0,stageFor(quest.holdElapsed)-1)
    quest.phaseCheckpoint=tonumber(quest.phaseCheckpoint) or Tuning.phases[stageFor(quest.holdElapsed)].start
    local state={
        quest=quest,
        windowId=windowId or quest.lastWindow or "wide",
        elapsed=quest.holdElapsed,
        clock=0,
        stage=stageFor(quest.holdElapsed),
        stageBanner=2.4,
        targets={},
        effects={},
        flashes={},
        impacts={},
        enemyShots=0,
        spawnCursor=1,
        result=nil,
        notice=nil,
        reducedMotion=data.accessibility and data.accessibility.reducedMotion==true,
        reducedFlashes=data.accessibility and (data.accessibility.reducedFlashes==true or data.accessibility.reducedMotion==true),
    }
    state.gun=FirstPerson.new(data,Catalog,quest,width,height)
    for index=1,#WindowScene.slots do
        state.targets[index]={
            slot=index,
            atlas=WindowScene.targetAtlases[((index-1)%#WindowScene.targetAtlases)+1],
            status="hidden",
            timer=.35+index*.22,
        }
    end
    if type(quest.targets)=="table" and #quest.targets==#WindowScene.slots then state.targets=quest.targets end
    quest.targets=state.targets
    state.impacts=type(quest.impacts)=="table" and quest.impacts or {}
    quest.impacts=state.impacts
    return state
end

local function activeLimit(state)
    local stage=select(1,stageFor(state.elapsed))
    local base=math.min(state.windowId=="tall" and 4 or 5,Tuning.phases[stage].active)
    return math.max(1,math.ceil(base*Tuning.pressure(state.quest.enemyMorale)))
end

local function addEffect(state,frame,x,y,scale,duration)
    state.effects[#state.effects+1]={
        frame=frame,x=x,y=y,scale=scale or .14,
        ttl=duration or .24,maxTtl=duration or .24,
        rotation=randomRange(-.35,.35),
    }
end

local function enemyShot(state,target)
    state.enemyShots=state.enemyShots+1
    local stage=select(1,stageFor(state.elapsed))
    if state.ducking then return end
    local cover=WindowScene.data.frames[state.windowId].cover
    state.quest.positionIntegrity=clamp(state.quest.positionIntegrity-(.34+stage*.12)*cover,0,100)
    state.flashes[#state.flashes+1]={slot=target.slot,ttl=.13,maxTtl=.13}
    if state.enemyShots%3==0 then
        state.impacts[#state.impacts+1]={
            point=((math.floor(state.enemyShots/3)-1)%6)+1,
            frame=(state.enemyShots%2==0) and 0 or 2,
            age=0,
            rotation=randomRange(-.4,.4),
        }
        if #state.impacts>8 then table.remove(state.impacts,1) end
    end
end

local function updateTargets(state,dt)
    local limit=activeLimit(state)
    state.spawnCooldown=math.max(0,(state.spawnCooldown or 0)-dt)
    local active=0
    for _,target in ipairs(state.targets) do
        if target.status~="hidden" and target.status~="dying" then active=active+1 end
        if target.status~="hidden" then
            target.timer=target.timer-dt
            if target.status=="appearing" and target.timer<=0 then
                target.status="exposed"
                local relief=state.elapsed>=Tuning.holdSeconds and state.quest.kills<Tuning.requiredKills
                target.timer=relief and randomRange(1.8,2.8) or randomRange(.85,1.65)
            elseif target.status=="exposed" and target.timer<=0 then
                target.status="firing"
                target.timer=.16
                target.fired=false
            elseif target.status=="firing" then
                if not target.fired then target.fired=true; enemyShot(state,target) end
                if target.timer<=0 then target.status="hiding"; target.timer=.22 end
            elseif target.status=="hiding" and target.timer<=0 then
                target.status="hidden"
                target.timer=randomRange(.70,1.75)
            elseif target.status=="dying" and target.timer<=0 then
                target.status="hidden"
                target.timer=randomRange(1.4,2.8)
            end
        else
            target.timer=target.timer-dt
        end
    end
    if active>=limit or state.spawnCooldown>0 then return end
    local layout=WindowScene.layout(state.windowId,state.width,state.height)
    for offset=0,#state.targets-1 do
        local index=(state.spawnCursor+offset-1)%#state.targets+1
        local target=state.targets[index]
        local x,y=WindowScene.slotPosition(layout,index)
        if target.status=="hidden" and target.timer<=0
            and WindowScene.pointOpen(state.windowId,state.width,state.height,x,y) then
            local heavy=state.stage>=2 and randomRange(0,1)<(state.stage>=3 and .40 or .20)
            target.atlas=WindowScene.targetAtlases[heavy and 3 or (randomRange(0,1)<.5 and 1 or 2)]
            target.heavy=heavy
            target.status="appearing"
            target.timer=.24
            target.withdrawal=nil
            state.spawnCursor=index%#state.targets+1
            state.spawnCooldown=Tuning.spawnDelay(state.quest.enemyMorale)
            break
        end
    end
end

local function updateEffects(state,dt)
    for index=#state.effects,1,-1 do
        local effect=state.effects[index]
        effect.ttl=effect.ttl-dt
        if effect.ttl<=0 then table.remove(state.effects,index) end
    end
    for index=#state.flashes,1,-1 do
        local flash=state.flashes[index]
        flash.ttl=flash.ttl-dt
        if flash.ttl<=0 then table.remove(state.flashes,index) end
    end
    for _,impact in ipairs(state.impacts) do impact.age=(impact.age or 0)+dt end
end

function Shootout.update(state,dt,data,Catalog,width,height)
    state.width,state.height=width,height
    state.clock=state.clock+dt
    state.stageBanner=math.max(0,(state.stageBanner or 0)-dt)
    if state.notice then
        state.notice.timer=state.notice.timer-dt
        if state.notice.timer<=0 then state.notice=nil end
    end
    FirstPerson.update(state.gun,dt,data,state.quest,width,height)
    updateEffects(state,dt)
    if state.result=="withdrawing" then
        state.withdrawTimer=state.withdrawTimer-dt
        for _,target in ipairs(state.targets) do
            if target.status~="hidden" then
                target.withdrawal=math.min(1,(target.withdrawal or 0)+dt*.5)
                if target.withdrawal>=1 then target.status="hidden" end
            end
        end
        if state.withdrawTimer<=0 then state.result="victory" end
        return state.result
    end
    if state.result then return state.result end
    if FirstPerson.needsSupply(state.gun,data,state.quest) then return nil end

    if not state.ducking then state.elapsed=state.elapsed+dt end
    state.quest.holdElapsed=state.elapsed
    local stage,name=stageFor(state.elapsed)
    if stage~=state.stage then
        state.stage=stage
        state.stageName=name
        state.stageBanner=2.8
        state.quest.phaseCheckpoint=Tuning.phases[stage].start
        if state.quest.completedPhase<stage-1 then
            state.quest.completedPhase=stage-1
            state.quest.enemyMorale=clamp(state.quest.enemyMorale-Tuning.phaseMoraleLoss,0,100)
            if Tuning.phases[stage].intermission then
                state.elapsed=Tuning.phases[stage].start
                state.quest.holdElapsed=state.elapsed
                state.result="intermission"
                return state.result
            end
        end
    end
    if not state.ducking then
        state.quest.suppressionElapsed=(state.quest.suppressionElapsed or 0)+dt
        if state.quest.suppressionElapsed>=Tuning.suppressionInterval then
            state.quest.suppressionElapsed=state.quest.suppressionElapsed-Tuning.suppressionInterval
            state.quest.enemyMorale=clamp(state.quest.enemyMorale-(state.elapsed>=Tuning.assistanceSeconds and 3 or 1),0,100)
        end
    end
    local shots=state.enemyShots
    updateTargets(state,dt)
    if state.enemyShots>shots then FirstPerson.playReport("frontier-22-lever-rifle",Catalog,data,true) end

    if state.quest.positionIntegrity<=0 then
        state.result="retreat"
        return state.result
    end
    if state.elapsed>=Tuning.holdSeconds and state.quest.kills>=Tuning.requiredKills and state.quest.enemyMorale<=0 then
        state.result="withdrawing"
        state.withdrawTimer=Tuning.withdrawalSeconds
        state.flashes={}
        state.notice={text="They are pulling back. Hold your fire and watch the doors.",timer=Tuning.withdrawalSeconds}
        return state.result
    end
    return nil
end

function Shootout.setAim(state,x,y)
    FirstPerson.setAim(state.gun,x,y)
end

function Shootout.setADS(state,value)
    FirstPerson.setADS(state.gun,value)
end

function Shootout.reload(state,data)
    local reloaded=FirstPerson.reload(state.gun,data,state.quest)
    if not reloaded then state.notice={text="No rounds available to reload.",timer=1.5} end
    return reloaded
end

function Shootout.cycleWeapon(state,data,Catalog)
    if state.result or state.gun.cooldown>0 or state.gun.reloadTimer>0 then return false end
    local options=FirstPerson.weaponOptions(data,Catalog)
    local selected=0
    for index,option in ipairs(options) do
        if option.name==state.gun.weapon and option.borrowed==state.gun.borrowed then selected=index end
    end
    local option=options[selected%#options+1]
    state.gun=FirstPerson.chooseWeapon(state.gun,option,data,Catalog,state.quest)
    state.notice={text=(option.borrowed and "HOUSE RIFLE: " or "YOUR WEAPON: ")..option.name:gsub("%-"," "),timer=2.8}
    return true
end

function Shootout.supply(state,data,Catalog)
    if state.result or state.gun.reloadTimer>0 or state.gun.cooldown>0 then return false end
    if state.gun.borrowed and FirstPerson.rounds(state.gun,data,state.quest)>0 then return false end
    local firstLoan=not state.quest.loanActive
    local resupplied=(tonumber(state.quest.loanAmmo) or 0)<=0
    state.gun=FirstPerson.useLoan(state.gun,data,Catalog,state.quest)
    state.notice={
        text=firstLoan and "Guard Fox: Take my lever rifle. Forty-eight rounds."
            or resupplied and "Guard Fox: Another pouch. Make every shot count."
            or "Guard Fox: Your house rifle is ready with its remaining ammunition.",
        timer=3.2,
    }
    return true
end

function Shootout.fire(state,data,width,height,Catalog)
    if state.result or state.ducking or FirstPerson.needsSupply(state.gun,data,state.quest) then return false end
    local fired,reason=FirstPerson.fire(state.gun,data,state.quest)
    if not fired then
        state.notice={text=reason=="reload" and "Magazine empty. Press R to reload." or "The weapon is not ready.",timer=1.5}
        return false
    end
    local layout=WindowScene.layout(state.windowId,width,height)
    local aimX,aimY=state.gun.aimX,state.gun.aimY
    FirstPerson.playReport(state.gun.weapon,Catalog,data,false)
    if not WindowScene.pointOpen(state.windowId,width,height,aimX,aimY) then return true end
    local best,bestDistance
    for _,target in ipairs(state.targets) do
        if target.status=="appearing" or target.status=="exposed" or target.status=="firing" then
            local x,y=WindowScene.slotPosition(layout,target.slot)
            local dx,dy=aimX-x,aimY-y
            local distance=dx*dx+(dy*1.2)*(dy*1.2)
            if WindowScene.targetHit(layout,target.slot,aimX,aimY) and (not bestDistance or distance<bestDistance) then
                best,bestDistance=target,distance
            end
        end
    end
    if best then
        best.status="dying"
        best.timer=.72
        state.quest.kills=state.quest.kills+1
        state.quest.enemyMorale=clamp(state.quest.enemyMorale-(best.heavy and 7 or 4),0,100)
        local x,y=WindowScene.slotPosition(layout,best.slot)
        addEffect(state,1,x,y,.13,.20)
    elseif WindowScene.buildingSolid(layout,aimX,aimY) then
        addEffect(state,5,aimX,aimY,.10,.24)
    end
    return true
end

function Shootout.retry(state)
    state.quest.positionIntegrity=65
    state.elapsed=state.quest.phaseCheckpoint or 0
    state.quest.holdElapsed=state.elapsed
    state.quest.recoveries=(state.quest.recoveries or 0)+1
    state.result=nil
    state.enemyShots=0
    state.impacts={}
    state.quest.impacts=state.impacts
    for index,target in ipairs(state.targets) do
        target.status="hidden"
        target.withdrawal=nil
        target.timer=.5+index*.18
    end
    state.notice={text="The defenders pull back, regroup, and reopen the firing line.",timer=3}
end

local function drawTargets(state,layout)
    for _,target in ipairs(state.targets) do
        if target.status~="hidden" then
            local x,y=WindowScene.slotPosition(layout,target.slot)
            local alpha=target.status=="appearing" and .72 or target.status=="hiding" and .58 or 1
            local rx,ry,rw,rh=WindowScene.slotRect(layout,target.slot)
            local rise=(target.status=="appearing" or target.status=="hiding") and rh*.15 or 0
            rise=rise+(target.withdrawal or 0)*rh*1.5
            WindowScene.clipSlot(layout,target.slot,function()
                WindowScene.drawActor(target.atlas,targetFrame(target),rx+rw/2,ry+rh*1.45+rise,rh*1.5/512,alpha)
            end)
        end
    end
end

local function drawEffects(state,layout)
    for _,flash in ipairs(state.flashes) do
        local x,y=WindowScene.slotPosition(layout,flash.slot)
        if not state.reducedFlashes then
            WindowScene.clipSlot(layout,flash.slot,function()
                WindowScene.drawEffect(0,x,y,.055,flash.ttl/flash.maxTtl)
            end)
        end
    end
    for _,effect in ipairs(state.effects) do
        WindowScene.drawEffect(effect.frame,effect.x,effect.y,effect.scale,effect.ttl/effect.maxTtl,effect.rotation)
    end
end

local function formatTime(seconds)
    seconds=math.max(0,math.ceil(seconds))
    return string.format("%d:%02d",math.floor(seconds/60),seconds%60)
end

local function panel(x,y,w,h)
    love.graphics.setColor(.055,.035,.020,.90)
    love.graphics.rectangle("fill",x,y,w,h,8,8)
    love.graphics.setColor(.80,.55,.24,.95)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line",x,y,w,h,8,8)
end

local function pointIn(x,y,rx,ry,rw,rh)
    return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh
end

local touchButtons={
    {id="escape",label="LEAVE",x=18,w=108},
    {id="r",label="RELOAD",x=142,w=108},
    {id="ads",label="AIM",x=266,w=108},
    {id="c",label="COVER",x=390,w=108},
    {id="l",label="SUPPLY",x=514,w=108},
    {id="tab",label="WEAPON",x=638,w=148},
    {id="fire",label="FIRE",x=812,w=130},
}

function Shootout.touchAction(x,y,width,height)
    for _,button in ipairs(touchButtons) do
        if pointIn(x,y,button.x*width/960,height-104,button.w*width/960,62) then return button.id end
    end
end

function Shootout.supplyRect(width,height)
    return width/2-170,height/2+70,340,50
end

function Shootout.retryRect(width,height)
    return width/2-150,height/2+80,300,50
end

function Shootout.mousepressed(state,x,y,button,data,Catalog,width,height)
    if button==2 then FirstPerson.setADS(state.gun,true); return true end
    if button~=1 then return true end
    if state.result=="retreat" then
        local rx,ry,rw,rh=Shootout.retryRect(width,height)
        if pointIn(x,y,rx,ry,rw,rh) then Shootout.retry(state) end
        return true
    end
    if FirstPerson.needsSupply(state.gun,data,state.quest) then
        local rx,ry,rw,rh=Shootout.supplyRect(width,height)
        if pointIn(x,y,rx,ry,rw,rh) then Shootout.supply(state,data,Catalog) end
        return true
    end
    Shootout.fire(state,data,width,height,Catalog)
    return true
end

function Shootout.mousereleased(state,button)
    if button==2 then FirstPerson.setADS(state.gun,false) end
    return true
end

function Shootout.draw(state,data,width,height)
    love.graphics.push("all")
    love.graphics.setColor(.045,.034,.025,1)
    love.graphics.rectangle("fill",0,0,width,height)
    love.graphics.push("all")
    WindowScene.clipWindow(state.windowId,width,height)
    local layout=WindowScene.drawBackground(state,width,height)
    WindowScene.drawApertures(layout)
    drawTargets(state,layout)
    WindowScene.drawBuilding(layout)
    drawEffects(state,layout)
    love.graphics.pop()
    WindowScene.drawWindow(state.windowId,width,height)
    WindowScene.drawDamage(state.impacts,width,height,state.windowId)
    FirstPerson.draw(state.gun,width,height)

    local aimX,aimY=state.gun.aimX,state.gun.aimY
    love.graphics.setColor(1,.82,.42,.92)
    love.graphics.setLineWidth(state.gun.ads and 1.5 or 2.5)
    local radius=state.gun.ads and 9 or 16
    love.graphics.circle("line",aimX,aimY,radius)
    love.graphics.line(aimX-radius-8,aimY,aimX-radius+2,aimY)
    love.graphics.line(aimX+radius-2,aimY,aimX+radius+8,aimY)
    love.graphics.line(aimX,aimY-radius-8,aimX,aimY-radius+2)
    love.graphics.line(aimX,aimY+radius-2,aimX,aimY+radius+8)

    panel(18,16,205,92)
    love.graphics.setColor(.96,.86,.67,1)
    love.graphics.print("HOLD  "..formatTime(Tuning.holdSeconds-state.elapsed),32,29)
    love.graphics.print("HOSTILES  "..state.quest.kills.." / "..Tuning.requiredKills,32,54)
    love.graphics.print("MORALE  "..math.ceil(state.quest.enemyMorale).."%",32,79)

    panel(width-228,16,210,92)
    love.graphics.setColor(.96,.86,.67,1)
    love.graphics.print("POSITION  "..math.ceil(state.quest.positionIntegrity).."%",width-214,29)
    local rounds=FirstPerson.rounds(state.gun,data,state.quest)
    love.graphics.print("MAG  "..(state.gun.magazine or 0).." / "..(state.gun.capacity or 0),width-214,54)
    love.graphics.print("ROUNDS  "..rounds,width-214,79)

    local _,stageName=stageFor(state.elapsed)
    if state.stageBanner>0 then
        panel(width/2-150,28,300,48)
        love.graphics.setColor(1,.82,.43,math.min(1,state.stageBanner))
        love.graphics.printf("PHASE "..select(1,stageFor(state.elapsed)).."  "..string.upper(stageName),width/2-140,45,280,"center")
    end
    if state.notice then
        panel(width/2-260,height-116,520,44)
        love.graphics.setColor(.96,.86,.68,1)
        love.graphics.printf(state.notice.text,width/2-246,height-102,492,"center")
    end
    love.graphics.setColor(.95,.84,.64,.86)
    love.graphics.printf("LMB fire   RMB aim   R reload   C cover   TAB weapon   ESC leave",width/2-310,height-30,620,"center")
    if state.ducking then
        panel(width/2-180,height/2-35,360,70)
        love.graphics.setColor(1,.88,.62,1)
        love.graphics.printf("IN COVER - HOLD TIMER PAUSED\n[C] Return to the window",width/2-168,height/2-17,336,"center")
    end
    if state.touchControls then
        for _,button in ipairs(touchButtons) do
            local x,w=button.x*width/960,button.w*width/960
            panel(x,height-104,w,62)
            love.graphics.setColor(1,.88,.62,1)
            love.graphics.printf(button.label,x,height-80,w,"center")
        end
    end

    if FirstPerson.needsSupply(state.gun,data,state.quest) and not state.result then
        love.graphics.setColor(0,0,0,.68)
        love.graphics.rectangle("fill",0,0,width,height)
        panel(width/2-260,height/2-92,520,232)
        love.graphics.setColor(1,.84,.56,1)
        love.graphics.printf("GUARD FOX",width/2-230,height/2-66,460,"center")
        love.graphics.setColor(.92,.86,.74,1)
        love.graphics.printf(
            state.quest.loanActive and "You are dry again. I found another pouch of .22s." or "Use my lever rifle and ammunition. It comes back when this is over.",
            width/2-220,height/2-28,440,"center"
        )
        local rx,ry,rw,rh=Shootout.supplyRect(width,height)
        love.graphics.setColor(.52,.26,.10,1)
        love.graphics.rectangle("fill",rx,ry,rw,rh,8,8)
        love.graphics.setColor(1,.88,.62,1)
        love.graphics.printf(state.quest.loanActive and "TAKE AMMO  [L]" or "USE FOX'S RIFLE  [L]",rx,ry+17,rw,"center")
    end

    if state.result=="retreat" then
        love.graphics.setColor(0,0,0,.72)
        love.graphics.rectangle("fill",0,0,width,height)
        panel(width/2-270,height/2-100,540,250)
        love.graphics.setColor(1,.66,.38,1)
        love.graphics.printf("THE FIRING LINE GIVES WAY",width/2-240,height/2-68,480,"center")
        love.graphics.setColor(.92,.85,.72,1)
        love.graphics.printf("The defenders drag everyone back from the windows. Your progress is kept, but the position must be stabilized before you continue.",width/2-220,height/2-28,440,"center")
        local rx,ry,rw,rh=Shootout.retryRect(width,height)
        love.graphics.setColor(.52,.25,.10,1)
        love.graphics.rectangle("fill",rx,ry,rw,rh,8,8)
        love.graphics.setColor(1,.88,.62,1)
        love.graphics.printf("REGROUP AND RETRY  [ENTER]",rx,ry+17,rw,"center")
    end
    love.graphics.pop()
end

return Shootout
