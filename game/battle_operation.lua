-- Shared crossing rules. Cameras, meshes and device quality never enter here.
local Field=require('game.battle_field')
local Actors=require('game.battle_actors')
local Grid=require('game.battle_grid')
local Motion=require('game.battle_motion')
local Operation={}
local function distance(a,b)return math.abs(a.q-b.q)+math.abs(a.r-b.r)end
function Operation.hasLivingPlayer(battle)
    for _,u in ipairs(Actors.units(battle))do if u.hp>0 then return true end end
    return false
end
function Operation.ready(battle)
    if not battle.field then return false end
    local count=0
    for _,u in ipairs(Actors.units(battle))do if u.hp>0 then
        count=count+1;if not Field.isExit(battle.field,u.q,u.r)then return false end
    end end
    if count==0 then return false end
    for _,u in ipairs(battle.units)do if u.team=='enemy' and u.hp>0
        and (battle.encounter.defenseBattle or u.boss)then return false end end
    return true
end
function Operation.complete(battle)
    local used={};for _,u in ipairs(battle.units)do if u.hp>0 and u.q==battle.field.exitColumn then used[u.r]=true end end
    for _,u in ipairs(Actors.units(battle))do if u.hp<=0 then
        u.moveAnim=nil
        for r=1,battle.field.rows do if not used[r]then u.q,u.r=battle.field.exitColumn,r;used[r]=true;break end end
    end end
    battle.crossingComplete=true
end
function Operation.awaken(battle)
    if not battle.field then return end
    local groups={}
    for _,enemy in ipairs(battle.units)do if enemy.team=='enemy' and enemy.hp>0 then
        if enemy.patrolQ then
            local target=Operation.seen(battle,enemy)
            if target then Operation.track(battle,enemy.pocket,target)end
        elseif not enemy.alerted then
            for _,ally in ipairs(battle.units)do
                if ally.team=='ally' and ally.hp>0 and distance(enemy,ally)<=9 then enemy.alerted=true;break end
            end
        end
        if enemy.alerted and not enemy.patrolQ then groups[enemy.pocket or 1]=true end
    end end
    for _,enemy in ipairs(battle.units)do if enemy.team=='enemy' and groups[enemy.pocket or 1]then enemy.alerted=true end end
    -- Only two groups pursue at once. Others retain local patrols.
    local candidates={}
    for _,enemy in ipairs(battle.units)do if enemy.team=='enemy'and enemy.hp>0 and enemy.patrolQ then
        enemy.alerted=false
        if enemy.searchUntil and enemy.searchUntil>=battle.round and enemy.lastSeenQ then
            local d=distance(enemy,{q=enemy.lastSeenQ,r=enemy.lastSeenR})
            candidates[enemy.pocket]=math.min(candidates[enemy.pocket]or math.huge,d)
        end
    end end
    local order={};for pocket,d in pairs(candidates)do order[#order+1]={pocket=pocket,distance=d}end
    table.sort(order,function(a,b)return a.distance==b.distance and a.pocket<b.pocket or a.distance<b.distance end)
    local active={};for i=1,math.min(2,#order)do active[order[i].pocket]=true end
    for _,enemy in ipairs(battle.units)do if enemy.patrolQ then enemy.alerted=active[enemy.pocket]==true end end
end
function Operation.seen(battle,enemy)
    local target
    for _,ally in ipairs(battle.units)do if ally.team=='ally'and ally.hp>0 then
        local d=distance(enemy,ally)
        if (d<=3 or d<=9 and Grid.lineOfSight(battle,enemy,ally))and(not target or d<distance(enemy,target))then target=ally end
    end end
    return target
end
function Operation.track(battle,pocket,target)
    for _,enemy in ipairs(battle.units)do if enemy.team=='enemy'and enemy.patrolQ and enemy.pocket==pocket
        and(not enemy.boss or distance(enemy,target)<=12)then
        enemy.lastSeenQ,enemy.lastSeenR=target.q,target.r;enemy.searchUntil=battle.round+3
    end end
end
function Operation.noise(battle,actor,radius)
    if not battle.field then return end
    for _,enemy in ipairs(battle.units)do
        if enemy.team=='enemy'and enemy.hp>0 and enemy.patrolQ and distance(enemy,actor)<=radius then Operation.track(battle,enemy.pocket,actor)end
    end
    Operation.awaken(battle)
end
function Operation.target(battle,enemy)
    if not enemy.patrolQ then
        local target;for _,u in ipairs(battle.units)do if u.team=='ally'and u.hp>0 and(not target or distance(enemy,u)<distance(enemy,target))then target=u end end
        return target
    end
    local target=Operation.seen(battle,enemy);if target then return target end
    if enemy.searchUntil and enemy.searchUntil>=battle.round and enemy.lastSeenQ then return {q=enemy.lastSeenQ,r=enemy.lastSeenR,remembered=true}end
end
function Operation.patrol(battle)
    if not battle.field or battle.patrolRound==battle.round then return end
    battle.patrolRound=battle.round;Operation.awaken(battle)
    local offsets={{-3,-4},{3,-4},{3,4},{-3,4}}
    for _,u in ipairs(battle.units)do if u.patrolQ and u.hp>0 and not u.alerted and not u.boss
        and (u.sleepRounds or 0)==0 and (u.paralyzedRounds or 0)==0 and (u.snaredRounds or 0)==0 then
        local i=u.patrolIndex or 1;local o=offsets[i]
        local target={q=u.patrolQ+o[1],r=math.max(2,math.min(battle.field.rows-1,u.patrolR+o[2]))}
        if distance(u,target)<=1 then i=i%4+1;u.patrolIndex=i;o=offsets[i];target={q=u.patrolQ+o[1],r=math.max(2,math.min(battle.field.rows-1,u.patrolR+o[2]))}end
        local reachable=Grid.reachable(battle,u,2);local best,score
        for _,p in pairs(reachable)do
            local d=distance(p,target)
            if not score or d<score or d==score and(p.q<best.q or p.q==best.q and p.r<best.r)then best,score=p,d end
        end
        if best and(best.q~=u.q or best.r~=u.r)then
            local path=Grid.path(battle,u,best.q,best.r,2,reachable)
            u.moveAnim={fromQ=u.q,fromR=u.r,toQ=best.q,toR=best.r,path=path,fromDistance=u.routeDistance or 0,t=0,duration=.28*(#path-1)}
            local previous=path[#path-1];u.intentQ,u.intentR=best.q-previous.q,best.r-previous.r
            u.routeDistance=(u.routeDistance or 0)+Motion.routeLength(battle.field,path);u.q,u.r=best.q,best.r
        end
    end end
    Operation.awaken(battle)
end
function Operation.active(battle,unit)
    return not battle.field or unit.team~='enemy' or unit.alerted==true
end
function Operation.placeEnemies(field,units,obstacles,populated)
    local used={};for _,u in ipairs(units)do if u.team~='enemy'then used[u.q..':'..u.r]=true end end
    local index=0
    for _,u in ipairs(units)do if u.team=='enemy'then
        index=index+1;local pocket=(index-1)%(populated and 6 or 3)+1;local base=(pocket-1)%3+1
        local q=math.floor(field.columns*({.28,.55,.80})[base])
        local r=({3,math.floor(Field.route(field,q)+.5),field.rows-2})[base]
        if populated then q=({12,20,32,40,54,62})[pocket]+math.floor((index-1)/6);r=({5,20,35,20,5,35})[pocket]end
        if u.boss then q=field.columns-5;r=math.floor(Field.route(field,q)+.5);if populated then pocket=6 end end
        for offset=0,field.rows-1 do
            local candidate=(r-1+offset)%field.rows+1
            if not used[q..':'..candidate]and not obstacles[q..':'..candidate]then r=candidate;break end
        end
        u.q,u.r=q,r;u.pocket=pocket;u.alerted=false
        if populated then u.patrolQ,u.patrolR=q,r;u.patrolIndex=(index-1)%4+1 end
        used[q..':'..r]=true;obstacles[q..':'..r]=nil
    end end
end
return Operation
