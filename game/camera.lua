local Camera = {zoom=1,panX=0,panY=0,panning=false,lastX=0,lastY=0,maxZoom=2.25}

function Camera:isActive()
    return self.zoom>1 or self.panX~=0 or self.panY~=0
end

function Camera:toWorld(x,y,focusX,focusY)
    return focusX+(x-focusX-self.panX)/self.zoom,focusY+(y-focusY-self.panY)/self.zoom
end

function Camera:apply(focusX,focusY)
    love.graphics.translate(focusX+self.panX,focusY+self.panY); love.graphics.scale(self.zoom,self.zoom); love.graphics.translate(-focusX,-focusY)
end

function Camera:beginPan(x,y)
    self.panning=true; self.lastX,self.lastY=x,y
end

function Camera:movePan(x,y,viewportScale)
    if not self.panning then return false end
    self.panX=self.panX+(x-self.lastX)/(viewportScale*self.zoom); self.panY=self.panY+(y-self.lastY)/(viewportScale*self.zoom)
    self.panX=math.max(-420,math.min(420,self.panX)); self.panY=math.max(-300,math.min(300,self.panY)); self.lastX,self.lastY=x,y
    return true
end

function Camera:endPan()
    self.panning=false
end

function Camera:wheel(delta)
    self:setZoom(self.zoom+delta*.08)
end

function Camera:setZoom(value)
    self.zoom=math.max(1,math.min(self.maxZoom,value or 1))
    return self.zoom
end

return Camera
