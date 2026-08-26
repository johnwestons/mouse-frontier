local Camera = {
    zoom=1,panX=0,panY=0,panning=false,lastX=0,lastY=0,
    minZoom=1,maxZoom=2.25,width=960,height=720,scope="default",scopes={}
}

local function clamp(value,low,high)
    return math.max(low,math.min(high,value))
end

function Camera:configure(width,height)
    self.width,self.height=width or self.width,height or self.height
    self:_clampPan()
end

function Camera:_saveScope()
    self.scopes[self.scope]={zoom=self.zoom,panX=self.panX,panY=self.panY}
end

function Camera:setScope(scope)
    scope=scope or "default"
    if scope==self.scope then return false end
    self:_saveScope()
    self.scope=scope
    local saved=self.scopes[scope]
    self.zoom=saved and saved.zoom or 1
    self.panX=saved and saved.panX or 0
    self.panY=saved and saved.panY or 0
    self.panning=false
    self:_clampPan()
    return true
end

function Camera:isActive()
    return math.abs(self.zoom-1)>.001 or math.abs(self.panX)>.001 or math.abs(self.panY)>.001
end

function Camera:_clampPan()
    local limitX=self.width*.5*math.max(0,self.zoom-1)
    local limitY=self.height*.5*math.max(0,self.zoom-1)
    self.panX=clamp(self.panX,-limitX,limitX)
    self.panY=clamp(self.panY,-limitY,limitY)
end

function Camera:toWorld(x,y,focusX,focusY)
    return focusX+(x-focusX-self.panX)/self.zoom,focusY+(y-focusY-self.panY)/self.zoom
end

function Camera:apply(focusX,focusY)
    love.graphics.translate(focusX+self.panX,focusY+self.panY)
    love.graphics.scale(self.zoom,self.zoom)
    love.graphics.translate(-focusX,-focusY)
end

function Camera:beginPan(x,y)
    self.panning=true
    self.lastX,self.lastY=x,y
end

function Camera:movePan(x,y,viewportScale)
    if not self.panning then return false end
    viewportScale=viewportScale or 1
    self.panX=self.panX+(x-self.lastX)/viewportScale
    self.panY=self.panY+(y-self.lastY)/viewportScale
    self.lastX,self.lastY=x,y
    self:_clampPan()
    return true
end

function Camera:panBy(dx,dy)
    self.panX=self.panX+(dx or 0)
    self.panY=self.panY+(dy or 0)
    self:_clampPan()
    return self.panX,self.panY
end

function Camera:endPan()
    self.panning=false
end

function Camera:setZoom(value)
    self.zoom=clamp(value or 1,self.minZoom,self.maxZoom)
    self:_clampPan()
    return self.zoom
end

function Camera:setZoomAt(value,anchorX,anchorY,focusX,focusY)
    anchorX,anchorY=anchorX or self.width/2,anchorY or self.height/2
    focusX,focusY=focusX or self.width/2,focusY or self.height/2
    local worldX,worldY=self:toWorld(anchorX,anchorY,focusX,focusY)
    self.zoom=clamp(value or 1,self.minZoom,self.maxZoom)
    self.panX=anchorX-focusX-self.zoom*(worldX-focusX)
    self.panY=anchorY-focusY-self.zoom*(worldY-focusY)
    self:_clampPan()
    return self.zoom
end

function Camera:wheel(delta,anchorX,anchorY,focusX,focusY)
    return self:setZoomAt(self.zoom+(delta or 0)*.1,anchorX,anchorY,focusX,focusY)
end

function Camera:reset()
    self.zoom,self.panX,self.panY=1,0,0
    self.panning=false
    self.scopes[self.scope]={zoom=1,panX=0,panY=0}
end

function Camera:resetAll()
    self.scopes={}
    self:reset()
end

function Camera:audit()
    local old={scope=self.scope,scopes=self.scopes,zoom=self.zoom,panX=self.panX,panY=self.panY,panning=self.panning,lastX=self.lastX,lastY=self.lastY}
    self.scopes={}
    self:setScope("camera-audit-world")
    self:reset(); self:setZoomAt(2,720,360,480,360); self:panBy(-40,20)
    local wx,wy=self:toWorld(720,360,480,360)
    local bounded=math.abs(self.panX)<=self.width*.5*(self.zoom-1) and math.abs(self.panY)<=self.height*.5*(self.zoom-1)
    self:setScope("camera-audit-menu")
    local isolated=self.zoom==1 and self.panX==0 and self.panY==0
    self:setZoom(1.5)
    self:setScope("camera-audit-world")
    local restored=self.zoom==2
    self.scope,self.scopes=old.scope,old.scopes
    self.zoom,self.panX,self.panY=old.zoom,old.panX,old.panY
    self.panning,self.lastX,self.lastY=old.panning,old.lastX,old.lastY
    return {inverse=type(wx)=="number" and type(wy)=="number",bounded=bounded,isolated=isolated,restored=restored,
        minZoom=self.minZoom,maxZoom=self.maxZoom,curve="global-camera-v1"}
end

return Camera
