-- Host campaign decisions; runtime presentation happens only after the checkpoint.
local P=require('game.net.protocol')
local Life=require('game.coop_last_stand_lifecycle')
local State=require('game.coop_last_stand_state')
local Sessions=require('game.coop_shooter_sessions')
local Shootout=require('game.last_stand_shootout')
local Tuning=require('game.last_stand_tuning')
local Positions=require('game.coop_last_stand_positions')
local PositionState=require('game.coop_last_stand_position_state')
local Commands={}
local actions={arrive=true,interior=true,backyard=true,result=true,resident=true,reward=true,returning=true,complete=true,resume=true}
local function number(value,low,high) return type(value)=='number' and value==value and value>=low and value<=high end
local function near(scene,x,y,r)
    return number(scene.x,0,960) and number(scene.y,0,720) and (scene.x-x)^2+(scene.y-y)^2<=r*r
end
local function remember(q,id) q.conversations=q.conversations or {}; q.conversations[id]=true end
local function advancePhase(q) return State.advance(q) end
function Commands.install(authority,context)
    for _,name in ipairs({'lastStand.offer','lastStand.accept','lastStand.decline','lastStand.start','lastStand.advance','lastStand.retry','lastStand.withdraw'}) do
        authority:register(name,function(data,id,args,transaction)
            local fields={questId=true,revision=true}
            if name=='lastStand.advance' then fields.action=true end
            if name=='lastStand.start' then fields.window=true end
            if not P.fields(args,fields) or not P.text(args.questId,32) or not P.integer(args.revision,1,Life.MAX)
                or name=='lastStand.advance' and not actions[args.action]
                or name=='lastStand.start' and args.window~='wide' and args.window~='tall' then return nil,'invalid_args' end
            local q=data.lastStand; local life=q and q.lifecycle
            local actor=context.actorState(id)
            local scene=context.lastStandScene and context.lastStandScene()
            if id~='host' then return nil,'host_only' end
            if not Life.validate(data) or not life or life.entityId~=args.questId or not scene or scene.active~=true
                or scene.questId~=life.entityId or scene.mode~=life.mode or scene.paused
                or not actor or actor.screen~='game' or actor.scene~='stop' or actor.traveling or actor.changingCar or actor.activeActivity
                or data.scene~='stop' or data.stopped~=true or data.location<4 or data.location>=50
                or data.tacticalBattle or data.roamingEncounter or data.coop.journey or scene.blocked then return nil,'quest_unavailable' end
            if life.revision~=args.revision or scene.revision~=life.revision then return nil,'stale_phase' end
            local mode=life.mode
            if mode~='approach' and mode~='offer' and q.originStop~=data.location then return nil,'quest_unavailable' end
            if life.revision>=Life.MAX then return nil,'phase_exhausted' end
            local operation,resultAction
            if name=='lastStand.offer' then
                if mode~='approach' or q.state=='paused' or scene.scoutReady~=true then return nil,'offer_unavailable' end
                operation=function() return Life.move(q,'offer') end
            elseif name=='lastStand.decline' then
                if mode~='offer' then return nil,'offer_unavailable' end
                operation=function() q.declinedStop=data.location; return Life.move(q,'approach','declined') end
            elseif name=='lastStand.accept' then
                if mode~='offer' or q.state=='paused' or not number(actor.x,-100000,100000)
                    or not number(actor.y,-100000,100000) then return nil,'offer_unavailable' end
                operation=function()
                    q.originStop=data.location; q.returnX=actor.x; q.returnY=actor.y
                    q.holdElapsed=0; q.kills=0; q.enemyMorale=100; q.positionIntegrity=100
                    Sessions.reset(q); State.reset(q); q.targets=nil; q.impacts=nil
                    PositionState.reset(q); q.lastWindow=nil
                    q.rewardClaimed=false; q.rewardScrap=nil; q.completed=nil; q.completedAtStop=nil
                    q.completedPhase=0; q.phaseCheckpoint=0; q.intermission=nil; q.victory=false
                    q.residentChecked=false; q.woundedTreated=nil; q.treatmentProgress=nil; q.conversations={}
                    return Life.move(q,'escort')
                end
            elseif name=='lastStand.start' then
                local pose=Life.pose(data,'host')
                if mode~='interior' or q.victory or scene.handoffWindow~=args.window
                    or not number(scene.handoffElapsed,.75,100000) or not near(scene,args.window=='wide' and 350 or 660,280,82)
                    or not pose or not near(pose,args.window=='wide' and 350 or 660,280,82)
                    or scene.action~='window-'..args.window then return nil,'window_unavailable' end
                operation=function()
                    local carry,why=Positions.hostStart(data,transaction,authority.bindings,args.window)
                    if not carry then return false,why end
                    if not State.open(q) then return false,'phase_exhausted' end
                    q.intermission=nil; q.lastWindow=args.window
                    local ok,reason=Life.move(q,'shootout'); if not ok then return false,reason end
                    Shootout.new(q,data,context.catalog,args.window,960,720)
                    local opened,reason=Positions.open(data,transaction,authority.bindings,args.window,carry)
                    if not opened then return false,reason end
                    remember(q,'window-'..args.window); return true
                end
            elseif name=='lastStand.retry' then
                resultAction='retry'
                if mode~='shootout' or not q.combat or q.combat.result~='retreat' then return nil,'retry_unavailable' end
                operation=function()
                    if not Shootout.retry(Shootout.commandView(q,data,'host',nil,960,720)) then return false,'phase_exhausted' end
                    return Life.touch(q)
                end
            elseif name=='lastStand.withdraw' then
                if mode=='shootout' then
                    if not q.combat or q.combat.result then return nil,'result_pending' end
                    operation=function() if not advancePhase(q) then return false,'phase_exhausted' end; return Life.move(q,'interior') end
                elseif mode=='backyard' and not q.victory and near(scene,480,605,55) and scene.action=='return-stop' then
                    operation=function() Sessions.reclaim(q); remember(q,'return-stop'); return Life.move(q,'approach','paused') end
                else return nil,'withdraw_unavailable' end
            else
                resultAction=args.action
                if args.action=='arrive' and mode=='escort' then
                    operation=function() return Life.move(q,'backyard') end
                elseif args.action=='resume' and mode=='approach' and q.state=='paused' and q.originStop==data.location and scene.scoutReady then
                    operation=function() return Life.move(q,'backyard') end
                elseif args.action=='interior' and (mode=='aftermath' or mode=='backyard' and near(scene,480,360,70) and scene.action=='enter-interior') then
                    operation=function() remember(q,'enter-interior'); return Life.move(q,'interior') end
                elseif args.action=='backyard' and mode=='interior' and near(scene,480,620,82) and scene.action=='exit-backyard' then
                    operation=function() remember(q,'exit-backyard'); return Life.move(q,'backyard') end
                elseif args.action=='result' and mode=='shootout' and q.combat and q.combat.result then
                    local combat=q.combat
                    if combat.result~='intermission' and combat.result~='retreat' and combat.result~='victory' then return nil,'result_unavailable' end
                    resultAction=combat.result
                    operation=function()
                        if combat.result=='retreat' then
                            if not Shootout.retry(Shootout.commandView(q,data,'host',nil,960,720)) then return false,'phase_exhausted' end
                            q.intermission=Tuning.phase(q.holdElapsed)
                        elseif combat.result=='intermission' then q.intermission=combat.stage
                        else q.victory=true; Sessions.reset(q) end
                        if not advancePhase(q) then return false,'phase_exhausted' end
                        return Life.move(q,'interior')
                    end
                elseif args.action=='resident' and q.victory then
                    local pose=Life.pose(data,'host')
                    local gecko=mode=='interior' and scene.action=='talk-gecko' and near(scene,710,335,60) and pose and near(pose,710,335,60)
                    local scout=mode=='backyard' and scene.action=='talk-scout' and near(scene,370,410,60) and pose and near(pose,370,410,60)
                    if not gecko and not scout then return nil,'resident_unavailable' end
                    operation=function() q.residentChecked=true; remember(q,gecko and 'talk-gecko' or 'talk-scout'); return true end
                elseif args.action=='reward' and mode=='interior' and q.victory and q.residentChecked and not q.rewardClaimed
                    and near(scene,300,335,60) and scene.action=='talk-fox' then
                    operation=function()
                        q.rewardScrap=28+(q.woundedTreated and q.positionIntegrity>=40 and 8 or 0)
                        data.scrap=math.max(0,tonumber(data.scrap) or 0)+q.rewardScrap
                        data.goodwill=math.max(0,math.floor(tonumber(data.goodwill) or 0))+3
                        data.resources.food=math.max(0,tonumber(data.resources.food) or 0)+2
                        q.rewardClaimed=true; Sessions.reset(q); remember(q,'talk-fox'); return Life.move(q,'aftermath')
                    end
                elseif args.action=='returning' and q.victory and q.rewardClaimed and (mode=='aftermath'
                    or mode=='backyard' and near(scene,480,605,55) and scene.action=='return-stop') then
                    operation=function() remember(q,'return-stop'); return Life.move(q,'returning') end
                elseif args.action=='complete' and mode=='returning' and q.rewardClaimed
                    and number(q.returnX,-100000,100000) and number(q.returnY,-100000,100000) then
                    operation=function()
                        q.completed=true; q.completedAtStop=data.location
                        data.playerX=q.returnX; data.playerY=q.returnY; return Life.move(q,'complete')
                    end
                else return nil,'transition_unavailable' end
            end
            local scopes={'world:scene','entity:'..life.entityId,'player:host','resources','world:maintenance','story:events'}
            if name=='lastStand.start' then scopes[#scopes+1]='activity:lastStand:'..life.entityId..':positions' end
            return {scopes=scopes,checkpoint=true,apply=function()
                local retreatReason=q.combat and q.combat.retreatReason
                local ok,reason=operation(); if not ok then return nil,reason end
                Life.ensure(data)
                return {questId=life.entityId,revision=life.revision,mode=life.mode,action=resultAction,
                    phaseRevision=q.combat and q.combat.phaseRevision,retreatReason=retreatReason,
                    rewardScrap=q.rewardScrap,returnX=q.returnX,returnY=q.returnY}
            end}
        end)
    end
end
return Commands
