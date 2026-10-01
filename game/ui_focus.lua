local UIFocus={}

local function usable(target)
    return target and target.rect and target.enabled~=false
        and type(target.rect.x)=="number" and type(target.rect.y)=="number"
        and type(target.rect.w)=="number" and type(target.rect.h)=="number"
end

local function selectedIndex(ui,targets,screenKey)
    if ui.keyboardFocusScreen~=screenKey then
        ui.keyboardFocusScreen=screenKey
        ui.keyboardFocusId=nil
    end
    for index,target in ipairs(targets) do
        if usable(target) and target.id==ui.keyboardFocusId then return index end
    end
    for index,target in ipairs(targets) do
        if usable(target) then
            ui.keyboardFocusId=target.id
            return index
        end
    end
end

local function center(target)
    local rect=target.rect
    return rect.x+rect.w/2,rect.y+rect.h/2
end

local function cycle(ui,targets,index,step)
    local count=#targets
    if count==0 then return nil end
    for offset=1,count do
        local candidate=((index-1+step*offset)%count)+1
        if usable(targets[candidate]) then return candidate end
    end
end

function UIFocus.move(ui,targets,screenKey,key,reverse)
    local index=selectedIndex(ui,targets,screenKey)
    if not index then return false end
    local nextIndex
    if key=="tab" then
        nextIndex=cycle(ui,targets,index,reverse and -1 or 1)
    else
        local dx=(key=="left" and -1) or (key=="right" and 1) or 0
        local dy=(key=="up" and -1) or (key=="down" and 1) or 0
        local x,y=center(targets[index]); local bestScore=math.huge
        for candidate,target in ipairs(targets) do
            if candidate~=index and usable(target) then
                local tx,ty=center(target); local offsetX,offsetY=tx-x,ty-y
                local primary=dx~=0 and offsetX*dx or offsetY*dy
                if primary>1 then
                    local secondary=dx~=0 and math.abs(offsetY) or math.abs(offsetX)
                    local score=primary+secondary*1.4
                    if score<bestScore then bestScore,nextIndex=score,candidate end
                end
            end
        end
        if not nextIndex then nextIndex=cycle(ui,targets,index,1) end
    end
    if not nextIndex then return true end
    ui.keyboardFocusId=targets[nextIndex].id
    ui.keyboardFocusVisible=true
    return true
end

function UIFocus.current(ui,targets,screenKey)
    local index=selectedIndex(ui,targets,screenKey)
    return index and targets[index] or nil
end

function UIFocus.draw(target)
    if not target or not usable(target) then return end
    local rect=target.rect
    love.graphics.push("all")
    love.graphics.setColor(0.025,0.018,0.01,.96)
    love.graphics.setLineWidth(6)
    love.graphics.rectangle("line",rect.x-3,rect.y-3,rect.w+6,rect.h+6,8,8)
    love.graphics.setColor(1,.86,.30,1)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line",rect.x-2,rect.y-2,rect.w+4,rect.h+4,7,7)
    love.graphics.setLineWidth(1)
    love.graphics.pop()
end

return UIFocus
