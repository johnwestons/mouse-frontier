-- Detached companion trade panel. Only the host executes merchant rules.
local Access=require('game.coop_merchant_access')
local Trade=require('game.merchant_trade')
local Renderer=require('game.merchant_trade_panel')
local Contract=require('game.coop_item_contract')
local Inventory=require('game.inventory')
local Style=require('game.ui_layout')
local Focus=require('game.ui_focus')
local Typography=require('game.typography')
local Accessibility=require('game.accessibility')
local Util=require('game.util')
local Panel={}; Panel.__index=Panel
local failures={stale_revision='The trade changed. Review the items and try again.',stale_item='The selected item changed. Select it again.',
    quote_changed='The price or item changed. Review the new offer.',sold='That item has already been sold.',
    scrap='There is not enough shared scrap.',space='There is no space for that item.',budget='The merchant has insufficient scrap.',
    stale_scene='The host moved the party. Try again in the new scene.',merchant_unavailable='Move closer to the merchant.',
    missing_merchant='The merchant is no longer available.',rate_limited='Please wait a moment before trying again.'}
local function sortedKeys(map)
    local keys={}; for key in pairs(map or {}) do keys[#keys+1]=key end; table.sort(keys); return keys
end
function Panel.new(view,c) return setmetatable({view=view,c=c,runtime=view.runtime,ui=view.ui},Panel) end
function Panel:actorState()
    local runtime=self.runtime; local npc=runtime.npcActor
    return {screen=runtime.state,scene=runtime.scene,x=runtime.player.x,y=runtime.player.y,
        npc=npc and {id=runtime.saveData.currentNPC,x=npc.x,y=npc.y} or nil}
end
function Panel:source()
    if not self.targetId then return nil end
    return Access.find(self.runtime.saveData,self.targetId,self.merchantId,self:actorState(),self.c.catalog,true)
end
function Panel:nearest()
    if self.pending or self.runtime.tradeOpen or self.runtime.inventoryOpen or not self.view:actionsAllowed() then return nil end
    return Access.nearest(self.runtime.saveData,self:actorState(),self.c.catalog)
end
function Panel:open(source)
    if self.view.activityBusy and self.view:activityBusy() then return false end
    if self.runtime.peopleOpen or self.view.people and self.view.people.pending then return false end
    if self.runtime.editMode or self.ui.radioOpen or self.view.objects and self.view.objects.pending then return false end
    if self.pending or self.view.inventory.pending or not self.view:actionsAllowed() then return false end
    source=source or self:nearest(); if not source then return false end
    local current=Access.find(self.runtime.saveData,source.targetId,source.merchantId,self:actorState(),self.c.catalog,true)
    if not current then return false end
    self.targetId,self.merchantId=current.targetId,current.merchantId; self.epoch=self.view.epoch
    self.runtime.tradeOpen=true; self.runtime.tradeMessage=nil; self.runtime.tradeBuyPage=0; self.runtime.tradeSellPage=0
    self.offers=nil; self.sales=nil; self.quote=nil; self.ui.keyboardFocusId=nil; self.view:neutralize(); return true
end
function Panel:close()
    self.runtime.tradeOpen=false; self.targetId=nil; self.merchantId=nil; self.quote=nil; self.offers=nil; self.sales=nil
    self.ui.guestTradeConfirm=nil; self.ui.guestTradeCancel=nil; self.ui.keyboardFocusId=nil
    return true
end
function Panel:offer(source,index)
    local item,listing=Trade.stockItem(source,index); if not item then return nil end
    return {args={targetId=source.targetId,merchantId=source.merchantId,index=index,
        listingId=source.kind=='caravan' and listing.id or nil,quotedPrice=Trade.buyPrice(self.runtime.saveData,self.c.catalog,source,index),quotedItem=item},
        expected=Access.expected(self.runtime.saveData,'companion',source,'merchant.buy',index,self.c.catalog)}
end
function Panel:buy(index)
    if self.pending or self.quote or not self.view:actionsAllowed() then return false end
    local source=self:source(); if not source then return false end
    local offer
    if self.offers then offer=self.offers[index] else offer=self:offer(source,index) end
    if not offer then return false end
    self.quote=offer; self.ui.keyboardFocusId='confirm-buy'; return true
end
function Panel:submit(name,args,expected)
    if self.pending or self.view.inventory.pending or not self.view:actionsAllowed() then return false end
    local id,reason=self.view.controller.network:submitCommand(name,args,self.view.epoch,expected)
    if not id then self.runtime.tradeMessage=failures[reason] or 'Trading is unavailable. Try again when ready.'; return false end
    self.pending={id=id,command=name}; self.quote=nil; self.runtime.tradeMessage='Waiting for the host...'
    self.view:neutralize(); return true
end
function Panel:confirm()
    local quote=self.quote; if not quote then return false end
    return self:submit('merchant.buy',quote.args,quote.expected)
end
function Panel:sell(index)
    if self.pending or self.quote or not self.view:actionsAllowed() then return false end
    local source=self:source(); if not source then return false end
    local selection
    if self.sales then selection=self.sales[index] else selection={item=Contract.selection(self.runtime.saveData,nil,{kind='inventory',index=index}),
        expected=Access.expected(self.runtime.saveData,'companion',source,'merchant.sell')} end
    if not selection or not selection.item then return false end
    return self:submit('merchant.sell',{targetId=source.targetId,merchantId=source.merchantId,index=index,sourceItem=selection.item},selection.expected)
end
function Panel:update()
    if self.runtime.tradeOpen and (self.epoch~=self.view.epoch or not self:source()) then
        self:close(); self.notice='Trading closed because the merchant is no longer available here.'
    end
    local pending=self.pending; local network=self.view.controller.network; local result=network and network.lastCommandResult
    if not pending or not result or result.requestId~=pending.id then return end
    if result.savePending or result.reason=='save_pending' or result.reason=='busy' then self.runtime.tradeMessage='Waiting for the host to finish saving...'; return end
    if result.ok and self.runtime.saveData.coop.revision<result.revision then self.runtime.tradeMessage='Updating trade...'; return end
    self.pending=nil; self.offers=nil; self.sales=nil
    if not result.ok then self.runtime.tradeMessage=failures[result.reason] or 'That trade could not be completed. Review the offer and try again.'; return end
    local d=result.details or {}; local title=Util.titleFromFile(d.item)
    self.runtime.tradeMessage=pending.command=='merchant.sell' and ('Sold '..title..' for '..d.price..' scrap.')
        or ('Bought '..title..' for '..d.price..' scrap.'..(d.delivery=='train' and ' Delivered to a train mailbox.' or d.delivery=='ammo' and (' Ammo +'..d.amount..'.') or ''))
    self.notice=self.runtime.tradeMessage
end
function Panel:targets()
    local targets={}
    local function add(id,rect,action,enabled)
        if rect then targets[#targets+1]={id=id,rect=rect,action=action,enabled=enabled~=false and rect.enabled~=false} end
    end
    if self.quote then
        add('confirm-buy',self.ui.guestTradeConfirm,function() return self:confirm() end,not self.pending)
        add('cancel-buy',self.ui.guestTradeCancel,function() self.quote=nil; self.ui.keyboardFocusId=nil; return true end)
        return targets
    end
    for _,index in ipairs(sortedKeys(self.ui.tradeBuy)) do local i=index; add('buy:'..i,self.ui.tradeBuy[i],function() return self:buy(i) end,not self.pending) end
    for _,index in ipairs(sortedKeys(self.ui.tradeSell)) do local i=index; add('sell:'..i,self.ui.tradeSell[i],function() return self:sell(i) end,not self.pending) end
    for _,entry in ipairs({{'buy-prev','tradeBuyPrev','tradeBuyPage',-1},{'buy-next','tradeBuyNext','tradeBuyPage',1},
        {'sell-prev','tradePrev','tradeSellPage',-1},{'sell-next','tradeNext','tradeSellPage',1}}) do
        local field,step=entry[3],entry[4]
        add(entry[1],self.ui[entry[2]],function() self.runtime[field]=(self.runtime[field] or 0)+step end,not self.pending)
    end
    add('trade-close',self.ui.tradeClose,function() return self:close() end)
    return targets
end
function Panel:press(x,y)
    for _,target in ipairs(self:targets()) do if target.enabled and Util.pointIn(x,y,target.rect) then self.ui.keyboardFocusId=target.id; target.action(); return true end end
    return true
end
function Panel:keypressed(key)
    if key=='escape' or key=='acback' or key=='q' or key=='i' then
        if self.quote then self.quote=nil; self.ui.keyboardFocusId=nil else self:close() end
    elseif key=='tab' or key=='up' or key=='down' or key=='left' or key=='right' then
        Focus.move(self.ui,self:targets(),'guest-trade',key,love.keyboard.isDown('lshift','rshift'))
    elseif key=='return' or key=='kpenter' or key=='space' then
        local target=Focus.current(self.ui,self:targets(),'guest-trade'); if target and target.enabled then target.action() end
    end
    return true
end
function Panel:textBox(text,x,y,w,h,scale,align)
    Typography.drawText(love.graphics,text,x,y,w,h,{scale=(scale or 1)*Accessibility.textScale(self.runtime.saveData),
        minScale=self.view.mobile.enabled and .75 or .65,align=align or 'left',valign='center'})
end
function Panel:button(...)
    return Style.transformRect(self.view.inventory:button(...))
end
function Panel:draw()
    local source=self:source(); if not source then self:close(); return end
    self.offers={}; self.sales={}
    for _,index in ipairs(sortedKeys(source.stock)) do self.offers[index]=self:offer(source,index) end
    for index=1,self.runtime.saveData.inventoryCapacity do self.sales[index]={item=Contract.selection(self.runtime.saveData,nil,{kind='inventory',index=index}),
        expected=Access.expected(self.runtime.saveData,'companion',source,'merchant.sell')} end
    Renderer.draw({runtime=self.runtime,ui=self.ui,catalog=self.c.catalog,colors=self.c.colors,busy=self.pending~=nil,
        button=function(...) return self:button(...) end,drawMenuFrame=function(...) return self.view.inventory:frame(...) end,
        textBox=function(...) return self:textBox(...) end,isWeapon=function(name) return Inventory.isWeapon(name,self.c.catalog.weaponStats) end},source)
    if self.quote then
        Style.scope('trade-confirm',{x=190,y=225,w=580,h=260},function()
            love.graphics.setColor(0,0,0,.7); love.graphics.rectangle('fill',0,0,960,720)
            self.view.inventory:frame(190,225,580,260,1,1); love.graphics.setColor(self.c.colors.cream)
            self:textBox('Buy '..Util.titleFromFile(self.quote.args.quotedItem)..' for '..self.quote.args.quotedPrice..' scrap?',220,245,520,125,1,'center')
            self.ui.guestTradeConfirm=self:button('BUY',220,395,240,60,true,1)
            self.ui.guestTradeCancel=self:button('CANCEL',500,395,240,60,true,1)
        end)
    end
    if self.ui.keyboardFocusVisible then Focus.draw(Focus.current(self.ui,self:targets(),'guest-trade')) end
end
return Panel
