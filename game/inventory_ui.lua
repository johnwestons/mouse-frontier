local InventoryUI = {}

local function inventorySlotRect(ctx,index)
    if ctx.mobileEnabled then return ctx.Inventory.mobileInventorySlotRect(index) end
    return ctx.Inventory.inventorySlotRect(index)
end

local function equipmentSlotRect(ctx,index)
    if ctx.mobileEnabled then return ctx.Inventory.mobileEquipmentSlotRect(index) end
    return ctx.Inventory.equipmentSlotRect(index)
end

local ammoDisplay = {
    {"9mm","9MM"},{"45-cal",".45"},{"556","5.56"},{"22lr",".22LR"},{"30-carbine",".30"},
    {"8mm","8MM"},{"380-acp",".380"},{"32-acp",".32"},{"12-gauge","12GA"},{"762x39","7.62"},
    {"rocks","ROCK"},{"arrows","ARROW"},{"ball-bearings","BALL"}
}

function InventoryUI.slotAtPoint(ctx,x,y)
    local data=ctx.data
    for i=1,(data.inventoryCapacity or 6) do
        if ctx.pointIn(x,y,inventorySlotRect(ctx,i)) then return {kind="inventory",index=i} end
    end
    for i=1,2 do
        if ctx.pointIn(x,y,equipmentSlotRect(ctx,i)) then return {kind="equipment",index=i} end
    end
    if ctx.chestOpen then
        local capacity=ctx.activeChest and ctx.Catalog.storageCapacities[ctx.activeChest.name] or 10
        for i=1,capacity do
            if ctx.pointIn(x,y,ctx.Inventory.chestSlotRect(i)) then return {kind="chest",index=i} end
        end
    end
end

function InventoryUI.drawItem(ctx,name,r)
    local atlas=ctx.ui.atlasItems and ctx.ui.atlasItems[name]
    local img=ctx.ui.propImages[name]
    if atlas then
        local s=math.min(64/atlas.w,64/atlas.h)
        love.graphics.setColor(1,1,1)
        love.graphics.draw(atlas.image,atlas.quad,r.x+r.w/2,r.y+r.h/2,0,s,s,atlas.w/2,atlas.h/2)
    elseif img then
        local s=math.min(58/img:getWidth(),58/img:getHeight())
        love.graphics.setColor(1,1,1)
        love.graphics.draw(img,r.x+r.w/2,r.y+r.h/2,0,s,s,img:getWidth()/2,img:getHeight()/2)
    else
        love.graphics.setColor(ctx.colors.cream)
        love.graphics.printf(name or "",r.x+3,r.y+28,r.w-6,"center")
    end
end

function InventoryUI.draw(ctx)
    local data,ui,Inventory,Catalog=ctx.data,ctx.ui,ctx.Inventory,ctx.Catalog
    local capacity=data.inventoryCapacity or 6
    ctx.drawMenuFrame(545,35,390,145,3,.94)
    love.graphics.setColor(ctx.colors.cream); love.graphics.print("AMMUNITION STORAGE",565,44,0,.82,.82)
    for i,entry in ipairs(ammoDisplay) do
        local col=(i-1)%5; local row=math.floor((i-1)/5); local x,y=558+col*75,58+row*29
        local image=ui.propImages[entry[1]]
        if image then
            local scale=math.min(27/image:getWidth(),24/image:getHeight())
            love.graphics.setColor(1,1,1); love.graphics.draw(image,x+10,y+14,0,scale,scale,image:getWidth()/2,image:getHeight()/2)
        end
        love.graphics.setColor(ctx.colors.cream); love.graphics.print(entry[2].." "..(data.ammo[entry[1]] or 0),x+25,y+5,0,.46,.46)
    end
    ctx.drawMenuFrame(545,185,390,510,2,1)
    love.graphics.setColor(.12,.09,.07,1); love.graphics.rectangle("fill",570,202,340,27,6,6)
    love.graphics.setColor(ctx.colors.cream); love.graphics.print("BACKPACK  -  "..capacity.." SLOTS",575,206,0,1.0,1.0)
    for i=1,capacity do
        local r=inventorySlotRect(ctx,i); love.graphics.setColor(0.28,0.22,0.16); love.graphics.rectangle("fill",r.x,r.y,r.w,r.h,7,7)
        if data.inventory[i] then InventoryUI.drawItem(ctx,data.inventory[i],r) end
    end
    love.graphics.setColor(.12,.09,.07,1); love.graphics.rectangle("fill",570,462,340,26,6,6)
    love.graphics.setColor(ctx.colors.cream); love.graphics.print("EQUIPPED WEAPONS",580,466,0,.82,.82)
    ui.equipmentSlots={}
    for i=1,2 do
        local r=equipmentSlotRect(ctx,i); ui.equipmentSlots[i]=r
        love.graphics.setColor(0.32,0.20,0.12); love.graphics.rectangle("fill",r.x,r.y,r.w,r.h,7,7)
        love.graphics.setColor(ctx.colors.brass); love.graphics.rectangle("line",r.x,r.y,r.w,r.h,7,7)
        if data.equipment[i] then InventoryUI.drawItem(ctx,data.equipment[i],r) end
    end
    local selectedName=ctx.draggedSlot and ctx.value(ctx.draggedSlot)
    local mx,my=ctx.pointer(); local hovered=InventoryUI.slotAtPoint(ctx,mx,my)
    local inspectName=(hovered and ctx.value(hovered)) or selectedName
    if ctx.isWeapon(inspectName) then
        local stats,combat=Catalog.weaponStats[inspectName],Catalog.weaponCombat[inspectName] or {}; local durability=data.weaponDurability[inspectName] or 100
        ctx.drawMenuFrame(565,558,350,64,3,.92); love.graphics.setColor(ctx.colors.cream)
        love.graphics.print(stats.name.."  TIER "..stats.tier,582,568,0,.78,.78)
        love.graphics.print("DMG "..stats.min.."-"..stats.max.."  "..string.upper(combat.kind or "melee").."  RANGE "..(combat.range or 1).."  DUR "..durability.."%"..(durability<=0 and " BROKEN" or ""),582,590,0,.60,.60)
        if combat.ammo then love.graphics.print(ctx.title(combat.ammo).." "..(data.ammo[combat.ammo] or 0),582,607,0,.55,.55) end
    elseif inspectName and Catalog.itemEffects[inspectName] and Catalog.itemEffects[inspectName].potion then
        local effect=Catalog.itemEffects[inspectName]
        ctx.drawMenuFrame(565,558,350,64,3,.92); love.graphics.setColor(ctx.colors.cream)
        love.graphics.print(ctx.title(inspectName),582,568,0,.78,.78)
        love.graphics.printf(effect.description,582,589,316,"left",0,.55,.55)
        love.graphics.print("DOUBLE CLICK TO DRINK",582,608,0,.52,.52)
    elseif inspectName and Catalog.itemEffects[inspectName] and (Catalog.itemEffects[inspectName].food or Catalog.itemEffects[inspectName].water) then
        local effect=Catalog.itemEffects[inspectName]; local restored={}
        if effect.food then restored[#restored+1]="FOOD +"..effect.food end
        if effect.water then restored[#restored+1]="WATER +"..effect.water end
        ctx.drawMenuFrame(565,558,350,64,3,.92); love.graphics.setColor(ctx.colors.cream)
        love.graphics.print(ctx.title(inspectName),582,568,0,.78,.78)
        love.graphics.print("RESTORES  "..table.concat(restored,"   "),582,590,0,.62,.62)
        love.graphics.print("DOUBLE CLICK TO "..(effect.label or "USE"),582,608,0,.52,.52)
    end
    local special=selectedName=="rose-heart-arrow" or selectedName=="blade-hearts"
    local effect=selectedName and Catalog.itemEffects[selectedName]
    local pack=selectedName and Catalog.backpackUpgrades[selectedName]
    local gift=ctx.isWeapon(selectedName) and (ctx.nearNPC or ctx.nearPassenger)
    local battleUsable=ctx.battleMode and (ctx.isWeapon(selectedName) or (effect and (effect.health or effect.potion)))
    local actionLabel=ctx.battleMode and (ctx.isWeapon(selectedName) and "EQUIP TO WEAPON SLOT 1" or (effect and ((effect.label or "USE").." "..ctx.title(selectedName)) or "SELECT MEDICINE, POTION, OR WEAPON"))
        or (gift and "GIVE WEAPON TO ALLY" or (pack and ("EQUIP "..pack.label) or (special and ("USE "..ctx.title(selectedName)) or (effect and (effect.label.." "..ctx.title(selectedName)) or "SELECT AN ITEM TO USE"))))
    local mobile=ctx.mobileEnabled
    ui.consume=ctx.button(actionLabel,565,mobile and 620 or 628,230,mobile and 62 or 38,ctx.battleMode and battleUsable or (effect~=nil or special or pack~=nil or gift))
    if ctx.giftOpen then
        ctx.drawMenuFrame(220,170,520,180,3,.97); love.graphics.setColor(ctx.colors.cream)
        love.graphics.printf("GIVE TO "..ctx.title(ctx.giftNPC or "NPC"),240,190,480,"center",0,1.15,1.15)
        love.graphics.printf("Place one item in the offer slot",250,220,460,"center",0,.78,.78)
        local offer={x=445,y=245,w=70,h=70}; love.graphics.setColor(.28,.22,.16); love.graphics.rectangle("fill",offer.x,offer.y,offer.w,offer.h,7,7)
        if ctx.giftSlot then InventoryUI.drawItem(ctx,data.inventory[ctx.giftSlot],offer) end
        ui.giftSlot=offer; ui.giftConfirm=ctx.button("OFFER",535,mobile and 250 or 260,mobile and 130 or 100,mobile and 64 or 36,ctx.giftSlot~=nil); ui.giftCancel=ctx.button("CANCEL",mobile and 295 or 325,mobile and 250 or 260,mobile and 130 or 100,mobile and 64 or 36,true)
    else ui.giftSlot=nil; ui.giftConfirm=nil; ui.giftCancel=nil end
    if ctx.battleMode then
        ui.drop=nil
        love.graphics.setColor(ctx.colors.cream)
        love.graphics.printf("Items cannot be dropped during battle.",805,638,110,"center",0,.50,.50)
    else ui.drop=ctx.button("DROP",805,mobile and 620 or 628,110,mobile and 62 or 38,ctx.draggedSlot~=nil) end
end

function InventoryUI.drawChest(ctx)
    local activeChest,ui=ctx.activeChest,ctx.ui
    ctx.drawMenuFrame(25,145,505,445,2,1)
    local capacity=activeChest and ctx.Catalog.storageCapacities[activeChest.name] or 10
    local mailbox=activeChest and activeChest.mailbox
    love.graphics.setColor(ctx.colors.cream)
    love.graphics.print(mailbox and ("REWARD MAILBOX  -  "..capacity.." SLOTS") or (ctx.title(activeChest and activeChest.name or "Storage").."  -  "..capacity.." SLOTS"),65,215,0,1.2,1.2)
    ui.chestSlots={}
    for i=1,capacity do
        local r=ctx.Inventory.chestSlotRect(i); ui.chestSlots[i]=r; love.graphics.setColor(0.25,0.18,0.12); love.graphics.rectangle("fill",r.x,r.y,r.w,r.h,7,7)
        if activeChest and activeChest.storage[i] then InventoryUI.drawItem(ctx,activeChest.storage[i],r) end
    end
    love.graphics.setColor(ctx.colors.cream)
    love.graphics.printf(mailbox and "TAKE REWARDS ONLY  -  ITEMS CANNOT BE DEPOSITED" or "SHIFT + CLICK TO QUICK TRANSFER",55,445,440,"center",0,.8,.8)
end

function InventoryUI.handleClick(ctx,x,y)
    local ui=ctx.ui
    if ctx.giftOpen then
        if ctx.pointIn(x,y,ui.giftCancel) then ctx.set("giftOpen",false); ctx.set("inventoryOpen",false); ctx.set("giftSlot",nil); return true end
        if ctx.pointIn(x,y,ui.giftConfirm) and ctx.giftSlot then ctx.offerGift(ctx.giftSlot); return true end
        local clicked=InventoryUI.slotAtPoint(ctx,x,y)
        if clicked and clicked.kind=="inventory" and ctx.value(clicked) then ctx.set("giftSlot",clicked.index); return true end
        return true
    end
    local clicked=InventoryUI.slotAtPoint(ctx,x,y)
    if clicked then
        local now=love.timer.getTime(); local name=ctx.value(clicked); local effect=name and ctx.Catalog.itemEffects[name]
        local last=ctx.lastClick
        if name and clicked.kind=="chest" and ctx.Catalog.ammoPickupAmounts[name] and love.keyboard.isDown("lshift","rshift") then ctx.collectAmmo(clicked); return true end
        if name and clicked.kind=="chest" and ctx.Catalog.ammoPickupAmounts[name] and last and last.kind==clicked.kind and last.index==clicked.index and now-ctx.lastClickTime<=.38 then
            ctx.collectAmmo(clicked); ctx.set("lastClick",nil); ctx.set("lastClickTime",0); return true
        end
        if effect and (effect.food or effect.water) and last and last.kind==clicked.kind and last.index==clicked.index and now-ctx.lastClickTime<=.38 then
            ctx.set("draggedSlot",clicked); ctx.set("inventoryDragActive",false); ctx.set("lastClick",nil); ctx.set("lastClickTime",0); ctx.consume(); return true
        end
        ctx.set("lastClick",{kind=clicked.kind,index=clicked.index}); ctx.set("lastClickTime",now)
        if love.keyboard.isDown("lshift","rshift") and ctx.value(clicked) and ctx.quickTransfer(clicked) then ctx.set("draggedSlot",nil); ctx.set("inventoryDragActive",false); return true end
        if ctx.value(clicked) then ctx.set("draggedSlot",clicked); ctx.set("inventoryDragActive",true) end
        return true
    end
    if ctx.draggedSlot and ctx.pointIn(x,y,ui.consume) then ctx.consume(); return true end
    if ctx.draggedSlot and ctx.pointIn(x,y,ui.drop) then ctx.drop(ctx.draggedSlot); return true end
    return false
end

function InventoryUI.handleRelease(ctx,x,y,button)
    if button~=1 or not ctx.inventoryOpen or not ctx.inventoryDragActive or not ctx.draggedSlot then return false end
    local target=InventoryUI.slotAtPoint(ctx,x,y)
    local same=target and target.kind==ctx.draggedSlot.kind and target.index==ctx.draggedSlot.index
    if target and not same then
        if ctx.move(ctx.draggedSlot,target) then ctx.set("draggedSlot",nil) end
        ctx.set("inventoryDragActive",false)
    elseif ctx.battleMode then
        ctx.set("inventoryDragActive",false)
    elseif not target and not ctx.pointIn(x,y,{x=40,y=125,w=860,h=445}) then
        ctx.drop(ctx.draggedSlot); ctx.set("inventoryDragActive",false)
    else ctx.set("inventoryDragActive",false) end
    return true
end

return InventoryUI
