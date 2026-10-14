-- Saved encounter timing and personal defenders; runtime views stay private.
local Players=require('game.coop_players')
local Sessions=require('game.coop_shooter_sessions')
local Shooting=require('game.first_person_shooting')
local Random=require('game.coop_random')
local Entities=require('game.coop_entities')
local Window=require('game.window_scene')
local Tuning=require('game.last_stand_tuning')
local P=require('game.net.protocol')
local Positions=require('game.coop_last_stand_position_state')
local State={VERSION=2}
local bindings=setmetatable({},{__mode='k'})
-- Presentation history has VM lifetime only. Values never refer back to their
-- weak combat key and never enter campaign snapshots or saved records.
local effectStreams=setmetatable({},{__mode='k'})
State.EFFECT_TTL=3
State.MAX_EFFECTS_PER_ACTOR=4
local shared={clock=true,stage=true,enemyShots=true,spawnCursor=true,spawnCooldown=true,
    result=true,retreatReason=true,withdrawTimer=true,lastTargetActorId=true}
local personal={windowId=true,ducking=true,coverProgress=true,hitRecovery=true,playerDamage=true}
local function defender(window)
    return {windowId=window or 'wide',ducking=false,coverProgress=0,hitRecovery=0,playerDamage=0}
end
function State.record(state) local b=bindings[state]; return b and b.record end
function State.campaignOf(state) local b=bindings[state]; return b and b.data end
function State.accepts(state,data)
    local b=bindings[state]
    return not b or b.data==Players.campaignOf(data) and b.actorId==Players.actorId(data)
end
function State.actorId(state) local b=bindings[state]; return b and b.actorId or 'host' end
function State.owner(state,id,create)
    id=id or 'host'; local b=bindings[state]
    if not b then return id=='host' and state or nil end
    if not Players.get(b.data,id) then return nil end
    local owners=b.record.defenders
    if not owners[id] and create then owners[id]=defender(owners.host.windowId) end
    return owners[id]
end
function State.bind(state,data,id)
    local root=Players.campaignOf(data); local quest=state.quest
    if not root.players or root.lastStand~=quest then return state end
    id=id or Players.actorId(data) or 'host'
    assert(Players.get(root,id),'unknown Last Stand actor')
    local record=quest.combat
    if not record then
        record={version=State.VERSION,phaseRevision=1,clock=state.clock or 0,stage=state.stage or 1,
            enemyShots=state.enemyShots or 0,spawnCursor=state.spawnCursor or 1,
            spawnCooldown=state.spawnCooldown or 0,defenders={host=defender(state.windowId)}}
        quest.combat=record
        local ok,reason=Entities.ensure(root); assert(ok,reason)
    end
    assert(record.version==State.VERSION,'unsupported Last Stand combat record')
    Positions.prepare(root)
    bindings[state]={record=record,data=root,actorId=id}
    local owner=assert(State.owner(state,id,true))
    if state.windowId then owner.windowId=state.windowId end
    for key in pairs(shared) do rawset(state,key,nil) end
    for key in pairs(personal) do rawset(state,key,nil) end
    rawset(state,'elapsed',nil); rawset(state,'targets',nil)
    -- Decals, damage numbers and delayed local flashes do not drive gameplay.
    quest.impacts=nil
    setmetatable(state,{__index=function(_,key)
        if shared[key] then return record[key] end
        if personal[key] then return owner[key] end
        if key=='elapsed' then return quest.holdElapsed end
        if key=='targets' then return quest.targets end
    end,__newindex=function(t,key,value)
        if shared[key] then record[key]=value
        elseif personal[key] then owner[key]=value
        elseif key=='elapsed' then quest.holdElapsed=value
        elseif key=='targets' then quest.targets=value
        else rawset(t,key,value) end
    end})
    return state
end
function State.advance(quest)
    if not quest.combat then return true end
    local record=quest.combat
    if not P.integer(record.phaseRevision,1,999999999) then return false end
    record.phaseRevision=record.phaseRevision+1
    effectStreams[record]=nil
    return true
end
function State.noteShot(state,shot)
    local b=bindings[state]
    if not b or b.actorId~='host' or not shot or (shot.actorId~='host' and shot.actorId~='companion') then return false end
    local record=b.record
    local stream=effectStreams[record]
    if not stream or stream.phaseRevision~=record.phaseRevision then
        stream={phaseRevision=record.phaseRevision,events={}}; effectStreams[record]=stream
    end
    if stream.lastSerial and shot.serial<=stream.lastSerial then return false end
    stream.lastSerial=shot.serial
    local event={serial=shot.serial,actorId=shot.actorId,windowId=shot.windowId,slot=shot.slot,point=shot.point,
        at=record.clock,hit=shot.hit==true,decal=shot.decal==true,impactFrame=shot.impactFrame,
        decalFrame=shot.decalFrame,damage=shot.damage or 0}
    stream.events[#stream.events+1]=event
    local count=0
    for index=#stream.events,1,-1 do
        local candidate=stream.events[index]
        if candidate.actorId==event.actorId then count=count+1 end
        if record.clock-candidate.at>State.EFFECT_TTL or count>State.MAX_EFFECTS_PER_ACTOR and candidate.actorId==event.actorId then
            table.remove(stream.events,index)
        end
    end
    return true
end
function State.effectEvents(state)
    local b=bindings[state]; if not b or b.actorId~='host' then return {} end
    local stream=effectStreams[b.record]
    if not stream or stream.phaseRevision~=b.record.phaseRevision then return {} end
    local result={}
    for _,event in ipairs(stream.events) do
        local elapsed=b.record.clock-event.at
        if elapsed>=0 and elapsed<=State.EFFECT_TTL then
            result[#result+1]={serial=event.serial,actorId=event.actorId,windowId=event.windowId,slot=event.slot,
                point=event.point,elapsed=elapsed,hit=event.hit,decal=event.decal,
                impactFrame=event.impactFrame,decalFrame=event.decalFrame,damage=event.damage}
        end
    end
    return result
end
function State.open(quest)
    -- This is called only after the host starts the next firing phase.
    if not State.advance(quest) then return false end
    if quest.combat and quest.combat.result=='intermission' then quest.combat.result=nil end
    return true
end
function State.prepare(data)
    local record=data.lastStand and data.lastStand.combat
    if record and record.version==1 then
        record.version=State.VERSION
        record.phaseRevision=1
    end
end
function State.reset(quest) quest.combat=nil end
function State.random(state,low,high)
    local b=bindings[state]
    if not b then return nil end
    local rng=Random.generator(b.data,b.data.coop.randomState or 1337)
    return low+(high-low)*rng()
end
function State.present(state,data,id,ids)
    local found=false; for _,candidate in ipairs(ids or {'host'}) do if candidate==id then found=true end end
    local root=Players.campaignOf(data)
    local actor=root.players and Players.get(root,id) or id=='host' and root
    return found and actor and (actor.health or actor.maxHealth or 20)>1 and State.owner(state,id)~=nil
end
function State.prepareParticipants(state,data,ids)
    local b=bindings[state]; if not b then return end
    for _,id in ipairs(ids or {'host'}) do
        if Players.get(b.data,id) then
            State.owner(state,id,true)
            local scope=id=='host' and state.quest or state.quest.shooterSessions and state.quest.shooterSessions[id]
            if not scope or not scope.weaponSession then
                Shooting.new(Players.forActor(b.data,id),require('game.catalog'),state.quest,state.width,state.height)
            end
        end
    end
end
function State.target(state,data,ids)
    local candidates={}; local seen={}
    for _,id in ipairs(ids or {'host'}) do
        if not seen[id] and State.present(state,data,id,ids) then candidates[#candidates+1]=id; seen[id]=true end
    end
    if #candidates==0 then return nil end
    local nextId=candidates[1]
    for i,id in ipairs(candidates) do if id==state.lastTargetActorId then nextId=candidates[i%#candidates+1]; break end end
    state.lastTargetActorId=nextId; return nextId
end
function State.updateDefenders(state,dt,ids)
    local record=State.record(state); if not record then return false end
    local step=dt/(state.reducedMotion and .1 or Tuning.coverSeconds)
    local enabled={}; for _,id in ipairs(ids or {'host','companion'}) do enabled[id]=true end
    for id,owner in pairs(record.defenders) do
        if enabled[id] then
        owner.coverProgress=owner.ducking and math.min(1,owner.coverProgress+step) or math.max(0,owner.coverProgress-step)
        owner.hitRecovery=math.max(0,owner.hitRecovery-dt)
        end
    end
    return true
end
function State.updateGuns(state,data,dt,width,height,ids)
    local b=bindings[state]; if not b then return false end
    local seen={}
    for _,id in ipairs(ids or {'host','companion'}) do
        local scope=id=='host' and state.quest or state.quest.shooterSessions and state.quest.shooterSessions[id]
        if not seen[id] and Players.get(b.data,id) and scope and scope.weaponSession then
            seen[id]=true
            Shooting.update(Sessions.view(scope.weaponSession,width,height),dt,Players.forActor(b.data,id),state.quest,width,height)
        end
    end
    return true
end
function State.canFight(state,data,ids)
    local b=bindings[state]
    if not b then return not Shooting.needsSupply(state.gun,data,state.quest) end
    for _,id in ipairs(ids or {'host'}) do
        local scope=id=='host' and state.quest or state.quest.shooterSessions and state.quest.shooterSessions[id]
        if State.present(state,data,id,ids) and scope and scope.weaponSession
            and not Shooting.needsSupply(Sessions.view(scope.weaponSession),Players.forActor(b.data,id),state.quest) then return true end
    end
    return false
end
function State.exposed(state,data,ids)
    for _,id in ipairs(ids or {'host'}) do
        local owner=State.owner(state,id)
        if State.present(state,data,id,ids) and not owner.ducking then return true end
    end
    return false
end
local function finite(n,low,high) return type(n)=='number' and n==n and n>=low and n<=high end
local function actor(data,id) return (id=='host' or id=='companion') and Players.get(data,id)~=nil end
local windows={wide=true,tall=true}
local statuses={hidden=true,appearing=true,exposed=true,firing=true,hiding=true,dying=true}
local atlases={}; for _,path in ipairs(Window.targetAtlases) do atlases[path]=true end
function State.validate(data)
    local quest=data.lastStand; local record=quest and quest.combat
    if record==nil then return true end
    if type(record)~='table' then return false end
    if not data.players or not P.fields(record,{version=true,phaseRevision=record.version==State.VERSION,entityId=true,clock=true,stage=true,enemyShots=true,
        spawnCursor=true,spawnCooldown=true,result=true,retreatReason=true,withdrawTimer=true,lastTargetActorId=true,defenders=true})
        or record.version~=1 and record.version~=State.VERSION
        or record.version==State.VERSION and not P.integer(record.phaseRevision,1,1e9)
        or not P.text(record.entityId,32) or not record.entityId:match('^e[1-9]%d*$')
        or not finite(record.clock,0,1e9) or not P.integer(record.stage,1,#Tuning.phases)
        or not P.integer(record.enemyShots,0,1e9) or not P.integer(record.spawnCursor,1,#Window.slots)
        or not finite(record.spawnCooldown,0,1e9) or type(record.defenders)~='table' or not record.defenders.host
        or not finite(quest.holdElapsed,0,1e9) or not P.integer(quest.kills,0,1e9)
        or not finite(quest.enemyMorale,0,100) or not finite(quest.positionIntegrity,0,100) then return false end
    if record.result~=nil and not ({intermission=true,retreat=true,withdrawing=true,victory=true})[record.result]
        or record.retreatReason~=nil and record.retreatReason~='wounded'
        or record.withdrawTimer~=nil and not finite(record.withdrawTimer,-1,1e9)
        or record.lastTargetActorId~=nil and not actor(data,record.lastTargetActorId) then return false end
    for id,owner in pairs(record.defenders) do
        if not actor(data,id) or not P.fields(owner,personal) or not windows[owner.windowId]
            or type(owner.ducking)~='boolean' or not finite(owner.coverProgress,0,1)
            or not finite(owner.hitRecovery,0,1e9) or not finite(owner.playerDamage,0,1e9) then return false end
    end
    if type(quest.targets)~='table' then return false end
    local count=0
    for index,target in pairs(quest.targets) do
        count=count+1
        if not P.integer(index,1,#Window.slots) or not P.fields(target,{slot=true,atlas=true,status=true,timer=true,
            health=true,maxHealth=true,hasSpawned=true,heavy=true,fired=true,withdrawal=true,targetActorId=true})
            or target.slot~=index or not atlases[target.atlas] or not statuses[target.status]
            or not finite(target.timer,-1e9,1e9) or not finite(target.maxHealth,1,100)
            or not finite(target.health,0,target.maxHealth) or type(target.hasSpawned)~='boolean'
            or target.heavy~=nil and type(target.heavy)~='boolean' or target.fired~=nil and type(target.fired)~='boolean'
            or target.withdrawal~=nil and not finite(target.withdrawal,0,1)
            or target.targetActorId~=nil and not actor(data,target.targetActorId) then return false end
    end
    return count==#Window.slots
end
return State
