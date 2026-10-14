-- Owner decisions for a saved companion encounter. No scene changes on close.
local Viewport=require('game.viewport')
local Host={}
function Host.wrap(application,c)
    local original={}; for name,value in pairs(application) do original[name]=value end
    local selected,entered,errorMessage=1,nil,nil
    local buttons={{x=230,y=378,w=230,h=64},{x=500,y=378,w=230,h=64}}
    local function pending() return c.runtime.state=='game' and c.runtime.saveData and c.runtime.saveData.roamingEncounter end
    local function enter()
        local s=pending(); if not s then entered=nil; return end
        if entered~=s.id then
            entered=s.id; selected=1; errorMessage=nil
            if c.neutralize then c.neutralize() end
            for _,field in ipairs({'inventoryOpen','mapOpen','journeyLogOpen','editMode','tradeOpen','trainUpgradeOpen','poseMenu','outfitCraftingOpen'}) do c.runtime[field]=false end
            c.runtime.firstAid=nil
        end
        return s
    end
    local function choose(index)
        local s=enter(); if not s then return false end
        local reply=index==1 and c.commands.submit('battle.begin',{encounterId=s.leadId,enemyIds=s.enemyIds})
            or c.commands.submit('scene.returnTrain',{})
        if reply.ok and index==1 and c.battleEntered then c.battleEntered() end
        errorMessage=reply.ok and nil or reply.reason
        return true
    end
    local function click(x,y)
        if not enter() then return false end
        x,y=c.screenToGame(x,y)
        for index,r in ipairs(buttons) do if x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h then return choose(index) end end
        return true
    end
    function application.update(dt) enter(); return original.update(dt) end
    function application.draw(...)
        local result=original.draw(...); c.ui.roamingEncounterControls=nil
        if not enter() then return result end
        c.ui.roamingEncounterControls=buttons
        local g=love.graphics; g.push('all'); g.origin()
        local ox,oy,sx,sy=Viewport.transform(960,720); g.translate(ox,oy); g.scale(sx,sy)
        g.setColor(0,0,0,.68); g.rectangle('fill',0,0,960,720)
        g.setColor(.08,.06,.04,.98); g.rectangle('fill',170,218,620,268,12,12)
        c.ui.roamingEncounterFont=c.ui.roamingEncounterFont or g.newFont(20); g.setFont(c.ui.roamingEncounterFont)
        g.setColor(.97,.88,.68,1); g.printf('COMPANION ENCOUNTER',190,242,580,'center')
        g.setColor(1,1,1,1); g.printf('Your companion is caught by enemies. Choose whether the party fights or returns to the train.',210,290,540,'center')
        for index,r in ipairs(buttons) do
            g.setColor(index==selected and .36 or .20,.20,.10,1); g.rectangle('fill',r.x,r.y,r.w,r.h,8,8)
            g.setColor(.98,.88,.67,1); g.printf(index==1 and 'FIGHT' or 'RETURN TO TRAIN',r.x+8,r.y+21,r.w-16,'center')
        end
        if errorMessage then g.setColor(1,.55,.4,1); g.printf('This decision is unavailable: '..errorMessage,185,457,590,'center') end
        g.pop(); return result
    end
    function application.keypressed(key,...)
        if not enter() then return original.keypressed(key,...) end
        if key=='left' or key=='right' or key=='up' or key=='down' then selected=3-selected
        elseif key=='return' or key=='kpenter' or key=='space' then choose(selected) end
        return true
    end
    function application.mousepressed(x,y,button,...)
        if pending() then if button==1 then return click(x,y) end; return true end
        return original.mousepressed(x,y,button,...)
    end
    function application.touchpressed(id,x,y,...)
        if pending() then return click(x,y) end
        return original.touchpressed(id,x,y,...)
    end
    function application.gamepadpressed(joystick,button,...)
        if not enter() then return original.gamepadpressed(joystick,button,...) end
        if button=='dpleft' or button=='dpright' or button=='dpup' or button=='dpdown' then selected=3-selected
        elseif button=='a' then choose(selected) end
        return true
    end
    for _,event in ipairs({'textinput','keyreleased','mousemoved','mousereleased','touchmoved','touchreleased','wheelmoved','gamepadreleased'}) do
        local name=event
        application[name]=function(...) if pending() then return true end; if original[name] then return original[name](...) end end
    end
    return application
end
return Host
