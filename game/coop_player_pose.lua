-- Personal presentation is transient authority state;
-- it never occupies an activity resource or enters a game-save actor record.
local P=require('game.net.protocol')
local Players=require('game.coop_players')
local Life=require('game.coop_last_stand_lifecycle')
local Pose={DURATION=.45,MAX_SERIAL=2147483647}
local allowed={idle=true,sit=true,lay=true,use=true}
function Pose.new() return {nextSerial=1,actors={}} end
local function ordinary(data,id,context,selecting)
    local actor=Players.get(data,id); local s=context.actorState(id)
    if not actor or actor.health<=0 or not s or s.screen~='game' or s.scene~=data.scene
        or not ({train=true,stop=true,house=true,expedition=true,caravan=true})[data.scene]
        or s.traveling or s.encounterActive or s.activityBlocked or s.changingCar
        or selecting and s.actionBusy or data.coop.journey or data.tacticalBattle or data.roamingEncounter
        or Life.active(data) or data.trainAmbush and data.trainAmbush.active==true
        or s.modalDomain~=nil then return nil,'pose_unavailable' end
    if id=='companion' and (s.movementReady~=true or not P.integer(s.motionId,1,Pose.MAX_SERIAL)) then
        return nil,'scene_not_ready'
    end
    if s.poseInputReady==false then return nil,'pose_unavailable' end
    return s,actor
end
local function state(value)
    value.personalPoses=value.personalPoses or Pose.new()
    return value.personalPoses
end
local function clock(service)
    local now=service.clock(); assert(P.clock(now),'invalid pose clock')
    return math.max(now,service.lastNow or 0)
end
local function valid(service,context,id,slot)
    local s,actor=ordinary(service.campaign,id,context,false)
    if not s or not slot or service.bindings[id]==nil or slot.generation~=service.bindings[id]
        or slot.epoch~=service.campaign.coop.sceneEpoch or slot.scene~=service.campaign.scene
        or slot.car~=actor.activeCar or id=='companion' and slot.motionId~=s.motionId then return nil end
    return s
end
local function moving(s)
    -- Actor intentX/Y retain facing direction after release for authored gait.
    -- Only current trusted input samples may cancel a stationary stance.
    return s.moving==true or (s.inputX or 0)~=0 or (s.inputY or 0)~=0
end
local function allocate(poses)
    if poses.nextSerial>Pose.MAX_SERIAL then return nil end
    local serial=poses.nextSerial; poses.nextSerial=serial+1; return serial
end
function Pose.install(service,context)
    assert(type(context)=='table' and type(context.actorState)=='function','trusted pose actor context required')
    service:register('player.pose',function(data,id,args,transaction)
        if not P.fields(args,{pose=true,motionId=true}) or not allowed[args.pose] then return nil,'invalid_pose' end
        local s,actor=ordinary(data,id,context,true); if not s then return nil,actor end
        if transaction.bindings[id]==nil or transaction.generation~=transaction.bindings[id] then return nil,'unbound_peer' end
        if id=='companion' then
            if args.motionId~=s.motionId then return nil,'stale_motion' end
        elseif args.motionId~=nil then return nil,'invalid_pose' end
        if (args.pose=='sit' or args.pose=='lay') and moving(s) then return nil,'pose_moving' end
        local poses=state(transaction.state)
        if poses.nextSerial>Pose.MAX_SERIAL then return nil,'pose_serial_exhausted' end
        return {scopes={'player:'..id},checkpoint=false,effects={},apply=function()
            local serial=assert(allocate(poses))
            local slot={generation=transaction.generation,motionId=id=='companion' and s.motionId or 0,
                epoch=data.coop.sceneEpoch,scene=data.scene,car=actor.activeCar,stance=args.pose=='use' and 'idle' or args.pose,
                serial=serial,useUntil=args.pose=='use' and transaction.now+Pose.DURATION or 0}
            poses.actors[id]=slot
            return {actorId=id,pose=args.pose,serial=serial,useMs=args.pose=='use' and 450 or 0}
        end}
    end)
end
function Pose.get(service,context,id)
    if service.pendingSave then return nil end
    local poses=service.activityState.personalPoses; local slot=poses and poses.actors[id]
    local s=valid(service,context,id,slot); if not s then return nil end
    local ms=math.max(0,math.min(450,math.ceil((slot.useUntil-clock(service))*1000-1e-8)))
    return {actorId=id,pose=moving(s) and 'idle' or slot.stance,serial=slot.serial,useMs=ms}
end
function Pose.advance(service,context)
    if service.pendingSave then return false end
    local poses=service.activityState.personalPoses; if not poses then return false end
    local now=clock(service); local changed=false
    for id,slot in pairs(poses.actors) do
        local s=valid(service,context,id,slot)
        if not s then poses.actors[id]=nil;changed=true
        else
            if moving(s) and slot.stance~='idle' then
                local serial=allocate(poses)
                if serial then slot.stance='idle';slot.serial=serial else poses.actors[id]=nil end
                changed=true
            end
            if slot.useUntil>0 and now>=slot.useUntil then slot.useUntil=0;changed=true end
        end
    end
    return changed
end
-- Root integration must call this from actor admission/disconnect/suspend.
-- Without that hook, get/advance still reject generation/epoch/car changes.
function Pose.releaseActor(activityState,id)
    local poses=activityState.personalPoses
    if poses and poses.actors[id] then poses.actors[id]=nil;return true end
    return false
end
function Pose.clear(service,id) return Pose.releaseActor(service.activityState,id) end
function Pose.presentation(facts,source)
    source=source or {}
    local result={};for key,value in pairs(source) do result[key]=value end
    if not facts then return result end
    result.playerPose=facts.pose
    -- Existing E/item/melee animations retain their original Source timers.
    -- Cosmetic idle facts must never erase those independent actions.
    if (source.actionTimer or 0)<=0 then
        result.actionTimer=(facts.useMs or 0)/1000
        result.actionKind=result.actionTimer>0 and 'use' or nil
        result.actionHeldItem=nil
    end
    return result
end
return Pose
