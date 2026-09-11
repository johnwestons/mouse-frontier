local Animation = require("game.train_animation")

local trackQuadCache=setmetatable({},{__mode="k"})

local Train = {
    railY=670,

    -- The flat side-elevation track keeps one fixed world scale at every
    -- aspect ratio. More tiles are drawn in fullscreen; tie spacing never
    -- stretches when the window changes shape.
    trackVisibleTop=230,
    trackRailSourceY=354,
    trackScale=96/181,
    trackEdgeCrop=4,
    trackSourceWidth=2172,
    trackSourceHeight=724,

    carVisibleLeft=10,
    carVisibleRight=630,
    carWheelY=356,
    carBogieCenters={154.5,483.5},
    carBogieAtlasOriginX=270.5,
    carBogieStrongBottom=448,
    carBogieScale=32/99,
    carWheelRadius=22.5,

    -- Source-space anchors are measured from the invariant generated body.
    -- A future asset swap now fails the asset contract instead of silently
    -- moving the consist.
    engineBodyVisibleLeft=61,
    engineBodyCouplerX=1864,
    engineBodyContactY=730,
    engineTargetWidth=546,
    engineBaseCarX=445,
    engineBaseX=8, -- legacy raw-origin reference retained for save migration tests
    -- The two green reference passes total a 138 world-pixel engine-only
    -- shift. The car and all interior object anchors remain unchanged.
    engineNoseBaseX=-99,
    engineDriverSourceCentersX={725,950,1175},
    engineDriverSourceY=622,
    engineDriverSourceRadius=108,
    engineCrankRadius=11,
    engineGuideY=632,
    engineRodLength=122,
    engineRunningGearLargeRadius=258,
    engineRunningGearSmallRadius=167,
    engineWheelSpritePinAngle=-.65,
    engineCouplingRodThicknessScale=.55,
    engineConnectingRodThicknessScale=.42,
    engineJointPinScale=.065,
    enginePilotSourceCentersX={288,534},
    enginePilotSourceY=683,
    enginePilotSourceRadius=50,
    engineTenderSourceCentersX={1580,1762},
    engineTenderSourceY=683,
    engineTenderSourceRadius=50,

    -- Only the smoke strip of the retired whole-engine frames is used. These
    -- anchors preserve the approved chimney position without reintroducing
    -- boiler/cab shimmer.
    legacySmokeVisibleLeft={80,82,82},
    legacySmokeCouplerX={1522,1527,1532},
    legacySmokeWheelY={740,745,742},
}

local function nearlyEqual(a,b,tolerance)
    return math.abs(a-b)<=(tolerance or 1e-6)
end

function Train.carScale(car,image)
    if not image then return 1 end
    return car.w/(Train.carVisibleRight-Train.carVisibleLeft)
end

function Train.carTransform(car,image)
    local scale=Train.carScale(car,image)
    return car.x-Train.carVisibleLeft*scale,Train.railY-Train.carWheelY*scale,scale
end

function Train.floorSurfaceBounds(car,image)
    local x,y,scale=Train.carTransform(car,image)
    return x+84*scale,x+556*scale,y+244*scale,y+286*scale
end

function Train.characterBounds(car,image,footOffset)
    local left,right,top,bottom=Train.floorSurfaceBounds(car,image)
    local padding=14
    footOffset=footOffset or 30
    return left+padding,right-padding,top-footOffset,bottom-footOffset
end

function Train.clampCharacterToFloor(car,image,characterX,characterY,footOffset)
    local drawX,drawY,scale=Train.carTransform(car,image)
    footOffset=footOffset or 30
    local contactY=math.max(drawY+244*scale,math.min(drawY+286*scale,characterY+footOffset))
    local depth=(contactY-(drawY+244*scale))/(42*scale)
    local sourceLeft=116+(84-116)*depth
    local sourceRight=524+(556-524)*depth
    local sidePadding=14
    local left=drawX+sourceLeft*scale+sidePadding
    local right=drawX+sourceRight*scale-sidePadding
    return math.max(left,math.min(right,characterX)),contactY-footOffset
end

function Train.floorBounds(car,image)
    return Train.floorSurfaceBounds(car,image)
end

function Train.locomotiveLayout(car)
    local carX=car and car.x or Train.engineBaseCarX
    local nose=Train.engineNoseBaseX+(carX-Train.engineBaseCarX)
    local scale=Train.engineTargetWidth/(Train.engineBodyCouplerX-Train.engineBodyVisibleLeft)
    local bodyX=nose-Train.engineBodyVisibleLeft*scale
    local bodyY=Train.railY-Train.engineBodyContactY*scale
    local centers={}
    for index,sourceX in ipairs(Train.engineDriverSourceCentersX) do
        centers[index]={x=bodyX+sourceX*scale,y=bodyY+Train.engineDriverSourceY*scale}
    end
    local tenderCenters={}
    for index,sourceX in ipairs(Train.engineTenderSourceCentersX) do
        tenderCenters[index]={x=bodyX+sourceX*scale,y=bodyY+Train.engineTenderSourceY*scale}
    end
    local pilotCenters={}
    for index,sourceX in ipairs(Train.enginePilotSourceCentersX) do
        pilotCenters[index]={x=bodyX+sourceX*scale,y=bodyY+Train.enginePilotSourceY*scale}
    end
    return {
        nose=nose,coupler=nose+Train.engineTargetWidth,bodyX=bodyX,bodyY=bodyY,
        bodyScale=scale,driverCenters=centers,driverRadius=Train.engineDriverSourceRadius*scale,
        pilotCenters=pilotCenters,pilotRadius=Train.enginePilotSourceRadius*scale,
        tenderCenters=tenderCenters,tenderRadius=Train.engineTenderSourceRadius*scale,
        wheelContactY=Train.railY,
        carFront=carX,overlap=nose+Train.engineTargetWidth-carX,
    }
end

local function viewportSpan(width,height,windowWidth,windowHeight)
    local viewportScale=math.min(windowWidth/width,windowHeight/height)
    local visibleWidth=windowWidth/viewportScale
    return -(visibleWidth-width)/2,width+(visibleWidth-width)/2,viewportScale
end

function Train.trackDrawPlan(width,scrollOffset,windowWidth,windowHeight)
    width=width or 960
    windowWidth=windowWidth or width
    windowHeight=windowHeight or 720
    local visibleLeft,visibleRight=viewportSpan(width,720,windowWidth,windowHeight)
    visibleLeft,visibleRight=visibleLeft-12,visibleRight+12
    local sourceWidth=Train.trackSourceWidth-Train.trackEdgeCrop*2
    local tileWidth=Train.trackSourceWidth*Train.trackScale
    local period=tileWidth*2
    scrollOffset=scrollOffset or 0
    local phase=scrollOffset%period
    local firstIndex=math.floor((visibleLeft-phase)/tileWidth)-1
    local lastIndex=math.ceil((visibleRight-phase)/tileWidth)+1
    local tiles={}
    for index=firstIndex,lastIndex do
        tiles[#tiles+1]={x=phase+index*tileWidth,mirrored=index%2~=0,index=index}
    end
    return {
        visibleLeft=visibleLeft,visibleRight=visibleRight,scale=Train.trackScale,
        sourceWidth=sourceWidth,tileWidth=tileWidth,drawScaleX=tileWidth/sourceWidth,
        period=period,phase=phase,
        scrollOffset=scrollOffset,
        tiles=tiles,trackTop=Train.railY-Train.trackRailSourceY*Train.trackScale,
    }
end

local function baseTrackQuad(track)
    local cached=trackQuadCache[track]
    if cached then return cached end
    local width,height=track:getDimensions()
    local edgeCrop=Train.trackEdgeCrop*width/Train.trackSourceWidth
    cached=love.graphics.newQuad(edgeCrop,0,width-edgeCrop*2,height,width,height)
    trackQuadCache[track]=cached
    return cached
end

function Train.drawTracks(trackAssets,width,scrollOffset)
    local track=type(trackAssets)=="table" and trackAssets.base or trackAssets
    if not track then return false end
    local windowWidth,windowHeight=love.graphics.getDimensions()
    local plan=Train.trackDrawPlan(width,scrollOffset,windowWidth,windowHeight)
    local quad=baseTrackQuad(track)
    -- Mobile packing shrinks the base and the four-frame ballast atlas by
    -- different amounts. Keep their authored anchors in world space while
    -- converting each texture's actual pixels back to that shared canvas.
    local imageWidth,imageHeight=track:getDimensions()
    local baseScaleX=plan.drawScaleX*Train.trackSourceWidth/imageWidth
    local baseScaleY=plan.scale*Train.trackSourceHeight/imageHeight
    love.graphics.push("all")
    love.graphics.setColor(1,1,1)
    for _,tile in ipairs(plan.tiles) do
        if tile.mirrored then
            love.graphics.draw(track,quad,tile.x+plan.tileWidth,plan.trackTop,0,-baseScaleX,baseScaleY)
        else
            love.graphics.draw(track,quad,tile.x,plan.trackTop,0,baseScaleX,baseScaleY)
        end
    end

    local ballastFrames=type(trackAssets)=="table" and trackAssets.ballastFrames or nil
    if ballastFrames and ballastFrames.image and ballastFrames.quads then
        local motion=Animation.trackPlan(scrollOffset or 0,{
            origin=0,scale=plan.scale,scrollFactor=1,tileWidth=plan.sourceWidth,
            vibrationStep=6,vibrationAmplitude=0,layerIds={"ballast-a","ballast-b"},
        })
        local frame=((motion.vibrationFrame-1)%ballastFrames.count)+1
        local ballastQuad=ballastFrames.quads[frame]
        local _,_,frameWidth,frameHeight=ballastQuad:getViewport()
        local ballastScaleX=plan.drawScaleX*Train.trackSourceWidth/frameWidth
        local ballastScaleY=plan.scale*Train.trackSourceHeight/frameHeight
        love.graphics.setColor(1,1,1)
        for _,tile in ipairs(plan.tiles) do
            if tile.mirrored then
                love.graphics.draw(ballastFrames.image,ballastQuad,
                    tile.x+plan.tileWidth,plan.trackTop,0,-ballastScaleX,ballastScaleY)
            else
                love.graphics.draw(ballastFrames.image,ballastQuad,
                    tile.x,plan.trackTop,0,ballastScaleX,ballastScaleY)
            end
        end
    end
    love.graphics.pop()
    return true
end

local function atan2(y,x)
    if math.atan2 then return math.atan2(y,x) end
    if x>0 then return math.atan(y/x) end
    if x<0 then return y>=0 and math.atan(y/x)+math.pi or math.atan(y/x)-math.pi end
    if y>0 then return math.pi/2 end
    if y<0 then return -math.pi/2 end
    return 0
end

local function drawGearComponent(atlas,component,x,y,rotation,scaleX,scaleY)
    if not atlas or not atlas.image or not component or not component.quad then return false end
    scaleX=scaleX or 1
    scaleY=scaleY or scaleX
    love.graphics.draw(atlas.image,component.quad,x,y,rotation or 0,scaleX,scaleY,
        component.originX,component.originY)
    return true
end

local function drawGearBetween(atlas,component,fromPoint,toPoint,sourceAngle,alpha,thicknessScale)
    local dx,dy=toPoint.x-fromPoint.x,toPoint.y-fromPoint.y
    local length=math.sqrt(dx*dx+dy*dy)
    if length<=0 or not component or not component.length then return false end
    love.graphics.setColor(1,1,1,alpha or 1)
    local lengthScale=length/component.length
    return drawGearComponent(atlas,component,fromPoint.x,fromPoint.y,
        atan2(dy,dx)-(sourceAngle or 0),lengthScale,
        lengthScale*(thicknessScale or 1))
end

local function drawSmoke(smokeFrames,car,clock)
    if not smokeFrames or #smokeFrames==0 then return end
    local index=math.floor((clock or 0)*3)%#smokeFrames+1
    local frame=smokeFrames[index]
    if not frame or not frame.image or not frame.quad then return end
    local visibleLeft=Train.legacySmokeVisibleLeft[index]
    local coupler=Train.legacySmokeCouplerX[index]
    local wheelY=Train.legacySmokeWheelY[index]
    local scale=Train.engineTargetWidth/(coupler-visibleLeft)
    local x=Train.locomotiveLayout(car).nose-31
    love.graphics.setColor(1,1,1)
    love.graphics.draw(frame.image,frame.quad,x,Train.railY-wheelY*scale,0,scale,scale)
end

local function drawLegacyLocomotive(image,car)
    if not image then return end
    local scale=Train.engineTargetWidth/(1537-80)
    local x=Train.locomotiveLayout(car).nose-80*scale
    love.graphics.setColor(1,1,1)
    love.graphics.draw(image,x,Train.railY-745*scale,0,scale,scale)
end

function Train.drawLocomotive(assets,car,distance,smokeClock)
    if not assets then return false end
    if type(assets)~="table" or not assets.body or not assets.runningGear then
        drawLegacyLocomotive(type(assets)=="table" and assets.fallback or assets,car)
        return true
    end
    local layout=Train.locomotiveLayout(car)
    local spec={
        driverCenters=layout.driverCenters,wheelRadius=layout.driverRadius,
        crankRadius=Train.engineCrankRadius,mainDriverIndex=2,
        guideY=Train.engineGuideY,rodLength=Train.engineRodLength,
        crossheadSide=-1,angleOffset=Train.engineWheelSpritePinAngle,
    }
    local near=Animation.locomotiveGeometry(distance or 0,spec)
    local far=Animation.locomotiveGeometry((distance or 0)+layout.driverRadius*math.pi/2,spec)
    local gear=assets.runningGear
    local wheelScale=layout.driverRadius/Train.engineRunningGearLargeRadius
    local wheelRotation=Train.engineWheelSpritePinAngle-near.angle

    love.graphics.push("all")
    drawSmoke(assets.smokeFrames,car,smokeClock)
    love.graphics.setShader(assets.generatedShader)
    love.graphics.setColor(1,1,1)
    love.graphics.draw(assets.body,layout.bodyX,layout.bodyY,0,layout.bodyScale,layout.bodyScale)
    love.graphics.setShader()

    -- The far-side gear is quartered by 90 degrees and sits behind the drivers.
    love.graphics.setShader(assets.generatedShader)
    for index=1,2 do
        drawGearBetween(gear,gear.couplingRod,far.drivers[index].crankPin,
            far.drivers[index+1].crankPin,0,.34,Train.engineCouplingRodThicknessScale)
    end
    for _,driver in ipairs(near.drivers) do
        love.graphics.setColor(1,1,1)
        drawGearComponent(gear,gear.largeWheel,driver.center.x,driver.center.y,
            wheelRotation,wheelScale)
    end
    local tenderScale=layout.tenderRadius/Train.engineRunningGearSmallRadius
    local pilotScale=layout.pilotRadius/Train.engineRunningGearSmallRadius
    for _,center in ipairs(layout.pilotCenters) do
        love.graphics.setColor(1,1,1)
        drawGearComponent(gear,gear.smallWheel,center.x,center.y,-near.angle,pilotScale)
    end
    for _,center in ipairs(layout.tenderCenters) do
        love.graphics.setColor(1,1,1)
        drawGearComponent(gear,gear.smallWheel,center.x,center.y,-near.angle,tenderScale)
    end
    for index=1,2 do
        drawGearBetween(gear,gear.couplingRod,near.drivers[index].crankPin,
            near.drivers[index+1].crankPin,0,1,Train.engineCouplingRodThicknessScale)
    end
    drawGearBetween(gear,gear.connectingRod,near.connectingRod.to,near.crosshead,math.pi,1,
        Train.engineConnectingRodThicknessScale)
    for _,driver in ipairs(near.drivers) do
        love.graphics.setColor(1,1,1)
        drawGearComponent(gear,gear.jointPin,driver.crankPin.x,driver.crankPin.y,0,
            Train.engineJointPinScale)
    end
    love.graphics.setShader()
    love.graphics.pop()
    return true
end

function Train.drawConsistConnection(car,runningGear,generatedShader)
    if not runningGear then return false end
    local layout=Train.locomotiveLayout(car)
    local y=Train.railY-22
    local enginePin={x=layout.coupler-12,y=y}
    local carPin={x=car.x+8,y=y}
    love.graphics.push("all")
    love.graphics.setShader(generatedShader)
    drawGearBetween(runningGear,runningGear.couplingRod,enginePin,carPin,0,1,.8)
    love.graphics.setColor(1,1,1)
    drawGearComponent(runningGear,runningGear.jointPin,enginePin.x,enginePin.y,0,.045)
    drawGearComponent(runningGear,runningGear.jointPin,carPin.x,carPin.y,0,.045)
    love.graphics.pop()
    return true
end

function Train.drawCarImage(image,car)
    if not image then return false end
    local x,y,scale=Train.carTransform(car,image)
    love.graphics.setColor(1,1,1)
    love.graphics.draw(image,x,y,0,scale,scale)
    return true
end

function Train.drawCarRunningGear(atlas,car,distance,generatedShader)
    if not atlas or not atlas.image or not atlas.quads or #atlas.quads==0 then return false end
    local phase=Animation.carPhase(distance or 0,Train.carWheelRadius)
    local frame=math.floor(phase.normalized*atlas.count)%atlas.count+1
    local quad=atlas.quads[frame]
    local carScale=car.w/(Train.carVisibleRight-Train.carVisibleLeft)
    local scale=Train.carBogieScale*carScale
    love.graphics.push("all")
    -- Cover only the retired wheel faces. A former rectangular underlay was
    -- visible around the transparent bogie sprite in fullscreen.
    love.graphics.setColor(.035,.03,.028,.98)
    for _,sourceCenter in ipairs(Train.carBogieCenters) do
        local centerX=car.x+(sourceCenter-Train.carVisibleLeft)*carScale
        for _,wheelOffset in ipairs({-54.5,54.5}) do
            love.graphics.circle("fill",centerX+wheelOffset*carScale,
                Train.railY-Train.carWheelRadius*carScale,Train.carWheelRadius*carScale)
        end
    end
    love.graphics.setShader(generatedShader)
    love.graphics.setColor(1,1,1)
    for _,sourceCenter in ipairs(Train.carBogieCenters) do
        local centerX=car.x+(sourceCenter-Train.carVisibleLeft)*carScale
        love.graphics.draw(atlas.image,quad,centerX,Train.railY,0,scale,scale,
            Train.carBogieAtlasOriginX,Train.carBogieStrongBottom)
    end
    love.graphics.pop()
    return true
end

function Train.consistLayout(width,count,options)
    options=options or {}
    count=math.max(1,math.floor(count or 1))
    local left,right,gap,height,y
    if options.mobile then left,right,gap,height,y=250,(width or 960)-25,6,58,140
    else left,right,gap,height,y=430,730,4,28,154 end
    local cellWidth=math.min(options.mobile and 76 or 48,math.floor((right-left-gap*(count-1))/count))
    local total=cellWidth*count+gap*(count-1)
    local start=right-total
    local result={}
    for index=1,count do result[index]={x=start+(index-1)*(cellWidth+gap),y=y,w=cellWidth,h=height,index=index} end
    return result
end

function Train.layoutAudit(car,width,height)
    width,height=width or 960,height or 720
    local engine=Train.locomotiveLayout(car)
    local sizes={{960,720},{1920,1080},{2560,1080},{3440,1440},{1280,1024},{2400,1080}}
    local anchorsStable=true
    local coverageReady=true
    local layouts={}
    for _,size in ipairs(sizes) do
        local left,right,scale=viewportSpan(width,height,size[1],size[2])
        local trackPlan=Train.trackDrawPlan(width,0,size[1],size[2])
        local covers=trackPlan.tiles[1].x<=trackPlan.visibleLeft
            and trackPlan.tiles[#trackPlan.tiles].x+trackPlan.tileWidth>=trackPlan.visibleRight
        anchorsStable=anchorsStable and nearlyEqual(engine.nose,-115) and nearlyEqual(engine.coupler,431)
            and nearlyEqual(engine.carFront,429) and nearlyEqual(engine.wheelContactY,Train.railY)
        coverageReady=coverageReady and covers
        layouts[#layouts+1]={windowWidth=size[1],windowHeight=size[2],visibleLeft=left,
            visibleRight=right,scale=scale,trackTiles=#trackPlan.tiles,covers=covers}
    end
    return {ready=anchorsStable and coverageReady,count=#layouts,layouts=layouts,
        anchorsStable=anchorsStable,coverageReady=coverageReady,curve="train-layout-matrix-v1"}
end

function Train.animationAudit()
    return Animation.audit()
end

function Train.audit(car,width)
    width=width or 960
    local engine=Train.locomotiveLayout(car)
    local carRight=car.x+car.w
    local tabs=Train.consistLayout(width,7)
    local interactiveRight=car.x+405
    local tabsFit=#tabs==7 and tabs[1].x>=0 and tabs[#tabs].x+tabs[#tabs].w<=width
    local floorLeft,floorRight=Train.characterBounds(car,nil,30)
    local motion=Train.animationAudit()
    local matrix=Train.layoutAudit(car,width,720)
    local consistCenter=(engine.nose+carRight)/2
    local centerError=math.abs(consistCenter-width/2)
    local aligned=nearlyEqual(engine.nose,-115) and nearlyEqual(engine.coupler,431)
        and nearlyEqual(engine.overlap,2) and nearlyEqual(centerError,13)
        and interactiveRight<=width
        and floorLeft>=car.x and floorRight<=carRight
    return {
        ready=aligned and tabsFit and motion.ready and matrix.ready,
        engineLeft=engine.nose,engineRight=engine.coupler,engineWidth=Train.engineTargetWidth,
        frontWheelCount=#engine.pilotCenters,
        couplingRodThicknessScale=Train.engineCouplingRodThicknessScale,
        connectingRodThicknessScale=Train.engineConnectingRodThicknessScale,
        carFront=car.x,carRight=carRight,couplerOverlap=engine.overlap,
        croppedRight=math.max(0,carRight-width),croppedLeft=math.max(0,-engine.nose),
        consistCenter=consistCenter,centerError=centerError,
        tabs=#tabs,tabsFit=tabsFit,aligned=aligned,
        wheelContactY=engine.wheelContactY,railY=Train.railY,
        animationReady=motion.ready,animationCurve=motion.curve,phaseCount=motion.phaseCount,
        driverCount=motion.driverCount,maxMechanicalError=motion.maxError,
        trackLayerCount=motion.trackLayerCount,trackPriorityAlternates=motion.trackPriorityAlternates,
        ballastMode="anchored-four-frame-pockets",ballastFrameCount=4,
        ballastAnchored=true,connectionMode="sprite-atlas",
        layoutMatrixReady=matrix.ready,layoutCount=matrix.count,trackCoverage=matrix.coverageReady,
        transitionDistance=width,curve="train-presentation-v7",
    }
end

return Train
