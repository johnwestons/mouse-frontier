-- Native acceptance comparisons use the actual wire ownership boundary.
-- Sparse numeric campaign maps need explicit keys before canonical encoding.
local Codec=require('game.net.codec')
local Checkpoint={}
function Checkpoint.encode(value)
    local function mapped(v)
        if type(v)~='table' then return v end
        local result={}; for k,item in pairs(v) do result[type(k)..':'..tostring(k)]=mapped(item) end
        return result
    end
    return assert(Codec.encode(mapped(value),{maxBytes=32768,maxDepth=16,maxEntries=2048,maxStringBytes=2048}))
end
function Checkpoint.ownership(actor)
    return {id=actor.id,character=actor.character,health=actor.health,maxHealth=actor.maxHealth,stats=actor.stats,
        equipment=actor.equipment,inventory=actor.inventory,itemSlots=actor.itemSlots,
        ammo=actor.ammo,weaponProficiency=actor.weaponProficiency,nextBattlePotions=actor.nextBattlePotions}
end
local function publicState(data)
    local s=assert(data.tacticalBattle); local b=s.battle; local units={}
    for _,u in ipairs(b.units) do
        local copy={}; for _,key in ipairs({'id','actorId','team','file','q','r','hp','maxHP','armor','aim','move',
            'guarding','regenRounds','regenAmount','armorBonus','armorBonusRounds','aimBonus','aimBonusRounds',
            'moveBonus','moveBonusRounds','bleedRounds','bleedDamage','staggeredRounds'}) do copy[key]=u[key] end
        units[#units+1]=copy
    end
    assert(data.players.host.id=='host' and data.players.companion.id=='companion','wrong battle actor identity')
    return {epoch=data.coop.sceneEpoch,scene=data.scene,location=data.location,encounterId=s.encounterId,revision=s.revision,
        active=b.active,round=b.round,phase=b.phase,moveUsed=b.moveUsed,chosenItemId=b.chosenItemId,
        units=units,tiles=b.tiles,tileVariants=b.tileVariants,obstacles=b.obstacles,abilitiesUsed=b.abilitiesUsed,
        host=Checkpoint.ownership(data.players.host),guest=Checkpoint.ownership(data.players.companion),scrap=data.scrap,
        goodwill=data.goodwill,encounter=data.encounters['2']}
end
function Checkpoint.publicSignature(data) return Checkpoint.encode(publicState(data)) end
function Checkpoint.privateSignature(data)
    local network=assert(data.coop.network,'host-private checkpoint identity missing')
    return Checkpoint.encode({state=publicState(data),campaignId=assert(network.campaignId),
        companionId=assert(network.companionId),rng=assert(data.coop.randomState)})
end
function Checkpoint.clientIdentity(client,campaignId,companionId,data)
    local credential=client and client.credential
    return type(client)=='table' and type(campaignId)=='string' and type(companionId)=='string'
        and client.campaignId==campaignId and credential and credential.campaignId==campaignId
        and credential.companionId==companionId and data.players.companion.id=='companion'
end
return Checkpoint
