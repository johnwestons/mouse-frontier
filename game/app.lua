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
local characterWalkImages, npcWalkImages = {}, {}
local characterActionImages, mobAttackImages, mobIdleImages, mobHitImages = {}, {}, {}, {}
local familyImages, mobDeathImages, mobWalkImages, mobRangedImages = {}, {}, {}, {}
local itemIdleImages = {}
local characterAnimations = {}
local HOLD_PICKUP_SECONDS = Config.holdPickupSeconds
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

Systems.worldScene=Systems.worldScene.new({
    runtime=runtime,
    ui=ui,
    scenery=scenery,
    catalog=Catalog,
    util=Util,
    house=House,
    stops=Stops,
    family=Family,
    settlements=Settlements,
    wildlife=Wildlife,
    mice=Mice,
    stopSludges=StopSludges,
    getIsWeapon=function() return Systems.inventoryActions.isWeapon end,
    isFurnitureItem=isFurnitureItem,
    writeSave=writeSave,
})

Systems.audioRuntime=Systems.audioRuntime.new({
    runtime=runtime,
    ui=ui,
    catalog=Catalog,
    audio=Audio,
})

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
    settlements=Settlements,
    trainObjectBounds=trainObjectBounds,
    trainFloorBounds=trainFloorBounds,
    clampToTrainFloor=clampToTrainFloor,
    isFurnitureItem=isFurnitureItem,
    resetStopSludges=Systems.worldScene.resetStopSludges,
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


Systems.battleRuntime=Systems.battleRuntime.new({
    runtime=runtime,
    width=W,
    height=H,
    ui=ui,
    scenery=scenery,
    colors=colors,
    characterImages=characterImages,
    npcImages=npcImages,
    mobImages=mobImages,
    characterWalkImages=characterWalkImages,
    npcWalkImages=npcWalkImages,
    mobAttackImages=mobAttackImages,
    mobIdleImages=mobIdleImages,
    mobHitImages=mobHitImages,
    mobDeathImages=mobDeathImages,
    mobWalkImages=mobWalkImages,
    mobRangedImages=mobRangedImages,
    getCharacterAnimations=function() return characterAnimations end,
    getMobileControls=function() return mobileControls end,
    getWorldRenderer=function() return Systems.worldRenderer end,
    getScreenUI=function() return Systems.screenUI end,
    catalog=Catalog,
    util=Util,
    battleRules=BattleRules,
    events=Events,
    battleController=BattleController,
    battleUI=Systems.battleUI,
    writeSave=writeSave,
    screenToGame=screenToGame,
    pointerPosition=pointerPosition,
    enterStop=function(...) return Systems.journeyRules.enterStop(...) end,
    handleInventoryClick=function(x,y) return Systems.inventoryPresenter.handleClick(x,y,ui.offerGift) end,
})

local function resolveEventChoice(index)
    local event=runtime.randomEvent; if not event then return end
    local result=Events.resolve(runtime.saveData,Catalog,event,index); ui.playSfx("menu")
    if result.blocked then return end
    runtime.randomEvent=nil; writeSave()
    if result.encounter then Systems.battleRuntime.beginEncounter(result.encounter); return end
    runtime.state="game"; Systems.journeyRules.enterStop()
    runtime.dialogue={speaker=result.clue and (event.category=="story" and "Family Trail" or "Missing Critter") or "Trail Event",text=result.clue or result.summary,timer=5}
end


Systems.inventoryActions=Systems.inventoryActions.new({
    runtime=runtime,
    inventory=Inventory,
    catalog=Catalog,
    util=Util,
    writeSave=writeSave,
    useBattleHealingItem=Systems.battleRuntime.useHealingItem,
    useBattlePotion=Systems.battleRuntime.usePotion,
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
    ensureStopLayout=Systems.worldScene.ensureStopLayout,
    setupNPC=Systems.worldScene.setupNPC,
    writeSave=writeSave,
    beginEncounter=Systems.battleRuntime.beginEncounter,
})

function App.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setFont(love.graphics.newFont(16))
    Systems.audioRuntime.initialize()
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
        updateAudio=Systems.audioRuntime.update,
        ensureStopLayout=Systems.worldScene.ensureStopLayout,
        updateWorldScene=Systems.worldScene.update,
        clampToTrainFloor=clampToTrainFloor,
        itemIsHere=Systems.worldScene.itemIsHere,
        setupNPC=Systems.worldScene.setupNPC,
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
screens:register("battle",{update=Systems.battleRuntime.update})
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
    ensureStopLayout=Systems.worldScene.ensureStopLayout,
    mobileEnabled=function() return mobileControls and mobileControls:isEnabled() or false end,
    drawLandscape=function(...) return Systems.worldRenderer.drawLandscape(...) end,
    drawTracks=function(...) return Systems.worldRenderer.drawTracks(...) end,
    drawLocomotive=function(...) return Systems.worldRenderer.drawLocomotive(...) end,
    drawTrainCar=function(...) return Systems.worldRenderer.drawTrainCar(...) end,
    isWeapon=Systems.inventoryActions.isWeapon,
    travelCost=Systems.journeyRules.travelCost,
})

Systems.inventoryPresenter=Systems.inventoryPresenter.new({
    runtime=runtime,
    ui=ui,
    inventoryUI=Systems.inventory,
    inventory=Inventory,
    catalog=Catalog,
    colors=colors,
    getMobileControls=function() return mobileControls end,
    pointIn=Util.pointIn,
    title=Util.titleFromFile,
    isWeapon=Systems.inventoryActions.isWeapon,
    drawMenuFrame=Systems.screenUI.drawMenuFrame,
    button=Systems.screenUI.button,
    pointer=function() return screenToGame(pointerPosition()) end,
    value=Systems.inventoryActions.containerValue,
    move=Systems.inventoryActions.moveBetweenSlots,
    quickTransfer=Systems.inventoryActions.quickTransfer,
    collectAmmo=Systems.inventoryActions.collectAmmo,
    drop=Systems.inventoryActions.dropFromContainer,
    consume=Systems.inventoryActions.consumeSelected,
    consumeBattle=Systems.inventoryActions.consumeBattleSelected,
})

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
    drawStopSludges=Systems.worldScene.drawStopSludges,
    drawWildlife=Systems.worldScene.drawWildlife,
    train=Train,
    characterAnimation=CharacterAnimation,
    catalog=Catalog,
    family=Family,
    settlements=Settlements,
    stops=Stops,
    util=Util,
    ui=ui,
    itemIsHere=Systems.worldScene.itemIsHere,
    pendingMailHere=Systems.journeyRules.pendingMailHere,
    ensureStopLayout=Systems.worldScene.ensureStopLayout,
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
    getAudioStatus=Systems.audioRuntime.status,
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
screens:register("battle",{draw=Systems.battleRuntime.draw})
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
    ensureStopLayout=Systems.worldScene.ensureStopLayout,
    ownsTrainCar=Systems.screenUI.ownsTrainCar,
    moveEditedItem=moveEditedItem,
    attackStopSludge=Systems.worldScene.attackStopSludge,
    acceptQuest=Systems.journeyRules.acceptQuest,
    attemptLeaveTrain=Systems.journeyRules.attemptLeaveTrain,
    travelCost=Systems.journeyRules.travelCost,
    playTrainDepart=Systems.audioRuntime.playTrainDepart,
    audioResetMusic=Systems.audioRuntime.resetMusic,
    audioPreviousTrack=Systems.audioRuntime.previousTrack,
    audioTogglePause=Systems.audioRuntime.togglePause,
    audioNextTrack=Systems.audioRuntime.nextTrack,
    audioToggleMute=Systems.audioRuntime.toggleMute,
    trainFloorBounds=trainFloorBounds,
    trainObjectBounds=trainObjectBounds,
    newSave=Systems.sessionBootstrap.newSave,
    enterGame=Systems.sessionBootstrap.enterGame,
    resolveEventChoice=resolveEventChoice,
    enterStop=Systems.journeyRules.enterStop,
    handleBattleMouse=Systems.battleRuntime.handleMouse,
    battleAttack=Systems.battleRuntime.attack,
    battleHeal=Systems.battleRuntime.heal,
    battleGuard=Systems.battleRuntime.guard,
    advanceBattleTurn=Systems.battleRuntime.advanceTurn,
    setBattlePrompt=Systems.battleRuntime.setPrompt,
    beginCarTransition=beginCarTransition,
    talkToNPC=Systems.journeyRules.talkToNPC,
    ensureHouseItems=Systems.worldScene.ensureHouseItems,
    setupNPC=Systems.worldScene.setupNPC,
    giveWeaponToNearby=Systems.inventoryActions.giveWeaponToNearby,
    pickUpNearby=Systems.inventoryActions.pickUpNearby,
    addCoalToFire=Systems.inventoryActions.addCoalToFire,
    handleInventoryClick=Systems.inventoryPresenter.handleClick,
    handleInventoryRelease=Systems.inventoryPresenter.handleRelease,
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
        elseif name=="writeSave" then return writeSave elseif name=="newSave" then return Systems.sessionBootstrap.newSave elseif name=="enterGame" then return Systems.sessionBootstrap.enterGame elseif name=="ensureStopLayout" then return Systems.worldScene.ensureStopLayout elseif name=="setupNPC" then return Systems.worldScene.setupNPC elseif name=="beginEncounter" then return Systems.battleRuntime.beginEncounter elseif name=="consumeSelected" then return Systems.inventoryActions.consumeSelected elseif name=="resolveEventChoice" then return resolveEventChoice elseif name=="advanceBattleTurn" then return Systems.battleRuntime.advanceTurn elseif name=="battleAttack" then return Systems.battleRuntime.attack elseif name=="resolveBattleAttack" then return Systems.battleRuntime.resolveAttack end
    end,__newindex=function(_,name,value)
        if name=="state" then runtime.state=value elseif name=="selectedSlot" then runtime.selectedSlot=value elseif name=="saveData" then runtime.saveData=value elseif name=="scene" then runtime.scene=value elseif name=="player" then runtime.player=value elseif name=="inventoryOpen" then runtime.inventoryOpen=value elseif name=="mapOpen" then runtime.mapOpen=value elseif name=="mapScroll" then runtime.mapScroll=value elseif name=="tradeOpen" then runtime.tradeOpen=value elseif name=="trainUpgradeOpen" then runtime.trainUpgradeOpen=value elseif name=="poseMenu" then runtime.poseMenu=value elseif name=="randomEvent" then runtime.randomEvent=value elseif name=="battle" then runtime.battle=value elseif name=="travelTransition" then runtime.travelTransition=value elseif name=="maintenanceSession" then maintenanceSession=value elseif name=="draggedSlot" then runtime.draggedSlot=value elseif name=="actionHeldItem" then runtime.actionHeldItem=value elseif name=="actionTimer" then runtime.actionTimer=value elseif name=="travelConfirm" then runtime.travelConfirm=value elseif name=="dialogue" then runtime.dialogue=value elseif name=="editMode" then runtime.editMode=value elseif name=="carTransition" then runtime.carTransition=value end
    end})
    SmokePlaythrough.install(smokeScope)
end
end

function App.quit() Maintenance.release(maintenanceSession); writeSave(); Save.flush(); Systems.audioRuntime.shutdown() end

return App
