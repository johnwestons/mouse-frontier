-- Compact, combat-free off-stop area used by The Rookery Caravan.
--
-- This module deliberately owns only campsite geometry and presentation. The
-- journey scheduler decides which stops host the caravan, the trade service
-- owns stock and transactions, and the caller owns scene transitions/saving.
local CaravanArea = {}

CaravanArea.SCENE = "caravan"
CaravanArea.KIND = "crowCaravan"
CaravanArea.BASE_ID = "crow-caravan"
CaravanArea.WIDTH = 960
CaravanArea.HEIGHT = 720
CaravanArea.SAFE = true
CaravanArea.VARIANT_ID = "rookery-v1"
CaravanArea.WALK_MASK = "assets/backgrounds/walkmask-crow-caravan-campsite-v1.png"

local walkMaskImage

local function walkMask()
    if not (love and love.image and love.image.newImageData) then return nil end
    if walkMaskImage==nil then
        local ok,image=pcall(love.image.newImageData,CaravanArea.WALK_MASK)
        walkMaskImage=ok and image or false
    end
    return walkMaskImage or nil
end

local arrivalSpawn = {x=480,y=626}
local returnGate = {
    id="return-stop", kind=CaravanArea.KIND, action="returnStop",
    x=480, y=660, radius=78, hoverRadius=62, label="RETURN TO STOP",
}

-- Vetted against the authored walk masks, door approaches, train anchors,
-- and the settlement activity anchor. Stops not listed here can never host a
-- caravan; this prevents a clamped fallback from placing the banner in an
-- unsafe or unreadable part of a settlement.
local authoredStopGates = {
    [9]={x=820,y=610}, [10]={x=820,y=610}, [11]={x=815,y=607},
    [13]={x=820,y=610}, [16]={x=820,y=610},
    [23]={x=827,y=620}, [24]={x=809,y=624}, [25]={x=820,y=610},
    [28]={x=820,y=610}, [29]={x=814,y=633}, [30]={x=806,y=558},
    [31]={x=774,y=499},
    [39]={x=804,y=401}, [40]={x=820,y=610}, [41]={x=820,y=610},
    [42]={x=783,y=521}, [45]={x=140,y=610}, [46]={x=808,y=607},
}

local merchantDefinitions = {
    {
        id="packmaster", name="Packmaster", file="crow-merchant.png",
        specialty="provisions", x=286, y=385, radius=104,
        label="TRADE - PACKMASTER", intentX=1, intentY=1,
    },
    {
        id="curio-keeper", name="Curio Keeper", file="crow-merchant.png",
        specialty="curios", x=480, y=260, radius=104,
        label="TRADE - CURIO KEEPER", intentX=0, intentY=1,
    },
    {
        id="ironbeak", name="Ironbeak", file="crow-merchant.png",
        specialty="weapons", x=674, y=385, radius=104,
        label="TRADE - IRONBEAK", intentX=-1, intentY=1,
    },
}

local stalls = {
    {id="provision-stall",merchantId="packmaster",x=176,y=264,w=210,h=106},
    {id="curio-wagon",merchantId="curio-keeper",x=382,y=132,w=196,h=108},
    {id="arms-stall",merchantId="ironbeak",x=574,y=264,w=210,h=106},
}

-- Dedicated campsite sprites occupy these authored prop footprints.
local props = {
    {name="patched-tent",x=196,y=230,maxW=148,maxH=112},
    {name="patched-tent",x=764,y=230,maxW=148,maxH=112,mirror=true},
    {name="supply-crate",x=192,y=420,maxW=54,maxH=48},
    {name="wooden-barrel",x=230,y=438,maxW=44,maxH=52},
    {name="reinforced-crate",x=730,y=423,maxW=54,maxH=48},
    {name="wooden-barrel",x=770,y=440,maxW=44,maxH=52},
    {name="lit-campfire",x=480,y=470,maxW=84,maxH=78,foreground=true},
}

-- Collision footprints use player-foot coordinates, not artwork bounds.
local obstacles = {
    {kind="rect",x=150,y=145,w=235,h=112},
    {kind="rect",x=388,y=112,w=184,h=102},
    {kind="rect",x=575,y=145,w=235,h=112},
    {kind="rect",x=157,y=270,w=142,h=72},
    {kind="rect",x=661,y=270,w=142,h=72},
    {kind="circle",x=480,y=466,r=46},
}

local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end

local function clampNumber(value,minimum,maximum)
    return math.max(minimum,math.min(maximum,value))
end

local function distance(ax,ay,bx,by)
    local dx,dy=bx-ax,by-ay
    return math.sqrt(dx*dx+dy*dy)
end

local function shallowCopy(source)
    local result={}
    for key,value in pairs(source or {}) do result[key]=value end
    return result
end

local function campId(stop)
    return "crow-caravan-stop-"..tostring(math.max(1,math.floor(tonumber(stop) or 1)))
end

local function defaultSeed(stop)
    -- Stable without relying on bit libraries, so old saves and tests agree.
    return (math.max(1,math.floor(tonumber(stop) or 1))*48271+7919)%2147483647
end

local function insideEllipse(x,y,cx,cy,rx,ry)
    local dx,dy=(x-cx)/rx,(y-cy)/ry
    return dx*dx+dy*dy<=1
end

local function insideObstacle(x,y,padding,obstacle)
    if obstacle.kind=="circle" then
        return distance(x,y,obstacle.x,obstacle.y)<=obstacle.r+padding
    end
    return x>=obstacle.x-padding and x<=obstacle.x+obstacle.w+padding
        and y>=obstacle.y-padding and y<=obstacle.y+obstacle.h+padding
end

local function rawWalkable(x,y,padding)
    if not finite(x) or not finite(y) then return false end
    padding=math.max(0,tonumber(padding) or 0)
    local main=insideEllipse(x,y,480,410,365-padding,250-padding)
    local arrival=x>=420+padding and x<=540-padding and y>=400 and y<=690-padding
    if not main and not arrival then return false end
    if x<42+padding or x>918-padding or y<88+padding or y>690-padding then return false end
    for _,obstacle in ipairs(obstacles) do
        if insideObstacle(x,y,padding,obstacle) then return false end
    end
    return true
end

function CaravanArea.areaId(stop)
    return campId(stop)
end

function CaravanArea.stopGate(stop)
    stop=math.max(1,math.floor(tonumber(stop) or 1))
    local gate=authoredStopGates[stop]
    return gate and shallowCopy(gate) or nil
end

function CaravanArea.hasStopGate(stop)
    return CaravanArea.stopGate(stop)~=nil
end

function CaravanArea.definition(stop)
    return {
        id=campId(stop), baseId=CaravanArea.BASE_ID, stop=math.max(1,math.floor(tonumber(stop) or 1)),
        kind="safeVendorCamp", scene=CaravanArea.SCENE, name="The Rookery Caravan",
        width=CaravanArea.WIDTH, height=CaravanArea.HEIGHT, safe=true, scrolling=false,
        variantId=CaravanArea.VARIANT_ID, backgroundKey="crowCaravanCampsite",
        walkMask=CaravanArea.WALK_MASK,
        spawns={arrival=shallowCopy(arrivalSpawn)}, returnGate=shallowCopy(returnGate),
        merchants=merchantDefinitions, stalls=stalls, props=props, obstacles=obstacles,
    }
end

local function ensureCaravanRoot(data)
    if type(data)~="table" then return nil end
    data.crowCaravans=type(data.crowCaravans)=="table" and data.crowCaravans or {}
    local root=data.crowCaravans
    root.version=math.max(1,math.floor(tonumber(root.version) or 1))
    root.scheduledStops=type(root.scheduledStops)=="table" and root.scheduledStops or {}
    root.camps=type(root.camps)=="table" and root.camps or {}
    root.groupRelationshipId=type(root.groupRelationshipId)=="string" and root.groupRelationshipId or "crow-caravan"
    return root
end

function CaravanArea.ensure(data,stop,options)
    local root=ensureCaravanRoot(data)
    if not root then return nil end
    options=options or {}
    stop=math.max(1,math.floor(tonumber(stop) or tonumber(data.location) or 1))
    local id=campId(stop)
    local key=tostring(stop)
    local state=root.camps[key]
    if type(state)~="table" and type(options.camp)=="table" then
        state=options.camp
        root.camps[key]=state
    end
    -- Stock must be generated by game.crow_caravans before area state is
    -- attached. Creating a partial camp here would make ensureCamp mistake it
    -- for a completed, persistent stock roll.
    if type(state)~="table" then return nil,"camp-not-created" end
    local previousId=state.id
    state.id=id
    if root.activeCampId and (root.activeCampId==previousId or root.activeCampId==id) then root.activeCampId=id end
    state.stop=stop
    state.seed=math.floor(tonumber(state.seed) or tonumber(options.seed) or defaultSeed(stop))
    state.variantId=type(state.variantId)=="string" and state.variantId
        or (type(options.variantId)=="string" and options.variantId or CaravanArea.VARIANT_ID)
    state.rolled=state.rolled==true or options.rolled==true
    if options.present~=nil then state.present=options.present==true else state.present=state.present==true end
    state.discovered=state.discovered==true
    state.visited=state.visited==true
    -- The stock service owns state.merchants as an ordered array. Area-local
    -- actor state remains separate so neither module changes the other's data.
    state.actorStates=type(state.actorStates)=="table" and state.actorStates or {}
    state.purchaseHistory=type(state.purchaseHistory)=="table" and state.purchaseHistory or {}
    for _,definition in ipairs(merchantDefinitions) do
        local actor=state.actorStates[definition.id]
        if type(actor)~="table" then actor={}; state.actorStates[definition.id]=actor end
        actor.id=definition.id
        actor.name=definition.name
        actor.specialty=definition.specialty
    end
    if finite(options.returnX) then state.returnX=options.returnX end
    if finite(options.returnY) then state.returnY=options.returnY end
    if options.returnFacing~=nil then state.returnFacing=options.returnFacing end
    return state
end

local function actorFromDefinition(definition,index)
    return {
        id=definition.id, name=definition.name, file=definition.file,
        specialty=definition.specialty, x=definition.x, y=definition.y,
        homeX=definition.x, homeY=definition.y, radius=definition.radius,
        label=definition.label, facing=definition.intentX>=0 and 1 or -1,
        intentX=definition.intentX, intentY=definition.intentY,
        moving=false, action="idle", animationDistance=0, idlePhase=index*.83,
        safe=true, targetable=false,
    }
end

function CaravanArea.new(options)
    options=options or {}
    local data=options.data
    local stop=math.max(1,math.floor(tonumber(options.stop) or (data and tonumber(data.location)) or 1))
    local state,errorMessage
    if data then state,errorMessage=CaravanArea.ensure(data,stop,options)
    else
        state={id=campId(stop),stop=stop,seed=tonumber(options.seed) or defaultSeed(stop),
            variantId=options.variantId or CaravanArea.VARIANT_ID,actorStates={},purchaseHistory={}}
    end
    if not state then return nil,errorMessage end
    local actors={}
    for index,definition in ipairs(merchantDefinitions) do actors[index]=actorFromDefinition(definition,index) end
    return {
        id=campId(stop),baseId=CaravanArea.BASE_ID,scene=CaravanArea.SCENE,kind="safeVendorCamp",
        name="The Rookery Caravan",stop=stop,width=CaravanArea.WIDTH,height=CaravanArea.HEIGHT,
        safe=true,scrolling=false,state=state,data=data,actors=actors,clock=0,
    }
end

function CaravanArea.enter(data,stop,returnContext,options)
    returnContext=returnContext or {}
    options=shallowCopy(options)
    options.data=data
    options.stop=stop
    options.present=true
    options.rolled=true
    options.returnX=returnContext.x
    options.returnY=returnContext.y
    options.returnFacing=returnContext.facing
    local session,errorMessage=CaravanArea.new(options)
    if not session then return nil,errorMessage end
    session.state.discovered=true
    session.state.visited=true
    local root=ensureCaravanRoot(data)
    root.activeCampId=session.id
    return session,arrivalSpawn.x,arrivalSpawn.y
end

function CaravanArea.restore(data,options)
    local root=ensureCaravanRoot(data)
    local state
    if root and root.activeCampId then
        for _,candidate in pairs(root.camps) do
            if type(candidate)=="table" and candidate.id==root.activeCampId then state=candidate; break end
        end
    end
    if type(state)~="table" then return nil end
    options=shallowCopy(options)
    options.data=data
    options.stop=state.stop
    return CaravanArea.new(options)
end

function CaravanArea.returnPoint(session)
    local state=session and session.state
    if not state then return nil end
    return state.returnX,state.returnY,state.returnFacing
end

function CaravanArea.leave(data,session)
    local x,y,facing=CaravanArea.returnPoint(session)
    local root=ensureCaravanRoot(data)
    if root and (not session or root.activeCampId==session.id) then root.activeCampId=nil end
    return x,y,facing
end

function CaravanArea.savePosition(session,player)
    if not (session and session.state and player) then return false end
    if finite(player.x) then session.state.playerX=player.x end
    if finite(player.y) then session.state.playerY=player.y end
    if player.facing~=nil then session.state.playerFacing=player.facing end
    return true
end

function CaravanArea.spawn(session,spawnId)
    if spawnId=="saved" and session and session.state
        and finite(session.state.playerX) and finite(session.state.playerY) then
        return CaravanArea.clamp(session.state.playerX,session.state.playerY)
    end
    return arrivalSpawn.x,arrivalSpawn.y
end

function CaravanArea.isWalkable(x,y,footRadius)
    if not finite(x) or not finite(y) then return false end
    local mask=walkMask()
    if mask then
        local radius=math.max(0,tonumber(footRadius) or 6)
        if x<radius or y<radius or x>CaravanArea.WIDTH-radius or y>CaravanArea.HEIGHT-radius then return false end
        local mw,mh=mask:getDimensions()
        local function sample(px,py)
            local ix=math.max(0,math.min(mw-1,math.floor(px*mw/CaravanArea.WIDTH)))
            local iy=math.max(0,math.min(mh-1,math.floor(py*mh/CaravanArea.HEIGHT)))
            return select(1,mask:getPixel(ix,iy))>.5
        end
        -- Match stop masks. Painted pixels replace the old floor and prop shapes.
        return sample(x,y) and sample(x-radius,y) and sample(x+radius,y)
            and sample(x,y-radius) and sample(x,y+radius)
    end
    return rawWalkable(x,y,math.max(0,tonumber(footRadius) or 7))
end

function CaravanArea.clamp(x,y)
    local mask=walkMask()
    x=clampNumber(tonumber(x) or arrivalSpawn.x,mask and 6 or 42,mask and CaravanArea.WIDTH-6 or 918)
    y=clampNumber(tonumber(y) or arrivalSpawn.y,mask and 6 or 88,mask and CaravanArea.HEIGHT-6 or 690)
    if CaravanArea.isWalkable(x,y) then return x,y end
    for radius=6,520,6 do
        for step=0,47 do
            local angle=step/48*math.pi*2
            local nx,ny=x+math.cos(angle)*radius,y+math.sin(angle)*radius
            if CaravanArea.isWalkable(nx,ny) then return nx,ny end
        end
    end
    return arrivalSpawn.x,arrivalSpawn.y
end

function CaravanArea.move(oldX,oldY,newX,newY)
    if walkMask() then
        -- Substeps keep long frames from skipping narrow painted barriers.
        local steps=math.max(1,math.ceil(distance(oldX,oldY,newX,newY)/6))
        local dx,dy=(newX-oldX)/steps,(newY-oldY)/steps
        local x,y=oldX,oldY
        for _=1,steps do
            if CaravanArea.isWalkable(x+dx,y+dy) then x,y=x+dx,y+dy
            elseif CaravanArea.isWalkable(x+dx,y) then x=x+dx
            elseif CaravanArea.isWalkable(x,y+dy) then y=y+dy end
        end
        return x,y
    end
    if CaravanArea.isWalkable(newX,newY) then return newX,newY end
    if CaravanArea.isWalkable(newX,oldY) then return newX,oldY end
    if CaravanArea.isWalkable(oldX,newY) then return oldX,newY end
    return oldX,oldY
end

function CaravanArea.stopEntrance(stop,gate)
    gate=gate or CaravanArea.stopGate(stop)
    if type(gate)~="table" or not finite(gate.x) or not finite(gate.y) then return nil end
    return {
        id=campId(stop).."-entrance",kind=CaravanArea.KIND,action="enterCaravan",
        campId=campId(stop),stop=math.max(1,math.floor(tonumber(stop) or 1)),
        x=gate.x,y=gate.y,radius=tonumber(gate.radius) or 86,
        hoverRadius=tonumber(gate.hoverRadius) or 62,label=gate.label or "VISIT CROW CARAVAN",
    }
end

function CaravanArea.merchant(session,merchantId)
    for _,actor in ipairs(session and session.actors or {}) do
        if actor.id==merchantId then return actor end
    end
end

function CaravanArea.interactions(session)
    if not session then return {} end
    local result={shallowCopy(returnGate)}
    result[1].areaId=session.id
    for _,actor in ipairs(session.actors or {}) do
        result[#result+1]={
            id=actor.id,kind=CaravanArea.KIND,action="trade",merchantId=actor.id,
            x=actor.x,y=actor.y,radius=actor.radius,hoverRadius=66,label=actor.label,areaId=session.id,
        }
    end
    return result
end

function CaravanArea.interaction(session,player)
    if not (session and player and finite(player.x) and finite(player.y)) then return nil end
    local best,bestDistance
    for _,candidate in ipairs(CaravanArea.interactions(session)) do
        local current=distance(player.x,player.y,candidate.x,candidate.y)
        if current<=candidate.radius and (not bestDistance or current<bestDistance) then
            best,bestDistance=candidate,current
        end
    end
    return best
end

function CaravanArea.update(session,dt)
    if not session then return end
    dt=math.max(0,tonumber(dt) or 0)
    session.clock=(session.clock or 0)+dt
    -- Merchants remain at authored interaction anchors. Their directional
    -- intent selects a readable idle pose while the atlas supplies motion.
    for _,actor in ipairs(session.actors or {}) do
        actor.moving=false
        actor.action="idle"
        actor.idleClock=(actor.idleClock or 0)+dt
    end
end

local function graphicsFrom(context)
    return context and context.graphics or (love and love.graphics)
end

-- The public names are intentionally compact because this bundle crosses the
-- world-renderer boundary every frame. Longer aliases keep development builds
-- made against the original art filenames compatible with the same renderer.
local assetAliases = {
    background={"background"},
    wagonBody={"wagonBody"},
    wheel={"wheel","wagonWheel"},
    stallBody={"stallBody"},
    stallBreeze={"stallBreeze"},
    tent={"tent","patchedTent"},
    cargo={"cargo","cargoCluster"},
    banner={"banner","crowBanner"},
    campfire={"campfire"},
}

local function caravanAsset(assets,key)
    if type(assets)~="table" then return nil end
    for _,name in ipairs(assetAliases[key] or {key}) do
        if assets[name]~=nil then return assets[name] end
    end
    return nil
end

local function imageDimensions(image)
    if image==nil then return nil end
    local ok,width,height=pcall(function() return image:getDimensions() end)
    if not ok or not finite(width) or not finite(height) or width<=0 or height<=0 then return nil end
    return width,height
end

local function atlasReady(atlas,columns,rows)
    if type(atlas)~="table" then return false,0 end
    local frameCount=math.floor(tonumber(atlas.count) or 0)
    local width,height=imageDimensions(atlas.image)
    if not width or not height or frameCount~=columns*rows or not finite(atlas.w) or atlas.w<=0
        or not finite(atlas.h) or atlas.h<=0 or type(atlas.quads)~="table" then
        return false,frameCount
    end
    if width~=atlas.w*columns or height~=atlas.h*rows
        or (atlas.columns~=nil and atlas.columns~=columns)
        or (atlas.rows~=nil and atlas.rows~=rows) then return false,frameCount end
    for index=1,frameCount do
        local quad=atlas.quads[index]
        local ok,x,y,w,h=pcall(function() return quad:getViewport() end)
        if not ok or x~=((index-1)%columns)*atlas.w or y~=math.floor((index-1)/columns)*atlas.h
            or w~=atlas.w or h~=atlas.h then return false,frameCount end
        local textureOK,textureW,textureH=pcall(function() return quad:getTextureDimensions() end)
        if not textureOK or textureW~=width or textureH~=height then return false,frameCount end
    end
    return true,frameCount
end

local function stallAtlasReady(atlas)
    if type(atlas)~="table" then return false,0 end
    local frameCount=tonumber(atlas.count) or 0
    local width,height=imageDimensions(atlas.image)
    if frameCount~=4 or not width or type(atlas.frames)~="table" then return false,frameCount end
    for index=1,frameCount do
        local frame=atlas.frames[index]
        if type(frame)~="table" then return false,frameCount end
        for _,name in ipairs({"canopy","drape"}) do
            local part=frame[name]
            if type(part)~="table" or not finite(part.w) or part.w<=0 or not finite(part.h) or part.h<=0
                or type(part.leftPin)~="table" or type(part.rightPin)~="table" then return false,frameCount end
            local ok,x,y,w,h=pcall(function() return part.quad:getViewport() end)
            if not ok or not finite(x) or not finite(y) or not finite(w) or not finite(h)
                or x<0 or y<0 or math.abs(w-part.w)>.001 or math.abs(h-part.h)>.001
                or x+w>width+.001 or y+h>height+.001 then return false,frameCount end
            local textureOK,textureW,textureH=pcall(function() return part.quad:getTextureDimensions() end)
            if not textureOK or textureW~=width or textureH~=height then return false,frameCount end
            for _,pin in ipairs({part.leftPin,part.rightPin}) do
                if not finite(pin.x) or not finite(pin.y) or pin.x<0 or pin.y<0
                    or pin.x>part.w or pin.y>part.h then return false,frameCount end
            end
            if distance(part.leftPin.x,part.leftPin.y,part.rightPin.x,part.rightPin.y)<.001 then return false,frameCount end
        end
    end
    return true,frameCount
end

function CaravanArea.validateAssets(assets)
    local errors={}
    local loadedCount=0
    for _,key in ipairs({"background","wagonBody","wheel","stallBody","tent","cargo","banner"}) do
        local image=caravanAsset(assets,key)
        if imageDimensions(image) then loadedCount=loadedCount+1
        else errors[#errors+1]="missing or invalid caravan image: "..key end
    end

    local fireReady,frameCount=atlasReady(caravanAsset(assets,"campfire"),4,1)
    if fireReady then loadedCount=loadedCount+1
    else errors[#errors+1]="campfire must be a valid four-frame horizontal atlas" end

    local stallReady,stallFrameCount=stallAtlasReady(caravanAsset(assets,"stallBreeze"))
    if stallReady then loadedCount=loadedCount+1
    else errors[#errors+1]="stallBreeze must supply four authored canopy/drape sprite frames with attachment pins" end

    return {
        ready=#errors==0,errors=errors,requiredCount=9,loadedCount=loadedCount,
        campfireFrames=frameCount,stallBreezeFrames=stallFrameCount,activeBreezeFrames=3,curve="crow-caravan-art-v2",
    }
end

local function requireAssets(context)
    local assets=context and context.caravanAssets
    local validation=CaravanArea.validateAssets(assets)
    assert(validation.ready,"The Rookery Caravan requires its authored sprite assets: "..table.concat(validation.errors,"; "))
    return assets
end

local function reducedMotion(session,context)
    if context and context.reducedMotion~=nil then return context.reducedMotion==true end
    local settings=session and session.data and session.data.accessibility
    return type(settings)=="table" and settings.reducedMotion==true
end

local function drawSpriteImage(graphics,image,x,y,maxW,maxH,rotation,mirror)
    local width,height=imageDimensions(image)
    if not width then return false end
    local scale=math.min((maxW or width)/width,(maxH or height)/height)
    graphics.setColor(1,1,1,1)
    graphics.draw(image,x,y,rotation or 0,scale*(mirror and -1 or 1),scale,width/2,height)
    return true
end

local stallBreezeSequence={1,2,4,2}
local stallRig={
    width=1536,height=1024,
    canopy={leftPin={x=300,y=130},rightPin={x=1210,y=200}},
    drape={leftPin={x=595,y=656},rightPin={x=865,y=656}},
    caps={{x=270,y=56,w=64,h=76},{x=1180,y=120,w=75,h=81}},
}
local stallCapQuads=setmetatable({},{__mode="k"})

local function drawPinnedCloth(graphics,image,part,target)
    local sourceDX,sourceDY=part.rightPin.x-part.leftPin.x,part.rightPin.y-part.leftPin.y
    local targetDX,targetDY=target.rightPin.x-target.leftPin.x,target.rightPin.y-target.leftPin.y
    local scale=math.sqrt((targetDX*targetDX+targetDY*targetDY)/(sourceDX*sourceDX+sourceDY*sourceDY))
    local angle=math.atan2(targetDY,targetDX)-math.atan2(sourceDY,sourceDX)
    graphics.draw(image,part.quad,target.leftPin.x,target.leftPin.y,angle,scale,scale,part.leftPin.x,part.leftPin.y)
end

local function drawStallCaps(graphics,body,bodyW,bodyH)
    local quads=stallCapQuads[body]
    if not quads then
        quads={}
        for index,cap in ipairs(stallRig.caps) do
            quads[index]=graphics.newQuad(cap.x*bodyW/stallRig.width,cap.y*bodyH/stallRig.height,
                cap.w*bodyW/stallRig.width,cap.h*bodyH/stallRig.height,bodyW,bodyH)
        end
        stallCapQuads[body]=quads
    end
    for index,cap in ipairs(stallRig.caps) do
        graphics.draw(body,quads[index],cap.x,cap.y,0,stallRig.width/bodyW,stallRig.height/bodyH)
    end
end

-- Each independently packed cloth sprite maps its two authored ties onto the
-- same stationary body pins. A single similarity transform preserves its pixel
-- art proportions while guaranteeing that neither attachment drifts in a frame.
function CaravanArea.drawStall(assets,options)
    options=options or {}
    local graphics=graphicsFrom(options)
    if not graphics then return false end
    local body=caravanAsset(assets,"stallBody")
    local bodyW,bodyH=imageDimensions(body)
    assert(bodyW,"The Rookery Caravan requires the stationary stall body sprite")
    local atlas=caravanAsset(assets,"stallBreeze")
    assert(stallAtlasReady(atlas),"The Rookery Caravan requires the pinned stall breeze sprite atlas")
    local frame
    if options.frame then frame=clampNumber(math.floor(options.frame),1,atlas.count)
    elseif options.reducedMotion then frame=1
    else
        local clock=(tonumber(options.clock) or 0)+(tonumber(options.phase) or 0)
        frame=stallBreezeSequence[math.floor(clock*2)%#stallBreezeSequence+1]
    end
    local rig=stallRig
    local scale=math.min((options.maxW or rig.width)/rig.width,(options.maxH or rig.height)/rig.height)
    local mirror=options.mirror and -1 or 1
    local x,y=tonumber(options.x) or 0,tonumber(options.y) or 0
    graphics.setColor(1,1,1,1)
    graphics.push()
    graphics.translate(x,y)
    graphics.scale(scale*mirror,scale)
    graphics.translate(-rig.width/2,-rig.height)
    graphics.draw(body,0,0,0,rig.width/bodyW,rig.height/bodyH)
    drawPinnedCloth(graphics,atlas.image,atlas.frames[frame].canopy,rig.canopy)
    drawPinnedCloth(graphics,atlas.image,atlas.frames[frame].drape,rig.drape)
    drawStallCaps(graphics,body,bodyW,bodyH)
    graphics.pop()
    return true,frame
end

local function drawSpriteStalls(graphics,assets,session,context)
    local clock=tonumber(session and session.clock) or 0
    local still=reducedMotion(session,context)
    for index,stall in ipairs(stalls) do
        CaravanArea.drawStall(assets,{
            graphics=graphics,x=stall.x+stall.w/2,y=stall.y+stall.h,
            maxW=stall.w+20,maxH=stall.h+34,clock=clock,phase=(index-1)*.6,
            reducedMotion=still,mirror=stall.id=="arms-stall",
        })
    end
end

-- Authoring coordinates are independent of texture resolution: mobile builds
-- may resize the PNGs, but the axle sockets and wheel hubs must stay attached.
local wagonRig={
    bodyWidth=1536,bodyHeight=1024,originX=768,originY=1024,
    axles={{x=462,y=828},{x=1175,y=815}},
    wheelWidth=1254,wheelHeight=1254,wheelHubX=625,wheelHubY=617,
    wheelVisibleDiameter=1100,mountedWheelDiameter=300,
}

local function drawSpriteWagons(graphics,assets)
    local body=caravanAsset(assets,"wagonBody")
    local wheel=caravanAsset(assets,"wheel")
    local bodyW,bodyH=imageDimensions(body)
    local wheelW,wheelH=imageDimensions(wheel)
    assert(bodyW and wheelW,"The Rookery Caravan requires both wagon body and wheel sprites")
    local rig=wagonRig
    local scale=math.min(240/rig.bodyWidth,150/rig.bodyHeight)
    local wheelScale=rig.mountedWheelDiameter/rig.wheelVisibleDiameter
    for _,x in ipairs({245,715}) do
        graphics.push()
        graphics.translate(x,226)
        graphics.scale(scale,scale)
        graphics.setColor(1,1,1,1)
        graphics.draw(body,-rig.originX,-rig.originY,0,rig.bodyWidth/bodyW,rig.bodyHeight/bodyH)
        -- Both visible axle sockets belong to the near side; their wheels must
        -- cover the sockets and lower chassis, rather than sit behind the body.
        for _,axle in ipairs(rig.axles) do
            graphics.draw(wheel,axle.x-rig.originX,axle.y-rig.originY,0,
                wheelScale*rig.wheelWidth/wheelW,wheelScale*rig.wheelHeight/wheelH,
                rig.wheelHubX*wheelW/rig.wheelWidth,rig.wheelHubY*wheelH/rig.wheelHeight)
        end
        graphics.pop()
    end
end

local function drawSpriteProps(graphics,session,context,foreground)
    local assets=context.caravanAssets
    if foreground then
        local atlas=caravanAsset(assets,"campfire")
        local fireReady,frameCount=atlasReady(atlas,4,1)
        assert(fireReady,"The Rookery Caravan requires the campfire sprite atlas")
        local fire=props[#props]
        local frame=reducedMotion(session,context) and 1 or math.floor((tonumber(session and session.clock) or 0)*8)%frameCount+1
        local scale=math.min(fire.maxW/atlas.w,fire.maxH/atlas.h)
        graphics.setColor(1,1,1,1)
        graphics.draw(atlas.image,atlas.quads[frame],fire.x,fire.y,0,scale,scale,atlas.w/2,atlas.h)
        return
    end

    local tent=caravanAsset(assets,"tent")
    assert(imageDimensions(tent),"The Rookery Caravan requires the tent sprite")
    drawSpriteImage(graphics,tent,props[1].x,props[1].y,props[1].maxW,props[1].maxH,0,false)
    drawSpriteImage(graphics,tent,props[2].x,props[2].y,props[2].maxW,props[2].maxH,0,true)

    local cargo=caravanAsset(assets,"cargo")
    assert(imageDimensions(cargo),"The Rookery Caravan requires the cargo sprite")
    -- Each cluster occupies the same combined footprint as the original
    -- crate-and-barrel pair, so paths and interaction spacing do not move.
    drawSpriteImage(graphics,cargo,211,438,100,78,0,false)
    drawSpriteImage(graphics,cargo,750,440,100,78,0,true)
end

function CaravanArea.drawGround(session,context)
    local graphics=graphicsFrom(context)
    if not graphics then return false end
    context=context or {}
    local assets=requireAssets(context)
    local background=caravanAsset(assets,"background")
    local width,height=imageDimensions(background)
    graphics.setColor(1,1,1,1)
    graphics.draw(background,0,0,0,CaravanArea.WIDTH/width,CaravanArea.HEIGHT/height)
    drawSpriteStalls(graphics,assets,session,context)
    drawSpriteWagons(graphics,assets)
    drawSpriteProps(graphics,session,context,false)
    return true
end

function CaravanArea.drawActors(session,context)
    local graphics=graphicsFrom(context)
    if not (graphics and session) then return false end
    context=context or {}
    for _,actor in ipairs(session.actors or {}) do
        local drawn=false
        if context.drawAnimatedCharacter then
            drawn=context.drawAnimatedCharacter(actor.file,actor.action,actor.x,actor.y+34,82,104,actor.facing,
                (session.clock or 0)+(actor.idlePhase or 0),session.clock or 0,actor)==true
        end
        if not drawn then
            local image=context.characterImages and context.characterImages[actor.file]
            local width,height=imageDimensions(image)
            assert(width,"The Rookery Caravan requires the merchant sprite: "..actor.file)
            local scale=math.min(82/width,104/height)
            graphics.setColor(1,1,1,1); graphics.draw(image,actor.x,actor.y+34,0,scale*-actor.facing,scale,width/2,height)
        end
        graphics.setColor(1,.88,.58,1)
        graphics.printf(actor.name,actor.x-90,actor.y+45,180,"center",0,.66,.66)
    end
    return true
end

function CaravanArea.drawForeground(session,context)
    local graphics=graphicsFrom(context)
    if not graphics then return false end
    drawSpriteProps(graphics,session,context or {},true)
    return true
end

function CaravanArea.draw(session,context)
    context=context or {}
    if not CaravanArea.drawGround(session,context) then return false end
    if context.drawUnderlay then context.drawUnderlay(session) end
    if context.drawDroppedItems then context.drawDroppedItems() end
    CaravanArea.drawActors(session,context)
    CaravanArea.drawForeground(session,context)
    if context.drawPlayer then context.drawPlayer() end
    if context.drawOverlay then context.drawOverlay(session) end
    local graphics=graphicsFrom(context)
    if graphics then
        graphics.setColor(.04,.025,.02,.82); graphics.rectangle("fill",18,16,330,52,8,8)
        graphics.setColor(1,.88,.58,1); graphics.print("THE ROOKERY CARAVAN",34,27)
    end
    return true
end

function CaravanArea.audit()
    local errors={}
    local seen={}
    if CaravanArea.WIDTH~=960 or CaravanArea.HEIGHT~=720 then errors[#errors+1]="campsite must remain one logical screen" end
    if CaravanArea.SAFE~=true then errors[#errors+1]="campsite safety flag is missing" end
    local gateCount=0
    for stop,gate in pairs(authoredStopGates) do
        gateCount=gateCount+1
        if stop<7 or stop>48 or not finite(gate.x) or not finite(gate.y) then errors[#errors+1]="invalid authored stop gate: "..tostring(stop) end
    end
    if gateCount~=18 then errors[#errors+1]="expected 18 vetted caravan host gates" end
    if not CaravanArea.isWalkable(arrivalSpawn.x,arrivalSpawn.y) then errors[#errors+1]="arrival spawn is blocked" end
    if not CaravanArea.isWalkable(returnGate.x,returnGate.y) then errors[#errors+1]="return gate is blocked" end
    for _,merchant in ipairs(merchantDefinitions) do
        if seen[merchant.id] then errors[#errors+1]="duplicate merchant id "..merchant.id end
        seen[merchant.id]=true
        if not CaravanArea.isWalkable(merchant.x,merchant.y) then errors[#errors+1]="merchant anchor blocked: "..merchant.id end
    end
    local session=CaravanArea.new({stop=12})
    if #CaravanArea.interactions(session)~=4 then errors[#errors+1]="expected three merchants and one return interaction" end
    return {
        ready=#errors==0,errors=errors,safe=CaravanArea.SAFE,width=CaravanArea.WIDTH,height=CaravanArea.HEIGHT,
        merchantCount=#merchantDefinitions,interactionCount=#CaravanArea.interactions(session),gateCount=gateCount,curve="crow-caravan-area-v1",
    }
end

CaravanArea.merchantDefinitions=merchantDefinitions
CaravanArea.stalls=stalls
CaravanArea.props=props
CaravanArea.obstacles=obstacles
CaravanArea.returnGate=returnGate
CaravanArea.authoredStopGates=authoredStopGates
CaravanArea.wagonRig=wagonRig
CaravanArea.stallRig=stallRig
return CaravanArea
