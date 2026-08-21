local WeaponAttachment = {}

local handCache = {}
local weaponCache = {}

local anchorOffsets = {
    ["cowboy-mouse-no-skull.png"] = -15,
}

local longGunWords = {"rifle", "carbine", "shotgun", "smg", "ak", "hunter"}

local function isLongGun(name)
    name = (name or ""):lower()
    for _,word in ipairs(longGunWords) do
        if name:find(word,1,true) then return true end
    end
    return false
end

local function alphaAt(data,x,y)
    local _,_,_,a=data:getPixel(x,y)
    return a or 0
end

local function detectFrameHand(data,frameX,frameWidth,height)
    local step=3
    local minX,minY,maxX,maxY=frameWidth,height,-1,-1
    for y=0,height-1,step do
        for x=0,frameWidth-1,step do
            if alphaAt(data,frameX+x,y)>.08 then
                minX,minY=math.min(minX,x),math.min(minY,y)
                maxX,maxY=math.max(maxX,x),math.max(maxY,y)
            end
        end
    end
    if maxX<minX then return {x=frameWidth*.28,y=height*.46,side=-1} end

    local visibleW,visibleH=maxX-minX+1,maxY-minY+1
    local bandTop=math.floor(minY+visibleH*.30)
    local bandBottom=math.floor(minY+visibleH*.60)
    local torsoTop=math.floor(minY+visibleH*.58)
    local torsoBottom=math.floor(minY+visibleH*.88)
    local bandMin,bandMax=frameWidth,-1
    local torsoMin,torsoMax=frameWidth,-1
    for y=bandTop,bandBottom,step do
        for x=minX,maxX,step do
            if alphaAt(data,frameX+x,y)>.08 then bandMin,bandMax=math.min(bandMin,x),math.max(bandMax,x) end
        end
    end
    for y=torsoTop,torsoBottom,step do
        for x=minX,maxX,step do
            if alphaAt(data,frameX+x,y)>.08 then torsoMin,torsoMax=math.min(torsoMin,x),math.max(torsoMax,x) end
        end
    end
    if bandMax<bandMin then return {x=minX+visibleW*.18,y=minY+visibleH*.46,side=-1} end
    local torsoCenter=torsoMax>=torsoMin and (torsoMin+torsoMax)/2 or (minX+maxX)/2
    local side=(torsoCenter-bandMin)>=(bandMax-torsoCenter) and -1 or 1
    local edge=side<0 and bandMin or bandMax
    local reach=math.max(9,visibleW*.16)
    local sumX,sumY,count=0,0,0
    for y=bandTop,bandBottom,step do
        for x=bandMin,bandMax,step do
            local nearEdge=side<0 and x<=edge+reach or x>=edge-reach
            if nearEdge and alphaAt(data,frameX+x,y)>.08 then
                sumX,sumY,count=sumX+x,sumY+y,count+1
            end
        end
    end
    if count==0 then return {x=edge-side*reach*.45,y=(bandTop+bandBottom)/2,side=side} end
    return {x=sumX/count,y=sumY/count,side=side}
end

local function handAnchors(manager,file,animation)
    local key=(manager.root or "").."|"..file
    if handCache[key] then return handCache[key] end
    local directory=manager.known and manager.known[file]
    local path=directory and (manager.root.."/"..directory.."/ranged.png")
    local ok,data=path and pcall(love.image.newImageData,path)
    local anchors={}
    if ok and data then
        for frame=1,animation.count do
            anchors[frame]=detectFrameHand(data,(frame-1)*animation.w,animation.w,animation.h)
        end
        if data.release then data:release() end
    else
        for frame=1,animation.count do anchors[frame]={x=animation.w*.28,y=animation.h*.46,side=-1} end
    end
    handCache[key]=anchors
    return anchors
end

local function visibleWeaponBounds(name,image)
    if weaponCache[name] then return weaponCache[name] end
    local width,height=image:getDimensions()
    local bounds={x=0,y=0,w=width,h=height}
    local ok,data=pcall(love.image.newImageData,"assets/sprites/weapons/"..name..".png")
    if ok and data then
        local step=2; local minX,minY,maxX,maxY=width,height,-1,-1
        for y=0,height-1,step do
            for x=0,width-1,step do
                if alphaAt(data,x,y)>.08 then
                    minX,minY=math.min(minX,x),math.min(minY,y)
                    maxX,maxY=math.max(maxX,x),math.max(maxY,y)
                end
            end
        end
        if maxX>=minX then bounds={x=minX,y=minY,w=maxX-minX+1,h=maxY-minY+1} end
        if data.release then data:release() end
    end
    weaponCache[name]=bounds
    return bounds
end

function WeaponAttachment.isFirearm(catalog,name)
    return name and catalog and catalog.weaponFamily and catalog.weaponFamily(name)=="firearms"
end

function WeaponAttachment.draw(manager,file,weaponName,image,x,y,maxWidth,maxHeight,facing,phase)
    if not manager or not file or not weaponName or not image then return false end
    local set=manager[file]; local animation=set and set.ranged
    if not animation then return false end

    local frameRate=6
    local frame=(math.floor((phase or 0)*frameRate)%animation.count)+1
    local anchors=handAnchors(manager,file,animation); local hand=anchors[frame]
    if not hand then return false end

    local baseExtent=set.baseExtent or math.max(animation.w,animation.h)
    local visible=animation.visibleExtent or baseExtent
    local normalize=math.max(.72,math.min(1.35,baseExtent/math.max(1,visible)))
    local characterScale=math.min((maxWidth or 76)/animation.w,(maxHeight or 96)/animation.h)*normalize
    local drawFacing=facing or 1
    local handX=x+(hand.x-animation.w/2)*characterScale*drawFacing
    local handY=y+(anchorOffsets[file] or 0)+(hand.y-animation.h)*characterScale

    local bounds=visibleWeaponBounds(weaponName,image)
    local longGun=isLongGun(weaponName)
    local visibleLength=longGun and 70 or 36
    local weaponScale=visibleLength/math.max(1,bounds.w)
    local sourceAim=longGun and 1 or -1
    local desiredAim=hand.side*(drawFacing<0 and -1 or 1)
    local flip=desiredAim==sourceAim and 1 or -1
    local gripX=bounds.x+bounds.w*(longGun and .60 or .80)
    local gripY=bounds.y+bounds.h*(longGun and .58 or .50)
    love.graphics.setColor(1,1,1)
    love.graphics.draw(image,handX,handY,0,weaponScale*flip,weaponScale,gripX,gripY)

    -- Restore a small piece of the authored hand over the grip. The firearm
    -- remains readable across the body while still looking held rather than
    -- pasted on top of the character.
    local patchSize=math.floor(math.min(animation.w,animation.h)*.12)
    local patchX=math.max(0,math.min(animation.w-patchSize,math.floor(hand.x-patchSize/2)))
    local patchY=math.max(0,math.min(animation.h-patchSize,math.floor(hand.y-patchSize/2)))
    hand.quad=hand.quad or love.graphics.newQuad((frame-1)*animation.w+patchX,patchY,patchSize,patchSize,animation.w*animation.count,animation.h)
    love.graphics.setColor(1,1,1)
    love.graphics.draw(animation.image,hand.quad,handX,handY,0,characterScale*drawFacing,characterScale,hand.x-patchX,hand.y-patchY)
    return true
end

function WeaponAttachment.clearCaches()
    handCache={}; weaponCache={}
end

return WeaponAttachment
