local Layout={}
Layout.order={"joystick","primary","secondary","back","menu","backpack"}
Layout.labels={joystick="MOVE",primary="USE",secondary="ACTION",back="BACK",menu="MENU",backpack="PACK"}
local defaults={joystick={x=.20,y=.76},primary={x=.78,y=.74},secondary={x=.64,y=.74},back={x=.12,y=.08},menu={x=.87,y=.08},backpack={x=.85,y=.89}}
local path="control-layout.txt"
Layout.MIN_OPACITY=.15
Layout.MAX_OPACITY=1
function Layout.normalizeOpacity(value)
    value=tonumber(value)
    if not value or value~=value or math.abs(value)==math.huge then return nil end
    return math.max(Layout.MIN_OPACITY,math.min(Layout.MAX_OPACITY,value))
end
function Layout.normalize(value)
    local result={}
    for _,key in ipairs(Layout.order) do
        local p=type(value)=="table" and value[key] or nil
        local function coordinate(axis,low,high)
            local v=type(p)=="table" and tonumber(p[axis]) or nil
            if not v or v~=v or math.abs(v)==math.huge then v=defaults[key][axis] end
            return math.max(low,math.min(high,v))
        end
        result[key]={x=coordinate("x",.10,.90),y=coordinate("y",.08,.90)}
    end
    result.opacity=Layout.normalizeOpacity(type(value)=="table" and value.opacity or nil)
    return result
end
function Layout.load(fs)
    if not fs.getInfo(path) then return nil end
    local source=fs.read(path)
    if type(source)~="string" then return nil end
    local result={}
    for line in source:gmatch("[^\r\n]+") do
        local key,x,y=line:match("^%s*([%a]+)%s+([%d%.%-]+)%s*([%d%.%-]*)")
        if key=="opacity" then result.opacity=tonumber(x)
        elseif defaults[key] then result[key]={x=tonumber(x),y=tonumber(y)} end
    end
    if not next(result) then return nil end
    return Layout.normalize(result)
end
function Layout.save(fs,value)
    local rows={}
    local normalized=Layout.normalize(value)
    for _,key in ipairs(Layout.order) do
        local p=normalized[key]
        rows[#rows+1]=string.format("%s %.6f %.6f",key,p.x,p.y)
    end
    if normalized.opacity then rows[#rows+1]=string.format("opacity %.6f",normalized.opacity) end
    return fs.write(path,table.concat(rows,"\n"))==true
end
function Layout.reset(fs) return not fs.getInfo(path) or fs.remove(path)==true end
return Layout
