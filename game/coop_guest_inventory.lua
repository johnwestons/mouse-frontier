-- Guest UI owns selection/drag state only. Accepted mutations arrive through
-- the campaign replica; no inventory rules or save writer run in this module.
local Inventory=require('game.inventory')
local InventoryUI=require('game.inventory_ui')
local Presenter=require('game.inventory_presenter')
local Contract=require('game.coop_item_contract')
local Focus=require('game.ui_focus')
local Style=require('game.ui_layout')
local Typography=require('game.typography')
local Util=require('game.util')
local Accessibility=require('game.accessibility')
local Containers=require('game.coop_container_view')
local Panel={}; Panel.__index=Panel
local bounds={x=25,y=35,w=910,h=660}
local failures={stale_revision='The items changed. Select the item again.',stale_item='The selected item changed. Select it again.',
    stale_scene='The host moved the party. Try again in the new scene.',inventory_full='Your backpack is full.',
    backpack_full='Free the extra backpack slots before removing this backpack.',storage_full='The train already has enough of that supply.',
    out_of_reach='Move closer to that item.',missing_item='That item is no longer available.',
    container_unavailable='That storage is no longer within reach.',cannot_transfer='That item cannot move to that slot.',
    rate_limited='Please wait a moment before trying again.'}
local function same(a,b)
    return a and b and a.kind==b.kind and a.index==b.index and a.slot==b.slot
end
local function copy(ref) return ref and {kind=ref.kind,index=ref.index,slot=ref.slot} end
function Panel.new(view,c)
    local self=setmetatable({view=view,c=c,runtime=view.runtime,ui=view.ui,pointerX=0,pointerY=0},Panel)
    self.ui.shareRecipient=function() return self.runtime.saveData and require('game.coop_sharing').recipient(self.runtime.saveData,'companion') end
    self.ui.sendPlayerGift=function(command,args) return self:submit(command,args) end
    self.presenter=Presenter.new({runtime=self.runtime,ui=self.ui,inventoryUI=InventoryUI,inventory=Inventory,
        catalog=c.catalog,colors=c.colors,mobileEnabled=function() return view.mobile.enabled end,
        pointIn=Util.pointIn,title=Util.titleFromFile,isWeapon=function(name) return Inventory.isWeapon(name,c.catalog.weaponStats or {}) end,
        drawMenuFrame=function(...) return self:frame(...) end,button=function(...) return self:button(...) end,
        pointer=function() return self.pointerX,self.pointerY end,value=function(ref) return self:value(ref) end,
        move=function(a,b) return self:move(a,b) end,consume=function() return self:consume() end,
        drop=function(ref) return self:drop(ref) end,quickTransfer=function(ref) return self:quickTransfer(ref) end,
        collectAmmo=function(ref) return self:collectAmmo(ref) end,consumeBattle=function() return self:consume() end})
    return self
end
function Panel:value(ref) return Inventory.value(self.runtime.saveData,self.runtime.activeChest,ref) end
function Panel:actorState()
    return {screen=self.runtime.state,scene=self.runtime.scene,x=self.runtime.player.x,y=self.runtime.player.y}
end
function Panel:clearContainer()
    self.containerId=nil; self.runtime.activeChest=nil; self.runtime.chestOpen=false; self:cancelDrag()
end
function Panel:openContainer(id)
    if self.view.activityBusy and self.view:activityBusy() then return false end
    if self.runtime.peopleOpen or self.view.people and self.view.people.pending then return false end
    if self.runtime.editMode or self.ui.radioOpen or self.view.objects and self.view.objects.pending then return false end
    if self.pending or not self.view:actionsAllowed() then return false end
    local chest=Containers.find(self.runtime.saveData,id,self:actorState(),self.c.catalog)
    if not chest then return false end
    if chest.expeditionChest and not chest.opened then return false end
    self:clearContainer(); self.containerId=id; self.runtime.activeChest=chest
    self.runtime.inventoryOpen=true; self.runtime.chestOpen=true; self.runtime.inventoryMode=self.runtime.inventoryMode or 'wearables'
    self.notice=nil; self.ui.keyboardFocusId=nil; self.view:neutralize(); return true
end
function Panel:cancelDrag()
    self.runtime.draggedSlot=nil; self.runtime.inventoryDragActive=false; self.selection=nil; self.selectionRef=nil; self.touch=nil
end
function Panel:remember()
    local ref=self.runtime.draggedSlot
    if not ref then self.selection=nil; self.selectionRef=nil
    elseif not same(ref,self.selectionRef) then
        self.selectionRef=copy(ref); self.selection=Contract.selection(self.runtime.saveData,self.runtime.activeChest,ref)
    end
end
function Panel:toggle()
    if self.view.activityBusy and self.view:activityBusy() then return false end
    if self.runtime.peopleOpen or self.view.people and self.view.people.pending then return false end
    if self.runtime.editMode or self.ui.radioOpen or self.view.objects and self.view.objects.pending then return false end
    if not self.view.ready or self.view.controller.menuOpen then return false end
    self.runtime.inventoryOpen=not self.runtime.inventoryOpen; self:clearContainer()
    self.runtime.inventoryMode=self.runtime.inventoryMode or 'wearables'
    self.view:neutralize(); self.ui.keyboardFocusId=nil
    return true
end
function Panel:submit(name,args)
    if self.pending or not self.view:actionsAllowed() then return false end
    local data=self.runtime.saveData
    local expected=Contract.expected(data,'companion',name,args,self.c.catalog)
    local id,reason=self.view.controller.network:submitCommand(name,args,self.view.epoch,expected)
    if not id then self.notice=failures[reason] or 'The action is unavailable. Try again when ready.'; return false end
    self.pending={id=id,command=name}; self.notice='Waiting for the host...'
    self:cancelDrag(); self.view:neutralize(); return true
end
function Panel:canEdit()
    if self.runtime.battle then
        return self.view.battles:canAct(require('game.battle_rules').activeUnit(self.runtime.battle))
    end
    return self.view:actionsAllowed()
end
function Panel:sourceArgs(ref)
    if not ref or ref.kind=='chest' and not self.containerId then return nil end
    local selected=same(ref,self.selectionRef) and self.selection or Contract.selection(self.runtime.saveData,self.runtime.activeChest,ref)
    if not selected then return nil end
    return {source=copy(ref),sourceItem=selected,containerId=ref.kind=='chest' and self.containerId or nil}
end
function Panel:move(from,to)
    if same(from,to) or not to or to.kind=='chest' and not self.containerId then return false end
    local args=self:sourceArgs(from); if not args then return false end
    args.target=copy(to); args.targetItem=Contract.selection(self.runtime.saveData,self.runtime.activeChest,to)
    if to.kind=='chest' then args.containerId=self.containerId end
    if self.runtime.battle then return self.view.battles:submit('battle.swap',args) end
    return self:submit('inventory.swap',args)
end
function Panel:quickTransfer(ref)
    if not self.containerId then return false end
    local args=self:sourceArgs(ref); if not args then return false end
    args.containerId=self.containerId
    return self:submit('storage.transfer',args)
end
function Panel:collectAmmo(ref)
    if not ref or ref.kind~='chest' or not self.c.catalog.ammoPickupAmounts[self:value(ref)] then return false end
    local args=self:sourceArgs(ref); if not args then return false end
    return self:submit('mailbox.collect',args)
end
function Panel:transferSelected()
    local ref=self.runtime.draggedSlot
    if ref and ref.kind=='chest' and self.c.catalog.ammoPickupAmounts[self:value(ref)] then return self:collectAmmo(ref) end
    return self:quickTransfer(ref)
end
function Panel:takeContainer()
    local chest=self.runtime.activeChest
    if not chest or chest.permanent or next(chest.storage) then return false end
    return self:submit('loot.pickup',{entityId=self.containerId})
end
function Panel:consume()
    local ref=self.runtime.draggedSlot; local name=self:value(ref); if not name then return false end
    if self.runtime.battle then
        if ref.kind~='inventory' then return false end
        if Inventory.isWeapon(name,self.c.catalog.weaponStats) then
            return self:move(ref,{kind='equipment',index=1})
        end
        return self.view.battles:submit('battle.item',{name=name})
    end
    local wearable=self.c.catalog.wearableItems[name]
    if wearable then
        local target={kind='wearable',slot=wearable.slot}
        if ref.kind=='wearable' then
            local index=Inventory.firstEmptySlot(self.runtime.saveData)
            if not index then self.notice='Free a backpack slot before removing this gear.'; return false end
            target={kind='inventory',index=index}
        end
        return self:move(ref,target)
    end
    if not self.c.catalog.itemEffects[name] and name~='rose-heart-arrow' and name~='blade-hearts' then return false end
    return self:submit('inventory.consume',self:sourceArgs(ref))
end
function Panel:drop(ref)
    local args=self:sourceArgs(ref); if not args then return false end
    return self:submit('loot.drop',args)
end
function Panel:nearest()
    if self.pending or self.runtime.inventoryOpen or not self.view:actionsAllowed() or not self.view.scene.itemIsHere then return nil end
    local player=self.runtime.player
    local best,distance=Containers.nearest(self.runtime.saveData,self:actorState(),self.c.catalog)
    for _,item in ipairs(self.runtime.saveData.droppedItems or {}) do
        if not Containers.isContainer(item,self.c.catalog) and not item.permanent and not (item.storage and next(item.storage)) and self.view.scene.itemIsHere(item) then
            local d=(player.x-item.x)^2+(player.y-item.y)^2
            if d<75^2 and (not distance or d<distance) then best,distance=item,d end
        end
    end
    return best
end
function Panel:pickup()
    local item=self:nearest(); if not item then return false end
    if item.expeditionChest and self.view.expedition then return self.view.expedition:interact() end
    if Containers.isContainer(item,self.c.catalog) then return self:openContainer(item.entityId) end
    return self:submit('loot.pickup',{entityId=item.entityId})
end
function Panel:actionLabel()
    local item=self:nearest()
    return item and Containers.isContainer(item,self.c.catalog) and (item.stopHotspotId and 'HARVEST' or item.mailbox and 'OPEN MAILBOX' or 'OPEN STORAGE') or 'PICK UP'
end
function Panel:update()
    if self.epoch and self.epoch~=self.view.epoch then self.runtime.inventoryOpen=false; self:clearContainer(); self.notice=nil end
    self.epoch=self.view.epoch
    if self.containerId then
        local chest=Containers.find(self.runtime.saveData,self.containerId,self:actorState(),self.c.catalog)
        if chest then self.runtime.activeChest=chest
        else self:clearContainer(); self.notice='Storage closed because it is no longer available here.' end
    end
    if self.selectionRef and not Contract.matches(self.selection,self.runtime.saveData,self.runtime.activeChest,self.selectionRef) then
        self:cancelDrag(); self.notice='The selected item changed. Select it again.'
    end
    local pending=self.pending; local network=self.view.controller.network; local result=network and network.lastCommandResult
    if not pending or not result or result.requestId~=pending.id then return end
    if result.savePending or result.reason=='save_pending' or result.reason=='busy' then self.notice='Waiting for the host to finish saving...'; return end
    if result.ok and self.runtime.saveData.coop.revision<result.revision then self.notice='Updating items...'; return end
    self.pending=nil
    if not result.ok then self.notice=failures[result.reason] or 'That action could not be completed. Select the item again.'; self.ui.sharingNotice=self.notice; return end
    local detail=result.details or {}
    if pending.command=='inventory.give' or pending.command=='ammo.give' then
        self.notice='Gave '..detail.amount..' '..Util.titleFromFile(detail.item)..'.'; self.ui.sharingNotice=self.notice; self:cancelDrag()
    elseif pending.command=='inventory.swap' or pending.command=='storage.transfer' then self.notice='Items updated.'
    elseif pending.command=='mailbox.collect' then self.notice='Collected '..detail.amount..' '..Util.titleFromFile(detail.item)..'.'
    elseif pending.command=='loot.drop' then self.notice='Dropped '..Util.titleFromFile(detail.item)..'.'
    elseif pending.command=='loot.pickup' then self.notice='Collected '..Util.titleFromFile(detail.item)..'.'
    elseif detail.heart then self.notice='Maximum health increased.'
    elseif detail.potion then self.notice=Util.titleFromFile(detail.item)..' is ready for the next battle.'
    else
        local gains={}
        for _,key in ipairs({'health','food','water','oil'}) do
            local amount=detail.gained and detail.gained[key]
            if amount and amount>0 then gains[#gains+1]=Util.titleFromFile(key)..' +'..amount end
        end
        self.notice='Used '..Util.titleFromFile(detail.item)..'.'..(#gains>0 and (' '..table.concat(gains,', ')) or '')
    end
end
function Panel:frame(x,y,w,h,kind,alpha)
    if self.c.drawMenuFrame then self.c.drawMenuFrame(x,y,w,h,kind,alpha)
    else love.graphics.setColor(self.c.colors.panel); love.graphics.rectangle('fill',x,y,w,h,8,8) end
    if Accessibility.enabled(self.runtime.saveData,'highContrast') then
        love.graphics.setColor(1,.84,.28,1); love.graphics.rectangle('line',x,y,w,h,8,8)
    end
end
function Panel:button(label,x,y,w,h,enabled,scale)
    self:frame(x,y,w,h,4,enabled and 1 or .55)
    love.graphics.setColor(self.c.colors.cream)
    Typography.drawText(love.graphics,label,x+8,y+5,w-16,h-10,
        {scale=(scale or .9)*Accessibility.textScale(self.runtime.saveData),minScale=.60,align='center',valign='center'})
    return {x=x,y=y,w=w,h=h,enabled=enabled~=false}
end
function Panel:targets()
    local targets={}; local runtime=self.runtime; local mobile=self.view.mobile.enabled
    local function add(id,rect,action,enabled)
        if rect then targets[#targets+1]={id=id,rect=Style.transformRectFor('inventory',bounds,rect),action=action,enabled=enabled} end
    end
    local function slot(ref,rect)
        add(ref.kind..':'..tostring(ref.index or ref.slot),rect,function()
            if runtime.draggedSlot then
                if same(ref,runtime.draggedSlot) then self:cancelDrag() else self:move(runtime.draggedSlot,ref) end
            elseif self:value(ref) then runtime.draggedSlot=ref; self:remember() end
        end,not self.pending)
    end
    for index=1,runtime.saveData.inventoryCapacity do
        local rect=mobile and Inventory.mobileInventorySlotRect(index) or Inventory.inventorySlotRect(index)
        if mobile and runtime.saveData.inventoryCapacity>12 then rect.y=230+math.floor((index-1)/4)*56; rect.h=50 end
        slot({kind='inventory',index=index},rect)
    end
    for index=1,2 do slot({kind='equipment',index=index},mobile and Inventory.mobileEquipmentSlotRect(index) or Inventory.equipmentSlotRect(index)) end
    for _,mode in ipairs({'ammo','wearables'}) do local id=mode
        add('mode:'..id,self.ui.inventoryModeTabs and self.ui.inventoryModeTabs[id],function() runtime.inventoryMode=id; self:cancelDrag() end)
    end
    if runtime.inventoryMode=='wearables' then
        for index,value in ipairs(self.c.catalog.wearableSlots) do slot({kind='wearable',slot=value.id},Inventory.wearableSlotRect(index)) end
    end
    if runtime.chestOpen then
        local chest=runtime.activeChest
        for index=1,self.c.catalog.storageCapacities[chest.name] or 10 do slot({kind='chest',index=index},Inventory.chestSlotRect(index)) end
        add('transfer',self.transferButton,function() self:transferSelected() end,self.transferButton and self.transferButton.enabled)
        add('take-container',self.takeButton,function() self:takeContainer() end,self.takeButton and self.takeButton.enabled)
    end
    add('use',self.ui.consume,function() self:consume() end,not self.pending and self.ui.consume and self.ui.consume.enabled)
    for _,control in ipairs(self.ui.sharingControls or {}) do add('share:'..control.id,control.rect,control.action,control.enabled and not self.pending) end
    add('drop',self.ui.drop,function() self:drop(runtime.draggedSlot) end,not self.pending and runtime.draggedSlot~=nil)
    add('close',self.closeButton,function() self:toggle() end)
    return targets
end
function Panel:keypressed(key)
    if key=='i' or key=='escape' or key=='acback' or key=='e' then self:toggle(); return true end
    if key=='tab' or key=='up' or key=='down' or key=='left' or key=='right' then
        return Focus.move(self.ui,self:targets(),'guest-inventory',key,love.keyboard.isDown('lshift','rshift'))
    end
    if key=='return' or key=='space' then
        local target=Focus.current(self.ui,self:targets(),'guest-inventory')
        if target then target.action(); self:remember() end
    end
    if key=='t' then self:transferSelected() end
    return true
end
function Panel:press(x,y)
    self.pointerX,self.pointerY=x,y; self.ui.keyboardFocusVisible=false
    local lx,ly=Style.inversePoint(x,y,'inventory',bounds)
    if Util.pointIn(lx,ly,self.closeButton) then self:toggle(); return true end
    if not self.pending and self:canEdit() then
        if self.runtime.chestOpen and Util.pointIn(lx,ly,self.transferButton) and self.transferButton.enabled then return self:transferSelected() end
        if self.runtime.chestOpen and Util.pointIn(lx,ly,self.takeButton) and self.takeButton.enabled then return self:takeContainer() end
        self.presenter.handleClick(x,y); self:remember()
    end
    return true
end
function Panel:release(x,y)
    self.pointerX,self.pointerY=x,y
    if not self.pending and self:canEdit() then self.presenter.handleRelease(x,y,1); self:remember() end
    return true
end
function Panel:draw()
    local g=love.graphics
    g.setColor(.02,.015,.01,.85); g.rectangle('fill',0,0,960,720)
    self.presenter.drawInventory()
    local chest=self.runtime.chestOpen and self.runtime.activeChest
    if chest then self.presenter.drawChestInventory() end
    Style.scope('inventory',bounds,function()
        self:frame(35,35,490,chest and 105 or 125,3,.97)
        g.setColor(self.c.colors.cream)
        Typography.drawText(g,chest and (chest.storageLabel or (chest.mailbox and 'REWARD MAILBOX' or 'SHARED STORAGE')) or 'BACKPACK',55,chest and 43 or 55,450,35,
            {align='center',valign='center',scale=1.2,minScale=1})
        self.transferButton=nil; self.takeButton=nil
        if chest then
            Typography.drawText(g,self.notice or 'Drag items, or select an item and choose a transfer below.',55,81,450,43,
                {align='center',valign='center',scale=.85,minScale=.7})
            self.closeButton=self:button('CLOSE',35,646,180,50,true)
            local ref=self.runtime.draggedSlot; local name=self:value(ref)
            local take=ref and ref.kind=='chest'
            local label=take and (self.c.catalog.ammoPickupAmounts[name] and 'COLLECT AMMO' or 'TAKE ITEM') or (chest.mailbox and 'TAKE REWARD' or 'STORE ITEM')
            local enabled=name~=nil and not self.pending and (not chest.mailbox or take)
            self.transferButton=self:button(label..(self.view.mobile.enabled and '' or ' [T]'),230,646,285,50,enabled)
            if not chest.permanent and not next(chest.storage) then
                self.takeButton=self:button('PICK UP EMPTY CONTAINER',55,495,445,52,not self.pending)
            end
        else
            Typography.drawText(g,'Inspect, equip and use your items.',55,102,450,30,{align='center',valign='center',scale=.9,minScale=.7})
            if not self.ui.sharingOpen then
            self:frame(35,175,490,165,3,.97); g.setColor(self.c.colors.cream)
            Typography.drawText(g,self.notice or (self.runtime.battle and 'Use medicine or potions, or move weapons between your backpack and equipped slots.'
                or 'Drag an item to move it. Select an item to use or drop it.'),55,198,450,120,
                {align='center',valign='center',scale=.95,minScale=.72})
            end
            self.closeButton=self:button('CLOSE BACKPACK',35,610,240,64,true)
        end
        if not chest and not self.view.mobile.enabled then
            g.setColor(self.c.colors.cream)
            local binding=self.c.bindings; local closeKeys={}
            for _,id in ipairs({'inventory','cancel'}) do
                if binding and binding.display then
                    if not binding.keyboard or binding.keyboard[id] then closeKeys[#closeKeys+1]=binding:display('key',id) end
                else closeKeys[#closeKeys+1]=id=='inventory' and 'I' or 'ESC' end
            end
            local closeHint=#closeKeys>0 and table.concat(closeKeys,' / ')..': close' or 'Use CLOSE BACKPACK to close.'
            Typography.drawText(g,'Select a slot or action.\n'..closeHint,55,400,450,110,
                {align='center',valign='center',scale=.85,minScale=.7})
        end
    end)
    if self.ui.keyboardFocusVisible then Focus.draw(Focus.current(self.ui,self:targets(),'guest-inventory')) end
    if self.runtime.inventoryDragActive and self.runtime.draggedSlot then
        local name=self:value(self.runtime.draggedSlot)
        if name then self.ui.drawItem(name,{x=self.pointerX-32,y=self.pointerY-32,w=64,h=64}) end
    end
end
return Panel
