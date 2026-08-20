local Family = {}

function Family.kindForAdult(file)
    file=(file or ""):lower()
    if file:find("hedgehog") then return "hedgehog" end
    if file:find("opossum") or file:find("possum") then return "opossum" end
end

function Family.ensure(actor,file)
    local kind=Family.kindForAdult(file)
    if not kind then actor.family=nil; return end
    if actor.familyRolled then return end
    actor.familyRolled=true
    actor.family=nil
    -- Only 40% of eligible adults are parents at this stop.  Their saved NPC
    -- record keeps this result stable when the player leaves and returns.
    if love.math.random()>.40 then return end
    local composition=love.math.random(3) -- child only, baby only, or both
    local family={}
    if composition==1 or composition==3 then family[#family+1]={kind=kind.."-child",x=actor.x-48,y=actor.y+20,facing=1} end
    if composition==2 or composition==3 then family[#family+1]={kind=kind.."-baby",x=actor.x-82,y=actor.y+25,facing=1} end
    actor.family=family
end

function Family.update(actor,dt,move)
    if not actor or not actor.family then return end
    for i,child in ipairs(actor.family) do
        local baby=child.kind:find("%-baby$")~=nil
        local parentDistance=math.sqrt((actor.x-child.x)^2+(actor.y-child.y)^2)
        local needsFollow=parentDistance>(baby and 82 or 72)

        -- A resting pose is a real state: no position updates are allowed
        -- until its timer ends or the parent starts walking away.
        if child.sleeping then
            child.sleepTimer=(child.sleepTimer or 0)-dt
            if parentDistance>115 or child.sleepTimer<=0 then child.sleeping=false else child.moving=false end
        end

        local targetX,targetY
        if not child.sleeping then
            if needsFollow then
                child.roamX,child.roamY=nil,nil
                local followDistance=baby and 82 or 58
                targetX=actor.x-followDistance*(actor.facing or 1)
                targetY=actor.y+(baby and 24 or 19)
                child.restTimer=0
            else
                child.roamTimer=(child.roamTimer or 0)-dt
                if not child.roamX or child.roamTimer<=0 then
                    local angle=love.math.random()*math.pi*2
                    local radius=love.math.random(baby and 28 or 34,baby and 52 or 64)
                    child.roamX=actor.x+math.cos(angle)*radius
                    child.roamY=actor.y+math.sin(angle)*radius*.48+(baby and 18 or 13)
                    child.roamTimer=love.math.random(3,7)
                end
                targetX,targetY=child.roamX,child.roamY
            end
        end

        if targetX then
        local dx,dy=targetX-child.x,targetY-child.y; local distance=math.sqrt(dx*dx+dy*dy)
            child.moving=distance>5
            if child.moving then
                child.sleeping=false; child.restTimer=0
                local speed=(baby and 38 or 46)*(distance>100 and 1.55 or 1)
                local step=math.min(distance,speed*dt)
                local nx,ny=child.x+dx/distance*step,child.y+dy/distance*step
                if move then nx,ny=move(child.x,child.y,nx,ny) end
                child.x,child.y=nx,ny
                if math.abs(dx)>.1 then child.facing=dx>0 and 1 or -1 end
            else
                child.moving=false
                child.restTimer=(child.restTimer or 0)+dt
                -- Roll once after a calm rest instead of recalculating the
                -- pose every frame.  This prevents lay sprites from sliding.
                if child.restTimer>5 and not needsFollow and love.math.random()<dt*.12 then
                    child.sleeping=true; child.sleepTimer=love.math.random(6,11); child.moving=false
                end
            end
        end
    end
end

function Family.draw(actor,images,clock)
    if not actor or not actor.family then return end
    for i,child in ipairs(actor.family) do
        local baby=child.kind:find("%-baby$")~=nil
        local suffix
        if child.moving then suffix="walk-"..((math.floor(clock*3+i)%2)+1) elseif child.sleeping then suffix="lay-"..((math.floor(clock*.55+i)%2)+1) else suffix="idle-"..((math.floor(clock*.65+i)%2)+1) end
        local image=images[child.kind.."-"..suffix] or images[child.kind.."-idle-1"]
        if image then
            local scale=math.min((baby and 23 or 34)/image:getWidth(),(baby and 27 or 40)/image:getHeight())
            love.graphics.setColor(1,1,1); love.graphics.draw(image,child.x,child.y,0,scale*(child.facing or 1),scale,image:getWidth()/2,image:getHeight())
        end
    end
end

return Family
