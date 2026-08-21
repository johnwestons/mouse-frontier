local PanelAnimation = {}

local CONDITION_SOURCE = {x = 35, y = 685, w = 480, h = 215}
local DONE_SOURCE = {x = 1125, y = 730, w = 225, h = 165}
local DONE_DURATION = .50
local CONDITION_DURATION = .80

local DONE_FRAMES = {
    {scale = 1.00, y = 0,  tint = {1.00, 1.00, 1.00}},
    {scale = 1.03, y = -1, tint = {1.00, .96, .82}},
    {scale = .92,  y = 4,  tint = {.78, .65, .48}},
    {scale = 1.05, y = -2, tint = {1.00, .90, .62}},
    {scale = 1.00, y = 0,  tint = {1.00, 1.00, 1.00}},
}

local CONDITION_FRAMES = {
    {scale = 1.000, y = 0,  tint = {1.00, 1.00, 1.00}},
    {scale = 1.012, y = -1, tint = {1.00, .94, .72}},
    {scale = .995,  y = 1,  tint = {.94, .84, .62}},
    {scale = 1.008, y = -1, tint = {1.00, .96, .80}},
    {scale = 1.000, y = 0,  tint = {1.00, 1.00, 1.00}},
}

local function frameAt(duration, remaining, count)
    if remaining <= 0 then return count end
    local elapsed = math.max(0, duration - remaining)
    return math.max(1, math.min(count, math.floor(elapsed / (duration / count)) + 1))
end

function PanelAnimation.sourceRects()
    return CONDITION_SOURCE, DONE_SOURCE
end

function PanelAnimation.doneDuration()
    return DONE_DURATION
end

function PanelAnimation.conditionDuration()
    return CONDITION_DURATION
end

function PanelAnimation.doneFrame(remaining)
    return frameAt(DONE_DURATION, remaining, #DONE_FRAMES)
end

function PanelAnimation.conditionFrame(remaining)
    return frameAt(CONDITION_DURATION, remaining, #CONDITION_FRAMES)
end

function PanelAnimation.frameCount()
    return #DONE_FRAMES, #CONDITION_FRAMES
end

function PanelAnimation.conditionValue(fromValue, toValue, remaining)
    if remaining <= 0 then return toValue end
    local frame = PanelAnimation.conditionFrame(remaining)
    local progress = frame / #CONDITION_FRAMES
    return fromValue + (toValue - fromValue) * progress
end

local function drawQuad(source, quad, sourceRect, gameX, gameY, frame)
    if not source or not quad then return false end
    local scaleX, scaleY = 960 / source:getWidth(), 540 / source:getHeight()
    local centerX = gameX + sourceRect.w * scaleX / 2
    local centerY = gameY + sourceRect.h * scaleY / 2 + frame.y
    love.graphics.setColor(frame.tint[1], frame.tint[2], frame.tint[3], 1)
    love.graphics.draw(source, quad, centerX, centerY, 0, scaleX * frame.scale, scaleY * frame.scale,
        sourceRect.w / 2, sourceRect.h / 2)
    love.graphics.setColor(1, 1, 1, 1)
    return true
end

function PanelAnimation.drawCondition(source, quad, remaining)
    local frame = CONDITION_FRAMES[PanelAnimation.conditionFrame(remaining)]
    return drawQuad(source, quad, CONDITION_SOURCE, 20, 483, frame)
end

function PanelAnimation.drawDone(source, quad, remaining, hover, ready)
    local frame
    if remaining > 0 then frame = DONE_FRAMES[PanelAnimation.doneFrame(remaining)]
    elseif hover and ready then
        local pulse = .5 + .5 * math.sin(love.timer.getTime() * 7)
        frame = {scale = 1.01 + pulse * .015, y = -pulse, tint = {1, .92 + pulse * .08, .72 + pulse * .22}}
    else frame = DONE_FRAMES[#DONE_FRAMES] end
    return drawQuad(source, quad, DONE_SOURCE, 646, 509, frame)
end

return PanelAnimation
