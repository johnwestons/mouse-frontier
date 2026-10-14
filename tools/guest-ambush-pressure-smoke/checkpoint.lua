-- Explicit typed keys preserve sparse numeric ownership maps in comparisons.
local Codec=require('game.net.codec')
local Checkpoint={}
function Checkpoint.encode(value,limits)
    local function mapped(v)
        if type(v)~='table' then return v end
        local result={}
        for key,item in pairs(v) do result[type(key)..':'..tostring(key)]=mapped(item) end
        return result
    end
    return assert(Codec.encode(mapped(value),limits))
end
function Checkpoint.returnReady(view,frame,oldEpoch)
    local data=view.runtime.saveData
    return view.ready and view.runtime.scene=='stop' and data.scene=='stop' and data.trainAmbush and not data.trainAmbush.active
        and view.epoch>oldEpoch and frame and frame.sceneEpoch==view.epoch and frame.motionId==view.motionId
        and frame.ready and view:inputAllowed()
end
function Checkpoint.returnFacts(data,limits)
    local function personal(actor)
        return {health=actor.health,maxHealth=actor.maxHealth,ammo=actor.ammo,stats=actor.stats,
            inventory=actor.inventory,equipment=actor.equipment,itemSlots=actor.itemSlots,
            weaponProficiency=actor.weaponProficiency}
    end
    return Checkpoint.encode({host=personal(data.players.host),guest=personal(data.players.companion),
        resources=data.resources,scrap=data.scrap,goodwill=data.goodwill,maintenance=data.maintenance,
        hostGun=data.trainAmbush.weaponSession,hostCached=data.trainAmbush.weaponSessions,
        guestGun=data.trainAmbush.shooterSessions.companion},limits)
end
return Checkpoint
