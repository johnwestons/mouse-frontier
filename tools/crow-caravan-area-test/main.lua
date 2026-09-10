local sourceBase=love.filesystem.getSourceBaseDirectory()
package.path=sourceBase.."/../?.lua;"..sourceBase.."/../?/init.lua;"..package.path

function love.load()
    local Area=require("game.crow_caravan_area")
    local CrowCaravans=require("game.crow_caravans")
    local Catalog=require("game.catalog")
    local Settlements=require("game.settlements")
    Settlements.load(function() return nil end)

    local audit=Area.audit()
    assert(audit.ready,table.concat(audit.errors or {},"; "))
    assert(audit.safe and audit.width==960 and audit.height==720,"safe one-screen contract changed")
    assert(audit.gateCount==18,"authored caravan host count changed")
    assert(Area.stopEntrance(12,nil)==nil,"unauthored stop gates must not be guessed")
    local gate=Area.stopEntrance(9)
    assert(gate and gate.action=="enterCaravan" and gate.campId=="crow-caravan-stop-9","stop gate contract failed")
    for stop,position in pairs(Area.authoredStopGates) do
        assert(Settlements.isWalkable(stop,position.x,position.y),"authored gate is not walkable at stop "..stop)
        local trainX,trainY=Settlements.trainPoint(stop)
        local distance=math.sqrt((position.x-trainX)^2+(position.y-trainY)^2)
        assert(distance>125,"authored gate overlaps the train at stop "..stop)
        assert(not Settlements.nearDoor(position.x,position.y,stop),"authored gate overlaps a door at stop "..stop)
        local activityX=315+((stop*37)%61)-30
        local activityY=505+((stop*23)%35)-17
        activityX,activityY=Settlements.clamp(activityX,activityY,stop)
        distance=math.sqrt((position.x-activityX)^2+(position.y-activityY)^2)
        assert(distance>120,"authored gate overlaps the settlement activity at stop "..stop)
    end

    local data={location=12,inventoryCapacity=16,weaponDurability={}}
    local schedule,reason=CrowCaravans.ensureSchedule(data,{bands={{12,12},{27,27},{43,43}},useDefaultExclusions=false,rng=function() return 0 end})
    assert(schedule,reason)
    local camp
    camp,reason=CrowCaravans.ensureCamp(data,Catalog,12,{rng=function() return .47 end})
    assert(camp,reason)
    local originalMerchants=camp.merchants
    local session,spawnX,spawnY=Area.enter(data,12,{x=815,y=548,facing=-1},{camp=camp})
    assert(session and session.safe and #session.actors==3,"session did not create three safe merchant actors")
    assert(camp.merchants==originalMerchants and #camp.merchants==3,"area helper changed stock merchants")
    assert(spawnX==480 and spawnY==626 and Area.isWalkable(spawnX,spawnY),"arrival spawn is invalid")
    assert(not Area.isWalkable(480,466),"campfire footprint must block movement")
    local actor=session.actors[1]
    local selected=Area.interaction(session,{x=actor.x,y=actor.y})
    assert(selected and selected.action=="trade" and selected.merchantId=="packmaster","merchant interaction failed")
    local returned=Area.interaction(session,{x=480,y=660})
    assert(returned and returned.action=="returnStop","return interaction failed")
    local blockedX,blockedY=Area.move(480,550,480,466)
    assert(blockedX==480 and blockedY==550,"movement entered the campfire footprint")
    local drewWithoutSprites,missingSpriteError=pcall(Area.draw,session,{})
    assert(not drewWithoutSprites and tostring(missingSpriteError):find("requires its authored sprite assets",1,true),
        "campsite must reject missing sprite assets instead of drawing procedural replacements")
    Area.savePosition(session,{x=520,y=600,facing=1})
    local restored=Area.restore(data)
    assert(restored and restored.id==session.id,"active campsite did not restore")
    local returnX,returnY,returnFacing=Area.leave(data,restored)
    assert(returnX==815 and returnY==548 and returnFacing==-1,"exact stop return context was lost")
    assert(data.crowCaravans.activeCampId==nil,"leaving did not clear active campsite")

    print("CROW_CARAVAN_AREA_TEST PASS merchants="..audit.merchantCount.." interactions="..audit.interactionCount)
    love.event.quit(0)
end
