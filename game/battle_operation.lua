-- Shared crossing rules. Cameras, meshes and device quality never enter here.
local Field=require('game.battle_field')
local Actors=require('game.battle_actors')
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
        if not enemy.alerted then
            for _,ally in ipairs(battle.units)do
                if ally.team=='ally' and ally.hp>0 and distance(enemy,ally)<=9 then enemy.alerted=true;break end
            end
        end
        if enemy.alerted then groups[enemy.pocket or 1]=true end
    end end
    for _,enemy in ipairs(battle.units)do if enemy.team=='enemy' and groups[enemy.pocket or 1]then enemy.alerted=true end end
end
function Operation.active(battle,unit)
    return not battle.field or unit.team~='enemy' or unit.alerted==true
end
function Operation.placeEnemies(field,units,obstacles)
    local used={};for _,u in ipairs(units)do if u.team~='enemy'then used[u.q..':'..u.r]=true end end
    local index=0
    for _,u in ipairs(units)do if u.team=='enemy'then
        index=index+1;local pocket=(index-1)%3+1
        local q=math.floor(field.columns*({.28,.55,.80})[pocket])
        local r=({3,math.floor(Field.route(field,q)+.5),field.rows-2})[pocket]
        if u.boss then q=field.columns-5;r=math.floor(Field.route(field,q)+.5)end
        for offset=0,field.rows-1 do
            local candidate=(r-1+offset)%field.rows+1
            if not used[q..':'..candidate]then r=candidate;break end
        end
        u.q,u.r=q,r;u.pocket=pocket;u.alerted=false
        used[q..':'..r]=true;obstacles[q..':'..r]=nil
    end end
end
return Operation
