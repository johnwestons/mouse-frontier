local WorldView=require("game.world_view")
local CharacterMotion=require("game.character_motion")
local CharacterAnimation=require("game.character_animation")
local Scene={}
local WindowScene=require("game.window_scene")

local ROOT="assets/sprites/quests/last-stand/runtime/"
local PATHS={
    backyard=ROOT.."friendly-house-backyard-shell.png",
    interior=ROOT.."friendly-house-interior-shell.png",
    otterWalk=ROOT.."otter-scout-approach-walk.png",
    otter=ROOT.."otter-scout-support-action-atlas.png",
    fox=ROOT.."guard-fox-rifle-action-atlas.png",
    gecko=ROOT.."gecko-ranger-pistol-action-atlas.png",
}

local images={}
local quads={}

local function image(path)
    if images[path]~=nil then return images[path] or nil end
    local ok,result=pcall(love.graphics.newImage,path)
    if ok and result then
        result:setFilter("linear","linear")
        images[path]=result
    else
        images[path]=false
    end
    return images[path] or nil
end

local function atlasQuad(path,frame,cellWidth,cellHeight,columns)
    local key=table.concat({path,frame,cellWidth,cellHeight,columns},":")
    if quads[key] then return quads[key] end
    local source=image(path)
    if not source then return nil end
    quads[key]=love.graphics.newQuad(
        (frame%columns)*cellWidth,
        math.floor(frame/columns)*cellHeight,
        cellWidth,
        cellHeight,
        source:getDimensions()
    )
    return quads[key]
end

local function drawAtlas(path,frame,x,y,scale,cellWidth,cellHeight,columns,flip)
    local source=image(path)
    local frameQuad=source and atlasQuad(path,frame,cellWidth,cellHeight,columns)
    if not frameQuad then return false end
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(source,frameQuad,x,y,0,flip and -scale or scale,scale,cellWidth/2,cellHeight-12)
    return true
end

function Scene.new(mode,quest)
    local scene={
        mode=mode,
        quest=quest or {},
        clock=0,
        defenders={
            fox={frame=0,timer=1.3,phase="idle"},
            gecko={frame=0,timer=2.6,phase="idle"},
        },
        player={
            x=480,
            y=mode=="interior" and 590 or 610,
            facing=1,
        },
    }
    CharacterMotion.resetActor(scene.player)
    return scene
end

function Scene.change(scene,mode)
    scene.mode=mode
    scene.moveTarget=nil
    scene.player.x=480
    scene.player.y=mode=="interior" and 590 or 610
    CharacterMotion.resetActor(scene.player)
end

local function movementAxis(negative,positive)
    return (love.keyboard.isDown(positive) and 1 or 0)-(love.keyboard.isDown(negative) and 1 or 0)
end

function Scene.setDestination(scene,x,y)
    scene.moveTarget={x=x,y=y}
end

function Scene.isWalkable(scene,x,y)
    if x<70 or x>890 or y>(scene.mode=="interior" and 620 or 620) then return false end
    if scene.mode=="interior" then
        if y<285 or (y>535 and (x<435 or x>525)) then return false end
        if x>150 and x<340 and y>350 and y<523 then return false end
        if x>807 and x<872 and y>342 and y<405 then return false end
    else
        if y<360 or (y>555 and (x<395 or x>590)) then return false end
        if x>125 and x<340 and y>429 and y<530 then return false end
        if x>551 and x<739 and y>409 and y<513 then return false end
    end
    return true
end

function Scene.update(scene,dt,options)
    options=options or {}
    scene.clock=scene.clock+dt
    local reports=0
    for _,defender in pairs(scene.defenders) do
        defender.flash=math.max(0,(defender.flash or 0)-dt)
        if scene.quest.victory or scene.quest.rewardClaimed or scene.quest.intermission then
            defender.frame=0
        else
            defender.timer=defender.timer-dt
            if defender.timer<=0 then
                if defender.phase=="idle" then
                    defender.phase="aim"; defender.frame=2; defender.timer=.9+math.random()*.6
                elseif defender.phase=="aim" then
                    defender.phase="fire"; defender.frame=3; defender.timer=.2; defender.flash=.12
                    reports=reports+1
                elseif defender.phase=="fire" then
                    defender.phase="reload"; defender.frame=4; defender.timer=1.1+math.random()
                else
                    defender.phase="idle"; defender.frame=0; defender.timer=1.8+math.random()*3
                end
            end
        end
    end
    if scene.handoff then return reports end
    local mobileX,mobileY=options.mobileX or 0,options.mobileY or 0
    local dx=movementAxis("a","d")+movementAxis("left","right")+(scene.axisX or 0)+mobileX
    local dy=movementAxis("w","s")+movementAxis("up","down")+(scene.axisY or 0)+mobileY
    local destination=false
    if dx==0 and dy==0 and scene.moveTarget then
        dx=scene.moveTarget.x-scene.player.x
        dy=scene.moveTarget.y-scene.player.y
        destination=true
        if dx*dx+dy*dy<12*12 then scene.moveTarget=nil; dx,dy=0,0 end
    elseif dx~=0 or dy~=0 then
        scene.moveTarget=nil
    end
    local distanceToTarget
    if destination then
        distanceToTarget=math.sqrt(dx*dx+dy*dy)
        dx,dy=dx/math.max(distanceToTarget,0.0001),dy/math.max(distanceToTarget,0.0001)
    end
    local motionOptions={
        profile=options.profile or CharacterMotion.defaults,
        speed=options.speed or 185,
        speedScale=options.sprinting and 1.7 or 1,
        maxDistance=destination and math.max(0,distanceToTarget-2) or nil,
        move=function(_,_,x,y)
            local player=scene.player
            local nextX,nextY=player.x,player.y
            if Scene.isWalkable(scene,x,player.y) then nextX=x end
            if Scene.isWalkable(scene,nextX,y) then nextY=y end
            local minY=scene.mode=="interior" and 285 or 360
            return math.max(70,math.min(890,nextX)),math.max(minY,math.min(620,nextY))
        end,
    }
    CharacterMotion.updateActor(scene.player,dx,dy,dt,motionOptions)
    if destination then
        local dxTarget,dyTarget=scene.moveTarget.x-scene.player.x,scene.moveTarget.y-scene.player.y
        if dxTarget*dxTarget+dyTarget*dyTarget<12*12 then scene.moveTarget=nil end
    end
    return reports
end

local function near(player,x,y,radius)
    local dx,dy=player.x-x,player.y-y
    return dx*dx+dy*dy<=radius*radius
end

function Scene.action(scene,needsLoan)
    local player=scene.player
    if scene.mode=="backyard" then
        if near(player,480,360,70) then return {id="enter-interior",label="USE BACK DOOR"} end
        if near(player,370,410,60) then return {id="talk-scout",label="TALK TO THE SCOUT"} end
        if near(player,750,455,65) then return {id="help-wounded",label="CHECK ON THE WOUNDED"} end
        if near(player,480,605,55) then
            return {id="return-stop",label=scene.quest.victory and "RETURN TO THE STOP" or "RETURN TO STOP / PAUSE QUEST"}
        end
        return nil
    end
    if near(player,300,335,60) then
        return needsLoan and not scene.quest.victory and {id="borrow-rifle",label="ACCEPT FOX'S RIFLE AND AMMO"}
            or {id="talk-fox",label="TALK TO GUARD FOX"}
    end
    if near(player,710,335,60) then return {id="talk-gecko",label="TALK TO GECKO RANGER"} end
    if not scene.quest.victory then
        if near(player,350,280,82) then return {id="window-wide",label="SHOOT FROM WIDE WINDOW"} end
        if near(player,660,280,82) then return {id="window-tall",label="SHOOT FROM TALL WINDOW"} end
    end
    if near(player,480,620,82) then return {id="exit-backyard",label="USE BACK DOOR"} end
    return nil
end

local function drawBackground(scene,width,height)
    local mode=scene.mode
    local path=mode=="interior" and PATHS.interior or PATHS.backyard
    local source=image(path)
    love.graphics.setColor(.055,.043,.032,1)
    love.graphics.rectangle("fill",0,0,width,height)
    if not source then return end
    local scale=width/source:getWidth()
    local drawHeight=source:getHeight()*scale
    if mode=="interior" then
        WindowScene.drawInterior(scene.quest,scene.clock,width,height,scale,(height-drawHeight)/2,scene.reducedMotion,scene.reducedFlashes)
    end
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(source,0,(height-drawHeight)/2,0,scale,scale)
end

local function drawPlayer(player,visual)
    love.graphics.setColor(0,0,0,.30)
    love.graphics.ellipse("fill",player.x,player.y+2,27,9)
    local playerImage=visual and visual.image or visual
    if visual and visual.animations and visual.character then
        local action=player.moving and "walk" or "idle"
        if CharacterAnimation.draw(visual.animations,visual.character,action,player.x,player.y+34,82,104,
            player.facing,visual.clock or 0,visual.clock or 0,player) then return end
    end
    if player.moving and visual and visual.walkImage then
        local image=visual.walkImage
        local scale=math.min(.075,90/image:getHeight())
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(image,player.x,player.y,0,-(player.facing or 1)*scale,scale,image:getWidth()/2,image:getHeight()/2)
        return
    end
    if playerImage and playerImage.getDimensions then
        local iw,ih=playerImage:getDimensions()
        local scale=78/math.max(iw,ih)
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(playerImage,player.x,player.y,0,scale,scale,iw/2,ih)
        return
    end
    love.graphics.setColor(.72,.60,.43,1)
    love.graphics.circle("fill",player.x,player.y-31,22)
    love.graphics.circle("fill",player.x-17,player.y-49,10)
    love.graphics.circle("fill",player.x+17,player.y-49,10)
    love.graphics.setColor(.24,.16,.10,1)
    love.graphics.rectangle("fill",player.x-18,player.y-12,36,22,8,8)
end

local function actorsFor(scene)
    if scene.mode=="backyard" then
        return {
            {path=PATHS.otter,frame=1,x=370,y=410,scale=.22},
            {path=PATHS.fox,frame=7,x=750,y=455,scale=.21},
            {path=PATHS.gecko,frame=5,x=610,y=370,scale=.20},
        }
    end
    local handoff=scene.handoff
    local shift=handoff and math.min(1,handoff.elapsed/.65)*45 or 0
    local foxFrame=scene.defenders.fox.frame
    local geckoFrame=scene.defenders.gecko.frame
    return {
        {path=PATHS.fox,frame=handoff and handoff.window=="wide" and 0 or foxFrame,
            x=300-(handoff and handoff.window=="wide" and shift or 0),y=295,scale=.22},
        {path=PATHS.gecko,frame=handoff and handoff.window=="tall" and 0 or geckoFrame,
            x=710+(handoff and handoff.window=="tall" and shift or 0),y=295,scale=.21,flip=true},
        {path=PATHS.otter,frame=0,x=520,y=430,scale=.20},
    }
end

local function drawAction(action,width,height)
    if not action then return end
    local x,y,w,h=330,height-66,300,44
    love.graphics.setColor(.07,.045,.025,.94)
    love.graphics.rectangle("fill",x,y,w,h,8,8)
    love.graphics.setColor(.88,.62,.27,1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line",x,y,w,h,8,8)
    love.graphics.printf("[E]  "..action.label,x,y+13,w,"center")
end

function Scene.draw(scene,width,height,playerImage,needsLoan)
    love.graphics.push("all")
    WorldView.begin()
    drawBackground(scene,width,height)
    love.graphics.setColor(.08,.045,.02,.11)
    love.graphics.rectangle("fill",0,0,width,height)
    local actors=actorsFor(scene)
    actors[#actors+1]={player=true,x=scene.player.x,y=scene.player.y}
    table.sort(actors,function(a,b) return a.y<b.y end)
    for _,actor in ipairs(actors) do
        if actor.player then
            drawPlayer(scene.player,playerImage)
        else
            drawAtlas(actor.path,actor.frame,actor.x,actor.y,actor.scale,512,512,4,actor.flip)
        end
    end
    if scene.mode=="interior" and not scene.reducedMotion and not scene.reducedFlashes
        and not scene.handoff and not scene.quest.victory and not scene.quest.intermission then
        if scene.defenders.fox.flash and scene.defenders.fox.flash>0 then WindowScene.drawEffect(0,347,247,.065,1) end
        if scene.defenders.gecko.flash and scene.defenders.gecko.flash>0 then WindowScene.drawEffect(0,666,248,.06,1) end
    end
    WorldView.finish()
    drawAction(Scene.action(scene,needsLoan),width,height)
    love.graphics.pop()
end

function Scene.actionRect(height)
    return 330,height-66,300,44
end

function Scene.drawApproach(state)
    local scout=state.scout
    if not scout then return end
    love.graphics.push("all")
    love.graphics.setColor(0,0,0,.28)
    WorldView.begin()
    love.graphics.ellipse("fill",scout.x,scout.y+2,28,9)
    local frame=state.arrival and state.arrival>0 and 0 or math.floor((state.walkDistance or 0)/8)%8
    drawAtlas(PATHS.otterWalk,frame,scout.x,scout.y,.23,320,512,8)
    WorldView.finish()
    local hintX,hintY=WorldView.toScreen(scout.x,scout.y)
    if state.arrival and state.arrival>0 then
        love.graphics.setColor(.08,.05,.03,.92)
        love.graphics.rectangle("fill",hintX-104,hintY-145,208,44,8,8)
        love.graphics.setColor(.98,.88,.68,1)
        local bark=state.quest.state=="paused" and "[E] Return to the homestead"
            or state.manualOffer and "[E] Talk to the scout" or "[E] Farmhouse defense"
        love.graphics.printf(bark,hintX-96,hintY-132,192,"center")
    end
    love.graphics.pop()
end

local function drawTraveler(visual,file,x,groundY,direction,distance,moving,clock)
    love.graphics.setColor(0,0,0,.28)
    love.graphics.ellipse("fill",x,groundY-6,20,7)
    local animations=visual and visual.animations
    local motion={intentX=direction,intentY=0,facing=direction,
        animationDistance=distance,moving=moving}
    if animations and CharacterAnimation.draw(animations,file,moving and "walk" or "idle",
        x,groundY,120,150,direction,clock,clock,motion) then return end
    if file=="otter-scout.png" then
        local frame=moving and CharacterMotion.frameForDistance(8,distance,20)-1 or 0
        drawAtlas(PATHS.otterWalk,frame,x,groundY,.34,320,512,8,direction<0)
        return
    end
    local fallback=visual and visual.image
    if fallback then
        local iw,ih=fallback:getDimensions()
        local scale=150/math.max(iw,ih)
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(fallback,x,groundY,0,-direction*scale,scale,iw/2,ih)
    end
end

function Scene.drawTransition(state,width,height,returning,playerVisual)
    love.graphics.push("all")
    WorldView.begin()
    WindowScene.drawBackground({quest=state.quest,clock=state.clock,reducedMotion=state.reducedMotion},width,height)
    local travel=state.reducedMotion and width*.5 or (state.clock*85)% (width+260)
    if not returning and state.clock>5 then
        local house=image(PATHS.backyard)
        if house then
            love.graphics.setColor(1,1,1,math.min(1,(state.clock-5)/2))
            love.graphics.draw(house,width*.44,height*.30,0,width*.5/house:getWidth(),width*.5/house:getWidth())
        end
    end
    local direction=returning and -1 or 1
    local distance=state.reducedMotion and 0 or (returning and travel*.45 or math.min(width*.58,travel*.45))
    local scoutX=returning and width-distance or 120+distance
    local groundY=height*.70
    local moving=not state.reducedMotion
    drawTraveler(playerVisual,"otter-scout.png",scoutX,groundY,direction,distance,moving,state.clock)
    drawTraveler(playerVisual,playerVisual and playerVisual.character,
        scoutX-direction*95,groundY,direction,distance,moving,state.clock)
    WorldView.finish()
    love.graphics.setColor(.04,.025,.016,.82)
    love.graphics.rectangle("fill",110,height*.14,width-220,118,12,12)
    love.graphics.setColor(.96,.84,.62,1)
    love.graphics.printf(returning and "The relay falls quiet behind you." or "You follow the scout beyond the town limits.",135,height*.14+26,width-270,"center")
    love.graphics.setColor(.82,.70,.52,1)
    love.graphics.printf(returning and "The survivors can finally leave the windows." or "Distant rifle cracks roll over the fields.",135,height*.14+67,width-270,"center")
    love.graphics.printf("[SPACE] Skip journey",width/2-120,height-55,240,"center")
    love.graphics.pop()
end

function Scene.release()
    for _,cache in ipairs({images,quads}) do
        for _,resource in pairs(cache) do
            if resource and resource.release then pcall(resource.release,resource) end
        end
    end
    images,quads={},{}
    WindowScene.release()
end

return Scene
