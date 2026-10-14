-- Host-owned, ephemeral activity locks. A transaction edits a detached state;
-- Authority commits it together with the campaign or discards both on failure.
-- No lease survives a saved-game reload or a peer-generation change.
local Leases={TIMEOUT=30}
local MAX_ID=2147483647

function Leases.new() return {nextId=1,resources={},positionOccupancy=require('game.coop_last_stand_occupancy').new()} end

function Leases.npcBusy(state,targetId,npc)
    for _,lease in pairs(state.resources) do
        local payload=lease.payload
        if payload and (payload.kind=='firstAid' or payload.kind=='conversation')
            and payload.targetId==targetId and payload.npc==npc then return true end
    end
    return false
end

function Leases.releaseActor(state,actorId)
    require('game.coop_player_pose').releaseActor(state,actorId)
    if state.positionOccupancy then require('game.coop_last_stand_occupancy').releaseActor(state.positionOccupancy,actorId) end
    for resource,lease in pairs(state.resources) do
        if lease.actorId==actorId then state.resources[resource]=nil end
    end
end

function Leases.sweep(state,now,epoch,bindings,modalDomain)
    for resource,lease in pairs(state.resources) do
        if now>=lease.expiresAt or lease.sceneEpoch~=epoch or bindings[lease.actorId]~=lease.generation
            or lease.payload and lease.payload.kind=='range' and modalDomain~=nil
            or lease.payload and lease.payload.modalDomain and lease.payload.modalDomain~=modalDomain then
            state.resources[resource]=nil
        end
    end
end

function Leases.acquire(state,resource,actorId,generation,epoch,now,payload)
    if state.resources[resource] then return nil,"activity_busy" end
    for _,lease in pairs(state.resources) do
        if lease.actorId==actorId then return nil,"actor_busy" end
    end
    if state.nextId>=MAX_ID then return nil,"lease_ids_exhausted" end
    local lease={id="l"..string.format("%.0f",state.nextId),resource=resource,actorId=actorId,
        generation=generation,sceneEpoch=epoch,startedAt=now,expiresAt=now+Leases.TIMEOUT,payload=payload}
    state.nextId=state.nextId+1
    state.resources[resource]=lease
    return lease
end

function Leases.find(state,id,actorId,generation,epoch,now)
    for _,lease in pairs(state.resources) do
        if lease.id==id then
            if lease.actorId~=actorId or lease.generation~=generation then return nil,"lease_owner" end
            if lease.sceneEpoch~=epoch or now>=lease.expiresAt then return nil,"lease_expired" end
            return lease
        end
    end
    return nil,"lease_expired"
end

function Leases.release(state,lease) state.resources[lease.resource]=nil end

return Leases
