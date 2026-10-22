-- Device-local orthographic camera for a 3D tactical battlefield.
local Camera={};Camera.__index=Camera
local rad=math.pi/180
local function clamp(n,a,b)return math.max(a,math.min(b,n))end
function Camera.new()
    return setmetatable({yaw=45,tilt=55,zoom=1,pixelsPerUnit=72,targetX=2,targetY=.6,targetZ=10,
        viewport={x=0,y=0,w=960,h=560},near=.1,far=200,distance=70},Camera)
end
function Camera:configure(viewport)
    self.viewport={x=viewport.x,y=viewport.y,w=math.max(1,viewport.w),h=math.max(1,viewport.h)}
end
function Camera:basis()
    if self._basis and self._basisYaw==self.yaw and self._basisTilt==self.tilt then return self._basis[1],self._basis[2],self._basis[3]end
    local a,t=self.yaw*rad,self.tilt*rad;local sa,ca,st,ct=math.sin(a),math.cos(a),math.sin(t),math.cos(t)
    self._basis={{ca,0,-sa},{-sa*st,ct,-ca*st},{sa*ct,st,ca*ct}};self._basisYaw,self._basisTilt=self.yaw,self.tilt
    return self._basis[1],self._basis[2],self._basis[3]
end
function Camera:project(x,y,z)
    local r,u,b=self:basis();local dx,dy,dz=x-self.targetX,y-self.targetY,z-self.targetZ
    local scale=self.pixelsPerUnit*self.zoom;local v=self.viewport
    return v.x+v.w/2+(dx*r[1]+dz*r[3])*scale,
        v.y+v.h/2-(dx*u[1]+dy*u[2]+dz*u[3])*scale,
        self.distance-(dx*b[1]+dy*b[2]+dz*b[3])
end
function Camera:ray(sx,sy)
    local r,u,b=self:basis();local v=self.viewport;local scale=self.pixelsPerUnit*self.zoom
    local x=(sx-v.x-v.w/2)/scale;local y=-(sy-v.y-v.h/2)/scale
    return {self.targetX+r[1]*x+u[1]*y+b[1]*self.distance,
        self.targetY+u[2]*y+b[2]*self.distance,self.targetZ+r[3]*x+u[3]*y+b[3]*self.distance},
        {-b[1],-b[2],-b[3]}
end
function Camera:orbit(dx,dy)
    self.yaw=(self.yaw+dx)%360;self.tilt=clamp(self.tilt+(dy or 0),20,85)
end
function Camera:pan(dx,dy)
    local r,u=self:basis();local scale=self.pixelsPerUnit*self.zoom
    -- Intersect the screen displacement with the horizontal target plane.
    local vertical=-dy/(scale*math.sin(self.tilt*rad))
    local a=self.yaw*rad
    self.targetX=self.targetX-dx*r[1]/scale+vertical*math.sin(a)
    self.targetZ=self.targetZ-dx*r[3]/scale+vertical*math.cos(a)
end
function Camera:setZoom(value)
    self.zoom=clamp(value,.05,3.5);return self.zoom
end
function Camera:frame(columns,rows)
    self.targetX,self.targetZ=columns/2,rows/2;self.targetY=.7
    local a,t=self.yaw*rad,self.tilt*rad;local v=self.viewport
    local horizontal=columns*math.abs(math.cos(a))+rows*math.abs(math.sin(a))
    local vertical=(columns*math.abs(math.sin(a))+rows*math.abs(math.cos(a)))*math.sin(t)+4*math.cos(t)
    self:setZoom(math.min(v.w/(horizontal+2),v.h/(vertical+2))/self.pixelsPerUnit)
end
function Camera:focus(q,r,height)
    self.targetX,self.targetZ=q+.5,r-.5;self.targetY=(height or 0)+.65
end
function Camera:contains(x,y)
    local v=self.viewport;return x>=v.x and y>=v.y and x<v.x+v.w and y<v.y+v.h
end
return Camera
