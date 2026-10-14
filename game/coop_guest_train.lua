-- Guest train controls emit host commands and own no campaign rule writers.
local Access=require('game.coop_train_access')
local Balance=require('game.train_upgrade_balance')
local Engines=require('game.engine_upgrades')
local Style=require('game.ui_layout')
local Focus=require('game.ui_focus')
local Util=require('game.util')
local Panel={}; Panel.__index=Panel
local bounds={x=150,y=70,w=660,h=580}
local failures={stale_revision='Train supplies or upgrades changed. Review them and try again.',
    quote_changed='The upgrade changed. Review the new price and tier.',stale_item='The selected coal changed. Try again.',
    missing_coal='Carry coal in your backpack to fuel the train.',storage_full='Coal storage is full.',
    out_of_reach='Move closer to the firebox in car 1.',locked='That upgrade is not unlocked yet.',
    owned='The train already has that car.',scrap='There is not enough shared scrap.',maximum='The engine is fully upgraded.',
    rate_limited='Please wait a moment before trying again.',stale_scene='The host moved the party. Try again in the new scene.'}
function Panel.new(view,c) return setmetatable({view=view,c=c,runtime=view.runtime,ui=view.ui},Panel) end
function Panel:nearFire()
    return not self.pending and not self.runtime.inventoryOpen and not self.runtime.tradeOpen and not self.runtime.trainUpgradeOpen
        and self.view:actionsAllowed() and Access.nearFire(self.runtime.saveData,
            {screen=self.runtime.state,scene=self.runtime.scene,x=self.runtime.player.x,y=self.runtime.player.y},self.c.car)
end
function Panel:workshopAvailable()
    local r=self.runtime
    return r.state=='game' and r.scene=='train' and r.saveData and r.saveData.scene=='train'
        and self.view:actionsAllowed()
end
function Panel:open()
    if self.view.activityBusy and self.view:activityBusy() then return false end
    if self.runtime.peopleOpen or self.view.people and self.view.people.pending then return false end
    if self.runtime.editMode or self.ui.radioOpen or self.view.objects and self.view.objects.pending then return false end
    if not self:workshopAvailable() or self.pending or self.view.inventory.pending or self.view.trade.pending
        or self.runtime.inventoryOpen or self.runtime.tradeOpen then return false end
    self.runtime.trainUpgradeOpen=true; self.epoch=self.view.epoch; self.quote=nil; self.offers=nil
    self.notice=nil; self.ui.keyboardFocusId=nil; self.view:neutralize(); return true
end
function Panel:close()
    self.runtime.trainUpgradeOpen=false; self.quote=nil; self.offers=nil; self.ui.keyboardFocusId=nil
    return true
end
function Panel:submit(command,args,expected)
    if self.pending or self.view.inventory.pending or self.view.trade.pending or not self.view:actionsAllowed() then return false end
    if (command=='train.upgrade' or command=='train.engineUpgrade') and not self:workshopAvailable() then return false end
    local id,reason=self.view.controller.network:submitCommand(command,args,self.view.epoch,expected)
    if not id then self.notice=failures[reason] or 'The action is unavailable. Try again when ready.'; return false end
    self.pending={id=id,command=command}; self.quote=nil; self.notice='Waiting for the host...'; self.view:neutralize(); return true
end
function Panel:fuel()
    if not self:nearFire() then return false end
    local source,selected=Access.coal(self.runtime.saveData)
    if not source then self.notice=failures.missing_coal; return false end
    return self:submit('train.fuel',{source=source,sourceItem=selected},Access.expected(self.runtime.saveData,'train.fuel','companion'))
end
function Panel:offer(command,entry)
    local data=self.runtime.saveData; local args,title
    if command=='train.upgrade' then
        if not Balance.carStatus(data,entry).affordable then return nil end
        args={carId=entry.id,quotedPrice=entry.cost}; title=entry.name
    else
        local status=Balance.engineStatus(data,Engines)
        if not status.affordable then return nil end
        args={quotedPrice=status.entry.cost,quotedLevel=status.targetLevel}; title=status.entry.name
    end
    return {command=command,args=args,title=title,expected=Access.expected(data,command,'companion')}
end
function Panel:choose(id)
    if self.pending or self.quote or not self.runtime.trainUpgradeOpen or not self:workshopAvailable() then return false end
    local offer
    if self.offers then offer=self.offers[id]
    elseif id=='engine' then offer=self:offer('train.engineUpgrade')
    else for _,entry in ipairs(Balance.carCatalog) do if entry.id==id then offer=self:offer('train.upgrade',entry); break end end end
    if not offer then return false end
    self.quote=offer; self.ui.keyboardFocusId='train-confirm'; return true
end
function Panel:confirm()
    local q=self.quote; if not q then return false end
    return self:submit(q.command,q.args,q.expected)
end
function Panel:update()
    if self.runtime.trainUpgradeOpen and (self.epoch~=self.view.epoch or self.runtime.scene~='train'
        or self.runtime.saveData.scene~='train' or self.runtime.state~='game') then
        self:close(); self.notice='Workshop closed because the host moved the party.'
    end
    local pending=self.pending; local network=self.view.controller.network; local result=network and network.lastCommandResult
    if not pending or not result or result.requestId~=pending.id then return end
    if result.savePending or result.reason=='save_pending' or result.reason=='busy' then self.notice='Waiting for the host to finish saving...'; return end
    if result.ok and self.runtime.saveData.coop.revision<result.revision then self.notice='Updating the train...'; return end
    self.pending=nil; self.offers=nil
    if not result.ok then self.notice=failures[result.reason] or 'That action could not be completed. Review it and try again.'; return end
    local d=result.details
    if pending.command=='train.fuel' then self.notice='Coal +'..d.gained..'. Used '..Util.titleFromFile(d.item)..'.'
    elseif pending.command=='train.upgrade' then self.notice=Util.titleFromFile(d.carId)..' added for '..d.price..' scrap.'
    else self.notice=Engines.profile(d.level).name..' installed for '..d.price..' scrap.' end
end
function Panel:targets()
    local targets={}
    local function add(id,rect,action,enabled)
        if rect then targets[#targets+1]={id=id,rect=rect,action=action,enabled=enabled~=false and rect.enabled~=false} end
    end
    if self.quote then
        add('train-confirm',self.ui.trainConfirm,function() self:confirm() end,not self.pending)
        add('train-cancel',self.ui.trainCancel,function() self.quote=nil; self.ui.keyboardFocusId=nil end)
    else
        add('engine',self.ui.guestEngine,function() self:choose('engine') end,not self.pending)
        for _,entry in ipairs(Balance.carCatalog) do local id=entry.id; add('car:'..id,(self.ui.guestCars or {})[id],function() self:choose(id) end,not self.pending) end
        add('train-close',self.ui.guestTrainClose,function() self:close() end)
    end
    return targets
end
function Panel:press(x,y)
    for _,target in ipairs(self:targets()) do if target.enabled and Util.pointIn(x,y,target.rect) then self.ui.keyboardFocusId=target.id; target.action(); break end end
    return true
end
function Panel:keypressed(key)
    if key=='escape' or key=='acback' or key=='u' or key=='i' then
        if self.quote then self.quote=nil; self.ui.keyboardFocusId=nil else self:close() end
    elseif key=='tab' or key=='up' or key=='down' or key=='left' or key=='right' then Focus.move(self.ui,self:targets(),'guest-train',key,love.keyboard.isDown('lshift','rshift'))
    elseif key=='return' or key=='kpenter' or key=='space' then local t=Focus.current(self.ui,self:targets(),'guest-train'); if t and t.enabled then t.action() end end
    return true
end
function Panel:draw()
    local g=love.graphics; local data=self.runtime.saveData; local text=function(...) self.view.trade:textBox(...) end
    local button=function(...) return Style.transformRect(self.view.inventory:button(...)) end
    g.setColor(0,0,0,.78); g.rectangle('fill',0,0,960,720)
    Style.scope('trainUpgrades',bounds,function()
        self.view.inventory:frame(150,70,660,580,1,1); g.setColor(self.c.colors.brass)
        text('TRAIN WORKSHOP',170,85,620,42,1.25,'center'); g.setColor(self.c.colors.cream)
        text(self.notice or ('Shared scrap '..data.scrap..' / Coal '..data.resources.coal..' / '..Balance.resourceCapacity(data,'coal')),175,128,610,35,.85,'center')
        self.offers={}; self.ui.guestCars={}
        local status=Balance.engineStatus(data,Engines)
        self.offers.engine=self:offer('train.engineUpgrade')
        text('ENGINE: '..Engines.profile(data.engineLevel).name,185,166,395,32,.9)
        local label=status.maximum and 'MAX LEVEL' or status.locked and ('UNLOCK '..status.unlockStop) or (status.entry.cost..' SCRAP')
        self.ui.guestEngine=button(label,615,164,160,54,status.affordable and not self.pending,.85)
        for i,entry in ipairs(Balance.carCatalog) do
            local y=230+(i-1)*58; local carStatus=Balance.carStatus(data,entry)
            self.offers[entry.id]=self:offer('train.upgrade',entry)
            g.setColor(self.c.colors.cream); text(entry.name..': '..entry.description,185,y,405,54,.82)
            local cost=carStatus.owned and 'OWNED' or carStatus.locked and ('UNLOCK '..carStatus.unlockStop) or (entry.cost..' SCRAP')
            self.ui.guestCars[entry.id]=button(cost,615,y,160,54,carStatus.affordable and not self.pending,.85)
        end
        self.ui.guestTrainClose=button('CLOSE WORKSHOP',315,595,330,44,true,.9)
    end)
    if self.quote then Style.scope('train-confirm',{x=190,y=225,w=580,h=260},function()
        g.setColor(0,0,0,.7); g.rectangle('fill',0,0,960,720); self.view.inventory:frame(190,225,580,260,1,1)
        g.setColor(self.c.colors.cream); text('Install '..self.quote.title..' for '..self.quote.args.quotedPrice..' scrap?',220,245,520,125,1,'center')
        self.ui.trainConfirm=button('INSTALL',220,395,240,60,true,1); self.ui.trainCancel=button('CANCEL',500,395,240,60,true,1)
    end) end
    if self.ui.keyboardFocusVisible then Focus.draw(Focus.current(self.ui,self:targets(),'guest-train')) end
end
return Panel
