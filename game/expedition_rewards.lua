local Areas=require("game.expedition_areas")
local CombatBalance=require("game.combat_balance")
local PlayerProgression=require("game.player_progression")
local TrainUpgradeBalance=require("game.train_upgrade_balance")

local Rewards={}

local function emptyReceipt()
    return {count=0,xp=0,coal=0,scrap=0,levels=0}
end

local function addReceipt(total,receipt)
    if not receipt then return end
    for _,key in ipairs({"count","xp","coal","scrap","levels"}) do total[key]=(total[key] or 0)+(receipt[key] or 0) end
end

-- Each authored enemy owns one reward receipt.  The killing mode and party
-- grouping cannot change its value or permit a second claim after reloading.
function Rewards.claimEnemy(data,catalog,definition,saved)
    if not data or not definition or not saved or saved.rewardResolved then return nil end
    if not saved.dead and (saved.hp or 1)>0 then return nil end
    local profile=CombatBalance.rewardProfile(definition.tier or CombatBalance.tierFor(data.location),1,false,definition.boss==true)
    local trait=data.trait or (catalog.characterTraitProfiles and catalog.characterTraitProfiles[1]) or {}
    local scrap=math.max(1,math.floor(math.floor((profile.scrapMin+profile.scrapMax)/2)*(trait.reward or 1)))+(trait.scrapBonus or 0)
    local coal=math.floor((profile.coalMin+profile.coalMax)/2)
    local receipt={count=1,xp=profile.xp,scrap=scrap,coal=TrainUpgradeBalance.addResource(data,"coal",coal),levels=0}
    data.scrap=(data.scrap or 0)+scrap
    receipt.levels=PlayerProgression.gainExperience(data,profile.xp)
    saved.rewardResolved=true
    saved.rewardReceipt=receipt
    return receipt
end

function Rewards.claimBattle(data,catalog,battle)
    local total=emptyReceipt()
    local encounter=battle and battle.encounter
    if not encounter or encounter.source~="expedition" then return total end
    local state=data.expeditions and data.expeditions[encounter.areaId]
    if not state or not state.mobs then return total end
    for _,unit in ipairs(battle.units or {}) do
        local saved=unit.team=="enemy" and unit.mobId and state.mobs[unit.mobId]
        if saved and (unit.hp or 1)<=0 then
            saved.hp=0; saved.dead=true
            local definition=Areas.mobDefinition(encounter.areaId,unit.mobId)
                or {id=unit.mobId,tier=encounter.tier,boss=unit.boss==true}
            addReceipt(total,Rewards.claimEnemy(data,catalog,definition,saved))
        end
    end
    return total
end

function Rewards.summary(receipt)
    if not receipt or receipt.count==0 then return "Rewards already collected." end
    return "+"..receipt.xp.." XP, +"..receipt.coal.." coal, +"..receipt.scrap.." scrap."..(receipt.levels>0 and " LEVEL UP!" or "")
end

return Rewards
