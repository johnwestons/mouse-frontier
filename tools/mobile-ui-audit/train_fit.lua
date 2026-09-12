-- Train-only extension of the isolated real-application visual audit.
local Audit={}

function Audit.setup(ctx)
    local View=require("game.train_view")
    local Train=require("game.train")
    local CharacterAnimation=require("game.character_animation")
    local game,ui,services=ctx.game,ctx.ui,ctx.services
    local car=ctx.context.state.car
    local scenery=ctx.context.graphs.content.scenery
    local G=love.graphics
    local carIds={"living-car","coal-hauler","storage","greenhouse","sleeper","medical","navigator"}
    local nativeWidth,nativeHeight=ctx.mobile and 2340 or 1280,ctx.mobile and 1080 or 720
    local imageKinds={}
    local function images(value,kind,seen)
        if type(value)=="userdata" and value.typeOf and value:typeOf("Image") then imageKinds[value]=kind
        elseif type(value)=="table" then
            seen=seen or {}; if seen[value] then return end; seen[value]=true
            for _,child in pairs(value) do images(child,kind,seen) end
        end
    end
    images(scenery.track,"track"); images(scenery.ballastPocketFrames,"ballast")
    images(scenery.worldTrainBody,"engine"); images(scenery.worldTrainRunningGear,"engine-gear")
    images(scenery.worldTrainSmokeFrames,"smoke"); images(scenery.trainCarBogie,"car-gear")
    images(scenery.trainCarImages,"car"); images(ui.propImages,"contents")
    images(ctx.context.graphs.content.itemIdleImages,"contents")
    local counts,drawCount={},0
    local depth,trainDepth,characterKind=0,nil,nil
    local originalPush,originalPop,originalApply,originalDraw=G.push,G.pop,View.apply,G.draw
    G.push=function(...) depth=depth+1; return originalPush(...) end
    G.pop=function(...)
        if trainDepth==depth then trainDepth=nil end
        depth=depth-1; return originalPop(...)
    end
    View.apply=function(layout)
        originalApply(layout)
        trainDepth=depth
    end
    local originalCharacterDraw=CharacterAnimation.draw
    CharacterAnimation.draw=function(sets,file,...)
        local previous=characterKind
        characterKind=file==game.saveData.character and "player" or "passenger"
        local result=originalCharacterDraw(sets,file,...)
        characterKind=previous
        return result
    end
    G.draw=function(image,...)
        if trainDepth then
            local layout=services.presentationRuntime.getTrainView()
            local ox,oy=G.transformPoint(0,0)
            local xx,xy=G.transformPoint(1,0)
            local yx,yy=G.transformPoint(0,1)
            local expected=layout.viewportScale*layout.scale*services.presentationRuntime.getZoom()
            local kind=characterKind or imageKinds[image] or "other"
            assert(math.abs(xx-ox-expected)<.002 and math.abs(yy-oy-expected)<.002
                and math.abs(xy-oy)<.002 and math.abs(yx-ox)<.002,kind.." escaped uniform train scaling")
            if not game.carTransition and not game.travelTransition then
                local vx,vy=require("game.viewport").transform(960,720)
                assert(math.abs(ox-vx-layout.x*layout.viewportScale)<.002
                    and math.abs(oy-vy-layout.y*layout.viewportScale)<.002,kind.." escaped common train anchor")
            end
            counts[kind]=(counts[kind] or 0)+1; drawCount=drawCount+1
        end
        return originalDraw(image,...)
    end

    local function prepare(width,height,count,active)
        assert(love.window.setMode(width or nativeWidth,height or nativeHeight,{resizable=false,vsync=0}))
        game.carTransition=nil; game.travelTransition=nil; game.editDragging=nil; game.editedItem=nil
        ui.editSliderDrag=nil; ui.interaction=nil; ui.itemOrderCache={}
        game.saveData.trainCars={}
        for i=1,count or 1 do game.saveData.trainCars[i]=carIds[i] end
        game.saveData.activeCar=active or 1; game.saveData.location=6; game.saveData.stopped=true
        game.animationClock=.7; game.sceneryOffset=47; game.playerPose="idle"; game.actionTimer=0
        game.player.x,game.player.y=services.trainCarRuntime.clampToFloor(740,555)
        game.player.facing=1; game.player.intentX=1; game.player.intentY=0
        game.saveData.droppedItems={}
        game.saveData.passengers={}
        for i=1,count or 1 do
            for _,item in ipairs({
                {name="boombox-radio",x=550,y=583,scale=1.15},
                {name="armchair-green",x=666,y=574,scale=1.15},
                {name="orange-rose-vase",x=855,y=555,scale=.85},
                {name="travel-chest",x=902,y=578,scale=1},
            }) do
                images(ui.propImages[item.name],"contents")
                images(ctx.context.graphs.content.itemIdleImages[item.name],"contents")
                item.scene="train"; item.carIndex=i; item.rotation=0
                game.saveData.droppedItems[#game.saveData.droppedItems+1]=item
            end
            game.saveData.passengers[#game.saveData.passengers+1]={npc="guard-fox.png",job="scavenger",
                x=813,y=555,carIndex=i,facing=-1,pose="idle",moving=false,ridesLeft=5}
        end
        counts={}; drawCount=0
    end
    local function check(transition)
        local width,height=G.getDimensions()
        local layout=assert(services.presentationRuntime.getTrainView())
        assert(layout.left>=layout.visibleLeft+20-.001 and layout.right<=layout.visibleRight-20+.001,
            "train does not fit viewport side margins")
        assert(layout.top>=layout.headerBottom-.001 and layout.bottom<720,"train crosses header or screen floor")
        assert(drawCount>0 and counts.track and counts.ballast and counts.car and counts["car-gear"],
            "train or tracks missing from transform audit")
        assert(counts.player and counts.passenger and counts.contents,"player, passenger or contents missing: "
            ..tostring(counts.player).."/"..tostring(counts.passenger).."/"..tostring(counts.contents))
        if (game.saveData.activeCar or 1)==1 then
            assert(counts.engine and counts["engine-gear"] and counts.smoke,"locomotive component missing")
        end
        assert(game.selectedSlot==nil,"train audit must stay unslotted")
        local categories={}; for kind,count in pairs(counts) do categories[#categories+1]=kind.."="..count end
        table.sort(categories)
        ctx.record(string.format("PASS train %dx%d %s car %d/%d scale=%.4f bounds=[%.1f,%.1f,%.1f,%.1f] %s draws: %s",
            width,height,game.saveData.trainCars[game.saveData.activeCar],game.saveData.activeCar,#game.saveData.trainCars,
            layout.scale,layout.left,layout.top,layout.right,layout.bottom,transition and "transition" or "contained",
            table.concat(categories,", ")))
    end
    local function add(name,setup,transition)
        ctx.add(name,setup,function() check(transition) end)
    end
    add("01-native-living-one-car",function() prepare() end)
    for i,id in ipairs(carIds) do
        add(string.format("%02d-native-%s-seven-cars",i+1,id),function() prepare(nil,nil,7,i) end)
    end
    add("09-fit-4-by-3",function() prepare(960,720) end)
    add("10-fit-16-by-9",function() prepare(1280,720) end)
    add("11-fit-phone",function() prepare(2340,1080) end)
    add("12-fit-ultrawide",function() prepare(3440,1440) end)
    add("13-editor-selected-furniture",function()
        prepare(); game.editMode=true; game.editedItem=2
    end)
    add("14-car-transition-midpoint",function()
        prepare(nil,nil,7,1)
        assert(services.trainCarRuntime.beginTransition(2))
        game.carTransition.t=game.carTransition.duration*.5
    end,true)
    add("15-train-departure",function()
        prepare()
        local timing=require("game.engine_upgrades").timings(game.saveData.engineLevel,100)
        game.travelTransition={t=timing.depart*.55,maintenanceCondition=100}
    end,true)
    add("16-train-arrival",function()
        prepare()
        local timing=require("game.engine_upgrades").timings(game.saveData.engineLevel,100)
        game.travelTransition={t=timing.arrive+timing.arrivalDuration*.60,maintenanceCondition=100}
    end,true)
    ctx.record("Train audit: 16 real-game captures; all train-image parent transforms checked; no saved-slot writes")
end

return Audit
