-- Run from the repository root with Lua or the expedition test runner.
local previousLove=love
local held={}
love={
    keyboard={isDown=function(...) for i=1,select("#",...) do if held[select(i,...)] then return true end end; return false end},
    mouse={getPosition=function() return 0,0 end},
    graphics={getDimensions=function() return 960,720 end},
    system={getOS=function() return "Android" end},
    timer={getTime=function() return 0 end},
}

local function noop() end
local function passthrough(x,y) return x,y end
local function defaults(values) return setmetatable(values,{__index=function() return noop end}) end
local function equal(actual,expected,label)
    assert(actual==expected,(label or "value")..": expected "..tostring(expected)..", got "..tostring(actual))
end

local Pause=require("game.world_pause")
local runtime,ui,maintenance={state="game"},{},{}
equal(Pause.isPaused(runtime,ui,maintenance),false,"world starts active")
for _,key in ipairs({"exitPrompt","travelConfirm","travelTransition","carTransition","inventoryOpen","mapOpen","editMode",
    "tradeOpen","trainUpgradeOpen","poseMenu","firstAid","shootingRange","helpDialogue","dialogue"}) do
    runtime[key]=true
    equal(Pause.isPaused(runtime,ui,maintenance),true,key.." pauses simulation")
    runtime[key]=nil
end
for _,key in ipairs({"optionsOpen","radioOpen","mobileMenuOpen"}) do
    ui[key]=true
    equal(Pause.isPaused(runtime,ui,maintenance),true,key.." pauses simulation")
    ui[key]=nil
end
runtime.dialogue={timer=5}
equal(Pause.isPaused(runtime,ui,nil,{allowDialogue=true}),false,"dialogue close control remains available")
runtime.dialogue=nil; maintenance.open=true
equal(Pause.isPaused(runtime,ui,maintenance),true,"maintenance pauses simulation")
maintenance.open=false; runtime.lastStand={capture=true}
equal(Pause.isPaused(runtime,ui,maintenance),true,"last stand captures world input")
runtime.lastStand=nil

-- Exercise the actual updater: options/mobile-menu pause enemies and player
-- together, then closing the menu resumes both on the next frame.
runtime={state="game",scene="expedition",saveData={character="test",location=6,droppedItems={}},
    player={x=100,y=100,speed=120,facing=1,moving=true,velocityX=30,velocityY=10},
    animationClock=0,walkingSoundTimer=0,actionTimer=0}
ui={optionsOpen=true,playSfx=noop}
local worldUpdates=0
local update=require("game.gameplay_update").new(defaults({
    runtime=runtime,width=960,holdPickupSeconds=1,ui=ui,car={},landscape={},scenery={},cloudLayer={},maintenanceSession={},
    mobileEnabled=function() return false end,mobileMovement=function() return 0,0 end,mobileHeld=function() return false end,
    mobileSprinting=function() return false end,interactionRouter={select=noop,flags=function() return {} end},
    inventoryActions={},journeyRules={},catalog={},settlements={},interiorDoors={},interactions={},
    clouds={update=noop},screens={is=function() return false end,update=function() return false end},
    engineUpgrades={},trainUpgradeBalance={},maintenance={update=noop},family={},util={},passengers={},
    firstAid={},shootingRange={},screenToGame=passthrough,
    updateWorldScene=function() worldUpdates=worldUpdates+1 end,
    moveExpedition=function(_,_,x,y) return x,y end,
}))
held.d=true
update.update(.1)
equal(worldUpdates,0,"enemy world update paused by options")
equal(runtime.player.x,100,"player paused by options")
equal(runtime.player.velocityX,0,"paused player has no residual movement")
ui.optionsOpen=false; ui.mobileMenuOpen=true
update.update(.1)
equal(worldUpdates,0,"enemy world update paused by mobile menu")
equal(runtime.player.x,100,"player paused by mobile menu")
ui.mobileMenuOpen=false
update.update(.1)
equal(worldUpdates,1,"world resumes after menu closes")
equal(runtime.player.x,112,"player resumes after menu closes")
held.d=nil

-- Real touch controls keep attack on the primary button while an independent
-- contextual button opens chests and uses exits.
runtime={state="game",scene="expedition",saveData={}}
ui={interaction={kind="expedition",action="chest",label="SEARCH CACHE"}}
local keys={}
local mobile=require("game.mobile_runtime").new(defaults({
    runtime=runtime,ui=ui,maintenanceSession={},mobileControls=require("game.mobile_controls"),width=960,height=720,
    viewportToGame=passthrough,getCameraZoom=function() return 1 end,
    getGameplayInput=function() return {keypressed=function(key) keys[#keys+1]=key end,keyreleased=noop,mousepressed=noop,mousemoved=noop,mousereleased=noop} end,
}))
local controls=mobile.initialize()
equal(controls.primaryAction(),"f","attack stays primary near chest")
local secondaryKey,secondaryLabel=controls.secondaryAction()
equal(secondaryKey,"q","chest remains a separate interaction")
equal(secondaryLabel,"OPEN","chest interaction label")
controls:_updateCornerLayout()
controls:touchpressed("attack",controls.primary.x,controls.primary.y)
controls:touchreleased("attack",controls.primary.x,controls.primary.y)
controls:touchpressed("open",controls.secondary.x,controls.secondary.y)
controls:touchreleased("open",controls.secondary.x,controls.secondary.y)
equal(table.concat(keys,","),"f,q","touch buttons route separate actions")
ui.interaction={kind="expedition",action="enterArea",label="RETURN TO OUTSKIRTS"}
equal(controls.primaryAction(),"f","attack stays primary near exit")
secondaryKey,secondaryLabel=controls.secondaryAction()
equal(secondaryLabel,"RETURN","return-area interaction is clearly labeled")
ui.optionsOpen=true
equal(controls:isGameplayActive(),false,"touch actions pause in options")
ui.optionsOpen=false; ui.mobileMenuOpen=true
equal(controls:isGameplayActive(),false,"touch actions pause in mobile menu")

-- Input routes modal close controls before world input, and quick attacks use
-- the direction of travel instead of the button's screen position.
runtime={state="game",scene="expedition",saveData={location=6,droppedItems={}},
    player={x=100,y=100,facing=1,intentX=0,intentY=-1}}
ui={playSfx=noop,interaction={kind="expedition",action="chest"}}
local attacks,interactions=0,0
local aimX,aimY
local router=require("game.interaction_router")
local input=require("game.gameplay_input").new(defaults({
    runtime=runtime,ui=ui,characters={},maintenanceSession={},scenery={},inventory={},catalog={},npcRelationships={},merchantTrade={},
    util={pointIn=function(x,y,box) return box and x>=box.x and x<=box.x+box.w and y>=box.y and y<=box.y+box.h end},
    engineUpgrades={},trainUpgradeBalance={},maintenance={},battleRules={},stops={},settlements={},interiorDoors={},firstAid={},shootingRange={},
    screenToGame=passthrough,worldCoordinates=passthrough,
    attackExpeditionMob=function(x,y) attacks=attacks+1; aimX,aimY=x,y end,
    activateExpeditionInteraction=function() interactions=interactions+1 end,
    interactionKeyAction=router.keyAction,interactionMouseAction=router.mouseAction,
}))
input.keypressed("f")
equal(attacks,1,"normal quick attack accepted")
equal(aimX,100,"quick attack honors north-facing direction x")
equal(aimY,0,"quick attack honors north-facing direction y")
runtime.poseMenu=true
input.keypressed("f"); ui.routeWorldInteraction("q")
equal(attacks,1,"pose menu blocks quick attack")
equal(interactions,0,"pose menu blocks world interaction")
runtime.poseMenu=false; ui.mobileMenuOpen=true
input.keypressed("f"); ui.routeWorldInteraction("q")
equal(attacks,1,"mobile menu blocks quick attack")
equal(interactions,0,"mobile menu blocks world interaction")
ui.mobileMenuOpen=false; runtime.mapOpen=true
ui.expeditionMapClose={x=766,y=28,w=150,h=44}
input.mousepressed(800,44,1)
equal(runtime.mapOpen,false,"local map closes via its visible button")
equal(attacks,1,"closing map does not also attack")
ui.routeWorldInteraction("q")
equal(interactions,1,"context action resumes after map closes")

-- Render the actual HUD against recording graphics to verify that the area
-- objective has a reserved space and MAP dispatches the expedition overlay.
setmetatable(love.graphics,{__index=function() return noop end})
runtime={state="game",scene="expedition",animationClock=0,player={x=100,y=100},saveData={location=6,resources={food=10,water=10,coal=10,oil=10},
    trainCars={"engine"},passengers={},inventory={},droppedItems={}}}
ui={propImages={},drawResource=noop,drawJourneyHUD=noop,drawDialogue=noop,drawMap=function() error("expedition opened the journey map") end}
local localMapDraws,objectiveFrame=0,nil
local hud=require("game.gameplay_hud").new(defaults({
    runtime=runtime,width=960,height=720,ui=ui,colors={cream={1,1,1},brass={1,.7,.2},panel={.1,.1,.1},green={0,1,0},blue={0,0,1},red={1,0,0}},
    maintenanceSession={},holdPickupSeconds=1,getCloudLayer=function() return {} end,mobileEnabled=function() return false end,
    engineUpgrades={},trainUpgradeBalance={resourceCapacity=function() return 20 end},clouds={},maintenance={oilCapacity=function() return 20 end},
    firstAid={},shootingRange={},lastStand={},catalog={},scenery={},npcImages={},util={},train={},
    button=function(label,x,y,w,h) return {x=x,y=y,w=w,h=h,label=label} end,
    drawMenuFrame=function(x,y,w,h) objectiveFrame={x=x,y=y,w=w,h=h} end,
    expeditionObjective=function() return {title="Riverwood Outskirts",text="Find the buried waystation.",status="Threats 0 / 2  •  Caches 0 / 1"} end,
    drawExpeditionLocalMap=function() localMapDraws=localMapDraws+1 end,
    travelStatus=function() return {cost={food=1,water=1,coal=1},affordable=true} end,
}))
hud.draw()
equal(objectiveFrame.y,200,"area objective sits below existing journey HUD")
equal(ui.map.label,"AREA MAP","expedition map control is clearly labeled")
runtime.mapOpen=true
hud.draw()
equal(localMapDraws,1,"expedition map renderer is used")
equal(ui.mapUp,nil,"journey scroll targets are cleared")
equal(ui.expeditionMapClose.label,"CLOSE MAP","local map has a visible close control")

-- The perspective train floor narrows toward its back edge. Its rectangular
-- outer bounds are not a safe spawn at the midpoint used after defeat.
runtime={scene="expedition",saveData={trainCars={"living-car"},activeCar=1},
    player={x=1450,y=460,velocityX=80,velocityY=-30,moving=true},npcActor={}}
local trainRuntime=require("game.train_car_runtime").new({
    runtime=runtime,ui={playSfx=noop},scenery={trainCarImages={["living-car"]={}}},
    car=require("game.config").trainCar,train=require("game.train"),width=960,height=720,writeSave=noop,
})
local left,right,top,bottom=trainRuntime.floorBounds()
local safeX,safeY=trainRuntime.clampToFloor(math.min((left+right)/2,904),(top+bottom)/2)
trainRuntime.enterTrain(false)
local floorX,floorY=trainRuntime.clampToFloor(runtime.player.x,runtime.player.y)
equal(runtime.scene,"train","return selects train scene")
equal(runtime.player.x,floorX,"return x is inside perspective floor")
equal(runtime.player.x,safeX,"return uses clear central floor arrival")
equal(runtime.player.y,safeY,"return uses floor midpoint depth")
assert(runtime.player.x<=904,"returning player is visible inside the viewport")
equal(runtime.player.y,floorY,"return y is inside perspective floor")
equal(runtime.player.velocityX,0,"return clears horizontal momentum")
equal(runtime.player.velocityY,0,"return clears vertical momentum")
equal(runtime.player.moving,false,"return displays idle player")

-- Exploring either expedition layer uses the existing outdoor ambience;
-- formal encounters still select their normal or boss battle playlists.
runtime={state="game",scene="expedition",saveData={activeExpeditionArea="stop06-outskirts"}}
local audioRuntime=require("game.audio_runtime").new({runtime=runtime,ui={},catalog={},audio={},audioCatalog={}})
equal(audioRuntime.musicCategory(),"stops","surface exploration uses stop ambience")
runtime.saveData.activeExpeditionArea="stop06-buried-waystation"
equal(audioRuntime.musicCategory(),"stops","dungeon exploration uses stop ambience")
runtime.state="battle"; runtime.battle={encounter={boss=true}}
equal(audioRuntime.musicCategory(),"bossFight","expedition boss retains boss music")
runtime.battle.encounter.boss=false
equal(audioRuntime.musicCategory(),"battle","expedition mob retains normal battle music")
runtime.state="game"; runtime.scene="train"
equal(audioRuntime.musicCategory(),"train","train return restores train music")

love=previousLove
return {ready=true,checks="modal-world-pause,player-resume,mobile-attack-and-interact,world-input-guards,area-map-close,hud-map-dispatch,train-return-floor,expedition-music"}
