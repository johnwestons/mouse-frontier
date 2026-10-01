local UIStyle = {}

local PATH = "ui-layout-presets.txt"
local SLOT_COUNT = 3
local active
local scopes = {}
local colorShaders=setmetatable({},{__mode="k"})
local unpackValues=table.unpack or unpack
local COLOR_STEPS=16
local COLOR_SHADER=[[
extern vec3 uiColorSteps[16];
extern float uiColorCount;

vec3 adjustUIColor(vec3 rgb, vec3 adjustment) {
    float value = max(rgb.r, max(rgb.g, rgb.b));
    float minimum = min(rgb.r, min(rgb.g, rgb.b));
    float delta = value - minimum;
    float hue = 0.0;
    if (delta > 0.00001) {
        if (value == rgb.r) hue = mod((rgb.g - rgb.b) / delta, 6.0);
        else if (value == rgb.g) hue = (rgb.b - rgb.r) / delta + 2.0;
        else hue = (rgb.r - rgb.g) / delta + 4.0;
        hue /= 6.0;
    }
    hue = fract(hue + adjustment.x);
    float saturation = value <= 0.0 ? 0.0 : delta / value;
    saturation = max(adjustment.z, clamp(saturation * adjustment.y, 0.0, 1.0));
    vec3 pureHue = clamp(abs(fract(vec3(hue) + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return value * mix(vec3(1.0), pureHue, saturation);
}

vec4 effect(vec4 color, Image texture, vec2 textureCoords, vec2 screenCoords) {
    vec4 pixel = Texel(texture, textureCoords) * color;
    for (int i = 0; i < 16; i++) {
        if (float(i) < uiColorCount) pixel.rgb = adjustUIColor(pixel.rgb, uiColorSteps[i]);
    }
    return pixel;
}
]]

local function colorChanged(style)
    return style.hue~=0 or style.saturation~=1 or style.colorTint~=0
end

local function colorSteps(style)
    local steps={}
    if style and colorChanged(style) then steps[#steps+1]={style.hue,style.saturation,style.colorTint} end
    for i=#scopes,1,-1 do
        local inherited=scopes[i].style
        if colorChanged(inherited) and #steps<COLOR_STEPS then
            steps[#steps+1]={inherited.hue,inherited.saturation,inherited.colorTint}
        end
    end
    return steps
end

local function setColorSteps(shader,steps)
    local values={}
    for i=1,COLOR_STEPS do values[i]=steps[i] or {0,1,0} end
    shader:send("uiColorSteps",unpackValues(values))
    shader:send("uiColorCount",#steps)
end

local function colorShader(gfx)
    local cached=colorShaders[gfx]
    if cached then return cached.shader,cached.error end
    if not gfx.newShader or not gfx.getShader or not gfx.setShader then
        return nil,"Sprite color adjustments are unavailable on this graphics device."
    end
    local ok,shader=pcall(gfx.newShader,COLOR_SHADER)
    local entry={shader=ok and shader or nil,error=not ok and tostring(shader) or nil}
    colorShaders[gfx]=entry
    return entry.shader,entry.error
end

local function clamp(value, low, high, fallback)
    value = tonumber(value)
    if not value or value ~= value or math.abs(value) == math.huge then value = fallback end
    return math.max(low, math.min(high, value))
end

local function token(value, fallback)
    value = tostring(value or fallback or "default")
    if not value:match("^[%w_-]+$") then return fallback or "default" end
    return value
end

local function defaults()
    return {
        x=0, y=0, scale=1, rotation=0, textScale=1, hue=0, saturation=1, colorTint=0,
        frame=0, font="regular", fontOverride=false, iconScale=1, iconVariant="default",
    }
end

local function normalize(source)
    source = type(source) == "table" and source or {}
    return {
        -- Wide mobile canvases can extend beyond the 960px reference viewport.
        -- Keep positions finite without stopping a drag halfway across a screen.
        x=clamp(source.x,-4096,4096,0), y=clamp(source.y,-4096,4096,0),
        scale=clamp(source.scale,.45,2.5,1), rotation=clamp(source.rotation,-180,180,0),
        textScale=clamp(source.textScale,.5,2.5,1), hue=clamp(source.hue,-.5,.5,0),
        saturation=clamp(source.saturation,0,2,1), colorTint=clamp(source.colorTint,0,1,0), frame=math.floor(clamp(source.frame,0,4,0)),
        font=(source.font=="bold" and "bold" or "regular"),
        fontOverride=source.fontOverride==true or tonumber(source.fontOverride)==1
            or (source.fontOverride==nil and source.font=="bold"),
        iconScale=clamp(source.iconScale,.5,2,1),
        iconVariant=token(source.iconVariant,"default"),
    }
end

local function normalizedScreen(value)
    value = token(value,"game")
    return value
end

local function profile()
    local slots = {}
    for i=1,SLOT_COUNT do slots[i]={name="Preset "..i,elements={}} end
    return slots
end

local function safeScreenKey(value)
    return normalizedScreen(value)
end

local function hsvTint(r,g,b,hueShift,saturationScale,colorTint)
    local maxValue=math.max(r,g,b)
    local minValue=math.min(r,g,b)
    local delta=maxValue-minValue
    local hue=0
    if delta>0 then
        if maxValue==r then hue=((g-b)/delta)%6
        elseif maxValue==g then hue=(b-r)/delta+2
        else hue=(r-g)/delta+4 end
        hue=hue/6
    end
    local saturation=maxValue==0 and 0 or delta/maxValue
    hue=(hue+hueShift)%1
    saturation=math.max(colorTint or 0,math.max(0,math.min(1,saturation*saturationScale)))
    local chroma=maxValue*saturation
    local section=hue*6
    local x=chroma*(1-math.abs(section%2-1))
    local rr,gg,bb
    if section<1 then rr,gg,bb=chroma,x,0
    elseif section<2 then rr,gg,bb=x,chroma,0
    elseif section<3 then rr,gg,bb=0,chroma,x
    elseif section<4 then rr,gg,bb=0,x,chroma
    elseif section<5 then rr,gg,bb=x,0,chroma
    else rr,gg,bb=chroma,0,x end
    local m=maxValue-chroma
    return rr+m,gg+m,bb+m
end

local function transformPoint(bounds, style, x, y)
    local cx,cy=bounds.x+bounds.w/2,bounds.y+bounds.h/2
    local dx,dy=x-cx,y-cy
    local radians=math.rad(style.rotation)
    local sx,sy=dx*style.scale,dy*style.scale
    local rx=sx*math.cos(radians)-sy*math.sin(radians)
    local ry=sx*math.sin(radians)+sy*math.cos(radians)
    return cx+style.x+rx,cy+style.y+ry
end

local function rectanglePoints(rect)
    return {
        {rect.x,rect.y},{rect.x+rect.w,rect.y},
        {rect.x,rect.y+rect.h},{rect.x+rect.w,rect.y+rect.h},
    }
end

local function pointsBounds(points)
    local left,top,right,bottom=math.huge,math.huge,-math.huge,-math.huge
    for _,point in ipairs(points) do
        local x,y=point[1],point[2]
        left,top,right,bottom=math.min(left,x),math.min(top,y),math.max(right,x),math.max(bottom,y)
    end
    return {x=left,y=top,w=right-left,h=bottom-top}
end

local function transformPoints(points,style,bounds)
    for _,point in ipairs(points) do
        point[1],point[2]=transformPoint(bounds,style,point[1],point[2])
    end
    return points
end

local function transformRect(rect, style, bounds)
    return pointsBounds(transformPoints(rectanglePoints(rect),style,bounds or rect))
end

local function transformedScopeRect(rect,style,bounds,ancestors)
    -- Keep the actual corners until every transform is applied. Repeatedly
    -- rotating an axis-aligned bounding box grows it beyond the drawn UI.
    local points=transformPoints(rectanglePoints(rect),style,bounds)
    for i=#ancestors,1,-1 do
        transformPoints(points,ancestors[i].style,ancestors[i].bounds)
    end
    return pointsBounds(points)
end

local function copyElements(elements)
    local copy={}
    for key,value in pairs(elements or {}) do
        if type(key)=="string" and key:match("^[%w_-]+%.[%w_-]+$") and type(value)=="table" then
            copy[key]=normalize(value)
        end
    end
    return copy
end

local function inversePoint(rect,style,x,y)
    local cx,cy=rect.x+rect.w/2,rect.y+rect.h/2
    local dx,dy=x-cx-style.x,y-cy-style.y
    local radians=-math.rad(style.rotation)
    local rx=dx*math.cos(radians)-dy*math.sin(radians)
    local ry=dx*math.sin(radians)+dy*math.cos(radians)
    return cx+rx/style.scale,cy+ry/style.scale
end

local function inverseDelta(style,x,y)
    local radians=-math.rad(style.rotation)
    return (x*math.cos(radians)-y*math.sin(radians))/style.scale,
        (x*math.sin(radians)+y*math.cos(radians))/style.scale
end

local function contains(rect,x,y)
    return x>=rect.x and x<=rect.x+rect.w and y>=rect.y and y<=rect.y+rect.h
end

function UIStyle.new(options)
    options=options or {}
    local fs=assert(options.filesystem,"UI layout editor requires a filesystem")
    local manager={filesystem=fs,screen=options.screen or function() return "game" end,
        slots=profile(),activeSlot=1,liveRects={},liveRegions={},selected="journeyHud",dirty=false}

    function manager:screenId() return safeScreenKey(self.screen()) end
    function manager:elementKey(element,screen)
        return safeScreenKey(screen or self:screenId()).."."..token(element,"element")
    end
    function manager:get(element,screen)
        local key=self:elementKey(element,screen)
        local stored=self.slots[self.activeSlot].elements[key]
        return normalize(stored or defaults())
    end
    function manager:inversePoint(x,y,element,bounds,screen)
        return inversePoint(bounds or {x=0,y=0,w=960,h=720},self:get(element,screen),x,y)
    end
    function manager:transformRect(rect,element,bounds,screen)
        return transformRect(rect,self:get(element,screen),bounds or rect)
    end
    function manager:beginFrame()
        self.liveRects={}; self.liveRegions={}
    end
    function manager:hitElement(element,x,y,screen)
        local regions=self.liveRegions[self:elementKey(element,screen)] or {}
        for i=#regions,1,-1 do
            local region=regions[i]
            local lx,ly=x,y
            for _,ancestor in ipairs(region.ancestors) do
                lx,ly=inversePoint(ancestor.bounds,ancestor.style,lx,ly)
            end
            lx,ly=inversePoint(region.bounds,region.style,lx,ly)
            if contains(region.bounds,lx,ly) then return true,region end
        end
        return false
    end
    function manager:moveDelta(element,dx,dy,screen)
        local regions=self.liveRegions[self:elementKey(element,screen)] or {}
        local region=regions[#regions]
        if region then
            for _,ancestor in ipairs(region.ancestors) do dx,dy=inverseDelta(ancestor.style,dx,dy) end
        end
        return dx,dy
    end
    function manager:snapshotSlot()
        return copyElements(self.slots[self.activeSlot].elements)
    end
    function manager:restoreSlot(snapshot,persist)
        if type(snapshot)~="table" then return false end
        self.slots[self.activeSlot].elements=copyElements(snapshot)
        self.dirty=true
        if persist==false then return true end
        return self:save()
    end
    function manager:set(element,values,persist,screen)
        local key=self:elementKey(element,screen)
        local nextValue=self:get(element,screen)
        for name,value in pairs(values or {}) do nextValue[name]=value end
        if values and values.font~=nil and values.fontOverride==nil then nextValue.fontOverride=true end
        self.slots[self.activeSlot].elements[key]=normalize(nextValue)
        self.dirty=true
        if persist==false then return true end
        return self:save()
    end
    function manager:resetElement(element,persist,screen)
        self.slots[self.activeSlot].elements[self:elementKey(element,screen)]=nil
        self.dirty=true
        if persist==false then return true end
        return self:save()
    end
    function manager:resetScreen(screen,persist)
        local prefix=safeScreenKey(screen or self:screenId()).."."
        local elements=self.slots[self.activeSlot].elements
        for key in pairs(elements) do if key:sub(1,#prefix)==prefix then elements[key]=nil end end
        self.dirty=true
        if persist==false then return true end
        return self:save()
    end
    function manager:useSlot(index)
        index=math.floor(clamp(index,1,SLOT_COUNT,1))
        self.activeSlot=index
        self.dirty=true
        return self:save()
    end
    function manager:load()
        local ok,source=pcall(self.filesystem.read,PATH)
        if not ok or type(source)~="string" then return false end
        local slots=profile()
        local activeSlot=1
        for line in source:gmatch("[^\r\n]+") do
            local activeValue=line:match("^ACTIVE%s+(%d+)$")
            if activeValue then activeSlot=math.floor(clamp(activeValue,1,SLOT_COUNT,1)) end
            local slot,name=line:match("^SLOT%s+(%d+)%s+([%w_-]+)$")
            if slot and slots[tonumber(slot)] then slots[tonumber(slot)].name=token(name,"Preset "..slot) end
            local values={}
            for word in line:gmatch("%S+") do values[#values+1]=word end
            if values[1]=="ELEMENT" and #values>=15 then
                local index=tonumber(values[2]); local screen=token(values[3]); local element=token(values[4])
                if slots[index] then
                    local key=screen.."."..element
                    slots[index].elements[key]=normalize({x=values[5],y=values[6],scale=values[7],rotation=values[8],
                        textScale=values[9],hue=values[10],saturation=values[11],frame=values[12],font=values[13],
                        iconScale=values[14],iconVariant=values[15],colorTint=values[16],fontOverride=values[17]})
                end
            end
        end
        self.slots=slots; self.activeSlot=activeSlot; self.dirty=false; self.lastSaveError=nil
        return true
    end
    function manager:save()
        local rows={"ACTIVE "..self.activeSlot}
        for index,slot in ipairs(self.slots) do
            rows[#rows+1]="SLOT "..index.." "..token(slot.name,"Preset_"..index)
            local keys={}
            for key in pairs(slot.elements) do keys[#keys+1]=key end
            table.sort(keys)
            for _,key in ipairs(keys) do
                local screen,element=key:match("^([%w_-]+)%.([%w_-]+)$")
                if screen and element then
                    local value=normalize(slot.elements[key])
                    rows[#rows+1]=string.format("ELEMENT %d %s %s %.3f %.3f %.3f %.3f %.3f %.3f %.3f %d %s %.3f %s %.3f %d",
                        index,screen,element,value.x,value.y,value.scale,value.rotation,value.textScale,value.hue,
                        value.saturation,value.frame,value.font,value.iconScale,value.iconVariant,value.colorTint,value.fontOverride and 1 or 0)
                end
            end
        end
        local ok,saved,message=pcall(self.filesystem.write,PATH,table.concat(rows,"\n"))
        local success=ok and saved==true
        self.dirty=not success
        self.lastSaveError=not success and tostring(ok and (message or "Settings could not be saved.") or saved) or nil
        return success,self.lastSaveError
    end
    function manager:scope(element,bounds,draw)
        local screen=self:screenId()
        local style=self:get(element,screen)
        bounds=bounds or {x=0,y=0,w=960,h=720}
        local cx,cy=bounds.x+bounds.w/2,bounds.y+bounds.h/2
        local transformed=transformedScopeRect(bounds,style,bounds,scopes)
        local liveKey=self:elementKey(element,screen)
        local ancestors={}
        for _,ancestor in ipairs(scopes) do ancestors[#ancestors+1]={style=ancestor.style,bounds=ancestor.bounds} end
        local regions=self.liveRegions[liveKey] or {}
        regions[#regions+1]={bounds=bounds,style=style,ancestors=ancestors}
        self.liveRegions[liveKey]=regions
        local previous=self.liveRects[liveKey]
        if previous then
            local left,top=math.min(previous.x,transformed.x),math.min(previous.y,transformed.y)
            local right,bottom=math.max(previous.x+previous.w,transformed.x+transformed.w),math.max(previous.y+previous.h,transformed.y+transformed.h)
            transformed={x=left,y=top,w=right-left,h=bottom-top}
        end
        self.liveRects[liveKey]=transformed
        local gfx=love.graphics
        gfx.push("all")
        local transformApplied=true
        local previousOrigin,previousScale=gfx.origin,gfx.scale
        local function applyTransform()
            gfx.translate(cx+style.x,cy+style.y)
            gfx.rotate(math.rad(style.rotation))
            previousScale(style.scale,style.scale)
            gfx.translate(-cx,-cy)
        end
        applyTransform()
        gfx.origin=function(...)
            local result=previousOrigin(...)
            transformApplied=false
            return result
        end
        gfx.scale=function(...)
            local result=previousScale(...)
            if not transformApplied then applyTransform(); transformApplied=true end
            return result
        end
        local previousSetColor=gfx.setColor
        local parentSteps=colorSteps()
        local steps=colorSteps(style)
        local shader,previousShader
        local inheritedFallback=scopes[#scopes] and scopes[#scopes].colorFallback
        if #steps>0 and not inheritedFallback then
            local candidate,compileError=colorShader(gfx)
            if compileError then self.lastColorError=compileError end
            previousShader=gfx.getShader and gfx.getShader()
            -- Preserve scene-specific effects. The normal UI shader transforms
            -- sampled sprite pixels as well as primitive/text vertex colors.
            if candidate and (not previousShader or previousShader==candidate) then
                local shaderOK,shaderError=pcall(function()
                    setColorSteps(candidate,steps)
                    gfx.setShader(candidate)
                end)
                if shaderOK then shader=candidate; self.lastColorError=nil
                else
                    self.lastColorError=tostring(shaderError)
                    if previousShader==candidate then pcall(setColorSteps,candidate,parentSteps) end
                end
            end
        end
        local colorFallback=not shader and colorChanged(style)
        if colorFallback then
            gfx.setColor=function(r,g,b,a,...)
                if type(r)=="table" then
                    local color=r
                    local nr,ng,nb=hsvTint(color[1] or 1,color[2] or 1,color[3] or 1,style.hue,style.saturation,style.colorTint)
                    local adjusted={nr,ng,nb,color[4]}
                    return previousSetColor(adjusted,...)
                end
                local nr,ng,nb=hsvTint(r or 1,g or 1,b or 1,style.hue,style.saturation,style.colorTint)
                return previousSetColor(nr,ng,nb,a,...)
            end
        end
        scopes[#scopes+1]={manager=self,element=element,screen=screen,style=style,bounds=bounds,
            colorFallback=colorFallback or inheritedFallback}
        local ok,result=pcall(draw)
        scopes[#scopes]=nil
        gfx.setColor=previousSetColor
        gfx.origin=previousOrigin; gfx.scale=previousScale
        if shader and previousShader==shader then setColorSteps(shader,parentSteps) end
        gfx.pop()
        if not ok then error(result) end
        return result
    end

    manager:load()
    active=manager
    return manager
end

function UIStyle.scope(element,bounds,draw)
    if active then return active:scope(element,bounds,draw) end
    return draw()
end

function UIStyle.currentTextStyle()
    local textScale=1
    for _,entry in ipairs(scopes) do textScale=textScale*entry.style.textScale end
    local font
    for i=#scopes,1,-1 do
        if scopes[i].style.fontOverride then font=scopes[i].style.font; break end
    end
    return textScale,font
end

function UIStyle.frame(kind)
    for i=#scopes,1,-1 do
        if scopes[i].style.frame>0 then return scopes[i].style.frame end
    end
    return kind
end

function UIStyle.iconScale()
    local scale=1
    for _,scope in ipairs(scopes) do scale=scale*scope.style.iconScale end
    return scale
end

function UIStyle.iconVariant()
    for i=#scopes,1,-1 do
        if scopes[i].style.iconVariant~="default" then return scopes[i].style.iconVariant end
    end
    return "default"
end

function UIStyle.transformRect(rect)
    local scope=scopes[#scopes]
    if not scope then return rect end
    local points=rectanglePoints(rect)
    for i=#scopes,1,-1 do transformPoints(points,scopes[i].style,scopes[i].bounds) end
    local result=pointsBounds(points)
    for key,value in pairs(rect) do if result[key]==nil then result[key]=value end end
    return result
end

function UIStyle.inversePoint(x,y,element,bounds)
    if active and #scopes>0 then
        for _,scope in ipairs(scopes) do
            x,y=inversePoint(scope.bounds,scope.style,x,y)
        end
        return x,y
    end
    if active and element then return active:inversePoint(x,y,element,bounds) end
    return x,y
end

function UIStyle.transformRectFor(element,bounds,rect)
    if active and element then return active:transformRect(rect,element,bounds) end
    return {x=rect.x,y=rect.y,w=rect.w,h=rect.h}
end

function UIStyle.manager() return active end

return UIStyle
