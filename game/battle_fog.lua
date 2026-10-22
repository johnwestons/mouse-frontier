-- Shared tactical sight and compact, persistent party exploration. Device draw
-- distance is deliberately absent: lowering graphics never changes these rules.
local Grid=require('game.battle_grid')
local Fog={VERSION=1,SIGHT=8}
local cache=setmetatable({},{__mode='k'})
local function index(field,q,r)return q*field.rows+r end
local function bytes(field)return math.ceil(field.columns*field.rows/4)end
local function sourceKey(b)
    local parts={}
    for _,u in ipairs(b.units or{})do if u.team=='ally'and u.hp>0 then parts[#parts+1]=u.id..':'..u.q..':'..u.r end end
    return table.concat(parts,'|')
end
local function sight(b,override,point)
    local visible,sources={},{}
    for _,u in ipairs(b.units or{})do if u.team=='ally'and u.hp>0 then
        local a=u==override and point or u
        sources[#sources+1]={a.q+.5,a.r-.5}
        for q=math.max(0,a.q-Fog.SIGHT),math.min(b.field.columns-1,a.q+Fog.SIGHT)do
            for r=math.max(1,a.r-Fog.SIGHT),math.min(b.field.rows,a.r+Fog.SIGHT)do
                if (q-a.q)^2+(r-a.r)^2<=Fog.SIGHT^2 then
                    -- The target's own cover must remain discoverable.
                    if Grid.lineOfSight(b,a,{q=q,r=r})or q==a.q and r==a.r then visible[index(b.field,q,r)]=true end
                end
            end
        end
    end end
    return visible,sources
end
local function unpacked(field,text)
    local values={}
    for i=1,#text do
        local nibble=tonumber(text:sub(i,i),16)or 0
        for bit=0,3 do if math.floor(nibble/2^bit)%2==1 then values[(i-1)*4+bit+1]=true end end
    end
    return values
end
local function packed(field,values)
    local result={}
    for i=0,bytes(field)-1 do
        local nibble=0;for bit=0,3 do if values[i*4+bit+1]then nibble=nibble+2^bit end end
        result[#result+1]=string.format('%x',nibble)
    end
    return table.concat(result)
end
function Fog.validate(b)
    if not b.field then return b.fog==nil end
    if b.fog==nil then return b.field.version==1 end
    local f=b.fog
    if type(f)~='table'or f.version~=Fog.VERSION or type(f.explored)~='string'
        or #f.explored~=bytes(b.field)or f.explored:find('[^0-9a-f]')then return false end
    for k in pairs(f)do if k~='version'and k~='explored'then return false end end
    return true
end
function Fog.state(b)
    if not b.field then return nil end
    local key=sourceKey(b);local remembered=b.fog and b.fog.explored or ''
    -- Guest presentation wraps a battle in a fresh shallow table every draw.
    -- The roster survives those wrappers; never redo sight rays every frame.
    local owner=b.units or b;local value=cache[owner]
    if value and value.key==key and value.remembered==remembered and value.field==b.field and value.obstacles==b.obstacles then return value end
    local visible,sources=sight(b);local explored=unpacked(b.field,remembered)
    for k in pairs(visible)do explored[k]=true end
    value={key=key,remembered=remembered,visible=visible,explored=explored,sources=sources,field=b.field,obstacles=b.obstacles}
    cache[owner]=value;return value
end
function Fog.update(b,unit,path)
    if not b.field then return end
    local state=Fog.state(b);local explored={}
    for k in pairs(state.explored)do explored[k]=true end
    -- A long march reveals the terrain passed along the route, not just its end.
    for _,p in ipairs(path or{})do for k in pairs(sight(b,unit,p))do explored[k]=true end end
    b.fog={version=Fog.VERSION,explored=packed(b.field,explored)}
end
function Fog.visible(b,q,r)
    if not b.field then return true end
    return Fog.state(b).visible[index(b.field,q,r)]==true
end
function Fog.explored(b,q,r)
    if not b.field then return true end
    return Fog.state(b).explored[index(b.field,q,r)]==true
end
function Fog.unitVisible(b,u)return u.team=='ally'or Fog.visible(b,u.q,u.r)end
function Fog.inRange(sources,x,z,radius)
    for _,p in ipairs(sources)do if (x-p[1])^2+(z-p[2])^2<=radius^2 then return true end end
    return false
end
return Fog
