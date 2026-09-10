local TrainAnimation = {}

local TWO_PI = math.pi * 2
local PHASE_COUNT = 12
local PHASE_STEP = TWO_PI / PHASE_COUNT
local TRACK_FRAME_COUNT = 4
local EPSILON = 1e-10

TrainAnimation.phaseCount = PHASE_COUNT
TrainAnimation.trackFrameCount = TRACK_FRAME_COUNT

-- Public API:
-- wheelAngle(distance, radius, angleOffset?) -> continuous radians in [0, 2pi).
-- phaseIndex(distance, radius, angleOffset?) -> 1..12 reference atlas phase.
-- locomotiveGeometry(distance, spec) -> continuous driver, rod, and crosshead points.
-- carPhase(distance, radius, angleOffset?) -> continuous car-wheel phase record.
-- trackPlan(distance, options?) -> shared scroll plus two vibrating stone layers.
-- audit() -> deterministic mechanical and layering invariant measurements.
-- Positive distance turns screen-space drivers counterclockwise (y grows downward).
-- Locomotive spec fields: driverCenters[3], wheelRadius, crankRadius, guideY,
-- rodLength, and optional mainDriverIndex/crossheadSide/angleOffset.
-- Track options: origin, scale, tileWidth, scrollFactor (default 1.08),
-- vibrationStep/amplitude, and layerIds. Each layer returns the same
-- scrollOrigin/scale plus local vibrationX/Y, frame, and draw priority.

local function finiteNumber(value, name)
    assert(type(value) == "number", (name or "value") .. " must be a number")
    assert(value == value and value ~= math.huge and value ~= -math.huge,
        (name or "value") .. " must be finite")
    return value
end

local function positiveNumber(value, name)
    finiteNumber(value, name)
    assert(value > 0, (name or "value") .. " must be greater than zero")
    return value
end

local function normalizedAngle(angle)
    angle = angle % TWO_PI
    if angle < 0 then angle = angle + TWO_PI end
    return angle
end

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then
        return y >= 0 and math.atan(y / x) + math.pi or math.atan(y / x) - math.pi
    end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

local function pointDistance(a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    return math.sqrt(dx * dx + dy * dy)
end

local function circularError(a, b)
    local difference = math.abs(normalizedAngle(a) - normalizedAngle(b))
    return math.min(difference, TWO_PI - difference)
end

local function centerPoint(value, index)
    assert(type(value) == "table", "driver center " .. index .. " must be a table")
    local x = value.x
    local y = value.y
    if x == nil then x = value[1] end
    if y == nil then y = value[2] end
    return {x = finiteNumber(x, "driver center " .. index .. " x"),
        y = finiteNumber(y, "driver center " .. index .. " y")}
end

function TrainAnimation.wheelAngle(distance, radius, angleOffset)
    distance = finiteNumber(distance or 0, "distance")
    radius = positiveNumber(radius, "wheel radius")
    angleOffset = finiteNumber(angleOffset or 0, "angle offset")
    return normalizedAngle(distance / radius + angleOffset)
end

function TrainAnimation.phaseIndex(distance, radius, angleOffset)
    local angle = TrainAnimation.wheelAngle(distance, radius, angleOffset)
    -- This index is for atlas reference and tests; geometry never snaps to it.
    local index = math.floor(angle / PHASE_STEP + EPSILON) % PHASE_COUNT
    return index + 1
end

function TrainAnimation.locomotiveGeometry(distance, spec)
    assert(type(spec) == "table", "locomotive geometry requires a spec")
    assert(type(spec.driverCenters) == "table" and #spec.driverCenters == 3,
        "locomotive spec requires exactly three driver centers")

    local centers = {}
    for index = 1, 3 do centers[index] = centerPoint(spec.driverCenters[index], index) end

    local wheelRadius = positiveNumber(spec.wheelRadius, "wheel radius")
    local crankRadius = positiveNumber(spec.crankRadius or wheelRadius * .5, "crank radius")
    assert(crankRadius <= wheelRadius, "crank radius cannot exceed wheel radius")
    local mainDriverIndex = spec.mainDriverIndex or spec.mainDriver or 2
    assert(type(mainDriverIndex) == "number" and mainDriverIndex == math.floor(mainDriverIndex)
        and mainDriverIndex >= 1 and mainDriverIndex <= 3,
        "main driver index must be 1, 2, or 3")
    local guideY = finiteNumber(spec.guideY == nil and centers[mainDriverIndex].y or spec.guideY,
        "guide y")
    local rodLength = positiveNumber(spec.rodLength, "connecting rod length")
    local crossheadSide = spec.crossheadSide
    if crossheadSide == nil and spec.cylinderSide ~= nil then
        assert(spec.cylinderSide == "left" or spec.cylinderSide == "right",
            "cylinder side must be left or right")
        crossheadSide = spec.cylinderSide == "left" and -1 or 1
    end
    if crossheadSide == nil then crossheadSide = -1 end
    assert(crossheadSide == -1 or crossheadSide == 1, "crosshead side must be -1 or 1")
    local angleOffset = finiteNumber(spec.angleOffset or 0, "angle offset")
    local mainCenter = centers[mainDriverIndex]
    assert(rodLength + EPSILON >= math.abs(mainCenter.y - guideY) + crankRadius,
        "connecting rod is too short to complete a full revolution at guide y")

    local angle = TrainAnimation.wheelAngle(distance, wheelRadius, angleOffset)
    local crankOffsetX = crankRadius * math.cos(angle)
    local crankOffsetY = -crankRadius * math.sin(angle)
    local counterweightAngle = normalizedAngle(angle + math.pi)
    local drivers = {}
    for index = 1, 3 do
        local center = centers[index]
        drivers[index] = {
            index = index,
            center = center,
            angle = angle,
            crankPin = {x = center.x + crankOffsetX, y = center.y + crankOffsetY},
            counterweight = {
                x = center.x + crankRadius * math.cos(counterweightAngle),
                y = center.y - crankRadius * math.sin(counterweightAngle),
                angle = counterweightAngle,
            },
        }
    end

    local couplingPoints, couplingSegments = {}, {}
    for index = 1, 3 do couplingPoints[index] = drivers[index].crankPin end
    for index = 1, 2 do
        local from, to = couplingPoints[index], couplingPoints[index + 1]
        couplingSegments[index] = {
            from = from,
            to = to,
            length = pointDistance(from, to),
            angle = atan2(to.y - from.y, to.x - from.x),
        }
    end

    local mainPin = drivers[mainDriverIndex].crankPin
    local vertical = mainPin.y - guideY
    local horizontalSquared = rodLength * rodLength - vertical * vertical
    if horizontalSquared < 0 and horizontalSquared > -EPSILON then horizontalSquared = 0 end
    assert(horizontalSquared >= 0, "connecting rod cannot reach the crosshead guide")
    local crosshead = {
        x = mainPin.x + crossheadSide * math.sqrt(horizontalSquared),
        y = guideY,
    }
    local connectingRod = {
        from = crosshead,
        to = mainPin,
        length = pointDistance(crosshead, mainPin),
        angle = atan2(mainPin.y - crosshead.y, mainPin.x - crosshead.x),
    }

    return {
        angle = angle,
        referencePhaseIndex = TrainAnimation.phaseIndex(distance, wheelRadius, angleOffset),
        wheelRadius = wheelRadius,
        crankRadius = crankRadius,
        drivers = drivers,
        couplingRod = {
            points = couplingPoints,
            segments = couplingSegments,
            angle = atan2(couplingPoints[3].y - couplingPoints[1].y,
                couplingPoints[3].x - couplingPoints[1].x),
            offset = {x = crankOffsetX, y = crankOffsetY},
        },
        mainDriverIndex = mainDriverIndex,
        guideY = guideY,
        crosshead = crosshead,
        connectingRod = connectingRod,
    }
end

function TrainAnimation.carPhase(distance, wheelRadius, angleOffset)
    local angle = TrainAnimation.wheelAngle(distance, wheelRadius, angleOffset)
    return {
        angle = angle,
        normalized = angle / TWO_PI,
        referencePhaseIndex = TrainAnimation.phaseIndex(distance, wheelRadius, angleOffset),
        wheelRadius = wheelRadius,
    }
end

local VIBRATION = {
    {{x = 0, y = -1}, {x = 0, y = 1}},
    {{x = 1, y = 0}, {x = -1, y = 0}},
    {{x = 0, y = 1}, {x = 0, y = -1}},
    {{x = -1, y = 0}, {x = 1, y = 0}},
}

function TrainAnimation.trackPlan(distance, options)
    options = options or {}
    assert(type(options) == "table", "track plan options must be a table")
    distance = finiteNumber(distance or 0, "distance")
    local scale = positiveNumber(options.scale or 1, "track scale")
    local origin = finiteNumber(options.origin or 0, "track origin")
    local scrollFactor = finiteNumber(options.scrollFactor or 1.08, "track scroll factor")
    assert(scrollFactor >= 0, "track scroll factor cannot be negative")
    local vibrationStep = positiveNumber(options.vibrationStep or 6, "vibration step")
    local vibrationAmplitude = finiteNumber(options.vibrationAmplitude or 1, "vibration amplitude")
    assert(vibrationAmplitude >= 0, "vibration amplitude cannot be negative")
    local layerIds = options.layerIds or {"stones-a", "stones-b"}
    assert(type(layerIds) == "table" and layerIds[1] ~= nil and layerIds[2] ~= nil,
        "track plan requires two layer ids")

    local travel = distance * scrollFactor
    local rawScrollOrigin = origin + travel
    local wrapSpan
    if options.tileWidth ~= nil then
        wrapSpan = positiveNumber(options.tileWidth, "track tile width") * scale
    end
    local scrollOrigin = wrapSpan and rawScrollOrigin % wrapSpan or rawScrollOrigin
    local vibrationFrame = math.floor(travel / vibrationStep) % TRACK_FRAME_COUNT + 1
    local frame = VIBRATION[vibrationFrame]
    local firstIsFront = vibrationFrame % 2 == 1
    local layers = {}
    for index = 1, 2 do
        layers[index] = {
            id = layerIds[index],
            scrollOrigin = scrollOrigin,
            scale = scale,
            vibrationX = frame[index].x * vibrationAmplitude,
            vibrationY = frame[index].y * vibrationAmplitude,
            frame = vibrationFrame,
            priority = (firstIsFront == (index == 1)) and 2 or 1,
        }
    end
    local drawOrder = layers[1].priority < layers[2].priority
        and {layers[1].id, layers[2].id} or {layers[2].id, layers[1].id}

    return {
        travel = travel,
        rawScrollOrigin = rawScrollOrigin,
        scrollOrigin = scrollOrigin,
        wrapSpan = wrapSpan,
        scale = scale,
        vibrationFrame = vibrationFrame,
        layers = layers,
        drawOrder = drawOrder,
        frontLayer = drawOrder[2],
    }
end

function TrainAnimation.audit()
    local tolerance = 1e-9
    local wheelRadius, crankRadius = 42, 18
    local distance, angleOffset = 137.25, .13
    local geometry = TrainAnimation.locomotiveGeometry(distance, {
        driverCenters = {{x = 120, y = 200}, {x = 240, y = 200}, {x = 360, y = 200}},
        wheelRadius = wheelRadius,
        crankRadius = crankRadius,
        mainDriverIndex = 2,
        guideY = 196,
        rodLength = 150,
        crossheadSide = -1,
        angleOffset = angleOffset,
    })

    local driverPhaseError, pinRadiusError, oppositeError = 0, 0, 0
    local firstDriver = geometry.drivers[1]
    for _, driver in ipairs(geometry.drivers) do
        driverPhaseError = math.max(driverPhaseError,
            circularError(driver.angle, firstDriver.angle))
        pinRadiusError = math.max(pinRadiusError,
            math.abs(pointDistance(driver.center, driver.crankPin) - crankRadius))
        local midpointX = (driver.crankPin.x + driver.counterweight.x) / 2
        local midpointY = (driver.crankPin.y + driver.counterweight.y) / 2
        oppositeError = math.max(oppositeError,
            pointDistance(driver.center, {x = midpointX, y = midpointY}))
    end

    local couplingLengthError, couplingParallelError = 0, 0
    for index, segment in ipairs(geometry.couplingRod.segments) do
        local expected = pointDistance(geometry.drivers[index].center,
            geometry.drivers[index + 1].center)
        couplingLengthError = math.max(couplingLengthError,
            math.abs(segment.length - expected))
        couplingParallelError = math.max(couplingParallelError,
            math.abs(segment.to.y - segment.from.y))
    end
    local guideError = math.abs(geometry.crosshead.y - geometry.guideY)
    local connectingRodLengthError = math.abs(geometry.connectingRod.length - 150)
    local wheelClosureError = circularError(
        TrainAnimation.wheelAngle(0, wheelRadius, angleOffset),
        TrainAnimation.wheelAngle(TWO_PI * wheelRadius, wheelRadius, angleOffset))

    local phaseIndices, phaseSequenceReady = {}, true
    for zeroBased = 0, PHASE_COUNT - 1 do
        local sampleDistance = (zeroBased + .25) * PHASE_STEP * wheelRadius
        local index = TrainAnimation.phaseIndex(sampleDistance, wheelRadius)
        phaseIndices[#phaseIndices + 1] = index
        phaseSequenceReady = phaseSequenceReady and index == zeroBased + 1
    end

    local car = TrainAnimation.carPhase(distance, 27, .21)
    local carAngleError = circularError(car.angle,
        TrainAnimation.wheelAngle(distance, 27, .21))

    local trackPlans, trackFrames, trackFronts = {}, {}, {}
    local trackOriginError, trackScaleError = 0, 0
    local trackPriorityAlternates = true
    for zeroBased = 0, TRACK_FRAME_COUNT do
        local plan = TrainAnimation.trackPlan(zeroBased * 5, {
            origin = 7,
            scale = 1.25,
            scrollFactor = 1,
            vibrationStep = 5,
            tileWidth = 100,
        })
        trackPlans[#trackPlans + 1] = plan
        trackFrames[#trackFrames + 1] = plan.vibrationFrame
        trackFronts[#trackFronts + 1] = plan.frontLayer
        trackOriginError = math.max(trackOriginError,
            math.abs(plan.layers[1].scrollOrigin - plan.layers[2].scrollOrigin))
        trackScaleError = math.max(trackScaleError,
            math.abs(plan.layers[1].scale - plan.layers[2].scale))
        if zeroBased > 0 then
            trackPriorityAlternates = trackPriorityAlternates
                and trackFronts[#trackFronts] ~= trackFronts[#trackFronts - 1]
        end
    end
    local trackFrameCycleReady = trackFrames[1] == 1 and trackFrames[2] == 2
        and trackFrames[3] == 3 and trackFrames[4] == 4 and trackFrames[5] == 1
    local trackLayerCount = #trackPlans[1].layers

    local maxError = math.max(driverPhaseError, pinRadiusError, oppositeError,
        couplingLengthError, couplingParallelError, guideError,
        connectingRodLengthError, wheelClosureError, carAngleError,
        trackOriginError, trackScaleError)
    local ready = #geometry.drivers == 3 and phaseSequenceReady
        and trackLayerCount == 2 and trackFrameCycleReady and trackPriorityAlternates
        and maxError <= tolerance

    return {
        ready = ready,
        phaseCount = PHASE_COUNT,
        phaseIndices = phaseIndices,
        driverCount = #geometry.drivers,
        driverPhaseError = driverPhaseError,
        pinRadiusError = pinRadiusError,
        counterweightOppositeError = oppositeError,
        couplingLengthError = couplingLengthError,
        couplingParallelError = couplingParallelError,
        guideError = guideError,
        connectingRodLengthError = connectingRodLengthError,
        wheelClosureError = wheelClosureError,
        carAngleError = carAngleError,
        trackLayerCount = trackLayerCount,
        trackFrames = trackFrames,
        trackFronts = trackFronts,
        trackOriginError = trackOriginError,
        trackScaleError = trackScaleError,
        trackPriorityAlternates = trackPriorityAlternates,
        maxError = maxError,
        curve = "train-animation-v1",
    }
end

return TrainAnimation
