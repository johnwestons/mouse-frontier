-- Independent recipient UI. Gifts and approved chatter execute on the host.
local Access=require('game.coop_recipient_access')
local Contract=require('game.coop_item_contract')
local Inventory=require('game.inventory')
local Containers=require('game.coop_container_view')
local Entities=require('game.coop_entities')
local Style=require('game.ui_layout')
local Focus=require('game.ui_focus')
local Util=require('game.util')
local QuestPanel=require('game.coop_guest_quests')
local Panel={}; Panel.__index=Panel
local failures={recipient_unavailable='The recipient is no longer within reach.',missing_recipient='The recipient is no longer available.',
    stale_item='The selected item changed. Select it again.',stale_revision='The items or relationship changed. Review them and try again.',
    item_not_accepted='That item cannot be given here.',backpack_full='Free the extra backpack slots before giving away this backpack.',
    container_unavailable='That storage is no longer within reach.',unavailable='Wait until your character is ready.',
    rate_limited='Please wait a moment and try again.',stale_scene='The host moved the party. Try again in the new scene.'}
function Panel.new(view,c)
    local self=setmetatable({view=view,c=c,runtime=view.runtime,ui=view.ui,page=0,mode='gift'},Panel)
    self.quests=QuestPanel.new(self); return self
end
function Panel:state()
    local r=self.runtime; local npc=r.npcActor
    return {screen=r.state,scene=r.scene,x=r.player.x,y=r.player.y,npc=npc and {id=r.saveData.currentNPC,x=npc.x,y=npc.y} or nil}
end
function Panel:busy()
    if self.view.activityBusy and self.view:activityBusy() then return true end
    return self.pending or self.view.inventory.pending or self.view.trade.pending or self.view.train.pending or self.view.objects.pending
        or self.runtime.inventoryOpen or self.runtime.tradeOpen or self.runtime.trainUpgradeOpen or self.runtime.editMode or self.ui.radioOpen
end
function Panel:nearest()
    if self:busy() or self.runtime.peopleOpen or not self.view:actionsAllowed() then return nil end
    return Access.nearest(self.runtime.saveData,self:state())
end
function Panel:recipient()
    return self.targetId and Access.find(self.runtime.saveData,self.targetId,self.npc,self:state())
end
function Panel:open(recipient)
    if self:busy() or not self.view:actionsAllowed() then return false end
    recipient=recipient or self:nearest(); if not recipient then return false end
    recipient=Access.find(self.runtime.saveData,recipient.targetId,recipient.npc,self:state()); if not recipient then return false end
    self.targetId,self.npc=recipient.targetId,recipient.npc; self.epoch=self.view.epoch; self.car=self.runtime.saveData.activeCar
    self.runtime.peopleOpen=true; self.page=0; self.mode='gift'; self.quote=nil; self.speech=nil; self.drawn=nil; self.notice=nil
    self.ui.keyboardFocusId=nil; self.view:neutralize(); return true
end
function Panel:close()
    self.quests:close()
    self.runtime.peopleOpen=false; self.targetId=nil; self.npc=nil; self.quote=nil; self.speech=nil; self.drawn=nil
    self.ui.keyboardFocusId=nil; return true
end
function Panel:submit(name,args,expected)
    if self.pending or not self.view:actionsAllowed() or not self.runtime.peopleOpen then return false end
    local id,reason=self.view.controller.network:submitCommand(name,args,self.view.epoch,expected)
    if not id then self.notice=failures[reason] or 'Action unavailable. Try again when ready.'; return false end
    self.pending={id=id,command=name}; self.notice='Waiting for the host...'; self.quote=nil; self.speech=nil; self.view:neutralize(); return true
end
function Panel:talk()
    local recipient=self:recipient(); if not recipient then return false end
    local name=recipient.kind=='passenger' and 'passenger.chatter' or 'npc.chatter'
    local args={targetId=self.targetId,npc=self.npc}
    return self:submit(name,args,Access.expected(self.runtime.saveData,'companion',name,args))
end
function Panel:setMode(mode)
    if self.pending or self.quote then return false end
    if mode=='equip' and (not self:recipient() or self:recipient().kind~='passenger') then return false end
    self.mode=mode; self.page=0; self.drawn=nil; self.ui.keyboardFocusId=nil; return true
end
function Panel:offers()
    local recipient=self:recipient(); if not recipient then return {} end
    local list={}; local data=self.runtime.saveData; local name=self.mode=='equip' and 'passenger.equip' or 'npc.gift'
    local function add(ref,chest,label)
        local selection=Contract.selection(data,chest,ref); if not selection then return end
        if self.mode=='equip' and not Inventory.isWeapon(selection.name,self.c.catalog.weaponStats) then return end
        local args={targetId=self.targetId,npc=self.npc,source=ref,sourceItem=selection,containerId=chest and chest.entityId}
        list[#list+1]={command=name,args=args,label=label,item=selection.name,expected=Access.expected(data,'companion',name,args)}
    end
    for i=1,data.inventoryCapacity or 6 do add({kind='inventory',index=i},nil,'Backpack '..i) end
    for i=1,2 do add({kind='equipment',index=i},nil,'Weapon '..i) end
    local slots={}; for slot in pairs(data.wearables or {}) do slots[#slots+1]=slot end; table.sort(slots)
    for _,slot in ipairs(slots) do add({kind='wearable',slot=slot},nil,Util.titleFromFile(slot)) end
    local count=0
    for _,record in ipairs(Entities.records(data)) do
        local chest=Containers.find(data,record.value.entityId,self:state(),self.c.catalog)
        if chest then
            count=count+1
            for i=1,self.c.catalog.storageCapacities[chest.name] or 20 do add({kind='chest',index=i},chest,'Storage '..count..' / '..i) end
        end
    end
    return list
end
function Panel:choose(index)
    if self.pending or self.quote or self.speech or not self.runtime.peopleOpen or not self.view:actionsAllowed() then return false end
    local offer=(self.drawn or self:offers())[index]; if not offer then return false end
    self.quote=offer; self.ui.keyboardFocusId='confirm'; return true
end
function Panel:confirm()
    local quote=self.quote; if not quote then return false end
    return self:submit(quote.command,quote.args,quote.expected)
end
function Panel:update()
    if self.runtime.peopleOpen and (self.epoch~=self.view.epoch or self.car~=self.runtime.saveData.activeCar
        or not self.view.focused or self.view.controller.menuOpen or not self:recipient()) then self:close() end
    if self.pending and self.pending.quest then self.quests:update(); return end
    local result=self.view.controller.network.lastCommandResult; local pending=self.pending
    if not pending or not result or result.requestId~=pending.id then return end
    if result.savePending or result.reason=='save_pending' or result.reason=='busy' then self.notice='Waiting for the host to finish saving...'; return end
    if result.ok and self.runtime.saveData.coop.revision<result.revision then self.notice='Updating the journey...'; return end
    self.pending=nil; self.drawn=nil
    if not result.ok then self.notice=failures[result.reason] or 'That action could not be completed. Review it and try again.'; return end
    local details=result.details
    if pending.command=='npc.chatter' or pending.command=='passenger.chatter' then
        local line=self.c.catalog.dialogueLines[details.lineIndex]
        if self.runtime.peopleOpen and self.epoch==self.view.epoch then self.speech={text=line,npc=details.npc,tier=details.tier} end
        self.notice=nil
    else
        self.notice=(details.equipped and 'Equipped ' or 'Gift accepted: ')..Util.titleFromFile(details.item)..'.'
    end
end
function Panel:targets() return self.controls or {} end
function Panel:keypressed(key)
    if self.quests.opened then return self.quests:keypressed(key) end
    if key=='j' then self.quests:open(); return true end
    if key=='escape' or key=='acback' or key=='g' then
        if self.quote then self.quote=nil; self.ui.keyboardFocusId=nil elseif self.speech then self.speech=nil else self:close() end
    elseif key=='tab' or key=='up' or key=='down' or key=='left' or key=='right' then Focus.move(self.ui,self:targets(),'guest-people',key,love.keyboard.isDown('lshift','rshift'))
    elseif key=='return' or key=='kpenter' or key=='space' then local t=Focus.current(self.ui,self:targets(),'guest-people'); if t and t.enabled then t.action() end end
    return true
end
function Panel:press(x,y)
    if self.quests.opened then return self.quests:press(x,y) end
    for _,target in ipairs(self:targets()) do if target.enabled and Util.pointIn(x,y,target.rect) then self.ui.keyboardFocusId=target.id; target.action(); break end end
    return true
end
function Panel:draw()
    if self.quests.opened then return self.quests:draw() end
    local g=love.graphics; local text=function(...) self.view.trade:textBox(...) end
    self.controls={}
    local function button(id,label,x,y,w,h,action,enabled)
        local rect=Style.transformRect(self.view.inventory:button(label,x,y,w,h,enabled~=false,.82))
        self.ui['people_'..id]=rect; self.controls[#self.controls+1]={id=id,rect=rect,action=action,enabled=enabled~=false}; return rect
    end
    g.setColor(0,0,0,.78); g.rectangle('fill',0,0,960,720)
    Style.scope('guest-people',{x=80,y=50,w=800,h=620},function()
        self.view.inventory:frame(80,50,800,620,1,1); g.setColor(self.c.colors.brass)
        text(Util.titleFromFile(self.npc or 'Recipient'),110,70,740,44,1.15,'center'); g.setColor(self.c.colors.cream)
        text(self.notice or 'Talk, give an item, or equip a passenger weapon.',110,120,740,48,.87,'center')
        local recipient=self:recipient(); local enabled=not self.pending and not self.quote and not self.speech
        button('gift','GIVE ITEM',115,181,232,54,function() self:setMode('gift') end,enabled)
        if recipient and recipient.kind=='passenger' then
            button('equip','EQUIP WEAPON',364,181,232,54,function() self:setMode('equip') end,enabled)
        else button('quests','QUEST HELP',364,181,232,54,function() self.quests:open() end,enabled and self.quests:available()) end
        button('talk','TALK',613,181,232,54,function() self:talk() end,enabled)
        self.drawn=self:offers(); local pages=math.max(1,math.ceil(#self.drawn/9)); self.page=math.min(self.page,pages-1)
        for row=1,9 do
            local index=self.page*9+row; local offer=self.drawn[index]
            if offer then
                local x,y=115+((row-1)%3)*249,254+math.floor((row-1)/3)*87
                local rect=button('item'..row,'',x,y,232,76,function() self:choose(index) end,enabled)
                -- Visual contents share the transformed menu scope.
                self.ui.drawItem(offer.item,{x=x+8,y=y+10,w=51,h=51}); g.setColor(self.c.colors.cream)
                text(Util.titleFromFile(offer.item),x+66,y+5,158,40,.75)
                text(offer.label,x+66,y+45,158,25,.68)
            end
        end
        if #self.drawn==0 then text('No carried or nearby stored items.',115,300,730,80,1,'center') end
        button('prev','<',115,539,110,54,function() self.page=math.max(0,self.page-1) end,enabled and self.page>0)
        text('Page '..(self.page+1)..' / '..pages,250,548,230,38,.84,'center')
        button('next','>',505,539,110,54,function() self.page=math.min(pages-1,self.page+1) end,enabled and self.page<pages-1)
        button('close','CLOSE',639,539,206,54,function() self:close() end,true)
        text(self.mode=='equip' and "Choose a weapon to replace the passenger's current weapon." or 'Choose an item, then confirm the gift.',115,614,730,30,.77,'center')
    end)
    if self.quote or self.speech then
        self.controls={}; g.setColor(0,0,0,.76); g.rectangle('fill',0,0,960,720)
        Style.scope('guest-people-confirm',{x=155,y=210,w=650,h=345},function()
            self.view.inventory:frame(155,210,650,345,1,1); g.setColor(self.c.colors.cream)
            if self.quote then
                text((self.quote.command=='passenger.equip' and 'Equip ' or 'Give ')..Util.titleFromFile(self.quote.item)..' to '..Util.titleFromFile(self.npc)..'?',185,235,590,145,1,'center')
                if Inventory.isWeapon(self.quote.item,self.c.catalog.weaponStats) then text('This replaces their current weapon.',185,380,590,35,.8,'center') end
                button('confirm','CONFIRM',185,446,275,64,function() self:confirm() end,not self.pending)
                button('cancel','CANCEL',500,446,275,64,function() self.quote=nil; self.ui.keyboardFocusId=nil end,true)
            else
                text(Util.titleFromFile(self.speech.npc)..' / '..self.speech.tier,185,227,590,32,.8,'center')
                text(self.speech.text,185,270,590,155,1.1,'center')
                button('speechClose','CLOSE',330,455,300,60,function() self.speech=nil; self.ui.keyboardFocusId=nil end,true)
            end
        end)
    end
    if self.ui.keyboardFocusVisible then Focus.draw(Focus.current(self.ui,self:targets(),'guest-people')) end
end
return Panel
