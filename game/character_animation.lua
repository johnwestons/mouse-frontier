local CharacterMotion = require("game.character_motion")

local CharacterAnimation = {}

-- A few authored sheets include a small transparent footer.  Keep the
-- shared bottom-anchor for every character, with only the affected sheets
-- receiving a pixel-space baseline correction.
CharacterAnimation.anchorOffsets = {
    ["cowboy-mouse-no-skull.png"] = -15,
}

CharacterAnimation.actions={
    idle=2,idle_north=2,idle_northeast=2,idle_southeast=2,idle_south=2,
    idle_west=2,idle_northwest=2,idle_southwest=2,
    sit=2,lay=2,walk=3,walk_north=8,walk_northeast=8,walk_southeast=8,walk_south=8,
    walk_west=8,walk_northwest=8,walk_southwest=8,
    melee=3,ranged=3,use=3,hit=3,death=3,unconscious=2,
}
CharacterAnimation.requiredActions={"idle","sit","lay","melee","ranged","use","hit"}

local function isWalkAction(action)
    return type(action)=="string" and (action=="walk" or action:match("^walk_")~=nil)
end

local function loadSet(manager,file)
    local directory=manager.known[file]
    if not directory then return nil end
    local set={}
    local generatedSet=love.filesystem.getInfo(manager.root.."/"..directory.."/unconscious.png")~=nil
    local motionProfile=CharacterMotion.profileFor(file)
    for action,count in pairs(CharacterAnimation.actions) do
        if action=="walk" then count=motionProfile and 8 or (generatedSet and 6 or 3) end
        local path=manager.root.."/"..directory.."/"..action..".png"
        local image=manager.loadImage(path)
        if image then
            local width,height=image:getDimensions(); local frameWidth=width/count; local quads={}
            for frame=1,count do quads[frame]=love.graphics.newQuad((frame-1)*frameWidth,0,frameWidth,height,width,height) end
            -- Runtime transparency scans used to decode every sheet a second
            -- time and inspect every pixel. Frame bounds are stable metadata
            -- and keep streamed character loads cheap and deterministic.
            set[action]={image=image,quads=quads,w=frameWidth,h=height,count=count,visibleExtent=math.max(frameWidth,height)}
        end
    end
    set.baseExtent=set.idle and set.idle.visibleExtent or nil
    set.motionProfile=motionProfile
    set.directional=motionProfile~=nil and CharacterMotion.hasDirectionalSet(set)
    set.authoredWest=set.directional and CharacterMotion.hasAuthoredWestSet(set)
    manager.sets[file]=set
    return set
end

local function releaseSet(set)
    for _,animation in pairs(set or {}) do
        if type(animation)=="table" and animation.image and animation.image.release then
            pcall(animation.image.release,animation.image)
        end
    end
end

function CharacterAnimation.load(root,loadImage)
    local manager={root=root,loadImage=loadImage,known={},sets={},retainSignature=""}
    if not love.filesystem.getInfo(root) then return manager end
    local missing={}
    for _,directory in ipairs(love.filesystem.getDirectoryItems(root)) do
        local info=love.filesystem.getInfo(root.."/"..directory)
        if info and info.type=="directory" then
            local file=directory..".png"
            manager.known[file]=directory
            -- Validate required files without decoding their image data.
            for _,action in ipairs(CharacterAnimation.requiredActions) do
                local path=root.."/"..directory.."/"..action..".png"
                if not love.filesystem.getInfo(path) then missing[#missing+1]=directory.."/"..action..".png" end
            end
        end
    end
    if #missing>0 then error("Required character animation sheets are missing:\n"..table.concat(missing,"\n")) end
    return setmetatable(manager,{__index=function(self,key)
        local method=CharacterAnimation[key]
        if method then return method end
        return self.sets[key] or loadSet(self,key)
    end})
end

function CharacterAnimation.retain(manager,files)
    if not manager or not manager.sets then return end
    local names={}
    for file,wanted in pairs(files or {}) do if wanted and manager.known[file] then names[#names+1]=file end end
    table.sort(names)
    local signature=table.concat(names,"|")
    if signature==manager.retainSignature then return end
    local keep={}; for _,file in ipairs(names) do keep[file]=true; if not manager.sets[file] then loadSet(manager,file) end end
    for file,set in pairs(manager.sets) do
        if not keep[file] then releaseSet(set); manager.sets[file]=nil end
    end
    manager.retainSignature=signature
end

function CharacterAnimation.draw(sets,file,action,x,y,maxWidth,maxHeight,facing,phase,clock,motion)
    local set=sets[file]
    local directionalMirror=1
    if set and set.directional and motion and (action=="walk" or action=="idle") then
        if action=="walk" then
            action,directionalMirror=CharacterMotion.directionalWalkAction(motion.intentX,motion.intentY,set.authoredWest)
        else
            action,directionalMirror=CharacterMotion.directionalIdleAction(motion.intentX,motion.intentY,set.authoredWest)
        end
    end
    local animation=set and (set[action] or set.idle)
    -- Do not silently turn a missing walk sheet into an idle/use animation.
    -- The caller can then use the dedicated legacy walk sheet instead.
    if action == "walk" and set and not set.walk then return false end
    if not animation then return false end
    local passiveRate={idle=.70,idle_north=.70,idle_northeast=.70,idle_southeast=.70,idle_south=.70,sit=.55,lay=.38,walk=5.2}
    local frameRate=action=="hit" and 8.5 or (passiveRate[action] or 6)
    -- The lay sheets face opposite the rest of the character set, so mirror
    -- the authored two-frame resting loop once to follow the normal facing
    -- convention: +1 faces right, -1 faces left.
    local layCorrection = action == "lay"
    local frame
    if set.directional and isWalkAction(action) and motion then
        frame=CharacterMotion.frameForDistance(animation.count,motion.animationDistance,set.motionProfile.pixelsPerFrame)
    else
        frame=action=="death" and animation.count or (math.floor((phase or clock)*frameRate)%animation.count)+1
    end
    local baseExtent=set.baseExtent or animation.visibleExtent or math.max(animation.w,animation.h)
    local visible=animation.visibleExtent or baseExtent
    -- Walk sheets can have a much tighter crop than the idle sheet (the
    -- conductor-cat set is a good example).  The old 1.35 ceiling left those
    -- frames visibly smaller even though they were authored at the same
    -- character scale.  Allow walking frames to recover their full extent,
    -- while keeping the conservative cap for poses/actions whose artwork may
    -- intentionally be more compact.
    local extentRatio=baseExtent/math.max(1,visible)
    local normalize=math.max(.72,math.min(action == "walk" and 1.8 or 1.35,extentRatio))
    local scale=math.min((maxWidth or 76)/animation.w,(maxHeight or 96)/animation.h)*normalize
    love.graphics.setColor(1,1,1)
    -- Central walk sheets were authored opposite to the runtime facing
    -- convention.  Correct only the walking action; idle/pose art keeps its
    -- normal orientation and legacy walk sheets are corrected by their caller.
    local directionalLocomotion=set.directional and (isWalkAction(action) or action:match("^idle")~=nil)
    local walkCorrection = not directionalLocomotion and (action == "walk" or action == "idle") and -1 or 1
    local drawFacing = (directionalLocomotion and directionalMirror or (facing or 1))
        * (layCorrection and -1 or 1) * walkCorrection
    local anchorOffset = CharacterAnimation.anchorOffsets[file] or 0
    love.graphics.draw(animation.image,animation.quads[frame],x,y + anchorOffset + (layCorrection and 20 or 0),0,scale*drawFacing,scale,animation.w/2,animation.h)
    return true
end

return CharacterAnimation
