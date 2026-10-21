io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local restart=os.getenv('MOUSE_FRONTIER_TRAVELER_HOST_RESTART')=='1'
local resumed=os.getenv('MOUSE_FRONTIER_TRAVELER_RESUMED')=='1'
local Save=require('game.save'); local Schema=require('game.save_schema'); local Items=require('game.item_instances')
local Viewport=require('game.viewport'); local Inventory=require('game.inventory'); local Style=require('game.ui_layout')
local app,c,stage,started,finished,capture,swordId
local oldSession
local nextReconnectLog=0
local function check(value,reason) assert(value,reason) end
local function file(name,value)
    local f=io.open(root..'/'..name,value~=nil and 'wb' or 'rb'); if not f then return end
    local result=value~=nil and f:write(tostring(value)) or f:read('*a'); f:close(); return result
end
local function key(value) app.keypressed(value); app.keyreleased(value) end
local function press(rect,inventory)
    check(rect,'missing control '..tostring(stage))
    if inventory then rect=Style.transformRectFor('inventory',{x=25,y=35,w=910,h=660},rect) end
    local ox,oy,sx,sy=Viewport.transform(960,720); local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('share',x,y); app.touchreleased('share',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function click(id,text)
    app.draw(); press(c.ui.localPlayControls[id]); if text then app.textinput(text); key('return') end
end
local function captureMenu(name)
    local width,height=love.graphics.getDimensions(); local canvas=love.graphics.newCanvas(width,height)
    love.graphics.push('all'); love.graphics.setCanvas(canvas); app.draw(); love.graphics.pop()
    file(role..'-'..name..'.png',canvas:newImageData():encode('png'):getString()); canvas:release()
end
local function ownUI() return role=='host' and c.ui or c.ui.localPlay.clientView.ui end
local function share(id)
    app.draw()
    for _,control in ipairs(ownUI().sharingControls or {}) do
        if control.id==id then check(control.enabled,'sharing control disabled '..id); press(control.rect,true); return end
    end
    local controls={}; for _,control in ipairs(ownUI().sharingControls or {}) do controls[#controls+1]=control.id end
    error('missing sharing control '..id..' open='..tostring(ownUI().sharingOpen)..' controls='..table.concat(controls,','))
end
local function chooseEquipment(index)
    app.draw(); press(touch and Inventory.mobileEquipmentSlotRect(index) or Inventory.equipmentSlotRect(index),true)
end
local function chooseInventory(index)
    app.draw(); press(touch and Inventory.mobileInventorySlotRect(index) or Inventory.inventorySlotRect(index),true)
end
local function finish()
    finished=true; file(role..'.done','true')
    print('LAN_SMOKE_OK role='..role..' directItemSharing=true reserveAmmoSharing=true conditionPreserved=true localSlotMenu=true portableProgress=true hostRestart='..tostring(restart)..' hostEnds='..tostring(not touch)..' touch='..tostring(touch))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'; lp.port=port
    if not resumed then Save.remove(1) end
    if role=='host' then
        if resumed then
            local saved=assert(Save.read(1),'host restart lost selected slot')
            local visitor=saved.players.companion
            check(visitor.stats.xp==18 and visitor.ammo['22lr']==0 and saved.ammo['22lr']==19,'host restart lost persisted exchange/progress')
            check(visitor.travelIdentity.tripId==file('traveler.trip'),'host restart lost visit identity')
            swordId=file('sword.id')
            c.runtime.state='slots'; app.update(0); key('f8'); click('saveSlot'); click('slot_1'); click('host')
            check(lp.network,'host could not relaunch saved journey after restart')
            file('host.resumed.session',lp.authority.sessionId)
            print('LAN_SMOKE_LISTENING'); stage='resumed'; return
        end
        c.runtime.selectedSlot=1
        local draft=c.newSave(c.characters[1]); draft.location=2; draft.scene='stop'; draft.stopped=true
        draft.homeStop={version=1,stage='departed',suppliesCollected=true,repairComplete=true,inOffice=false}
        check(c.enterGame(draft),'seed failed'); c.ensureStopLayout()
        local d=c.runtime.saveData; d.playerX,d.playerY=500,500; c.runtime.player.x,c.runtime.player.y=500,500
        Items.write(d,nil,{kind='equipment',index=1},'frontier-short-sword'); Items.setCondition(d,'frontier-short-sword',41,{kind='equipment',index=1})
        swordId=d.itemSlots.equipment[1].id; file('sword.id',swordId); d.ammo['22lr']=17
        check(Items.ensure(d) and Save.write(1,d),'host seed save failed')
        c.runtime.saveData=nil; c.runtime.selectedSlot=nil; c.runtime.state='slots'
        local place=lp.context.placeCompanion
        lp.context.placeCompanion=function(data)
            local ok,reason=place(data); if not ok then return ok,reason end
            local p=data.players.companion; p.playerX,p.playerY=530,500; return true
        end
        app.update(0); key('f8'); click('saveSlot'); captureMenu('local-slots'); click('slot_1'); captureMenu('launch-menu'); click('host')
        check(lp.network,'host launch from Local Play failed'); print('LAN_SMOKE_LISTENING'); stage='send'
    else
        local own=c.newSave(c.characters[2] or c.characters[1]); own.ammo['22lr']=2; own.stats.level=5; own.stats.xp=7
        own.location=9; own.scene='train'
        own.homeStop={version=1,stage='departed',suppliesCollected=true,repairComplete=true,inOffice=false}
        check(Save.write(1,own),'guest save seed failed')
        c.runtime.state='slots'; app.update(0); key('f8'); click('address','127.0.0.1:'..port)
        click('saveSlot'); click('slot_1'); click('join'); check(lp.network,'join failed'); stage='receive'
    end
end
local function hostUpdate()
    local lp=c.ui.localPlay; local d=c.runtime.saveData
    if lp:pending() then check(lp:approve(),'approval failed') end
    if lp.menuOpen then click('close') end
    if stage=='send' and file('guest.ready') then
        check(d.players.companion.stats.level==5 and d.players.companion.stats.xp==7,'selected character progression not imported')
        key('i'); share('open'); check(c.ui.sharingOpen,'host share panel did not open'); chooseEquipment(1); share('item')
        check(not d.equipment[1],'host give control did not move weapon'); stage='return'
    elseif stage=='return' and file('guest.sent') then
        local found
        for i,name in pairs(d.inventory) do
            local item=Items.get(d,nil,{kind='inventory',index=i})
            if item and item.id==swordId then check(name=='frontier-short-sword' and item.durability==41,'weapon changed'); found=true end
        end
        check(found and d.ammo['22lr']==19 and d.players.companion.ammo['22lr']==0,'sharing totals wrong')
        check(Schema.validate(d) and Items.validate(d),'sharing broke ownership')
        local saved=Save.read(1); check(saved and saved.ammo['22lr']==19,'sharing was not saved')
        d.players.companion.stats.xp=d.players.companion.stats.xp+11
        check(lp.authority:checkpointNow(),'progress checkpoint failed')
        if restart then
            file('traveler.trip',d.players.companion.travelIdentity.tripId)
            file('host.restart','true'); print('LAN_SMOKE_RESTART role=host travelerSaved=true')
            finished=true; love.event.quit(42); return
        end
        capture='sharing'; file('host.verified','true'); stage='finish'
    elseif stage=='resumed' and file('guest.resumed') then
        check(d.players.companion.stats.xp==18 and d.players.companion.ammo['22lr']==0,'reconnect replaced latest hosted profile')
        check(d.players.companion.travelIdentity.tripId==file('traveler.trip'),'reconnect started another visit')
        check(Schema.validate(d) and Items.validate(d),'reconnect broke ownership')
        file('host.verified','true'); stage='finish'
    elseif stage=='finish' then
        if not touch and not file('host.endStarted') then lp:open(); click('stop'); file('host.endStarted','true') end
        if file('guest.done') then finish() end
    end
end
local function guestUpdate()
    local lp=c.ui.localPlay; local v=lp.clientView
    if restart and (stage=='finish' or stage=='reconnecting') and file('host.restart') then
        if stage=='finish' then oldSession=lp.network and lp.network.sessionId; stage='reconnecting' end
        local expected=file('host.resumed.session')
        if expected and lp.phase=='connected' and lp.network.sessionId==expected and lp.menuOpen then click('close') end
        if love.timer.getTime()>=nextReconnectLog then
            nextReconnectLog=love.timer.getTime()+5
            print('LAN_TRAVELER_RECONNECT phase='..tostring(lp.phase)..' session='..tostring(lp.network and lp.network.sessionId)..' expected='..tostring(expected)..' ready='..tostring(v and v:actionsAllowed())..' error='..tostring(lp.error))
        end
        if expected and lp.phase=='connected' and lp.network.sessionId==expected and v and v:actionsAllowed() then
            check(expected~=oldSession,'host process session did not change')
            local own=v.runtime.saveData
            check(own.stats.xp==18 and own.ammo['22lr']==0,'resumed client lost latest personal progress')
            check(lp.replica.data.players.companion.travelIdentity.tripId==file('traveler.trip'),'client resumed wrong visit')
            file('guest.resumed','true'); stage='resumed'
        elseif expected and file('host-resumed.ready') and lp.phase=='idle' then
            lp:open(); click('join')
        end
        return
    end
    if stage=='returning' then
        if lp.phase=='idle' then
            local own=Save.read(1)
            check(own and own.stats.level==5 and own.stats.xp==18 and own.ammo['22lr']==0,'gains or ammo did not return to selected local save')
            check(own.location==9 and own.scene=='train' and not require('game.coop_traveler').isAway(own),'local world overwritten or character still away')
            check(not own.localTraveler.lastReturn.pending,'return acknowledgement unfinished')
            check(c.enterGame(own),'returned save could not resume solo'); finish()
        end
        return
    end
    if lp.menuOpen and lp.phase=='connected' then click('close') end
    if not v or not v:actionsAllowed() then return end
    local d=v.runtime.saveData
    if stage=='receive' then
        file('guest.ready','true'); local found
        for i in pairs(d.inventory) do local item=Items.get(d,nil,{kind='inventory',index=i}); if item and item.id==file('sword.id') then found=i; check(item.durability==41,'received weapon repaired itself') end end
        if found then
            key('i'); share('open')
            local types={}; for ammo in pairs(c.catalog.ammoPickupAmounts) do types[#types+1]=ammo end; table.sort(types)
            for _=1,#types do if types[v.ui.shareAmmoIndex]=='22lr' then break end; share('next') end
            share('all'); share('ammo'); stage='ammo'
        end
    elseif stage=='ammo' and not v.inventory.pending and d.ammo['22lr']==0 then
        local found
        for i in pairs(d.inventory) do local item=Items.get(d,nil,{kind='inventory',index=i}); if item and item.id==file('sword.id') then found=i end end
        check(found,'received sword disappeared'); chooseInventory(found); share('item'); stage='sent'
    elseif stage=='sent' and not v.inventory.pending then
        for i in pairs(d.inventory) do local item=Items.get(d,nil,{kind='inventory',index=i}); check(not item or item.id~=file('sword.id'),'returned sword duplicated') end
        capture='sharing'; file('guest.sent','true'); stage='finish'
    elseif (stage=='finish' or stage=='resumed') and file('host.verified') then
        if touch then lp:open(); click('leave') end
        stage='returning'
    end
end
local function guard(fn,...)
    local args={...}; local ok,reason=xpcall(function() return fn(unpack(args)) end,debug.traceback)
    if not ok then print('LAN_SMOKE_FAIL role='..role..' stage='..tostring(stage)..' reason='..tostring(reason)); finished=true; love.event.quit(1) end
end
function love.load() guard(load) end
function love.update(dt)
    if finished then return end
    guard(function()
        app.update(math.min(dt,.05))
        local reason=c.ui.localPlay.error
        local interrupted=restart and role=='guest' and file('host.restart') and (reason=='host_disconnected' or reason=='host_timeout' or reason=='application_closed')
        check(not reason or interrupted,'Local Play failed: '..tostring(reason))
        if role=='host' then hostUpdate() else guestUpdate() end
        check(love.timer.getTime()-started<(restart and 140 or 70),'timeout at '..tostring(stage))
    end)
end
function love.draw()
    if not app or finished then return end
    guard(function()
        app.draw()
        if capture then local name=role..'-'..capture..'.png'; capture=nil
            love.graphics.captureScreenshot(function(pixels)
                local f=assert(io.open(root..'/'..name,'wb')); f:write(pixels:encode('png'):getString()); f:close()
            end)
        end
    end)
end
