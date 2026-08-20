-- Centralized character roster policy.  Files remain assets, but this module
-- decides which pools may select them automatically.
local Roster = {}

Roster.retired = {
    ["dog-red-scarf.png"] = true,
    ["dog-yellow-scarf.png"] = true,
    ["raccoon-witch.png"] = true,
    ["clown-head.png"] = true,
    ["musician-frog.png"] = true,
    ["pipe-frog.png"] = true,
    ["skateboard-mouse.png"] = true,
}

Roster.mobOnly = {
    ["red-hood-mouse.png"] = true,
    ["raccoon-cape.png"] = true,
    ["shield-mouse.png"] = true,
    ["cowboy-mouse-no-skull.png"] = true,
    ["raccoon-heart.png"] = true,
    ["vampire-mouse.png"] = true,
}

Roster.assetOnly = {
    ["skateboard-mouse.png"] = true,
    ["cowboy-mouse-on-skull.png"] = true,
    ["clown-head.png"] = true,
}

function Roster.isMobOnly(file)
    return Roster.mobOnly[file] == true
end

function Roster.isAssetOnly(file)
    return Roster.assetOnly[file] == true
end

function Roster.isNpcCandidate(file)
    return type(file) == "string" and file:match("%.png$")
        and not Roster.retired[file]
        and not Roster.isMobOnly(file) and not Roster.isAssetOnly(file)
end

function Roster.isPlayable(file)
    return Roster.isNpcCandidate(file)
end

function Roster.cleanNpcRoster(files)
    local result, seen = {}, {}
    for _, file in ipairs(files or {}) do
        if Roster.isNpcCandidate(file) and not seen[file] then
            result[#result + 1], seen[file] = file, true
        end
    end
    table.sort(result)
    return result
end

function Roster.mergeNpcRoster(files, candidates, activeCharacter)
    local merged = Roster.cleanNpcRoster(files)
    local filtered, seen = {}, {}
    for _, file in ipairs(merged) do
        if file ~= activeCharacter then
            filtered[#filtered + 1], seen[file] = file, true
        end
    end
    merged = filtered
    for _, file in ipairs(candidates or {}) do
        if file ~= activeCharacter and Roster.isNpcCandidate(file) and not seen[file] then
            merged[#merged + 1], seen[file] = file, true
        end
    end
    table.sort(merged)
    return merged
end

return Roster
