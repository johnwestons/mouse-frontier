local Typography = require("game.typography")
local UIStyle = require("game.ui_layout")
local OutfitItemArt = require("game.outfit_item_art")
local InventoryUI = {}

local function text(value,x,y,w,h,scale,minimum,align)
    return Typography.drawText(love.graphics,value,x,y,w,h,{scale=scale,minScale=minimum or scale,align=align or "left",valign="center"})
end

local function detailCard(ctx)
    -- The three-line detail card needs the full interior height; a decorative
    -- menu frame's thick top and bottom strips would cross the text.
    love.graphics.setColor(.08,.055,.035,.97); love.graphics.rectangle("fill",565,562,350,56,5,5)
    love.graphics.setColor(ctx.colors.brass); love.graphics.rectangle("line",565,562,350,56,5,5)
    love.graphics.setColor(ctx.colors.cream)
end

local function inventorySlotRect(ctx,index)
    if ctx.mobileEnabled then
        local r=ctx.Inventory.mobileInventorySlotRect(index)
        -- A fourth backpack row must end above the equipped-weapons heading.
        -- This same rectangle is used for drawing, dragging, and hit testing.
        if (ctx.data.inventoryCapacity or 6)>12 then r.y=230+math.floor((index-1)/4)*56; r.h=50 end
        return r
    end
    return ctx.Inventory.inventorySlotRect(index)
end

local function equipmentSlotRect(ctx,index)
    if ctx.mobileEnabled then return ctx.Inventory.mobileEquipmentSlotRect(index) end
    return ctx.Inventory.equipmentSlotRect(index)
end

local function sameSlot(a,b)
    if not a or not b or a.kind~=b.kind then return false end
    if a.kind=="wearable" then return a.slot==b.slot end
    return a.index==b.index
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
    if ctx.inventoryMode=="wearables" then
        for index,slot in ipairs(ctx.Catalog.wearableSlots or {}) do
            if ctx.pointIn(x,y,ctx.Inventory.wearableSlotRect(index)) then return {kind="wearable",slot=slot.id} end
        end
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
    if OutfitItemArt.draw(name,r) then return end
    local repairPart=ctx.Catalog.repairParts and ctx.Catalog.repairParts[name]
    local imageName=(ctx.Catalog.repairPartAliases and ctx.Catalog.repairPartAliases[name]) or name
    local atlas=not repairPart and ctx.ui.atlasItems and ctx.ui.atlasItems[name]
    local img=ctx.ui.propImages[imageName]
    local variant=UIStyle.iconVariant()
    if variant=="prop" and img then atlas=nil
    elseif variant=="atlas" and atlas then img=nil end
    if atlas then
        local s=math.min(math.min(64,r.w-8)/atlas.w,math.min(64,r.h-8)/atlas.h)*UIStyle.iconScale()
        love.graphics.setColor(1,1,1)
        love.graphics.draw(atlas.image,atlas.quad,r.x+r.w/2,r.y+r.h/2,0,s,s,atlas.w/2,atlas.h/2)
    elseif img then
        local s=math.min(math.min(58,r.w-8)/img:getWidth(),math.min(58,r.h-8)/img:getHeight())*UIStyle.iconScale()
        love.graphics.setColor(1,1,1)
        love.graphics.draw(img,r.x+r.w/2,r.y+r.h/2,0,s,s,img:getWidth()/2,img:getHeight()/2)
    else
        love.graphics.setColor(ctx.colors.cream)
        text(repairPart and (repairPart.component or repairPart.name) or ctx.title(name or ""),r.x+4,r.y+4,r.w-8,r.h-8,.70,.58,"center")
    end
end

function InventoryUI.draw(ctx)
    local data,ui,Inventory,Catalog=ctx.data,ctx.ui,ctx.Inventory,ctx.Catalog
    local capacity=data.inventoryCapacity or 6
    local mobile=ctx.mobileEnabled
    ui.outfitWorkbenchPanel=nil; ui.inventorySewingBench=nil; ui.inventoryWeaponRepair=nil
    if not ctx.battleMode and not ctx.chestOpen and not ctx.giftOpen
        and ui.canOpenOutfitWorkbench and ui.canOpenWeaponRepairWorkbench then
        local panel={x=35,y=165,w=490,h=290}; ui.outfitWorkbenchPanel=panel
        ctx.drawMenuFrame(panel.x,panel.y,panel.w,panel.h,3,.97)
        love.graphics.setColor(ctx.colors.brass); text("WORKSHOP",55,185,450,28,1,.82,"center")
        love.graphics.setColor(ctx.colors.cream)
        text("Repair owned weapons with parts and scrap, or sew upgrades from gathered materials.",60,224,440,76,.88,.76,"center")
        local weaponAvailable,weaponReason=ui.canOpenWeaponRepairWorkbench()
        local outfitAvailable,outfitReason=ui.canOpenOutfitWorkbench()
        ctx.button("WEAPON REPAIR",52,318,212,60,weaponAvailable,.82)
        ctx.button("SEWING BENCH",275,318,212,60,outfitAvailable,.82)
        -- Inventory input is converted back into this panel's coordinates.
        ui.inventoryWeaponRepair={x=52,y=318,w=212,h=60,enabled=weaponAvailable}
        ui.inventorySewingBench={x=275,y=318,w=212,h=60,enabled=outfitAvailable}
        local reason=not weaponAvailable and weaponReason or not outfitAvailable and outfitReason
        text(reason or "Choose a bench while the train is stopped.",60,390,440,38,.74,.64,"center")
    end
    ctx.drawMenuFrame(545,35,390,145,3,.94)
    ui.inventoryModeTabs={}
    for index,tab in ipairs({{id="ammo",label="AMMUNITION"},{id="wearables",label="GEAR UPGRADES"}}) do
        local r={x=565+(index-1)*175,y=43,w=165,h=22}
        ui.inventoryModeTabs[tab.id]=r
        local active=(ctx.inventoryMode or "wearables")==tab.id
        love.graphics.setColor(active and .30 or .12,active and .22 or .09,active and .14 or .07,1)
        love.graphics.rectangle("fill",r.x,r.y,r.w,r.h,5,5)
        love.graphics.setColor(ctx.colors.brass); love.graphics.rectangle("line",r.x,r.y,r.w,r.h,5,5)
        love.graphics.setColor(ctx.colors.cream); text(tab.label,r.x+4,r.y+1,r.w-8,r.h-2,.78,.70,"center")
    end
    if (ctx.inventoryMode or "wearables")=="ammo" then
        ui.wearableSlots=nil
        for i,entry in ipairs(ammoDisplay) do
            local col=(i-1)%5; local row=math.floor((i-1)/5); local x,y=558+col*75,68+row*33
            local image=ui.propImages[entry[1]]
            if image then
                local scale=math.min(22/image:getWidth(),26/image:getHeight())
                love.graphics.setColor(1,1,1); love.graphics.draw(image,x+10,y+15,0,scale,scale,image:getWidth()/2,image:getHeight()/2)
            end
            love.graphics.setColor(ctx.colors.cream)
            text(entry[2],x+24,y,49,14,.64,.62)
            text(tostring(data.ammo[entry[1]] or 0),x+24,y+14,49,17,.80,.64)
        end
    else
        ui.wearableSlots={}
        for index,slot in ipairs(Catalog.wearableSlots or {}) do
            local r=Inventory.wearableSlotRect(index); ui.wearableSlots[slot.id]=r
            love.graphics.setColor(ctx.colors.cream); text(slot.label,r.x,r.y-20,r.w,17,.70,.62,"center")
            love.graphics.setColor(.28,.22,.16); love.graphics.rectangle("fill",r.x,r.y,r.w,r.h,7,7)
            love.graphics.setColor(ctx.colors.brass); love.graphics.rectangle("line",r.x,r.y,r.w,r.h,7,7)
            local name=data.wearables and data.wearables[slot.id]
            if name then InventoryUI.drawItem(ctx,name,r)
            else
                love.graphics.setColor(ctx.colors.cream); text("EMPTY",r.x+4,r.y+4,r.w-8,r.h-8,.68,.60,"center")
            end
        end
    end
    ctx.drawMenuFrame(545,185,390,510,2,1)
    love.graphics.setColor(.12,.09,.07,1); love.graphics.rectangle("fill",570,202,340,27,6,6)
    love.graphics.setColor(ctx.colors.cream); text("BACKPACK  -  "..capacity.." SLOTS",575,204,330,23,1,.85)
    for i=1,capacity do
        local r=inventorySlotRect(ctx,i); love.graphics.setColor(0.28,0.22,0.16); love.graphics.rectangle("fill",r.x,r.y,r.w,r.h,7,7)
        if data.inventory[i] then InventoryUI.drawItem(ctx,data.inventory[i],r) end
    end
    love.graphics.setColor(.12,.09,.07,1); love.graphics.rectangle("fill",570,462,340,26,6,6)
    love.graphics.setColor(ctx.colors.cream); text("EQUIPPED WEAPONS",580,464,320,23,.90,.82)
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
        detailCard(ctx)
        text(stats.name.."  T"..stats.tier,578,565,324,17,.83,.70)
        text("DMG "..stats.min.."-"..stats.max.."  REACH "..Catalog.weaponReach(inspectName).."  DUR "..durability.."%"..(durability<=0 and " BROKEN" or ""),578,583,324,15,.70,.62)
        local role=combat.ammo and (ctx.title(combat.ammo).." AMMO: "..(data.ammo[combat.ammo] or 0)) or Catalog.weaponRole(inspectName)
        text(role,578,599,324,15,.70,.62)
    elseif inspectName and Catalog.wearableItems[inspectName] then
        local profile=Catalog.wearableItems[inspectName]; local stats={}
        if profile.capacity then stats[#stats+1]="CAPACITY "..profile.capacity end
        local statLabels={armor="ARMOR",aim="AIM",attack="ATTACK",move="MOVE",maxHealth="HEALTH"}
        for _,stat in ipairs({"armor","aim","attack","move","maxHealth"}) do
            local amount=profile.bonuses and profile.bonuses[stat]
            if amount and amount~=0 then stats[#stats+1]=statLabels[stat].." "..(amount>0 and "+" or "")..amount end
        end
        local slotLabel=profile.slot
        for _,slot in ipairs(Catalog.wearableSlots or {}) do if slot.id==profile.slot then slotLabel=slot.label end end
        detailCard(ctx)
        text(profile.label or ctx.title(inspectName),578,565,324,17,.83,.70)
        text(slotLabel,578,583,324,15,.70,.62)
        local statText=#stats>0 and table.concat(stats,"  ") or "GEAR UPGRADE"
        if profile.recipeId then statText="BATTLE: "..statText end
        text(statText,578,599,324,15,.70,.62)
    elseif inspectName and Catalog.craftMaterials and Catalog.craftMaterials[inspectName] then
        local material=Catalog.craftMaterials[inspectName]
        detailCard(ctx)
        text(material.label or ctx.title(inspectName),578,565,324,17,.83,.70)
        text(material.description or "Gather for outfit crafting at the sewing bench.",578,585,324,29,.75,.64)
    elseif inspectName and Catalog.itemEffects[inspectName] and Catalog.itemEffects[inspectName].potion then
        local effect=Catalog.itemEffects[inspectName]
        detailCard(ctx)
        text(ctx.title(inspectName),578,565,324,17,.83,.70)
        text(effect.description,578,583,324,30,.70,.64)
    elseif inspectName and Catalog.itemEffects[inspectName] and (Catalog.itemEffects[inspectName].food or Catalog.itemEffects[inspectName].water) then
        local effect=Catalog.itemEffects[inspectName]; local restored={}
        if effect.food then restored[#restored+1]="FOOD +"..effect.food end
        if effect.water then restored[#restored+1]="WATER +"..effect.water end
        detailCard(ctx)
        text(ctx.title(inspectName),578,565,324,17,.83,.70)
        text("RESTORES  "..table.concat(restored,"   "),578,584,324,16,.75,.65)
        text((mobile and "DOUBLE TAP TO " or "DOUBLE CLICK TO ")..(effect.label or "USE"),578,600,324,15,.67,.62)
    elseif inspectName and Catalog.itemEffects[inspectName] then
        local effect=Catalog.itemEffects[inspectName]
        detailCard(ctx)
        text(ctx.title(inspectName),578,565,324,17,.83,.70)
        text(effect.health and ("RESTORES "..effect.health.." HP") or effect.description or (effect.label or "USE"),578,585,324,28,.76,.64)
    elseif inspectName and Catalog.rangeTools and Catalog.rangeTools[inspectName] then
        local tool=Catalog.rangeTools[inspectName]
        detailCard(ctx)
        text(ctx.title(inspectName),578,565,324,17,.83,.70)
        text(tool.description or "Reusable tool for the shooting range.",578,585,324,28,.76,.64)
    elseif inspectName and Catalog.repairParts and Catalog.repairParts[inspectName] then
        local part=Catalog.repairParts[inspectName]
        local weapon=Catalog.weaponStats[part.weapon]
        detailCard(ctx)
        love.graphics.setColor(ctx.colors.brass); text(part.name,578,565,324,29,.76,.62)
        love.graphics.setColor(ctx.colors.cream); text("FITS: "..(weapon and weapon.name or ctx.title(part.weapon)),578,598,324,15,.70,.60)
    elseif inspectName and Catalog.miscItems and Catalog.miscItems[inspectName] then
        local item=Catalog.miscItems[inspectName]
        detailCard(ctx)
        text(ctx.title(inspectName),578,565,324,17,.83,.70)
        text(item.description,578,585,324,28,.76,.64)
    end
    local special=selectedName=="rose-heart-arrow" or selectedName=="blade-hearts"
    local effect=selectedName and Catalog.itemEffects[selectedName]
    local rangeTool=selectedName and Catalog.rangeTools and Catalog.rangeTools[selectedName]
    local wearable=selectedName and Catalog.wearableItems[selectedName]
    local selectedWearable=ctx.draggedSlot and ctx.draggedSlot.kind=="wearable"
    local wearableLabel=selectedWearable and ctx.draggedSlot.slot or (wearable and wearable.slot)
    for _,slot in ipairs(Catalog.wearableSlots or {}) do if slot.id==wearableLabel then wearableLabel=slot.label end end
    local gift=ctx.isWeapon(selectedName) and (ctx.nearNPC or ctx.nearPassenger)
    local battleUsable=ctx.battleMode and (ctx.isWeapon(selectedName) or (effect and (effect.health or effect.potion)))
    local actionLabel
    if ctx.battleMode then
        if ctx.isWeapon(selectedName) then actionLabel="EQUIP TO WEAPON SLOT 1"
        elseif effect then actionLabel=(effect.label or "USE").." "..ctx.title(selectedName)
        elseif wearable or selectedWearable then actionLabel="GEAR UPGRADES CHANGE OUTSIDE BATTLE"
        else actionLabel="SELECT MEDICINE, POTION, OR WEAPON" end
    else
        if gift then actionLabel="GIVE WEAPON TO ALLY"
        elseif selectedWearable then actionLabel="REMOVE "..wearableLabel
        elseif wearable then actionLabel=(wearable.slot=="backpack" and "EQUIP " or "INSTALL ")..wearableLabel
        elseif special then actionLabel="USE "..ctx.title(selectedName)
        elseif effect then actionLabel=effect.label.." "..ctx.title(selectedName)
        elseif rangeTool then actionLabel="REUSABLE TOOL - ACTIVATE AT THE RANGE"
        elseif Catalog.craftMaterials and Catalog.craftMaterials[selectedName] then actionLabel="CRAFTING SUPPLY"
        elseif Catalog.repairParts and Catalog.repairParts[selectedName] then actionLabel="REPAIR COMPONENT"
        elseif Catalog.miscItems and Catalog.miscItems[selectedName] then actionLabel="MISCELLANEOUS ITEM"
        else actionLabel="SELECT AN ITEM TO USE" end
    end
    local consumeEnabled
    if ctx.battleMode then consumeEnabled=battleUsable
    else consumeEnabled=effect~=nil or special or wearable~=nil or selectedWearable or gift end
    ui.consume=ctx.button(actionLabel,565,mobile and 620 or 628,230,mobile and 62 or 38,consumeEnabled)
    if ui.consume then ui.consume.enabled=consumeEnabled end
    if ctx.giftOpen then
        ctx.drawMenuFrame(220,170,520,180,3,.97); love.graphics.setColor(ctx.colors.cream)
        text("GIVE TO "..ctx.title(ctx.giftNPC or "NPC"),240,187,480,29,1.15,.92,"center")
        text("Place one item in the offer slot",250,218,460,22,.90,.78,"center")
        local offer={x=445,y=245,w=70,h=70}; love.graphics.setColor(.28,.22,.16); love.graphics.rectangle("fill",offer.x,offer.y,offer.w,offer.h,7,7)
        if ctx.giftSlot then InventoryUI.drawItem(ctx,data.inventory[ctx.giftSlot],offer) end
        ui.giftSlot=offer; ui.giftConfirm=ctx.button("OFFER",535,mobile and 250 or 260,mobile and 130 or 100,mobile and 64 or 36,ctx.giftSlot~=nil); ui.giftConfirm.enabled=ctx.giftSlot~=nil; ui.giftCancel=ctx.button("CANCEL",mobile and 295 or 325,mobile and 250 or 260,mobile and 130 or 100,mobile and 64 or 36,true)
    else ui.giftSlot=nil; ui.giftConfirm=nil; ui.giftCancel=nil end
    if ctx.battleMode then
        ui.drop=nil
        love.graphics.setColor(ctx.colors.cream)
        text("NO DROPS\nIN BATTLE",805,mobile and 626 or 628,110,mobile and 48 or 38,.74,.67,"center")
    else ui.drop=ctx.button("DROP",805,mobile and 620 or 628,110,mobile and 62 or 38,ctx.draggedSlot~=nil); ui.drop.enabled=ctx.draggedSlot~=nil end
end

function InventoryUI.drawChest(ctx)
    local activeChest,ui=ctx.activeChest,ctx.ui
    ctx.drawMenuFrame(25,145,505,490,2,1)
    local capacity=activeChest and ctx.Catalog.storageCapacities[activeChest.name] or 10
    local mailbox=activeChest and activeChest.mailbox
    love.graphics.setColor(ctx.colors.cream)
    text(mailbox and ("REWARD MAILBOX  -  "..capacity.." SLOTS") or (ctx.title(activeChest and activeChest.name or "Storage").."  -  "..capacity.." SLOTS"),55,192,445,32,1.1,.85)
    ui.chestSlots={}
    for i=1,capacity do
        local r=ctx.Inventory.chestSlotRect(i); ui.chestSlots[i]=r; love.graphics.setColor(0.25,0.18,0.12); love.graphics.rectangle("fill",r.x,r.y,r.w,r.h,7,7)
        if activeChest and activeChest.storage[i] then InventoryUI.drawItem(ctx,activeChest.storage[i],r) end
    end
    love.graphics.setColor(ctx.colors.cream)
    local help=mailbox and "TAKE REWARDS ONLY  -  NO DEPOSITS" or (ctx.mobileEnabled and "DRAG ITEMS TO OR FROM YOUR BACKPACK" or "SHIFT + CLICK TO QUICK TRANSFER")
    text(help,55,capacity>10 and 592 or 445,440,30,.82,.74,"center")
end

function InventoryUI.handleClick(ctx,x,y)
    local ui=ctx.ui
    if not ctx.giftOpen and ui.inventoryWeaponRepair and ui.inventoryWeaponRepair.enabled
        and ctx.pointIn(x,y,ui.inventoryWeaponRepair) then
        if ui.openWeaponRepairWorkbench then ui.openWeaponRepairWorkbench() end
        return true
    end
    if not ctx.giftOpen and ui.inventorySewingBench and ui.inventorySewingBench.enabled
        and ctx.pointIn(x,y,ui.inventorySewingBench) then
        if ui.openOutfitWorkbench then ui.openOutfitWorkbench() end
        return true
    end
    if not ctx.giftOpen then
        for mode,rect in pairs(ui.inventoryModeTabs or {}) do
            if ctx.pointIn(x,y,rect) then
                ctx.set("inventoryMode",mode); ctx.set("draggedSlot",nil); ctx.set("inventoryDragActive",false)
                return true
            end
        end
    end
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
        if name and clicked.kind=="chest" and ctx.Catalog.ammoPickupAmounts[name] and sameSlot(last,clicked) and now-ctx.lastClickTime<=.38 then
            ctx.collectAmmo(clicked); ctx.set("lastClick",nil); ctx.set("lastClickTime",0); return true
        end
        if effect and (effect.food or effect.water) and sameSlot(last,clicked) and now-ctx.lastClickTime<=.38 then
            ctx.set("draggedSlot",clicked); ctx.set("inventoryDragActive",false); ctx.set("lastClick",nil); ctx.set("lastClickTime",0); ctx.consume(); return true
        end
        local doubleClick=sameSlot(last,clicked) and now-ctx.lastClickTime<=.38
        local special=name=="rose-heart-arrow" or name=="blade-hearts"
        local wearable=name and ctx.Catalog.wearableItems[name]
        local nonConsumable=name and (ctx.isWeapon(name) or (not effect and not special and not wearable))
        if nonConsumable and doubleClick and ctx.quickTransfer(clicked) then
            ctx.set("draggedSlot",nil); ctx.set("inventoryDragActive",false)
            ctx.set("lastClick",nil); ctx.set("lastClickTime",0)
            return true
        end
        ctx.set("lastClick",{kind=clicked.kind,index=clicked.index,slot=clicked.slot}); ctx.set("lastClickTime",now)
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
    local same=target and target.kind==ctx.draggedSlot.kind
        and (target.kind=="wearable" and target.slot==ctx.draggedSlot.slot
            or target.kind~="wearable" and target.index==ctx.draggedSlot.index)
    if ctx.battleMode and (ctx.draggedSlot.kind=="wearable" or (target and target.kind=="wearable")) then
        ctx.set("inventoryDragActive",false)
        return true
    end
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
