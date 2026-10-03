local RepairPartArt={}

local palette={
    ink={.085,.060,.038,1}, shadow={.20,.14,.085,1}, steel={.47,.44,.36,1},
    light={.78,.72,.57,1}, brass={.86,.58,.18,1}, wood={.43,.26,.13,1},
    green={.32,.70,.38,1}, red={.72,.26,.18,1}, cream={.96,.88,.68,1},
}

function RepairPartArt.draw(catalog,name,rect)
    local part=catalog and catalog.repairParts and catalog.repairParts[name]
    if not part then return false end
    love.graphics.push("all")
    local unit=math.max(1,math.floor(math.min(rect.w,rect.h)/32))
    local originX=math.floor(rect.x+(rect.w-unit*32)/2)
    local originY=math.floor(rect.y+(rect.h-unit*32)/2)
    local function block(x,y,w,h,color)
        love.graphics.setColor(palette[color] or palette.steel)
        love.graphics.rectangle("fill",originX+x*unit,originY+y*unit,w*unit,h*unit)
    end
    local function outline(x,y,w,h)
        block(x,y,w,h,"ink")
    end
    local kind=part.icon
    if kind=="barrel" then
        outline(3,12,26,8); block(5,13,21,5,"steel"); block(7,13,15,2,"light"); block(2,11,4,10,"brass"); block(27,13,2,6,"shadow")
    elseif kind=="bolt" then
        outline(6,10,20,13); block(8,12,16,8,"steel"); block(10,10,8,3,"light"); block(20,13,7,3,"brass"); block(23,16,3,9,"shadow"); block(21,22,7,3,"brass")
    elseif kind=="lever" then
        outline(5,10,22,12); block(7,12,17,7,"steel"); block(8,10,8,3,"light"); block(18,14,8,3,"brass"); outline(18,18,5,11); block(20,20,2,7,"wood"); block(17,26,7,4,"brass")
    elseif kind=="slide" then
        outline(4,12,25,9); block(6,13,21,6,"steel"); block(8,13,14,2,"light"); block(24,17,4,3,"brass"); block(7,21,18,3,"shadow")
    elseif kind=="cylinder" then
        outline(9,7,15,19); block(11,9,11,16,"brass"); block(13,10,7,13,"steel"); block(12,12,3,3,"ink"); block(18,12,3,3,"ink"); block(12,19,3,3,"ink"); block(18,19,3,3,"ink"); block(15,15,3,3,"ink")
    elseif kind=="bow" then
        outline(8,3,5,4); block(10,6,3,7,"wood"); block(13,13,4,6,"brass"); block(17,19,3,7,"wood"); block(19,25,5,4,"wood"); block(13,7,2,19,"cream"); block(15,25,8,2,"cream")
    elseif kind=="crossbow" then
        outline(13,7,7,19); block(15,9,3,15,"wood"); outline(2,9,28,6); block(4,11,24,2,"steel"); block(7,14,18,3,"brass"); block(14,5,5,4,"light"); block(14,24,6,5,"shadow")
    elseif kind=="bands" then
        outline(5,7,6,6); block(7,9,3,3,"wood"); outline(21,7,6,6); block(23,9,3,3,"wood"); block(9,11,3,10,"red"); block(20,11,3,10,"red"); outline(11,19,11,8); block(13,21,7,4,"wood"); block(15,22,3,2,"cream")
    elseif kind=="core" then
        outline(7,7,18,18); block(9,9,14,14,"wood"); block(12,10,8,4,"brass"); block(11,15,10,3,"steel"); block(13,20,7,2,"light"); block(14,13,4,10,"shadow")
    elseif kind=="blade" then
        block(5,24,7,4,"wood"); block(9,21,5,4,"brass"); block(12,18,5,4,"steel"); block(15,15,5,4,"light"); block(18,12,5,4,"steel"); block(21,9,5,4,"light"); block(24,6,4,4,"cream"); block(6,23,3,5,"ink")
    elseif kind=="axe" then
        outline(13,6,6,22); block(15,9,2,16,"wood"); outline(7,7,18,10); block(8,8,6,7,"steel"); block(14,8,9,4,"light"); block(14,12,7,3,"brass"); block(11,26,10,4,"brass")
    elseif kind=="hammer" then
        outline(13,13,6,17); block(15,15,2,12,"wood"); outline(5,7,22,10); block(7,9,18,6,"steel"); block(9,9,12,2,"light"); block(12,27,9,3,"brass")
    elseif kind=="spear" then
        block(14,14,4,16,"wood"); block(13,8,6,8,"steel"); block(15,4,2,6,"light"); block(10,12,4,4,"brass"); block(20,12,4,4,"brass"); block(13,30,6,2,"ink")
    end
    love.graphics.pop()
    return true
end

return RepairPartArt
