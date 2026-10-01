local InteractionBeacon=require("game.interaction_beacon")
local WorldPause=require("game.world_pause")
local Rewards=require("game.expedition_rewards")
local Sprites=require("game.expedition_sprites")
local Assets=require("game.assets")
local Typography=require("game.typography")

local ExpeditionRuntime={}

local function required(context,name,expected)
    local value=context[name]
    assert(value~=nil,"expedition runtime requires "..name)
    if expected then assert(type(value)==expected,"expedition runtime "..name.." must be a "..expected) end
    return value
end

local function new(context)
    assert(type(context)=="table","expedition runtime requires a context")
    local runtime=required(context,"runtime","table")
    local ui=required(context,"ui","table")
    local Catalog=required(context,"catalog","table")
    local Areas=required(context,"areas","table")
    local RoamingMobs=required(context,"roamingMobs","table")
    local getIsWeapon=required(context,"getIsWeapon","function")
    local getBeginEncounter=required(context,"getBeginEncounter","function")
    local writeSave=required(context,"writeSave","function")
    local clampToStop=required(context,"clampToStop","function")
    local mobImages=required(context,"mobImages","table")
    local mobIdleImages=required(context,"mobIdleImages","table")
    local mobWalkImages=required(context,"mobWalkImages","table")
    local mobAttackImages=required(context,"mobAttackImages","table")
    local mobHitImages=required(context,"mobHitImages","table")
    local mobDeathImages=required(context,"mobDeathImages","table")
    local mobRangedImages=required(context,"mobRangedImages","table")
    local W=required(context,"width","number")
    local H=required(context,"height","number")
    local roaming=RoamingMobs.new()
    local backgrounds,actionAssets={},{}
    local routes=setmetatable({},{__mode="k"})
    local roamingContext

    local atlasDefinitions={
        ["sludge-bandit.png"]={actionPath="assets/sprites/Mobs/expedition/sludge-bandit-action-atlas.png",walkPath="assets/sprites/Mobs/expedition/sludge-bandit-walk-v5.png"},
        ["sludge-badger-boss.png"]={actionPath="assets/sprites/Mobs/expedition/sludge-badger-boss-action-atlas.png",walkPath="assets/sprites/Mobs/expedition/sludge-badger-boss-walk-v4.png",boss=true},
    }

    local function ensureAssets(area)
        area=area or Areas.current(runtime.saveData)
        if not area then return end
        if not backgrounds[area.id] then
            local image=love.graphics.newImage(area.background); image:setFilter("linear","linear")
            backgrounds[area.id]=image
        end
        for _,definition in ipairs(area.mobs or {}) do
            local file,spec=definition.file,atlasDefinitions[definition.file]
            if spec and not actionAssets[file] then
                local frames=Sprites.load(spec); actionAssets[file]=frames
                for _,image in ipairs(frames) do Assets.markExternallyOwned(image) end
                mobImages[file]=frames[1]; mobIdleImages[file]=frames[1]; mobWalkImages[file]=frames[2]
                mobAttackImages[file]=frames[3]; mobHitImages[file]=frames[4]; mobDeathImages[file]=frames[5]
                mobRangedImages[file]=frames[3]
            elseif not spec and not actionAssets[file] then
                -- Ordinary world mobs use the same authored sprites as regular
                -- encounters. Reuse their standalone sprite in the field until
                -- a later expedition supplies a dedicated action atlas.
                local image=mobImages[file]
                if image then
                    Assets.markExternallyOwned(image)
                    actionAssets[file]={[1]=image,[2]=image,[3]=image,[4]=image,[5]=image,[6]=image,
                        referenceHeight=image:getHeight(),baseFacing=definition.baseFacing or 1}
                end
            end
        end
    end

    local function isWeapon(name)
        local checker=getIsWeapon()
        return type(checker)=="function" and checker(name) or false
    end

    local function enterArea(areaId,spawnId)
        local area=Areas.definition(areaId)
        if not area then return false end
        Areas.ensure(runtime.saveData)
        runtime.saveData.activeExpeditionArea=areaId
        local state=Areas.state(runtime.saveData,areaId); state.discovered=true
        runtime.scene=Areas.SCENE; runtime.npcActor=nil
        local x,y=Areas.spawn(areaId,spawnId)
        runtime.player.x,runtime.player.y=Areas.clamp(runtime.saveData,areaId,x,y)
        Areas.resetEnvironment(runtime.saveData,areaId)
        runtime.expeditionFloodEjectTimer=0
        runtime.player.velocityX,runtime.player.velocityY=0,0
        runtime.player.moving=false; runtime.expeditionGraceTimer=1.5
        roaming.transient[areaId]=nil; routes=setmetatable({},{__mode="k"})
        runtime.inventoryOpen=false; runtime.chestOpen=false; runtime.activeChest=nil; runtime.mapOpen=false
        ensureAssets(area)
        if area.kind=="surface" and not state.tutorialSeen then
            state.tutorialSeen=true
            if area.tutorialText then runtime.dialogue={speaker="Expedition",text=area.tutorialText,timer=10} end
        end
        ui.playSfx("doors"); writeSave()
        return true
    end

    local function returnToStop()
        runtime.scene="stop"; runtime.saveData.activeExpeditionArea=nil; runtime.npcActor=nil
        runtime.player.x,runtime.player.y=clampToStop(875,420)
        runtime.player.velocityX,runtime.player.velocityY=0,0; runtime.player.moving=false
        ui.playSfx("doors"); writeSave()
        return true
    end

    local function currentInteraction()
        return Areas.interaction(runtime.saveData,runtime.scene,runtime.player)
    end

    local function activateInteraction(selected)
        if WorldPause.isPaused(runtime,ui) then return false end
        selected=selected or currentInteraction()
        if not selected or selected.kind~="expedition" then return false end
        if selected.action=="enterArea" then return enterArea(selected.targetArea,selected.spawn) end
        if selected.action=="returnStop" then return returnToStop() end
        if selected.action=="challenge" then
            ensureAssets()
            local ctx=roamingContext()
            return ctx and RoamingMobs.challenge(roaming,ctx,selected.mobId) or false
        end
        if selected.action=="survey" then
            local state=Areas.state(runtime.saveData,selected.areaId or runtime.saveData.activeExpeditionArea)
            if not state or not selected.markerId then return false end
            if state.markers[selected.markerId] then
                roaming.message="This cairn is already marked."
            else
                state.markers[selected.markerId]=true
                local gates=Areas.updateGates(runtime.saveData,selected.areaId or runtime.saveData.activeExpeditionArea)
                local area=Areas.definition(selected.areaId or runtime.saveData.activeExpeditionArea)
                local marked=0
                for _,markerId in ipairs(area and area.completionRequiredMarkers or {}) do
                    if state.markers[markerId] then marked=marked+1 end
                end
                roaming.message=gates and gates.routeSurveyed and "The basin route is fully surveyed."
                    or ("Cairn marked. "..marked.." of "..#(area and area.completionRequiredMarkers or {}).." charted.")
                ui.playSfx("menu"); writeSave()
            end
            roaming.messageTimer=3.5
            return true
        end
        if selected.action=="chest" then
            local state=Areas.state(runtime.saveData,selected.areaId or runtime.saveData.activeExpeditionArea)
            local gates=Areas.updateGates(runtime.saveData,selected.areaId or runtime.saveData.activeExpeditionArea)
            if selected.requires and not (gates and gates[selected.requires]) then
                local area=Areas.definition(selected.areaId or runtime.saveData.activeExpeditionArea)
                roaming.message=selected.lockedMessage or (area and area.sealedCacheMessage) or "This cache is sealed."
                roaming.messageTimer=4.5
                return true
            end
            local chest=state and state.chests[selected.chestId]
            if not chest then return false end
            chest.opened=true; runtime.activeChest=chest; runtime.chestOpen=true; runtime.inventoryOpen=true
            runtime.draggedSlot=nil; runtime.inventoryDragActive=false; ui.playSfx("menu"); writeSave()
            return true
        end
        return false
    end

    roamingContext=function()
        local area=Areas.current(runtime.saveData)
        if not area then return nil end
        local areaState=Areas.state(runtime.saveData,area.id)
        return {
            data=runtime.saveData,area=area,areaState=areaState,player=runtime.player,catalog=Catalog,
            isWeapon=isWeapon,clock=runtime.animationClock,assets=actionAssets,
            grace=(runtime.expeditionGraceTimer or 0)>0,
            onHostileAction=function() runtime.expeditionGraceTimer=0 end,
            isActive=function(definition) return Areas.isMobActive(runtime.saveData,area.id,definition) end,
            canReach=function(x1,y1,x2,y2) return Areas.canReach(runtime.saveData,area.id,x1,y1,x2,y2) end,
            pathTarget=function(saved,x,y)
                local now=runtime.animationClock or 0
                local route=routes[saved]
                if route and route.untilTime>now and (route.targetX-x)^2+(route.targetY-y)^2<24^2
                    and (route.x-saved.x)^2+(route.y-saved.y)^2>6^2 then return route.x,route.y end
                local nx,ny=Areas.pathTarget(runtime.saveData,area.id,saved.x,saved.y,x,y)
                if nx then routes[saved]={x=nx,y=ny,targetX=x,targetY=y,untilTime=now+.35} else routes[saved]=nil end
                return nx,ny
            end,
            move=function(oldX,oldY,newX,newY) return Areas.move(runtime.saveData,area.id,oldX,oldY,newX,newY) end,
            beginEncounter=function(encounter)
                ensureAssets(area)
                local begin=getBeginEncounter(); assert(type(begin)=="function","battle runtime is not ready")
                begin(encounter)
            end,
            onAction=function(weapon,duration) runtime.actionHeldItem=weapon; runtime.actionKind="melee"; runtime.actionTimer=duration or .42 end,
            playSfx=ui.playSfx,
            onDefeated=function(definition,saved)
                local receipt=Rewards.claimEnemy(runtime.saveData,Catalog,definition,saved)
                Areas.updateGates(runtime.saveData,area.id); writeSave()
                return Rewards.summary(receipt)
            end,
        }
    end

    local function update(dt)
        if runtime.scene~=Areas.SCENE or not runtime.saveData or not runtime.player then return end
        Areas.ensure(runtime.saveData); Areas.updateGates(runtime.saveData,runtime.saveData.activeExpeditionArea)
        if WorldPause.isPaused(runtime,ui) then return end
        runtime.expeditionFloodEjectTimer=math.max(0,(runtime.expeditionFloodEjectTimer or 0)-dt)
        local environmentPhase,environmentChanged=Areas.updateEnvironment(runtime.saveData,runtime.saveData.activeExpeditionArea,dt)
        if environmentChanged and environmentPhase=="flooded"
            and Areas.isInFlood(runtime.saveData,runtime.saveData.activeExpeditionArea,runtime.player.x,runtime.player.y) then
            local bankX,bankY=Areas.nearestFloodBank(runtime.saveData,runtime.saveData.activeExpeditionArea,runtime.player.x,runtime.player.y)
            if bankX and bankY then
                runtime.player.x,runtime.player.y=bankX,bankY
                runtime.player.velocityX,runtime.player.velocityY=0,0; runtime.player.moving=false
                runtime.expeditionFloodEjectTimer=3.5
            end
        end
        if environmentChanged then writeSave() end
        runtime.expeditionGraceTimer=math.max(0,(runtime.expeditionGraceTimer or 0)-dt)
        local state=Areas.state(runtime.saveData,runtime.saveData.activeExpeditionArea)
        if state.completed and not state.completionNotified then
            state.completionNotified=true
            local area=Areas.current(runtime.saveData)
            roaming.message=(area and area.completionMessage) or "The guardian is defeated. The vault is open!"
            roaming.messageTimer=7
            writeSave()
        end
        local ctx=roamingContext(); if ctx then RoamingMobs.update(roaming,ctx,dt) end
    end

    local function attack(x,y)
        if runtime.scene~=Areas.SCENE or WorldPause.isPaused(runtime,ui) then return false end
        ensureAssets()
        local ctx=roamingContext(); if not ctx then return false end
        local used=RoamingMobs.attack(roaming,ctx,x,y)
        if used then writeSave() end
        return used
    end

    local function draw(options)
        local area=Areas.current(runtime.saveData); if not area then return end
        ensureAssets(area)
        local offsetX,offsetY=Areas.cameraOffset(runtime.saveData,runtime.player,W,H)
        love.graphics.push(); love.graphics.translate(-offsetX,-offsetY)
        love.graphics.setColor(1,1,1)
        local background=backgrounds[area.id]
        if background then love.graphics.draw(background,0,0,0,area.width/background:getWidth(),area.height/background:getHeight()) end
        local environment=Areas.environment(runtime.saveData,area.id)
        local floodZone=environment and environment.definition.floodZone
        if environment and environment.flooded and floodZone then
            love.graphics.setColor(.10,.48,.74,.76); love.graphics.setLineWidth(floodZone.radius*2)
            for i=1,#floodZone.points-1 do
                local a,b=floodZone.points[i],floodZone.points[i+1]
                love.graphics.line(a.x,a.y,b.x,b.y)
                love.graphics.circle("fill",a.x,a.y,floodZone.radius)
                if i==#floodZone.points-1 then love.graphics.circle("fill",b.x,b.y,floodZone.radius) end
            end
            love.graphics.setLineWidth(1)
        end
        local gates=Areas.updateGates(runtime.saveData,area.id)
        if area.kind=="dungeon" and gates and not gates.bossGateOpen then
            local pulse=.55+.25*math.sin(runtime.animationClock*5)
            love.graphics.setColor(.08,.04,.02,.78); love.graphics.rectangle("fill",993,419,27,101,8,8)
            love.graphics.setColor(.25,.95,.92,pulse); love.graphics.setLineWidth(4)
            for y=425,500,15 do love.graphics.line(998,y,1015,y+10) end
            love.graphics.setLineWidth(1)
        end
        local state=Areas.state(runtime.saveData,area.id)
        for _,spot in ipairs(area.interactions or {}) do
            local chest=spot.chestId and state.chests[spot.chestId]
            if chest and chest.opened then
                -- Raised lid and dark empty interior remain visible in the world.
                love.graphics.setColor(.16,.09,.035,1); love.graphics.rectangle("fill",spot.x-17,spot.y-28,34,17,3,3)
                love.graphics.setColor(.62,.40,.15,1); love.graphics.polygon("fill",spot.x-18,spot.y-29,spot.x+18,spot.y-29,spot.x+15,spot.y-45,spot.x-15,spot.y-45)
                love.graphics.setColor(.96,.78,.35,1); love.graphics.rectangle("line",spot.x-17,spot.y-28,34,17,3,3)
            end
        end
        InteractionBeacon.drawUnderlay(ui.interaction,runtime.animationClock,{player=runtime.player,saveData=runtime.saveData})
        if options and options.drawDroppedItems then options.drawDroppedItems() end
        local ctx=roamingContext(); if ctx then RoamingMobs.draw(roaming,ctx,options and options.drawPlayer) end
        InteractionBeacon.drawOverlay(ui.interaction,runtime.animationClock,{player=runtime.player,saveData=runtime.saveData})
        love.graphics.pop()
        local message
        if not WorldPause.isPaused(runtime,ui) then
            local area=Areas.current(runtime.saveData)
            local environment=area and Areas.environment(runtime.saveData,area.id)
            if (runtime.expeditionFloodEjectTimer or 0)>0 then message="THE SURGE CARRIES YOU TO THE NEAREST BANK"
            elseif environment and environment.phase=="warning" then message="THE WASH IS RISING — TAKE THE HIGH RIDGE"
            elseif environment and environment.flooded then message="FLASH FLOOD — THE LOW WASH IS CLOSED"
            elseif environment and environment.phase=="receding" then message="THE FLOOD IS DRAINING — THE WASH WILL REOPEN"
            else message=RoamingMobs.message(roaming) end
        end
        if message then
            love.graphics.setColor(.04,.025,.02,.86); love.graphics.rectangle("fill",W/2-205,H-74,410,42,8,8)
            love.graphics.setColor(1,1,1,1); love.graphics.printf(message,W/2-195,H-61,390,"center")
        end
    end

    local function move(oldX,oldY,newX,newY)
        return Areas.move(runtime.saveData,runtime.saveData.activeExpeditionArea,oldX,oldY,newX,newY)
    end

    local function cameraOffset()
        return Areas.cameraOffset(runtime.saveData,runtime.player,W,H)
    end

    local function audit()
        local areaAudit=Areas.audit(); local mobAudit=RoamingMobs.audit()
        return {ready=areaAudit.ready and mobAudit.ready,areas=areaAudit,mobs=mobAudit,assetCount=6,curve="expedition-runtime-v2"}
    end

    local function reset()
        roaming=RoamingMobs.new()
        routes=setmetatable({},{__mode="k"})
        runtime.expeditionGraceTimer=0
    end

    local function objective()
        if runtime.scene~=Areas.SCENE then return nil end
        local area=Areas.current(runtime.saveData)
        if not area then return nil end
        local gates=Areas.updateGates(runtime.saveData,area.id) or {}
        local state=Areas.state(runtime.saveData,area.id)
        local defeated=0
        for _,mob in pairs(state.mobs or {}) do if mob.dead then defeated=defeated+1 end end
        local objectives=area.objectives or {}
        local text=state.completed and objectives.complete
            or area.kind=="surface" and objectives.surface
            or area.progressType=="survey" and objectives.explore
            or gates.bossDefeated and objectives.complete
            or gates.bossGateOpen and objectives.bossReady
            or objectives.gateClosed
            or "Explore the area and follow the route."
        local status="CLEARED "..defeated.."/"..#area.mobs
        if area.progressType=="survey" then
            local marked=0
            for _,markerId in ipairs(area.completionRequiredMarkers or {}) do
                if state.markers[markerId] then marked=marked+1 end
            end
            status="CAIRNS "..marked.."/"..#(area.completionRequiredMarkers or {})
        end
        return {title=area.name,text=text,status=status}
    end

    local function drawTrailhead()
        if runtime.scene~="stop" or not runtime.saveData or not Areas.availableAtStop(runtime.saveData.location) then return end
        local spot=Areas.entrance(runtime.saveData.location)
        local entrance=Areas.interaction(runtime.saveData,"stop",{x=spot.x,y=spot.y})
        love.graphics.push("all")
        love.graphics.setColor(.23,.12,.045,1); love.graphics.rectangle("fill",spot.x-4,spot.y-35,8,42)
        love.graphics.setColor(.38,.23,.08,1); love.graphics.polygon("fill",spot.x-96,spot.y-68,spot.x-3,spot.y-68,spot.x+14,spot.y-49,spot.x-3,spot.y-30,spot.x-96,spot.y-30)
        love.graphics.setColor(1,.85,.44,1); love.graphics.printf(spot.signLabel or "EXPEDITION",spot.x-92,spot.y-57,133,"center",0,.68,.68)
        love.graphics.pop()
        local options={player=runtime.player,saveData=runtime.saveData}
        InteractionBeacon.drawUnderlay(entrance,runtime.animationClock,options)
        InteractionBeacon.drawOverlay(entrance,runtime.animationClock,options)
    end

    local function drawLocalMap()
        local area=Areas.current(runtime.saveData)
        if not area then return end
        ensureAssets(area)
        love.graphics.push("all")
        love.graphics.setColor(.045,.035,.025,.97)
        love.graphics.rectangle("fill",80,80,W-160,H-150,12,12)
        local scale=math.min((W-208)/area.width,(H-246)/area.height)
        local x,y=(W-area.width*scale)/2,150
        local background=backgrounds[area.id]
        love.graphics.setColor(1,1,1,1)
        if background then love.graphics.draw(background,x,y,0,area.width*scale/background:getWidth(),area.height*scale/background:getHeight()) end
        local state=Areas.state(runtime.saveData,area.id)
        local gates=Areas.updateGates(runtime.saveData,area.id)
        local nextStep=objective()
        local environment=Areas.environment(runtime.saveData,area.id)
        ui.expeditionMapObjectiveBounds={x=110,y=126,w=W-220,h=18}
        love.graphics.setLineWidth(2)
        for _,path in ipairs(area.corridors or {}) do
            local open=not path.gate or gates[path.gate]
            if open then love.graphics.setColor(.96,.82,.41,.46) else love.graphics.setColor(.64,.44,.85,.55) end
            love.graphics.line(x+path.x1*scale,y+path.y1*scale,x+path.x2*scale,y+path.y2*scale)
        end
        local floodZone=environment and environment.definition.floodZone
        if environment and environment.phase~="dry" and floodZone then
            if environment.flooded then love.graphics.setColor(.20,.70,.96,.82)
            elseif environment.phase=="warning" then love.graphics.setColor(1,.78,.28,.78)
            else love.graphics.setColor(.45,.78,.93,.48) end
            love.graphics.setLineWidth(math.max(3,floodZone.radius*2*scale))
            for i=1,#floodZone.points-1 do
                local a,b=floodZone.points[i],floodZone.points[i+1]
                love.graphics.line(x+a.x*scale,y+a.y*scale,x+b.x*scale,y+b.y*scale)
            end
            love.graphics.setLineWidth(2)
        end
        love.graphics.setColor(1,.86,.60,1)
        love.graphics.printf(area.name,110,105,W-220,"center")
        love.graphics.setColor(.86,.80,.68,1)
        local guidance=nextStep and nextStep.text or ""
        if environment and environment.phase=="warning" then guidance="THE WASH IS RISING: USE THE HIGH RIDGE"
        elseif environment and environment.flooded then guidance="FLASH FLOOD: THE LOW WASH IS CLOSED"
        elseif environment and environment.phase=="receding" then guidance="FLOODWATER IS DRAINING FROM THE WASH" end
        Typography.drawText(love.graphics,guidance,110,126,W-220,18,
            {scale=.72,minScale=.62,singleLine=true,align="center",valign="center"})
        for _,spot in ipairs(area.interactions or {}) do
            local chest=spot.chestId and state.chests[spot.chestId]
            local locked=spot.requires and not gates[spot.requires]
            local surveyed=spot.markerId and state.markers[spot.markerId]
            local sx,sy=x+spot.x*scale,y+spot.y*scale
            if surveyed then love.graphics.setColor(.48,.92,.67,1)
            elseif locked then love.graphics.setColor(.76,.52,.98,1)
            elseif chest and chest.opened then love.graphics.setColor(.60,.67,.65,1)
            else love.graphics.setColor(.98,.76,.32,1) end
            love.graphics.circle("fill",sx,sy,5)
            local label=spot.markerId and (surveyed and "MARKED" or (spot.mapLabel or "CAIRN"))
                or spot.kind=="chest" and (locked and "SEALED CACHE" or chest.opened and "OPENED CACHE" or (spot.mapLabel or "CACHE"))
                or spot.kind=="returnStop" and (spot.mapLabel or "TOWN") or (spot.mapLabel or "AREA")
            love.graphics.printf(label,sx-40,sy+8,133,"center",0,.60,.60)
        end
        for _,definition in ipairs(area.mobs or {}) do
            local mob=state.mobs[definition.id]
            if not mob.dead and Areas.isMobActive(runtime.saveData,area.id,definition) then
                love.graphics.setColor(1,.30,.20,1)
                love.graphics.circle("line",x+mob.x*scale,y+mob.y*scale,definition.boss and 8 or 4)
            end
        end
        if runtime.player then
            love.graphics.setColor(.55,.95,.80,1)
            love.graphics.circle("fill",x+runtime.player.x*scale,y+runtime.player.y*scale,5)
        end
        love.graphics.setColor(1,.86,.60,1)
        love.graphics.printf("GOLD: paths / caches    RED: threats    GREEN: you    VIOLET: sealed",95,H-102,(W-190)/.75,"center",0,.75,.75)
        love.graphics.pop()
    end

    return {update=update,draw=draw,move=move,attack=attack,currentInteraction=currentInteraction,
        activateInteraction=activateInteraction,enterArea=enterArea,returnToStop=returnToStop,
        cameraOffset=cameraOffset,ensureAssets=ensureAssets,reset=reset,audit=audit,
        objective=objective,drawTrailhead=drawTrailhead,drawLocalMap=drawLocalMap}
end

return {new=new}
