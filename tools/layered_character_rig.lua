-- Offline sprite authoring only. Runtime consumes ordinary baked strips.
local Rig = {}
local walks = {x={30,14,-2,-18,-34,-19,3,25},lift={0,0,0,0,0,7,17,12},
    bob={0,3,0,-2,0,3,0,-2},lean={-.006,.003,-.009,-.014,-.006,.003,-.009,-.014}}
local runs = {x={37.5,0,-31,-34,-23,0,28,40},lift={0,0,6,21,24,24,18,6},
    bob={0,3,-3,-5,0,3,-3,-5},lean={.018,.023,.010,.006,.018,.023,.010,.006}}

local function inside(poly,x,y)
    local hit,j=false,#poly
    for i=1,#poly do
        local a,b=poly[i],poly[j]
        if (a[2]>y)~=(b[2]>y) and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1] then hit=not hit end
        j=i
    end
    return hit
end

function Rig.new(source,config)
    local self={config=config,layers={},source=source}
    local body=love.image.newImageData(512,512)
    for i,def in ipairs(config.legs) do
        local pixels=love.image.newImageData(512,512)
        for y=0,511 do for x=0,511 do
            if inside(def.textureMask or def.mask,x,y) then pixels:setPixel(x,y,source:getPixel(x,y)) end
        end end
        self.layers[i]={image=love.graphics.newImage(pixels),data=pixels,def=def}
    end
    for y=0,511 do for x=0,511 do
        local remove=false
        for _,def in ipairs(config.legs) do
            if y>=def.bodyCutY and inside(def.mask,x,y) then remove=true end
        end
        if not remove then body:setPixel(x,y,source:getPixel(x,y)) end
    end end
    self.body=love.graphics.newImage(body);self.bodyData=body
    return setmetatable(self,{__index=Rig})
end

local function smooth(v) v=math.max(0,math.min(1,v));return v*v*(3-2*v) end

function Rig:drawLeg(layer,phase,bodyY,far,clip)
    local def,c=layer.def,self.config
    local hx,hy=def.targetHipX or def.hipX,def.hipY+bodyY
    local ax=hx+c.forward[1]*clip.x[phase]
    local ay=def.groundAnkleY+c.forward[2]*clip.x[phase]-clip.lift[phase]
    local dx,dy=ax-hx,ay-hy
    local distance=math.max(.001,math.sqrt(dx*dx+dy*dy))
    local l1,l2=def.upperLength or 26,def.lowerLength or 27
    local along=(l1*l1-l2*l2+distance*distance)/(2*distance)
    local bend=math.sqrt(math.max(0,l1*l1-along*along))*(c.kneeBend or c.forward[1])
    local kx=hx+dx/distance*along+dy/distance*bend
    local ky=hy+dy/distance*along-dx/distance*bend
    local function bone(x,y,sourceY,x1,y1,x2,y2,length)
        local vx,vy=x2-x1,y2-y1
        local norm=math.max(.001,math.sqrt(vx*vx+vy*vy))
        return x1+vx*(y-sourceY)/length+vy/norm*(x-def.hipX),
            y1+vy*(y-sourceY)/length-vx/norm*(x-def.hipX)
    end
    local function position(x,y)
        local tx,ty=bone(x,y,def.hipY,hx,hy,kx,ky,def.kneeY-def.hipY)
        local sx,sy=bone(x,y,def.kneeY,kx,ky,ax,ay,def.ankleY-def.kneeY)
        local knee=smooth((y-def.kneeY+7)/14)
        local px,py=tx+(sx-tx)*knee,ty+(sy-ty)*knee
        local angle=phase>=6 and -.16*c.forward[1] or 0
        local fx=ax+math.cos(angle)*(x-def.hipX)-math.sin(angle)*(y-def.ankleY)
        local fy=ay+math.sin(angle)*(x-def.hipX)+math.cos(angle)*(y-def.ankleY)
        local ankle=smooth((y-def.ankleY+12)/14)
        return px+(fx-px)*ankle,py+(fy-py)*ankle
    end
    local vertices={}
    for y=def.top,def.bottom,2 do for _,x in ipairs({def.left,def.right}) do
        local px,py=position(x,y)
        vertices[#vertices+1]={px,py,x/512,y/512,1,1,1,1}
    end end
    local mesh=love.graphics.newMesh(vertices,'strip','stream');mesh:setTexture(layer.image)
    local shade=far and .8 or 1
    love.graphics.setColor(shade,shade,shade,1);love.graphics.draw(mesh);mesh:release()
end

function Rig:draw(index,mode)
    local clip=mode=='run' and runs or walks
    if mode=='run' and self.config.runLift then
        clip={x=clip.x,lift=self.config.runLift,bob=clip.bob,lean=clip.lean}
    end
    for _,part in ipairs(self.config.drawOrder) do
        local phase=part.physical=='left' and index or (index+3)%8+1
        self:drawLeg(self.layers[part.layer],phase,clip.bob[index],part.far,clip)
    end
    love.graphics.setColor(1,1,1,1)
    local cx,cy=self.config.bodyPivot[1],self.config.bodyPivot[2]
    love.graphics.draw(self.body,cx,cy+clip.bob[index],clip.lean[index]*self.config.forward[1],1,1,cx,cy)
end

return Rig
