-- Tactical battles retain their board, roster and result until host dismissal.
local P=require('game.net.protocol')
local Grid=require('game.battle_grid')
local Actors=require('game.battle_actors')
local Field=require('game.battle_field')
local Operation=require('game.battle_operation')
local Fog=require('game.battle_fog')
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
local function nativeMotion(field,u)
    if u.routeDistance~=nil and not number(u.routeDistance,0,1e9)then return false end
    if u.intentQ~=nil or u.intentR~=nil then
        if not P.integer(u.intentQ,-1,1)or not P.integer(u.intentR,-1,1)or math.abs(u.intentQ)+math.abs(u.intentR)~=1 then return false end
    end
    local m=u.moveAnim;if m==nil then return true end
    if type(m)~='table'or not P.integer(m.fromQ,0,field.columns-1)or not P.integer(m.fromR,1,field.rows)
        or m.toQ~=u.q or m.toR~=u.r or not number(m.duration,.001,10)or not number(m.t,0,m.duration)
        or not number(m.fromDistance or 0,0,1e9)then return false end
    if m.path==nil then return field.version==1 end
    local count=dense(m.path,field.columns*field.rows);if not count or count<2 then return false end
    for i,p in ipairs(m.path)do
        if not P.fields(p,{q=true,r=true})or not P.integer(p.q,0,field.columns-1)or not P.integer(p.r,1,field.rows)then return false end
        local prior=m.path[i-1]
        if prior and(math.abs(p.q-prior.q)+math.abs(p.r-prior.r)~=1 or not Field.traversalCost(field,prior.q,prior.r,p.q,p.r))then return false end
    end
    return m.path[1].q==m.fromQ and m.path[1].r==m.fromR and m.path[count].q==u.q and m.path[count].r==u.r
end
function State.pending(data)
    local state=data.tacticalBattle
    if state==nil then return nil end
    if not P.fields(state,{version=true,location=true,encounterId=true,revision=true,battle=true}) or state.version~=State.VERSION
        or state.location~=data.location or not P.text(state.encounterId,32) or not P.integer(state.revision,0,2147483647)
        or type(state.battle)~='table' then return nil,'invalid tactical battle checkpoint' end
    local b=state.battle; local e=data.encounters and data.encounters[tostring(data.location)]
    if b.field~=nil and not Field.validate(b.field)then return nil,'invalid tactical field' end
    if not Fog.validate(b)then return nil,'invalid tactical fog' end
    local columns,rows=Grid.dimensions(b)
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
            or not ({ally=true,enemy=true})[u.team] or not P.integer(u.q,0,columns) or not P.integer(u.r,1,rows)
            or not number(u.maxHP,1,1e9) or not number(u.hp,0,u.maxHP)
            or not number(u.move,-1e6,1e6) or not number(u.armor,-1e6,1e6) or not number(u.aim,-1e6,1e6) then return nil,'invalid tactical unit' end
        ids[u.id]=true
        if b.field and not nativeMotion(b.field,u)then return nil,'invalid tactical route' end
        if u.alerted~=nil and type(u.alerted)~='boolean' or u.pocket~=nil and not P.integer(u.pocket,1,6)then return nil,'invalid tactical awareness' end
        if u.patrolQ~=nil then
            if not b.field or not P.integer(u.patrolQ,0,columns)or not P.integer(u.patrolR,1,rows)
                or not P.integer(u.patrolIndex,1,4)or not P.integer(u.pocket,1,6)then return nil,'invalid tactical patrol' end
        elseif u.patrolR~=nil or u.patrolIndex~=nil then return nil,'invalid tactical patrol' end
        if u.lastSeenQ~=nil or u.lastSeenR~=nil or u.searchUntil~=nil then
            if not u.patrolQ or not P.integer(u.lastSeenQ,0,columns)or not P.integer(u.lastSeenR,1,rows)
                or not P.integer(u.searchUntil,1,2147483647)then return nil,'invalid tactical search' end
        end
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
        for q=0,columns do
            if dense(tiles[q],rows)~=rows then return nil,'invalid tactical board' end
            for r=1,rows do if not P.integer(tiles[q][r],1,name=='tiles' and(b.field and 1 or 6)or 3) then return nil,'invalid tactical terrain' end end
        end
        for q in pairs(tiles) do if not P.integer(q,0,columns) then return nil,'invalid tactical board' end end
    end
    if b.patrolRound~=nil and not P.integer(b.patrolRound,1,b.round)then return nil,'invalid tactical patrol round' end
    if type(b.obstacles)~='table' then return nil,'missing tactical obstacles' end
    for key,o in pairs(b.obstacles) do
        if not P.fields(o,{q=true,r=true,kind=true}) or not P.integer(o.q,0,columns) or not P.integer(o.r,1,rows)
            or key~=o.q..':'..o.r or not Grid.obstacleProfiles[o.kind] then return nil,'invalid tactical obstacle' end
    end
    if b.field and Field.playableCount(b.field,b.obstacles)<Field.minimumPlayable(b.field)then return nil,'insufficient tactical spaces' end
    if b.crossingComplete~=nil and (not b.field or b.crossingComplete~=true or b.finished~='win')then return nil,'invalid extraction receipt' end
    if b.field and b.finished=='win' and (not b.crossingComplete or not Operation.ready(b))then return nil,'incomplete extraction' end
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
