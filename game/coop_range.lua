-- Each actor owns a separate saved lane; the stop's best score/reward is shared.
local P=require('game.net.protocol')
local Players=require('game.coop_players')
local Items=require('game.item_instances')
local Entities=require('game.coop_entities')
local Leases=require('game.coop_leases')
local Random=require('game.coop_random')
local Range=require('game.shooting_range')
local State=require('game.coop_range_state')
local StopHelp=require('game.stop_help_progression')
local Commands={POINT=1000000}
local names={'range.acquire','range.configure','range.ammo','range.fire','range.reload','range.release'}
local function reference(value,prefix) return P.text(value,32) and value:match('^'..prefix..'[1-9]%d*$')~=nil end
local function ordinary(data,id,context)
    local own=Players.forActor(data,id); local actor=context.actorState(id)
    if not own or own.health<=0 or not actor or actor.screen~='game' or actor.scene~='stop' or data.scene~='stop'
        or data.stopped~=true or actor.traveling or actor.changingCar or actor.encounterActive
        or actor.activityBlocked and actor.activeActivity~='range'
        or data.tacticalBattle or data.trainAmbush and data.trainAmbush.active
        or require('game.coop_last_stand_lifecycle').active(data)
        or id=='companion' and (actor.movementReady~=true or actor.modalDomain~=nil) then return nil,'range_unavailable' end
    return own,actor
end
local function spotAt(data,id,context,spotId)
    local own,actor=ordinary(data,id,context); if not own then return nil,actor end
    local spot,record=Entities.find(data,spotId)
    local layout=data.stopLayouts and data.stopLayouts[tostring(data.location)]
    if not spot or not record or record.kind~='rangeSpot' or not layout or layout.shootingRange~=spot
        or not Range.isHost(data.location) or not Range.near(spot,actor.x,actor.y) then return nil,'range_distance' end
    return spot,own,actor
end
local function ready(context,id,session,allowPaused)
    local status=context.rangeState and context.rangeState(id)
    return status and status.active==true and status.ready==true and (allowPaused or not status.paused)
        and (status.spotId==nil or status.spotId==session.spotId)
        and (status.roundRevision==nil or status.roundRevision==session.roundRevision)
end
local function base(id,session,lease)
    return {actorId=id,spotId=session.spotId,roundRevision=session.roundRevision,phase=session.phase,
        weaponId=session.itemId,weapon=session.weapon,loaded=session.loaded,fireMode=session.fireMode}
end
function Commands.view(data,activities,bindings,now,id,context)
    local lease=Commands.occupied(data,activities,bindings,now,id,context); if not lease then return nil end
    local view=State.view(data,id,context.catalog); view.leaseId=lease.id; view.expiresIn=math.max(0,lease.expiresAt-now)
    view.paused=lease.payload.paused==true
    return view
end
local function rounds(result,session,own)
    result.rounds=session.ammoType and own.ammo[session.ammoType] or nil; return result
end
function Commands.occupied(data,activities,bindings,now,id,context)
    local session=State.session(data,id); if not session or not bindings or bindings[id]==nil then return nil end
    local spot=spotAt(data,id,context,session.spotId); if not spot then return nil end
    local lease=activities.resources[State.resource(session.spotId,id)]
    if not lease or lease.actorId~=id or lease.generation~=bindings[id] or lease.sceneEpoch~=data.coop.sceneEpoch
        or now>=lease.expiresAt or not lease.payload or lease.payload.kind~='range'
        or lease.payload.spotId~=session.spotId or lease.payload.location~=data.location then return nil end
    return lease
end
-- Called only by the host simulation loop, never by a network argument. A
-- disconnected, stale, paused or unacknowledged lane freezes its exact progress.
function Commands.advance(data,activities,bindings,now,context,dt)
    local completed={}; local changed=false
    if type(dt)~='number' or dt~=dt or dt<0 or dt==math.huge then return completed,false end
    dt=math.min(.08,dt)
    for _,id in ipairs({'host','companion'}) do
        local session=State.session(data,id)
        local lease=session and Commands.occupied(data,activities,bindings,now,id,context)
        if lease and ready(context,id,session,true) then
            lease.expiresAt=now+Leases.TIMEOUT
            if session.phase=='play' and not lease.payload.paused and ready(context,id,session) then
                if session.time>0 then
                    local own=Players.forActor(data,id)
                    Range.serverUpdate(session,dt,own,context.catalog,Random.range(Random.generator(data,data.coop.randomState or context.rangeRandomSeed or 1)))
                    changed=true
                end
                if session.time==0 and session.completed then completed[#completed+1]=id end
            end
        end
    end
    if changed then assert(Entities.ensure(data)) end
    return completed,changed
end
local function shape(name,args)
    if name=='range.acquire' then return P.fields(args,{spotId=true}) and reference(args.spotId,'e') end
    if name=='range.release' then return P.fields(args,{leaseId=true}) and reference(args.leaseId,'l') end
    local allowed={leaseId=true,roundRevision=true,weaponId=true}
    if name=='range.configure' then allowed={leaseId=true,roundRevision=true,action=true,kind=true,direction=true,weaponId=true,paused=true}
    elseif name=='range.fire' then allowed.x=true; allowed.y=true end
    if not P.fields(args,allowed) or not reference(args.leaseId,'l') or not P.integer(args.roundRevision,1,State.MAX_REVISION) then return false end
    if name=='range.fire' then return reference(args.weaponId,'i') and P.integer(args.x,0,Commands.POINT) and P.integer(args.y,0,Commands.POINT) end
    if name~='range.configure' then return reference(args.weaponId,'i') end
    if args.action=='pause' then
        return type(args.paused)=='boolean' and args.kind==nil and args.direction==nil and args.weaponId==nil
    elseif args.paused~=nil then return false
    elseif args.action=='start' or args.action=='setup' or args.action=='complete' then
        return args.kind==nil and args.direction==nil and args.weaponId==nil
    elseif args.action=='change' then
        return args.weaponId==nil and (args.kind=='weapon' or args.kind=='motion' or args.kind=='material'
            or args.kind=='pattern' or args.kind=='distance' or args.kind=='length') and (args.direction==1 or args.direction==-1)
    elseif args.action=='mode' then return args.kind==nil and args.weaponId==nil and (args.direction==nil or args.direction==1 or args.direction==-1)
    elseif args.action=='weapon' then return args.kind==nil and args.direction==nil and reference(args.weaponId,'i') end
    return false
end
local function selected(own,session,weaponId,catalog)
    if session.itemId~=weaponId then return nil,'ownership' end
    local item=Items.owned(own,weaponId)
    if not item or item.name~=session.weapon or not catalog.weaponCombat[item.name]
        or catalog.weaponCombat[item.name].kind~='ranged' then return nil,'ownership' end
    if item.durability<=0 then return nil,'weapon_broken' end
    return item
end
local function settlementHelp(data,context)
    local layout=data.stopLayouts and data.stopLayouts[tostring(data.location)]
    local npc=layout and (layout.npcOutside or layout.npc) or data.currentNPC
    if npc==nil then npc=data.currentNPC end
    if not P.text(npc,128) then npc=nil end
    local help=context.stopHelp or StopHelp
    -- The original range awards relationship help to the settlement resident.
    -- Derive that scalar from the host world; no client NPC or saved view
    -- reference is accepted and the canonical session stays detached.
    return {add=function(save,amount,kind,_,location) return help.add(save,amount,kind,npc,location) end}
end
function Commands.install(authority,context)
    assert(context.catalog and context.actorState,'range authority context missing')
    for _,name in ipairs(names) do
        authority:register(name,function(data,id,args,transaction)
            if not shape(name,args) then return nil,'invalid_args' end
            local spotId,lease,session
            if name=='range.acquire' then spotId=args.spotId
            else
                local why; lease,why=Leases.find(transaction.state,args.leaseId,id,transaction.generation,data.coop.sceneEpoch,transaction.now)
                if not lease then return nil,why end
                if not lease.payload or lease.payload.kind~='range' then return nil,'wrong_activity' end
                spotId=lease.payload.spotId
                session=State.session(data,id)
                if not session or session.spotId~=spotId or lease.resource~=State.resource(spotId,id)
                    or lease.payload.location~=data.location then return nil,'range_unavailable' end
            end
            local spot,own=spotAt(data,id,context,spotId); if not spot then return nil,own end
            if name~='range.acquire' and name~='range.release' then
                if args.roundRevision~=session.roundRevision then return nil,'stale_round' end
                local pausing=name=='range.configure' and args.action=='pause'
                if not ready(context,id,session,pausing) then return nil,'range_not_ready' end
                if lease.payload.paused and not pausing then return nil,'range_paused' end
                if name~='range.configure' then local item,why=selected(own,session,args.weaponId,context.catalog); if not item then return nil,why end end
            end
            return {scopes=State.scopes(data,id,spotId,name,args),checkpoint=true,apply=function()
                if name=='range.acquire' then
                    local previous=State.session(data,id)
                    if previous and previous.spotId==spotId and previous.location==data.location then
                        session=previous
                        local ok,why=Range.serverRestore(session,own,context.catalog)
                        -- Missing selected equipment must still allow reopening
                        -- setup to choose another owned weapon. Firing remains
                        -- subject to exact current ownership below.
                        if not ok and why~='weapon_missing' then return nil,why end
                    else
                        local why; session,why=Range.serverNew(own,spot,context.catalog,{previous=previous})
                        if not session then return nil,why end
                        session.version=State.VERSION; session.spotId=spotId; session.location=data.location; session.roundRevision=1
                        State.ensure(data)[id]=session
                    end
                    lease=transaction.state.resources[State.resource(spotId,id)]
                    if lease then
                        if lease.actorId~=id or lease.generation~=transaction.generation or lease.sceneEpoch~=data.coop.sceneEpoch then return nil,'lease_owner' end
                        lease.expiresAt=transaction.now+Leases.TIMEOUT
                    else
                        local why; lease,why=Leases.acquire(transaction.state,State.resource(spotId,id),id,transaction.generation,
                            data.coop.sceneEpoch,transaction.now,{kind='range',spotId=spotId,location=data.location,paused=false})
                        if not lease then return nil,why end
                    end
                    assert(Entities.ensure(data)); local result=rounds(base(id,session,lease),session,own)
                    result.leaseId=lease.id; result.expiresIn=Leases.TIMEOUT; result.paused=lease.payload.paused==true; return result
                elseif name=='range.release' then
                    local result=rounds(base(id,session,lease),session,own); Leases.release(transaction.state,lease)
                    result.released=true; result.leaseId=lease.id; return result
                end
                lease.expiresAt=transaction.now+Leases.TIMEOUT
                local result
                if name=='range.configure' then
                    local ok,why
                    local beforePhase,beforeWeapon=session.phase,session.itemId
                    if args.action=='pause' then lease.payload.paused=args.paused; ok=true
                    elseif args.action=='start' then
                        if session.roundRevision>=State.MAX_REVISION then return nil,'round_exhausted' end
                        ok,why=Range.serverStart(session,own,context.catalog)
                        if ok then session.roundRevision=session.roundRevision+1 end
                    elseif args.action=='setup' then
                        if session.phase=='lobby' then ok=true else ok=Range.serverSetup(session) end
                    elseif args.action=='change' then ok=Range.serverConfigure(session,own,context.catalog,args.kind,args.direction)
                    elseif args.action=='mode' then
                        if session.phase~='play' then return nil,'wrong_phase' end
                        ok=Range.serverMode(session,args.direction)
                    elseif args.action=='weapon' then
                        if session.phase~='lobby' and session.phase~='results' then return nil,'wrong_phase' end
                        local item=Items.owned(own,args.weaponId)
                        if not item or not context.catalog.weaponCombat[item.name] or context.catalog.weaponCombat[item.name].kind~='ranged' then return nil,'ownership' end
                        local options=Range.ownedWeapons(own,context.catalog); local index
                        for i,key in ipairs(options) do if key==args.weaponId then index=i end end
                        if not index then return nil,'ownership' end
                        -- Cycling is the original checked selection rule; bounded
                        -- inventory size prevents untrusted arbitrary selectors.
                        for _=1,#options do
                            if session.itemId==args.weaponId then ok=true; break end
                            ok=Range.serverConfigure(session,own,context.catalog,'weapon',1); if not ok then break end
                        end
                        ok=ok and session.itemId==args.weaponId
                    else
                        if session.phase=='results' and session.result then ok=true
                        elseif session.phase~='play' or session.time~=0 or session.completed~=true then return nil,'round_not_complete'
                        else ok=Range.serverComplete(session,data,spot,settlementHelp(data,context))~=nil end
                    end
                    if not ok then return nil,why or 'configuration_unavailable' end
                    if args.action~='start' and args.action~='mode' and args.action~='pause'
                        and (session.phase~=beforePhase or session.itemId~=beforeWeapon or args.action=='change') then
                        if session.roundRevision>=State.MAX_REVISION then return nil,'round_exhausted' end
                        session.roundRevision=session.roundRevision+1
                    end
                    result=base(id,session,lease); result.action=args.action
                    if args.action=='pause' then result.paused=lease.payload.paused==true end
                    if args.action=='complete' then
                        result.completed=true; for key,value in pairs(session.result) do result[key]=value end
                    end
                elseif name=='range.fire' then
                    local oldHits=session.hits
                    local ok,why=Range.serverFire(session,own,context.catalog,args.x/Commands.POINT*960,args.y/Commands.POINT*720,
                        Random.range(Random.generator(data,transaction.randomSeed)))
                    if not ok then return nil,why or 'fire_unavailable' end
                    result=base(id,session,lease); result.fired=true; result.hit=session.hits>oldHits
                elseif name=='range.reload' then
                    if not Range.serverReload(session,own,context.catalog) then return nil,'reload_unavailable' end
                    result=base(id,session,lease); result.reloading=session.reloadTimer>0
                else
                    local ok,offer=Range.serverBuyAmmo(session,own,context.catalog)
                    if not ok then return nil,'ammo_unavailable' end
                    result=base(id,session,lease); result.ammoType=offer.ammo; result.purchasedRounds=offer.amount; result.cost=offer.cost
                end
                assert(Entities.ensure(data)); return rounds(result,session,own)
            end}
        end)
    end
end
return Commands
