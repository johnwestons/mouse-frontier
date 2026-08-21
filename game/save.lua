local Save = {}
local pending = {}
local debounceSeconds = .20

local function serialize(value, indent)
    indent = indent or ""
    if type(value)=="number" or type(value)=="boolean" then return tostring(value) end
    if type(value)=="string" then return string.format("%q",value) end
    if type(value)~="table" then return "nil" end
    local out,nextIndent={"{\n"},indent.."  "
    for key,valueAtKey in pairs(value) do
        local encodedKey=type(key)=="number" and "["..key.."]" or "["..string.format("%q",key).."]"
        out[#out+1]=nextIndent..encodedKey.." = "..serialize(valueAtKey,nextIndent)..",\n"
    end
    out[#out+1]=indent.."}"
    return table.concat(out)
end

function Save.path(slot) return "saves/slot"..slot..".lua" end

local function loadValidated(path)
    if not love.filesystem.getInfo(path) then return nil,"missing" end
    local chunk,errorMessage=love.filesystem.load(path)
    if not chunk then return nil,errorMessage end
    local ok,data=pcall(chunk)
    if not ok then return nil,data end
    if type(data)~="table" then return nil,"save did not return a table" end
    return data
end

function Save.read(slot)
    local path=Save.path(slot)
    local data,errorMessage=loadValidated(path)
    if data then return data end
    -- A crash can interrupt the final copy. Prefer the already validated
    -- temporary file, then the previous known-good backup.
    for _,recoveryPath in ipairs({path..".tmp",path..".bak"}) do
        local recovered=loadValidated(recoveryPath)
        if recovered then
            print("[SAVE] Recovered "..path.." from "..recoveryPath)
            Save.write(slot,recovered)
            return recovered
        end
    end
    if errorMessage~="missing" then print("[SAVE] Invalid "..path..": "..tostring(errorMessage)) end
    return nil
end

function Save.write(slot,data)
    if not slot or type(data)~="table" then return false end
    love.filesystem.createDirectory("saves")
    local path,temporaryPath,backupPath=Save.path(slot),Save.path(slot)..".tmp",Save.path(slot)..".bak"
    local payload="return "..serialize(data)
    local ok,errorMessage=love.filesystem.write(temporaryPath,payload)
    if not ok then print("[SAVE] Write failed: "..tostring(errorMessage)); return false end
    local chunk,loadError=love.filesystem.load(temporaryPath)
    local valid,decoded=false,nil
    if chunk then valid,decoded=pcall(chunk) end
    if not valid or type(decoded)~="table" then
        love.filesystem.remove(temporaryPath)
        print("[SAVE] Validation failed: "..tostring(loadError or decoded))
        return false
    end
    local contents=love.filesystem.read(temporaryPath)
    local previous=love.filesystem.read(path)
    if previous then love.filesystem.write(backupPath,previous) end
    local replaced,replaceError=love.filesystem.write(path,contents)
    local finalData= replaced and loadValidated(path) or nil
    if not finalData then
        if previous then love.filesystem.write(path,previous) end
        print("[SAVE] Replace failed: "..tostring(replaceError or "final validation failed"))
        return false
    end
    love.filesystem.remove(temporaryPath)
    return true
end

function Save.schedule(slot,data)
    if not slot or type(data)~="table" then return false end
    pending[slot]={data=data,remaining=debounceSeconds}
    return true
end

function Save.update(dt)
    for slot,entry in pairs(pending) do
        entry.remaining=entry.remaining-(tonumber(dt) or 0)
        if entry.remaining<=0 then Save.write(slot,entry.data); pending[slot]=nil end
    end
end

function Save.flush(slot)
    if slot then
        local entry=pending[slot]; if not entry then return true end
        local ok=Save.write(slot,entry.data); if ok then pending[slot]=nil end; return ok
    end
    local ok=true
    for pendingSlot,entry in pairs(pending) do if Save.write(pendingSlot,entry.data) then pending[pendingSlot]=nil else ok=false end end
    return ok
end

function Save.remove(slot)
    pending[slot]=nil
    local removed=love.filesystem.remove(Save.path(slot))
    love.filesystem.remove(Save.path(slot)..".tmp"); love.filesystem.remove(Save.path(slot)..".bak")
    return removed
end

return Save
