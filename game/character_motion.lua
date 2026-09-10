local CharacterMotion = {}

local EPSILON = 0.0001

-- Optional per-character tuning. A complete reviewed directional asset set
-- activates automatically; characters not yet upgraded keep the existing
-- instant-response, side-facing movement path.
CharacterMotion.profiles = {
}

CharacterMotion.defaults = {
    pixelsPerFrame = 20,
    acceleration = 1050,
    deceleration = 1350,
    maxFrameTime = 0.10,
    maxStepDistance = 5,
    speedMultipliers = {0.96, 0.94, 1.04, 1.06, 0.96, 0.94, 1.04, 1.06},
    accelerationMultipliers = {0.92, 0.90, 1.08, 1.10, 0.92, 0.90, 1.08, 1.10},
}

CharacterMotion.directionalActions = {
    "walk", "walk_north", "walk_northeast", "walk_southeast", "walk_south",
    "idle", "idle_north", "idle_northeast", "idle_southeast", "idle_south",
}

-- Asymmetric characters may provide real west-facing art instead of moving
-- carried gear or costume details to the opposite side through mirroring.
CharacterMotion.authoredWestActions = {
    "walk_west", "walk_northwest", "walk_southwest",
    "idle_west", "idle_northwest", "idle_southwest",
}

local resolvedProfiles = {}
local unavailableProfiles = {}

local function directionalAssetsAvailable(file)
    if type(file)~="string" or not file:match("%.png$")
        or not love or not love.filesystem then return false end
    local directory="assets/sprites/character-animations/"..file:gsub("%.png$","")
    for _,action in ipairs(CharacterMotion.directionalActions) do
        if not love.filesystem.getInfo(directory.."/"..action..".png") then return false end
    end
    return true
end

local function copyProfile(overrides)
    local profile = {}
    for key, value in pairs(CharacterMotion.defaults) do profile[key] = value end
    for key, value in pairs(overrides or {}) do profile[key] = value end
    return profile
end

local function smoothstep(value)
    return value * value * (3 - 2 * value)
end

local function approach(value, target, amount)
    if value < target then return math.min(target, value + amount) end
    if value > target then return math.max(target, value - amount) end
    return target
end

local function sampleCurve(values, animationDistance, pixelsPerFrame)
    if type(values) ~= "table" or #values == 0 then return 1 end
    local phase = math.max(0, tonumber(animationDistance) or 0)
        / math.max(1, tonumber(pixelsPerFrame) or 20)
    local pose = math.floor(phase)
    local blend = smoothstep(phase - pose)
    local current = tonumber(values[pose % #values + 1]) or 1
    local following = tonumber(values[(pose + 1) % #values + 1]) or current
    return current + (following - current) * blend
end

function CharacterMotion.profileFor(file)
    if type(file)~="string" then return nil end
    if resolvedProfiles[file] then return resolvedProfiles[file] end
    if unavailableProfiles[file] then return nil end
    local overrides = CharacterMotion.profiles[file]
    if type(overrides) ~= "table" and not directionalAssetsAvailable(file) then
        unavailableProfiles[file]=true
        return nil
    end
    resolvedProfiles[file] = copyProfile(overrides)
    return resolvedProfiles[file]
end

function CharacterMotion.define(file, profile)
    assert(type(file) == "string" and file:match("%.png$"), "motion profile requires a character png")
    assert(type(profile) == "table", "motion profile requires a table")
    CharacterMotion.profiles[file] = profile
    resolvedProfiles[file] = nil
    unavailableProfiles[file] = nil
    return CharacterMotion.profileFor(file)
end

function CharacterMotion.hasDirectionalSet(set)
    if type(set) ~= "table" then return false end
    for _, action in ipairs(CharacterMotion.directionalActions) do
        if not set[action] then return false end
    end
    return true
end

function CharacterMotion.hasAuthoredWestSet(set)
    if type(set) ~= "table" then return false end
    for _, action in ipairs(CharacterMotion.authoredWestActions) do
        if not set[action] then return false end
    end
    return true
end

local function directionalAction(prefix, x, y, authoredWest)
    x, y = tonumber(x) or 0, tonumber(y) or 0
    local absX, absY = math.abs(x), math.abs(y)
    local diagonalThreshold = 0.41421356237 -- tan(22.5 degrees)
    if absX < EPSILON and absY < EPSILON then return prefix, 1 end
    if absX <= absY * diagonalThreshold then
        return y < 0 and prefix .. "_north" or prefix .. "_south", 1
    end
    if absY <= absX * diagonalThreshold then
        if x < 0 and authoredWest then return prefix .. "_west", 1 end
        return prefix, x < 0 and -1 or 1
    end
    if x < 0 and authoredWest then
        return y < 0 and prefix .. "_northwest" or prefix .. "_southwest", 1
    end
    return y < 0 and prefix .. "_northeast" or prefix .. "_southeast",
        x < 0 and -1 or 1
end

function CharacterMotion.directionalWalkAction(x, y, authoredWest)
    return directionalAction("walk", x, y, authoredWest)
end

function CharacterMotion.directionalIdleAction(x, y, authoredWest)
    return directionalAction("idle", x, y, authoredWest)
end

function CharacterMotion.frameForDistance(frameCount, distance, pixelsPerFrame)
    frameCount = math.max(1, tonumber(frameCount) or 1)
    if frameCount <= 1 then return 1 end
    local stride = math.max(1, tonumber(pixelsPerFrame) or 20)
    return math.floor(math.max(0, tonumber(distance) or 0) / stride) % frameCount + 1
end

function CharacterMotion.sample(animationDistance, profile)
    profile = profile or CharacterMotion.defaults
    return sampleCurve(profile.speedMultipliers, animationDistance, profile.pixelsPerFrame),
        sampleCurve(profile.accelerationMultipliers, animationDistance, profile.pixelsPerFrame)
end

function CharacterMotion.resetActor(actor)
    actor.velocityX, actor.velocityY = 0, 0
    actor.intentX, actor.intentY = actor.facing or 1, 0
    actor.animationDistance, actor.idleClock = 0, 0
    actor.gaitSpeedMultiplier, actor.gaitAccelerationMultiplier = 1, 1
    actor.blocked = false
end

function CharacterMotion.stopActor(actor)
    actor.velocityX, actor.velocityY = 0, 0
    actor.gaitSpeedMultiplier, actor.gaitAccelerationMultiplier = 1, 1
end

local function moveStep(actor, stepX, stepY, mover)
    local oldX, oldY = actor.x, actor.y
    local wantedX, wantedY = oldX + stepX, oldY + stepY
    local nextX, nextY = mover(oldX, oldY, wantedX, wantedY)
    actor.x, actor.y = nextX or oldX, nextY or oldY
    return actor.x - oldX, actor.y - oldY
end

function CharacterMotion.updateActor(actor, inputX, inputY, dt, options)
    options = options or {}
    local profile = options.profile or CharacterMotion.defaults
    dt = math.max(0, math.min(tonumber(dt) or 0, profile.maxFrameTime or 0.10))
    inputX, inputY = tonumber(inputX) or 0, tonumber(inputY) or 0
    local inputLength = math.sqrt(inputX * inputX + inputY * inputY)
    local strength = math.min(1, inputLength)
    local directionX, directionY = 0, 0
    if inputLength > EPSILON then
        directionX, directionY = inputX / inputLength, inputY / inputLength
        actor.intentX, actor.intentY = directionX, directionY
        if math.abs(directionX) > 0.08 then actor.facing = directionX < 0 and -1 or 1 end
    end

    local gaitSpeed, gaitAcceleration = CharacterMotion.sample(actor.animationDistance, profile)
    if inputLength <= EPSILON then gaitSpeed, gaitAcceleration = 1, 1 end
    actor.gaitSpeedMultiplier = gaitSpeed
    actor.gaitAccelerationMultiplier = gaitAcceleration

    local speed = math.max(0, tonumber(options.speed) or 0)
        * math.max(0, tonumber(options.speedScale) or 1) * gaitSpeed
    local targetX, targetY = directionX * speed * strength, directionY * speed * strength
    local sameDirection = inputLength > EPSILON
        and targetX * (actor.velocityX or 0) + targetY * (actor.velocityY or 0) >= 0
    local response = sameDirection and (profile.acceleration or 1050) * gaitAcceleration
        or (profile.deceleration or 1350)
    actor.velocityX = approach(actor.velocityX or 0, targetX, response * dt)
    actor.velocityY = approach(actor.velocityY or 0, targetY, response * dt)

    local travelX, travelY = actor.velocityX * dt, actor.velocityY * dt
    local travelDistance = math.sqrt(travelX * travelX + travelY * travelY)
    local limit = tonumber(options.maxDistance)
    if limit and limit >= 0 and travelDistance > limit and travelDistance > EPSILON then
        local ratio = limit / travelDistance
        travelX, travelY = travelX * ratio, travelY * ratio
        travelDistance = limit
    end

    local mover = options.move or function(_, _, x, y) return x, y end
    local maximumTravel = math.max(math.abs(travelX), math.abs(travelY))
    local stepLimit = math.max(1, tonumber(profile.maxStepDistance) or 5)
    local steps = math.max(1, math.ceil(maximumTravel / stepLimit))
    local stepX, stepY = travelX / steps, travelY / steps
    local movedX, movedY = 0, 0
    for _ = 1, steps do
        local actualX, actualY = moveStep(actor, stepX, stepY, mover)
        movedX, movedY = movedX + actualX, movedY + actualY
        if math.abs(actualX - stepX) > 0.05 and math.abs(stepX) > EPSILON then actor.velocityX = 0 end
        if math.abs(actualY - stepY) > 0.05 and math.abs(stepY) > EPSILON then actor.velocityY = 0 end
    end

    local distance = math.sqrt(movedX * movedX + movedY * movedY)
    actor.moving = distance > EPSILON
    actor.blocked = inputLength > EPSILON and distance + 0.05 < travelDistance
    if actor.moving then
        actor.animationDistance = (actor.animationDistance or 0) + distance
        actor.idleClock = 0
    else
        actor.idleClock = (actor.idleClock or 0) + dt
    end
    return distance
end

function CharacterMotion.moveToward(actor, targetX, targetY, dt, options)
    local dx, dy = targetX - actor.x, targetY - actor.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local stopDistance = math.max(0, tonumber(options and options.stopDistance) or 2)
    if distance <= stopDistance then
        CharacterMotion.updateActor(actor, 0, 0, dt, options)
        return true, 0
    end
    options = options or {}
    options.maxDistance = distance
    local moved = CharacterMotion.updateActor(actor, dx / distance, dy / distance, dt, options)
    return false, moved
end

return CharacterMotion
