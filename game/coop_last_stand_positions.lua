-- Window assistance uses transactional occupancy, separate from activity locks.
local P=require('game.net.protocol')
local Players=require('game.coop_players')
local Life=require('game.coop_last_stand_lifecycle')
local State=require('game.coop_last_stand_position_state')
local Occupancy=require('game.coop_last_stand_occupancy')
local Shootout=require('game.last_stand_shootout')
local Sessions=require('game.coop_shooter_sessions')
local Shooting=require('game.first_person_shooting')
local Positions={}
function Positions.scopes(data,id)
    local life=data.lastStand and data.lastStand.lifecycle; if not life then return {} end
    return {'world:scene','entity:'..life.entityId,'player:'..id,'activity:lastStand:'..life.entityId..':positions'}
end
function Positions.domain(data)
    local q=data.lastStand; local life=q and q.lifecycle
    if not life or life.mode~='interior' and life.mode~='shootout' then return nil end
    if life.mode=='shootout' and not q.combat then return nil end
    return {questId=life.entityId,revision=life.revision,mode=life.mode,sceneEpoch=data.coop.sceneEpoch,
        phaseRevision=life.mode=='shootout' and q.combat.phaseRevision or nil}
end
local function occupancy(state)
    state.positionOccupancy=state.positionOccupancy or Occupancy.new(); return state.positionOccupancy
end
function Positions.occupied(data,state,bindings,now,id)
    local o=occupancy(state); if not Occupancy.sweep(o,Positions.domain(data),bindings,now) then return nil end
    local lease=Occupancy.forActor(o,id)
    local domain=Positions.domain(data)
    return lease and State.selected(data,id)==lease.windowId
        and (domain.mode~='shootout' or lease.shootingReady==true) and lease or nil
end
local function ready(data,id,context)
    local q=data.lastStand; local life=q and q.lifecycle; local actor=context.actorState(id)
    local scene=context.lastStandScene and context.lastStandScene()
    if not life or not scene or not scene.active or scene.questId~=life.entityId or scene.revision~=life.revision
        or scene.mode~=life.mode or scene.blocked or not actor or actor.screen~='game' or actor.scene~='stop'
        or actor.traveling or actor.changingCar or actor.activeActivity or Players.forActor(data,id).health<=1
        or id=='host' and scene.paused
        or id~='host' and (actor.movementReady~=true or actor.modalDomain~=Life.key(data)) then return false end
    if life.mode=='shootout' then
        local phase=context.lastStandPhase and context.lastStandPhase(id)
        return q.combat and not q.combat.result and phase and phase.active==true and not phase.paused
            and phase.encounterId==q.combat.entityId and phase.phaseRevision==q.combat.phaseRevision
    end
    return life.mode=='interior'
end
function Positions.maintain(data,state,bindings,now,context)
    local o=occupancy(state); local domain=Positions.domain(data)
    if not Occupancy.sweep(o,domain,bindings,now) then return false end
    for id in pairs(bindings) do
        local lease=Occupancy.forActor(o,id)
        if lease and State.selected(data,id)==lease.windowId and ready(data,id,context)
            and (domain.mode~='shootout' or lease.shootingReady==true) then
            Occupancy.renew(o,lease.id,id,bindings[id],domain,now,bindings)
        end
    end
    return true
end
local function claim(data,o,domain,id,generation,window,now,bindings)
    local lease,reason=Occupancy.acquire(o,domain,id,generation,window,now,bindings)
    if not lease then return nil,reason end
    State.ensure(data)
    local previous=State.selected(data,id); local stale=State.owner(data,window)
    -- Expired/disconnected reservation intent yields only in this checkpoint.
    if stale and stale~=id then State.release(data,stale) end
    local ok,why=State.claim(data,id,window); if not ok then return nil,why end
    return lease,nil,previous
end
function Positions.hostStart(data,transaction,bindings,window)
    local o=occupancy(transaction.state); local domain=Positions.domain(data)
    local swept,reason=Occupancy.sweep(o,domain,bindings,transaction.now); if not swept then return nil,reason end
    local lease,why=claim(data,o,domain,'host',0,window,transaction.now,bindings)
    if not lease then return nil,why end
    local other=Occupancy.forActor(o,'companion')
    return {companion=other and State.selected(data,'companion')==other.windowId and other.windowId or nil}
end
function Positions.open(data,transaction,bindings,window,carry)
    local o=occupancy(transaction.state); o.windows={}
    local domain=Positions.domain(data)
    local lease,reason=Occupancy.acquire(o,domain,'host',0,window,transaction.now,bindings)
    if not lease then return false,reason end
    lease.shootingReady=true
    if carry and carry.companion and bindings.companion then
        local other,why=Occupancy.acquire(o,domain,'companion',bindings.companion,carry.companion,transaction.now,bindings)
        if not other then return false,why end
    end
    return true
end
function Positions.install(authority,context)
    authority:register('lastStand.position',function(data,id,args,transaction)
        if not P.fields(args,{questId=true,revision=true,action=true,window=true,phaseRevision=true})
            or not P.text(args.questId,32) or not args.questId:match('^e[1-9]%d*$')
            or not P.integer(args.revision,1,Life.MAX)
            or args.action~='select' and args.action~='ready' and args.action~='release'
            or args.action~='release' and args.window~='wide' and args.window~='tall'
            or args.action=='release' and args.window~=nil then return nil,'invalid_args' end
        local q=data.lastStand; local life=q and q.lifecycle
        if not life or not Life.validate(data) or not State.validate(data) or life.entityId~=args.questId
            or q.victory or q.originStop~=data.location or data.scene~='stop' or not data.stopped
            or data.tacticalBattle or data.roamingEncounter or data.coop.journey
            or not ready(data,id,context) then return nil,'position_unavailable' end
        local scene=context.lastStandScene()
        if life.revision~=args.revision or scene.revision~=life.revision then return nil,'stale_phase' end
        if life.mode=='shootout' then
            if args.action=='select' or not P.integer(args.phaseRevision,1,Life.MAX) then return nil,'invalid_args' end
            if args.phaseRevision~=q.combat.phaseRevision then return nil,'stale_phase' end
        elseif life.mode~='interior' or args.action=='ready' or args.phaseRevision~=nil then return nil,'invalid_args' end
        if args.action=='select' then
            local pose=Life.pose(data,id); local x=args.window=='wide' and 350 or 660
            if not pose or (pose.x-x)^2+(pose.y-280)^2>82^2 then return nil,'position_distance' end
        end
        return {scopes=Positions.scopes(data,id),checkpoint=true,apply=function()
            local o=occupancy(transaction.state); local domain=Positions.domain(data)
            local swept,reason=Occupancy.sweep(o,domain,authority.bindings,transaction.now); if not swept then return nil,reason end
            local previous=State.selected(data,id); local lease
            if args.action=='release' then
                Occupancy.releaseActor(o,id); State.release(data,id)
                if q.combat and q.combat.defenders[id] then q.combat.defenders[id].ducking=true end
            else
                local why; lease,why,previous=claim(data,o,domain,id,transaction.generation,args.window,transaction.now,authority.bindings)
                if not lease then return nil,why end
                if args.action=='ready' then
                    local view=Shootout.commandView(q,data,id,nil,960,720)
                    view.windowId=args.window
                    local scope=Sessions.scope(Players.forActor(data,id),q)
                    if not scope.weaponSession then Shooting.new(Players.forActor(data,id),context.catalog,q,960,720) end
                    lease.shootingReady=true
                end
            end
            return {actorId=id,questId=life.entityId,revision=life.revision,action=args.action,
                windowId=args.window,previousWindowId=previous,leaseId=lease and lease.id,
                expiresIn=lease and Occupancy.TIMEOUT,phaseRevision=domain.phaseRevision}
        end}
    end)
end
return Positions
