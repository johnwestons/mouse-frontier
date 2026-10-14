-- Guard Fox supplies each actor's own loan pool. No firearm factory or story
-- transition is needed while walking inside the farmhouse.
local P=require('game.net.protocol')
local Players=require('game.coop_players')
local Life=require('game.coop_last_stand_lifecycle')
local Sessions=require('game.coop_shooter_sessions')
local Shootout=require('game.last_stand_shootout')
local Provider={}
function Provider.scope(data,id)
    local quest=data.lastStand
    return id=='host' and quest or quest and quest.shooterSessions and quest.shooterSessions[id]
end
function Provider.needed(data,id,catalog)
    local scope=Provider.scope(data,id)
    if scope and scope.loanActive and (scope.loanAmmo or 0)>0 then return false end
    return not Shootout.hasUsableFirearm(Players.forActor(data,id),catalog)
end
function Provider.scopes(data,id)
    local life=data.lastStand and data.lastStand.lifecycle
    if not life then return {} end
    return {'world:scene','entity:'..life.entityId,'player:'..id,'story:events'}
end
function Provider.prepare(data,id,args,context)
    if not P.fields(args,{mode=true,questId=true,revision=true}) or args.mode~='farmhouse'
        or not P.text(args.questId,32) or not P.integer(args.revision,1,Life.MAX) then return nil,'invalid_args' end
    local quest=data.lastStand; local life=quest and quest.lifecycle
    local scene=context.lastStandScene and context.lastStandScene()
    local actor=context.actorState(id); local pose=Life.pose(data,id)
    if not life or not Life.validate(data) or life.entityId~=args.questId or life.mode~='interior'
        or quest.victory or quest.originStop~=data.location or data.scene~='stop' or not data.stopped
        or data.tacticalBattle or data.roamingEncounter or data.coop.journey
        or not scene or not scene.active or scene.questId~=life.entityId or scene.mode~=life.mode or scene.blocked
        or not actor or actor.screen~='game' or actor.scene~='stop' or actor.traveling or actor.changingCar or actor.activeActivity
        or id=='host' and scene.paused
        or id~='host' and (actor.movementReady~=true or actor.modalDomain~=Life.key(data))
        or not pose or Players.forActor(data,id).health<=0 then return nil,'provider_unavailable' end
    if life.revision~=args.revision or scene.revision~=life.revision then return nil,'stale_phase' end
    if (pose.x-300)^2+(pose.y-335)^2>60^2 then return nil,'provider_distance' end
    if not Provider.needed(data,id,context.catalog) then return nil,'supply_unavailable' end
    return {scopes=Provider.scopes(data,id),checkpoint=true,apply=function()
        local scope=Sessions.scope(Players.forActor(data,id),quest)
        local first=not scope.loanActive; local before=scope.loanAmmo or 0
        scope.loanActive=true; scope.loanAmmo=math.max(before,first and 48 or 12)
        if id=='host' then quest.conversations=quest.conversations or {}; quest.conversations['borrow-rifle']=true end
        return {actorId=id,mode='farmhouse',questId=life.entityId,revision=life.revision,
            loanActive=true,loanAmmo=scope.loanAmmo,suppliedRounds=scope.loanAmmo-before}
    end}
end
return Provider
