if os.getenv("MOUSE_FRONTIER_SMOKE")=="1" then
    love.errorhandler=function(message)
        io.stderr:write("LOVE_ERROR: "..tostring(message).."\n"..debug.traceback().."\n"); io.stderr:flush()
        return function() os.exit(1) end
    end
end

local App = {}
local Config = require("game.config")
local SaveSchema = require("game.save_schema")
local W, H = Config.baseWidth, Config.baseHeight
local CURRENT_SAVE_VERSION = SaveSchema.CURRENT_VERSION
local Audio = require("game.audio")
local Save = require("game.save")
local Train = require("game.train")
local Viewport = require("game.viewport")
local Catalog = require("game.catalog")
local Inventory = require("game.inventory")
local CharacterAnimation = require("game.character_animation")
local Family = require("game.family")
local EngineUpgrades = require("game.engine_upgrades")
local Passengers = require("game.passengers")
local Util = require("game.util")
local House = require("game.house")
local Stops = require("game.stops")
local Roster = require("game.roster")
local RuntimeState = require("game.runtime_state")
local Wildlife = require("game.wildlife")
local Mice = require("game.mice")
local Settlements = require("game.settlements")
local Events = require("game.events")
local EventUI = require("game.event_ui")
local Camera = require("game.camera")
local BattleRules = require("game.battle_rules")
local BattleController = require("game.battle_controller")
local Assets = require("game.assets")
local StopSludges = require("game.stop_sludges")
local InteriorDoors = require("game.interior_doors")
local Interactions = require("game.interactions")
local SmokePlaythrough = require("game.smoke_playthrough")
local Clouds = require("game.clouds")
local Maintenance = require("game.maintenance")
local MobileControls = require("game.mobile_controls")
local Systems = require("game.systems")
local GameplayUpdate = Systems.gameplayUpdate
local session = Systems.session.new()
local screens = Systems.screens.new(session)
screens:register("intro"); screens:register("slots"); screens:register("characters"); screens:register("game")
screens:register("battle"); screens:register("event"); screens:register("ending")
local runtime = RuntimeState.new({
    session = session,
    transition = function(screen) screens:transition(screen) end,
})
local characters, characterImages, npcImages, mobImages, mobFiles = {}, {}, {}, {}, {}
local scenery, backgroundImages, ui = {}, {}, {}
local cloudLayer
local stopSludges = StopSludges.new()
local characterWalkImages, npcWalkImages = {}, {}
local characterActionImages, mobAttackImages, mobIdleImages, mobHitImages = {}, {}, {}, {}
local familyImages, mobDeathImages, mobWalkImages, mobRangedImages = {}, {}, {}, {}
local itemIdleImages = {}
local characterAnimations = {}
local HOLD_PICKUP_SECONDS = Config.holdPickupSeconds
local lastInventoryClick, lastInventoryClickTime = nil, 0
local maintenanceSession = Maintenance.new()
local mobileControls


-- Rolling-stock layout: the car sits farther right to leave room for the
-- enlarged locomotive while retaining one shared rail/coupler baseline.
local car = Config.trainCar
local function activeTrainCarImage()
    local image=scenery and scenery.trainCarImages and scenery.trainCarImages[runtime.saveData and runtime.saveData.trainCars and runtime.saveData.trainCars[runtime.saveData.activeCar or 1] or "living-car"]
    return image
end
local function trainFloorBounds()
    return Train.characterBounds(car,activeTrainCarImage(),30)
end
local function trainObjectBounds()
    -- Editor placement is intentionally unconstrained: objects may be arranged
    -- anywhere in the visible game canvas, including the roof/track margins.
    return 0, W, 0, H
end
local function clampToTrainFloor(x,y)
    return Train.clampCharacterToFloor(car,activeTrainCarImage(),x,y,30)
end
local colors = Config.colors


local function writeSave()
    if not runtime.selectedSlot or not runtime.saveData then return end
    runtime:syncForSave()
    ui.itemOrderRevision=(ui.itemOrderRevision or 0)+1
    session:scheduleSave(Save)
end

local function isFurnitureItem(name)
    return name and love.filesystem.getInfo("assets/sprites/furniture/"..name..".png")~=nil
end

Systems.sessionBootstrap=Systems.sessionBootstrap.new({
    saveSchema=SaveSchema,
    characters=characters,
    characterImages=characterImages,
    npcImages=npcImages,
    car=car,
    ui=ui,
    maintenanceSession=maintenanceSession,
    runtime=runtime,
    filesystem=love.filesystem,
    roster=Roster,
    house=House,
    catalog=Catalog,
    maintenance=Maintenance,
    engineUpgrades=EngineUpgrades,
    passengers=Passengers,
    events=Events,
    stopSludges=StopSludges,
    settlements=Settlements,
    trainObjectBounds=trainObjectBounds,
    trainFloorBounds=trainFloorBounds,
    clampToTrainFloor=clampToTrainFloor,
    isFurnitureItem=isFurnitureItem,
    setStopSludges=function(value) stopSludges=value end,
})



local function screenToGame(x,y)
    x,y=Viewport.toGame(x,y,W,H)
    -- Radio/options are screen-space overlays; camera zoom must not shift their
    -- hit testing into a neighboring station button.
    if runtime.state=="game" and not runtime.travelConfirm and not ui.radioOpen and not ui.mobileMenuOpen and Camera:isActive() then
        local focusX,focusY=(runtime.player and runtime.player.x or W/2),(runtime.player and runtime.player.y or H/2)
        x,y=Camera:toWorld(x,y,focusX,focusY)
    end
    return x,y
end

local function pointerPosition()
    local x,y=love.mouse.getPosition()
    if mobileControls then return mobileControls:pointer(x,y) end
    return x,y
end


local function updateStopSludges(dt)
    if runtime.scene~="stop" or not runtime.saveData or not runtime.player then return end
    StopSludges.update(stopSludges,{data=runtime.saveData,location=runtime.saveData.location,player=runtime.player,npc=runtime.npcActor,catalog=Catalog,isWeapon=Systems.inventoryActions.isWeapon,clock=runtime.animationClock,
        clamp=function(x,y) return Settlements.clamp(x,y,runtime.saveData.location) end,
        dropCoal=function(x,y)
            runtime.saveData.droppedItems[#runtime.saveData.droppedItems+1]={name="coal-chunk",x=x,y=y,scene="stop",location=runtime.saveData.location,droppedByPlayer=false}
            writeSave()
        end},dt)
end

local function attackStopSludge(x,y)
    if runtime.scene~="stop" or runtime.inventoryOpen or runtime.mapOpen or runtime.dialogue or runtime.editMode or ui.radioOpen or runtime.trainUpgradeOpen or runtime.poseMenu or ui.optionsOpen then return false end
    return StopSludges.attack(stopSludges,{data=runtime.saveData,location=runtime.saveData.location,player=runtime.player,npc=runtime.npcActor,catalog=Catalog,isWeapon=Systems.inventoryActions.isWeapon,clock=runtime.animationClock,
        onAction=function(weapon) runtime.actionHeldItem=weapon; runtime.actionKind="melee"; runtime.actionTimer=.42 end,
        playSfx=function(kind) ui.playSfx(kind) end})
end


local function itemIsHere(item)
    if item.scene ~= runtime.scene then return false end
    if runtime.scene == "train" then return (item.carIndex or 1)==(runtime.saveData.activeCar or 1) end
    if runtime.scene == "house" then return item.location == runtime.saveData.location and (item.houseDoor or 1)==(runtime.saveData.activeHouseDoor or 1) end
    return item.location == runtime.saveData.location
end


local function ensureHouseItems() House.ensure(runtime.saveData,Catalog,isFurnitureItem) end


local function ensureStopLayout() return Stops.ensure(runtime.saveData,Catalog,runtime.scene) end


local function setupNPC()
    if runtime.scene == "train" then runtime.npcActor = nil; return end
    local layout=ensureStopLayout()
    runtime.saveData.currentNPC=(runtime.scene=="house" and layout.npcInside or layout.npcOutside) or layout.npc
    local key = Util.sceneKey(runtime.scene,runtime.saveData.location)..(runtime.scene=="house" and (":"..tostring(runtime.saveData.activeHouseDoor or 1)) or "")
    local saved = runtime.saveData.npcStates[key]
    local defaults = runtime.scene == "house" and {x=650,y=410} or {x=math.max(330,math.min(790,(layout.houseX or 520)+135)),y=430}
    saved = saved or {x=defaults.x,y=defaults.y,homeX=defaults.x,homeY=defaults.y,wait=1.5}
    saved.weapon=saved.weapon or layout.npcWeapon
    if runtime.scene=="house" then
        saved.x,saved.y=Util.clampHouseFloor(saved.x,saved.y)
        saved.homeX,saved.homeY=Util.clampHouseFloor(saved.homeX,saved.homeY)
    elseif runtime.scene=="stop" then
        saved.x,saved.y=Settlements.clamp(saved.x,saved.y,runtime.saveData.location)
        saved.homeX,saved.homeY=Settlements.clamp(saved.homeX,saved.homeY,runtime.saveData.location)
    end
    runtime.saveData.npcStates[key] = saved
    runtime.npcActor = saved
    Family.ensure(runtime.npcActor,runtime.saveData.currentNPC)
end

local beginEncounter


local function battleContext()
    return {battle=runtime.battle,saveData=runtime.saveData,Catalog=Catalog,Util=Util,BattleRules=BattleRules,Events=Events,BOARD_COLS=7,BOARD_ROWS=4,playSfx=ui.playSfx,weaponSfx=ui.weaponSfx,writeSave=writeSave}
end
beginEncounter=function(encounter)
    local c=battleContext(); runtime.battle=BattleController.begin(c,encounter); runtime.battleZoom=1; runtime.state="battle"; runtime.inventoryOpen=false; runtime.mapOpen=false; runtime.dialogue=nil; writeSave()
end

local function resolveEventChoice(index)
    local event=runtime.randomEvent; if not event then return end
    local result=Events.resolve(runtime.saveData,Catalog,event,index); ui.playSfx("menu")
    if result.blocked then return end
    runtime.randomEvent=nil; writeSave()
    if result.encounter then beginEncounter(result.encounter); return end
    runtime.state="game"; Systems.journeyRules.enterStop()
    runtime.dialogue={speaker=result.clue and (event.category=="story" and "Family Trail" or "Missing Critter") or "Trail Event",text=result.clue or result.summary,timer=5}
end


local function setBattleMessage(text) BattleController.message(battleContext(),text) end
local function setBattlePrompt(text) BattleController.prompt(battleContext(),text) end
local function advanceBattleTurn() BattleController.advance(battleContext()) end
local function resolveBattleAttack(attacker,target,weaponName) return BattleController.resolve(battleContext(),attacker,target,weaponName) end
local function enemyBattleTurn() BattleController.enemyTurn(battleContext()) end
local function battleAttack(weaponName) BattleController.attack(battleContext(),weaponName) end
local function battleMoveTo(q,r) BattleController.move(battleContext(),q,r) end
local function battleHeal() BattleController.heal(battleContext()) end
local function battleGuard() BattleController.guard(battleContext()) end
local function useBattleAbility(kind) BattleController.ability(battleContext(),kind) end
local function useBattlePotion(name) return BattleController.usePotion(battleContext(),name) end
Systems.inventoryActions=Systems.inventoryActions.new({
    runtime=runtime,
    inventory=Inventory,
    catalog=Catalog,
    util=Util,
    battleController=BattleController,
    writeSave=writeSave,
    battleContext=battleContext,
    useBattlePotion=useBattlePotion,
})
Systems.journeyRules=Systems.journeyRules.new({
    runtime=runtime,
    car=car,
    inventory=Inventory,
    catalog=Catalog,
    engineUpgrades=EngineUpgrades,
    maintenance=Maintenance,
    passengers=Passengers,
    util=Util,
    house=House,
    events=Events,
    ensureStopLayout=ensureStopLayout,
    setupNPC=setupNPC,
    writeSave=writeSave,
    beginEncounter=beginEncounter,
})

function ui.playSfx(kind)
    if ui.audio and runtime.saveData then return ui.audio:playSfx(kind,runtime.saveData.audio,runtime.battle) end
end

local function playTrainDepart()
    ui.departSource=ui.playSfx("trainDepart")
end

function ui.weaponSfx(weaponName,combat)
    if weaponName=="trail-slingshot" or weaponName=="scrap-boomerang" or combat.ammo=="arrows" then return "bow" end
    if combat.kind~="ranged" then return weaponName=="scratch" and "slash" or "sword" end
    local tier=(Catalog.weaponStats[weaponName] and Catalog.weaponStats[weaponName].tier) or 1
    return tier<=4 and "gunshotLight" or (tier<=6 and "gunshotMedium" or "gunshotHeavy")
end

function ui.musicCategory()
    if runtime.state=="ending" then return "endingHappy" end
    if runtime.state=="battle" then return runtime.battle and runtime.battle.encounter and runtime.battle.encounter.tier=="hard" and "bossFight" or "battle" end
    if runtime.scene=="house" then return "insideHomes" end
    if runtime.scene=="stop" or runtime.state=="event" then return "stops" end
    return "train"
end

function ui.updateMusic()
    if runtime.saveData and ui.audio then ui.audio:update(runtime.saveData.audio,ui.musicCategory()) end
end

function ui.updateChickens(dt)
    if runtime.scene~="stop" or not runtime.saveData then return end
    local stopLayout=ensureStopLayout()
    Wildlife.spawn(stopLayout,runtime.saveData.location,Settlements)
    Wildlife.update(stopLayout.wildlife,dt,runtime.saveData.location,Settlements)
end

function ui.updateMice(dt)
    if runtime.scene~="stop" or not runtime.saveData then return end
    local stopLayout=ensureStopLayout()
    Mice.spawn(stopLayout,runtime.saveData.location,Settlements)
    Mice.update(stopLayout.mice,dt,runtime.saveData.location,Settlements)
end

function ui.drawChickens(layout)
    if not layout or runtime.scene~="stop" then return end
    Wildlife.spawn(layout,runtime.saveData.location,Settlements)
    Wildlife.draw(layout.wildlife,scenery.stopWildlife,runtime.animationClock)
end

function ui.drawMice(layout)
    if not layout or runtime.scene~="stop" then return end
    Mice.spawn(layout,runtime.saveData.location,Settlements)
    Mice.draw(layout.mice,scenery.stopWildlife,runtime.animationClock)
end

function App.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setFont(love.graphics.newFont(16))
    ui.audio=Audio.new(); ui.audio:installGunPools()
    love.filesystem.createDirectory("saves")
    characterAnimations=Assets.load({
        ui=ui, scenery=scenery, characters=characters, characterImages=characterImages,
        npcImages=npcImages, mobImages=mobImages, mobFiles=mobFiles, backgroundImages=backgroundImages,
        characterWalkImages=characterWalkImages, npcWalkImages=npcWalkImages, characterActionImages=characterActionImages,
        mobAttackImages=mobAttackImages, mobIdleImages=mobIdleImages, mobHitImages=mobHitImages,
        mobDeathImages=mobDeathImages, mobWalkImages=mobWalkImages, mobRangedImages=mobRangedImages,
        familyImages=familyImages, itemIdleImages=itemIdleImages,
    })
    ui.introCinematic=Systems.intro.new(10)
    cloudLayer = Clouds.new(scenery.cloudImages)
    scenery.settlements=Settlements.load(function(path)
        local ok,image=pcall(love.graphics.newImage,path)
        return ok and image or nil
    end)
    ui.assetStreamer=require("game.asset_streamer").new({
        settlements=scenery.settlements,
        interiorFiles=scenery.interiorFiles,
        characterAnimations=characterAnimations,
        legacyAnimationTables={characterWalkImages,npcWalkImages,characterActionImages,mobAttackImages,mobIdleImages,mobHitImages,mobDeathImages,mobWalkImages,mobRangedImages,npcImages,mobImages},
    })
    mobileControls=MobileControls.new({
        width=W,height=H,
        toGame=function(x,y) return Viewport.toGame(x,y,W,H) end,
        gameplayActive=function()
            return runtime.state=="game" and not runtime.travelConfirm and not runtime.travelTransition and not maintenanceSession.open
                and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.tradeOpen and not runtime.trainUpgradeOpen and not runtime.editMode
                and not runtime.poseMenu and not ui.optionsOpen and not ui.radioOpen and not ui.mobileMenuOpen and not runtime.exitPrompt
        end,
        getZoom=function() return Camera.zoom end,
        setZoom=function(value) Camera:setZoom(value) end,
        backVisible=function()
            if runtime.exitPrompt then return true end
            if runtime.state=="slots" or runtime.state=="characters" then return true end
            if runtime.state=="battle" then return runtime.inventoryOpen end
            return runtime.state=="game" and (runtime.travelConfirm or maintenanceSession.open or runtime.inventoryOpen or runtime.mapOpen or runtime.tradeOpen or runtime.trainUpgradeOpen
                or runtime.editMode or runtime.poseMenu or ui.optionsOpen or ui.radioOpen or ui.mobileMenuOpen or runtime.dialogue~=nil)
        end,
        backLabel=function() return runtime.state=="slots" and "EXIT" or "BACK" end,
        menuVisible=function()
            return runtime.state=="game" and not runtime.travelConfirm and not runtime.travelTransition and not maintenanceSession.open and not runtime.exitPrompt
                and not runtime.inventoryOpen and not runtime.mapOpen and not runtime.tradeOpen and not runtime.trainUpgradeOpen and not runtime.editMode
                and not runtime.poseMenu and not ui.optionsOpen and not ui.radioOpen and not runtime.dialogue
        end,
        menuLabel=function() return ui.mobileMenuOpen and "CLOSE" or "MENU" end,
        menuAction=function() ui.mobileMenuOpen=not ui.mobileMenuOpen; Camera:endPan() end,
        primaryAction=function()
            if runtime.dialogue then return "q","CLOSE" end
            local kind=ui.interaction and ui.interaction.kind
            if kind=="radio" then return "p","RADIO"
            elseif kind=="item" then return "e","PICK UP"
            elseif kind=="chest" then return "i","OPEN"
            elseif kind=="fire" then return "e","COAL"
            elseif kind=="npc" or kind=="passenger" then return "q","TALK"
            elseif kind=="house" then return "q","ENTER"
            elseif kind=="houseExit" then return "q","EXIT"
            elseif kind=="returnTrain" then return "q","BOARD"
            elseif kind=="carNext" or kind=="carPrev" then return "q","DOOR"
            end
            return "e","USE"
        end,
        secondaryAction=function()
            local kind=ui.interaction and ui.interaction.kind
            if kind=="npc" or kind=="passenger" then return "g","GIVE" end
        end,
        pressKey=function(key) Systems.gameplayInput.keypressed(key) end,
        releaseKey=function(key) Systems.gameplayInput.keyreleased(key) end,
        pressPointer=function(x,y,button) Systems.gameplayInput.mousepressed(x,y,button) end,
        movePointer=function(x,y,dx,dy) Systems.gameplayInput.mousemoved(x,y,dx,dy) end,
        releasePointer=function(x,y,button) Systems.gameplayInput.mousereleased(x,y,button) end,
    })
    Systems.gameplayUpdate=GameplayUpdate.new({
        runtime=runtime,
        width=W,
        holdPickupSeconds=HOLD_PICKUP_SECONDS,
        ui=ui,
        car=car,
        scenery=scenery,
        cloudLayer=cloudLayer,
        maintenanceSession=maintenanceSession,
        mobileControls=mobileControls,
        interactionRouter=Systems.interactions,
        inventoryActions=Systems.inventoryActions,
        journeyRules=Systems.journeyRules,
        catalog=Catalog,
        settlements=Settlements,
        interiorDoors=InteriorDoors,
        interactions=Interactions,
        save=Save,
        clouds=Clouds,
        screens=screens,
        engineUpgrades=EngineUpgrades,
        maintenance=Maintenance,
        family=Family,
        util=Util,
        passengers=Passengers,
        screenToGame=screenToGame,
        ensureStopLayout=ensureStopLayout,
        updateStopSludges=updateStopSludges,
        clampToTrainFloor=clampToTrainFloor,
        itemIsHere=itemIsHere,
        setupNPC=setupNPC,
        trainFloorBounds=trainFloorBounds,
        writeSave=writeSave,
    })
end

screens:register("intro",{update=function(dt)
    if Systems.intro.update(ui.introCinematic,dt) then runtime.state="slots" end
    return true
end})
screens:register("slots",{update=function() return true end})
screens:register("characters",{update=function() return true end})
screens:register("battle",{update=function(dt) if runtime.battle then BattleController.update(battleContext(),dt) end; return true end})
screens:register("event",{update=function() return true end})
screens:register("ending",{update=function() return true end})
screens:register("game",{update=function() return false end})

function App.update(dt) return Systems.gameplayUpdate.update(dt) end

Systems.screenUI=Systems.screenUI.new({
    runtime=runtime,
    width=W,
    height=H,
    ui=ui,
    colors=colors,
    scenery=scenery,
    characters=characters,
    characterImages=characterImages,
    npcImages=npcImages,
    save=Save,
    util=Util,
    catalog=Catalog,
    inventory=Inventory,
    eventUI=EventUI,
    events=Events,
    engineUpgrades=EngineUpgrades,
    writeSave=writeSave,
    screenToGame=screenToGame,
    ensureStopLayout=ensureStopLayout,
    mobileEnabled=function() return mobileControls and mobileControls:isEnabled() or false end,
    drawLandscape=function(...) return Systems.worldRenderer.drawLandscape(...) end,
    drawTracks=function(...) return Systems.worldRenderer.drawTracks(...) end,
    drawLocomotive=function(...) return Systems.worldRenderer.drawLocomotive(...) end,
    drawTrainCar=function(...) return Systems.worldRenderer.drawTrainCar(...) end,
    isWeapon=Systems.inventoryActions.isWeapon,
    travelCost=Systems.journeyRules.travelCost,
})



function ui.setInventoryState(name,value)
    if name=="draggedSlot" then runtime.draggedSlot=value elseif name=="inventoryDragActive" then runtime.inventoryDragActive=value
    elseif name=="giftOpen" then runtime.giftOpen=value elseif name=="giftSlot" then runtime.giftSlot=value
    elseif name=="inventoryOpen" then runtime.inventoryOpen=value elseif name=="lastClick" then lastInventoryClick=value
    elseif name=="lastClickTime" then lastInventoryClickTime=value end
end

function ui.inventoryContext()
    return {data=runtime.saveData,activeChest=runtime.activeChest,chestOpen=runtime.chestOpen,inventoryOpen=runtime.inventoryOpen,draggedSlot=runtime.draggedSlot,inventoryDragActive=runtime.inventoryDragActive,
        giftOpen=runtime.giftOpen,giftNPC=runtime.giftNPC,giftSlot=runtime.giftSlot,lastClick=lastInventoryClick,lastClickTime=lastInventoryClickTime,nearNPC=runtime.nearNPC,nearPassenger=runtime.nearPassenger,
        ui=ui,Inventory=Inventory,Catalog=Catalog,colors=colors,mobileControls=mobileControls,pointIn=Util.pointIn,title=Util.titleFromFile,isWeapon=Systems.inventoryActions.isWeapon,
        drawMenuFrame=Systems.screenUI.drawMenuFrame,button=Systems.screenUI.button,pointer=function() return screenToGame(pointerPosition()) end,value=Systems.inventoryActions.containerValue,set=ui.setInventoryState,
        battleMode=runtime.state=="battle",move=Systems.inventoryActions.moveBetweenSlots,quickTransfer=Systems.inventoryActions.quickTransfer,collectAmmo=Systems.inventoryActions.collectAmmo,drop=runtime.state=="battle" and function() return false end or Systems.inventoryActions.dropFromContainer,
        consume=runtime.state=="battle" and Systems.inventoryActions.consumeBattleSelected or Systems.inventoryActions.consumeSelected}
end

function ui.drawInventory() Systems.inventory.draw(ui.inventoryContext()) end
function ui.drawChestInventory() Systems.inventory.drawChest(ui.inventoryContext()) end
function ui.drawItem(name,r) Systems.inventory.drawItem(ui.inventoryContext(),name,r) end




function ui.battleUIContext()
    return {
        W=W,H=H,battle=runtime.battle,battleZoom=runtime.battleZoom,scenery=scenery,colors=colors,mobileControls=mobileControls,
        characterImages=characterImages,npcImages=npcImages,mobImages=mobImages,
        characterWalkImages=characterWalkImages,npcWalkImages=npcWalkImages,
        mobAttackImages=mobAttackImages,mobIdleImages=mobIdleImages,mobHitImages=mobHitImages,
        mobDeathImages=mobDeathImages,mobWalkImages=mobWalkImages,mobRangedImages=mobRangedImages,
        animationClock=runtime.animationClock,characterAnimations=characterAnimations,
        saveData=runtime.saveData,inventoryOpen=runtime.inventoryOpen,ui=ui,
        drawLandscape=Systems.worldRenderer.drawLandscape,drawGround=Systems.worldRenderer.drawGround,
        drawAnimatedCharacter=Systems.worldRenderer.drawAnimatedCharacter,button=Systems.screenUI.button,screenToGame=screenToGame,pointerPosition=pointerPosition,
        setInventoryOpen=function(value) runtime.inventoryOpen=value end,
        resetInventoryDrag=function() runtime.draggedSlot=nil; runtime.inventoryDragActive=false end,
        battleAttack=battleAttack,setBattlePrompt=setBattlePrompt,battleHeal=battleHeal,battleGuard=battleGuard,
        useBattleAbility=useBattleAbility,useBattlePotion=useBattlePotion,advanceBattleTurn=advanceBattleTurn,
        resolveBattleAttack=resolveBattleAttack,battleMoveTo=battleMoveTo
    }
end

function ui.drawTacticalBattle() Systems.battleUI.draw(ui.battleUIContext()) end

Systems.worldRenderer=Systems.worldRenderer.new({
    runtime=runtime,
    width=W,
    height=H,
    backgroundImages=backgroundImages,
    scenery=scenery,
    car=car,
    colors=colors,
    getCharacterAnimations=function() return characterAnimations end,
    characterImages=characterImages,
    characterWalkImages=characterWalkImages,
    characterActionImages=characterActionImages,
    itemIdleImages=itemIdleImages,
    npcImages=npcImages,
    npcWalkImages=npcWalkImages,
    familyImages=familyImages,
    mobImages=mobImages,
    mobIdleImages=mobIdleImages,
    mobWalkImages=mobWalkImages,
    mobHitImages=mobHitImages,
    mobDeathImages=mobDeathImages,
    getStopSludges=function() return stopSludges end,
    stopSludgesService=StopSludges,
    train=Train,
    characterAnimation=CharacterAnimation,
    catalog=Catalog,
    family=Family,
    settlements=Settlements,
    stops=Stops,
    util=Util,
    ui=ui,
    itemIsHere=itemIsHere,
    pendingMailHere=Systems.journeyRules.pendingMailHere,
    ensureStopLayout=ensureStopLayout,
})


local function beginCarTransition(targetIndex)
    if runtime.carTransition or runtime.scene~="train" then return false end
    local current=runtime.saveData.activeCar or 1
    targetIndex=math.max(1,math.min(#(runtime.saveData.trainCars or {}),targetIndex))
    if targetIndex==current then return false end
    local left,right,top,bottom=trainFloorBounds()
    runtime.carTransition={from=current,to=targetIndex,t=0,duration=.78,targetX=targetIndex>current and left or right,targetY=(top+bottom)/2}
    runtime.player.moving=false; runtime.nearbyItem=nil; runtime.nearChest=nil; runtime.nearCarNext=false; runtime.nearCarPrev=false
    ui.playSfx("trainDoor")
    return true
end

local function moveEditedItem(dx,dy)
    local item=runtime.editedItem and runtime.saveData.droppedItems[runtime.editedItem]; if not item then return end
    local left,right,top,bottom=trainObjectBounds(); item.x=math.max(left,math.min(right,item.x+dx)); item.y=math.max(top,math.min(bottom,item.y+dy)); writeSave()
end

Systems.gameplayHUD=Systems.gameplayHUD.new({
    runtime=runtime,
    width=W,
    height=H,
    ui=ui,
    colors=colors,
    maintenanceSession=maintenanceSession,
    holdPickupSeconds=HOLD_PICKUP_SECONDS,
    getCloudLayer=function() return cloudLayer end,
    getMobileControls=function() return mobileControls end,
    engineUpgrades=EngineUpgrades,
    clouds=Clouds,
    maintenance=Maintenance,
    util=Util,
    button=Systems.screenUI.button,
    drawMenuFrame=Systems.screenUI.drawMenuFrame,
    drawTrade=Systems.screenUI.drawTrade,
    isFurnitureItem=isFurnitureItem,
    containerValue=Systems.inventoryActions.containerValue,
    screenToGame=screenToGame,
    pointerPosition=pointerPosition,
    drawLandscape=Systems.worldRenderer.drawLandscape,
    drawTracks=Systems.worldRenderer.drawTracks,
    drawTrainView=Systems.worldRenderer.drawTrainView,
    drawHouse=Systems.worldRenderer.drawHouse,
    drawStop=Systems.worldRenderer.drawStop,
})



screens:register("intro",{draw=function()
    local windowWidth,windowHeight=love.graphics.getDimensions()
    Systems.intro.draw(ui.introCinematic,scenery,colors,windowWidth,windowHeight)
end})
screens:register("slots",{draw=ui.drawSlots})
screens:register("characters",{draw=ui.drawCharacterSelect})
screens:register("battle",{draw=ui.drawTacticalBattle})
screens:register("event",{draw=ui.drawRandomEvent})
screens:register("ending",{draw=Systems.screenUI.drawEnding})
screens:register("game",{draw=function() if runtime.travelConfirm then ui.drawTravelConfirm() else Systems.gameplayHUD.draw() end end})

function App.draw()
    love.graphics.clear(0.025,0.02,0.025,1)
    if screens:is("intro") then screens:draw(); return end
    local offsetX,offsetY,scaleX,scaleY=Viewport.transform(W,H)
    love.graphics.push()
    love.graphics.translate(offsetX,offsetY)
    love.graphics.scale(scaleX,scaleY)
    if runtime.state=="game" and not runtime.travelConfirm and not maintenanceSession.open and not ui.mobileMenuOpen and Camera:isActive() then
        local focusX,focusY=(runtime.player and runtime.player.x or W/2),(runtime.player and runtime.player.y or H/2)
        Camera:apply(focusX,focusY)
    end
    screens:draw()
    if runtime.exitPrompt then Systems.screenUI.drawExitPrompt() end
    love.graphics.pop()
    if mobileControls then mobileControls:draw(offsetX,offsetY,scaleX,scaleY) end
    if runtime.travelTransition then
        local t=runtime.travelTransition.t; local timing=EngineUpgrades.timings(runtime.saveData.engineLevel)
        local alpha=t<timing.change and math.max(0,math.min(1,(t-timing.fadeOut)/timing.fadeDuration)) or math.max(0,1-(t-timing.change)/timing.finishFade)
        local windowWidth,windowHeight=love.graphics.getDimensions()
        love.graphics.setColor(0,0,0,alpha)
        love.graphics.rectangle("fill",0,0,windowWidth,windowHeight)
    end
end

Systems.gameplayInput=Systems.gameplayInput.new({
    runtime=runtime,
    width=W,
    height=H,
    ui=ui,
    characters=characters,
    maintenanceSession=maintenanceSession,
    scenery=scenery,
    systems=Systems,
    inventory=Inventory,
    catalog=Catalog,
    util=Util,
    save=Save,
    eventUI=EventUI,
    engineUpgrades=EngineUpgrades,
    maintenance=Maintenance,
    camera=Camera,
    viewport=Viewport,
    battleRules=BattleRules,
    stops=Stops,
    settlements=Settlements,
    interiorDoors=InteriorDoors,
    writeSave=writeSave,
    screenToGame=screenToGame,
    pointerPosition=pointerPosition,
    isWeapon=Systems.inventoryActions.isWeapon,
    isFurnitureItem=isFurnitureItem,
    ensureStopLayout=ensureStopLayout,
    ownsTrainCar=Systems.screenUI.ownsTrainCar,
    moveEditedItem=moveEditedItem,
    attackStopSludge=attackStopSludge,
    acceptQuest=Systems.journeyRules.acceptQuest,
    attemptLeaveTrain=Systems.journeyRules.attemptLeaveTrain,
    travelCost=Systems.journeyRules.travelCost,
    playTrainDepart=playTrainDepart,
    trainFloorBounds=trainFloorBounds,
    trainObjectBounds=trainObjectBounds,
    newSave=Systems.sessionBootstrap.newSave,
    enterGame=Systems.sessionBootstrap.enterGame,
    resolveEventChoice=resolveEventChoice,
    enterStop=Systems.journeyRules.enterStop,
    battleAttack=battleAttack,
    battleHeal=battleHeal,
    battleGuard=battleGuard,
    advanceBattleTurn=advanceBattleTurn,
    setBattlePrompt=setBattlePrompt,
    beginCarTransition=beginCarTransition,
    talkToNPC=Systems.journeyRules.talkToNPC,
    ensureHouseItems=ensureHouseItems,
    setupNPC=setupNPC,
    giveWeaponToNearby=Systems.inventoryActions.giveWeaponToNearby,
    pickUpNearby=Systems.inventoryActions.pickUpNearby,
    addCoalToFire=Systems.inventoryActions.addCoalToFire,
    requestExitPrompt=Systems.screenUI.requestExitPrompt,
    resolveExitPrompt=Systems.screenUI.resolveExitPrompt,
})
function App.mousepressed(x,y,button,istouch,...)
    if mobileControls and mobileControls:ignoreSyntheticMouse(istouch) then return end
    return Systems.gameplayInput.mousepressed(x,y,button,...)
end
function App.mousemoved(x,y,dx,dy,istouch,...)
    if mobileControls and mobileControls:ignoreSyntheticMouse(istouch) then return end
    return Systems.gameplayInput.mousemoved(x,y,dx,dy,...)
end
function App.mousereleased(x,y,button,istouch,...)
    if mobileControls and mobileControls:ignoreSyntheticMouse(istouch) then return end
    return Systems.gameplayInput.mousereleased(x,y,button,...)
end
function App.wheelmoved(...) return Systems.gameplayInput.wheelmoved(...) end
function App.keypressed(key,...)
    if key=="acback" then key="escape" end
    return Systems.gameplayInput.keypressed(key,...)
end
function App.keyreleased(...) return Systems.gameplayInput.keyreleased(...) end
function App.touchpressed(id,x,y) if mobileControls then return mobileControls:touchpressed(id,x,y) end end
function App.touchmoved(id,x,y,dx,dy) if mobileControls then return mobileControls:touchmoved(id,x,y,dx,dy) end end
function App.touchreleased(id,x,y) if mobileControls then return mobileControls:touchreleased(id,x,y) end end
function App.focus(focused)
    if not focused then
        if mobileControls then mobileControls:cancelAll() end
        writeSave(); Save.flush()
    end
end



function App.installSmoke()
if os.getenv("MOUSE_FRONTIER_SMOKE")=="1" then
    local smokeScope=setmetatable({}, {__index=function(_,name)
        if name=="state" then return session.screen elseif name=="selectedSlot" then return session.selectedSlot elseif name=="saveData" then return session.saveData elseif name=="characters" then return characters elseif name=="ui" then return ui elseif name=="scene" then return session.scene elseif name=="player" then return session.player elseif name=="inventoryOpen" then return runtime.inventoryOpen elseif name=="mapOpen" then return runtime.mapOpen elseif name=="mapScroll" then return runtime.mapScroll elseif name=="tradeOpen" then return runtime.tradeOpen elseif name=="trainUpgradeOpen" then return runtime.trainUpgradeOpen elseif name=="poseMenu" then return runtime.poseMenu elseif name=="randomEvent" then return runtime.randomEvent elseif name=="battle" then return runtime.battle elseif name=="travelTransition" then return runtime.travelTransition elseif name=="maintenanceSession" then return maintenanceSession elseif name=="draggedSlot" then return runtime.draggedSlot elseif name=="actionHeldItem" then return runtime.actionHeldItem elseif name=="actionTimer" then return runtime.actionTimer elseif name=="actionKind" then return runtime.actionKind elseif name=="travelConfirm" then return runtime.travelConfirm elseif name=="car" then return car elseif name=="dialogue" then return runtime.dialogue elseif name=="editMode" then return runtime.editMode elseif name=="carTransition" then return runtime.carTransition
        elseif name=="session" then return session elseif name=="runtime" then return runtime elseif name=="screens" then return screens elseif name=="CURRENT_SAVE_VERSION" then return CURRENT_SAVE_VERSION elseif name=="SaveSchema" then return SaveSchema elseif name=="Catalog" then return Catalog elseif name=="Assets" then return Assets elseif name=="Save" then return Save elseif name=="Maintenance" then return Maintenance elseif name=="Events" then return Events elseif name=="Systems" then return Systems elseif name=="mobileControls" then return mobileControls elseif name=="Camera" then return Camera
        elseif name=="writeSave" then return writeSave elseif name=="newSave" then return Systems.sessionBootstrap.newSave elseif name=="enterGame" then return Systems.sessionBootstrap.enterGame elseif name=="ensureStopLayout" then return ensureStopLayout elseif name=="setupNPC" then return setupNPC elseif name=="beginEncounter" then return beginEncounter elseif name=="consumeSelected" then return Systems.inventoryActions.consumeSelected elseif name=="resolveEventChoice" then return resolveEventChoice elseif name=="advanceBattleTurn" then return advanceBattleTurn elseif name=="battleAttack" then return battleAttack elseif name=="resolveBattleAttack" then return resolveBattleAttack end
    end,__newindex=function(_,name,value)
        if name=="state" then runtime.state=value elseif name=="selectedSlot" then runtime.selectedSlot=value elseif name=="saveData" then runtime.saveData=value elseif name=="scene" then runtime.scene=value elseif name=="player" then runtime.player=value elseif name=="inventoryOpen" then runtime.inventoryOpen=value elseif name=="mapOpen" then runtime.mapOpen=value elseif name=="mapScroll" then runtime.mapScroll=value elseif name=="tradeOpen" then runtime.tradeOpen=value elseif name=="trainUpgradeOpen" then runtime.trainUpgradeOpen=value elseif name=="poseMenu" then runtime.poseMenu=value elseif name=="randomEvent" then runtime.randomEvent=value elseif name=="battle" then runtime.battle=value elseif name=="travelTransition" then runtime.travelTransition=value elseif name=="maintenanceSession" then maintenanceSession=value elseif name=="draggedSlot" then runtime.draggedSlot=value elseif name=="actionHeldItem" then runtime.actionHeldItem=value elseif name=="actionTimer" then runtime.actionTimer=value elseif name=="travelConfirm" then runtime.travelConfirm=value elseif name=="dialogue" then runtime.dialogue=value elseif name=="editMode" then runtime.editMode=value elseif name=="carTransition" then runtime.carTransition=value end
    end})
    SmokePlaythrough.install(smokeScope)
end
end

function App.quit() Maintenance.release(maintenanceSession); writeSave(); Save.flush(); if ui.audio and ui.audio.shutdown then ui.audio:shutdown() end end

return App
