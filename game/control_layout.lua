local Layout={}
Layout.order={"joystick","primary","secondary","back","menu","backpack"}
Layout.labels={joystick="MOVE",primary="USE",secondary="ACTION",back="BACK",menu="MENU",backpack="PACK"}
local defaults={joystick={x=.20,y=.76},primary={x=.78,y=.74},secondary={x=.64,y=.74},back={x=.12,y=.08},menu={x=.87,y=.08},backpack={x=.85,y=.89}}
local path="control-layout.txt"
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
    return result
end
function Layout.load(fs)
    if not fs.getInfo(path) then return nil end
    local source=fs.read(path)
    if type(source)~="string" then return nil end
    local result={}
    for key,x,y in source:gmatch("([%a]+)%s+([%d%.%-]+)%s+([%d%.%-]+)") do result[key]={x=tonumber(x),y=tonumber(y)} end
    if not next(result) then return nil end
    return Layout.normalize(result)
end
function Layout.save(fs,value)
    local rows={}
    for _,key in ipairs(Layout.order) do
        local p=Layout.normalize(value)[key]
        rows[#rows+1]=string.format("%s %.6f %.6f",key,p.x,p.y)
    end
    return fs.write(path,table.concat(rows,"\n"))==true
end
function Layout.reset(fs) return not fs.getInfo(path) or fs.remove(path)==true end
return Layout
