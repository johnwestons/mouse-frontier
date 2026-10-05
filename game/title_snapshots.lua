-- Authored four-pose memories, held still in the title menu's side bays.
local TitleSnapshots = {}

TitleSnapshots.presets = {
    -- One content envelope covers all four poses, with eight source pixels
    -- of breathing room. Normalized bounds also fit the resized mobile atlas.
    {id="share-water", label="SHARE WATER", crop={61/768,42/512,707/768,463/512}},
    {id="share-food", label="SHARE FOOD", crop={0,185/627,1,417/627}},
    {id="bandage", label="BANDAGE A WOUND", crop={13/627,79/627,614/627,513/627}},
    {id="laugh", label="SHARE A LAUGH", crop={0,115/627,1,432/627}},
    {id="help-walk", label="HELP THEM WALK", crop={0,49/611,1,514/611}},
    {id="handshake", label="MEET WITH TRUST", crop={0,115/627,1,445/627}},
    {id="seedling-care", label="TEND A SEEDLING", crop={0,114/627,1,503/627}},
    {id="share-shelter", label="SHARE SHELTER", crop={40/627,4/627,578/627,592/627}},
    {id="radio-repair", label="REPAIR A RADIO", crop={62/627,74/627,540/627,475/627}},
    {id="warm-kettle", label="PREPARE TEA", crop={34/627,91/627,559/627,452/627}},
    {id="shared-haul", label="MOVE SUPPLIES TOGETHER", crop={38/627,72/627,555/627,483/627}},
    {id="lantern-melody", label="PLAY A TUNE", crop={34/627,91/627,559/627,444/627}},
    {id="route-map", label="PLAN THE ROUTE", crop={42/627,80/627,551/627,466/627}},
    {id="herbal-delivery", label="SHARE MEDICINAL HERBS", crop={40/627,70/627,553/627,494/627}},
    {id="roadside-repair", label="REPAIR A CART", crop={41/627,99/627,552/627,430/627}},
    {id="quiet-garden", label="TEND A SEEDLING", crop={41/627,85/627,552/627,455/627}},
    {id="camp-supper", label="SHARE A MEAL", crop={41/627,77/627,552/627,472/627}},
    {id="lantern-repair", label="FIX A LANTERN", crop={38/627,85/627,555/627,456/627}},
    {id="shared-bandages", label="BANDAGE A FRIEND", crop={41/627,56/627,552/627,515/627}},
    {id="fair-trade", label="TRADE KINDLY", crop={41/627,81/627,545/627,471/627}},
    {id="boiler-repair", label="REPAIR A BOILER", crop={39/627,94/627,546/627,440/627}},
    {id="river-route", label="FIND A SAFE FORD", crop={34/627,78/627,559/627,470/627}},
    {id="trailmarkers", label="MARK A TRAIL", crop={41/627,79/627,551/627,468/627}},
    {id="signal-lesson", label="LEARN A SIGNAL", crop={40/627,141/627,546/627,345/627}},
    {id="station-map", label="READ THE ROUTE", crop={41/627,90/627,545/627,446/627}},
}

local SCENE_SECONDS = 36
local POSE_DISSOLVE_SECONDS = 3
local POSE_STARTS = {7, 15, 23}
local MEMORY_OPACITY = .72

local function smoothstep(value)
    value=math.max(0,math.min(1,value))
    return value*value*(3-2*value)
end

-- No 4 -> 1 pose loop: each memory finishes its gesture and rests until it
-- disappears. Distinct scenes never overlap, and the two bays change apart.
function TitleSnapshots.playback(clock,side)
    side=math.floor(side or 0)
    local elapsed=math.max(0,clock or 0)+side*18
    local cycle=math.floor(elapsed/SCENE_SECONDS)
    local sceneTime=elapsed%SCENE_SECONDS
    local preset=TitleSnapshots.presets[((cycle+side*3)%#TitleSnapshots.presets)+1]
    local opacity=1
    if sceneTime<4 then
        opacity=smoothstep(sceneTime/4)
    elseif sceneTime>=31 then
        opacity=1-smoothstep((sceneTime-31)/4)
    end

    local frame,nextFrame,blend=1,1,0
    for index,start in ipairs(POSE_STARTS) do
        if sceneTime>=start+POSE_DISSOLVE_SECONDS then
            frame=index+1
            nextFrame=frame
        elseif sceneTime>=start then
            frame=index
            nextFrame=index+1
            blend=smoothstep((sceneTime-start)/POSE_DISSOLVE_SECONDS)
            break
        else
            break
        end
    end
    return {id=preset.id,label=preset.label,crop=preset.crop,sceneTime=sceneTime,cycle=cycle,
        frame=frame,nextFrame=nextFrame,frameBlend=blend,alpha=opacity*MEMORY_OPACITY}
end

local spriteGeometry=setmetatable({}, {__mode="k"})
local memoryShader

local function getMemoryShader()
    if memoryShader then return memoryShader end
    memoryShader=love.graphics.newShader([[
        extern vec2 frames;
        extern vec2 pixelInset;
        extern vec4 contentRect;
        extern float poseBlend;

        vec4 effect(vec4 color, Image texture, vec2 textureCoordinates, vec2 screenCoordinates) {
            vec2 frameUV=textureCoordinates*vec2(4.0,1.0);
            vec2 localUV=(frameUV-contentRect.xy)/contentRect.zw;
            vec2 uv=clamp(frameUV,pixelInset,vec2(1.0)-pixelInset);
            vec4 first=Texel(texture,vec2((uv.x+frames.x)/4.0,uv.y));
            vec4 second=Texel(texture,vec2((uv.x+frames.y)/4.0,uv.y));

            // Interpolate once in premultiplied space so shared opaque pixels
            // retain their opacity, instead of darkening under stacked draws.
            vec4 pixel=mix(vec4(first.rgb*first.a,first.a),
                           vec4(second.rgb*second.a,second.a),poseBlend);
            pixel.rgb=pixel.rgb/max(pixel.a,0.00001);
            pixel.rgb=mix(pixel.rgb,vec3(0.96,0.84,0.66),0.10)*color.rgb;
            float edge=min(min(localUV.x,1.0-localUV.x),min(localUV.y,1.0-localUV.y));
            pixel.a*=smoothstep(0.0,0.14,edge)*color.a;
            return pixel;
        }
    ]])
    return memoryShader
end

local function geometryFor(sprite,crop)
    local cached=spriteGeometry[sprite]
    if not cached then
        local width,height=sprite:getDimensions()
        local frameWidth=width/4
        local croppedWidth,croppedHeight=frameWidth*crop[3],height*crop[4]
        cached={width=croppedWidth,height=croppedHeight,frameWidth=frameWidth,frameHeight=height,
            quad=love.graphics.newQuad(frameWidth*crop[1],height*crop[2],croppedWidth,croppedHeight,width,height)}
        spriteGeometry[sprite]=cached
    end
    return cached
end

function TitleSnapshots.draw(options)
    options=options or {}
    local x,y=options.x or 0,options.y or 0
    local width,height=options.width or 360,options.height or 470
    local playback=TitleSnapshots.playback(options.clock,options.side)
    local sprite=options.sprites and options.sprites[playback.id]
    playback.height=height
    playback.authoredSprite=sprite~=nil
    if not sprite or width<=0 or height<=0 or playback.alpha<=0 then return playback end

    local geometry=geometryFor(sprite,playback.crop)
    local scale=math.min(width/geometry.width,height/geometry.height)
    local shader=getMemoryShader()
    shader:send("frames",{playback.frame-1,playback.nextFrame-1})
    shader:send("pixelInset",{.5/geometry.frameWidth,.5/geometry.frameHeight})
    shader:send("contentRect",playback.crop)
    shader:send("poseBlend",playback.frameBlend)

    -- A single, centered draw always fits inside the supplied bay. Preserve
    -- its caller's shader, blend mode, color and clipping state.
    love.graphics.push("all")
    love.graphics.setShader(shader)
    love.graphics.setBlendMode("alpha","alphamultiply")
    love.graphics.setColor(1,1,1,playback.alpha)
    love.graphics.draw(sprite,geometry.quad,x+width/2,y+height/2,0,scale,scale,
        geometry.width/2,geometry.height/2)
    love.graphics.pop()
    return playback
end

return TitleSnapshots
