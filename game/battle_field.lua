-- Canonical battlefield data. No graphics, device state, or global random calls.
-- Geometry is retained with the battle; cosmetic meshes are rebuilt locally.
local Sites=require('game.battle_sites')
local Field={VERSION=3,COLUMNS=72,ROWS=40,MIN_PLAYABLE=2400,LEVEL_SCALE=8}
local decoded=setmetatable({},{__mode='k'})
local kinds={'dead-tree','rusty-car','ruined-shack','boulders','barricade','rail-cart'}
local function clamp(n,a,b)return math.max(a,math.min(b,n))end
local function smooth(n)n=clamp(n,0,1);return n*n*(3-2*n)end
local function lerp(a,b,t)return a+(b-a)*t end
local function validInteger(n,a,b)return type(n)=='number' and n==math.floor(n) and n>=a and n<=b end

-- Park-Miller arithmetic stays exact in both LuaJIT and Lua 5.1 doubles.
function Field.random(seed)
    local state=math.floor(seed or 1)%2147483647;if state<=0 then state=1 end
    return function(a,b)
        state=(state*16807)%2147483647
        local n=(state-1)/2147483646
        if a==nil then return n end
        if b==nil then b=a;a=1 end
        return a+math.floor(n*(b-a+1))
    end
end
local function hash(seed,x,z)
    return ((seed%65521)*251+(x+211)*733+(z+307)*1301+(x+73)*(z+91)*17)%65521/65520
end
local function noise(seed,x,z)
    local ix,iz=math.floor(x),math.floor(z);local u,v=smooth(x-ix),smooth(z-iz)
    return lerp(lerp(hash(seed,ix,iz),hash(seed,ix+1,iz),u),lerp(hash(seed,ix,iz+1),hash(seed,ix+1,iz+1),u),v)
end
function Field.route(field,x)
    return field.rows*.5+math.sin(x*.24+(field.seed%157)*.04)*1.4
end
local function crossDistance(field,x)
    local width=field.columns
    return math.min(math.abs(x-width*.23),math.abs(x-width*.5),math.abs(x-width*.77))
end
function Field.isCorridor(field,x,z)
    return math.abs(z-Field.route(field,x))<1.65 or math.abs(z-3)<1.0
        or math.abs(z-(field.rows-3))<1.0 or crossDistance(field,x)<1.1
        or x<2.5 or x>field.columns-2.5
end
local function generatedHeight(field,x,z)
    local seed=field.seed;local w,h=field.columns,field.rows
    local a=math.exp(-((x-w*.42)^2/(w*1.1)+(z-h*.25)^2/13))*2.6
    local b=math.exp(-((x-w*.75)^2/(w*.75)+(z-h*.78)^2/17))*3.4
    local c=math.exp(-((x-w*.15)^2/26+(z-h*.8)^2/12))*1.7
    local shape=a+b+c+.32*noise(seed,x*.35,z*.35)
    local d=math.min(math.abs(z-Field.route(field,x))/1.65,math.abs(z-3)/1.6,math.abs(z-(h-3))/1.6,crossDistance(field,x)/1.1)
    local edge=math.min(x/2.5,(w-x)/2.5)
    local corridor=smooth(d-.45)*smooth(edge)
    return Sites.flatten(field,x,z,.125+shape*corridor)
end
local function levels(field)
    local cached=decoded[field]
    if cached and cached.source==field.elevationData then return cached.values end
    local values={};for pair in field.elevationData:gmatch('%x%x')do values[#values+1]=tonumber(pair,16)/Field.LEVEL_SCALE end
    decoded[field]={source=field.elevationData,values=values};return values
end
function Field.vertexHeight(field,x,z)
    if not field then return 0 end
    x=clamp(math.floor(x),0,field.columns);z=clamp(math.floor(z),0,field.rows)
    return levels(field)[x*(field.rows+1)+z+1]
end
-- Uses the same diagonal and interpolation as the rendered terrain triangles.
function Field.heightAt(field,x,z)
    if not field then return 0 end
    x=clamp(x,0,field.columns);z=clamp(z,0,field.rows)
    local ix,iz=math.min(field.columns-1,math.floor(x)),math.min(field.rows-1,math.floor(z))
    local u,v=x-ix,z-iz
    local a=Field.vertexHeight(field,ix,iz);local b=Field.vertexHeight(field,ix+1,iz)
    local c=Field.vertexHeight(field,ix,iz+1);local d=Field.vertexHeight(field,ix+1,iz+1)
    if u+v<=1 then return a+(b-a)*u+(c-a)*v end
    return d+(c-d)*(1-u)+(b-d)*(1-v)
end
function Field.cellHeight(field,q,r)return Field.heightAt(field,q+.5,r-.5)end
function Field.traversalCost(field,q,r,nq,nr)
    local a,b=Field.cellHeight(field,q,r),Field.cellHeight(field,nq,nr)
    local middle=Field.heightAt(field,(q+nq)/2+.5,(r+nr)/2-.5)
    if math.max(math.abs(middle-a),math.abs(b-middle))>.625 then return nil end
    return b-a>.25 and 2 or 1
end
function Field.materialAt(field,x,z)
    if math.abs(z-Field.route(field,x))<.8 then return 'path' end
    if Field.heightAt(field,x,z)>1.5 then return 'stone' end
    if field.biome==2 then return 'grass' end
    if field.biome==3 and noise(field.seed,x*.25,z*.25)>.52 then return 'rubble' end
    return 'earth'
end
-- Legacy board accessors use these derived arrays. They carry no additional
-- gameplay information and need not travel over the network.
function Field.tileArrays(field)
    local tiles,variants={},{};local rng=Field.random(field.seed+991)
    for q=0,field.columns-1 do
        tiles[q]={};variants[q]={}
        for r=1,field.rows do tiles[q][r]=1;variants[q][r]=rng(1,3)end
    end
    return tiles,variants
end
function Field.generate(seed,biome,tier)
    local field={version=Field.VERSION,columns=Field.COLUMNS,rows=Field.ROWS,
        seed=clamp(math.floor(seed or 1),1,2147483646),biome=clamp(math.floor(biome or 1),1,4),exitColumn=Field.COLUMNS-1}
    field.layout=({'rail-cutting','ruined-crossing','ridge-pass'})[field.seed%3+1]
    local encoded={}
    for x=0,field.columns do for z=0,field.rows do
        encoded[#encoded+1]=string.format('%02x',clamp(math.floor(generatedHeight(field,x,z)*Field.LEVEL_SCALE+.5),0,255))
    end end
    field.elevationData=table.concat(encoded)
    local tiles,variants,candidates,obstacles={},{},{},{}
    local rng=Field.random(field.seed+991)
    local sites=Sites.list(field)
    for _,site in ipairs(sites)do
        for x=0,site.w-1 do for z=0,site.d-1 do
            local q,r=site.q+x,site.r+z
            local kind=Sites.wall(site,x,z)
            if kind and not Field.isCorridor(field,q+.5,r-.5)then
                obstacles[q..':'..r]={q=q,r=r,kind=kind}
            end
        end end
    end
    for q=0,field.columns-1 do
        tiles[q]={};variants[q]={}
        for r=1,field.rows do
            tiles[q][r]=1;variants[q][r]=rng(1,3)
            if not Field.isCorridor(field,q+.5,r-.5)and not Sites.at(field,q,r,sites)then candidates[#candidates+1]={q=q,r=r} end
        end
    end
    for i=#candidates,2,-1 do local j=rng(1,i);candidates[i],candidates[j]=candidates[j],candidates[i]end
    local count=0;for _ in pairs(obstacles)do count=count+1 end
    local desired=(tier=='hard' and 448 or tier=='medium' and 416 or 384)-count
    desired=math.min(desired,field.columns*field.rows-Field.MIN_PLAYABLE,#candidates)
    for i=1,desired do
        local p=candidates[i];local kind=kinds[rng(1,#kinds)]
        obstacles[p.q..':'..p.r]={q=p.q,r=p.r,kind=kind}
    end
    -- A bounded known-valid fallback protects future terrain tuning as well as
    -- unusual seeds. An operation must retain the promised reachable area.
    if Field.connectedCount(field,obstacles)<Field.MIN_PLAYABLE then
        field.elevationData=string.rep('01',(field.columns+1)*(field.rows+1))
        obstacles={}
    end
    return field,tiles,variants,obstacles
end
function Field.validate(field)
    if type(field)~='table' then return false,'missing battlefield' end
    local allowed={version=true,columns=true,rows=true,seed=true,biome=true,layout=true,exitColumn=true,elevationData=true}
    for key in pairs(field)do if not allowed[key]then return false,'unknown battlefield field' end end
    local geometry=field.version==1 and field.columns==36 and field.rows==20
        or (field.version==2 or field.version==Field.VERSION)and field.columns==Field.COLUMNS and field.rows==Field.ROWS
    if not geometry
        or not validInteger(field.seed,1,2147483646) or not validInteger(field.biome,1,4)
        or field.exitColumn~=field.columns-1 or not ({['rail-cutting']=true,['ruined-crossing']=true,['ridge-pass']=true})[field.layout]
        or type(field.elevationData)~='string' or #field.elevationData~=(field.columns+1)*(field.rows+1)*2
        or field.elevationData:find('[^0-9a-f]') then return false,'invalid battlefield geometry' end
    return true
end
function Field.minimumPlayable(field)return field.version==1 and 600 or Field.MIN_PLAYABLE end
function Field.isExit(field,q,r)
    return field and q==field.exitColumn and validInteger(r,1,field.rows) or false
end
function Field.playableCount(field,obstacles)
    local count=field.columns*field.rows;for _ in pairs(obstacles or {})do count=count-1 end;return count
end
function Field.connectedCount(field,obstacles)
    local queue,seen={{q=0,r=3}},{[3]=true};local head,count=1,0
    local directions={{1,0},{0,1},{-1,0},{0,-1}}
    while queue[head]do
        local a=queue[head];head=head+1;count=count+1
        for _,v in ipairs(directions)do
            local q,r=a.q+v[1],a.r+v[2];local k=q*field.rows+r
            if q>=0 and q<field.columns and r>=1 and r<=field.rows and not seen[k]
                and not obstacles[q..':'..r] and Field.traversalCost(field,a.q,a.r,q,r)then
                seen[k]=true;queue[#queue+1]={q=q,r=r}
            end
        end
    end
    return count
end
local function triangleHit(o,d,ax,ay,az,bx,by,bz,cx,cy,cz)
    local ex,ey,ez=bx-ax,by-ay,bz-az;local fx,fy,fz=cx-ax,cy-ay,cz-az
    local px,py,pz=d[2]*fz-d[3]*fy,d[3]*fx-d[1]*fz,d[1]*fy-d[2]*fx
    local det=ex*px+ey*py+ez*pz;if math.abs(det)<1e-9 then return nil end
    local tx,ty,tz=o[1]-ax,o[2]-ay,o[3]-az;local inv=1/det
    local u=(tx*px+ty*py+tz*pz)*inv;if u<-.000001 or u>1.000001 then return nil end
    local qx,qy,qz=ty*ez-tz*ey,tz*ex-tx*ez,tx*ey-ty*ex
    local v=(d[1]*qx+d[2]*qy+d[3]*qz)*inv;if v<-.000001 or u+v>1.000001 then return nil end
    local t=(fx*qx+fy*qy+fz*qz)*inv;return t>=0 and t or nil
end
-- Traverse only crossed cells; picking is independent of camera angle or zoom.
function Field.raycast(field,origin,direction)
    local enter,leave=0,math.huge
    for axis,maximum in ipairs({field.columns,32,field.rows})do
        local o,d=origin[axis],direction[axis]
        if math.abs(d)<1e-10 then if o<0 or o>maximum then return nil end
        else
            local a,b=-o/d,(maximum-o)/d;if a>b then a,b=b,a end
            enter=math.max(enter,a);leave=math.min(leave,b)
        end
    end
    if leave<enter then return nil end
    local x=origin[1]+direction[1]*(enter+1e-6);local z=origin[3]+direction[3]*(enter+1e-6)
    local q,r=clamp(math.floor(x),0,field.columns-1),clamp(math.floor(z),0,field.rows-1)
    local sx=direction[1]>=0 and 1 or -1;local sz=direction[3]>=0 and 1 or -1
    for _=1,field.columns+field.rows+4 do
        local a=Field.vertexHeight(field,q,r);local b=Field.vertexHeight(field,q+1,r)
        local c=Field.vertexHeight(field,q,r+1);local d=Field.vertexHeight(field,q+1,r+1)
        local first=triangleHit(origin,direction,q,a,r,q,c,r+1,q+1,b,r)
        local second=triangleHit(origin,direction,q+1,b,r,q,c,r+1,q+1,d,r+1)
        local hit=first and second and math.min(first,second) or first or second
        if hit and hit>=enter-1e-5 and hit<=leave+1e-5 then
            return q,r+1,{origin[1]+direction[1]*hit,origin[2]+direction[2]*hit,origin[3]+direction[3]*hit}
        end
        local tx=math.abs(direction[1])<1e-10 and math.huge or ((sx>0 and q+1 or q)-origin[1])/direction[1]
        local tz=math.abs(direction[3])<1e-10 and math.huge or ((sz>0 and r+1 or r)-origin[3])/direction[3]
        if math.min(tx,tz)>leave then return nil end
        if tx<=tz then q=q+sx else r=r+sz end
        if q<0 or q>=field.columns or r<0 or r>=field.rows then return nil end
    end
end
return Field
