-- Public post-action facts only, never a serialized domain result or save.
local P=require('game.net.protocol')
local Sewing=require('game.net.sewing_results')
local Aid=require('game.net.first_aid_results')
local Quests=require('game.net.quest_results')
local Guns=require('game.net.gun_results')
local LastStandAid=require('game.net.last_stand_aid_results')
local LastStandPosition=require('game.net.last_stand_position_results')
local Range=require('game.net.range_results')
local Pose=require('game.net.pose_results')
local Travel=require('game.net.travel_request_results')
local R={}
local fields={
    ['traveler.return']={returned=true,acknowledged=true},
    ['traveler.ack']={returned=true,acknowledged=true},
    ['expedition.survey']={areaId=true,markerId=true,already=true,marked=true,total=true,complete=true},
    ['expedition.cache']={areaId=true,containerId=true,opened=true},
    ['roaming.attack']={serial=true,actorId=true,weapon=true,duration=true,facing=true,damage=true,dead=true,shellBroken=true,hitId=true},
    ['inventory.swap']={moved=true},
    ['inventory.give']={recipient=true,item=true,amount=true},
    ['ammo.give']={recipient=true,item=true,amount=true},
    ['storage.transfer']={moved=true},
    ['mailbox.collect']={item=true,amount=true},
    ['inventory.consume']={item=true,gained=true,heart=true,potion=true},
    ['loot.drop']={item=true,entityId=true},
    ['loot.pickup']={item=true,amount=true,heart=true},
    ['merchant.buy']={item=true,price=true,delivery=true,amount=true},
    ['merchant.sell']={item=true,price=true},
    ['train.fuel']={item=true,gained=true},
    ['train.upgrade']={carId=true,price=true},
    ['train.engineUpgrade']={level=true,price=true},
    ['radio.station']={station=true,rainEnabled=true},
    ['decoration.acquire']={leaseId=true,entityId=true},
    ['decoration.place']={entityId=true},
    ['decoration.collect']={item=true,slot=true},
    ['activity.release']={released=true,leaseId=true},
    ['npc.gift']={item=true,npc=true,equipped=true,tier=true},
    ['passenger.equip']={item=true,npc=true,equipped=true,tier=true},
    ['npc.chatter']={npc=true,lineIndex=true,tier=true},
    ['passenger.chatter']={npc=true,lineIndex=true,tier=true},
    ['maintenance.acquire']={leaseId=true,targetDoses=true,completed=true},
    ['maintenance.step']={success=true,reason=true,targetDoses=true},
    ['maintenance.complete']={success=true,reason=true,before=true,condition=true,cost=true},
    ['weaponRepair.acquire']={leaseId=true,elapsed=true,expiresIn=true},
    ['weaponRepair.step']={leaseId=true,elapsed=true,expiresIn=true},
    ['weaponRepair.complete']={success=true,reason=true,name=true,cost=true,quality=true,restored=true,part=true},
}
local visits={['scene.leaveTrain']=true,['scene.returnTrain']=true,['scene.enterHouse']=true,['scene.exitHouse']=true,
    ['scene.office']=true,['scene.caravan']=true,['scene.expedition']=true}
for command in pairs(visits) do fields[command]={actorId=true,scene=true,sceneRevision=true} end
function R.supports(command) return command=='progression.request' or command=='player.pose' or Range.supports(command) or command=='lastStand.position' or command=='lastStand.aid' or Guns.supports(command) or command=='quest.help' or command=='quest.deliver' or command=='outfit.craft' or command=='firstAid.acquire' or command=='firstAid.step' or command=='firstAid.complete' or fields[command]~=nil end
local function amount(value) return type(value)=='number' and value==value and value>=0 and value<=1e9 end
local function doses(value)
    if not P.fields(value,{[1]=true,[2]=true,[3]=true}) then return false end
    for i,max in ipairs({2,1,2}) do if not P.integer(value[i],0,max) then return false end end
    return true
end
local function lease(value) return P.text(value,32) and value:match('^l[1-9]%d*$')~=nil end
function R.valid(command,value)
    if command=='inventory.give' or command=='ammo.give' then
        return P.fields(value,fields[command]) and (value.recipient=='host' or value.recipient=='companion')
            and P.text(value.item,128) and P.integer(value.amount,1,1000000)
    end
    if visits[command] then return P.fields(value,fields[command]) and (value.actorId=='host' or value.actorId=='companion')
        and ({train=true,stop=true,house=true,caravan=true,expedition=true})[value.scene]==true
        and P.integer(value.sceneRevision,1,2147483647) end
    if command=='progression.request' then return Travel.valid(value)end
    if command=='player.pose' then return Pose.valid(value) end
    if Range.supports(command) then return Range.valid(command,value) end
    if command=='lastStand.position' then return LastStandPosition.valid(value) end
    if command=='lastStand.aid' then return LastStandAid.valid(value) end
    if Guns.supports(command) then return Guns.valid(command,value) end
    if command=='quest.help' or command=='quest.deliver' then return Quests.valid(command,value) end
    if command=='firstAid.acquire' or command=='firstAid.step' or command=='firstAid.complete' then return Aid.valid(command,value) end
    if command=='outfit.craft' then return Sewing.valid(value) end
    local allowed=fields[command]
    if not allowed or not P.fields(value,allowed) then return false end
    if command=='traveler.return' or command=='traveler.ack' then return value.returned==true and type(value.acknowledged)=='boolean' end
    if command=='expedition.cache' then return P.text(value.areaId,64) and P.text(value.containerId,64) and value.opened==true end
    if command=='expedition.survey' then
        return P.text(value.areaId,64) and P.text(value.markerId,64) and type(value.already)=='boolean' and type(value.complete)=='boolean'
            and P.integer(value.total,1,64) and P.integer(value.marked,1,value.total) and value.complete==(value.marked==value.total)
    end
    if command=='roaming.attack' then
        return P.integer(value.serial,1,2147483647) and (value.actorId=='host' or value.actorId=='companion')
            and P.text(value.weapon,128) and P.clock(value.duration) and value.duration<=1 and (value.facing==1 or value.facing==-1)
            and P.integer(value.damage,0,1000000) and type(value.dead)=='boolean' and type(value.shellBroken)=='boolean'
            and (value.hitId==nil and value.damage==0 and not value.dead and not value.shellBroken
                or P.text(value.hitId,32) and value.damage>0)
    end
    if command=='maintenance.acquire' then return lease(value.leaseId) and doses(value.targetDoses) and type(value.completed)=='boolean' end
    if command=='maintenance.step' or command=='maintenance.complete' or command=='weaponRepair.complete' then
        if type(value.success)~='boolean' then return false end
        if not value.success then
            local reasons=command=='maintenance.step' and {unavailable=true,location=true,full=true,oil=true}
                or command=='maintenance.complete' and {already=true,location=true,progress=true,oil=true}
                or {miss=true,ownership=true,ready=true,part=true,scrap=true,precision=true}
            if not reasons[value.reason] then return false end
            for key in pairs(value) do if key~='success' and key~='reason' then return false end end
            return true
        end
        if value.reason~=nil then return false end
        if command=='maintenance.step' then return value.targetDoses==nil or doses(value.targetDoses) end
        if not P.integer(value.cost,1,1e9) then return false end
        if command=='maintenance.complete' then return P.integer(value.before,0,100) and P.integer(value.condition,0,100) end
        return P.text(value.name,128) and P.integer(value.restored,0,100) and (value.quality=='good' or value.quality=='perfect')
            and (value.part==nil or P.text(value.part,128))
    end
    if command=='weaponRepair.acquire' or command=='weaponRepair.step' then
        return lease(value.leaseId) and amount(value.elapsed) and amount(value.expiresIn) and value.expiresIn<=30
    end
    if command=='inventory.swap' or command=='storage.transfer' then return value.moved==true end
    if command=='npc.chatter' or command=='passenger.chatter' then
        return P.text(value.npc,128) and P.integer(value.lineIndex,1,128) and P.text(value.tier,64)
    end
    if command=='npc.gift' or command=='passenger.equip' then
        return P.text(value.item,128) and P.text(value.npc,128) and type(value.equipped)=='boolean' and P.text(value.tier,64)
            and (command~='passenger.equip' or value.equipped==true)
    end
    if command=='radio.station' then return (value.station=='8bit' or value.station=='chill' or value.station=='vibes') and type(value.rainEnabled)=='boolean' end
    if command=='decoration.acquire' or command=='activity.release' then
        return P.text(value.leaseId,32) and value.leaseId:match('^l%d+$')~=nil
            and (command=='activity.release' and value.released==true or command=='decoration.acquire' and P.text(value.entityId,64))
    end
    if command=='decoration.place' then return P.text(value.entityId,64) end
    if command=='train.upgrade' or command=='train.engineUpgrade' then
        return P.integer(value.price,1,1e9) and (command=='train.upgrade' and P.text(value.carId,64)
            or command=='train.engineUpgrade' and P.integer(value.level,1,100))
    end
    if not P.text(value.item,128) then return false end
    if command=='decoration.collect' then return P.integer(value.slot,1,64) end
    if command=='train.fuel' then
        return (value.item=='coal-chunk' or value.item=='coal-bucket') and P.integer(value.gained,1,3)
    end
    if command=='merchant.buy' or command=='merchant.sell' then
        if not amount(value.price) or value.price<1 or value.price~=math.floor(value.price) then return false end
        if command=='merchant.buy' and value.delivery~='inventory' and value.delivery~='train' and value.delivery~='ammo' then return false end
        if command=='merchant.buy' and value.delivery=='ammo' and not amount(value.amount) then return false end
    end
    for _,key in ipairs({'heart','potion'}) do if value[key]~=nil and value[key]~=true then return false end end
    if value.amount~=nil and not amount(value.amount) then return false end
    if command=='mailbox.collect' and not amount(value.amount) then return false end
    if command=='loot.drop' and not P.text(value.entityId,64) then return false end
    if value.gained~=nil then
        if not P.fields(value.gained,{food=true,water=true,oil=true,health=true}) then return false end
        for _,gain in pairs(value.gained) do if not amount(gain) then return false end end
    end
    if command=='inventory.consume' and not (value.heart or value.potion or value.gained) then return false end
    return true
end
function R.project(command,value)
    if command=='progression.request' then return Travel.project(value)end
    if command=='player.pose' then return Pose.project(value) end
    if Range.supports(command) then return Range.project(command,value) end
    if command=='lastStand.position' then return LastStandPosition.project(value) end
    if command=='lastStand.aid' then return LastStandAid.project(value) end
    if Guns.supports(command) then return Guns.project(command,value) end
    if command=='quest.help' or command=='quest.deliver' then return Quests.project(command,value) end
    if command=='firstAid.acquire' or command=='firstAid.step' or command=='firstAid.complete' then return Aid.project(command,value) end
    if command=='outfit.craft' then return Sewing.project(value) end
    if not R.supports(command) then return nil end
    if type(value)~='table' then return nil,'invalid_public_result' end
    local result={}
    if command=='maintenance.step' or command=='maintenance.complete' or command=='weaponRepair.complete' then
        result.success=value.ok==true
        if not result.success then
            result.reason=value.reason
            if not R.valid(command,result) then return nil,'invalid_public_result' end
            return result
        end
    end
    for key in pairs(fields[command]) do
        if key=='success' then result[key]=value.ok==true
        elseif key=='targetDoses' and type(value[key])=='table' then result[key]={value[key][1],value[key][2],value[key][3]}
        elseif key=='tier' then result[key]=value.status and value.status.name
        elseif key~='gained' or command=='train.fuel' then result[key]=value[key]
        elseif type(value.gained)=='table' then
            result.gained={}
            for _,resource in ipairs({'food','water','oil','health'}) do result.gained[resource]=value.gained[resource] end
        end
    end
    if not R.valid(command,result) then return nil,'invalid_public_result' end
    return result
end
return R
