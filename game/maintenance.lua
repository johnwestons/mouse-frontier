local Maintenance = {}

local ASSET_ROOT = "assets/sprites/maintenance/oil-running-gear/"
local BACKGROUND_Y = 90
local TARGETS = {
    {x = 340, y = 343, radius = 42, doses = 2},
    {x = 537, y = 343, radius = 42, doses = 1},
    {x = 735, y = 343, radius = 42, doses = 2},
}
local LAMPS = {
    {x = 351, y = 545}, {x = 413, y = 545}, {x = 475, y = 545},
    {x = 537, y = 545}, {x = 599, y = 545},
}
local DONE_RECT = {x = 659, y = 512, w = 106, h = 64}
local CLOSE_RECT = {x = 881, y = 104, w = 42, h = 34}
local TOTAL_DOSES = #LAMPS

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function pointInRect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function setSystemCursorVisible(visible)
    if love.mouse and love.mouse.setVisible then pcall(love.mouse.setVisible, visible) end
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
        targetDoses = {0, 0, 0},
        particles = {},
        message = nil,
        completed = false,
        cursorActive = false,
        assetError = nil,
        pulse = 0,
        targetMotion = {0, 0, 0},
        lampPulse = {0, 0, 0, 0, 0},
        spriteDrops = {},
        serviceBursts = {},
        canPump = 0,
        testMotion = 0,
        mouseX = 480,
        mouseY = 360,
    }
end

function Maintenance.release(session)
    if session.assets then
        for _, image in pairs(session.assets) do releaseImage(image) end
        session.assets = nil
    end
    session.cursorActive = false
    setSystemCursorVisible(true)
end

function Maintenance.close(session)
    session.open = false
    Maintenance.release(session)
end

local function progressCount(session)
    local total = 0
    for i = 1, #TARGETS do total = total + clamp(session.targetDoses[i] or 0, 0, TARGETS[i].doses) end
    return total
end

function Maintenance.progressCount(session)
    return progressCount(session)
end

function Maintenance.progressLights(session)
    local count, lights = progressCount(session), {}
    for i = 1, TOTAL_DOSES do lights[i] = i <= count end
    return lights
end

function Maintenance.targetCount()
    return #TARGETS
end

function Maintenance.targetState(session)
    local result = {}
    for i, target in ipairs(TARGETS) do
        result[i] = {doses = session.targetDoses[i] or 0, required = target.doses,
            complete = (session.targetDoses[i] or 0) >= target.doses}
    end
    return result
end

function Maintenance.targetPosition(index)
    local target = TARGETS[index]
    return target and target.x, target and target.y
end

function Maintenance.open(session, data)
    local state = Maintenance.ensure(data)
    session.open = true
    session.completed = state.lastServicedStop == (data.location or 1)
    session.targetDoses = {}
    for i, target in ipairs(TARGETS) do session.targetDoses[i] = session.completed and target.doses or 0 end
    session.particles = {}
    session.spriteDrops = {}
    session.serviceBursts = {}
    session.targetMotion = {0, 0, 0}
    session.lampPulse = {0, 0, 0, 0, 0}
    session.canPump = 0
    session.testMotion = 0
    session.message = session.completed and "RUNNING GEAR SERVICED AT THIS STOP" or "PLACE THE OIL-CAN NOZZLE ON A WHEEL HUB"
    session.assetError = nil
    session.pulse = 0
    if not session.assets then
        local background, backgroundError = loadImage("minigame-background.png")
        local oilCan, oilCanError = loadImage("oil-can.png")
        local oilDrop, oilDropError = loadImage("oil-drop.png")
        local serviceEffect, serviceEffectError = loadImage("service-effect.png")
        session.assets = {background = background, oilCan = oilCan, oilDrop = oilDrop, serviceEffect = serviceEffect}
        session.assetError = backgroundError or oilCanError or oilDropError or serviceEffectError
    end
    session.cursorActive = not session.completed and session.assets and session.assets.oilCan ~= nil
    setSystemCursorVisible(not session.cursorActive)
    return session.assetError == nil
end

local function allOiled(session)
    return progressCount(session) >= TOTAL_DOSES
end

function Maintenance.servicePoint(session, index)
    local target = TARGETS[index]
    if not session.open or session.completed or not target then return false end
    local current = session.targetDoses[index] or 0
    if current >= target.doses then
        session.message = "THAT HUB IS FULLY OILED — MOVE TO ANOTHER"
        return false
    end
    session.targetDoses[index] = current + 1
    local count = progressCount(session)
    session.targetMotion[index] = .42
    session.canPump = .22
    session.lampPulse[count] = .50
    session.spriteDrops[#session.spriteDrops + 1] = {x = target.x, y = target.y - 8, life = .48, total = .48}
    if count >= TOTAL_DOSES then
        session.message = "ALL FIVE OIL LAMPS ARE LIT — PRESS DONE"
    else
        session.message = "OIL APPLIED  •  " .. count .. " / " .. TOTAL_DOSES .. " LAMPS LIT"
    end
    for n = 1, 9 do
        session.particles[#session.particles + 1] = {
            x = target.x + love.math.random(-8, 8), y = target.y + love.math.random(-6, 6),
            vx = love.math.random(-18, 18), vy = love.math.random(-40, -16),
            life = love.math.random() * .35 + .35,
        }
    end
    return true
end

function Maintenance.complete(session, data)
    if session.completed or not allOiled(session) then
        session.message = session.completed and "RUNNING GEAR ALREADY SERVICED HERE" or "LIGHT ALL FIVE OIL LAMPS BEFORE FINISHING"
        return false
    end
    local state = Maintenance.ensure(data)
    local before = state.condition
    state.condition = clamp(state.condition + 40, 0, 100)
    state.lastServicedStop = math.max(1, math.floor(tonumber(data.location) or 1))
    state.totalServices = state.totalServices + 1
    session.completed = true
    session.cursorActive = false
    session.testMotion = 1.45
    for i, target in ipairs(TARGETS) do
        session.targetMotion[i] = 1.45
        session.serviceBursts[#session.serviceBursts + 1] = {x = target.x + 12, y = target.y - 18, life = 1.0, total = 1.0, delay = (i - 1) * .10}
    end
    setSystemCursorVisible(true)
    session.message = "SERVICE COMPLETE  •  CONDITION +" .. math.floor(state.condition - before) .. "%"
    return true
end

function Maintenance.update(session, dt)
    if not session.open then return end
    session.pulse = (session.pulse + dt) % (math.pi * 2)
    session.canPump = math.max(0, session.canPump - dt)
    session.testMotion = math.max(0, session.testMotion - dt)
    for i = 1, #TARGETS do session.targetMotion[i] = math.max(0, (session.targetMotion[i] or 0) - dt) end
    for i = 1, TOTAL_DOSES do session.lampPulse[i] = math.max(0, (session.lampPulse[i] or 0) - dt) end
    for i = #session.spriteDrops, 1, -1 do
        local drop = session.spriteDrops[i]
        drop.life = drop.life - dt
        if drop.life <= 0 then table.remove(session.spriteDrops, i)
        else drop.y = drop.y + 24 * dt end
    end
    for i = #session.serviceBursts, 1, -1 do
        local burst = session.serviceBursts[i]
        if burst.delay > 0 then burst.delay = burst.delay - dt
        else
            burst.life = burst.life - dt
            burst.y = burst.y - 18 * dt
            if burst.life <= 0 then table.remove(session.serviceBursts, i) end
        end
    end
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

local function drawFallbackPanel()
    love.graphics.setColor(.055, .043, .035, 1)
    love.graphics.rectangle("fill", 0, BACKGROUND_Y, 960, 540)
    love.graphics.setColor(.30, .20, .11, 1)
    love.graphics.rectangle("line", 18, BACKGROUND_Y + 18, 924, 504, 12, 12)
    love.graphics.setColor(.91, .63, .20, 1)
    love.graphics.printf("OIL THE RUNNING GEAR", 0, 130, 960, "center", 0, 1.6, 1.6)
end

local function drawConditionPanel(data)
    local condition = Maintenance.condition(data)
    love.graphics.setColor(.035, .027, .023, .97)
    love.graphics.rectangle("fill", 44, 487, 226, 78, 7, 7)
    love.graphics.setColor(.54, .34, .15, 1)
    love.graphics.setLineWidth(2); love.graphics.rectangle("line", 44, 487, 226, 78, 7, 7); love.graphics.setLineWidth(1)
    love.graphics.setColor(.96, .82, .48, 1)
    love.graphics.print("GEAR CONDITION", 59, 498, 0, .70, .70)
    love.graphics.printf(math.floor(condition) .. "%", 205, 497, 48, "right", 0, .76, .76)
    love.graphics.setColor(.10, .07, .05, 1); love.graphics.rectangle("fill", 59, 526, 194, 18, 4, 4)
    local meterColor = condition < 25 and {.88, .20, .12} or (condition < 50 and {.95, .55, .12} or {.34, .78, .34})
    love.graphics.setColor(meterColor); love.graphics.rectangle("fill", 62, 529, 188 * condition / 100, 12, 3, 3)
    love.graphics.setColor(.87, .75, .52, 1)
    love.graphics.printf(condition < 25 and "CRITICAL  •  +2 COAL" or (condition < 50 and "WORN  •  +1 COAL" or "RUNNING EFFICIENTLY"), 55, 550, 204, "center", 0, .54, .54)
end

local function drawTargetState(session, index, target)
    local current = session.targetDoses[index] or 0
    local complete = current >= target.doses
    local hover = session.cursorActive and ((session.mouseX - target.x) ^ 2 + (session.mouseY - target.y) ^ 2 <= target.radius ^ 2)
    if complete then
        local alpha = .22 + .08 * math.sin(session.pulse * 3 + index)
        love.graphics.setColor(1, .72, .12, alpha); love.graphics.circle("fill", target.x, target.y, target.radius - 5)
        love.graphics.setColor(1, .82, .25, .95); love.graphics.setLineWidth(3); love.graphics.circle("line", target.x, target.y, target.radius - 5); love.graphics.setLineWidth(1)
    elseif hover then
        love.graphics.setColor(1, .75, .20, .18); love.graphics.circle("fill", target.x, target.y, target.radius)
        love.graphics.setColor(1, .82, .35, .90); love.graphics.setLineWidth(2); love.graphics.circle("line", target.x, target.y, target.radius); love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(.08, .055, .04, .88); love.graphics.circle("fill", target.x, target.y - 55, 13)
    love.graphics.setColor(1, .84, .42, 1); love.graphics.printf(current .. "/" .. target.doses, target.x - 20, target.y - 60, 40, "center", 0, .58, .58)
end

local function targetMotionAngle(session, index)
    local timer = session.targetMotion[index] or 0
    if timer <= 0 then return 0 end
    if session.testMotion > 0 then
        local elapsed = 1.45 - session.testMotion
        return elapsed * 7.5 + (index - 1) * .05
    end
    local elapsed = .42 - timer
    return math.sin(elapsed * 25) * .12 * (timer / .42)
end

local function drawMovingHub(session, index, target, background)
    local angle = targetMotionAngle(session, index)
    if not background or math.abs(angle) < .001 or not love.graphics.stencil then return end
    love.graphics.stencil(function() love.graphics.circle("fill", target.x, target.y, target.radius - 5) end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.push()
    love.graphics.translate(target.x, target.y)
    love.graphics.rotate(angle)
    love.graphics.translate(-target.x, -target.y)
    love.graphics.draw(background, 0, BACKGROUND_Y, 0, 960 / background:getWidth(), 540 / background:getHeight())
    love.graphics.pop()
    love.graphics.setStencilTest()
end

local function drawLamp(session, index, lamp)
    local lit = index <= progressCount(session)
    if lit then
        local pulse = session.lampPulse[index] or 0
        local glow = 28 + 10 * (pulse / .50)
        love.graphics.setColor(1, .67, .06, .16 + .20 * (pulse / .50)); love.graphics.circle("fill", lamp.x, lamp.y, glow)
        love.graphics.setColor(1, .72, .08, .30); love.graphics.circle("fill", lamp.x, lamp.y, 21)
        love.graphics.setColor(1, .84, .20, 1); love.graphics.circle("fill", lamp.x, lamp.y, 13)
        love.graphics.setColor(1, .95, .58, 1); love.graphics.circle("fill", lamp.x - 3, lamp.y - 4, 5)
    else
        love.graphics.setColor(.08, .06, .045, .90); love.graphics.circle("fill", lamp.x, lamp.y, 15)
        love.graphics.setColor(.38, .27, .14, 1); love.graphics.circle("line", lamp.x, lamp.y, 16)
    end
end

local function drawOilCanCursor(session)
    if not session.cursorActive then return end
    local oilCan = session.assets and session.assets.oilCan
    if not oilCan then return end
    -- The source nozzle points right. A negative X scale mirrors it so the
    -- nozzle tip is the exact mouse hotspot and the can body hangs down/right.
    love.graphics.setColor(1, 1, 1, 1)
    local pump = session.canPump > 0 and math.sin((.22 - session.canPump) * 32) * .055 * (session.canPump / .22) or 0
    love.graphics.draw(oilCan, session.mouseX, session.mouseY, pump, -.20, .20, 1494, 66)
end

local function drawAnimatedSprites(session)
    local oilDrop = session.assets and session.assets.oilDrop
    if oilDrop then
        local width, height = oilDrop:getDimensions()
        for _, drop in ipairs(session.spriteDrops) do
            local scale = .024 * (1 + .18 * (drop.life / drop.total))
            love.graphics.setColor(1, 1, 1, clamp(drop.life * 3, 0, 1))
            love.graphics.draw(oilDrop, drop.x, drop.y, 0, scale, scale, width / 2, height / 2)
        end
    end
    local effect = session.assets and session.assets.serviceEffect
    if effect then
        local width, height = effect:getDimensions()
        for _, burst in ipairs(session.serviceBursts) do
            if burst.delay <= 0 then
                local progress = 1 - burst.life / burst.total
                local scale = .07 + progress * .025
                love.graphics.setColor(1, 1, 1, clamp(burst.life * 1.5, 0, 1))
                love.graphics.draw(effect, burst.x, burst.y, -.25, scale, scale, width * .25, height * .72)
            end
        end
    end
end

function Maintenance.draw(session, data)
    if not session.open then return end
    love.graphics.setColor(0, 0, 0, .84); love.graphics.rectangle("fill", 0, 0, 960, 720)
    local background = session.assets and session.assets.background
    if background then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(background, 0, BACKGROUND_Y, 0, 960 / background:getWidth(), 540 / background:getHeight())
    else drawFallbackPanel() end

    for i, target in ipairs(TARGETS) do drawMovingHub(session, i, target, background) end
    for i, target in ipairs(TARGETS) do drawTargetState(session, i, target) end
    for i, lamp in ipairs(LAMPS) do drawLamp(session, i, lamp) end
    for _, particle in ipairs(session.particles) do
        love.graphics.setColor(1, .68, .10, clamp(particle.life * 2, 0, 1))
        love.graphics.circle("fill", particle.x, particle.y, 2.7)
    end
    drawAnimatedSprites(session)
    drawConditionPanel(data)

    if allOiled(session) and not session.completed then
        love.graphics.setColor(1, .70, .12, .22); love.graphics.rectangle("fill", DONE_RECT.x, DONE_RECT.y, DONE_RECT.w, DONE_RECT.h, 8, 8)
        love.graphics.setColor(1, .84, .32, 1); love.graphics.setLineWidth(2); love.graphics.rectangle("line", DONE_RECT.x, DONE_RECT.y, DONE_RECT.w, DONE_RECT.h, 8, 8); love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(.08, .055, .04, .94); love.graphics.rectangle("fill", CLOSE_RECT.x, CLOSE_RECT.y, CLOSE_RECT.w, CLOSE_RECT.h, 5, 5)
    love.graphics.setColor(.96, .86, .64, 1); love.graphics.printf("X", CLOSE_RECT.x, CLOSE_RECT.y + 8, CLOSE_RECT.w, "center", 0, .85, .85)
    love.graphics.setColor(.035, .027, .023, .92); love.graphics.rectangle("fill", 275, 570, 410, 29, 5, 5)
    love.graphics.setColor(.96, .86, .64, 1); love.graphics.printf(session.message or "", 275, 578, 410, "center", 0, .61, .61)
    love.graphics.printf("OIL THE THREE HUBS  •  FIVE LAMPS  •  ENTER: DONE  •  ESC: CLOSE", 0, 651, 960, "center", 0, .63, .63)
    if session.assetError then
        love.graphics.setColor(.92, .34, .22, 1); love.graphics.printf("Maintenance art fallback active", 0, 680, 960, "center", 0, .58, .58)
    end
    drawOilCanCursor(session)
end

function Maintenance.mousepressed(session, x, y, data)
    if not session.open then return nil end
    if pointInRect(x, y, CLOSE_RECT) then Maintenance.close(session); return "closed" end
    if session.cursorActive then
        for i, target in ipairs(TARGETS) do
            if (x - target.x) ^ 2 + (y - target.y) ^ 2 <= target.radius ^ 2 then
                return Maintenance.servicePoint(session, i) and "serviced" or "blocked"
            end
        end
    end
    if pointInRect(x, y, DONE_RECT) then return Maintenance.complete(session, data) and "completed" or "blocked" end
    return "consumed"
end

function Maintenance.keypressed(session, key, data)
    if not session.open then return nil end
    if key == "escape" or key == "q" then Maintenance.close(session); return "closed" end
    local index = tonumber(key)
    if index and index >= 1 and index <= #TARGETS then return Maintenance.servicePoint(session, index) and "serviced" or "blocked" end
    if key == "return" or key == "kpenter" or key == "space" then return Maintenance.complete(session, data) and "completed" or "blocked" end
    return "consumed"
end

return Maintenance
