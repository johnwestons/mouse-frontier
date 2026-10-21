-- Shared inventory controls for desktop/touch hosts and guests.
local T=require('game.typography')
local Contract=require('game.coop_item_contract')
local Share={}
function Share.draw(ctx)
    local ui,data=ctx.ui,ctx.data; ui.sharingControls={}; ui.sharingPanel=nil
    if ctx.battleMode or ctx.giftOpen or ctx.chestOpen or not ui.shareRecipient then return end
    local recipient=ui.shareRecipient()
    if not recipient then ui.sharingOpen=false; return end
    local function button(id,label,x,y,w,action,enabled)
        ctx.button(label,x,y,w,52,enabled~=false,.82)
        ui.sharingControls[#ui.sharingControls+1]={id=id,rect={x=x,y=y,w=w,h=52},action=action,enabled=enabled~=false}
    end
    if not ui.sharingOpen then
        ui.sharingPanel={x=52,y=480,w=450,h=52}
        button('open','SHARE WITH PLAYER',52,480,450,function() ui.sharingOpen=true end)
        return
    end
    ctx.drawMenuFrame(35,165,490,435,3,.98)
    ui.sharingPanel={x=35,y=165,w=490,h=435}
    love.graphics.setColor(ctx.colors.cream)
    T.drawText(love.graphics,'GIVE TO '..recipient:upper(),55,184,450,30,{align='center',scale=1,minScale=.8})
    local ref=ctx.draggedSlot; local name=ref and ref.kind~='chest' and ctx.value(ref)
    T.drawText(love.graphics,name and ctx.title(name) or 'Select an item in your backpack or equipped slots.',55,226,450,48,{align='center',scale=.85,minScale=.7})
    local function send(command,args)
        args.recipient=recipient
        local ok,reason=ui.sendPlayerGift(command,args)
        ui.sharingNotice=ok and 'Transfer submitted.' or reason or 'Transfer unavailable.'
    end
    button('item','GIVE SELECTED ITEM',55,280,450,function()
        send('inventory.give',{source=ref,sourceItem=Contract.selection(data,nil,ref)})
    end,name~=nil)
    local types={}; for ammo in pairs(ctx.Catalog.ammoPickupAmounts) do types[#types+1]=ammo end; table.sort(types)
    ui.shareAmmoIndex=math.max(1,math.min(ui.shareAmmoIndex or 1,#types))
    local ammo=types[ui.shareAmmoIndex]; local available=data.ammo[ammo] or 0
    ui.shareAmount=math.max(1,math.min(ui.shareAmount or 1,math.max(1,available)))
    button('previous','<',55,346,52,function() ui.shareAmmoIndex=(ui.shareAmmoIndex-2)%#types+1 end)
    button('next','>',453,346,52,function() ui.shareAmmoIndex=ui.shareAmmoIndex%#types+1 end)
    T.drawText(love.graphics,ctx.title(ammo)..'  ('..available..' available)',116,350,328,42,{align='center',scale=.85,minScale=.66})
    button('minus','-',55,410,64,function() ui.shareAmount=math.max(1,ui.shareAmount-1) end)
    button('plus','+',211,410,64,function() ui.shareAmount=math.min(available,ui.shareAmount+1) end,available>0)
    T.drawText(love.graphics,tostring(ui.shareAmount),125,415,80,42,{align='center',scale=.95,minScale=.8})
    button('all','ALL',287,410,82,function() ui.shareAmount=available end,available>0)
    button('ammo','GIVE AMMO',381,410,124,function() send('ammo.give',{ammo=ammo,amount=ui.shareAmount}) end,available>0)
    T.drawText(love.graphics,ui.sharingNotice or 'Stand near the other player to give them items or ammo.',55,476,450,48,{align='center',scale=.78,minScale=.65})
    button('close','BACK',55,532,450,function() ui.sharingOpen=false end)
end
function Share.click(ctx,x,y)
    for _,control in ipairs(ctx.ui.sharingControls or {}) do
        if ctx.pointIn(x,y,control.rect) then if control.enabled then control.action() end; return true end
    end
    return false
end
return Share
