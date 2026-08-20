local Save = {}

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

function Save.read(slot)
    local path=Save.path(slot)
    local wanted="slot"..slot..".lua"; local found=false
    if love.filesystem.getInfo("saves") then for _,name in ipairs(love.filesystem.getDirectoryItems("saves")) do if name==wanted then found=true; break end end end
    if not found then return nil end
    local chunk,errorMessage=love.filesystem.load(path)
    if not chunk then print("[SAVE] Could not load "..path..": "..tostring(errorMessage)); return nil end
    local ok,data=pcall(chunk)
    if not ok then print("[SAVE] Invalid "..path..": "..tostring(data)); return nil end
    if type(data)~="table" then
        print("[SAVE] Invalid "..path..": save did not return a table")
        return nil
    end
    return data
end

function Save.write(slot,data)
    if not slot or type(data)~="table" then return false end
    love.filesystem.createDirectory("saves")
    local path,temporaryPath=Save.path(slot),Save.path(slot)..".tmp"
    local ok,errorMessage=love.filesystem.write(temporaryPath,"return "..serialize(data))
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
    local replaced,replaceError=love.filesystem.write(path,contents)
    love.filesystem.remove(temporaryPath)
    if not replaced then print("[SAVE] Replace failed: "..tostring(replaceError)) end
    return replaced
end

function Save.remove(slot) return love.filesystem.remove(Save.path(slot)) end

return Save
