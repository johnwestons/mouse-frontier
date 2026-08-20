local Diagnostics={failures={},seen={}}

function Diagnostics.reset()
    Diagnostics.failures={}
    Diagnostics.seen={}
end

function Diagnostics.record(path,category,reason)
    local key=tostring(category or "asset").."|"..tostring(path)
    if Diagnostics.seen[key] then return end
    Diagnostics.seen[key]=true
    Diagnostics.failures[#Diagnostics.failures+1]={path=path,category=category or "asset",reason=reason}
end

function Diagnostics.count() return #Diagnostics.failures end

function Diagnostics.summary()
    local lines={}
    for _,entry in ipairs(Diagnostics.failures) do
        lines[#lines+1]=("[%s] %s%s"):format(entry.category,entry.path,entry.reason and (" — "..tostring(entry.reason)) or "")
    end
    table.sort(lines)
    return table.concat(lines,"\n")
end

function Diagnostics.assertHealthy()
    if #Diagnostics.failures>0 then
        error("Runtime art assets failed to load:\n"..Diagnostics.summary())
    end
    return true
end

return Diagnostics
