local WheelAnimation = {}

local FRAME_DURATION = .16
local FRAMES = {
    {angle = 0,                 rodX = 0,  rodY = 0},
    {angle = math.pi * 2 / 5,  rodX = 2,  rodY = -7},
    {angle = math.pi * 4 / 5,  rodX = -2, rodY = -4},
    {angle = math.pi * 6 / 5,  rodX = -2, rodY = 4},
    {angle = math.pi * 8 / 5,  rodX = 2,  rodY = 7},
}

local WHEELS = {
    {x = 313, y = 365},
    {x = 493, y = 365},
    {x = 675, y = 365},
}
local WHEEL_RADIUS_X = 84
local WHEEL_RADIUS_Y = 82
local HUB_RADIUS = 31
local ROD = {x = 225, y = 346, w = 535, h = 38}

function WheelAnimation.duration()
    return #FRAMES * FRAME_DURATION
end

function WheelAnimation.frameDuration()
    return FRAME_DURATION
end

function WheelAnimation.frameCount()
    return #FRAMES
end

function WheelAnimation.frameAt(elapsed)
    return math.max(1, math.min(#FRAMES, math.floor(math.max(0, elapsed) / FRAME_DURATION) + 1))
end

local function drawSource(source, backgroundY, rotation, centerX, centerY, offsetX, offsetY)
    local scaleX, scaleY = 960 / source:getWidth(), 540 / source:getHeight()
    love.graphics.push()
    love.graphics.translate((offsetX or 0) + centerX, (offsetY or 0) + centerY)
    love.graphics.rotate(rotation or 0)
    love.graphics.translate(-centerX, -centerY)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(source, 0, backgroundY, 0, scaleX, scaleY)
    love.graphics.pop()
end

local function withWheelStencil(wheel, excludeRodBand, callback)
    love.graphics.stencil(function()
        love.graphics.ellipse("fill", wheel.x, wheel.y, WHEEL_RADIUS_X, WHEEL_RADIUS_Y)
    end, "replace", 1)
    if excludeRodBand then
        -- Scissor rectangles use screen coordinates in LÖVE, while this panel
        -- is drawn in scaled game coordinates. Subtract the rod band from the
        -- stencil instead so the full wheel survives at every window size.
        love.graphics.stencil(function()
            love.graphics.rectangle("fill", wheel.x - WHEEL_RADIUS_X, wheel.y - 19,
                WHEEL_RADIUS_X * 2, 38)
        end, "replace", 0, true)
    end
    love.graphics.setStencilTest("equal", 1)
    callback()
    love.graphics.setStencilTest()
end

local function drawOuterWheel(source, backgroundY, wheel, angle)
    withWheelStencil(wheel, true, function()
        -- The rod crosses the wheel centers in the source art. Render the
        -- rotating wheel above and below that band, then layer the animated
        -- rod and rotating axle square separately for clean mechanical depth.
        drawSource(source, backgroundY, angle, wheel.x, wheel.y)
    end)
end

local function drawRod(source, backgroundY, frame)
    local x, y = ROD.x + frame.rodX, ROD.y + frame.rodY
    love.graphics.stencil(function()
        love.graphics.rectangle("fill", x, y, ROD.w, ROD.h, 4, 4)
        love.graphics.circle("fill", WHEELS[1].x + frame.rodX, WHEELS[1].y + frame.rodY, 25)
        love.graphics.circle("fill", WHEELS[2].x + frame.rodX, WHEELS[2].y + frame.rodY, 25)
        love.graphics.circle("fill", WHEELS[3].x + frame.rodX, WHEELS[3].y + frame.rodY, 25)
    end, "replace", 1)
    love.graphics.setStencilTest("equal", 1)
    drawSource(source, backgroundY, 0, 0, 0, frame.rodX, frame.rodY)
    love.graphics.setStencilTest()
end

local function drawHub(source, backgroundY, wheel, angle)
    love.graphics.stencil(function() love.graphics.circle("fill", wheel.x, wheel.y, HUB_RADIUS) end, "replace", 1)
    love.graphics.setStencilTest("equal", 1)
    drawSource(source, backgroundY, angle, wheel.x, wheel.y)
    love.graphics.setStencilTest()
end

function WheelAnimation.draw(source, clearedBackground, backgroundY, elapsed)
    if not source or not clearedBackground or not love.graphics.stencil then return false end
    local frame = FRAMES[WheelAnimation.frameAt(elapsed)]
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(clearedBackground, 0, backgroundY, 0,
        960 / clearedBackground:getWidth(), 540 / clearedBackground:getHeight())

    for _, wheel in ipairs(WHEELS) do drawOuterWheel(source, backgroundY, wheel, frame.angle) end
    drawRod(source, backgroundY, frame)
    for _, wheel in ipairs(WHEELS) do drawHub(source, backgroundY, wheel, frame.angle) end
    love.graphics.setScissor()
    love.graphics.setStencilTest()
    return true
end

return WheelAnimation
