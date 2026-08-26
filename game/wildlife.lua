local Wildlife = {}
local quadCache=setmetatable({},{__mode="k"})

local species = {
    rooster = "chicken-rooster-walk.png",
    hen = "chicken-hen-walk.png",
    chick = "chicken-chick-walk.png",
}

local function chickenImage(images, kind)
    return images and images[species[kind]]
end

local function nearbyWalkable(x,y,location,settlements)
    if settlements.isWalkable(location,x,y) then return x,y end
    for radius=16,192,16 do
        for step=0,15 do
            local angle=step/16*math.pi*2
            local nx,ny=x+math.cos(angle)*radius,y+math.sin(angle)*radius
            if settlements.isWalkable(location,nx,ny) then return nx,ny end
        end
    end
    local tx,ty=settlements.trainPoint(location)
    return tx,ty
end

function Wildlife.load(images, loadImage)
    images = images or {}
    for kind, file in pairs(species) do
        if not images[file] then images[file] = loadImage("assets/sprites/stop-wildlife/chickens/" .. file) end
    end
    return images
end

function Wildlife.spawn(layout,location,settlements)
    -- Migrate the old implementation, which populated every stop. Presence is
    -- deterministic per location so loading a save never rerolls the flock.
    if layout.chickensInitialized then return layout.wildlife or {} end
    layout.chickensInitialized=true
    layout.wildlife={}
    local seed=(location or 1)*41+3
    local feedActivity=layout.worldActivity and layout.worldActivity.kind=="wildlife-trough"
    layout.chickensEnabled=(seed%100)<40 or feedActivity
    if not layout.chickensEnabled then return layout.wildlife end

    local centerX,centerY=nearbyWalkable(250+(seed%430),430+(seed%145),location,settlements)
    local function add(kind,x,y,mother,phase)
        x,y=nearbyWalkable(x,y,location,settlements)
        layout.wildlife[#layout.wildlife+1]={kind=kind,x=x,y=y,homeX=x,homeY=y,mother=mother,phase=phase,wait=1+(phase%2),facing=1,moving=false}
    end
    add("rooster",centerX-44,centerY-5,nil,.4)
    add("hen",centerX+18,centerY,nil,1.3)
    local chickCount=1+(seed%3)
    for i=1,chickCount do add("chick",centerX+8+i*13,centerY+15,2,1.8+i*.35) end
    return layout.wildlife
end

function Wildlife.update(list,dt,location,settlements,ecology)
    for index,bird in ipairs(list or {}) do
        bird.t=(bird.t or 0)+dt; bird.wait=(bird.wait or 0)-dt
        local mother=bird.mother and list[bird.mother]
        local player=ecology and ecology.player
        local threatX,threatY=player and bird.x-player.x or 0,player and bird.y-player.y or 0
        local threatDistance=math.sqrt(threatX*threatX+threatY*threatY)
        if player and threatDistance<82 then
            local length=math.max(1,threatDistance)
            bird.targetX,bird.targetY=nearbyWalkable(bird.x+threatX/length*90,bird.y+threatY/length*58,location,settlements)
            bird.wait=.9; bird.scared=true
        elseif mother then
            -- Chicks keep a loose formation behind their mother and walk to
            -- catch up rather than being teleported with her.
            local side=((index%2)==0 and -1 or 1)*(10+index*3)
            bird.targetX,bird.targetY=mother.x-side*(mother.facing or 1),mother.y+12+(index%3)*5
        elseif bird.wait<=0 or not bird.targetX then
            local center=ecology and ecology.feed
            local angle=love.math.random()*math.pi*2; local distance=center and love.math.random(12,48) or love.math.random(25,85)
            local centerX,centerY=center and center.x or bird.homeX,center and center.y or bird.homeY
            bird.targetX,bird.targetY=nearbyWalkable(centerX+math.cos(angle)*distance,centerY+math.sin(angle)*distance*.62,location,settlements)
            bird.wait=love.math.random(2,6)
            bird.scared=false
        end
        local dx,dy=(bird.targetX or bird.x)-bird.x,(bird.targetY or bird.y)-bird.y
        local distance=math.sqrt(dx*dx+dy*dy); bird.moving=distance>2
        if bird.moving then
            bird.facing=dx>=0 and 1 or -1
            local speed=(bird.kind=="chick" and 28 or 22)*(bird.scared and 1.65 or 1)
            local step=math.min(distance,speed*dt)
            local nx,ny=bird.x+dx/distance*step,bird.y+dy/distance*step
            bird.x,bird.y=settlements.move(location,bird.x,bird.y,nx,ny)
        end
    end
end

function Wildlife.draw(list, images, clock)
    for _, bird in ipairs(list or {}) do
        local image=chickenImage(images,bird.kind)
        if image then
            local frameWidth=image:getWidth()/5
            -- The sheet has five walk frames. The old expression multiplied
            -- the clock twice, advancing at roughly 25 frames per second and
            -- making the flock look like it was vibrating. Keep the cycle
            -- gentle and let idle chickens hold their first frame.
            local frameRate=bird.kind=="chick" and 4.2 or 4.8
            local frame=bird.moving and (math.floor(clock*frameRate+(bird.phase or 0))%5) or 0
            local quads=quadCache[image]
            if not quads then quads={}; for index=0,4 do quads[index]=love.graphics.newQuad(index*frameWidth,0,frameWidth,image:getHeight(),image:getWidth(),image:getHeight()) end; quadCache[image]=quads end
            local quad=quads[frame]
            local scale=bird.kind=="chick" and .034 or .064
            local sx=scale*(bird.facing or 1)
            love.graphics.setColor(1,1,1); love.graphics.draw(image,quad,bird.x,bird.y,0,sx,scale,frameWidth/2,image:getHeight())
        end
    end
end

return Wildlife
