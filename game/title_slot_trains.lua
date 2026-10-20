local Train=require('game.cinematic_train')
local Trains={travelSeconds=4.6}
-- Hue, saturation multiplier and brightness multiplier for each slot's paint.
-- Slot 2 samples the user's E55 Smoke reference: #6E8DAB (110,141,171).
local paintTones={{-1,1,1},{.582,.357,.671},{.215,.42,.64}}
local mask

function Trains.new()
    return {rows={{elapsed=0,amount=0},{elapsed=0,amount=0},{elapsed=0,amount=0}}}
end

function Trains.update(state,dt,focused,reducedMotion)
    dt=math.max(0,math.min(dt or 0,.1))
    if state.focused~=focused then
        state.focused=focused
        if focused then state.rows[focused].elapsed=0 end
    end
    for index,row in ipairs(state.rows)do
        local active=index==focused
        -- Losing focus restores a still parked train immediately; no departure
        -- frames or fade animation may continue in an unfocused save control.
        row.amount=active and math.min(1,row.amount+dt/.22) or 0
        if reducedMotion then row.elapsed=0
        elseif active then row.elapsed=math.min(row.elapsed+dt,Trains.travelSeconds)
        elseif row.amount==0 then row.elapsed=0 end
    end
end

function Trains.position(row,rect,departureX)
    local scale=rect.h/228
    local finish=rect.x-Train.rearExtent(scale)-12
    local progress=math.min(1,row.elapsed/Trains.travelSeconds)
    return departureX+(finish-departureX)*progress,rect.y+rect.h*.80,scale
end

local function shader()
    if not mask then
        mask=love.graphics.newShader([[
            extern vec2 clipOrigin;
            extern vec2 clipInverseX;
            extern vec2 clipInverseY;
            extern vec2 clipSize;
            extern vec3 paintTone;
            vec3 recolorPaint(vec3 rgb) {
                float value=max(max(rgb.r,rgb.g),rgb.b);
                float minimum=min(min(rgb.r,rgb.g),rgb.b);
                float delta=value-minimum;
                float saturation=value>0.0 ? delta/value : 0.0;
                float hue=0.0;
                if (delta>0.00001) {
                    if (value==rgb.r) hue=mod((rgb.g-rgb.b)/delta,6.0);
                    else if (value==rgb.g) hue=(rgb.b-rgb.r)/delta+2.0;
                    else hue=(rgb.r-rgb.g)/delta+4.0;
                    hue=fract(hue/6.0);
                }
                // Change the red paint while retaining brass, steel, glass,
                // foliage and smoke from the original sprites.
                float redDistance=min(hue,1.0-hue);
                float paint=(1.0-smoothstep(0.065,0.11,redDistance))*smoothstep(0.20,0.45,saturation);
                float signedHue=hue>0.5 ? hue-1.0 : hue;
                float shifted=fract(paintTone.x+signedHue*0.4);
                vec3 pure=clamp(abs(fract(vec3(shifted)+vec3(0.0,2.0/3.0,1.0/3.0))*6.0-3.0)-1.0,0.0,1.0);
                vec3 recolored=value*paintTone.z*mix(vec3(1.0),pure,saturation*paintTone.y);
                return mix(rgb,recolored,paint);
            }
            vec4 effect(vec4 color,Image texture,vec2 uv,vec2 screen) {
                vec2 delta=screen-clipOrigin;
                vec2 p=vec2(dot(delta,clipInverseX),dot(delta,clipInverseY));
                vec2 q=abs(p-clipSize*.5)-(clipSize*.5-vec2(12.0));
                float distance=length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-12.0;
                vec4 pixel=Texel(texture,uv)*color;
                if (paintTone.x>=0.0) pixel.rgb=recolorPaint(pixel.rgb);
                pixel.a*=1.0-smoothstep(-0.6,0.6,distance);
                // A soft dark backing keeps the save description readable.
                pixel.rgb*=mix(0.36,1.0,smoothstep(clipSize.x*.30,clipSize.x*.62,p.x));
                return pixel;
            }
        ]])
    end
    return mask
end

function Trains.draw(state,index,rect,departureX,scenery,idleAlpha)
    local g=love.graphics
    local x,y=g.transformPoint(rect.x,rect.y)
    local xx,xy=g.transformPoint(rect.x+rect.w,rect.y)
    local yx,yy=g.transformPoint(rect.x,rect.y+rect.h)
    local ax,ay=(xx-x)/rect.w,(xy-y)/rect.w
    local bx,by=(yx-x)/rect.h,(yy-y)/rect.h
    local determinant=ax*by-ay*bx
    if math.abs(determinant)<.00001 then return end
    -- transformPoint uses graphics units, but the shader receives framebuffer
    -- pixels. Match the active target's density, including offscreen canvases.
    local target=g.getCanvas()
    local pixelScale=(target and target:getDPIScale()) or g.getDPIScale() or 1
    local clip=shader()
    clip:send('clipOrigin',{x*pixelScale,y*pixelScale})
    clip:send('clipInverseX',{by/determinant/pixelScale,-bx/determinant/pixelScale})
    clip:send('clipInverseY',{-ay/determinant/pixelScale,ax/determinant/pixelScale})
    clip:send('clipSize',{rect.w,rect.h})
    clip:send('paintTone',paintTones[1])
    g.push('all')
    g.setShader(clip)
    local row=state.rows[index]
    local couplerX,railY,scale=Trains.position(row,rect,departureX)
    local background=scenery.introBackground
    if background then
        local width,height=background:getDimensions()
        local zoom=math.max(rect.w/width,rect.h/height)
        g.setColor(.60,.53,.44,.55+row.amount*.30)
        g.draw(background,rect.x,railY-height*Train.railRatio*zoom,0,zoom,zoom)
    end
    clip:send('paintTone',paintTones[index])
    if row.amount<1 then Train.draw(scenery,departureX,railY,scale,0,(idleAlpha or .40)*(1-row.amount)) end
    if row.amount>0 then Train.draw(scenery,couplerX,railY,scale,row.elapsed,row.amount) end
    g.pop()
end

return Trains
