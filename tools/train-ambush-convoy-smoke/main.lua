local Rules=require("game.train_ambush_rules")
local Scene=require("game.train_ambush_scene")
local previewState
local capturePending=false
local captureTimer=0
local function check(condition,message)
    if not condition then error(message) end
end

function love.load()
    local data={location=2,health=20,maxHealth=20,scrap=8,maintenance={condition=72},events={}}
    local state=Rules.start(data)
    previewState=state
    check(#state.vehicles==3,"convoy has three vehicle states")
    check(Rules.vehicle(state,"wagon").maxHull==14,"wagon hull configured")
    check(Rules.vehicle(state,"cargo").maxHull==26,"cargo truck hull configured")
    state.phase="combat"
    local wagon=Rules.vehicle(state,"wagon")
    local ok=Rules.hit(data,state,{kind="hull",vehicle="wagon",x=330,y=235},{ammoType="22lr"})
    check(ok,"wagon hull hit accepted")
    check(#state.bulletHoles==1 and state.bulletHoles[1].vehicle=="wagon","bullet hole persisted on wagon")
    local layout=Scene.layout(state,960,540)
    check(#layout.vehicles==2,"scene lays out near and far vehicle lanes")
    local motionData={location=2,health=20,scrap=8,maintenance={condition=72},events={}}
    local motionState=Rules.start(motionData); motionState.phase="combat"
    for _=1,13 do Rules.hit(motionData,motionState,{kind="hull",vehicle="wagon",x=330,y=235},{ammoType="22lr"}) end
    check(Rules.vehicle(motionState,"wagon").motion.phase=="departLeft","damaged far vehicle exits left")
    Rules.update(motionData,motionState,1.6)
    check(motionState.activeFar=="cargo" and Rules.vehicle(motionState,"cargo").active,"far vehicles take turns")
    for _,vehicle in ipairs(state.vehicles) do
        if vehicle.active then vehicle.motion.phase="matched"; vehicle.motion.clock=0; vehicle.crew[1].phase="peek" end
    end
    print("TRAIN_AMBUSH_CONVOY_OK types=3 lanes=2 bulletHoles="..#state.bulletHoles)
    previewState=state
end

function love.draw()
    if previewState then
        Scene.draw(previewState,960,540,{reducedMotion=true,reducedFlashes=true},nil)
        love.graphics.captureScreenshot("train-ambush-convoy-preview-two-lanes.png")
        previewState=nil
        capturePending=true
    end
end

function love.update(dt)
    if capturePending then
        captureTimer=captureTimer+dt
        if captureTimer>.5 then love.event.quit() end
    end
end
