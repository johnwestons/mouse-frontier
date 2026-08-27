local Interactions = {}

local function distance(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function targetOf(candidate)
    return candidate and (candidate.target or candidate) or nil
end

local function identityOf(candidate)
    local target = targetOf(candidate)
    if not target then
        return nil
    end
    return candidate.id or target.id or candidate.key or target.key
end

local function sameCandidate(a, b)
    if not a or not b then
        return false
    end
    local aTarget, bTarget = targetOf(a), targetOf(b)
    if aTarget == bTarget then
        return true
    end
    local aId, bId = identityOf(a), identityOf(b)
    if aId ~= nil and bId ~= nil then
        return aId == bId and a.kind == b.kind
    end
    return a.kind == b.kind
        and aTarget and bTarget
        and aTarget.x == bTarget.x
        and aTarget.y == bTarget.y
end

local function facingVector(player)
    if not player then
        return 0, 0
    end
    local x = player.intentX or player.moveX or player.vx or 0
    local y = player.intentY or player.moveY or player.vy or 0
    if x ~= 0 or y ~= 0 then
        local length = math.sqrt(x * x + y * y)
        return x / length, y / length
    end
    local facing = player.facing
    if type(facing) == "number" then
        return facing < 0 and -1 or 1, 0
    end
    local vectors = {
        left = { -1, 0 }, west = { -1, 0 },
        right = { 1, 0 }, east = { 1, 0 },
        up = { 0, -1 }, north = { 0, -1 },
        down = { 0, 1 }, south = { 0, 1 },
    }
    local vector = vectors[facing]
    return vector and vector[1] or 0, vector and vector[2] or 0
end

function Interactions.select(candidates, cursorX, cursorY, player, previous, options)
    options = options or {}
    previous = previous or Interactions.previousSelection
    local best, bestScore, bestIndex
    local pointerActive = options.pointerActive
    if pointerActive == nil then
        pointerActive = type(cursorX) == "number" and type(cursorY) == "number"
            and not (player and cursorX == player.x and cursorY == player.y)
    end
    local facingX, facingY = facingVector(player)

    for index, candidate in ipairs(candidates or {}) do
        local target = targetOf(candidate)
        if target and type(target.x) == "number" and type(target.y) == "number"
            and candidate.available ~= false and target.available ~= false
            and target.disabled ~= true and target.hidden ~= true then
            local acquireRadius = candidate.radius or target.interactionRadius or target.radius or 56
            local releaseRadius = candidate.releaseRadius or acquireRadius * (options.releaseScale or 1.18)
            local retained = sameCandidate(candidate, previous)
            local playerDistance = distance(player.x, player.y, target.x, target.y)
            local allowedRadius = retained and releaseRadius or acquireRadius

            if playerDistance <= allowedRadius then
                local cursorDistance = pointerActive and distance(cursorX, cursorY, target.x, target.y) or math.huge
                local hoverRadius = candidate.hoverRadius or target.hoverRadius or math.min(acquireRadius, 20)
                local hovered = pointerActive and cursorDistance <= hoverRadius
                local score = playerDistance

                if hovered then
                    score = cursorDistance * 0.70 + playerDistance * 0.30
                    score = score - 1000
                end

                if playerDistance > 0 and (facingX ~= 0 or facingY ~= 0) then
                    local dot = ((target.x - player.x) * facingX + (target.y - player.y) * facingY) / playerDistance
                    score = score - math.max(0, dot) * (options.facingWeight or 9)
                end
                score = score - (candidate.priority or target.interactionPriority or 0) * 100
                if retained then
                    score = score - (options.stickiness or 14)
                end

                candidate.playerDistance = playerDistance
                candidate.cursorDistance = cursorDistance
                candidate.hovered = hovered
                candidate.score = score
                candidate.radius = acquireRadius
                candidate.releaseRadius = releaseRadius

                if not bestScore or score < bestScore or (score == bestScore and index < bestIndex) then
                    best, bestScore, bestIndex = candidate, score, index
                end
            end
        end
    end

    Interactions.previousSelection = best
    return best
end

return Interactions
