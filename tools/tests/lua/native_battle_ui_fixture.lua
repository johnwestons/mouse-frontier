-- Headless UI fixture: production camera, ray picking and UI code, with only
-- GPU allocation/submission replaced. Native GL behavior has its own smoke gate.
local F={}
local Camera=require('game.battle_camera')
local Field=require('game.battle_field')
function F.graphics()
    local function noop()end
    local font={getHeight=function()return 22 end,getLineHeight=function()return 1.08 end,
        getWidth=function(_,s)return #tostring(s)*12 end}
    function font:getWrap(s,w)
        local lines={};local n=math.max(1,math.floor(w/12));s=tostring(s)
        for i=1,math.max(1,#s),n do lines[#lines+1]=s:sub(i,i+n-1)end
        return math.min(#s,n)*12,lines
    end
    love.graphics=setmetatable({getDimensions=function()return 960,720 end,getFont=function()return font end,
        transformPoint=function(x,y)return x,y end},{__index=function()return noop end})
end
function F.install()
    F.graphics()
    local Renderer={};Renderer.__index=Renderer
    function Renderer.new(options)return setmetatable({camera=Camera.new(),quality=options.quality,stats={}},Renderer)end
    function Renderer:setBattle(b)self.field=b.field;self.geometryKey=b.field.elevationData end
    function Renderer:release()end
    function Renderer:surfaceMesh()return {release=function()end}end
    function Renderer:drawOverlay()end
    function Renderer:drawSprite()end
    function Renderer:render(b,v,callback)
        self:setBattle(b);self.camera:configure({x=0,y=0,w=v.w,h=v.h});callback();self.camera:configure(v);return self.stats
    end
    function Renderer:pick(x,y)
        if not self.camera:contains(x,y)then return nil end
        return Field.raycast(self.field,self.camera:ray(x,y))
    end
    package.loaded['game.battle_renderer3d']=Renderer
end
function F.prepare(ui,b,data)
    return require('game.battle_native_ui').state({W=960,H=720,ui=ui,battle=b,saveData=data,mobileEnabled=false})
end
return F
