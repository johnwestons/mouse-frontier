local Mice = {}
local quadCache = setmetatable({}, {__mode = "k"})
local walkFile = "field-mouse-walk.png"

local function nearbyWalkable(x, y, location, settlements)
    if settlements.isWalkable(location, x, y) then return x, y end
    for radius = 16, 160, 16 do
        for step = 0, 15 do
            local angle = step / 16 * math.pi * 2
            local nx, ny = x + math.cos(angle) * radius, y + math.sin(angle) * radius
            if settlements.isWalkable(location, nx, ny) then return nx, ny end
        end
    end
    return settlements.trainPoint(location)
end

function Mice.load(images, loadImage)
    images = images or {}
    if not images[walkFile] then images[walkFile] = loadImage("assets/sprites/stop-wildlife/" .. walkFile) end
    return images
end

function Mice.spawn(layout, location, settlements)
    if layout.miceInitialized then return layout.mice or {} end
    layout.miceInitialized = true
    layout.mice = {}
    local seed = (location or 1) * 67 + 11
    layout.miceEnabled = (seed % 100) < 48
    if not layout.miceEnabled then return layout.mice end

    local centerX, centerY = nearbyWalkable(180 + (seed % 520), 390 + (seed % 170), location, settlements)
    local count = 2 + (seed % 3)
    for index = 1, count do
        local x, y = nearbyWalkable(centerX + index * 16 - 30, centerY + (index % 2) * 16, location, settlements)
        layout.mice[#layout.mice + 1] = {
            x = x, y = y, homeX = x, homeY = y, phase = index * .73, wait = 1 + index * .6,
            facing = index % 2 == 0 and -1 or 1, moving = false,
        }
    end
    return layout.mice
end

function Mice.update(list, dt, location, settlements, ecology)
    for _, mouse in ipairs(list or {}) do
        mouse.t = (mouse.t or 0) + dt
        mouse.wait = (mouse.wait or 0) - dt
        local player=ecology and ecology.player
        local threatX,threatY=player and mouse.x-player.x or 0,player and mouse.y-player.y or 0
        local threatDistance=math.sqrt(threatX*threatX+threatY*threatY)
        if player and threatDistance<70 then
            local length=math.max(1,threatDistance)
            mouse.targetX,mouse.targetY=nearbyWalkable(mouse.x+threatX/length*105,mouse.y+threatY/length*62,location,settlements)
            mouse.wait=1.2; mouse.scared=true
        elseif mouse.wait <= 0 or not mouse.targetX then
            local angle = love.math.random() * math.pi * 2
            local feed=ecology and ecology.feed
            local distance = feed and love.math.random(18,58) or love.math.random(30,105)
            local centerX,centerY=feed and feed.x or mouse.homeX,feed and feed.y or mouse.homeY
            mouse.targetX, mouse.targetY = nearbyWalkable(
                centerX + math.cos(angle) * distance,
                centerY + math.sin(angle) * distance * .62,
                location, settlements)
            mouse.wait = love.math.random(3, 8)
            mouse.scared=false
        end
        local dx, dy = mouse.targetX - mouse.x, mouse.targetY - mouse.y
        local distance = math.sqrt(dx * dx + dy * dy)
        mouse.moving = distance > 2
        if mouse.moving then
            mouse.facing = dx >= 0 and 1 or -1
            local step = math.min(distance, 24 * (mouse.scared and 1.8 or 1) * dt)
            local nx, ny = mouse.x + dx / distance * step, mouse.y + dy / distance * step
            mouse.x, mouse.y = settlements.move(location, mouse.x, mouse.y, nx, ny)
        end
    end
end

function Mice.draw(list, images, clock)
    local image = images and images[walkFile]
    if not image then return end
    local frameWidth = image:getWidth() / 5
    local quads = quadCache[image]
    if not quads then
        quads = {}
        for index = 0, 4 do
            quads[index] = love.graphics.newQuad(index * frameWidth, 0, frameWidth, image:getHeight(), image:getWidth(), image:getHeight())
        end
        quadCache[image] = quads
    end
    for _, mouse in ipairs(list or {}) do
        local frame = mouse.moving and (math.floor(clock * 4.2 + mouse.phase) % 5) or 0
        local scale = .034
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, quads[frame], mouse.x, mouse.y, 0, scale * (mouse.facing or 1), scale, frameWidth / 2, image:getHeight())
    end
end

return Mice
