-- Ambient repair rounds follow the user's four green waypoints. Movement
-- uses actual resolved distance; work poses are authored sprite frames.
local Home=require("game.home_stop")
local Motion=require("game.character_motion")
local Animation=require("game.character_animation")
local Fox={KEY="homeStop:tinker"}
Fox.profile={}
for key,value in pairs(Motion.defaults) do Fox.profile[key]=value end
Fox.profile.pixelsPerFrame=5.6
Fox.speed=58
Fox.bodySize=82
Fox.footBaseline=458/512
Fox.motionRoot="assets/sprites/home-stop/adult-tinker-fox/"
Fox.route={
    {x=340,y=448,work="crates",duration=3.5},
    {x=425,y=424},{x=500,y=375},{x=580,y=326},
    {x=635,y=300,work="wrench",duration=4},
    {x=615,y=365},{x=615,y=410},{x=650,y=438},
    {x=705,y=448,work="wrench",duration=5},
    {x=706,y=525},{x=742,y=584},{x=800,y=610},{x=860,y=590},{x=895,y=550},
    {x=897,y=503,work="oil",duration=5},
    {x=900,y=560},{x=865,y=612},{x=805,y=632},{x=690,y=625},{x=560,y=570},{x=440,y=510},
}
function Fox.ensure(data)
    data.npcStates=data.npcStates or {}
    local actor=data.npcStates[Fox.KEY]
    if not actor then
        actor={x=Fox.route[1].x,y=Fox.route[1].y,routeIndex=1,workTime=0,work="crates",rounds=0,facing=1}
        Motion.resetActor(actor)
        data.npcStates[Fox.KEY]=actor
    end
    -- Existing test journeys can resume the old checklist stop with the adult
    -- action; route timing and the already travelled gait distance stay intact.
    if actor.work=="checklist" then actor.work=(actor.routeIndex or 1)==1 and "crates" or "wrench" end
    actor.file=Home.FOX
    actor.characterId=require('game.npc_identity').ensure(data,Home.FOX,1,1,Fox.KEY).id
    return actor
end
function Fox.actor(data) return data.npcStates and data.npcStates[Fox.KEY] end
function Fox.interaction(data,player)
    if not Home.isHome(data) or Home.isOffice(data) or data.scene~="stop" or not player then return nil end
    local actor=Fox.actor(data)
    if not actor or type(player.x)~="number" or type(player.y)~="number" then return nil end
    if (player.x-actor.x)^2+(player.y-actor.y)^2>=95^2 then return nil end
    return {kind="homeFox",action="talk",label="Talk to Tinker Fox",x=actor.x,y=actor.y,hoverRadius=52}
end
function Fox.facePlayer(data,player)
    local actor=Fox.actor(data)
    if not actor or not player then return end
    local dx,dy=player.x-actor.x,player.y-actor.y
    Motion.stopActor(actor); actor.moving=false
    if dx*dx+dy*dy>.001 then actor.intentX,actor.intentY=dx,dy; actor.facing=dx<0 and -1 or 1 end
end
function Fox.update(data,dt,talkingPlayer)
    if not Home.isHome(data) or data.scene~="stop" then return end
    local actor=Fox.ensure(data)
    if talkingPlayer then Fox.facePlayer(data,talkingPlayer); return end
    dt=math.max(0,math.min(.1,dt))
    local point=Fox.route[actor.routeIndex or 1]
    if actor.work then
        Motion.stopActor(actor); actor.moving=false
        actor.workTime=(actor.workTime or 0)+dt
        if actor.workTime>=(point.duration or 4) then
            actor.work=nil; actor.workTime=0
            actor.routeIndex=actor.routeIndex%#Fox.route+1
        end
        return
    end
    local arrived=Motion.moveToward(actor,point.x,point.y,dt,{profile=Fox.profile,speed=Fox.speed,stopDistance=2,
        move=function(ox,oy,x,y) return Home.move(ox,oy,x,y) end})
    if arrived then
        if point.work then
            actor.work=point.work; actor.workTime=0
            -- Work on the near fittings faces east; the far platform action
            -- has separately authored west-facing oiling frames.
            actor.facing=point.work=="oil" and -1 or 1
            actor.intentX,actor.intentY=actor.facing,0
        else
            actor.routeIndex=actor.routeIndex%#Fox.route+1
            if actor.routeIndex==1 then actor.rounds=(actor.rounds or 0)+1 end
        end
    end
end
local workAssets={}
local motionSet
local workPaths={crates=Fox.motionRoot.."crates.png",wrench=Fox.motionRoot.."wrench.png",oil=Fox.motionRoot.."oil.png"}
function Fox.release()
    for _,asset in pairs(workAssets) do asset.image:release() end
    if motionSet then for _,asset in pairs(motionSet) do if type(asset)=="table" and asset.image then asset.image:release() end end end
    workAssets={}
    motionSet=nil
end
local function motionAssets()
    if motionSet then return motionSet end
    local g=love.graphics
    motionSet={directional=true,authoredWest=true,motionProfile=Fox.profile}
    for _,suffix in ipairs({"","_north","_northeast","_northwest","_west","_southwest","_south","_southeast"}) do
        for _,action in ipairs({"walk","idle"}) do
            local key=action..suffix
            local image=g.newImage(Fox.motionRoot..key..".png")
            image:setFilter("linear","linear")
            local width,height=image:getDimensions()
            local count=width/height
            assert(count==(action=="walk" and 8 or 2),"Adult home fox requires eight authored walk poses and two idle poses: "..key)
            -- Every adult strip shares the same logical body canvas. Mobile
            -- packs may resize eight-pose walks more than idles/work strips;
            -- use this decoded cell's size, bypassing cross-strip crop scaling.
            local asset={image=image,w=height,h=height,count=count,visibleExtent=height,bodyExtent=height,quads={}}
            for frame=1,count do asset.quads[frame]=g.newQuad((frame-1)*height,0,height,height,width,height) end
            motionSet[key]=asset
        end
    end
    motionSet.baseExtent=motionSet.idle.h
    return motionSet
end
function Fox.draw(sets,data,clock,talking)
    local actor=Fox.actor(data)
    if not actor then return end
    local g=love.graphics
    g.setColor(0,0,0,.2); g.ellipse("fill",actor.x,actor.y,18,6)
    local file=not talking and actor.work and workPaths[actor.work]
    if file and not workAssets[file] and love.filesystem.getInfo(file) then
        local image=g.newImage(file); image:setFilter("linear","linear")
        local width,height=image:getDimensions()
        local asset={image=image,w=width/4,h=height,quads={}}
        for frame=1,4 do asset.quads[frame]=g.newQuad((frame-1)*asset.w,0,asset.w,height,width,height) end
        workAssets[file]=asset
    end
    local asset=file and workAssets[file]
    if asset then
        local frame=math.floor((actor.workTime or 0)*4)%4+1
        local scale=Fox.bodySize/asset.h
        g.setColor(1,1,1,1)
        g.draw(asset.image,asset.quads[frame],actor.x,actor.y,0,scale,scale,asset.w/2,asset.h*Fox.footBaseline)
    else
        local set=motionAssets()
        local y=actor.y+Fox.bodySize*(1-Fox.footBaseline)
        Animation.draw({[Home.FOX]=set},Home.FOX,not talking and actor.moving and "walk" or "idle",actor.x,y,Fox.bodySize,Fox.bodySize,actor.facing,clock,clock,actor)
    end
end
return Fox
