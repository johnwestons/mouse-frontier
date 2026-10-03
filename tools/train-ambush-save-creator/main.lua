local Save=require("game.save")
local SaveSchema=require("game.save_schema")
local Events=require("game.events")

local function report(message)
    print("TRAIN_AMBUSH_SAVE "..message)
end

function love.load()
    local data={
        version=SaveSchema.CURRENT_VERSION,
        character="mail-mouse.png",
        location=2,
        scene="train",
        stopped=true,
        forceEventId="rail-bandits",
        playerX=729,playerY=565,
        health=20,maxHealth=20,scrap=8,
        resources={food=10,water=10,coal=10,oil=10},
        stats={level=1,xp=0,nextXP=10},
        equipment={"frontier-22-lever-rifle","frontier-short-sword"},
        inventory={},
        inventoryCapacity=6,
        ammo={rocks=12,arrows=0,["ball-bearings"]=0,["22lr"]=40,["9mm"]=0,["45-cal"]=0,["556"]=0,["30-carbine"]=0,["8mm"]=0,["380-acp"]=0,["32-acp"]=0,["12-gauge"]=0,["762x39"]=0},
        weaponDurability={["frontier-22-lever-rifle"]=100},
        trainCars={"living-car"},activeCar=1,engineLevel=0,
        maintenance={condition=72,lastServicedStop=0,totalServices=0,totalWear=0},
        audio={station="8bit",musicVolume=.10,sfxVolume=.55,rainVolume=.20,rainEnabled=false,musicPaused=false,musicMuted=false},
        accessibility={version=1,textSize=1,highContrast=false,reducedMotion=false,controlHints=true,touchFeedback=true,largeTouchTargets=true},
        events={},encounters={},visitedStops={[2]=true},eventHistory={},eventCategoryHistory={},eventProgress={story=0,mystery=0},
    }
    local ok,errorMessage=Save.write(1,data)
    if not ok then
        report("FAILED "..tostring(errorMessage))
        love.event.quit(1)
        return
    end
    local loaded=Save.read(1)
    local forced=loaded and Events.random(loaded,{pickCategory=function() return "battle" end})
    if not loaded or loaded.forceEventId~="rail-bandits" or loaded.location~=2 or not forced or forced.id~="rail-bandits" then
        report("FAILED verification")
        love.event.quit(1)
        return
    end
    report("READY slot=1 location=2 forceEventId=rail-bandits scrap=8 ammo22lr=40")
    love.event.quit()
end
