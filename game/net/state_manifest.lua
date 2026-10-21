-- Every persistent field needs an explicit wire ownership decision. New save
-- fields fail projection until classified; migration flags stay host-local.
local M={VERSION=1,SCHEMA=47}
M.groups={
    journey={'location','scene','stopped','activeHouseDoor','lastStopDoor','activeExpeditionArea','activeHelpQuestId',
        'visitedStops','arrivalNotice'},
    train={'resources','scrap','goodwill','trainCars','engineLevel','maintenance','outfitCrafting'},
    world={'droppedItems','houseInitialized','houseLayoutsArranged','stopLayouts','stopSludges','expeditions','crowCaravans','lootRolls','lootContainerCursor'},
    people={'npcRoster','currentNPC','npcStates','npcOffers','npcWeapons','passengers','relationships','npcIdentities'},
    quests={'supplyQuests','mailQuests','questAsked','helpHistory','helpQuestSessions','supplyDeliveryCycle'},
    story={'encounters','choices','events','eventProgress','eventHistory','eventCategoryHistory','mysteryStops',
        'conversations','finale','lastStand','trainAmbush','expeditionBattle','pendingRewards','homeStop'},
    combat={'tacticalBattle','roamingCombat','roamingEncounter','rangeSessions'},
}
M.actorFields={'id','character','trait','traitBaselineApplied','health','maxHealth','stats','inventory','inventoryCapacity',
    'equipment','ammo','backpack','wearables','weaponDurability','weaponProficiency','nextBattlePotions',
    'battlePotionLootChance','playerX','playerY','playerFacing','activeCar','weapons','itemSlots','presence','travelIdentity','travelReturn'}
M.ignored={version=true,coop=true,itemIdentity=true,localTraveler=true,travelerHistory=true,accessibility=true,weaponDropsAdded=true,ammoDropsAdded=true,
    medicalDropsAdded=true,starterChestAdded=true,specialItemsAdded=true,lootContainerMigration=true,expandedLootAdded=true,
    radioAdded=true,lootBalanceVersion=true,trainObjectLayoutVersion=true,forceEventId=true}
M.order={'journey','train','world','people','quests','story','combat','radio','authority','actor:host','actor:companion'}
M.known={players=true,audio=true}; M.allowed={}
for name,fields in pairs(M.groups) do
    local allowed={}; M.allowed[name]=allowed
    for _,field in ipairs(fields) do assert(not M.known[field]); M.known[field]=true; allowed[field]=true end
end
for field in pairs(M.ignored) do assert(not M.known[field]); M.known[field]=true end
M.actorAllowed={}; for _,field in ipairs(M.actorFields) do M.actorAllowed[field]=true end
M.allowed.radio={station=true,rainEnabled=true}
M.allowed.authority={sourceRevision=true,scopes=true,journey=true}
M.allowed['actor:host']=M.actorAllowed; M.allowed['actor:companion']=M.actorAllowed
return M
