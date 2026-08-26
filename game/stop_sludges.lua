-- Stop-only sludge crawler encounters.  Kept separate from the main scene loop so
-- new stop creatures can be added without increasing main.lua's local/upvalue count.
local M = {}
local quadCache=setmetatable({},{__mode="k"})

local function dist(ax, ay, bx, by)
    local dx, dy = bx-ax, by-ay
    return math.sqrt(dx*dx + dy*dy), dx, dy
end

local function countForStop(stop)
    if stop <= 8 then return 2 end
    if stop <= 20 then return 3 end
    if stop <= 35 then return 4 end
    return 5
end

function M.new()
    return {byStop={}, message=nil, messageTimer=0, attackTimer=0}
end

function M.ensure(sys, data, stop, ctx)
    local key=tostring(stop)
    if sys.byStop[key] then return sys.byStop[key] end
    data.stopSludges=data.stopSludges or {}
    local saved=data.stopSludges[key]
    if type(saved)~="table" then
        saved={}
        local n=countForStop(stop)
        for i=1,n do
            local x=240+((i*173+stop*41)%500)
            local y=360+((i*97+stop*23)%220)
            saved[#saved+1]={x=x,y=y,hp=12+math.floor(stop/12),maxHp=12+math.floor(stop/12),dead=false}
        end
        data.stopSludges[key]=saved
    end
    sys.byStop[key]=saved
    return saved
end

local function meleeWeapon(ctx)
    local p=ctx.player; local data=ctx.data
    for i=1,2 do
        local name=data and data.equipment and data.equipment[i]
        local combat=name and ctx.catalog.weaponCombat and ctx.catalog.weaponCombat[name]
        if name and name~="scratch" and ctx.isWeapon(name) and (not combat or combat.kind~="ranged") then return name end
    end
    return nil
end

function M.attack(sys,ctx,targetX,targetY)
    if sys.attackTimer>0 then return false,"Readying attack..." end
    local weapon=meleeWeapon(ctx)
    if not weapon then return false,"A melee weapon is required." end
    local p=ctx.player; local px,py=p.x,p.y
    targetX=tonumber(targetX) or px; targetY=tonumber(targetY) or py
    local dtx,dty=targetX-px,targetY-py; local dlen=math.sqrt(dtx*dtx+dty*dty)
    -- Swinging is an action of its own.  A missing/zero-length cursor aim
    -- should never cancel the animation; use the character's facing instead.
    if dlen<0.01 then
        dtx=(p.facing or 1)*100; dty=0; dlen=100
    end
    local best,bestScore
    for _,s in ipairs(M.ensure(sys,ctx.data,ctx.location,ctx)) do
        if not s.dead then
            local d=dist(px,py,s.x,s.y)
            -- Damage is proximity-based rather than cursor-based.  The player
            -- can freely swing anywhere; a nearby crawler is hit automatically.
            if d<=150 and (not bestScore or d<bestScore) then best,bestScore=s,d end
        end
    end
    p.facing=dtx>=0 and 1 or -1
    sys.attackTimer=.42
    if ctx.onAction then ctx.onAction(weapon) end
    if ctx.playSfx then ctx.playSfx("sword") end
    if not best then
        sys.message="The swing misses."; sys.messageTimer=1.2
        return true
    end
    local stats=ctx.catalog.weaponStats[weapon] or {min=2,max=4}
    local damage=math.max(1,love.math.random(stats.min or 2,stats.max or 4))
    best.hp=math.max(0,best.hp-damage); best.hitTimer=.38; best.healthTimer=3; best.flee=true
    if best.hp<=0 then best.dead=true; best.deathTimer=0; best.dropDone=false end
    sys.message=(best.hp<=0 and "Sludge crawler defeated!" or ("Melee hit for "..damage.." damage.")); sys.messageTimer=1.6
    return true
end

function M.update(sys,ctx,dt)
    sys.attackTimer=math.max(0,sys.attackTimer-dt); sys.messageTimer=math.max(0,sys.messageTimer-dt)
    local list=M.ensure(sys,ctx.data,ctx.location,ctx)
    local p=ctx.player
    for _,s in ipairs(list) do
        s.hitTimer=math.max(0,(s.hitTimer or 0)-dt); s.healthTimer=math.max(0,(s.healthTimer or 0)-dt)
        if s.dead then
            s.deathTimer=(s.deathTimer or 0)+dt
            if s.deathTimer>=1.7 and not s.dropDone then
                s.dropDone=true
                if ctx.dropCoal then ctx.dropCoal(s.x,s.y) end
            end
        else
            local d,dx,dy=dist(s.x,s.y,p.x,p.y)
            local avoid= d<78
            if ctx.npc and ctx.npc.x then local nd,nx,ny=dist(s.x,s.y,ctx.npc.x,ctx.npc.y); if nd<62 then avoid=true; dx,dy=nx,ny; d=nd end end
            if avoid or s.flee or (s.hp < s.maxHp*.35 and d<155) then
                local len=math.max(1,d); local speed=s.flee and 52 or 28
            -- dx/dy point from the sludge toward the threat; crawlers retreat.
            s.x=s.x-(dx/len)*speed*dt; s.y=s.y-(dy/len)*speed*dt
                if ctx.clamp then s.x,s.y=ctx.clamp(s.x,s.y) end
            end
        end
    end
end

local function atlasSpec(asset,fallbackFrames)
    if not asset then return nil end
    local descriptor=type(asset)=="table" and asset or nil
    local image=descriptor and descriptor.image or asset
    local columns=math.max(1,(descriptor and descriptor.columns) or fallbackFrames or 1)
    local rows=math.max(1,(descriptor and descriptor.rows) or 1)
    local count=math.max(1,math.min((descriptor and descriptor.count) or columns*rows,columns*rows))
    return image,columns,rows,count,image:getWidth()/columns,image:getHeight()/rows
end

local function drawSheet(asset,fallbackFrames,frame,x,y,sx,sy,ox,oy)
    local img,columns,rows,count,fw,fh=atlasSpec(asset,fallbackFrames)
    if not img then return end
    local byLayout=quadCache[img]; if not byLayout then byLayout={}; quadCache[img]=byLayout end
    local key=columns.."x"..rows..":"..count
    local quads=byLayout[key]
    if not quads then
        quads={}
        for index=0,count-1 do
            local column,row=index%columns,math.floor(index/columns)
            quads[index]=love.graphics.newQuad(math.floor(column*fw),math.floor(row*fh),math.floor(fw),math.floor(fh),img:getWidth(),img:getHeight())
        end
        byLayout[key]=quads
    end
    local q=quads[frame%count]
    love.graphics.draw(img,q,x,y,0,sx or 1,sy or sx or 1,ox or fw/2,oy or fh)
end

function M.draw(sys,ctx)
    local list=M.ensure(sys,ctx.data,ctx.location,ctx)
    for _,s in ipairs(list) do
        local img=ctx.images and ctx.images.idle
        local frames=2; local frame=math.floor(ctx.clock*1.8+(s.x or 0)*.01)%frames
        if s.dead then img=ctx.images.death or img; frames=4; frame=math.min(3,math.floor((s.deathTimer or 0)*2.4))
        elseif (s.hitTimer or 0)>0 then img=ctx.images.hit or img; frames=4; frame=math.floor(ctx.clock*8)%frames
        elseif s.flee then img=ctx.images.walk or img; frames=4; frame=math.floor(ctx.clock*3)%frames end
        if img then
            local sink=s.dead and math.min(1,(s.deathTimer or 0)/1.7) or 0
            local _,_,_,_,_,frameHeight=atlasSpec(img,frames)
            local scale=math.min(.14,45/math.max(1,frameHeight))
            love.graphics.setColor(0,0,0,.28); love.graphics.ellipse("fill",s.x,s.y+3,27,9)
            love.graphics.setColor(1,1,1,1-sink*.75); drawSheet(img,frames,frame,s.x,s.y+sink*24,scale,scale)
            if not s.dead and (s.healthTimer or 0)>0 then
                love.graphics.setColor(.12,.04,.03,.85); love.graphics.rectangle("fill",s.x-28,s.y-78,56,7)
                love.graphics.setColor(.82,.16,.12,1); love.graphics.rectangle("fill",s.x-27,s.y-77,54*math.max(0,s.hp/s.maxHp),5)
            end
        end
    end
    if sys.messageTimer>0 and sys.message then
        love.graphics.setColor(.08,.05,.03,.86); love.graphics.rectangle("fill",300,350,360,34,6,6)
        love.graphics.setColor(1,.88,.58,1); love.graphics.printf(sys.message,305,359,350,"center",0,.78,.78)
    end
end

return M
