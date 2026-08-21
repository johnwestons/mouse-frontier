local Maintenance = {}

local ASSET_ROOT = "assets/sprites/maintenance/oil-running-gear/"
local SLOT_CENTERS = {356, 419, 483, 549, 614}
local SLOT_Y = 559

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function Maintenance.ensure(data)
    data.maintenance = type(data.maintenance) == "table" and data.maintenance or {}
    local state = data.maintenance
    state.condition = clamp(tonumber(state.condition) or 72, 0, 100)
    state.lastServicedStop = math.max(0, math.floor(tonumber(state.lastServicedStop) or 0))
    state.totalServices = math.max(0, math.floor(tonumber(state.totalServices) or 0))
    state.totalWear = math.max(0, math.floor(tonumber(state.totalWear) or 0))
    return state
end

function Maintenance.condition(data)
    return Maintenance.ensure(data).condition
end

function Maintenance.coalPenalty(data)
    local condition = Maintenance.condition(data)
    if condition < 25 then return 2 end
    if condition < 50 then return 1 end
    return 0
end

function Maintenance.onTravel(data)
    local state = Maintenance.ensure(data)
    local stop = math.max(1, math.floor(tonumber(data.location) or 1))
    local wear = 6 + math.floor((stop - 1) / 15)
    state.condition = clamp(state.condition - wear, 0, 100)
    state.totalWear = state.totalWear + wear
    return wear, state.condition
end

local function loadImage(name)
    local ok, image = pcall(love.graphics.newImage, ASSET_ROOT .. name)
    if ok then
        image:setFilter("linear", "linear")
        return image
    end
    return nil, tostring(image)
end

local function releaseImage(image)
    if image and image.release then pcall(image.release, image) end
end

function Maintenance.new()
    return {
        open = false,
        assets = nil,
        oiled = {false, false, false, false, false},
        particles = {},
        message = nil,
        completed = false,
        assetError = nil,
    }
end

function Maintenance.release(session)
    if not session.assets then return end
    for _, image in pairs(session.assets) do releaseImage(image) end
    session.assets = nil
end

function Maintenance.close(session)
    session.open = false
    Maintenance.release(session)
end

function Maintenance.open(session, data)
    local state = Maintenance.ensure(data)
    session.open = true
    session.completed = state.lastServicedStop == (data.location or 1)
    session.oiled = {}
    for i = 1, 5 do session.oiled[i] = session.completed end
    session.particles = {}
    session.message = session.completed and "RUNNING GEAR SERVICED AT THIS STOP" or "SELECT EACH DRY BEARING TO APPLY OIL"
    session.assetError = nil
    if not session.assets then
        local background, backgroundError = loadImage("minigame-mockup.png")
        local dry, dryError = loadImage("bearing-dry.png")
        local oiled, oiledError = loadImage("bearing-oiled.png")
        session.assets = {background = background, dry = dry, oiled = oiled}
        session.assetError = backgroundError or dryError or oiledError
    end
    return session.assetError == nil
end

local function allOiled(session)
    for i = 1, 5 do if not session.oiled[i] then return false end end
    return true
end

function Maintenance.servicePoint(session, index)
    if not session.open or session.completed or index < 1 or index > 5 or session.oiled[index] then return false end
    session.oiled[index] = true
    session.message = allOiled(session) and "ALL BEARINGS OILED — PRESS DONE" or ("BEARING " .. index .. " SERVICED")
    for n = 1, 7 do
        session.particles[#session.particles + 1] = {
            x = SLOT_CENTERS[index] + love.math.random(-12, 12),
            y = SLOT_Y + love.math.random(-9, 5),
            vx = love.math.random(-15, 15), vy = love.math.random(-45, -20),
            life = love.math.random() * .35 + .35,
        }
    end
    return true
end

function Maintenance.complete(session, data)
    if session.completed or not allOiled(session) then
        session.message = session.completed and "RUNNING GEAR ALREADY SERVICED HERE" or "OIL ALL FIVE BEARINGS BEFORE FINISHING"
        return false
    end
    local state = Maintenance.ensure(data)
    local before = state.condition
    state.condition = clamp(state.condition + 40, 0, 100)
    state.lastServicedStop = math.max(1, math.floor(tonumber(data.location) or 1))
    state.totalServices = state.totalServices + 1
    session.completed = true
    session.message = "SERVICE COMPLETE  •  CONDITION +" .. math.floor(state.condition - before) .. "%"
    return true
end

function Maintenance.update(session, dt)
    if not session.open then return end
    for i = #session.particles, 1, -1 do
        local particle = session.particles[i]
        particle.life = particle.life - dt
        if particle.life <= 0 then table.remove(session.particles, i)
        else
            particle.x = particle.x + particle.vx * dt
            particle.y = particle.y + particle.vy * dt
            particle.vy = particle.vy + 70 * dt
        end
    end
end

local function drawCentered(image, x, y, maxW, maxH)
    if not image then return false end
    local width, height = image:getDimensions()
    local scale = math.min(maxW / width, maxH / height)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x, y, 0, scale, scale, width / 2, height / 2)
    return true
end

local function drawFallbackPanel()
    love.graphics.setColor(.07, .055, .045, 1)
    love.graphics.rectangle("fill", 0, 90, 960, 540)
    love.graphics.setColor(.28, .20, .12, 1)
    love.graphics.rectangle("line", 18, 108, 924, 504, 12, 12)
    love.graphics.setColor(.91, .63, .20, 1)
    love.graphics.printf("OIL THE RUNNING GEAR", 0, 135, 960, "center", 0, 1.6, 1.6)
    love.graphics.setColor(.26, .12, .08, 1)
    love.graphics.rectangle("fill", 130, 245, 700, 165, 20, 20)
end

function Maintenance.draw(session, data)
    if not session.open then return end
    love.graphics.setColor(0, 0, 0, .82)
    love.graphics.rectangle("fill", 0, 0, 960, 720)
    local background = session.assets and session.assets.background
    if background then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(background, 0, 90, 0, 960 / background:getWidth(), 540 / background:getHeight())
    else drawFallbackPanel() end

    local condition = Maintenance.condition(data)
    love.graphics.setColor(.045, .035, .03, .98)
    love.graphics.rectangle("fill", 53, 525, 220, 42, 5, 5)
    local meterColor = condition < 25 and {.83, .18, .12} or (condition < 50 and {.92, .53, .12} or {.26, .72, .34})
    love.graphics.setColor(.12, .09, .07, 1); love.graphics.rectangle("fill", 64, 547, 195, 9, 3, 3)
    love.graphics.setColor(meterColor); love.graphics.rectangle("fill", 64, 547, 195 * condition / 100, 9, 3, 3)
    love.graphics.setColor(.96, .87, .66, 1); love.graphics.print("CONDITION  " .. math.floor(condition) .. "%", 65, 531, 0, .74, .74)

    local mx, my = session.mouseX or -1000, session.mouseY or -1000
    for i, centerX in ipairs(SLOT_CENTERS) do
        local hover = (mx - centerX) ^ 2 + (my - SLOT_Y) ^ 2 <= 30 ^ 2
        if hover and not session.completed then
            love.graphics.setColor(.95, .66, .20, .30)
            love.graphics.circle("fill", centerX, SLOT_Y, 30)
        end
        local image = session.assets and (session.oiled[i] and session.assets.oiled or session.assets.dry)
        if not drawCentered(image, centerX, SLOT_Y, 54, 46) then
            love.graphics.setColor(session.oiled[i] and .35 or .20, session.oiled[i] and .72 or .18, session.oiled[i] and .34 or .12, 1)
            love.graphics.circle("fill", centerX, SLOT_Y, 19)
            love.graphics.setColor(.92, .71, .28, 1); love.graphics.circle("line", centerX, SLOT_Y, 20)
        end
        love.graphics.setColor(.97, .88, .68, .9)
        love.graphics.printf(tostring(i), centerX - 20, SLOT_Y + 23, 40, "center", 0, .58, .58)
    end
    for _, particle in ipairs(session.particles) do
        love.graphics.setColor(.95, .68, .16, clamp(particle.life * 2, 0, 1))
        love.graphics.circle("fill", particle.x, particle.y, 2.5)
    end

    session.doneRect = {x = 670, y = 525, w = 112, h = 54}
    session.closeRect = {x = 881, y = 104, w = 42, h = 34}
    if allOiled(session) and not session.completed then
        love.graphics.setColor(.96, .70, .20, .24); love.graphics.rectangle("fill", 670, 525, 112, 54, 8, 8)
        love.graphics.setColor(.98, .82, .43, 1); love.graphics.rectangle("line", 670, 525, 112, 54, 8, 8)
    end
    love.graphics.setColor(.08, .055, .04, .92); love.graphics.rectangle("fill", session.closeRect.x, session.closeRect.y, session.closeRect.w, session.closeRect.h, 5, 5)
    love.graphics.setColor(.96, .86, .64, 1); love.graphics.printf("X", session.closeRect.x, session.closeRect.y + 8, session.closeRect.w, "center", 0, .85, .85)
    love.graphics.setColor(.06, .045, .035, .90); love.graphics.rectangle("fill", 225, 598, 510, 27, 5, 5)
    love.graphics.setColor(.96, .86, .64, 1); love.graphics.printf(session.message or "", 225, 605, 510, "center", 0, .67, .67)
    love.graphics.printf("CLICK BEARINGS OR PRESS 1–5   •   ENTER: DONE   •   ESC: CLOSE", 0, 649, 960, "center", 0, .64, .64)
    if session.assetError then
        love.graphics.setColor(.92, .34, .22, 1); love.graphics.printf("Maintenance art fallback active", 0, 679, 960, "center", 0, .58, .58)
    end
end

function Maintenance.mousepressed(session, x, y, data)
    if not session.open then return nil end
    if session.closeRect and x >= session.closeRect.x and x <= session.closeRect.x + session.closeRect.w and y >= session.closeRect.y and y <= session.closeRect.y + session.closeRect.h then
        Maintenance.close(session); return "closed"
    end
    for i, centerX in ipairs(SLOT_CENTERS) do
        if (x - centerX) ^ 2 + (y - SLOT_Y) ^ 2 <= 31 ^ 2 then
            return Maintenance.servicePoint(session, i) and "serviced" or "blocked"
        end
    end
    if session.doneRect and x >= session.doneRect.x and x <= session.doneRect.x + session.doneRect.w and y >= session.doneRect.y and y <= session.doneRect.y + session.doneRect.h then
        return Maintenance.complete(session, data) and "completed" or "blocked"
    end
    return "consumed"
end

function Maintenance.keypressed(session, key, data)
    if not session.open then return nil end
    if key == "escape" or key == "q" then Maintenance.close(session); return "closed" end
    local index = tonumber(key)
    if index and index >= 1 and index <= 5 then return Maintenance.servicePoint(session, index) and "serviced" or "blocked" end
    if key == "return" or key == "kpenter" or key == "space" then return Maintenance.complete(session, data) and "completed" or "blocked" end
    return "consumed"
end

return Maintenance
