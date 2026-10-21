-- Small, bounded reliable uploads reuse the checksummed chunk receiver. This
-- transports a personal character only; it never evaluates a save or imports a world.
local Baseline=require('game.net.baseline')
local P=require('game.net.protocol')
local Traveler=require('game.coop_traveler')
local Transfer={MAX_BYTES=65536}
local function kind(message,value)
    local result={}; for key,item in pairs(message) do result[key]=item end; result.type=value; return result
end
function Transfer.pack(profile,hash)
    local wire,reason=Traveler.pack(profile); if not wire then return nil,reason end
    local transfer,errorMessage=Baseline.pack({revision=profile.serial,sceneEpoch=1,profile=wire},1,hash)
    if not transfer then return nil,errorMessage end
    if transfer.header.bytes>Transfer.MAX_BYTES then return nil,'traveler_too_large' end
    return {header=kind(transfer.header,'traveler_header'),next=function()
        local part=transfer:next(); return part and kind(part,'traveler_part')
    end}
end
function Transfer.receiver(header,now,allowed,hash)
    if not P.envelope(header,'traveler_header') or not P.integer(header.bytes,1,Transfer.MAX_BYTES)
        or header.id~=1 or header.sceneEpoch~=1 then return nil,'invalid_traveler_header' end
    local decoded
    local receiver,reason=Baseline.receiver(kind(header,'baseline'),now,function(snapshot)
        if not P.fields(snapshot,{revision=true,sceneEpoch=true,profile=true}) or snapshot.sceneEpoch~=1 then return false end
        decoded=Traveler.unpack(snapshot.profile,allowed)
        return decoded~=nil and decoded.serial==snapshot.revision
    end,hash)
    if not receiver then return nil,reason end
    return {push=function(_,part,time)
        if not P.envelope(part,'traveler_part') then return nil,'invalid_traveler_part' end
        local result,errorMessage=receiver:push(kind(part,'part'),time)
        if result then return decoded end
        return result,errorMessage
    end}
end
return Transfer
