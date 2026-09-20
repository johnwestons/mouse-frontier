local Catalog=require("game.catalog")
local Inventory=require("game.inventory")
local Model={}
Model.categories={"All","Weapons","Ammunition","Food & drink","Medicine","Potions","Supplies","Backpacks","Storage","Furniture","Decorations","Other"}
Model.directories={"props","items","furniture","weapons","train-decorations","ammo","gear"}
-- Source sheets and engine effects share asset folders but are not inventory objects.
local excluded={["backpack-upgrades-v1"]=true,["backpack-upgrades-v1-source"]=true,
    ["boiler-firebox"]=true,["locomotive-smoke-large-1"]=true,["locomotive-smoke-large-2"]=true,["locomotive-smoke-small"]=true}
function Model.title(name) return (name:gsub("%-"," "):gsub("%a[%w']*",function(s) return s:sub(1,1):upper()..s:sub(2) end)) end
function Model.entry(name,directory)
    local weapon,effect,pack,storage=Catalog.weaponStats[name],Catalog.itemEffects[name],Catalog.backpackUpgrades[name],Catalog.storageCapacities[name]
    local category="Other"
    if weapon then category="Weapons"
    elseif Catalog.ammoPickupAmounts[name] then category="Ammunition"
    elseif pack then category="Backpacks"
    elseif storage then category="Storage"
    elseif effect and effect.potion then category="Potions"
    elseif effect and effect.health then category="Medicine"
    elseif effect and (effect.food or effect.water) then category="Food & drink"
    elseif name=="coal-chunk" or (effect and effect.oil) then category="Supplies"
    elseif directory=="furniture" then category="Furniture"
    elseif directory=="train-decorations" or directory=="props" then category="Decorations" end
    local detail={category.." | "..Catalog.rarityFor(name)}
    if weapon then
        detail[#detail+1]="Damage: "..weapon.min.." - "..weapon.max.."   Tier: "..weapon.tier
        local combat=Catalog.weaponCombat[name] or {}
        detail[#detail+1]=(combat.kind or "melee")..(combat.range and " | Range: "..combat.range or "")
        if combat.ammo then detail[#detail+1]="Ammo: "..Model.title(combat.ammo) end
    end
    if effect then
        if effect.description then detail[#detail+1]=effect.description
        else
            for _,key in ipairs({"food","water","health","oil"}) do
                if effect[key] then detail[#detail+1]="Restores "..effect[key].." "..key.."." end
            end
        end
    end
    if name=="coal-chunk" then detail[#detail+1]="Adds coal when used as fuel." end
    if pack then detail[#detail+1]="Backpack capacity: "..pack.capacity.." slots." end
    if storage then detail[#detail+1]="Storage capacity: "..storage.." items." end
    if Catalog.ammoPickupAmounts[name] then detail[#detail+1]="Added directly to your ammunition counter, in rounds." end
    if category=="Furniture" or category=="Decorations" or category=="Storage" then detail[#detail+1]="Carry in your backpack; place using the inventory." end
    detail[#detail+1]="Trade value: "..Inventory.scrapPrice(name,Catalog).." scrap."
    local label=(weapon and weapon.name) or (pack and pack.label) or Model.title(name)
    return {id=name,label=label,category=category,rarity=Catalog.rarityFor(name),detail=table.concat(detail,"\n"),search=(name.." "..label.." "..table.concat(detail," ")):lower()}
end
function Model.build(fs,atlases)
    local names={}
    for _,directory in ipairs(Model.directories) do
        local path="assets/sprites/"..directory
        if fs.getInfo(path) then
            for _,file in ipairs(fs.getDirectoryItems(path)) do
                if file:match("%.png$") and not excluded[file:sub(1,-5)] then names[file:sub(1,-5)]=directory end
            end
        end
    end
    for name in pairs(atlases or {}) do names[name]=names[name] or "items" end
    for _,field in ipairs({"weaponStats","itemEffects","backpackUpgrades","ammoPickupAmounts","storageCapacities"}) do
        for name in pairs(Catalog[field]) do if name~="scratch" and not name:match("^mob%-") then names[name]=names[name] or "items" end end
    end
    local entries={}
    for name,directory in pairs(names) do entries[#entries+1]=Model.entry(name,directory) end
    table.sort(entries,function(a,b) if a.label==b.label then return a.id<b.id end return a.label<b.label end)
    return entries
end
function Model.filter(entries,query,category,rarity)
    local result={}
    query=(query or ""):lower()
    for _,entry in ipairs(entries) do
        local matches=(not category or category=="All" or entry.category==category) and (not rarity or rarity=="All" or entry.rarity==rarity)
        for word in query:gmatch("%S+") do if not entry.search:find(word,1,true) then matches=false; break end end
        if matches then result[#result+1]=entry end
    end
    return result
end
function Model.amount(value)
    local number=tonumber(value)
    if not number or number~=number or number==math.huge or number<1 or number>999999 or number~=math.floor(number) then return nil end
    return number
end
function Model.resources(data)
    local result={{id="scrap",label="Scrap",kind="scrap"}}
    local keys={food=true,water=true,coal=true,oil=true}
    for name in pairs(data and data.resources or {}) do keys[name]=true end
    local sorted={}; for name in pairs(keys) do sorted[#sorted+1]=name end; table.sort(sorted)
    for _,name in ipairs(sorted) do result[#result+1]={id=name,label=Model.title(name),kind="resources"} end
    sorted={}; for name in pairs(Catalog.ammoPickupAmounts) do sorted[#sorted+1]=name end; table.sort(sorted)
    for _,name in ipairs(sorted) do result[#result+1]={id=name,label=Model.title(name).." ammo",kind="ammo"} end
    return result
end
function Model.resourceValue(data,entry)
    if not data then return 0 end
    return entry.kind=="scrap" and (data.scrap or 0) or ((data[entry.kind] or {})[entry.id] or 0)
end
function Model.grantResource(data,entry,value)
    local amount=Model.amount(value)
    if not data then return false,"Load a journey to add resources." end
    if not amount then return false,"Enter a whole quantity from 1 to 999999." end
    local valid=false
    for _,known in ipairs(Model.resources(data)) do if known.id==entry.id and known.kind==entry.kind then valid=true end end
    if not valid then return false,"Unknown resource." end
    local total=Model.resourceValue(data,entry)+amount
    if total>999999999 then return false,"Resource limit reached." end
    if entry.kind=="scrap" then data.scrap=total else data[entry.kind]=data[entry.kind] or {}; data[entry.kind][entry.id]=total end
    return true,"Added "..amount.." "..entry.label.."."
end
function Model.grantItem(data,entry,value)
    if not data then return false,"Load a journey to add items." end
    local amount=Model.amount(value)
    if not amount then return false,"Enter a whole quantity from 1 to 999999." end
    if Catalog.ammoPickupAmounts[entry.id] then return Model.grantResource(data,{id=entry.id,kind="ammo",label=entry.label},amount) end
    local free={}
    for i=1,(data.inventoryCapacity or 6) do if not data.inventory[i] then free[#free+1]=i end end
    if #free<amount then return false,"Only "..#free.." free backpack slots. Lower the quantity or make room." end
    for i=1,amount do data.inventory[free[i]]=entry.id end
    return true,"Added "..amount.." x "..entry.label.." to your backpack."
end
return Model
