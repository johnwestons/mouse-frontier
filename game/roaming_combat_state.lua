-- At most one recent accepted field swing per actor. New projections display
-- these facts without rerunning RNG, weapon wear, rewards or scene changes.
local P=require('game.net.protocol')
local Areas=require('game.expedition_areas')
local Players=require('game.coop_players')
local State={}
local fields={serial=true,epoch=true,areaId=true,actorId=true,x=true,y=true,weapon=true,duration=true,facing=true,
    damage=true,dead=true,shellBroken=true,mobId=true,hitId=true,state=true,timer=true,staggerCooldown=true,message=true,alerts=true}
local states={patrol=true,alert=true,chase=true,windup=true,recover=true,stagger=true}
function State.point(n) return type(n)=='number' and n==n and n>=-100000 and n<=100000 end
function State.validCue(data,cue)
    if type(data.coop)~='table' or not P.integer(data.coop.sceneEpoch,1,2147483647)
        or not P.fields(cue,fields) or not P.integer(cue.serial,1,2147483647) or not P.integer(cue.epoch,1,data.coop.sceneEpoch)
        or not Players.get(data,cue.actorId) or not P.text(cue.areaId,64) or not data.expeditions or not data.expeditions[cue.areaId]
        or not State.point(cue.x) or not State.point(cue.y) or not P.text(cue.weapon,128) or not P.clock(cue.duration) or cue.duration>1
        or (cue.facing~=1 and cue.facing~=-1) or not P.integer(cue.damage,0,1000000) or type(cue.dead)~='boolean'
        or type(cue.shellBroken)~='boolean' or not P.text(cue.message,512) or type(cue.alerts)~='table' then return false end
    local area=data.expeditions[cue.areaId]
    if type(area)~='table' or type(area.mobs)~='table' then return false end
    local count=0; local seen={}
    for index,id in pairs(cue.alerts) do
        if not P.integer(index,1,64) or not P.text(id,64) or seen[id] or not area.mobs[id]
            or not Areas.mobDefinition(cue.areaId,id) then return false end
        count=count+1; seen[id]=true
    end
    if count~=#cue.alerts then return false end
    if cue.mobId then
        local mob=area.mobs[cue.mobId]
        local definition=Areas.mobDefinition(cue.areaId,cue.mobId)
        return P.text(cue.mobId,64) and definition~=nil and type(mob)=='table' and cue.hitId==mob.entityId
            and P.text(cue.hitId,32)
            and states[cue.state]==true and P.clock(cue.timer) and cue.timer<=2 and P.clock(cue.staggerCooldown) and cue.staggerCooldown<=2
            and cue.damage>=1
            and not (cue.dead and cue.shellBroken) and (not cue.shellBroken or definition.boss==true)
    end
    return cue.hitId==nil and cue.state==nil and cue.timer==nil and cue.staggerCooldown==nil
        and cue.damage==0 and not cue.dead and not cue.shellBroken
end
function State.validate(data)
    local s=data.roamingCombat
    if s==nil then return true end
    if not P.fields(s,{version=true,serial=true,actors=true}) or s.version~=1
        or not P.integer(s.serial,1,2147483647) or not P.fields(s.actors,{host=true,companion=true}) then return false end
    local count=0; local seen={}
    for id,cue in pairs(s.actors) do
        if type(cue)~='table' or cue.actorId~=id or not State.validCue(data,cue) or cue.serial>s.serial or seen[cue.serial] then return false end
        count=count+1; seen[cue.serial]=true
    end
    return count>0 and seen[s.serial]==true
end
return State
