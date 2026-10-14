-- Both peers use one saved tactical model; only host commands change scenes.
local State=require('game.tactical_battle_state')
local Actors=require('game.battle_actors')
local Players=require('game.coop_players')
local Party=require('game.party_scene')
local Random=require('game.coop_random')
local P=require('game.net.protocol')
local Controller=require('game.battle_controller')
local Rules=require('game.battle_rules')
local Grid=require('game.battle_grid')
local Weapons=require('game.battle_weapon_ownership')
local Inventory=require('game.inventory')
local Contract=require('game.coop_item_contract')
local Expedition=require('game.coop_expedition_battles')
local Commands={}
function Commands.scopes(data)
    local s=data.tacticalBattle
    local e=s and s.battle.encounter
    local entity=e and e.source=='expedition' and data.expeditions[e.areaId].entityId
        or data.scene=='expedition' and data.expeditions[data.activeExpeditionArea].entityId
        or s and s.encounterId or data.encounters[tostring(data.location)].entityId
    local result={'party','world:scene','combat:tactical','entity:'..entity,
        'rng','resources','player:host','world:rewardDelivery'}
    if data.players.companion then result[#result+1]='player:companion' end
    if data.roamingEncounter then result[#result+1]='combat:roaming' end
    for _,item in ipairs(data.droppedItems or {}) do
        if item.name=='mailbox-reward' and item.scene=='train' then result[#result+1]='entity:'..item.entityId; break end
    end
    for i,p in ipairs(data.passengers or {}) do if i<=2 then result[#result+1]='entity:'..p.entityId end end
    return result
end
local function positions(data)
    local result={}
    for _,id in ipairs({'host','companion'}) do
        local actor=Players.get(data,id)
        if actor then result[id]={x=actor.playerX,y=actor.playerY,carIndex=actor.activeCar,facing=actor.playerFacing or 1} end
    end
    return result
end
local function controller(data,battle,catalog,t)
    return {battle=battle,saveData=data,Catalog=catalog,Util=require('game.util'),BattleRules=Rules,BattleGrid=Grid,
        CombatBalance=require('game.combat_balance'),TrainUpgradeBalance=require('game.train_upgrade_balance'),
        PlayerProgression=require('game.player_progression'),Events=require('game.events'),BOARD_COLS=Grid.COLS,BOARD_ROWS=Grid.ROWS,
        rng=Random.generator(data,t.randomSeed),writeSave=function() end,playSfx=function() end,weaponSfx=function() end}
end
local function busy(b)
    if b.intro~=nil or (b.attackTimer or 0)>0 or (b.enemyDelay or 0)>0 or b.projectile then return true end
    for _,u in ipairs(b.units) do if (u.actionTimer or 0)>0 or (u.hitTimer or 0)>0 or u.moveAnim then return true end end
    return false
end
function Commands.install(authority,context)
    local function hostSurface(data,screen)
        local host=context.actorState('host')
        return host and host.screen==screen and host.scene==data.scene and not host.traveling and not host.changingCar
    end
    authority:register('battle.begin',function(data,id,args,t)
        if not P.fields(args,{encounterId=true,enemyIds=true}) or not P.text(args.encounterId,32) then return nil,'invalid_args' end
        local e=data.encounters[tostring(data.location)]
        local host=context.actorState('host')
        if not hostSurface(data,'game') or host.encounterActive or host.activityBlocked or data.health<=0
            or data.tacticalBattle or data.expeditionBattle or data.events.current or data.coop.journey then return nil,'battle_unavailable' end
        if data.scene=='expedition' then
            local reason; e,reason=Expedition.entry(data,host,args); if not e then return nil,reason end
        elseif args.enemyIds~=nil then return nil,'invalid_args'
        elseif not e or e.entityId~=args.encounterId or not e.hasMob or e.resolved or not ({train=true,stop=true})[data.scene] then return nil,'battle_unavailable' end
        return {scopes=Commands.scopes(data),apply=function()
            data.roamingEncounter=nil
            local c=controller(data,nil,context.catalog,t)
            c.actorIds=authority.bindings.companion~=nil and {'host','companion'} or {'host'}
            local b=Controller.begin(c,e)
            if not State.capture(data,b) then return nil,'battle_unavailable' end
            local result,reason=Party.commit(data,t,positions(data),'battle'); if not result then return nil,reason end
            result.encounterId=e.entityId; result.battleSource=e.source; return result
        end}
    end)
    local common={encounterId=true,turnRevision=true,unitId=true}
    local function prepare(data,id,args,extra,enemy)
        local allowed={}; for key in pairs(common) do allowed[key]=true end; for key in pairs(extra or {}) do allowed[key]=true end
        if not P.fields(args,allowed) or not P.text(args.encounterId,32) or not P.text(args.unitId,64)
            or not P.integer(args.turnRevision,0,2147483647) then return nil,'invalid_args' end
        local b=State.restore(data,context.catalog); local s=data.tacticalBattle
        if not b or not hostSurface(data,'battle') or s.encounterId~=args.encounterId then return nil,'battle_unavailable' end
        if s.revision~=args.turnRevision then return nil,'stale_turn' end
        local u=Rules.activeUnit(b)
        if u.id~=args.unitId or u.hp<=0 or b.finished then return nil,'not_your_turn' end
        if enemy then if u.team~='enemy' then return nil,'not_enemy_turn' end
        else
            local owner=Actors.id(u) or 'host'
            local fallback=id=='host' and owner=='companion' and authority.bindings.companion==nil
            if u.team~='ally' or id~=owner and not fallback then return nil,'not_your_turn' end
        end
        if busy(b) then return nil,'battle_busy' end
        if s.revision>=2147483647 then return nil,'turn_revision_exhausted' end
        return b,u
    end
    local function action(name,extra,validate,apply)
        authority:register(name,function(data,id,args,t)
            local b,u=prepare(data,id,args,extra,name=='battle.enemyTurn'); if not b then return nil,u end
            local valid,reason=validate(data,b,u,args); if not valid then return nil,reason end
            return {scopes=Commands.scopes(data),checkpoint=true,apply=function()
                local ok,errorMessage=apply(controller(data,b,context.catalog,t),u,args)
                if ok==false then return nil,errorMessage or 'action_unavailable' end
                Expedition.sync(data,b)
                data.tacticalBattle.revision=data.tacticalBattle.revision+1
                return {ok=true,encounterId=data.tacticalBattle.encounterId,turnRevision=data.tacticalBattle.revision,
                    activeUnit=b.units[b.active].id,finished=b.finished}
            end}
        end)
    end
    local function valid() return true end
    action('battle.move',{q=true,r=true},function(data,b,u,args)
        if not P.integer(args.q,0,Grid.COLS) or not P.integer(args.r,1,Grid.ROWS) then return nil,'invalid_args' end
        if b.moveUsed or b.phase=='action' or b.phase=='target' or not Rules.canMove(b,u,args.q,args.r,u.move) then return nil,'move_unavailable' end
        return true
    end,function(c,u,args) Controller.move(c,args.q,args.r) end)
    action('battle.attack',{weapon=true,targetId=true},function(data,b,u,args)
        if not P.text(args.weapon,64) or args.targetId~=nil and not P.text(args.targetId,64) then return nil,'invalid_args' end
        if not Weapons.resolve(data,u,args.weapon,context.catalog) then return nil,'ownership' end
        if args.targetId then
            local target; for _,unit in ipairs(b.units) do if unit.id==args.targetId then target=unit end end
            if not target or target.team~='enemy' or target.hp<=0 then return nil,'invalid_target' end
        end
        return true
    end,function(c,u,args)
        if not args.targetId then return Controller.attack(c,args.weapon) end
        for _,target in ipairs(c.battle.units) do if target.id==args.targetId then return Controller.resolve(c,u,target,nil,args.weapon) end end
    end)
    action('battle.guard',{},valid,function(c) Controller.guard(c) end)
    action('battle.endTurn',{},valid,function(c) Controller.advance(c) end)
    action('battle.heal',{},function(data,b,u)
        local a=Actors.data(data,u)
        for i=1,a.inventoryCapacity do local e=context.catalog.itemEffects[a.inventory[i]]; if e and e.health then return true end end
        return nil,'no_healing_item'
    end,function(c) return Controller.heal(c) end)
    action('battle.item',{name=true},function(data,b,u,args)
        local effect=P.text(args.name,128) and context.catalog.itemEffects[args.name]
        if not effect or not effect.health and not effect.potion then return nil,'invalid_item' end
        local a=Actors.data(data,u)
        for i=1,a.inventoryCapacity do if a.inventory[i]==args.name then return true end end
        return nil,'item_unavailable'
    end,function(c,u,args) return Controller.useHealingItem(c,args.name) end)
    action('battle.swap',{source=true,sourceItem=true,target=true,targetItem=true},function(data,b,u,args)
        local a=Actors.data(data,u)
        local function ref(value)
            return P.fields(value,{kind=true,index=true}) and P.integer(value.index,1,
                value.kind=='inventory' and a.inventoryCapacity or value.kind=='equipment' and 2 or 0)
        end
        if not ref(args.source) or not ref(args.target) or args.sourceItem==nil or args.targetItem==nil then return nil,'invalid_slot' end
        if not Contract.matches(args.sourceItem,a,nil,args.source) or not Contract.matches(args.targetItem,a,nil,args.target) then return nil,'stale_item' end
        if args.source.kind==args.target.kind and args.source.index==args.target.index then return nil,'same_slot' end
        return true
    end,function(c,u,args)
        local moved,reason=Inventory.move(Actors.data(c.saveData,u),nil,args.source,args.target,
            context.catalog.weaponStats,context.catalog.ammoPickupAmounts,context.catalog.wearableItems)
        if not moved then return false,reason or 'cannot_transfer' end
        -- A selected attack must quote an equipped instance again after a swap.
        c.battle.phase='select'; c.battle.chosenWeapon=nil; c.battle.chosenItemId=nil
        return true
    end)
    action('battle.ability',{kind=true},function(data,b,u,args)
        if args.kind~=context.catalog.characterAbility(u.file).kind then return nil,'invalid_ability' end
        if b.abilitiesUsed[u.id] then return nil,'ability_used' end
        return true
    end,function(c,u,args) Controller.ability(c,args.kind) end)
    action('battle.enemyTurn',{},valid,function(c) Controller.enemyTurn(c) end)
    for _,name in ipairs({'battle.continue','battle.retreat'}) do
        authority:register(name,function(data,id,args,t)
            if not P.fields(args,{encounterId=true,turnRevision=true}) then return nil,'invalid_args' end
            local b=State.pending(data); local s=data.tacticalBattle
            if not b or not hostSurface(data,'battle') or args.encounterId~=s.encounterId then return nil,'battle_unavailable' end
            if args.turnRevision~=s.revision then return nil,'stale_turn' end
            if name=='battle.continue' and not b.finished then return nil,'battle_unfinished' end
            return {scopes=Commands.scopes(data),apply=function()
                local outcome=name=='battle.retreat' and 'retreat' or b.finished
                if b.encounter.source=='expedition' then return Expedition.finish(data,b,context.catalog,outcome,t,context) end
                for _,unit in ipairs(Actors.units(b)) do local actor=Actors.data(data,unit); actor.health=math.max(1,actor.health); actor.battlePotionLootChance=nil end
                data.tacticalBattle=nil
                local result,reason=Party.commit(data,t,positions(data),'game'); if not result then return nil,reason end
                result.outcome=outcome; return result
            end}
        end)
    end
end
return Commands
