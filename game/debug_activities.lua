-- Explicit, offline cheats. Entry uses the same bootstrap and activity services
-- as normal play, so locks, item identities, and ordinary exits stay valid.
local Areas=require('game.expedition_areas')
local Items=require('game.item_instances')
local Model=require('game.player_tools_model')
local Debug={}
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
function Debug.new(c)
    local self={}
    local entries={
        {id='range',label='GUN RANGE',detail='Weapon, distance and challenge selection.'},
        {id='ambush',label='BANDIT ATTACK',detail='Fresh train ambush; use Withdraw to leave.'},
        {id='lastStand',label='LAST STAND',detail='Start at the farmhouse backyard.'},
        {id='shootout',label='LAST STAND: SHOOTOUT',detail='Jump straight to a firing position.'},
        {id='firstAid',label='FIRST AID PRACTICE',detail='All treatment stages; no quest rewards.'},
        {id='maintenance',label='TRAIN MAINTENANCE',detail='Fresh wheel-hub service session.'},
        {id='sewing',label='SEWING',detail='Open the bench; resume an existing project.'},
        {id='repair',label='WEAPON REPAIR',detail='Open the bench with a worn test rifle.'},
        {id='battle',label='TACTICAL BATTLE',detail='Start a fresh ordinary combat encounter.'},
    }
    local ids={};for id in pairs(Areas.definitions) do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids) do local area=Areas.definitions[id]
        entries[#entries+1]={id='area:'..id,label=area.name:upper(),detail='Adventure at stop '..area.stop..'; existing area progress retained.',area=id}
    end
    function self:entries() return entries end
    function self:available()
        local r=c.runtime
        if not r.saveData or not r.selectedSlot or (r.state~='game' and r.state~='battle' and r.state~='event' and r.state~='ending') then
            return false,'Load a save file first.'
        end
        if c.controller:isClient() or r.session and r.session.networkMode~='offline' and r.session.networkMode~=nil then
            return false,'Disconnect Local Play before launching a debug activity.'
        end
        if c.ui.checkpointBlocked or r.session and r.session.checkpointPending then return false,'Wait for the save checkpoint to finish.' end
        return true
    end
    local function grant(data,id,count)
        local owned=0;for _,name in pairs(data.inventory) do if name==id then owned=owned+1 end end
        local needed=math.max(0,(count or 1)-owned)
        if needed==0 then return true end
        local free=0;for i=1,data.inventoryCapacity or 6 do if not data.inventory[i] then free=free+1 end end
        if free<needed then return false,'Make room in the backpack for test supplies, or turn Test Supplies off.' end
        return Model.grantItem(data,{id=id,label=id},needed)
    end
    function self:launch(id,supplies)
        local allowed,reason=self:available();if not allowed then return false,reason end
        local entry;for _,item in ipairs(entries) do if item.id==id then entry=item;break end end
        if not entry then return false,'Unknown activity.' end
        local r=c.runtime;local data=copy(r.saveData)
        if data.players then require('game.coop_players').attachHost(data) end
        data.scene='train';data.stopped=true;data.activeCar=1;data.playerX=nil;data.playerY=nil
        data.activeExpeditionArea=nil;data.expeditionBattle=nil;data.tacticalBattle=nil;data.roamingEncounter=nil
        data.trainAmbush=nil;data.rangeSessions=nil
        if data.events then data.events.current=nil end
        if data.coop then data.coop.journey=nil;data.coop.activities=nil end
        if data.lastStand and data.lastStand.state~='complete' and data.lastStand.state~='waiting' then
            require('game.coop_last_stand_lifecycle').move(data.lastStand,'approach','paused')
        end
        if supplies~=false then
            data.health=data.maxHealth or 20;data.scrap=math.max(data.scrap or 0,100)
            data.resources=data.resources or {};for _,key in ipairs({'food','water','coal','oil'}) do data.resources[key]=math.max(data.resources[key] or 0,20) end
            data.ammo=data.ammo or {};for _,weapon in pairs(c.catalog.weaponCombat) do if weapon.ammo then data.ammo[weapon.ammo]=math.max(data.ammo[weapon.ammo] or 0,120) end end
            if id=='range' or id=='ambush' or id=='repair' or id=='battle' or entry.area then
                local ok,reason=grant(data,'frontier-22-lever-rifle');if not ok then return false,reason end
            end
            if id=='sewing' then for _,cost in ipairs(require('game.outfit_catalog').recipes[1].materials) do
                local ok,reason=grant(data,cost.id,cost.count);if not ok then return false,reason end
            end end
        end
        if entry.area then
            local area=Areas.definitions[entry.area];data.location=area.stop;data.scene='expedition';data.activeExpeditionArea=entry.area
            local spawn=area.spawns.town or area.spawns.surface or select(2,next(area.spawns))
            data.playerX,data.playerY=spawn.x,spawn.y
        elseif id=='range' then data.location=2;data.scene='stop'
        elseif id=='lastStand' or id=='shootout' then data.location=5;data.scene='stop'
        elseif id=='maintenance' then
            local state=c.maintenance.ensure(data);state.lastServicedStop=nil;state.condition=65
        elseif id=='repair' and supplies~=false then
            for _,item in ipairs(Items.weapons(data,c.catalog)) do
                if item.name=='frontier-22-lever-rifle' then Items.setCondition(data,item.id,45);break end
            end
        elseif id=='battle' then
            data.location=2;data.scene='stop';data.encounters[tostring(data.location)]={rolled=true,hasMob=true,resolved=false,tier='easy',mobFile=c.catalog.mobTiers.easy[1],mobFiles={c.catalog.mobTiers.easy[1]}}
        end
        c.closeActivities()
        local ok,message=c.enterGame(data);if not ok then return false,message or 'Could not enter activity.' end
        r.dialogue=nil;c.ui.mobileMenuOpen=false;c.ui.optionsOpen=false;c.ui.escMenuOpen=false
        if id=='range' then
            local spot=c.world.currentShootingRange();if not spot then return false,'No range at this stop.' end
            r.player.x,r.player.y=spot.x,spot.y
            ok,message=c.world.beginShootingRange()
        elseif id=='ambush' then require('game.train_ambush_rules').start(r.saveData);ok=true
        elseif id=='lastStand' or id=='shootout' then ok,message=c.lastStand:debugStart(id=='shootout')
        elseif id=='firstAid' then
            r.firstAid=require('game.first_aid').new({npc=r.saveData.currentNPC,location=r.saveData.location});r.firstAid.debugPractice=true;ok=true
        elseif id=='maintenance' then ok=c.maintenance.open(c.maintenanceSession,r.saveData)
        elseif id=='sewing' then ok=c.ui.openOutfitWorkbench()
        elseif id=='repair' then
            ok=c.ui.openWeaponRepairWorkbench()
            if ok and supplies~=false then for _,item in ipairs(Items.weapons(r.saveData,c.catalog)) do
                if item.name=='frontier-22-lever-rifle' then r.weaponRepairSelected=item.key;break end
            end end
        elseif id=='battle' then ok,message=c.battle.beginEncounter(r.saveData.encounters[tostring(r.saveData.location)])
        else ok=true end
        c.save()
        return ok~=false,message or (ok==false and 'Activity unavailable. Check supplies and retry.' or 'Activity started.')
    end
    return self
end
return Debug
