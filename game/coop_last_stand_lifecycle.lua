-- Modal scenes share the ordinary stop scene, so they need their own identity.
local P=require('game.net.protocol')
local Geometry=require('game.last_stand_geometry')
local Life={VERSION=2,MAX=1000000000}
local bindings=setmetatable({},{__mode='k'})
local pairsFor={approach={waiting=true,declined=true,paused=true},offer={waiting=true,declined=true,paused=true},
    escort={escort=true},backyard={backyard=true},interior={interior=true},shootout={shootout=true},
    aftermath={aftermath=true},returning={returning=true},complete={complete=true}}
local states={waiting=true,declined=true,paused=true,escort=true,backyard=true,interior=true,shootout=true,
    aftermath=true,returning=true,complete=true}
function Life.validate(data)
    local quest=data.lastStand; local record=quest and quest.lifecycle
    if record==nil then return true end
    if not (data.players~=nil and P.fields(record,{version=true,entityId=true,revision=true,mode=true,positions=true})
        and (record.version==1 or record.version==Life.VERSION) and P.text(record.entityId,32) and record.entityId:match('^e[1-9]%d*$')~=nil
        and P.integer(record.revision,1,Life.MAX) and pairsFor[record.mode]~=nil and pairsFor[record.mode][quest.state]==true) then return false end
    if record.version==1 then return record.positions==nil end
    if not Geometry.walking(record.mode) then return record.positions==nil end
    if not P.fields(record.positions,{host=true,companion=true}) or not record.positions.host then return false end
    if record.positions.host==record.positions.companion then return false end
    for id,pose in pairs(record.positions) do
        if not data.players[id] or not P.fields(pose,{x=true,y=true,facing=true})
            or not Geometry.walkable(record.mode,pose.x,pose.y) or pose.facing~=1 and pose.facing~=-1 then return false end
    end
    return true
end
local function positions(record,data)
    if not Geometry.walking(record.mode) then record.positions=nil; return end
    record.positions=record.positions or {}
    for id in pairs(data and data.players or {host=true}) do
        if not record.positions[id] then local x,y=Geometry.spawn(record.mode,id); record.positions[id]={x=x,y=y,facing=1} end
    end
end
function Life.ensure(data)
    local quest=data.lastStand
    if not data.players or type(quest)~='table' then return nil end
    require('game.coop_last_stand_position_state').prepare(data)
    if not quest.lifecycle then
        quest.state=states[quest.state] and quest.state or 'waiting'
        quest.lifecycle={version=Life.VERSION,revision=1,
            mode=(quest.state=='waiting' or quest.state=='declined' or quest.state=='paused') and 'approach' or quest.state}
        local ok,reason=require('game.coop_entities').ensure(data); assert(ok,reason)
    end
    if quest.lifecycle.version==1 then quest.lifecycle.version=Life.VERSION end
    positions(quest.lifecycle,data)
    assert(Life.validate(data),'invalid Last Stand lifecycle')
    return quest.lifecycle
end
function Life.prepare(data)
    local quest=data.lastStand
    if type(quest)=='table' and quest.state~=nil then Life.ensure(data) end
end
function Life.move(quest,mode,state)
    state=state or ((mode=='offer' or mode=='approach') and quest.state or mode)
    if not pairsFor[mode] or not pairsFor[mode][state] then return false,'invalid_transition' end
    local record=quest.lifecycle
    if record then
        if record.mode==mode and quest.state==state then return true end
        if record.revision>=Life.MAX then return false,'phase_exhausted' end
        record.revision=record.revision+1; record.mode=mode
        record.positions=nil; positions(record)
    end
    quest.state=state
    return true
end
function Life.touch(quest)
    local record=quest.lifecycle
    if not record then return true end
    if record.revision>=Life.MAX then return false,'phase_exhausted' end
    record.revision=record.revision+1
    return true
end
function Life.active(data)
    local record=data and data.lastStand and data.lastStand.lifecycle
    return record and record.mode~='approach' and record.mode~='complete' and record or nil
end
function Life.key(data)
    local record=Life.active(data)
    return record and record.entityId..':'..record.revision..':'..record.mode or nil
end
function Life.walking(data)
    local record=Life.active(data); return record and Geometry.walking(record.mode) or false
end
function Life.pose(data,id)
    local record=Life.active(data)
    return record and record.positions and record.positions[id]
end
function Life.bind(player,data,id,seed)
    local pose=Life.pose(data,id); if not pose or bindings[player]==pose then return false end
    if seed and Geometry.walkable(data.lastStand.lifecycle.mode,player.x,player.y) then
        pose.x,pose.y,pose.facing=player.x,player.y,player.facing==-1 and -1 or 1
    end
    bindings[player]=pose
    rawset(player,'x',nil); rawset(player,'y',nil); rawset(player,'facing',nil)
    setmetatable(player,{__index=function(_,key) if key=='x' or key=='y' or key=='facing' then return pose[key] end end,
        __newindex=function(t,key,value) if key=='x' or key=='y' or key=='facing' then pose[key]=value else rawset(t,key,value) end end})
    return true
end
return Life
