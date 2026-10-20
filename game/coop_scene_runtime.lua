local NPCs=require("game.scene_npcs")
local Engines=require("game.engine_upgrades")
local Scenes={}
function Scenes.restoreJourney(runtime)
    local data=runtime.saveData
    local leg=data and data.coop and data.coop.journey
    if not leg then runtime.travelTransition=nil; return end
    local arrived=leg.phase=="arrived"
    local timing=Engines.timings(data.engineLevel,leg.maintenanceCondition)
    runtime.travelTransition={t=arrived and timing.change or 0,changed=arrived,departSoundPlayed=true,maintenanceCondition=leg.maintenanceCondition}
end
function Scenes.install(context)
    local runtime,ui=context.runtime,context.ui
    ui.transitionParty=function(name,args) return context.commands.submit(name,args or {}) end
    ui.applyPartyState=function(result,name)
        runtime.session:acceptPartyState(result)
        runtime.state=result.screen
        runtime.carTransition=nil
        if ui.suspendOutfitWorkbench then ui.suspendOutfitWorkbench() end
        if ui.cancelWeaponRepair then ui.cancelWeaponRepair() end
        if ui.closeDecoration then ui.closeDecoration() end
        if ui.pauseFirstAid then ui.pauseFirstAid() end
        if context.closeMaintenance then context.closeMaintenance() end
        context.neutralize()
        runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil
        runtime.tradeOpen=false; runtime.giftOpen=false; runtime.mapOpen=false
        runtime.trainUpgradeOpen=false; runtime.travelConfirm=false
        runtime.dialogue=nil; runtime.questOffer=nil; runtime.helpDialogue=nil
        runtime.holdPickupIndex=nil; runtime.holdPickupTime=0; runtime.draggedSlot=nil; runtime.inventoryDragActive=false
        runtime.nearbyItem=nil; runtime.nearChest=nil; runtime.nearHouse=false; runtime.nearReturnTrain=false
        runtime.nearExpedition=false; runtime.nearCaravan=false; ui.interaction=nil
        runtime.npcActor=NPCs.prepare(runtime.saveData,context.catalog)
        runtime.npcActors=NPCs.list(runtime.saveData,runtime.scene,runtime.saveData.activeHouseDoor)
        if not NPCs.hasResidents(runtime.saveData) and runtime.npcActor then runtime.npcActors={runtime.npcActor} end
        NPCs.refresh(runtime,NPCs.locked(runtime))
        if name=="travel.depart" then Scenes.restoreJourney(runtime)
        elseif name=="travel.arrive" then runtime.travelTransition.changed=true
        elseif name=="travel.finish" then
            runtime.travelTransition=nil; runtime.sceneryOffset=0; runtime.landscapeOffset=0
            if result.arrivalNotice and result.screen~="ending" then runtime.dialogue={speaker="Passenger",text=runtime.saveData.arrivalNotice,timer=4} end
        end
        if context.applyScene then context.applyScene(result,name) end
    end
end
return Scenes
