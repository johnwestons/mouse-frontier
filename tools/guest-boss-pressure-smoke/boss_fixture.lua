-- Read-only test pilot and checkpoint comparisons. Initial owned kit is the
-- only grant; all native combat thereafter uses original rules and controls.
local Codec=require('game.net.codec')
local Players=require('game.coop_players'); local Progression=require('game.player_progression')
local Items=require('game.item_instances'); local Balance=require('game.combat_balance')
local Rules=require('game.battle_rules'); local Weapons=require('game.battle_weapon_ownership')
local Actors=require('game.battle_actors')
local GameState=require('game.net.game_state'); local Ownership=require('game.replica_ownership')
local Fixture={STOP=35,LEVEL=8,AMMO=60}
local limits={maxBytes=524288,maxDepth=20,maxEntries=16384,maxStringBytes=8192}
function Fixture.encode(value)
    local function map(v)
        if type(v)~='table' then return v end
        local result={}; for key,item in pairs(v) do result[type(key)..':'..tostring(key)]=map(item) end
        return result
    end
    return assert(Codec.encode(map(value),limits))
end
function Fixture.metrics(bytes)
    if type(bytes)~='string' or #bytes==0 then return nil end
    local value=Codec.decode(bytes,{maxBytes=1024,maxDepth=4,maxEntries=16,maxStringBytes=32})
    if type(value)~='table' then return nil end
    local function integer(v,maximum)
        return type(v)=='number' and v==v and v==math.floor(v) and v>=0 and v<=maximum
    end
    if not integer(value.incoming,1000000) then return nil end
    for key in pairs(value) do if key~='incoming' and key~='shots' and key~='heals' and key~='moves' then return nil end end
    for key,maximum in pairs({shots=Fixture.AMMO,heals=256,moves=1000000}) do
        local actors=value[key]; if type(actors)~='table' then return nil end
        for id in pairs(actors) do if id~='host' and id~='companion' then return nil end end
        if not integer(actors.host,maximum) or not integer(actors.companion,maximum) then return nil end
    end
    return value
end
function Fixture.adoptMetrics(bytes,previous)
    local value=Fixture.metrics(bytes)
    if not value then return previous end
    if previous then
        if value.incoming<previous.incoming then return previous end
        for _,key in ipairs({'shots','heals','moves'}) do for _,id in ipairs({'host','companion'}) do
            if value[key][id]<previous[key][id] then return previous end
        end end
    end
    return value
end
function Fixture.kit(data,id,catalog,wounded)
    local actor=Players.forActor(data,id)
    while actor.stats.level<Fixture.LEVEL do
        Progression.gainExperience(actor,Progression.requirement(actor.stats.level)-actor.stats.xp)
    end
    Items.write(actor,nil,{kind='equipment',index=2},'frontier-556-carbine'); actor.ammo['556']=Fixture.AMMO
    local first=id=='host' and 3 or 1
    for offset,name in ipairs({'field-bandage-roll','frontier-medkit','frontier-medkit'}) do
        Items.write(actor,nil,{kind='inventory',index=first+offset-1},name)
    end
    if wounded then actor.health=actor.maxHealth-8 end
    assert(Items.ensure(data),'canonical owned kit failed')
end
function Fixture.normalRoster(data)
    local b=assert(data.tacticalBattle).battle; local e=b.encounter
    assert(data.location==Fixture.STOP and e.boss==true and e.tier==Balance.tierFor(Fixture.STOP),'not production Stop35 boss')
    local profile=Balance.enemyProfile(Fixture.STOP,e.tier); local enemies,bosses=0,0
    for _,u in ipairs(b.units) do
        assert(not u.perfectAccuracy,'fixture cannot use perfect accuracy')
        if u.team=='enemy' then
            enemies=enemies+1; if u.boss then bosses=bosses+1 end
            local hp=u.boss and math.floor(profile.maxHP*1.55) or profile.maxHP
            assert(u.maxHP==hp and u.hp==hp and u.armor==profile.armor+(u.boss and 1 or 0)
                and u.aim==profile.aim+(u.boss and 1 or 0) and u.move==profile.move,'boss roster was shortened or modified')
        end
    end
    assert(enemies>=1 and enemies<=3 and bosses==1,'original rolled boss roster missing')
    return enemies
end
function Fixture.quiet(b)
    if not b or b.intro or b.projectile or (b.attackTimer or 0)>0 or (b.enemyDelay or 0)>0 then return false end
    for _,u in ipairs(b.units) do if u.moveAnim or (u.actionTimer or 0)>0 or (u.hitTimer or 0)>0 then return false end end
    return true
end
function Fixture.ownership(actor)
    return {id=actor.id,character=actor.character,health=actor.health,maxHealth=actor.maxHealth,stats=actor.stats,
        inventory=actor.inventory,equipment=actor.equipment,itemSlots=actor.itemSlots,ammo=actor.ammo,
        weaponProficiency=actor.weaponProficiency,weaponDurability=actor.weaponDurability}
end
function Fixture.publicState(data)
    local s=data.tacticalBattle; local b=s and s.battle; local units={}
    for _,u in ipairs(b and b.units or {}) do
        local copy={}; for _,key in ipairs({'id','actorId','team','file','weapon','q','r','hp','maxHP','armor','aim','move',
            'boss','guarding','regenRounds','regenAmount','armorBonus','armorBonusRounds','aimBonus','aimBonusRounds',
            'moveBonus','moveBonusRounds','bleedRounds','bleedDamage','staggeredRounds'}) do copy[key]=u[key] end
        units[#units+1]=copy
    end
    return {epoch=data.coop.sceneEpoch,scene=data.scene,location=data.location,encounter=data.encounters[tostring(Fixture.STOP)],
        battle=b and {encounterId=s.encounterId,revision=s.revision,active=b.active,round=b.round,phase=b.phase,
            finished=b.finished,moveUsed=b.moveUsed,chosenWeapon=b.chosenWeapon,chosenItemId=b.chosenItemId,
            units=units,field=b.field,fog=b.fog,tiles=b.tiles,tileVariants=b.tileVariants,obstacles=b.obstacles,abilitiesUsed=b.abilitiesUsed},
        host=Fixture.ownership(data.players.host),guest=Fixture.ownership(data.players.companion),
        scrap=data.scrap,goodwill=data.goodwill,resources=data.resources,droppedItems=data.droppedItems}
end
function Fixture.publicSignature(data)
    -- Checkpoint expectations use the real wire projection, including its
    -- numeric/ownership encoding. Replica data must never be projected again.
    local public=Ownership.isReplica(data) and data or assert(GameState.project(data)).view
    return Fixture.encode(Fixture.publicState(public))
end
function Fixture.privateSignature(data)
    return Fixture.encode({state=Fixture.publicState(data),players=data.players,campaignId=data.coop.network.campaignId,
        companionId=data.coop.network.companionId,rng=data.coop.randomState})
end
function Fixture.ready(lp)
    local v=lp.clientView; local f=lp.motionFrame; local replica=lp.replica and lp.replica.data
    local runtime=v and v.runtime; local data=runtime and runtime.saveData
    return lp.network and lp.network.status=='ready' and v and v.ready and v.focused~=false
        and not lp.menuOpen and replica and data and f and f.ready
        and replica.coop.sceneEpoch==v.epoch and data.coop.sceneEpoch==v.epoch
        and runtime.scene==data.scene and runtime.scene==replica.scene and data.location==replica.location
        and f.sessionId==lp.network.sessionId and f.sceneEpoch==v.epoch and f.motionId==v.motionId
        and f.serial==v.lastSerial and f.domain==v.modalDomain
        -- Tactical combat intentionally prohibits walking. Its acknowledged
        -- frame is still valid; ordinary return must prove unpaused motion.
        and (not f.paused or data.tacticalBattle~=nil)
end
function Fixture.rejoinAction(lp,expected,controls)
    if not expected then return 'wait' end
    if lp.network then
        -- An automatic reconnect can have a transport before its session ID
        -- arrives. Preserve that real attempt through approval/baseline/ack.
        if lp.network.sessionId==expected or lp.network.status~='ready' then return 'wait' end
        return 'leave'
    end
    local reconnect=lp.reconnectStatus and lp:reconnectStatus()
    if reconnect and reconnect.active then return 'cancelReconnect' end
    if lp.phase=='idle' and lp.menuOpen and controls and controls.join and controls.join.enabled~=false then return 'join' end
    return 'wait'
end
function Fixture.plan(data,b,id,catalog,pressure,needsHeal,needsMove)
    local u=Rules.activeUnit(b); if not u or Actors.id(u)~=id or not Fixture.quiet(b) or b.finished then return nil end
    local actor=Actors.data(data,u)
    if (needsHeal or u.hp<=u.maxHP-8) and u.hp<u.maxHP then
        for _,name in pairs(actor.inventory) do
            local effect=catalog.itemEffects[name]
            if effect and effect.health and not effect.potion then return {kind='heal'} end
        end
    end
    -- Large operations start outside combat. Advance through unexplored ground
    -- until there is a visible threat before waiting for real incoming damage.
    local nearest
    for _,enemy in ipairs(b.units) do if enemy.team=='enemy' and enemy.hp>0
        and require('game.battle_fog').unitVisible(b,enemy)
        and (not nearest or Rules.distance(u,enemy)<Rules.distance(u,nearest)) then nearest=enemy end end
    if not nearest then
        if not b.field then return nil end
        if not b.moveUsed and b.phase~='action'and b.phase~='target'then
            local budget=require('game.battle_grid').moveBudget(b,u)
            local Field=require('game.battle_field');local Fog=require('game.battle_fog');local f=b.field
            local center=math.floor(f.columns*.55);local east=f.columns-5
            local waypoints={{q=math.floor(f.columns*.28),r=3},{q=center,r=math.floor(Field.route(f,center)+.5)},
                {q=math.floor(f.columns*.8),r=f.rows-2},{q=east,r=math.floor(Field.route(f,east)+.5)}}
            local goal={q=f.exitColumn,r=u.r}
            for _,p in ipairs(waypoints)do if not Fog.explored(b,p.q,p.r)then goal=p;break end end
            local point=Rules.bestAdvance(b,u,goal,budget,0)
            if point and Rules.canMove(b,u,point.q,point.r,budget)then return{kind='move',q=point.q,r=point.r}end
        end
        return{kind='endTurn'}
    end
    if not pressure then return {kind='guard'} end
    if needsMove and not b.moveUsed and b.phase~='action' and b.phase~='target' then
        local point=Rules.bestAdvance(b,u,nearest,u.move,1)
        if point and (point.q~=u.q or point.r~=u.r) and Rules.canMove(b,u,point.q,point.r,u.move) then
            return {kind='move',q=point.q,r=point.r}
        end
    end
    if b.phase=='target' then
        local info=Weapons.resolve(data,u,b.chosenItemId or b.chosenWeapon,catalog)
        for _,enemy in ipairs(b.units) do if info and enemy.team=='enemy' and enemy.hp>0
            and require('game.battle_fog').unitVisible(b,enemy)and Rules.distance(u,enemy)<=Rules.weaponRange(catalog,info.name) and Rules.lineOfSight(b,u,enemy) then
            return {kind='target',q=enemy.q,r=enemy.r} end end
        return nil -- Wait; never manufacture a target or edit the turn.
    end
    local best,power
    for index,selector in ipairs(Weapons.options(data,u,catalog)) do
        local info=Weapons.resolve(data,u,selector,catalog); local combat=info and catalog.weaponCombat[info.name]
        if info and info.durability>0 and (not combat.ammo or (actor.ammo[combat.ammo] or 0)>0) then
            for _,enemy in ipairs(b.units) do if enemy.team=='enemy' and enemy.hp>0
                and require('game.battle_fog').unitVisible(b,enemy)and Rules.distance(u,enemy)<=Rules.weaponRange(catalog,info.name)
                and (combat.kind~='ranged' or Rules.lineOfSight(b,u,enemy)) then
                local maximum=catalog.weaponStats[info.name].max
                if not power or maximum>power then best,power=index,maximum end
            end end
        end
    end
    if best then return {kind='weapon',index=best} end
    if not b.moveUsed and b.phase~='action' then
        local point=Rules.bestAdvance(b,u,nearest,u.move,1)
        if point and (point.q~=u.q or point.r~=u.r) and Rules.canMove(b,u,point.q,point.r,u.move) then return {kind='move',q=point.q,r=point.r} end
    end
    return {kind='endTurn'}
end
return Fixture
