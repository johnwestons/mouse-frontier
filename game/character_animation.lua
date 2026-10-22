local CharacterMotion = require("game.character_motion")
local ActionProfiles = require("game.character_action_profiles")
local SwingProfiles = require("game.character_swing_profiles")

local CharacterAnimation = {}
local poseViews=setmetatable({},{__mode='k'})

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
    melee=3,swing=6,ranged=3,use=3,hit=3,death=3,unconscious=2,
    sweep=4,carry=4,tend=4,
}
CharacterAnimation.requiredActions={"idle","sit","lay","melee","swing","ranged","use","hit"}

local function isWalkAction(action)
    return type(action)=="string" and (action=="walk" or action:match("^walk_")~=nil
        or action=="run" or action:match("^run_")~=nil)
end

local function loadSet(manager,file)
    local directory=manager.known[file]
    if not directory then return nil end
    local set={}
    local generatedSet=love.filesystem.getInfo(manager.root.."/"..directory.."/unconscious.png")~=nil
    local motionProfile=CharacterMotion.profileFor(file)
    local actionProfile=ActionProfiles.characters[file]
    local actions=CharacterAnimation.actions
    if motionProfile and motionProfile.runPixelsPerFrame then
        actions={}
        for action,count in pairs(CharacterAnimation.actions) do actions[action]=count end
        for _,action in ipairs(CharacterMotion.runActions) do actions[action]=8 end
    end
    for action,count in pairs(actions) do
        if action=="walk" then count=motionProfile and 8 or (generatedSet and 6 or 3) end
        local playback=actionProfile and (action~='idle' or actionProfile.hasIdle) and ActionProfiles.actions[action]
        if action=='swing' then playback=SwingProfiles.actions.swing end
        if playback then count=playback.count end
        local path=manager.root.."/"..directory.."/"..action..".png"
        local image=manager.loadImage(path)
        if image then
            local width,height=image:getDimensions()
            if isWalkAction(action) then
                -- Walk strips can use a different frame count from the legacy
                -- default; infer it from every direction's sheet dimensions.
                local sheetFrames=math.floor(width/math.max(1,height)+.5)
                if sheetFrames>0 and math.abs(width-sheetFrames*height)<=1 then count=sheetFrames end
            end
            local frameWidth=width/count; local quads={}
            for frame=1,count do quads[frame]=love.graphics.newQuad((frame-1)*frameWidth,0,frameWidth,height,width,height) end
            -- Runtime transparency scans used to decode every sheet a second
            -- time and inspect every pixel. Frame bounds are stable metadata
            -- and keep streamed character loads cheap and deterministic.
            set[action]={image=image,quads=quads,w=frameWidth,h=height,count=count,visibleExtent=math.max(frameWidth,height)}
            if playback then
                set[action].playback=playback
                -- Mobile packages resize complete cells. The logical body
                -- canvas scales with the decoded image, not its source PNG.
                set[action].bodyExtent=height
                set[action].handPoints=actionProfile and actionProfile.hands and actionProfile.hands[action]
                if action=='swing' then
                    local swing=SwingProfiles.characters[file]
                    set[action].handPoints=swing
                    if swing then
                        local ratio=swing.bodyScale or 1
                        set[action].bodyExtent=height*ratio
                        local baseline=(swing.baseline or 229)/256
                        set[action].originY=height*(baseline+(1-baseline)*ratio)
                    end
                end
            end
        end
    end
    set.baseExtent=set.idle and set.idle.visibleExtent or nil
    set.motionProfile=motionProfile
    set.directional=motionProfile~=nil and CharacterMotion.hasDirectionalSet(set)
    set.authoredWest=set.directional and CharacterMotion.hasAuthoredWestSet(set)
    set.runDirectional=set.directional and CharacterMotion.hasRunSet(set)
    if motionProfile and motionProfile.runPixelsPerFrame then
        assert(set.runDirectional, "Run profile requires eight authored run views: "..file)
    end
    manager.sets[file]=set
    return set
end

local function releaseSet(set,protected,released)
    released=released or {}
    for _,animation in pairs(set or {}) do
        if type(animation)=="table" and animation.image and animation.image.release
            and not (protected and protected[animation.image]) and not released[animation.image] then
            released[animation.image]=true
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
    local keep,protected,released={},{},{}
    for _,file in ipairs(names)do
        keep[file]=true
        for _,animation in pairs(manager.sets[file] or {})do
            if type(animation)=='table' and animation.image then protected[animation.image]=true end
        end
    end
    for file,set in pairs(manager.sets) do
        if not keep[file] then releaseSet(set,protected,released); manager.sets[file]=nil end
    end
    -- Town/NPC transitions must not allocate a complete new sheet set while
    -- irrelevant previous scene sets are still resident. Kept actor art stays.
    for _,file in ipairs(names)do if not manager.sets[file]then loadSet(manager,file)end end
    manager.retainSignature=signature
end

-- Shared with held-item rendering: the hand and body must use the same frame.
function CharacterAnimation.actionFrame(animation,phase)
    local elapsed=math.max(0,tonumber(phase) or 0)
    local playback=animation.playback
    if not playback then return math.floor(elapsed*6)%animation.count+1 end
    if playback.introFrames then
        local intro=playback.introFrames/(playback.fps or 8)
        if elapsed<intro then return math.min(playback.introFrames,math.floor(elapsed*playback.fps)+1) end
        local first=playback.loopStart or playback.introFrames+1
        return first+math.floor((elapsed-intro)*(playback.holdFps or .7))%(animation.count-first+1)
    end
    if playback.duration then
        return math.min(animation.count,math.floor(elapsed/playback.duration*animation.count)+1)
    end
    return math.floor(elapsed*(playback.fps or 6))%animation.count+1
end

-- Menu previews keep a stable presentation actor so pose transitions can
-- advance. Repeat one-shot demonstrations with a quiet pause between them.
function CharacterAnimation.previewSample(state,file,action,clock,animation,direction)
    state=state or {}
    local down=action=='death' or action=='unconscious'
    if state.file~=file or clock<(state.clock or clock)
        or (down and state.direction and direction~=state.direction) then state={file=file,motion={}} end
    if state.action~=action then state.action=action; state.started=clock end
    state.clock=clock; state.direction=direction
    local elapsed=math.max(0,clock-(state.started or clock))
    local duration=animation and animation.playback and animation.playback.duration
    return duration and elapsed%(duration+1) or elapsed,state
end

-- List loaded animations rather than maintaining a second menu-only roster.
-- Directional families use the direction controls; other registered actions,
-- including future additions, remain individually selectable.
function CharacterAnimation.previewActions(set)
    local movement,poses,listed={},{},{}
    local function available(action)
        local animation=set and set[action]
        return type(animation)=='table' and animation.image and animation.quads
    end
    for _,action in ipairs({'idle','walk','run'}) do
        if available(action) then movement[#movement+1]=action; listed[action]=true end
    end
    for _,action in ipairs({'sit','lay','use','melee','swing','ranged','hit','death','unconscious','sweep','carry','tend'}) do
        if available(action) then poses[#poses+1]=action; listed[action]=true end
    end
    local extra={}
    for action in pairs(set or {}) do
        local family=type(action)=='string' and action:match('^(%a+)_')
        local grouped=available(family) and ((family=='run' and set.runDirectional)
            or ((family=='walk' or family=='idle') and set.directional))
        if not listed[action] and not grouped and available(action) then extra[#extra+1]=action end
    end
    table.sort(extra)
    for _,action in ipairs(extra) do poses[#poses+1]=action end
    return movement,poses
end

local function poseFrame(set,action,phase,clock,motion,facing)
    if not motion then return action,nil,facing end
    local now=tonumber(clock) or tonumber(phase) or 0
    local view=poseViews[motion]
    if not view or now<(view.clock or 0) then view={}; poseViews[motion]=view end
    if view.action~=action then
        local old=set[view.action]
        view.exit=action=='idle' and not motion.moving and old and old.playback and old.playback.introFrames and view.action or nil
        view.exitFrom=view.exit and math.min(old.playback.introFrames,
            CharacterAnimation.actionFrame(old,math.max(0,now-(view.started or now)))) or nil
        view.action=action; view.started=now
    end
    view.clock=now
    -- Nearby opponents can move across a fallen unit. Keep the facing from
    -- the start of its collapse through the resting loop until it recovers.
    if action=='death' or action=='unconscious' then
        view.downFacing=view.downFacing or ((facing or 1)<0 and -1 or 1)
    else view.downFacing=nil end
    local poseFacing=view.downFacing or facing
    local elapsed=math.max(0,now-(view.started or now))
    if view.exit then
        local animation=set[view.exit]; local p=animation.playback
        local frame=view.exitFrom-math.floor(elapsed*p.fps)
        if frame>=1 then return view.exit,frame,poseFacing end
        view.exit=nil
    end
    local animation=set[action]
    if not animation or not animation.playback then return action,nil,poseFacing end
    if action=='sit' or action=='lay' then return action,CharacterAnimation.actionFrame(animation,elapsed),poseFacing end
    if action=='unconscious' and set.death and set.death.playback then
        local duration=set.death.playback.duration or .85
        if elapsed<duration then return 'death',CharacterAnimation.actionFrame(set.death,elapsed),poseFacing end
        return action,CharacterAnimation.actionFrame(animation,elapsed-duration),poseFacing
    end
    return action,nil,poseFacing
end

function CharacterAnimation.sample(sets,file,action,maxWidth,maxHeight,facing,phase,clock,motion)
    local set=sets[file]
    local pose
    if set then action,pose,facing=poseFrame(set,action,phase,clock,motion,facing) end
    local directionalMirror=1
    if set and set.directional and motion and (action=="walk" or action=="idle") then
        if action=="walk" then
            if set.runDirectional and motion.locomotionMode=="run" then
                action,directionalMirror=CharacterMotion.directionalRunAction(motion.intentX,motion.intentY)
            else
                action,directionalMirror=CharacterMotion.directionalWalkAction(motion.intentX,motion.intentY,set.authoredWest)
            end
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
    local chore=action=="sweep" or action=="carry" or action=="tend"
    local frameRate=chore and (action=="carry" and 2 or 3) or (action=="hit" and 8.5 or (passiveRate[action] or 6))
    -- All authored directional idles share the motion-spec cadence. Western
    -- sectors must not fall through to the six-fps action default.
    if set.directional and (action=="idle" or action:match("^idle_")~=nil) then frameRate=.65 end
    -- The lay sheets face opposite the rest of the character set, so mirror
    -- the authored two-frame resting loop once to follow the normal facing
    -- convention: +1 faces right, -1 faces left.
    local layCorrection = action == "lay" and not animation.playback
    local frame
    if pose then frame=pose
    elseif isWalkAction(action) and motion and (set.directional or motion.animationDistance~=nil) then
        frame=CharacterMotion.frameForActor(animation.count,motion,set.motionProfile or CharacterMotion.defaults)
    elseif animation.playback then frame=CharacterAnimation.actionFrame(animation,phase or clock)
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
    -- Chore strips reserve a wide transparent cell for the broom stroke.
    -- Their body canvas is one cell-height wide; scaling against the full
    -- tool canvas would shrink the resident when they stop to work.
    local bodyExtent=animation.bodyExtent or (chore and animation.h)
    local scale=bodyExtent and math.min((maxWidth or 76)/bodyExtent,(maxHeight or 96)/bodyExtent)
        or math.min((maxWidth or 76)/animation.w,(maxHeight or 96)/animation.h)*normalize
    -- Central walk sheets were authored opposite to the runtime facing
    -- convention.  Correct only the walking action; idle/pose art keeps its
    -- normal orientation and legacy walk sheets are corrected by their caller.
    local directionalLocomotion=set.directional and (isWalkAction(action) or action:match("^idle")~=nil)
    local walkCorrection = not directionalLocomotion and not animation.playback and (action == "walk" or action == "idle") and -1 or 1
    local drawFacing = (chore and 1 or (directionalLocomotion and directionalMirror or (facing or 1)))
        * (layCorrection and -1 or 1) * walkCorrection
    local anchorOffset = CharacterAnimation.anchorOffsets[file] or 0
    return {image=animation.image,quad=animation.quads[frame],scale=scale,mirror=drawFacing,
        width=animation.w,height=animation.h,originY=animation.originY or animation.h,
        offsetY=anchorOffset+(layCorrection and 20 or 0),action=action,frame=frame}
end

function CharacterAnimation.draw(sets,file,action,x,y,maxWidth,maxHeight,facing,phase,clock,motion)
    local sample=CharacterAnimation.sample(sets,file,action,maxWidth,maxHeight,facing,phase,clock,motion)
    if not sample then return false end
    love.graphics.setColor(1,1,1)
    love.graphics.draw(sample.image,sample.quad,x,y+sample.offsetY,0,sample.scale*sample.mirror,sample.scale,sample.width/2,sample.originY)
    return true
end

return CharacterAnimation
