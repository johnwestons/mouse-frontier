local WorldView=require("game.world_view")
local FirstPerson=require("game.first_person_shooting")
local WindowScene=require("game.window_scene")
local Tuning=require("game.last_stand_tuning")
local Typography=require("game.typography")
local Accessibility=require("game.accessibility")
local ActorState=require('game.coop_last_stand_state')
local Players=require('game.coop_players')
local Sessions=require('game.coop_shooter_sessions')

local Shootout={}
local SHOT_TRAVEL=.26
local SHOT_DELAY=.045
local IMPACT_DURATION=.36
local HIT_FLASH_DURATION=.45
local HIT_ANIMATION_DURATION=.20
local DEATH_ANIMATION_DURATION=.72
local DAMAGE_NUMBER_DURATION=.72
local HIT_CONFIRM_FRAME=5
local DEATH_COLLAPSE_FRAME=6
local DEATH_DOWN_FRAME=7

-- Local controls share authority while hosting. The callback returns nil in
-- offline play, retaining its existing local action and camera behavior.
function Shootout.setCommands(state,submit) state.submitCommand=submit end
local function command(state,name,args)
    if not state.submitCommand then return nil end
    local record=ActorState.record(state)
    if not record then return nil end
    local id=ActorState.actorId(state)
    args=args or {}; args.mode='lastStand'; args.encounterId=record.entityId; args.phaseRevision=record.phaseRevision
    if name~='gun.cover' and name~='lastStand.supply' then
        args.weaponId=args.weaponId or (state.gun.borrowed and 'loan:'..id or state.gun.itemId)
    end
    local reply=state.submitCommand(name,args)
    if reply and reply.ok then
        local data=Players.forActor(ActorState.campaignOf(state),id)
        local scope=Sessions.scope(data,state.quest)
        if scope.weaponSession and Sessions.record(state.gun)~=scope.weaponSession then
            local old=state.gun
            state.gun=Sessions.view(scope.weaponSession,state.width,state.height)
            state.gun.touchAim=old.touchAim
            FirstPerson.setAim(state.gun,old.aimX,old.aimY); FirstPerson.setADS(state.gun,old.ads)
        end
        if name=='gun.mode' or name=='gun.select' or name=='lastStand.supply' then
            state.gun.fireHeld=false; state.gun.fireHeldSources={}; state.fireHeldSources={}
        end
    end
    return reply
end

local function visualRange(low,high)
    local value=love.math and love.math.random and love.math.random() or math.random()
    return low+(high-low)*value
end
local function randomRange(state,low,high)
    return ActorState.random(state,low,high) or visualRange(low,high)
end

local function clamp(value,low,high) return math.max(low,math.min(high,value)) end

local stageFor=Tuning.phase

local function initializeTargetHealth(target)
    local defaultHealth=target.heavy and Tuning.heavyEnemyHealth or Tuning.enemyHealth
    target.maxHealth=math.max(1,tonumber(target.maxHealth) or defaultHealth)
    target.health=clamp(tonumber(target.health) or target.maxHealth,0,target.maxHealth)
    if target.hasSpawned==nil then target.hasSpawned=target.status~="hidden" end
    target.hitTimer=nil
    target.damageNumber=nil
    target.damageNumberTimer=nil
    target.damageNumberElapsed=nil
end

local function firearmDamage(state,data)
    data.weaponProficiency=data.weaponProficiency or {}
    local uses=math.max(0,math.floor(tonumber(data.weaponProficiency.firearms) or 0))+1
    data.weaponProficiency.firearms=uses
    local rank=math.min(Tuning.maxFirearmProficiencyRank,math.floor(uses/10))
    local base=Tuning.caliberDamage[state.gun.ammoType] or Tuning.caliberDamage["22lr"]
    return base+rank*Tuning.firearmProficiencyDamagePerRank
end

local function targetFrame(target,effect)
    if target.status=="dying" then
        local progress=1-clamp(target.timer/DEATH_ANIMATION_DURATION,0,1)
        return progress<.38 and DEATH_COLLAPSE_FRAME or DEATH_DOWN_FRAME
    end
    if (effect and effect.hitTimer or 0)>0 then return HIT_CONFIRM_FRAME end
    if target.status=="appearing" or target.status=="hiding" then return 1 end
    if target.status=="exposed" then return 2 end
    if target.status=="firing" then return 3 end
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
        width=width,height=height,
        windowId=windowId or quest.lastWindow or "wide",
        elapsed=quest.holdElapsed,
        clock=0,
        stage=stageFor(quest.holdElapsed),
        stageBanner=2.4,
        targets={},
        effects={},
        flashes={},
        incomingShots={},
        impactBursts={},
        impacts={},
        enemyShots=0,
        ducking=false,
        coverProgress=0,
        hitRecovery=0,
        hitFeedback=0,
        spawnCursor=1,
        result=nil,
        notice=nil,
        targetEffects={},
        reducedMotion=Accessibility.ensure(data) and Accessibility.ensure(data).reducedMotion==true,
        reducedFlashes=Accessibility.ensure(data) and (Accessibility.ensure(data).reducedFlashes==true or Accessibility.ensure(data).reducedMotion==true),
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
    for index,target in ipairs(state.targets) do
        if type(target)~="table" then
            target={slot=index,atlas=WindowScene.targetAtlases[((index-1)%#WindowScene.targetAtlases)+1],status="hidden",timer=.5}
            state.targets[index]=target
        end
        initializeTargetHealth(target)
    end
    quest.targets=state.targets
    state.impacts=type(quest.impacts)=="table" and quest.impacts or {}
    if not data.players then quest.impacts=state.impacts end
    return ActorState.bind(state,data)
end

function Shootout.forActor(state,data,Catalog,id)
    local root=Players.campaignOf(data)
    if ActorState.campaignOf(state)~=root or not Players.get(root,id) then return nil,'shooter_unavailable' end
    if id=='host' then return state end
    local view=ActorState.bind({quest=state.quest,width=state.width,height=state.height,
        stageBanner=0,effects={},flashes={},incomingShots={},impactBursts={},impacts={},targetEffects={},
        hitFeedback=0,reducedMotion=state.reducedMotion,reducedFlashes=state.reducedFlashes},root,id)
    view.gun=FirstPerson.new(Players.forActor(root,id),Catalog,state.quest,state.width,state.height)
    return view
end

-- A guest draws checked replica copies. It never binds this presentation to
-- saved combat records, creates a weapon session, or runs world simulation.
local function copiedEffects(source,fields,limit)
    local result={}
    for index,entry in ipairs(type(source)=='table' and source or {}) do
        if index>limit then break end
        local copy={}
        for _,field in ipairs(fields) do
            local value=entry[field]
            if type(value)=='number' or type(value)=='string' or type(value)=='boolean' then copy[field]=value end
        end
        result[#result+1]=copy
    end
    return result
end
function Shootout.guestView(quest,actor,gun,width,height,visual)
    local combat=quest and quest.combat; local owner=combat and combat.defenders and combat.defenders.companion
    if not owner or not gun then return nil end
    visual=visual or {}
    local state={quest=quest,gun=gun,width=width,height=height,guestPresentation=true,presentationActorId='companion',
        windowId=owner.windowId,ducking=owner.ducking,coverProgress=owner.coverProgress or 0,
        clock=combat.clock or 0,elapsed=quest.holdElapsed or 0,stage=combat.stage or 1,
        targets=quest.targets or {},result=combat.result,stageBanner=0,hitFeedback=math.max(0,math.min(HIT_FLASH_DURATION,tonumber(visual.hitFeedback) or 0)),
        effects={},targetEffects={},
        incomingShots=copiedEffects(visual.incomingShots,{'slot','point','elapsed','actorId','windowId','impactFrame','decalFrame','hit','decal','serial'},16),
        flashes=copiedEffects(visual.flashes,{'slot','ttl','maxTtl','actorId','windowId'},16),
        impactBursts=copiedEffects(visual.impactBursts,{'point','frame','ttl','maxTtl','actorId','windowId'},16),
        impacts=copiedEffects(visual.impacts,{'point','frame','age','rotation','actorId','windowId'},8),
        reducedMotion=Accessibility.ensure(actor) and Accessibility.ensure(actor).reducedMotion==true,
        reducedFlashes=Accessibility.ensure(actor) and (Accessibility.ensure(actor).reducedFlashes==true
            or Accessibility.ensure(actor).reducedMotion==true)}
    for slot,effect in pairs(type(visual.targetEffects)=='table' and visual.targetEffects or {}) do
        if type(slot)=='number' and slot==math.floor(slot) and slot>=1 and slot<=#WindowScene.slots then
            state.targetEffects[slot]=copiedEffects({effect},{'hitTimer','damageNumber','damageNumberTimer','damageNumberElapsed'},1)[1]
        end
    end
    return state
end

function Shootout.drawGuest(state,data,width,height)
    if not state or not state.guestPresentation then return false end
    Shootout.draw(state,data,width,height); return true
end

local function activeLimit(state,data,ids)
    local stage=select(1,stageFor(state.elapsed))
    local windowLimit=0
    for _,id in ipairs(ids or {'host'}) do
        local owner=ActorState.owner(state,id)
        if owner and ActorState.present(state,data,id,ids) then windowLimit=math.max(windowLimit,owner.windowId=='tall' and 4 or 5) end
    end
    local base=math.min(windowLimit,Tuning.phases[stage].active)
    return math.max(1,math.ceil(base*Tuning.pressure(state.quest.enemyMorale)))
end

local function addEffect(state,frame,x,y,scale,duration)
    state.effects[#state.effects+1]={
        frame=frame,x=x,y=y,scale=scale or .14,
        ttl=duration or .24,maxTtl=duration or .24,
        rotation=visualRange(-.35,.35),
    }
end

local function enemyShot(state,target,data,ids)
    state.enemyShots=state.enemyShots+1
    local id=target.targetActorId or 'host'
    if not ActorState.present(state,data,id,ids) then return end -- Never redirect a committed windup.
    local owner=ActorState.owner(state,id)
    local root=Players.campaignOf(data)
    local actor=root.players and Players.forActor(root,id) or data
    local window=owner.windowId or state.windowId
    local stage=select(1,stageFor(state.elapsed))
    local points=WindowScene.data.damagePoints[window] or WindowScene.data.damagePoints.wide
    local pointOrder=window=="tall" and {1,2,3,4} or {2,5,1,3,4}
    local shot={slot=target.slot,point=pointOrder[(state.enemyShots-1)%#points+1],elapsed=0,
        actorId=id,windowId=window,serial=state.enemyShots,
        impactFrame=state.enemyShots%2==0 and 5 or 4,
        decalFrame=state.enemyShots%2==0 and 0 or 2}
    state.incomingShots[#state.incomingShots+1]=shot
    state.flashes[#state.flashes+1]={slot=target.slot,ttl=.16,maxTtl=.16}
    if owner.ducking or owner.coverProgress>0 then ActorState.noteShot(state,shot); return end
    local cover=WindowScene.data.frames[window].cover
    state.quest.positionIntegrity=clamp(state.quest.positionIntegrity-(.34+stage*.12)*cover,0,100)
    local hitChance=(Tuning.hitChance+(stage-1)*Tuning.hitChancePerPhase)*cover
    if owner.hitRecovery<=0 and randomRange(state,0,1)<hitChance then
        local damage=target.heavy and 2 or 1
        local health=tonumber(actor.health) or tonumber(actor.maxHealth) or 20
        actor.health=math.max(1,health-damage)
        owner.playerDamage=(owner.playerDamage or 0)+health-actor.health
        owner.hitRecovery=Tuning.hitRecoverySeconds
        shot.hit=true
        shot.damage=health-actor.health
        if id=='host' and actor.health<=1 then
            state.retreatReason="wounded"
            state.result="retreat"
        end
    end
    if state.enemyShots%3==0 then
        shot.decal=true
    end
    ActorState.noteShot(state,shot)
end

function Shootout.effectState(state)
    local record=ActorState.record(state)
    if not record or ActorState.actorId(state)~='host' then return nil end
    return {encounterId=record.entityId,phaseRevision=record.phaseRevision,clock=record.clock,
        events=ActorState.effectEvents(state),paused=state.effectsPaused==true}
end

local function updateTargets(state,dt,data,ids)
    local limit=activeLimit(state,data,ids)
    state.spawnCooldown=math.max(0,(state.spawnCooldown or 0)-dt)
    local active=0
    for _,target in ipairs(state.targets) do
        if target.status~="hidden" and target.status~="dying" then active=active+1 end
        if target.status~="hidden" then
            target.timer=target.timer-dt
            if target.status=="appearing" and target.timer<=0 then
                target.status="exposed"
                local relief=state.elapsed>=Tuning.holdSeconds and state.quest.kills<Tuning.requiredKills
                target.timer=relief and randomRange(state,1.8,2.8) or randomRange(state,.85,1.65)
            elseif target.status=="exposed" and target.timer<=0 then
                target.status="firing"
                target.timer=.16
                target.fired=false
                target.targetActorId=ActorState.target(state,data,ids)
            elseif target.status=="firing" then
                if not target.fired then target.fired=true; enemyShot(state,target,data,ids) end
                if target.timer<=0 then target.status="hiding"; target.timer=.22 end
            elseif target.status=="hiding" and target.timer<=0 then
                target.status="hidden"
                target.timer=randomRange(state,.70,1.75)
            elseif target.status=="dying" and target.timer<=0 then
                target.status="hidden"
                target.timer=randomRange(state,1.4,2.8)
            end
        else
            target.timer=target.timer-dt
        end
    end
    if active>=limit or state.spawnCooldown>0 then return end
    for offset=0,#state.targets-1 do
        local index=(state.spawnCursor+offset-1)%#state.targets+1
        local target=state.targets[index]
        local visible=false
        for _,id in ipairs(ids or {'host'}) do
            local owner=ActorState.owner(state,id)
            if owner and ActorState.present(state,data,id,ids) then
                local layout=WindowScene.layout(owner.windowId,state.width,state.height)
                local x,y=WindowScene.slotPosition(layout,index)
                if WindowScene.pointOpen(owner.windowId,state.width,state.height,x,y) then visible=true; break end
            end
        end
        if target.status=="hidden" and target.timer<=0 and visible then
            -- Survivors keep their health and identity between peeks and retries.
            if not target.hasSpawned or (target.health or 0)<=0 then
                local heavy=state.stage>=2 and randomRange(state,0,1)<(state.stage>=3 and .40 or .20)
                target.atlas=WindowScene.targetAtlases[heavy and 3 or (randomRange(state,0,1)<.5 and 1 or 2)]
                target.heavy=heavy
                target.maxHealth=heavy and Tuning.heavyEnemyHealth or Tuning.enemyHealth
                target.health=target.maxHealth
                target.hasSpawned=true
            end
            target.status="appearing"
            target.timer=.24
            target.withdrawal=nil
            target.targetActorId=nil
            state.spawnCursor=index%#state.targets+1
            state.spawnCooldown=Tuning.spawnDelay(state.quest.enemyMorale)
            break
        end
    end
end

local function updateEffects(state,dt)
    for _,target in pairs(state.targetEffects) do
        if target.hitTimer then
            target.hitTimer=target.hitTimer-dt
            if target.hitTimer<=0 then target.hitTimer=nil end
        end
        if target.damageNumberTimer then
            target.damageNumberTimer=target.damageNumberTimer-dt
            target.damageNumberElapsed=(target.damageNumberElapsed or 0)+dt
            if target.damageNumberTimer<=0 then
                target.damageNumber=nil
                target.damageNumberTimer=nil
                target.damageNumberElapsed=nil
            end
        end
    end
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
    for index=#state.impactBursts,1,-1 do
        local burst=state.impactBursts[index]
        burst.ttl=burst.ttl-dt
        if burst.ttl<=0 then table.remove(state.impactBursts,index) end
    end
    for index=#state.incomingShots,1,-1 do
        local shot=state.incomingShots[index]
        shot.elapsed=shot.elapsed+dt
        if shot.elapsed>=SHOT_DELAY+SHOT_TRAVEL then
            if (shot.actorId or 'host')==ActorState.actorId(state) and (not shot.windowId or shot.windowId==state.windowId) then
            state.impactBursts[#state.impactBursts+1]={point=shot.point,frame=shot.impactFrame,
                ttl=IMPACT_DURATION,maxTtl=IMPACT_DURATION}
            if shot.hit and (shot.actorId or 'host')==ActorState.actorId(state) then
                state.hitFeedback=HIT_FLASH_DURATION
                state.notice={text="You were hit! Take cover below the window.",timer=1.7}
            end
            if shot.decal then
                state.impacts[#state.impacts+1]={point=shot.point,
                    frame=shot.decalFrame,
                    age=0,rotation=visualRange(-.4,.4)}
                if #state.impacts>8 then table.remove(state.impacts,1) end
            end
            end
            table.remove(state.incomingShots,index)
        end
    end
    for _,impact in ipairs(state.impacts) do impact.age=(impact.age or 0)+dt end
end

function Shootout.update(state,dt,data,Catalog,width,height,ids)
    if ActorState.actorId(state)~='host' or not ActorState.accepts(state,data) then return nil,'host_only' end
    ids=ids or {'host'}
    state.width,state.height=width,height
    ActorState.prepareParticipants(state,data,ids)
    state.clock=state.clock+dt
    state.hitFeedback=math.max(0,(state.hitFeedback or 0)-dt)
    if not ActorState.updateDefenders(state,dt,ids) then
        state.hitRecovery=math.max(0,(state.hitRecovery or 0)-dt)
        local coverTarget=state.ducking and 1 or 0
        local coverStep=dt/(state.reducedMotion and .1 or Tuning.coverSeconds)
        state.coverProgress=state.coverProgress+clamp(coverTarget-state.coverProgress,-coverStep,coverStep)
    end
    state.stageBanner=math.max(0,(state.stageBanner or 0)-dt)
    if state.notice then
        state.notice.timer=state.notice.timer-dt
        if state.notice.timer<=0 then state.notice=nil end
    end
    if not ActorState.updateGuns(state,data,dt,width,height,ids) then FirstPerson.update(state.gun,dt,data,state.quest,width,height) end
    if ActorState.present(state,data,'host',ids) and state.gun.fireHeld and state.gun.fireMode=="auto" and not state.result
        and state.gun.cooldown<=0 and state.gun.reloadTimer<=0 then
        Shootout.fire(state,data,width,height,Catalog)
    end
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
    if not ActorState.canFight(state,data,ids) then return nil end

    local exposed=ActorState.exposed(state,data,ids)
    if exposed then state.elapsed=state.elapsed+dt end
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
    if exposed then
        state.quest.suppressionElapsed=(state.quest.suppressionElapsed or 0)+dt
        if state.quest.suppressionElapsed>=Tuning.suppressionInterval then
            state.quest.suppressionElapsed=state.quest.suppressionElapsed-Tuning.suppressionInterval
            state.quest.enemyMorale=clamp(state.quest.enemyMorale-(state.elapsed>=Tuning.assistanceSeconds and 3 or 1),0,100)
        end
    end
    local shots=state.enemyShots
    updateTargets(state,dt,data,ids)
    if state.enemyShots>shots then FirstPerson.playReport("frontier-22-lever-rifle",Catalog,data,true) end

    if state.result then return state.result end

    if state.quest.positionIntegrity<=0 then
        state.result="retreat"
        return state.result
    end
    if state.elapsed>=Tuning.holdSeconds and state.quest.kills>=Tuning.requiredKills and state.quest.enemyMorale<=0 then
        state.result="withdrawing"
        state.withdrawTimer=Tuning.withdrawalSeconds
        state.flashes={}
        state.notice={text="Enemy withdrawal in progress.",timer=Tuning.withdrawalSeconds}
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

function Shootout.setCover(state,value)
    if state.result then return false end
    local reply=command(state,'gun.cover',{cover=value==true})
    if reply then return reply.ok==true end
    state.ducking=value==true
    return true
end

function Shootout.setTouchAim(state,x,y,width,height)
    FirstPerson.setTouchAim(state.gun,x,y,width,height)
end

function Shootout.setFireHeld(state,source,held,data,width,height,Catalog)
    if not state or not state.gun then return false end
    source=source or "fire"
    state.fireHeldSources=state.fireHeldSources or {}
    local wasHeld=state.fireHeldSources[source]==true
    if held then
        state.fireHeldSources[source]=true
    else
        state.fireHeldSources[source]=nil
    end
    state.gun.fireHeld=next(state.fireHeldSources)~=nil
    if held and not wasHeld then
        return Shootout.fire(state,data,width,height,Catalog)
    end
    return false
end

function Shootout.cycleFireMode(state,direction)
    if not state or not state.gun then return nil end
    local reply=command(state,'gun.mode',{direction=direction})
    local mode
    if reply then mode=reply.ok and reply.result.fireMode or nil
    else mode=FirstPerson.cycleFireMode(state.gun,direction) end
    if mode then state.notice={text="FIRE MODE: "..string.upper(mode),timer=1.8} end
    return mode
end

function Shootout.reload(state,data)
    if not ActorState.accepts(state,data) then return false end
    local reply=command(state,'gun.reload')
    local reloaded
    if reply then reloaded=reply.ok==true else reloaded=FirstPerson.reload(state.gun,data,state.quest) end
    if not reloaded then state.notice={text="No rounds available to reload.",timer=1.5} end
    return reloaded
end

function Shootout.cycleWeapon(state,data,Catalog)
    if not ActorState.accepts(state,data) then return false end
    if state.result or state.gun.cooldown>0 or state.gun.reloadTimer>0 then return false end
    local options=FirstPerson.weaponOptions(data,Catalog)
    local selected=0
    for index,option in ipairs(options) do
        if option.name==state.gun.weapon and option.borrowed==state.gun.borrowed and option.itemId==state.gun.itemId then selected=index end
    end
    local option=options[selected%#options+1]
    local reply=command(state,'gun.select',{weaponId=option.borrowed and 'loan:'..ActorState.actorId(state) or option.itemId})
    if reply then if not reply.ok then return false end
    else state.gun=FirstPerson.chooseWeapon(state.gun,option,data,Catalog,state.quest) end
    state.notice={text=(option.borrowed and "HOUSE RIFLE: " or "YOUR WEAPON: ")..option.name:gsub("%-"," "),timer=2.8}
    return true
end

function Shootout.supply(state,data,Catalog)
    if not ActorState.accepts(state,data) then return false end
    if state.result or state.gun.reloadTimer>0 or state.gun.cooldown>0 then return false end
    if state.gun.borrowed and FirstPerson.rounds(state.gun,data,state.quest)>0 then return false end
    if not Sessions.owned(state.gun,data) then return false end
    local scope=Sessions.scope(data,state.quest)
    local firstLoan=not scope.loanActive
    local resupplied=(tonumber(scope.loanAmmo) or 0)<=0
    local reply=command(state,'lastStand.supply')
    if reply then if not reply.ok then return false end
    else state.gun=FirstPerson.useLoan(state.gun,data,Catalog,state.quest) end
    state.notice={
        text=firstLoan and "Loan rifle equipped. 48 rounds supplied."
            or resupplied and "Loan ammunition replenished."
            or "Loan rifle equipped with remaining ammunition.",
        timer=3.2,
    }
    return true
end

-- Detached authority drafts use campaign coordinates and no device feedback.
function Shootout.commandView(quest,data,id,gun,width,height)
    return ActorState.bind({quest=quest,gun=gun,width=width,height=height},data,id)
end

function Shootout.fireAt(state,data,width,height,Catalog,aimX,aimY)
    if not ActorState.accepts(state,data) then return nil,'ownership' end
    if ActorState.record(state) and (data.health or 0)<=1 then return nil,'shooter_unavailable' end
    if state.result then return nil,'shooter_unavailable' end
    if state.ducking or state.coverProgress>0 then return nil,'in_cover' end
    if FirstPerson.needsSupply(state.gun,data,state.quest) then return nil,'supply_required' end
    local fired,reason=FirstPerson.fire(state.gun,data,state.quest)
    if not fired then return nil,reason end
    local shotDamage=firearmDamage(state,data)
    local layout=WindowScene.layout(state.windowId,width,height)
    local result={fired=true,hit=false,x=aimX,y=aimY}
    if not WindowScene.pointOpen(state.windowId,width,height,aimX,aimY) then return result end
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
        local previousHealth=math.max(0,tonumber(best.health) or best.maxHealth or Tuning.enemyHealth)
        local dealtDamage=math.min(previousHealth,shotDamage)
        best.health=math.max(0,previousHealth-dealtDamage)
        result.hit=true; result.slot=best.slot; result.damage=dealtDamage
        if best.health<=0 then
            best.status="dying"
            best.timer=DEATH_ANIMATION_DURATION
            state.quest.kills=state.quest.kills+1
            state.quest.enemyMorale=clamp(state.quest.enemyMorale-(best.heavy and 7 or 4),0,100)
        end
    end
    return result
end

local function presentShot(state,data,width,height,Catalog,result,report)
    local aimX,aimY=result.x,result.y
    if report then FirstPerson.playReport(state.gun.weapon,Catalog,data,false) end
    local layout=WindowScene.layout(state.windowId,width,height)
    if result.hit then
        local effect=state.targetEffects[result.slot] or {}; state.targetEffects[result.slot]=effect
        effect.damageNumber=string.format("%.2f",result.damage):gsub("0+$",""):gsub("%.$","")
        effect.damageNumberTimer=DAMAGE_NUMBER_DURATION; effect.damageNumberElapsed=0
        effect.hitTimer=state.targets[result.slot].health>0 and HIT_ANIMATION_DURATION or nil
        local x,y=WindowScene.slotPosition(layout,result.slot)
        addEffect(state,1,x,y,.13,.20)
    elseif WindowScene.pointOpen(state.windowId,width,height,aimX,aimY) and WindowScene.buildingSolid(layout,aimX,aimY) then
        addEffect(state,5,aimX,aimY,.10,.24)
    end
end

function Shootout.fire(state,data,width,height,Catalog)
    if not ActorState.accepts(state,data) then return false end
    if state.result or state.ducking or state.coverProgress>0 or FirstPerson.needsSupply(state.gun,data,state.quest) then return false end
    local aimX,aimY=WorldView.toWorld(state.gun.aimX,state.gun.aimY)
    local before={}; for index,target in ipairs(state.targets) do before[index]=target.health end
    local reply=command(state,'gun.fire',{x=math.floor(clamp(aimX/width,0,1)*1000000+.5),
        y=math.floor(clamp(aimY/height,0,1)*1000000+.5)})
    local result,reason
    if reply then
        reason=reply.reason
        if reply.ok then
            result={fired=true,hit=false,x=aimX,y=aimY}
            if reply.result.hit then
                for index,target in ipairs(state.targets) do
                    if target.health<before[index] then
                        result.hit=true; result.slot=target.slot; result.damage=before[index]-target.health; break
                    end
                end
            end
        end
    else result,reason=Shootout.fireAt(state,data,width,height,Catalog,aimX,aimY) end
    if not result then
        local message=reason=="safe" and "Weapon selector is on SAFE. Press V to change mode."
            or reason=="reload" and "Magazine empty. Press R to reload." or "The weapon is not ready."
        state.notice={text=message,timer=1.5}
        return false
    end
    presentShot(state,data,width,height,Catalog,result,not reply or reply.durable==true)
    return true
end

function Shootout.retry(state)
    if ActorState.actorId(state)~='host' then return false,'host_only' end
    if not ActorState.advance(state.quest) then return false,'phase_exhausted' end
    state.quest.positionIntegrity=65
    state.elapsed=state.quest.phaseCheckpoint or 0
    state.quest.holdElapsed=state.elapsed
    state.quest.recoveries=(state.quest.recoveries or 0)+1
    state.result=nil
    state.retreatReason=nil
    local record=ActorState.record(state)
    if record then
        for _,owner in pairs(record.defenders) do owner.ducking=false; owner.coverProgress=0; owner.hitRecovery=0 end
    else state.ducking=false; state.coverProgress=0; state.hitRecovery=0 end
    state.enemyShots=0
    state.flashes={}
    state.incomingShots={}
    state.impactBursts={}
    state.hitFeedback=0
    state.impacts={}
    state.targetEffects={}
    if not record then state.quest.impacts=state.impacts end
    for index,target in ipairs(state.targets) do
        target.status="hidden"
        target.withdrawal=nil
        target.targetActorId=nil
        target.timer=.5+index*.18
    end
    state.notice={text="The defenders pull back, regroup, and reopen the firing line.",timer=3}
    return true
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
                WindowScene.drawActor(target.atlas,targetFrame(target,state.targetEffects[target.slot]),rx+rw/2,ry+rh*1.45+rise,rh*1.5/512,alpha)
            end)
        end
    end
end

local function drawDamageNumbers(state,layout)
    for _,target in ipairs(state.targets) do
        local effect=state.targetEffects[target.slot]
        if target.status~="hidden" and effect and effect.damageNumber and (effect.damageNumberTimer or 0)>0 then
            local rx,ry,rw,rh=WindowScene.slotRect(layout,target.slot)
            local rise=(target.status=="appearing" or target.status=="hiding") and rh*.15 or 0
            rise=rise+(target.withdrawal or 0)*rh*1.5
            local progress=clamp((effect.damageNumberElapsed or 0)/DAMAGE_NUMBER_DURATION,0,1)
            local alpha=clamp((effect.damageNumberTimer or 0)/DAMAGE_NUMBER_DURATION,0,1)
            local x=rx+rw/2
            local y=ry+rh*.09+rise-progress*math.max(10,rh*.24)
            love.graphics.setColor(0,0,0,alpha*.9)
            love.graphics.printf(effect.damageNumber,x-25+1,y+1,50,"center")
            love.graphics.setColor(.96,.12,.10,alpha)
            love.graphics.printf(effect.damageNumber,x-25,y,50,"center")
        end
    end
end

local function drawEffects(state,layout)
    for _,flash in ipairs(state.flashes) do
        local x,y=WindowScene.slotPosition(layout,flash.slot)
        if not state.reducedFlashes then
            WindowScene.clipSlot(layout,flash.slot,function()
                WindowScene.drawEffect(1,x,y,.105,flash.ttl/flash.maxTtl)
            end)
        end
    end
    for _,effect in ipairs(state.effects) do
        WindowScene.drawEffect(effect.frame,effect.x,effect.y,effect.scale,effect.ttl/effect.maxTtl,effect.rotation)
    end
end

local function drawIncomingFire(state,layout,width,height)
    for _,shot in ipairs(state.incomingShots) do
        local actorId=state.presentationActorId or ActorState.actorId(state)
        if (shot.actorId or 'host')==actorId and (not shot.windowId or shot.windowId==state.windowId) then
        local progress=clamp((shot.elapsed-SHOT_DELAY)/SHOT_TRAVEL,0,1)
        if progress>0 then
            local startX,startY=WindowScene.slotPosition(layout,shot.slot)
            local endX,endY=WindowScene.impactPosition(state.windowId,width,height,shot.point)
            local headX=startX+(endX-startX)*progress
            local headY=startY+(endY-startY)*progress
            local tailProgress=math.max(0,progress-.24)
            local tailX=startX+(endX-startX)*tailProgress
            local tailY=startY+(endY-startY)*tailProgress
            love.graphics.setColor(1,.24,.04,.42)
            love.graphics.setLineWidth(11)
            love.graphics.line(tailX,tailY,headX,headY)
            love.graphics.setColor(1,.75,.20,1)
            love.graphics.setLineWidth(4)
            love.graphics.line(tailX,tailY,headX,headY)
            if not state.reducedFlashes then
                love.graphics.setColor(1,.96,.72,1)
                love.graphics.circle("fill",headX,headY,5)
            end
        end
        end
    end
    for _,burst in ipairs(state.impactBursts) do
        local x,y=WindowScene.impactPosition(state.windowId,width,height,burst.point)
        local alpha=burst.ttl/burst.maxTtl
        WindowScene.drawEffect(burst.frame,x,y,.16,alpha)
        if not state.reducedFlashes then
            love.graphics.setColor(1,.79,.38,alpha*.8)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line",x,y,10+(1-alpha)*17)
        end
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
    {id="v",label="FIRE MODE",x=514,w=108},
    {id="tab",label="WEAPON",x=638,w=148},
    {id="fire",label="FIRE",x=812,w=130},
}

function Shootout.touchAction(x,y,width,height)
    for _,button in ipairs(touchButtons) do
        if pointIn(x,y,button.x*width/960,height-104,button.w*width/960,62) then return button.id end
    end
end

function Shootout.supplyRect(width,height)
    return width/2-170,height/2+70,340,62
end

function Shootout.retryRect(width,height)
    return width/2-150,height/2+80,300,62
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
    Shootout.setFireHeld(state,"mouse",true,data,width,height,Catalog)
    return true
end

function Shootout.mousereleased(state,button)
    if button==2 then FirstPerson.setADS(state.gun,false) end
    if button==1 then Shootout.setFireHeld(state,"mouse",false) end
    return true
end

function Shootout.draw(state,data,width,height)
    local textScale=Accessibility.textScale(data)
    local function textBox(text,x,y,w,h,scale,align)
        return Typography.drawText(love.graphics,text,x,y,w,h,{scale=(scale or 1)*textScale,minScale=.85,align=align or "left",valign="center"})
    end
    love.graphics.push("all")
    love.graphics.setColor(.045,.034,.025,1)
    love.graphics.rectangle("fill",0,0,width,height)
    WorldView.begin()
    local cover=state.coverProgress or 0
    local easedCover=cover*cover*(3-2*cover)
    local _,openingY,_,openingHeight=WindowScene.opening(state.windowId,width,height)
    local drop=(openingY+openingHeight-height*.14)*easedCover
    love.graphics.push("all")
    love.graphics.translate(0,-drop)
    WindowScene.drawLowerWall(state.windowId,width,height,drop)
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
    drawIncomingFire(state,layout,width,height)
    drawDamageNumbers(state,layout)
    love.graphics.pop()
    WorldView.finish()
    if cover<1 then
        love.graphics.push("all")
        love.graphics.translate(0,height*easedCover)
        FirstPerson.draw(state.gun,width,height)
        love.graphics.pop()
    end

    if not state.ducking and cover==0 and not state.gun.ads then
        local aimX,aimY=state.gun.aimX,state.gun.aimY
        love.graphics.setColor(1,.82,.42,.92)
        love.graphics.setLineWidth(2.5)
        local radius=16
        love.graphics.circle("line",aimX,aimY,radius)
        love.graphics.line(aimX-radius-8,aimY,aimX-radius+2,aimY)
        love.graphics.line(aimX+radius-2,aimY,aimX+radius+8,aimY)
        love.graphics.line(aimX,aimY-radius-8,aimX,aimY-radius+2)
        love.graphics.line(aimX,aimY+radius-2,aimX,aimY+radius+8)
    end

    if state.hitFeedback>0 and not state.reducedFlashes then
        local strength=state.hitFeedback/HIT_FLASH_DURATION
        love.graphics.setColor(.76,.045,.025,.27*strength)
        love.graphics.rectangle("fill",0,0,width,height)
        love.graphics.setColor(.95,.13,.055,.65*strength)
        love.graphics.setLineWidth(22)
        love.graphics.rectangle("line",11,11,width-22,height-22)
    end

    panel(18,16,250,108)
    love.graphics.setColor(.96,.86,.67,1)
    textBox("HOLD  "..formatTime(Tuning.holdSeconds-state.elapsed),32,24,222,28)
    textBox("HOSTILES  "..state.quest.kills.." / "..Tuning.requiredKills,32,57,222,28)
    textBox("MORALE  "..math.ceil(state.quest.enemyMorale).."%",32,90,222,28)

    panel(width-260,16,242,176)
    love.graphics.setColor(.96,.86,.67,1)
    textBox("HEALTH  "..math.ceil(data.health or data.maxHealth or 20).." / "..math.ceil(data.maxHealth or 20),width-246,24,214,28)
    textBox("POSITION  "..math.ceil(state.quest.positionIntegrity).."%",width-246,57,214,28)
    local rounds=FirstPerson.rounds(state.gun,data,state.quest)
    textBox("MAG  "..(state.gun.magazine or 0).." / "..(state.gun.capacity or 0),width-246,90,214,28)
    textBox("ROUNDS  "..rounds,width-246,123,214,28)
    textBox("FIRE MODE  "..string.upper(state.gun.fireMode or "single").."  [V]",width-246,156,214,28)

    local _,stageName=stageFor(state.elapsed)
    if state.stageBanner>0 then
        panel(width/2-190,20,380,72)
        love.graphics.setColor(1,.82,.43,math.min(1,state.stageBanner))
        textBox("PHASE "..select(1,stageFor(state.elapsed)).."  "..string.upper(stageName),width/2-178,26,356,60,1,"center")
    end
    if state.notice then
        local noticeY=height-(state.touchControls and 190 or 118)
        panel(width/2-290,noticeY,580,70)
        love.graphics.setColor(.96,.86,.68,1)
        textBox(state.notice.text,width/2-276,noticeY+6,552,58,.95,"center")
    end
    if not state.guestPresentation then
    love.graphics.setColor(.95,.84,.64,.86)
    local hints=state.touchControls and "Left stick to aim. Right FIRE button to shoot."
        or "LMB fire  •  RMB aim  •  R reload  •  V mode  •  C cover  •  TAB weapon  •  ESC leave"
    textBox(hints,24,height-36,width-48,30,.9,"center")
    if state.ducking then
        panel(width/2-230,height/2-52,460,104)
        love.graphics.setColor(1,.88,.62,1)
        textBox("IN COVER  •  PROTECTED\n"..(state.touchControls and "Tap COVER to return to the window" or "[C] Return to the window"),width/2-216,height/2-42,432,84,1,"center")
    end
    if state.touchControls then
        for _,button in ipairs(touchButtons) do
            local x,w=button.x*width/960,button.w*width/960
            panel(x,height-104,w,62)
            love.graphics.setColor(1,.88,.62,1)
            textBox(button.label,x+6,height-100,w-12,54,1,"center")
        end
    end

    if FirstPerson.needsSupply(state.gun,data,state.quest) and not state.result then
        love.graphics.setColor(0,0,0,.68)
        love.graphics.rectangle("fill",0,0,width,height)
        panel(width/2-290,height/2-100,580,244)
        love.graphics.setColor(1,.84,.56,1)
        textBox("LOAN SUPPLIES",width/2-270,height/2-80,540,38,1.15,"center")
        love.graphics.setColor(.92,.86,.74,1)
        textBox(
            state.quest.loanActive and "Loan ammunition is depleted. Replenishment available." or "Loan rifle and ammunition available for this defense.",
            width/2-260,height/2-30,520,86,1,"center"
        )
        local rx,ry,rw,rh=Shootout.supplyRect(width,height)
        love.graphics.setColor(.52,.26,.10,1)
        love.graphics.rectangle("fill",rx,ry,rw,rh,8,8)
        love.graphics.setColor(1,.88,.62,1)
        local label=state.quest.loanActive and "TAKE AMMO" or "USE FOX'S RIFLE"
        textBox(label..(state.touchControls and "" or "  [L]"),rx+10,ry+4,rw-20,rh-8,1,"center")
    end

    if state.result=="retreat" then
        love.graphics.setColor(0,0,0,.72)
        love.graphics.rectangle("fill",0,0,width,height)
        panel(width/2-300,height/2-108,600,266)
        love.graphics.setColor(1,.66,.38,1)
        textBox("THE FIRING LINE GIVES WAY",width/2-280,height/2-90,560,42,1.1,"center")
        love.graphics.setColor(.92,.85,.72,1)
        textBox("The defenders pull everyone back from the windows. Your progress is saved. Stabilize the position to continue.",width/2-270,height/2-36,540,106,1,"center")
        local rx,ry,rw,rh=Shootout.retryRect(width,height)
        love.graphics.setColor(.52,.25,.10,1)
        love.graphics.rectangle("fill",rx,ry,rw,rh,8,8)
        love.graphics.setColor(1,.88,.62,1)
        textBox("REGROUP AND RETRY"..(state.touchControls and "" or "  [ENTER]"),rx+10,ry+4,rw-20,rh-8,1,"center")
    end
    end
    love.graphics.pop()
end

return Shootout
