-- Persistent personal cover and damage against one host-simulated convoy.
-- Legacy root fields remain the host's record; the guest never borrows them.
local Players=require('game.coop_players')
local Shooting=require('game.first_person_shooting')
local Sessions=require('game.coop_shooter_sessions')
local P=require('game.net.protocol')
local State={VERSION=1}
function State.owner(state,id,create)
    if id==nil or id=='host' then return state end
    if id~='companion' then return nil end
    local owners=state.defenders
    if not owners and create then owners={}; state.defenders=owners end
    if owners and not owners[id] and create then owners[id]={cover=false,coverProgress=0,playerDamage=0} end
    return owners and owners[id]
end
function State.ensure(data,state)
    if not data.players then return state end
    state.defendersVersion=State.VERSION
    state.defenders=state.defenders or {}
    state.cover=state.cover==true; state.coverProgress=state.coverProgress or 0; state.playerDamage=state.playerDamage or 0
    return state
end
function State.view(state,id)
    local owner=State.owner(state,id)
    if id==nil or id=='host' then return state end
    local result={}; for key,value in pairs(state) do result[key]=value end
    result.cover=owner and owner.cover or false; result.coverProgress=owner and owner.coverProgress or 0
    result.playerDamage=owner and owner.playerDamage or 0
    return result
end
function State.updateCover(state,dt)
    local step=dt/.16
    local function update(owner)
        owner.coverProgress=owner.cover and math.min(1,(owner.coverProgress or 0)+step) or math.max(0,(owner.coverProgress or 0)-step)
    end
    update(state)
    for _,owner in pairs(state.defenders or {}) do update(owner) end
end
function State.updateGuns(data,state,dt,width,height)
    for _,id in ipairs({'host','companion'}) do
        local actor=Players.get(data,id)
        local owner=id=='host' and state or state.shooterSessions and state.shooterSessions[id]
        if actor and owner and owner.weaponSession then
            Shooting.update(Sessions.view(owner.weaponSession,width,height),dt,Players.forActor(data,id),state,width,height)
        end
    end
end
function State.target(data,state,ids,previous)
    local candidates={}
    for _,id in ipairs(ids or {'host'}) do
        local actor=data.players and Players.get(data,id) or id=='host' and data
        if actor and (actor.health or 20)>1 and (id=='host' or State.owner(state,id)) then candidates[#candidates+1]=id end
    end
    if #candidates==0 then return nil end
    for i,id in ipairs(candidates) do if id==previous then return candidates[i%#candidates+1] end end
    return candidates[1]
end
function State.damage(data,state,id,amount,ids)
    local present=false; for _,candidate in ipairs(ids or {'host'}) do if candidate==id then present=true end end
    local actor=data.players and Players.get(data,id) or id=='host' and data
    local owner=State.owner(state,id)
    if not present or not actor or not owner or (actor.health or 20)<=1 or (owner.coverProgress or 0)>=1 then return 0 end
    local before=actor.health or 20; actor.health=math.max(1,before-amount)
    owner.playerDamage=(owner.playerDamage or 0)+before-actor.health
    return before-actor.health
end
local function fraction(n) return P.clock(n) and n<=1 end
function State.validate(data)
    local state=data.trainAmbush
    if not state or state.defendersVersion==nil then return true end
    if state.defendersVersion~=State.VERSION or not data.players or not P.text(state.entityId,32)
        or type(state.cover)~='boolean' or not fraction(state.coverProgress) or not P.clock(state.playerDamage)
        or state.playerDamage>1e9 or type(state.defenders)~='table' then return false end
    if state.lastTargetActorId~=nil and (state.lastTargetActorId~='host' and state.lastTargetActorId~='companion'
        or not Players.get(data,state.lastTargetActorId)) then return false end
    for id,owner in pairs(state.defenders) do
        if id~='companion' or not Players.get(data,id) or not P.fields(owner,{cover=true,coverProgress=true,playerDamage=true})
            or type(owner.cover)~='boolean' or not fraction(owner.coverProgress)
            or not P.clock(owner.playerDamage) or owner.playerDamage>1e9 then return false end
    end
    if state.vehicles~=nil and type(state.vehicles)~='table' then return false end
    for _,vehicle in pairs(state.vehicles or {}) do
        if type(vehicle)~='table' or vehicle.crew~=nil and type(vehicle.crew)~='table' then return false end
        for _,crew in pairs(vehicle.crew or {}) do
            if type(crew)~='table' then return false end
            if crew.targetActorId~=nil and (crew.targetActorId~='host' and crew.targetActorId~='companion'
                or not Players.get(data,crew.targetActorId)) then return false end
        end
    end
    return true
end
return State
