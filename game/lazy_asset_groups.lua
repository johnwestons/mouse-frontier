-- Deferred scene assets keep their existing renderer-facing tables and aliases.
-- Retention releases old groups before a caller asks the next scene to load.
local Groups={};Groups.__index=Groups
local function visit(value,seen,action)
    if value==nil or seen[value] then return end
    seen[value]=true
    if type(value)=='userdata' or type(value)=='table' and value.getDimensions then
        action(value)
    elseif type(value)=='table' then
        for _,child in pairs(value)do visit(child,seen,action)end
    end
end
function Groups.new(destination)
    local previous=getmetatable(destination)
    local fallback=previous and previous.__index
    local self=setmetatable({destination=destination,entries={}},Groups)
    local mt={};for key,value in pairs(previous or {})do mt[key]=value end
    mt.__index=function(target,key)
        local entry=self.entries[key]
        if entry then
            local value=entry.load()
            if value~=nil then rawset(target,key,value)end
            return value
        end
        if type(fallback)=='function' then return fallback(target,key)end
        if type(fallback)=='table' then return fallback[key]end
    end
    setmetatable(destination,mt)
    return self
end
function Groups:add(key,group,load)
    self.entries[key]={group=group,load=load}
end
function Groups:retain(keep,external)
    local protected={}
    visit(external,{},function(image)protected[image]=true end)
    for key,entry in pairs(self.entries)do
        if keep[entry.group] then visit(rawget(self.destination,key),{},function(image)protected[image]=true end)end
    end
    local seen={}
    for key,entry in pairs(self.entries)do
        if not keep[entry.group] then
            visit(rawget(self.destination,key),seen,function(image)
                if not protected[image] and image.release then pcall(image.release,image)end
            end)
            rawset(self.destination,key,nil)
        end
    end
end
return Groups
