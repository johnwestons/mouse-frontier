local WeaponAttachment = {}

local okPoints, generatedPoints = pcall(require, "game.weapon_attachment_points")
if not okPoints or type(generatedPoints)~="table" then generatedPoints={} end

local handCache = {}
local weaponCache = {}
local patchCache = {}

-- Keep this in step with CharacterAnimation.anchorOffsets. WeaponAttachment
-- intentionally has no dependency on the renderer so it can also be used by
-- the Sprite Doctor preview and smoke harnesses.
local anchorOffsets = {
    ["cowboy-mouse-no-skull.png"] = -15,
}

local longGunWords = {"rifle", "carbine", "shotgun", "smg", "ak", "hunter"}

local function clamp(value,low,high)
    return math.max(low,math.min(high,value))
end

local function containsWord(name,words)
    name=(name or ""):lower()
    for _,word in ipairs(words) do
        if name:find(word,1,true) then return true end
    end
    return false
end

local function isLongGun(name)
    return containsWord(name,longGunWords)
end

local function alphaAt(data,x,y)
    local _,_,_,a=data:getPixel(x,y)
    return a or 0
end

-- Runtime fallback for newly-added characters whose generated entry has not
-- reached weapon_attachment_points.lua yet. The offline Sprite Doctor uses a
-- more exhaustive detector; this small alpha scan runs only once per frame.
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
    if maxX<minX then return {x=frameWidth*.28,y=height*.48,side=-1,confidence=0} end

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
    if bandMax<bandMin then return {x=minX+visibleW*.18,y=minY+visibleH*.46,side=-1,confidence=0} end
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
    if count==0 then return {x=edge-side*reach*.45,y=(bandTop+bandBottom)/2,side=side,confidence=0} end
    return {x=sumX/count,y=sumY/count,side=side,confidence=0}
end

local function generatedHand(file,action,frame,animation)
    local byFile=generatedPoints[file]
    local byAction=byFile and byFile[action]
    local point=byAction and byAction[frame]
    if type(point)~="table" or type(point.x)~="number" or type(point.y)~="number" then return nil end
    if point.x<0 or point.x>1 or point.y<0 or point.y>1 then return nil end
    return {
        x=point.x*animation.w,
        y=point.y*animation.h,
        side=point.side==-1 and -1 or 1,
        confidence=point.confidence or 0,
        generated=true,
    }
end

local function fallbackHands(manager,file,action,animation)
    local key=(manager.root or "").."|"..file.."|"..action.."|"..animation.count.."|"..animation.w.."x"..animation.h
    if handCache[key] then return handCache[key] end
    local directory=manager.known and manager.known[file]
    local path=directory and (manager.root.."/"..directory.."/"..action..".png")
    local ok,data=path and love.image and love.image.newImageData and pcall(love.image.newImageData,path)
    local anchors={}
    if ok and data then
        for frame=1,animation.count do
            anchors[frame]=detectFrameHand(data,(frame-1)*animation.w,animation.w,animation.h)
        end
        if data.release then data:release() end
    else
        for frame=1,animation.count do anchors[frame]={x=animation.w*.28,y=animation.h*.48,side=-1,confidence=0} end
    end
    handCache[key]=anchors
    return anchors
end

local function handFor(manager,file,action,frame,animation)
    return generatedHand(file,action,frame,animation) or fallbackHands(manager,file,action,animation)[frame]
end

-- Accept either a standalone Image or an atlas record created by assets.lua.
-- Keeping the atlas quad intact avoids allocating a separate Image per item.
function WeaponAttachment.itemSprite(ui,name)
    if not ui or not name then return nil end
    local atlas=ui.atlasItems and ui.atlasItems[name]
    if atlas and atlas.image and atlas.quad then
        return {image=atlas.image,quad=atlas.quad,w=atlas.w,h=atlas.h,atlas=true}
    end
    local image=ui.propImages and ui.propImages[name]
    if image then
        local w,h=image:getDimensions()
        return {image=image,w=w,h=h}
    end
end

local function asSprite(imageOrSprite)
    if not imageOrSprite then return nil end
    if imageOrSprite.image then return imageOrSprite end
    if imageOrSprite.getDimensions then
        local w,h=imageOrSprite:getDimensions()
        return {image=imageOrSprite,w=w,h=h}
    end
end

local function visibleWeaponBounds(name,sprite)
    local key=(name or "").."|"..tostring(sprite.w).."x"..tostring(sprite.h)..(sprite.quad and "|atlas" or "|single")
    if weaponCache[key] then return weaponCache[key] end
    local width,height=sprite.w,sprite.h
    local bounds
    if sprite.quad then
        -- Atlas registrations expose cell dimensions but intentionally keep
        -- their source path private. Generated weapon atlases reserve a thin
        -- safety gutter, so exclude it when choosing the held-item scale.
        bounds={x=width*.06,y=height*.06,w=width*.88,h=height*.88}
    else
        bounds={x=0,y=0,w=width,h=height}
        local path="assets/sprites/weapons/"..name..".png"
        local ok,data=love.image and love.image.newImageData and pcall(love.image.newImageData,path)
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
    end
    weaponCache[key]=bounds
    return bounds
end

local function weaponLayout(name,action,combat,bounds)
    local lower=(name or ""):lower()
    local ranged=action=="ranged"
    local longGun=ranged and isLongGun(lower)
    local bow=ranged and lower:find("bow",1,true)~=nil
    local sling=ranged and lower:find("slingshot",1,true)~=nil
    local polearm=combat and combat.family=="polearm" or containsWord(lower,{"spear","halberd","partisan","trident","glaive"})
    local oversized=containsWord(lower,{"greatsword","executioner","battle-axe","maul"})
    local length=longGun and 70 or (bow and 58 or (polearm and 72 or (oversized and 58 or (ranged and 38 or 48))))
    local major=math.max(1,bounds.w,bounds.h)
    if longGun then
        return {scale=length/math.max(1,bounds.w),sourceAim=1,gripX=.60,gripY=.58}
    elseif ranged and not bow and not sling then
        -- Existing standalone and atlas pistols point left in their source
        -- art. Retain their proven grip/orientation behavior.
        return {scale=length/major,sourceAim=-1,gripX=.80,gripY=.50}
    elseif ranged then
        return {scale=length/major,sourceAim=1,gripX=.50,gripY=.55}
    end
    return {scale=length/major,sourceAim=1,gripX=polearm and .22 or .18,gripY=polearm and .76 or .80}
end

local function drawSprite(sprite,x,y,rotation,sx,sy,ox,oy)
    if sprite.quad then love.graphics.draw(sprite.image,sprite.quad,x,y,rotation,sx,sy,ox,oy)
    else love.graphics.draw(sprite.image,x,y,rotation,sx,sy,ox,oy) end
end

local function drawHandPatch(manager,file,action,animation,frame,hand,handX,handY,characterScale,drawFacing)
    local patchSize=math.max(4,math.floor(math.min(animation.w,animation.h)*.075))
    local patchX=clamp(math.floor(hand.x-patchSize/2),0,animation.w-patchSize)
    local patchY=clamp(math.floor(hand.y-patchSize/2),0,animation.h-patchSize)
    local key=(manager.root or "").."|"..file.."|"..action.."|"..frame.."|"..patchX..":"..patchY..":"..patchSize
    local quad=patchCache[key]
    if not quad then
        quad=love.graphics.newQuad((frame-1)*animation.w+patchX,patchY,patchSize,patchSize,animation.w*animation.count,animation.h)
        patchCache[key]=quad
    end
    love.graphics.setColor(1,1,1)
    love.graphics.draw(animation.image,quad,handX,handY,0,characterScale*drawFacing,characterScale,hand.x-patchX,hand.y-patchY)
end

function WeaponAttachment.isFirearm(catalog,name)
    return name and catalog and catalog.weaponFamily and catalog.weaponFamily(name)=="firearms"
end

-- Draw a weapon at the hand point for the same action frame rendered by
-- CharacterAnimation.draw. The final action/combat parameters are optional
-- to preserve callers of the original firearm-only API.
function WeaponAttachment.draw(manager,file,weaponName,imageOrSprite,x,y,maxWidth,maxHeight,facing,phase,action,combat)
    if not manager or not file or not weaponName then return false end
    local sprite=asSprite(imageOrSprite)
    if not sprite or not sprite.image then return false end
    action=action=="melee" and "melee" or "ranged"
    local set=manager[file]; local animation=set and set[action]
    if not animation then return false end

    local frame=(math.floor((phase or 0)*6)%animation.count)+1
    local hand=handFor(manager,file,action,frame,animation)
    if not hand then return false end

    local baseExtent=set.baseExtent or math.max(animation.w,animation.h)
    local visible=animation.visibleExtent or baseExtent
    local normalize=math.max(.72,math.min(1.35,baseExtent/math.max(1,visible)))
    local characterScale=math.min((maxWidth or 76)/animation.w,(maxHeight or 96)/animation.h)*normalize
    local drawFacing=facing or 1
    local handX=x+(hand.x-animation.w/2)*characterScale*drawFacing
    local handY=y+(anchorOffsets[file] or 0)+(hand.y-animation.h)*characterScale

    local bounds=visibleWeaponBounds(weaponName,sprite)
    local layout=weaponLayout(weaponName,action,combat,bounds)
    local desiredAim=(hand.side or -1)*(drawFacing<0 and -1 or 1)
    local flip=desiredAim==layout.sourceAim and 1 or -1
    local gripX=bounds.x+bounds.w*layout.gripX
    local gripY=bounds.y+bounds.h*layout.gripY
    love.graphics.setColor(1,1,1)
    drawSprite(sprite,handX,handY,0,layout.scale*flip,layout.scale,gripX,gripY)

    -- Repaint a small authored patch over the grip. This creates the visual
    -- overlap that makes the item read as held without requiring character-
    -- specific hand layers in every animation sheet.
    drawHandPatch(manager,file,action,animation,frame,hand,handX,handY,characterScale,drawFacing)
    return true
end

function WeaponAttachment.clearCaches()
    handCache={}; weaponCache={}; patchCache={}
end

return WeaponAttachment
