local Maintenance = {}
local WheelAnimation = require("game.maintenance_wheel_animation")
local PanelAnimation = require("game.maintenance_panel_animation")
local EngineUpgrades = require("game.engine_upgrades")
local Typography = require("game.typography")
local Accessibility = require("game.accessibility")

local ASSET_ROOT = "assets/sprites/maintenance/oil-running-gear/"
local BACKGROUND_Y = 90
local TARGETS = {
    {x = 313, y = 365, radius = 18, doses = 2},
    {x = 493, y = 365, radius = 18, doses = 1},
    {x = 675, y = 365, radius = 18, doses = 2},
}
local LAMPS = {
    {x = 351, y = 545}, {x = 413, y = 545}, {x = 475, y = 545},
    {x = 537, y = 545}, {x = 599, y = 545},
}
local DONE_RECT = {x = 659, y = 512, w = 106, h = 64}
local CLOSE_RECT = {x = 881, y = 104, w = 42, h = 34}
local TOTAL_DOSES = #LAMPS
local OIL_PER_DROP = 1
local CONDITION_SOURCE, DONE_SOURCE = PanelAnimation.sourceRects()
local BASE_OIL_CAPACITY=20
local SERVICE_OIL_COST=5
local SERVICE_RESTORE=40

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

function Maintenance.oilSupply(data)
    data.resources = type(data.resources) == "table" and data.resources or {}
    data.resources.oil = math.max(0, math.floor(tonumber(data.resources.oil) or 0))
    return data.resources.oil
end

local function ownsCar(data,id)
    for _,owned in ipairs((data and data.trainCars) or {}) do if owned==id then return true end end
    return false
end

function Maintenance.oilCapacity(data)
    return BASE_OIL_CAPACITY+(ownsCar(data,"coal-hauler") and 10 or 0)
end

function Maintenance.serviceOilCost()
    return SERVICE_OIL_COST
end

function Maintenance.serviceRestore()
    return SERVICE_RESTORE
end

function Maintenance.wearProfile(data)
    local stop=math.max(1,math.floor(tonumber(data and data.location) or 1))
    local carCount=math.max(1,#((data and data.trainCars) or {"living-car"}))
    local routeWear=5+math.floor((stop-1)/15)
    local carWear=math.floor(math.max(0,carCount-1)/3)
    local engineReduction=EngineUpgrades.profile(data and data.engineLevel).wearReduction or 0
    return {wear=math.max(3,routeWear+carWear-engineReduction),routeWear=routeWear,carWear=carWear,
        engineReduction=engineReduction,stop=stop,carCount=carCount}
end

function Maintenance.status(data)
    local condition=Maintenance.condition(data)
    local label=condition<25 and "CRITICAL" or (condition<50 and "WORN" or (condition<75 and "FAIR" or "READY"))
    local speed=condition<25 and .82 or (condition<50 and .92 or 1)
    return {condition=condition,label=label,coalPenalty=Maintenance.coalPenalty(data),speed=speed,
        projectedWear=Maintenance.wearProfile(data).wear,oil=Maintenance.oilSupply(data),oilCapacity=Maintenance.oilCapacity(data),
        serviceCost=SERVICE_OIL_COST,serviceRestore=SERVICE_RESTORE}
end

function Maintenance.coalPenalty(data)
    local condition = Maintenance.condition(data)
    if condition < 25 then return 2 end
    if condition < 50 then return 1 end
    return 0
end

function Maintenance.onTravel(data)
    local state = Maintenance.ensure(data)
    local profile=Maintenance.wearProfile(data)
    local wear=profile.wear
    state.condition = clamp(state.condition - wear, 0, 100)
    state.totalWear = state.totalWear + wear
    state.lastWear=wear
    state.lastTravelStop=profile.stop
    return wear, state.condition
end

function Maintenance.audit()
    local base={location=1,engineLevel=0,trainCars={"living-car"},resources={oil=20},maintenance={condition=100}}
    local expanded={location=46,engineLevel=0,trainCars={"living-car","coal-hauler","storage","greenhouse","sleeper","medical","navigator"},resources={oil=30},maintenance={condition=40}}
    local upgraded={location=46,engineLevel=4,trainCars=expanded.trainCars,resources={oil=30},maintenance={condition=20}}
    local baseWear=Maintenance.wearProfile(base); local expandedWear=Maintenance.wearProfile(expanded); local upgradedWear=Maintenance.wearProfile(upgraded)
    local applied,condition=Maintenance.onTravel(upgraded)
    local low=Maintenance.status(upgraded)
    return {ready=baseWear.wear==5 and expandedWear.wear==10 and upgradedWear.wear==8 and applied==8 and condition==12
            and low.coalPenalty==2 and low.speed==.82 and Maintenance.oilCapacity(expanded)==30,
        baseWear=baseWear.wear,expandedWear=expandedWear.wear,upgradedWear=upgradedWear.wear,
        oilCapacity=Maintenance.oilCapacity(expanded),serviceCost=SERVICE_OIL_COST,serviceRestore=SERVICE_RESTORE,
        lowCoalPenalty=low.coalPenalty,lowSpeed=low.speed,curve="maintenance-v1"}
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
        donePress = 0,
        conditionMotion = 0,
        conditionFrom = 72,
        conditionTo = 72,
        title = "OIL THE RUNNING GEAR",
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

function Maintenance.reservedOil(session)
    return session.completed and 0 or progressCount(session) * OIL_PER_DROP
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

function Maintenance.setTitle(session, title)
    if type(title) == "string" and title ~= "" then session.title = title end
end

function Maintenance.animationSpec()
    local doneFrames, conditionFrames = PanelAnimation.frameCount()
    return {wheelFrames = WheelAnimation.frameCount(), doneFrames = doneFrames, conditionFrames = conditionFrames}
end

function Maintenance.animationState(session)
    local wheelElapsed = session.testMotion > 0 and (WheelAnimation.duration() - session.testMotion) or 0
    return {
        wheelFrame = WheelAnimation.frameAt(wheelElapsed),
        doneFrame = PanelAnimation.doneFrame(session.donePress or 0),
        conditionFrame = PanelAnimation.conditionFrame(session.conditionMotion or 0),
        smokePuffs = #(session.serviceBursts or {}),
    }
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
    session.donePress = 0
    session.conditionMotion = 0
    session.conditionFrom = state.condition
    session.conditionTo = state.condition
    session.message = session.completed and "RUNNING GEAR SERVICED AT THIS STOP" or "PLACE THE OIL-CAN NOZZLE ON A WHEEL HUB"
    session.assetError = nil
    session.pulse = 0
    if not session.assets then
        local background, backgroundError = loadImage("minigame-background.png")
        local base, baseError = loadImage("minigame-base.png")
        local oilCan, oilCanError = loadImage("oil-can.png")
        local oilDrop, oilDropError = loadImage("oil-drop.png")
        local serviceEffect, serviceEffectError = loadImage("service-effect.png")
        local conditionQuad, doneQuad
        if background then
            local width, height = background:getDimensions()
            conditionQuad = love.graphics.newQuad(CONDITION_SOURCE.x, CONDITION_SOURCE.y, CONDITION_SOURCE.w, CONDITION_SOURCE.h, width, height)
            doneQuad = love.graphics.newQuad(DONE_SOURCE.x, DONE_SOURCE.y, DONE_SOURCE.w, DONE_SOURCE.h, width, height)
        end
        session.assets = {background = background, base = base, oilCan = oilCan, oilDrop = oilDrop,
            serviceEffect = serviceEffect, conditionQuad = conditionQuad, doneQuad = doneQuad}
        session.assetError = backgroundError or baseError or oilCanError or oilDropError or serviceEffectError
    end
    session.cursorActive = not session.completed and session.assets and session.assets.oilCan ~= nil
    setSystemCursorVisible(not session.cursorActive)
    return session.assetError == nil
end

local function allOiled(session)
    return progressCount(session) >= TOTAL_DOSES
end

function Maintenance.servicePoint(session, index, data)
    local target = TARGETS[index]
    if not session.open or session.completed or not target then return false end
    local current = session.targetDoses[index] or 0
    if current >= target.doses then
        session.message = "THAT HUB IS FULLY OILED — MOVE TO ANOTHER"
        return false
    end
    if not data or Maintenance.oilSupply(data) < (progressCount(session) + 1) * OIL_PER_DROP then
        session.message = "NOT ENOUGH TRAIN OIL — FIND AN OIL CANISTER"
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
    local oilCost = Maintenance.serviceOilCost(data)
    if Maintenance.oilSupply(data) < oilCost then
        session.message = "NOT ENOUGH TRAIN OIL TO COMPLETE SERVICE"
        return false
    end
    local before = state.condition
    state.condition = clamp(state.condition + Maintenance.serviceRestore(data), 0, 100)
    state.lastServicedStop = math.max(1, math.floor(tonumber(data.location) or 1))
    state.totalServices = state.totalServices + 1
    data.resources.oil = data.resources.oil - oilCost
    session.completed = true
    session.cursorActive = false
    session.testMotion = WheelAnimation.duration()
    session.donePress = PanelAnimation.doneDuration()
    session.conditionFrom = before
    session.conditionTo = state.condition
    session.conditionMotion = PanelAnimation.conditionDuration()
    for i, target in ipairs(TARGETS) do
        session.targetMotion[i] = WheelAnimation.duration()
        session.serviceBursts[#session.serviceBursts + 1] = {x = target.x + 12, y = target.y - 18, life = 1.0, total = 1.0, delay = (i - 1) * .10}
    end
    setSystemCursorVisible(true)
    session.message = "DONE  •  " .. oilCost .. " OIL USED  •  CONDITION +" .. math.floor(state.condition - before) .. "%"
    return true
end

function Maintenance.update(session, dt)
    if not session.open then return end
    session.pulse = (session.pulse + dt) % (math.pi * 2)
    session.canPump = math.max(0, session.canPump - dt)
    session.testMotion = math.max(0, session.testMotion - dt)
    session.donePress = math.max(0, session.donePress - dt)
    session.conditionMotion = math.max(0, session.conditionMotion - dt)
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
    Typography.drawText(love.graphics,"OIL THE RUNNING GEAR",80,116,800,48,{scale=1.4,minScale=1,align="center",valign="center"})
end

local function drawConditionPanel(session, data)
    local condition = session.conditionMotion > 0 and
        PanelAnimation.conditionValue(session.conditionFrom, session.conditionTo, session.conditionMotion) or Maintenance.condition(data)
    local source, quad = session.assets and session.assets.background, session.assets and session.assets.conditionQuad
    if not PanelAnimation.drawCondition(source, quad, session.conditionMotion) then
        love.graphics.setColor(.035, .027, .023, .97); love.graphics.rectangle("fill", 20, 483, 276, 123, 7, 7)
    end
    -- The original frame and label remain sprite art; only the instrument's
    -- inner reading is live so saved wear is represented accurately.
    love.graphics.setColor(.08, .055, .04, .97); love.graphics.rectangle("fill", 54, 531, 215, 31, 3, 3)
    local meterColor = condition < 25 and {.88, .20, .12} or (condition < 50 and {.95, .55, .12} or {.34, .78, .34})
    love.graphics.setColor(meterColor); love.graphics.rectangle("fill", 58, 536, 207 * condition / 100, 20, 2, 2)
    love.graphics.setColor(.96, .82, .48, 1); Typography.drawText(love.graphics,math.floor(condition).."%",202,499,68,30,{scale=1,minScale=.9,align="right",valign="center"})
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
    love.graphics.setColor(.08, .055, .04, .96); love.graphics.rectangle("fill",target.x-27,target.y-70,54,32,8,8)
    love.graphics.setColor(1, .84, .42, 1); Typography.drawText(love.graphics,current.."/"..target.doses,target.x-25,target.y-69,50,30,{scale=1,minScale=.9,align="center",valign="center"})
end

local function targetMotionAngle(session, index)
    local timer = session.targetMotion[index] or 0
    if timer <= 0 then return 0 end
    local elapsed = .42 - timer
    return math.sin(elapsed * 25) * .12 * (timer / .42)
end

local function drawDoneSprite(session)
    local source, quad = session.assets and session.assets.background, session.assets and session.assets.doneQuad
    local hover = pointInRect(session.mouseX or -1000, session.mouseY or -1000, DONE_RECT)
    PanelAnimation.drawDone(source, quad, session.donePress, hover, allOiled(session) and not session.completed)
end

local function drawTitle(session)
    local title = session.title or "OIL THE RUNNING GEAR"
    love.graphics.push()
    love.graphics.translate(480, 126)
    love.graphics.scale(1.20, 1.20)
    love.graphics.setColor(.08, .045, .02, .95)
    love.graphics.printf(title, -155, -8, 310, "center")
    love.graphics.setColor(.92, .63, .25, 1)
    love.graphics.printf(title, -155, -10, 310, "center")
    love.graphics.pop()
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
                local scale = .052 + progress * .018
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
    local base = session.assets and session.assets.base
    local elapsed = session.testMotion > 0 and (WheelAnimation.duration() - session.testMotion) or 0
    local layered = WheelAnimation.draw(background, base, BACKGROUND_Y, elapsed)
    if not layered then
        if background then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(background, 0, BACKGROUND_Y, 0, 960 / background:getWidth(), 540 / background:getHeight())
        else drawFallbackPanel() end
    end

    if session.testMotion <= 0 then for i, target in ipairs(TARGETS) do drawMovingHub(session, i, target, background) end end
    drawTitle(session)
    for i, target in ipairs(TARGETS) do drawTargetState(session, i, target) end
    for i, lamp in ipairs(LAMPS) do drawLamp(session, i, lamp) end
    for _, particle in ipairs(session.particles) do
        love.graphics.setColor(1, .68, .10, clamp(particle.life * 2, 0, 1))
        love.graphics.circle("fill", particle.x, particle.y, 2.7)
    end
    drawAnimatedSprites(session)
    drawConditionPanel(session, data)
    drawDoneSprite(session)

    local textScale=Accessibility.textScale(data)
    local mobile=os.getenv("MOUSE_FRONTIER_MOBILE")=="1" or (love.system and love.system.getOS and love.system.getOS()=="Android")
    love.graphics.setColor(.035, .027, .023, .96); love.graphics.rectangle("fill",690,578,240,58,5,5)
    love.graphics.setColor(.96, .82, .48, 1)
    Typography.drawText(love.graphics,"OIL "..Maintenance.oilSupply(data).." / "..Maintenance.oilCapacity(data).."\nSERVICE COST "..Maintenance.serviceOilCost(data),700,582,220,50,{scale=.95*textScale,minScale=.85,align="center",valign="center"})

    if allOiled(session) and not session.completed then
        love.graphics.setColor(1, .70, .12, .22); love.graphics.rectangle("fill", DONE_RECT.x, DONE_RECT.y, DONE_RECT.w, DONE_RECT.h, 8, 8)
        love.graphics.setColor(1, .84, .32, 1); love.graphics.setLineWidth(2); love.graphics.rectangle("line", DONE_RECT.x, DONE_RECT.y, DONE_RECT.w, DONE_RECT.h, 8, 8); love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(.08, .055, .04, .94); love.graphics.rectangle("fill", CLOSE_RECT.x, CLOSE_RECT.y, CLOSE_RECT.w, CLOSE_RECT.h, 5, 5)
    love.graphics.setColor(.96, .86, .64, 1); Typography.drawText(love.graphics,"X",CLOSE_RECT.x,CLOSE_RECT.y,CLOSE_RECT.w,CLOSE_RECT.h,{scale=1,minScale=.9,align="center",valign="center"})
    love.graphics.setColor(.035, .027, .023, .96); love.graphics.rectangle("fill",300,574,378,62,5,5)
    love.graphics.setColor(.96, .86, .64, 1); Typography.drawText(love.graphics,session.message or "",310,579,358,52,{scale=.95*textScale,minScale=.85,align="center",valign="center"})
    local instructions=mobile and "Oil three hubs. Tap DONE when all five lamps are lit."
        or "OIL THREE HUBS  •  ENTER: DONE  •  ESC: CLOSE"
    Typography.drawText(love.graphics,instructions,24,645,912,35,{scale=.95*textScale,minScale=.85,align="center",valign="center"})
    if session.assetError then
        love.graphics.setColor(.92, .34, .22, 1); Typography.drawText(love.graphics,"Maintenance art fallback active",24,683,912,28,{scale=.85,minScale=.85,align="center",valign="center"})
    end
    drawOilCanCursor(session)
end

function Maintenance.mousepressed(session, x, y, data)
    if not session.open then return nil end
    if pointInRect(x, y, CLOSE_RECT) then Maintenance.close(session); return "closed" end
    if session.cursorActive then
        for i, target in ipairs(TARGETS) do
            if (x - target.x) ^ 2 + (y - target.y) ^ 2 <= target.radius ^ 2 then
                return Maintenance.servicePoint(session, i, data) and "serviced" or "blocked"
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
    if index and index >= 1 and index <= #TARGETS then return Maintenance.servicePoint(session, index, data) and "serviced" or "blocked" end
    if key == "return" or key == "kpenter" or key == "space" then return Maintenance.complete(session, data) and "completed" or "blocked" end
    return "consumed"
end

return Maintenance
