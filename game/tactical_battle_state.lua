-- Tactical battles retain their board, roster and result until host dismissal.
local P=require('game.net.protocol')
local Grid=require('game.battle_grid')
local Actors=require('game.battle_actors')
local Expedition=require('game.coop_expedition_battles')
local State={VERSION=1}
local function dense(values,maximum)
    if type(values)~='table' then return nil end
    local count=0
    for key in pairs(values) do if not P.integer(key,1,maximum) then return nil end; count=count+1 end
    if count~=#values then return nil end
    return count
end
local function number(value,low,high) return type(value)=='number' and value==value and value>=low and value<=high end
function State.pending(data)
    local state=data.tacticalBattle
    if state==nil then return nil end
    if not P.fields(state,{version=true,location=true,encounterId=true,revision=true,battle=true}) or state.version~=State.VERSION
        or state.location~=data.location or not P.text(state.encounterId,32) or not P.integer(state.revision,0,2147483647)
        or type(state.battle)~='table' then return nil,'invalid tactical battle checkpoint' end
    local b=state.battle; local e=data.encounters and data.encounters[tostring(data.location)]
    if type(b.encounter)~='table' or b.encounter.entityId~=state.encounterId
        or b.encounter.source~='expedition' and (not e or e.entityId~=state.encounterId)
        or data.expeditionBattle or data.events and data.events.current
        or data.coop and data.coop.journey then return nil,'invalid tactical encounter' end
    local count=dense(b.units,32)
    if not count or count<2 or not P.integer(b.active,1,count) or not P.integer(b.round,1,2147483647)
        or not ({select=true,action=true,target=true,move=true})[b.phase] or not P.text(b.message,2048)
        or not P.text(b.objective,256) or type(b.abilitiesUsed)~='table' or not dense(b.log,4096)
        or b.finished~=nil and b.finished~='win' and b.finished~='loss' then return nil,'invalid tactical turn' end
    local ids,players,spaces={},{},{}; local enemies=0
    for _,u in ipairs(b.units) do
        if type(u)~='table' or not P.text(u.id,64) or ids[u.id] or not P.text(u.file,128) or not P.text(u.name,256)
            or not ({ally=true,enemy=true})[u.team] or not P.integer(u.q,0,Grid.COLS) or not P.integer(u.r,1,Grid.ROWS)
            or not number(u.maxHP,1,1e9) or not number(u.hp,0,u.maxHP)
            or not number(u.move,-1e6,1e6) or not number(u.armor,-1e6,1e6) or not number(u.aim,-1e6,1e6) then return nil,'invalid tactical unit' end
        ids[u.id]=true
        local owner=Actors.id(u)
        if u.actorId~=nil and not owner then return nil,'invalid tactical owner' end
        if owner then
            local actor=data.players and data.players[owner]
            if u.team~='ally' or not actor or actor.character~=u.file or players[owner] then return nil,'invalid tactical owner' end
            players[owner]=true
        elseif u.team=='enemy' then enemies=enemies+1 end
        if u.hp>0 then local key=u.q..':'..u.r; if spaces[key] then return nil,'overlapping tactical units' end; spaces[key]=true end
    end
    if not players.host or enemies<1 then return nil,'incomplete tactical roster' end
    if b.pendingActorId~=nil and (b.pendingActorId~='companion' or players.companion or not data.players.companion
        or b.finished or count>=32) then return nil,'invalid pending tactical actor' end
    if b.encounter.source=='expedition' and not Expedition.validate(data,b,state.encounterId) then return nil,'invalid expedition tactical encounter' end
    for _,name in ipairs({'tiles','tileVariants'}) do
        local tiles=b[name]
        if type(tiles)~='table' then return nil,'missing tactical board' end
        for q=0,Grid.COLS do
            if dense(tiles[q],Grid.ROWS)~=Grid.ROWS then return nil,'invalid tactical board' end
            for r=1,Grid.ROWS do if not P.integer(tiles[q][r],1,name=='tiles' and 6 or 3) then return nil,'invalid tactical terrain' end end
        end
        for q in pairs(tiles) do if not P.integer(q,0,Grid.COLS) then return nil,'invalid tactical board' end end
    end
    if type(b.obstacles)~='table' then return nil,'missing tactical obstacles' end
    for key,o in pairs(b.obstacles) do
        if not P.fields(o,{q=true,r=true,kind=true}) or not P.integer(o.q,0,Grid.COLS) or not P.integer(o.r,1,Grid.ROWS)
            or key~=o.q..':'..o.r or not Grid.obstacleProfiles[o.kind] then return nil,'invalid tactical obstacle' end
    end
    return b
end
function State.validate(data)
    local _,reason=State.pending(data); return reason==nil
end
function State.queueCompanion(data)
    local s=data.tacticalBattle; if not s or s.battle.finished then return false end
    for _,unit in ipairs(s.battle.units) do if Actors.id(unit)=='companion' then return false end end
    if s.battle.pendingActorId=='companion' then return false end
    s.battle.pendingActorId='companion'; s.revision=s.revision+1
    return true
end
function State.capture(data,battle)
    if not battle then return false end
    local e=battle.encounter.source=='expedition' and battle.encounter or data.encounters[tostring(data.location)]
    if not e or e.entityId~=battle.encounter.entityId then return false end
    local revision=data.tacticalBattle and data.tacticalBattle.revision or 0
    battle.encounter=e
    data.tacticalBattle={version=State.VERSION,location=data.location,encounterId=e.entityId,revision=revision,battle=battle}
    return true
end
function State.restore(data,catalog)
    local b,reason=State.pending(data); if not b then return nil,reason end
    if b.encounter.source~='expedition' then b.encounter=data.encounters[tostring(data.location)] end
    require('game.battle_weapon_ownership').restore(data,b,catalog)
    return b
end
-- Adopt the prior single-player checkpoint before its finished-result recovery
-- can leave the scene. The copy keeps failed conversion from modifying a save.
function State.importLegacy(data)
    if data.tacticalBattle or not data.expeditionBattle then return false end
    local original,reason=require('game.expedition_battle_state').pending(data)
    if not original then return false,reason end
    local candidate,copyError=require('game.save_schema').copy(data)
    if not candidate then return false,copyError end
    local b=candidate.expeditionBattle.battle; local e=b.encounter
    local Areas=require('game.expedition_areas'); local definition=Areas.definition(e.areaId)
    local area=candidate.expeditions[e.areaId]
    if not definition or definition.stop~=candidate.location or not area then return false,'invalid legacy expedition area' end
    e.enemyStates={}; e.mobFiles={}
    for _,unit in ipairs(b.units) do
        if unit.team=='enemy' then
            local mob=Areas.mobDefinition(e.areaId,unit.mobId); local saved=mob and area.mobs[unit.mobId]
            if not saved or not saved.entityId then return false,'missing legacy enemy identity' end
            e.enemyStates[#e.enemyStates+1]={entityId=saved.entityId,mobId=mob.id,file=mob.file,name=mob.name,
                hp=unit.hp,maxHp=unit.maxHP,tier=mob.tier,boss=mob.boss==true,weapon='mob-claw'}
            e.mobFiles[#e.mobFiles+1]=mob.file
        end
    end
    if not e.enemyStates[1] then return false,'missing legacy enemy' end
    e.entityId=e.enemyStates[1].entityId; e.returnContext.scene=Areas.SCENE
    candidate.expeditionBattle=nil; candidate.scene=Areas.SCENE; candidate.activeExpeditionArea=e.areaId
    State.capture(candidate,b)
    local valid,errorMessage=State.pending(candidate)
    if not valid then return false,errorMessage end
    data.expeditionBattle=nil; data.tacticalBattle=candidate.tacticalBattle
    data.scene=Areas.SCENE; data.activeExpeditionArea=e.areaId
    data.playerX,data.playerY=e.returnContext.x,e.returnContext.y
    Expedition.sync(data,b)
    return true
end
return State
