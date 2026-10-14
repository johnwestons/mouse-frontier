-- Ephemeral window occupancy. Never store this state in the campaign save,
-- and never put these reservations in the generic activity-lock collection.
local P=require('game.net.protocol')
local Occupancy={TIMEOUT=30,MIN_RENEW_INTERVAL=.25,MAX=1000000000}
local windows={wide=true,tall=true}
local function time(now) return P.clock(now) and now<=1e12 end
local function domainValid(d)
    return P.fields(d,{questId=true,revision=true,mode=true,sceneEpoch=true,phaseRevision=true})
        and P.text(d.questId,32) and d.questId:match('^e[1-9]%d*$')~=nil
        and P.integer(d.revision,1,Occupancy.MAX) and P.integer(d.sceneEpoch,1,2147483647)
        and (d.mode=='interior' and d.phaseRevision==nil
            or d.mode=='shootout' and P.integer(d.phaseRevision,1,Occupancy.MAX))
end
local function same(a,b)
    return a.questId==b.questId and a.revision==b.revision and a.mode==b.mode
        and a.sceneEpoch==b.sceneEpoch and a.phaseRevision==b.phaseRevision
end
local function bound(id,generation,bindings)
    return type(bindings)=='table' and (id=='host' and generation==0
        or id=='companion' and P.integer(generation,1,2147483647)) and bindings[id]==generation
end
local function clock(state,now)
    if not time(now) or now<(state.lastNow or 0) then return false end
    state.lastNow=now; return true
end
function Occupancy.new() return {nextId=1,windows={}} end
function Occupancy.sweep(state,domain,bindings,now)
    if not clock(state,now) then return false,'invalid_time' end
    for window,lease in pairs(state.windows) do
        if now>=lease.expiresAt or not domainValid(domain) or not same(lease.domain,domain)
            or not bound(lease.actorId,lease.generation,bindings) then state.windows[window]=nil end
    end
    return true
end
function Occupancy.acquire(state,domain,id,generation,window,now,bindings)
    if not domainValid(domain) or not windows[window] or not bound(id,generation,bindings) then return nil,'invalid_occupancy' end
    local swept,reason=Occupancy.sweep(state,domain,bindings,now); if not swept then return nil,reason end
    local occupied=state.windows[window]
    if occupied and occupied.actorId~=id then return nil,'position_occupied' end
    if occupied then return Occupancy.renew(state,occupied.id,id,generation,domain,now,bindings) end
    if state.nextId>=2147483647 then return nil,'position_ids_exhausted' end
    local lease={id='p'..string.format('%.0f',state.nextId),actorId=id,generation=generation,windowId=window,
        domain={questId=domain.questId,revision=domain.revision,mode=domain.mode,sceneEpoch=domain.sceneEpoch,phaseRevision=domain.phaseRevision},
        startedAt=now,lastRenewedAt=now,expiresAt=now+Occupancy.TIMEOUT}
    -- Switching releases the old window only after the new one is available.
    Occupancy.releaseActor(state,id)
    state.nextId=state.nextId+1; state.windows[window]=lease
    return lease
end
function Occupancy.find(state,token,id,generation,domain,now,bindings)
    if not domainValid(domain) or not bound(id,generation,bindings) then return nil,'invalid_occupancy' end
    local swept,reason=Occupancy.sweep(state,domain,bindings,now); if not swept then return nil,reason end
    for _,lease in pairs(state.windows) do
        if lease.id==token then
            if lease.actorId~=id or lease.generation~=generation then return nil,'position_owner' end
            return lease
        end
    end
    return nil,'position_expired'
end
function Occupancy.renew(state,token,id,generation,domain,now,bindings)
    local lease,reason=Occupancy.find(state,token,id,generation,domain,now,bindings)
    if not lease then return nil,reason end
    if now-lease.lastRenewedAt>=Occupancy.MIN_RENEW_INTERVAL then
        lease.lastRenewedAt=now; lease.expiresAt=now+Occupancy.TIMEOUT
    end
    return lease
end
function Occupancy.release(state,token,id,generation,domain,now,bindings)
    local lease,reason=Occupancy.find(state,token,id,generation,domain,now,bindings)
    if not lease then return false,reason end
    state.windows[lease.windowId]=nil; return true
end
function Occupancy.releaseActor(state,id)
    for window,lease in pairs(state.windows) do if lease.actorId==id then state.windows[window]=nil end end
end
function Occupancy.owner(state,window) local lease=state.windows[window]; return lease and lease.actorId end
function Occupancy.forActor(state,id)
    for _,lease in pairs(state.windows) do if lease.actorId==id then return lease end end
end
return Occupancy
