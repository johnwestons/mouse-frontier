local function required(context, name, expectedType)
  local value=context[name]
  assert(value~=nil,"session bootstrap requires "..name)
  if expectedType then assert(type(value)==expectedType,"session bootstrap "..name.." must be a "..expectedType) end
  return value
end

local function new(context)
  assert(type(context)=="table","session bootstrap requires an explicit context")
  local SaveSchema=required(context,"saveSchema","table")
  local characters=required(context,"characters","table")
  local characterImages=required(context,"characterImages","table")
  local npcImages=required(context,"npcImages","table")
  local car=required(context,"car","table")
  local ui=required(context,"ui","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local runtime=required(context,"runtime","table")
  local filesystem=required(context,"filesystem","table")
  local Roster=required(context,"roster","table")
  local House=required(context,"house","table")
  local Catalog=required(context,"catalog","table")
  local Maintenance=required(context,"maintenance","table")
  local EngineUpgrades=required(context,"engineUpgrades","table")
  local Passengers=required(context,"passengers","table")
  local Events=required(context,"events","table")
  local Settlements=required(context,"settlements","table")
  local trainObjectBounds=required(context,"trainObjectBounds","function")
  local trainFloorBounds=required(context,"trainFloorBounds","function")
  local clampToTrainFloor=required(context,"clampToTrainFloor","function")
  local isFurnitureItem=required(context,"isFurnitureItem","function")
  local resetStopSludges=required(context,"resetStopSludges","function")

  local function newSave(character)
      local npcRoster, seen = {}, {}
      for _, file in ipairs(filesystem.getDirectoryItems("assets/sprites/NPCS")) do
          if Roster.isNpcCandidate(file) then npcRoster[#npcRoster + 1], seen[file] = file, true end
      end
      for _, file in ipairs(characters) do
          if Roster.isNpcCandidate(file) and file ~= character and not seen[file] then npcRoster[#npcRoster + 1] = file end
      end
      table.sort(npcRoster)
      local worldItems = {}
      worldItems[#worldItems+1]={name="travel-chest",x=car.x+275,y=car.y+255,scene="train",carIndex=1,scale=1,rotation=0,storage={}}
      worldItems[#worldItems+1]={name="boombox-radio",x=car.x+470,y=car.y+285,scene="train",carIndex=1,scale=1.15,rotation=0,permanent=true}
      worldItems[#worldItems+1]={name="mailbox-reward",x=car.x+560,y=car.y+270,scene="train",carIndex=1,scale=1.15,rotation=0,permanent=true,mailbox=true,mailUnread=false,storage={}}
      local result={
          version = SaveSchema.CURRENT_VERSION, character = character, location = 1, scene = "train", stopped = true,
          npcRoster = npcRoster, currentNPC = npcRoster[1],
          resources = {food = 10, water = 10, coal = 10, oil = 10},
          health = 20, maxHealth = 20, stats={level=1,xp=0,nextXP=10},
          equipment = {"frontier-short-sword", "trail-slingshot"},
          ammo = {rocks=12,arrows=0,["ball-bearings"]=0,["9mm"]=0,["45-cal"]=0,["556"]=0,["22lr"]=0,["30-carbine"]=0,["8mm"]=0,["380-acp"]=0,["32-acp"]=0,["12-gauge"]=0,["762x39"]=0},
          inventory = {"orange-rose-vase", "cowboy-hat", nil, nil, nil, nil},
          droppedItems = worldItems, visitedStops = {[1] = true}, houseInitialized = {}, houseLayoutsArranged = {}, npcStates = {},
          encounters = {}, weaponDropsAdded = true, starterChestAdded=true, medicalDropsAdded=true, ammoDropsAdded=true,
          choices = {}, stopLayouts = {}, stopSludges={}, events = {}, eventCategoryHistory={}, weaponDurability={}, weaponProficiency={}, mailQuests={}, supplyQuests={}, passengers={}, questAsked={}, lootRolls={}, npcOffers={}, npcWeapons={},
          maintenance={condition=72,lastServicedStop=0,totalServices=0,totalWear=0},
          inventoryCapacity=6, backpack=nil,
          scrap=0, trainCars={"living-car"}, activeCar=1, engineLevel=0,
          specialItemsAdded=true, lootContainerMigration=true, expandedLootAdded=true, radioAdded=true,lootBalanceVersion=1,
          audio={station="8bit",musicVolume=.10,sfxVolume=.55,rainVolume=.20,rainEnabled=false,musicPaused=false,musicMuted=false}, playerX = car.x + 300, playerY = car.y + 285
      }
      for i,name in ipairs({"coal-bucket","pickaxe","potted-sprout","flower-pot","potted-flowers"}) do House.storeLoot(result,Catalog,name,i) end
      return result
  end

  local function enterGame(data)
      if type(data)~="table" then return false end
      local migrated,migrationError=SaveSchema.migrate(data)
      if not migrated then return false,migrationError end
      data=migrated
      Maintenance.close(maintenanceSession)
      ui.itemOrderRevision=(ui.itemOrderRevision or 0)+1; ui.itemOrderCache={}
      data.location=math.max(1,math.min(50,math.floor(tonumber(data.location) or 1)))
      data.resources=type(data.resources)=="table" and data.resources or {}
      for _,name in ipairs({"food","water","coal"}) do data.resources[name]=math.max(0,tonumber(data.resources[name]) or 0) end
      -- Existing saves predate train oil; give them the same starter reserve as
      -- a new game instead of loading them into an unwinnable empty state.
      data.resources.oil=math.max(0,tonumber(data.resources.oil) or 10)
      data.scene = data.scene or "train"
      data.stopped = data.stopped == nil and true or data.stopped
      data.droppedItems = data.droppedItems or {}
      for _, item in ipairs(data.droppedItems) do
          item.scene = item.scene or "train"
          if item.scene=="train" then
              item.carIndex=item.carIndex or 1
              local left,right,top,bottom=trainObjectBounds(); item.x=math.max(left,math.min(right,item.x or left)); item.y=math.max(top,math.min(bottom,item.y or top))
          end
          if item.scene ~= "train" then item.location = item.location or data.location end
      end
      data.visitedStops = data.visitedStops or {[data.location or 1] = true}
      data.visitedStops[data.location or 1] = true
      data.houseInitialized = data.houseInitialized or {}
      data.houseLayoutsArranged = data.houseLayoutsArranged or {}
      data.npcStates = data.npcStates or {}
      data.stopLayouts = data.stopLayouts or {}
      data.stopSludges = data.stopSludges or {}
      data.events = data.events or {}
      Maintenance.ensure(data)
      data.weaponDurability=data.weaponDurability or {}
      data.weaponProficiency=data.weaponProficiency or {}
      data.supplyQuests=data.supplyQuests or {}
      data.mailQuests=data.mailQuests or {}
      data.passengers=data.passengers or {}
      data.questAsked=data.questAsked or {}
      data.lootRolls=data.lootRolls or {}
      if (data.lootBalanceVersion or 0)<1 then
          for i=#data.droppedItems,1,-1 do
              local item=data.droppedItems[i]
              local rollKey=tostring(item.location or data.location)..":"..tostring(item.houseDoor or 1)
              if item.scene=="house" and Catalog.storageCapacities[item.name] and not item.droppedByPlayer and not data.lootRolls[rollKey] then
                  table.remove(data.droppedItems,i)
              end
          end
          data.lootBalanceVersion=1
      end
      data.nextBattlePotions=data.nextBattlePotions or {}
      data.npcOffers=data.npcOffers or {}; data.npcWeapons=data.npcWeapons or {}
      data.inventoryCapacity=data.inventoryCapacity or 6
      data.scrap=data.scrap or 0
      data.audio=data.audio or {station="8bit",musicVolume=.10,sfxVolume=.55,rainVolume=.20,rainEnabled=false}
      data.audio.musicPaused=data.audio.musicPaused or false; data.audio.musicMuted=data.audio.musicMuted or false
      data.audio.station=data.audio.station or "8bit"; if data.audio.musicVolume==nil then data.audio.musicVolume=.10 end; data.audio.sfxVolume=data.audio.sfxVolume or .55; data.audio.rainVolume=data.audio.rainVolume or .20
      if data.audio.rainEnabled==nil then data.audio.rainEnabled=data.audio.station=="chill" end
      data.trainCars=data.trainCars or {"living-car"}
      data.activeCar=math.max(1,math.min(#data.trainCars,data.activeCar or 1))
      data.engineLevel=math.max(0,math.min(#EngineUpgrades.tiers-1,data.engineLevel or 0))
      local assignedTrait=Catalog.characterTrait(data.character)
      if not data.traitBaselineApplied then
          data.maxHealth=(data.maxHealth or 20)+(assignedTrait.maxHealth or 0)
          data.traitBaselineApplied=true
      elseif not data.trait or data.trait.name~=assignedTrait.name then
          data.maxHealth=(data.maxHealth or 20)-(data.trait and data.trait.maxHealth or 0)+(assignedTrait.maxHealth or 0)
      end
      data.trait=assignedTrait
      data.health=math.min(data.maxHealth,data.health or data.maxHealth)
      for i,item in ipairs(data.droppedItems) do item.layer=item.layer or i end
      if not data.specialItemsAdded then data.specialItemsAdded=true end
      for i,passenger in ipairs(data.passengers) do
          local left,right,top,bottom=trainFloorBounds(); passenger.x,passenger.y=clampToTrainFloor(passenger.x or car.x+230+(i-1)*85,passenger.y or (top+bottom)/2)
          passenger.homeX=math.max(left,math.min(right,passenger.homeX or passenger.x)); passenger.homeY=math.max(top,math.min(bottom,passenger.homeY or passenger.y)); passenger.wait=passenger.wait or 1; passenger.job=passenger.job or Passengers.jobFor(passenger.npc); passenger.pose=passenger.pose or "idle"; passenger.carIndex=math.max(1,math.min(#data.trainCars,passenger.carIndex or 1))
      end
      data.health, data.maxHealth = data.health or 20, data.maxHealth or 20
      data.stats=data.stats or {level=1,xp=0,nextXP=10}
      data.inventory = data.inventory or {}
      data.equipment = data.equipment or {}
      data.ammo=data.ammo or {}
      for _,name in ipairs({"rocks","arrows","ball-bearings","9mm","45-cal","556","22lr","30-carbine","8mm","380-acp","32-acp","12-gauge","762x39"}) do
          data.ammo[name]=math.max(0,tonumber(data.ammo[name]) or 0)
      end
      if not data.ammoDropsAdded then data.ammoDropsAdded=true end
      data.weapons=nil
      if not data.weaponDropsAdded then data.weaponDropsAdded=true end
      if not data.starterChestAdded then
          local found=false; for _,item in ipairs(data.droppedItems) do if item.name=="travel-chest" and item.scene=="train" then item.storage=item.storage or {}; found=true end end
          if not found then data.droppedItems[#data.droppedItems+1]={name="travel-chest",x=car.x+165,y=car.y+285,scene="train",scale=1,rotation=0,storage={}} end
          data.starterChestAdded=true
      end
      for _,item in ipairs(data.droppedItems) do if Catalog.storageCapacities[item.name] then item.storage=item.storage or {} end end
      if not data.radioAdded then
          data.droppedItems[#data.droppedItems+1]={name="boombox-radio",x=car.x+470,y=car.y+285,scene="train",carIndex=1,scale=1.15,rotation=0,permanent=true}
          data.radioAdded=true
      end
      local mailboxFound=false
      for _,item in ipairs(data.droppedItems) do
          if item.name=="mailbox-reward" and item.scene=="train" then
              mailboxFound=true; item.mailbox=true; item.permanent=true; item.scale=(item.scale and item.scale>=.9) and item.scale or 1.15; item.storage=item.storage or {}; item.mailUnread=item.mailUnread==true
          end
      end
      if not mailboxFound then
          data.droppedItems[#data.droppedItems+1]={name="mailbox-reward",x=car.x+560,y=car.y+270,scene="train",carIndex=1,scale=1.15,rotation=0,permanent=true,mailbox=true,mailUnread=false,storage={}}
      end
      for _,item in ipairs(data.droppedItems) do
          if item.name=="travel-chest" and item.scene=="train" and (item.x<car.x+35 or item.x>car.x+car.w-35) then item.x,item.y=car.x+165,car.y+285 end
      end
      if not data.medicalDropsAdded then data.medicalDropsAdded=true end
      if not data.lootContainerMigration then
          local loose={}
          for i=#data.droppedItems,1,-1 do
              local item=data.droppedItems[i]
              if (item.scene=="stop" or item.scene=="house") and not item.droppedByPlayer and not isFurnitureItem(item.name) then
                  loose[#loose+1]={name=item.name,location=item.location or data.location}; table.remove(data.droppedItems,i)
              end
          end
          for _,loot in ipairs(loose) do House.storeLoot(data,Catalog,loot.name,loot.location) end
          data.lootContainerMigration=true
      end
      if not data.expandedLootAdded then data.expandedLootAdded=true end
      data.lootBalanceVersion=data.lootBalanceVersion or 1
      data.encounters = data.encounters or {}
      local loadedNpcCandidates={}
      for file in pairs(npcImages) do loadedNpcCandidates[#loadedNpcCandidates+1]=file end
      Events.ensure(data)
      -- Older saves may have selected a character that is now a mob-only asset.
      -- Keep the save usable by moving that selection to the first valid hero.
      if not Roster.isPlayable(data.character) or not characterImages[data.character] then
          data.character = characters[1]
      end
      data.npcRoster = Roster.mergeNpcRoster(data.npcRoster,loadedNpcCandidates,data.character)
      local currentNpcAllowed=false
      for _,file in ipairs(data.npcRoster) do if file==data.currentNPC then currentNpcAllowed=true; break end end
      if not currentNpcAllowed then data.currentNPC = data.npcRoster[1] end
      resetStopSludges()
      local image = characterImages[data.character]
      local restoredX=data.playerX or car.x+90; local restoredY=data.playerY or car.y+180
      if data.scene=="train" then restoredX,restoredY=clampToTrainFloor(restoredX,restoredY) end
      if data.scene=="stop" then restoredX,restoredY=Settlements.clamp(restoredX,restoredY,data.location) end
      local activePlayer={x = restoredX, y = restoredY, speed = 185,
          image = image, facing = 1, moving = false, scale = image and math.min(0.075, 90 / image:getHeight()) or 1}
      runtime:activate(data,activePlayer)
      runtime:resetForGameEntry()
      return true
  end

  return {newSave=newSave,enterGame=enterGame}
end

return {new=new}
