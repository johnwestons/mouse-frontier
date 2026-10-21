local Accessibility=require("game.accessibility")
local WorldView=require("game.world_view")
local Scene=require("game.last_stand_scene")
local Shootout=require("game.last_stand_shootout")
local FirstAid=require("game.first_aid")
local WorldPause=require("game.world_pause")
local FirstPerson=require("game.first_person_shooting")
local Tuning=require("game.last_stand_tuning")
local CharacterMotion=require("game.character_motion")
local Life=require('game.coop_last_stand_lifecycle')
local AidState=require('game.coop_last_stand_aid_state')
local PositionState=require('game.coop_last_stand_position_state')
local ShooterPad=require('game.mobile_shooter_controls')
local AimTargets=require('game.mobile_aim_targets')

local Quest={}
local VERSION=1

local OFFER_LINES={
    "Objective: defend the farmhouse from the railway gang at the relay depot.",
    "Wounded defenders: backyard. Firing positions: two front windows.",
    "Accept to follow the scout to the farmhouse and begin the defense.",
    "Relay distance: 300 meters. Defense target: three minutes and reduced enemy morale.",
    "Loan weapon and ammunition available from Guard Fox. Press L to borrow during the shootout.",
}

local function offerPage(page)
    if type(page)~='number' or page~=math.floor(page) or not OFFER_LINES[page] then return nil end
    return {title='A LIGHT IN THE WINDOWS',text=OFFER_LINES[page],page=page,count=#OFFER_LINES}
end

local function aftermathSummary(quest)
    if not quest or quest.rewardClaimed~=true or (quest.rewardScrap~=28 and quest.rewardScrap~=36) then return nil end
    return {title='THE RELAY GOES QUIET',scrap=quest.rewardScrap,goodwill=3,food=2,
        text='The gang has withdrawn. The defenders lower their weapons one by one. Reward: '
            ..quest.rewardScrap..' scrap, 3 goodwill, and 2 food.'}
end

local VALID_STATES={
    waiting=true,
    declined=true,
    paused=true,
    escort=true,
    backyard=true,
    interior=true,
    shootout=true,
    aftermath=true,
    returning=true,
    complete=true,
}

local CoopProgression=require("game.coop_progression")
local function required(context,name,expected)
    local value=context[name]
    assert(value~=nil,"last stand quest requires "..name)
    if expected then assert(type(value)==expected,"last stand quest "..name.." must be a "..expected) end
    return value
end

local function pointIn(x,y,rx,ry,rw,rh)
    return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh
end

local function offerButtons(width,height)
    return width/2-230,height-118,210,50,width/2+20,height-118,210,50
end

local function mainButton(width,height)
    return width/2-170,height-118,340,50
end

local function modalPanel(title,text,width,height,accent)
    love.graphics.setColor(0,0,0,.62)
    love.graphics.rectangle("fill",0,0,width,height)
    local x,y,w,h=width/2-310,height/2-190,620,380
    love.graphics.setColor(.075,.048,.028,.97)
    love.graphics.rectangle("fill",x,y,w,h,14,14)
    love.graphics.setColor(accent or .82,.55,.23,1)
    love.graphics.setLineWidth(3)

    love.graphics.setColor(1,.84,.55,1)
    love.graphics.printf(title,x+28,y+30,w-56,"center")
    love.graphics.setColor(.93,.87,.75,1)
    love.graphics.printf(text,x+54,y+88,w-108,"center")
end

local function ensureQuest(data)
    if type(data.lastStand)~="table" then data.lastStand={} end
    local quest=data.lastStand
    quest.version=VERSION
    quest.state=VALID_STATES[quest.state] and quest.state or "waiting"
    quest.holdElapsed=math.max(0,tonumber(quest.holdElapsed) or 0)
    quest.kills=math.max(0,math.floor(tonumber(quest.kills) or 0))
    quest.enemyMorale=math.max(0,math.min(100,tonumber(quest.enemyMorale) or 100))
    quest.positionIntegrity=math.max(0,math.min(100,tonumber(quest.positionIntegrity) or 100))
    quest.loanAmmo=math.max(0,math.floor(tonumber(quest.loanAmmo) or 0))
    quest.loanActive=quest.loanActive==true
    quest.rewardClaimed=quest.rewardClaimed==true
    Life.ensure(data)
    AidState.prepare(data)
    PositionState.prepare(data)
    return quest
end

function Quest.new(context)
    assert(type(context)=="table","last stand quest requires an explicit context")
    local runtime=required(context,"runtime","table")
    local Catalog=required(context,"catalog","table")
    local writeSave=required(context,"writeSave","function")
    local characterImages=required(context,"characterImages","table")
    local characterWalkImages=context.characterWalkImages or {}
    local getCharacterAnimations=context.getCharacterAnimations or function() return {} end
    local mobileMovement=context.mobileMovement or function() return 0,0 end
    local mobileSprinting=context.mobileSprinting or function() return false end
    local mobileEnabled=context.mobileEnabled or function() return false end
    local width=required(context,"width","number")
    local height=required(context,"height","number")
    local controlBindings=required(context,"controlBindings","table")

    local service={}
    local resourcesActive=false

    local function releaseResources()
        if not resourcesActive then return end
        FirstPerson.release()
        Scene.release()
        resourcesActive=false
    end

    local function save() return writeSave() end

    local function busy()
        return WorldPause.isPaused(runtime,context.ui,context.maintenanceSession)
            or runtime.battle or runtime.encounter or runtime.sleeping
    end

    local function playerVisual()
        local data=runtime.saveData
        if not data then return nil end
        return {
            image=characterImages[data.character],
            character=data.character,
            animations=getCharacterAnimations(),
            walkImage=characterWalkImages[data.character],
            clock=runtime.animationClock or 0,
        }
    end

    local function needsLoan(quest)
        if quest.loanActive and quest.loanAmmo>0 then return false end
        return not Shootout.hasUsableFirearm(runtime.saveData,Catalog)
    end

    local function sharedCommands() return context.submit and WorldPause.isSharedHost(runtime) end
    local function hostInputPaused(state)
        return state.paused==true or context.inputPaused and context.inputPaused() or false
    end
    local function makeScene(mode,quest)
        local scene=Scene.new(mode,quest)
        if runtime.saveData.players then Life.bind(scene.player,runtime.saveData,'host') end
        return scene
    end
    local function bindCommands(shootout)
        if context.submit then
            Shootout.setCommands(shootout,function(name,args)
                if WorldPause.isSharedHost(runtime) then return context.submit(name,args) end
            end)
        end
    end
    local function presentProgression(state,result)
        local mode=result.mode
        local residentNotice=state.pendingResidentNotice
        state.pendingResidentNotice=nil
        state.pendingProgression=nil
        state.aimTouch=nil; state.aimTouchSession=nil; state.fireTouchSources=nil
        if state.shootout then Shootout.setFireHeld(state.shootout,'keyboard',false); FirstPerson.release() end
        Scene.release()
        state.mode=mode; state.capture=mode~='approach' and mode~='complete'; state.clock=0
        state.handoff=nil; state.notice=nil
        if mode=='approach' then
            if state.quest.state=='paused' then
                runtime.lastStand=nil; releaseResources()
                runtime.dialogue={speaker='Otter Scout',text='Defense paused. Return to the scout to resume.',timer=4}
            else
                state.manualOffer=true; state.arrival=1
                runtime.dialogue={speaker='Otter Scout',text='Defense declined. The scout remains available.',timer=3}
            end
        elseif mode=='offer' then state.offerPage=1; state.arrival=1
        elseif mode=='shootout' then
            state.scene=nil
            state.shootout=Shootout.new(state.quest,runtime.saveData,Catalog,state.quest.lastWindow,width,height)
            bindCommands(state.shootout)
            if result.action=='retry' then
                state.shootout.notice={text='The defenders pull back, regroup, and reopen the firing line.',timer=3}
            end
        elseif mode=='backyard' or mode=='interior' or mode=='aftermath' then
            state.scene=makeScene(mode=='aftermath' and 'interior' or mode,state.quest); state.shootout=nil
            if result.action=='intermission' then state.notice={text=Tuning.phases[state.quest.intermission].line,timer=8}
            elseif result.action=='retreat' then
                local wounded=result.retreatReason=='wounded'; if wounded then state.woundFlash=.45 end
                state.notice={text=wounded
                    and 'Guard Fox pulls you below the window, badly wounded. Your health is still low. Return to the train to heal before trying again.'
                    or 'The defenders pull you back. The current phase will restart; earlier progress and eliminations are safe.',timer=7}
            elseif result.action=='victory' then state.notice={text='Enemies retreating. Check on a resident, then return to Guard Fox.',timer=8}
            elseif result.action=='resident' then
                state.notice={text=residentNotice or (mode=='backyard' and 'Resident checked. Return route: backyard gate.'
                    or 'Resident checked. Defense complete.'),timer=5}
            end
        elseif mode=='complete' then
            if runtime.player then runtime.player.x=result.returnX; runtime.player.y=result.returnY end
            runtime.lastStand=nil; releaseResources()
            runtime.dialogue={speaker='Otter Scout',text='Defense complete.',timer=4}
        else state.scene=nil; state.shootout=nil end
    end
    local function transition(state,name,args)
        if not sharedCommands() then return false end
        if state.pendingProgression then return true,false end
        local life=state.quest.lifecycle
        args=args or {}; args.questId=life.entityId; args.revision=life.revision
        local reply=context.submit(name,args)
        if reply and reply.ok then
            if reply.savePending then
                state.pendingProgression={campaign=runtime.saveData,result=reply.result}
            else presentProgression(state,reply.result) end
        end
        return true,reply and reply.ok==true
    end

    local function beginApproach(quest)
        local player=runtime.player
        if not player then return false end
        local direction=(player.x or width/2)<width/2 and 1 or -1
        runtime.lastStand={
            mode="approach",
            capture=false,
            quest=quest,
            clock=0,
            arrival=0,
            scout={
                x=(player.x or width/2)+direction*285,
                y=(player.y or height/2)+34,
            },
        }
        return true
    end

    local function showOffer(state)
        if transition(state,'lastStand.offer') then return end
        if not CoopProgression.allowed(runtime,"lastStand.accept") then return false,"host_only" end
        if not Life.move(state.quest,'offer') then return false,'phase_exhausted' end
        state.mode="offer"
        state.capture=true
        state.offerPage=state.offerPage or 1
        state.arrival=1
    end

    local function enterScene(state,mode)
        local action=mode=='interior' and 'interior' or state.quest.state=='paused' and 'resume'
            or state.mode=='escort' and 'arrive' or 'backyard'
        if transition(state,'lastStand.advance',{action=action}) then return end
        if not CoopProgression.allowed(runtime,"lastStand.advance") then return false,"host_only" end
        state.aimTouch=nil; state.aimTouchSession=nil
        if state.mode~=mode then
            if state.mode=="shootout" then
                if not require('game.coop_last_stand_state').advance(state.quest) then return false,'phase_exhausted' end
                FirstPerson.release()
            end
            Scene.release()
        end
        state.mode=mode
        state.capture=true
        state.scene=state.scene or Scene.new(mode,state.quest)
        Scene.change(state.scene,mode)
        Life.move(state.quest,mode)
        if runtime.saveData.players then
            Life.ensure(runtime.saveData); Life.bind(state.scene.player,runtime.saveData,'host')
        end
        state.notice=nil
        save()
    end

    local function accept(state)
        if transition(state,'lastStand.accept') then return end
        if not CoopProgression.allowed(runtime,"lastStand.accept") then return false,"host_only" end
        local quest=state.quest
        Life.move(quest,'escort')
        quest.originStop=runtime.saveData.location
        quest.returnX=runtime.player and runtime.player.x or width/2
        quest.returnY=runtime.player and runtime.player.y or height/2
        quest.holdElapsed=0
        quest.kills=0
        quest.enemyMorale=100
        quest.positionIntegrity=100
        require('game.coop_shooter_sessions').reset(quest)
        quest.rewardClaimed=false
        quest.targets=nil
        require('game.coop_last_stand_state').reset(quest)
        quest.impacts=nil
        quest.completedPhase=0
        quest.phaseCheckpoint=0
        quest.intermission=nil
        quest.victory=false
        quest.residentChecked=false
        quest.conversations={}
        state.mode="escort"
        state.capture=true
        state.clock=0
        state.reducedMotion=Accessibility.ensure(runtime.saveData) and Accessibility.ensure(runtime.saveData).reducedMotion==true
        save()
    end

    local function decline(state)
        if transition(state,'lastStand.decline') then return end
        if not CoopProgression.allowed(runtime,"quest.decline") then return false,"host_only" end
        local quest=state.quest
        Life.move(quest,'approach','declined')
        quest.declinedStop=runtime.saveData.location
        state.mode="approach"
        state.capture=false
        state.manualOffer=true
        runtime.dialogue={speaker="Otter Scout",text="Defense declined. The scout remains available.",timer=3}
        save()
    end

    local function grantLoan(state)
        if sharedCommands() then
            if state.pendingSupply then return end
            local life=state.quest.lifecycle
            local reply=context.submit('lastStand.supply',{mode='farmhouse',questId=life.entityId,revision=life.revision})
            if reply and reply.ok then
                if reply.savePending then
                    state.pendingSupply={campaign=runtime.saveData,result=reply.result}
                else state.notice={text='Loan supplies received. '..reply.result.loanAmmo..' rounds available.',timer=3.6} end
            else state.notice={text='Supplies are currently unavailable. Stay near Guard Fox and try again.',timer=3.6} end
            return
        end
        local quest=state.quest
        local first=not quest.loanActive
        quest.loanActive=true
        quest.loanAmmo=math.max(quest.loanAmmo,first and 48 or 12)
        state.notice={
            text=first and "Guard Fox lends you a Frontier .22 lever rifle and 48 rounds." or "Guard Fox passes you another pouch of .22 ammunition.",
            timer=3.6,
        }
        save()
    end

    local function beginShootout(state,windowId)
        if transition(state,'lastStand.start',{window=windowId}) then return end
        if not CoopProgression.allowed(runtime,"lastStand.start") then return false,"host_only" end
        if not require('game.coop_last_stand_state').open(state.quest) then return false,'phase_exhausted' end
        state.handoff=nil
        state.scene.handoff=nil
        Scene.release()
        state.quest.intermission=nil
        state.quest.lastWindow=windowId
        Life.move(state.quest,'shootout')
        state.mode="shootout"
        state.capture=true
        state.shootout=Shootout.new(state.quest,runtime.saveData,Catalog,windowId,width,height)
        bindCommands(state.shootout)
        save()
    end

    local function requestWindow(state,windowId)
        if not CoopProgression.allowed(runtime,"lastStand.start") then return false,"host_only" end
        if state.handoff or state.pendingPosition or state.quest.victory then return end
        if sharedCommands() then
            local life=state.quest.lifecycle
            local reply=context.submit('lastStand.position',{questId=life.entityId,revision=life.revision,action='select',window=windowId})
            if not reply or not reply.ok then
                state.notice={text='That firing position is unavailable.',timer=2.5}; return
            end
            if reply.savePending then
                state.pendingPosition={campaign=runtime.saveData,questId=life.entityId,revision=life.revision,window=windowId}; return
            end
        else
            -- Standalone offline controllers still accept legacy data without
            -- multiplayer actor records. Canonical campaigns retain their
            -- checked personal window selection.
            if runtime.saveData.players then
                PositionState.ensure(runtime.saveData)
                local owner=PositionState.owner(runtime.saveData,windowId)
                if owner and owner~='host' then PositionState.release(runtime.saveData,owner) end
                if not PositionState.claim(runtime.saveData,'host',windowId) then return end
            end
        end
        state.handoff={window=windowId,elapsed=0}
        state.scene.handoff=state.handoff
        state.notice={text=windowId=="wide" and "Wide firing position selected."
            or "Narrow firing position selected.",timer=2.5}
    end

    local function presentTreatment(state,result,kind)
        state.pendingTreatment=nil
        if kind=='start' and result.session then
            local campaign=runtime.saveData; local life=state.quest.lifecycle
            state.treatment=FirstAid.bindCommands(result.session,function(_,args)
                if runtime.saveData~=campaign or state.quest~=campaign.lastStand then return {ok=false,reason='wrong_campaign'} end
                args.questId=life.entityId; args.revision=result.revision
                local reply=context.submit('lastStand.aid',args)
                state.treatmentReply=reply
                return reply
            end,result.leaseId)
        else
            state.treatment=nil
            state.notice={text=result.completed and "The dressing holds. The defender can rest, and another pair of paws is free to help."
                or result.inspected and result.treated and "The defender is resting comfortably. Your dressing is holding."
                or 'Treatment paused. Your progress is saved.',timer=5}
        end
    end
    local function treatmentReply(state,reply,kind)
        if reply and reply.ok then
            if reply.savePending then state.pendingTreatment={campaign=runtime.saveData,result=reply.result,kind=kind}
            else presentTreatment(state,reply.result,kind) end
        else
            state.treatment=nil; state.notice={text='Treatment unavailable. Stay near the patient and try again.',timer=4}
        end
    end
    local function beginTreatment(state)
        if not sharedCommands() then return false end
        if state.pendingTreatment then return true end
        local life=state.quest.lifecycle
        treatmentReply(state,context.submit('lastStand.aid',{questId=life.entityId,revision=life.revision,
            action=state.quest.woundedTreated and 'inspect' or 'acquire'}),'start')
        return true
    end
    local function finishTreatment(state,result)
        if not result then return end
        if state.treatment and state.treatment.command and not sharedCommands() then
            state.treatment=nil; state.pendingAidComplete=nil; return
        end
        if sharedCommands() then
            if not state.treatment or not state.treatment.command then return end
            if result=='complete' then
                local life=state.quest.lifecycle
                if runtime.session and runtime.session.checkpointPending then
                    state.pendingAidComplete={campaign=runtime.saveData,questId=life.entityId,revision=life.revision}
                    return
                end
                local reply=context.submit('lastStand.aid',{questId=life.entityId,revision=life.revision,
                    action='complete',leaseId=state.treatment.leaseId})
                if not reply.ok and reply.reason=='lease_expired' then
                    -- The global save barrier intentionally clears all activity locks.
                    -- Reacquire the saved ready treatment before confirming its benefit.
                    local resumed=context.submit('lastStand.aid',{questId=life.entityId,revision=life.revision,action='acquire'})
                    treatmentReply(state,resumed,'start')
                    if resumed.ok and resumed.result.session then
                        state.pendingAidComplete={campaign=runtime.saveData,questId=life.entityId,revision=life.revision}
                    end
                else treatmentReply(state,reply,'finish') end
            elseif result=='cancelled' then
                local reply=state.treatmentReply
                if not (reply and reply.ok and reply.result.outcome=='cancelled') then
                    local life=state.quest.lifecycle
                    reply=context.submit('lastStand.aid',{questId=life.entityId,revision=life.revision,
                        action='pause',leaseId=state.treatment.leaseId})
                end
                treatmentReply(state,reply,'finish')
            end
            return
        end
        if result=="complete" then
            state.quest.woundedTreated=true
            state.quest.positionIntegrity=math.min(100,state.quest.positionIntegrity+12)
            state.notice={text="The dressing holds. The defender can rest, and another pair of paws is free to help.",timer=5}
        end
        if result=="complete" or result=="cancelled" then state.treatment=nil end
        save()
    end

    local awardVictory,beginReturn
    local function handleSceneAction(state)
        local action=Scene.action(state.scene,needsLoan(state.quest))
        if not action then return false end
        local progressionActions={['enter-interior']="lastStand.advance",['exit-backyard']="lastStand.advance",['return-stop']="lastStand.withdraw"}
        if state.quest.victory and (action.id=='talk-gecko' or action.id=='talk-scout' or action.id=='talk-fox') then
            progressionActions[action.id]='lastStand.advance'
        end
        if progressionActions[action.id] and not CoopProgression.allowed(runtime,progressionActions[action.id]) then return false,"host_only" end
        if sharedCommands() then
            if action.id=='enter-interior' then transition(state,'lastStand.advance',{action='interior'}); return true
            elseif action.id=='exit-backyard' then transition(state,'lastStand.advance',{action='backyard'}); return true
            elseif action.id=='window-wide' then requestWindow(state,'wide'); return true
            elseif action.id=='window-tall' then requestWindow(state,'tall'); return true
            elseif action.id=='borrow-rifle' then grantLoan(state); return true
            elseif action.id=='help-wounded' then beginTreatment(state); return true
            elseif (action.id=='talk-gecko' or action.id=='talk-scout') and state.quest.victory then
                if state.pendingProgression then return true end
                state.pendingResidentNotice=action.id=='talk-gecko' and 'Resident checked. Defense complete.'
                    or 'Resident checked. Return route: backyard gate.'
                local _,accepted=transition(state,'lastStand.advance',{action='resident'})
                if not accepted then state.pendingResidentNotice=nil end
                return true
            elseif action.id=='talk-fox' and state.quest.victory and not state.quest.rewardClaimed and state.quest.residentChecked then
                transition(state,'lastStand.advance',{action='reward'}); return true
            elseif action.id=='return-stop' and not state.quest.victory then
                transition(state,'lastStand.withdraw'); return true
            elseif action.id=='return-stop' and state.quest.rewardClaimed then
                transition(state,'lastStand.advance',{action='returning'}); return true
            end
        end
        if action.id=="enter-interior" then enterScene(state,"interior")
        elseif action.id=="exit-backyard" then enterScene(state,"backyard")
        elseif action.id=="borrow-rifle" then grantLoan(state)
        elseif action.id=="window-wide" then requestWindow(state,"wide")
        elseif action.id=="window-tall" then requestWindow(state,"tall")
        elseif action.id=="talk-fox" then
            if state.quest.victory and not state.quest.rewardClaimed and state.quest.residentChecked then
                awardVictory(state)
            else
                state.notice={text=state.quest.victory and (state.quest.rewardClaimed
                    and "Defense complete. Return with the scout when ready."
                    or "Enemies retreating. Check on a resident, then return to Guard Fox.")
                    or "Both windows are available. Press L to borrow the spare rifle.",timer=5}
            end
        elseif action.id=="talk-gecko" then
            state.quest.residentChecked=state.quest.victory or state.quest.residentChecked
            state.notice={text=state.quest.victory and "Resident checked. Defense complete."
                or "The narrow window provides more cover. Duck to avoid incoming fire.",timer=5}
        elseif action.id=="talk-scout" then
            state.quest.residentChecked=state.quest.victory or state.quest.residentChecked
            state.notice={text=state.quest.victory and "Resident checked. Return route: backyard gate."
                or "Wounded defenders: backyard. Return route: backyard gate.",timer=5}
        elseif action.id=="help-wounded" then
            state.quest.residentChecked=state.quest.victory or state.quest.residentChecked
            if state.quest.woundedTreated then
                state.notice={text="The defender is resting comfortably. Your dressing is holding.",timer=4}
            else
                AidState.ensure(runtime.saveData)
                state.treatment=FirstAid.new({progress=state.quest.treatmentProgress,
                    location=state.quest.originStop,itemName="house medical supplies"})
            end
        elseif action.id=="return-stop" then
            if state.quest.victory then
                if state.quest.rewardClaimed then beginReturn(state)
                else state.notice={text="Check on a resident and speak to Guard Fox before leaving. They want to thank you.",timer=4} end
                return true
            end
            Life.move(state.quest,'approach','paused')
            require('game.coop_shooter_sessions').reclaim(state.quest)
            runtime.lastStand=nil
            releaseResources()
            runtime.dialogue={speaker="Otter Scout",text="Defense paused. Return to the scout to resume.",timer=4}
            save()
        end
        state.quest.conversations=state.quest.conversations or {}
        state.quest.conversations[action.id]=true
        save()
        return true
    end

    awardVictory=function(state)
        if transition(state,'lastStand.advance',{action='reward'}) then return end
        if not CoopProgression.allowed(runtime,"lastStand.advance") then return false,"host_only" end
        local quest=state.quest
        if not quest.rewardClaimed then
            local bonus=quest.woundedTreated and quest.positionIntegrity>=40 and 8 or 0
            quest.rewardScrap=28+bonus
            runtime.saveData.scrap=math.max(0,tonumber(runtime.saveData.scrap) or 0)+quest.rewardScrap
            runtime.saveData.goodwill=math.max(0,math.floor(tonumber(runtime.saveData.goodwill) or 0))+3
            runtime.saveData.resources=runtime.saveData.resources or {}
            runtime.saveData.resources.food=math.max(0,tonumber(runtime.saveData.resources.food) or 0)+2
            quest.rewardClaimed=true
        end
        require('game.coop_shooter_sessions').reset(quest)
        Life.move(quest,'aftermath')
        state.mode="aftermath"
        state.capture=true
        state.scene=Scene.new("interior",quest)
        state.shootout=nil
        state.clock=0
        save()
    end

    beginReturn=function(state)
        if transition(state,'lastStand.advance',{action='returning'}) then return end
        if not CoopProgression.allowed(runtime,"lastStand.advance") then return false,"host_only" end
        Life.move(state.quest,'returning')
        state.mode="returning"
        state.capture=true
        state.clock=0
        save()
    end

    local function completeReturn(state)
        if transition(state,'lastStand.advance',{action='complete'}) then return end
        if not CoopProgression.allowed(runtime,"lastStand.advance") then return false,"host_only" end
        local quest=state.quest
        Life.move(quest,'complete')
        quest.completed=true
        quest.completedAtStop=runtime.saveData.location
        if runtime.player then
            runtime.player.x=tonumber(quest.returnX) or runtime.player.x
            runtime.player.y=tonumber(quest.returnY) or runtime.player.y
        end
        runtime.lastStand=nil
        releaseResources()
        runtime.dialogue={
            speaker="Otter Scout",
            text="Defense complete.",
            timer=4,
        }
        save()
    end

    local function restore(quest)
        local mode=sharedCommands() and quest.lifecycle.mode or quest.state
        if not sharedCommands() then
            if mode=='escort' then mode='backyard' end
            if mode=='shootout' then mode='interior' end
            if mode=='returning' then mode='aftermath' end
            Life.move(quest,mode)
        end
        local state={
            mode=mode,
            capture=true,
            quest=quest,
            clock=0,
            scene=(mode=="backyard" or mode=="interior" or mode=="aftermath") and makeScene(mode=="aftermath" and "interior" or mode,quest) or nil,
        }
        runtime.lastStand=state
        if mode=='shootout' then
            state.shootout=Shootout.new(quest,runtime.saveData,Catalog,quest.lastWindow,width,height); bindCommands(state.shootout)
        end
        return state
    end

    function service:debugStart(shootout)
        if not runtime.saveData or runtime.session and runtime.session.networkMode~='offline' and runtime.session.networkMode~=nil then return false,'offline_only' end
        releaseResources()
        local previous=runtime.saveData.lastStand or {}
        -- Debug replay must not reset the user's completed conversations.
        runtime.saveData.lastStand={state='backyard',originStop=runtime.saveData.location,
            returnX=runtime.player.x,returnY=runtime.player.y,loanActive=true,loanAmmo=120,
            conversations=previous.conversations,rewardClaimed=previous.rewardClaimed}
        local quest=ensureQuest(runtime.saveData)
        local state=restore(quest)
        if shootout then beginShootout(state,'wide') end
        save();return true
    end

    local function canOffer(quest)
        if quest.state~="waiting" and quest.state~="declined" and quest.state~="paused" then return false end
        local data=runtime.saveData
        if runtime.state~="game" or runtime.scene~="stop" or not data or not data.stopped then return false end
        if data.location<4 or data.location>=50 or busy() then return false end
        if quest.state=="paused" and quest.originStop~=data.location then return false end
        return true
    end

    -- Every button accepted by the device binding editor must be polled here.
    local controllerButtons={"a","b","x","y","start","back","guide","leftshoulder","rightshoulder",
        "leftstick","rightstick","dpup","dpdown","dpleft","dpright"}
    local controllerHeld={}
    local controllerADS=false
    local controllerFire=false
    local controllerGun
    local function neutralizeShooter(state,preserveButtons)
        if state.aimPad then state.aimPad:cancel() end
        if state.shootout and state.shootout.gun then
            state.shootout.fireHeldSources={}; state.shootout.gun.fireHeldSources={}; state.shootout.gun.fireHeld=false
            Shootout.setADS(state.shootout,false)
        end
        state.aimTouch=nil; state.aimTouchSession=nil; state.fireTouchSources=nil
        if not preserveButtons then controllerHeld={} end
        controllerADS=false; controllerFire=false; controllerGun=nil
        if state.scene then state.scene.axisX=0; state.scene.axisY=0 end
    end
    local function pollController(dt)
        local state=runtime.lastStand
        if not state or not love.joystick then return end
        if context.inputPaused and context.inputPaused() or runtime.session and runtime.session.checkpointPending then
            neutralizeShooter(state); return
        end
        -- Internal pause still polls button edges so Start can resume. Aim and
        -- fire remain neutral while the pause is open.
        if state.paused then neutralizeShooter(state,true) end
        local pads=love.joystick.getJoysticks()
        local pad
        for _,candidate in ipairs(pads) do if candidate:isGamepad() then pad=candidate; break end end
        if not pad then
            if controllerADS and state.shootout then Shootout.setADS(state.shootout,false) end
            if controllerFire and state.shootout then Shootout.setFireHeld(state.shootout,"controller",false) end
            controllerADS=false; controllerGun=nil; controllerFire=false
            controllerHeld={}
            if state.scene then state.scene.axisX=0; state.scene.axisY=0 end
            return
        end
        local scope=state.treatment and "last_stand_treatment"
            or state.mode=="offer" and "last_stand_offer"
            or (state.mode=="escort" or state.mode=="returning") and "last_stand_escort"
            or state.mode=="shootout" and "last_stand_shootout"
            or (state.mode=="backyard" or state.mode=="interior") and "last_stand_world"
            or "last_stand"
        for _,button in ipairs(controllerButtons) do
            local down=pad:isGamepadDown(button)
            local previous=controllerHeld[button]
            if down and not previous then
                local key=controlBindings:translateButton(button,scope)
                if key then service:keypressed(key) end
                controllerHeld[button]={key=key,scope=scope}
            elseif not down and previous then
                -- Release the pressed action, even if its physical binding was
                -- changed while held. A different modal scope cannot inherit it.
                if previous.key and previous.scope==scope then service:keyreleased(previous.key) end
                controllerHeld[button]=nil
            end
        end
        state=runtime.lastStand
        if not state then return end
        local function axis(name) return controlBindings:axisValue(name) end
        if state.scene then
            state.scene.axisX,state.scene.axisY=controlBindings:movement()
        end
        if state.mode=="shootout" and not state.paused then
            local gun=state.shootout.gun
            local aimDX,aimDY=axis("aim_x"),axis("aim_y")
            if aimDX~=0 or aimDY~=0 then
                Shootout.setAim(state.shootout,math.max(0,math.min(width,gun.aimX+aimDX*340*dt)),
                    math.max(0,math.min(height,gun.aimY+aimDY*340*dt)))
            end
            local aiming=axis("ads")>.4
            if aiming~=controllerADS or (aiming and controllerGun~=gun) then Shootout.setADS(state.shootout,aiming) end
            controllerADS=aiming; controllerGun=gun
            local firing=axis("fire")>.4
            if firing and not controllerFire then
                Shootout.setFireHeld(state.shootout,"controller",true,runtime.saveData,width,height,Catalog)
            elseif not firing and controllerFire then
                Shootout.setFireHeld(state.shootout,"controller",false)
            end
            controllerFire=firing
        elseif state.mode~="shootout" then
            if controllerFire then Shootout.setFireHeld(state.shootout,"controller",false) end
            controllerADS=false; controllerGun=nil; controllerFire=false
        end
    end

    function service:update(dt)
        -- A title-screen hosting intent must finish its checked connection or
        -- be cancelled before ordinary offline restoration can change modes.
        if context.hostSavedJourneyPending and context.hostSavedJourneyPending() then return self:isCapturing() end
        local pendingState=runtime.lastStand
        local treatment=pendingState and pendingState.pendingTreatment
        if treatment and not (runtime.session and runtime.session.checkpointPending) then
            local life=pendingState.quest.lifecycle
            if treatment.campaign==runtime.saveData and runtime.saveData.lastStand==pendingState.quest
                and life.entityId==treatment.result.questId and life.revision==treatment.result.revision then
                presentTreatment(pendingState,treatment.result,treatment.kind)
            else pendingState.pendingTreatment=nil; pendingState.treatment=nil end
        end
        local complete=pendingState and pendingState.pendingAidComplete
        if complete and not (runtime.session and runtime.session.checkpointPending) then
            pendingState.pendingAidComplete=nil
            local life=pendingState.quest.lifecycle
            if complete.campaign==runtime.saveData and pendingState.quest==runtime.saveData.lastStand
                and life.entityId==complete.questId and life.revision==complete.revision then finishTreatment(pendingState,'complete') end
        end
        local supply=pendingState and pendingState.pendingSupply
        if supply and not (runtime.session and runtime.session.checkpointPending) then
            local life=pendingState.quest.lifecycle
            if supply.campaign==runtime.saveData and runtime.saveData.lastStand==pendingState.quest
                and life.entityId==supply.result.questId and life.revision==supply.result.revision then
                pendingState.notice={text='Loan supplies received. '..supply.result.loanAmmo..' rounds available.',timer=3.6}
            end
            pendingState.pendingSupply=nil
        end
        local pending=pendingState and pendingState.pendingProgression
        if pending and not (runtime.session and runtime.session.checkpointPending) then
            local life=pendingState.quest.lifecycle
            if pending.campaign==runtime.saveData and runtime.saveData.lastStand==pendingState.quest
                and life.entityId==pending.result.questId and life.revision==pending.result.revision then
                presentProgression(pendingState,pending.result)
            else pendingState.pendingProgression=nil end
        end
        local position=pendingState and pendingState.pendingPosition
        if position and not (runtime.session and runtime.session.checkpointPending) then
            pendingState.pendingPosition=nil
            local life=pendingState.quest.lifecycle
            if position.campaign==runtime.saveData and runtime.saveData.lastStand==pendingState.quest
                and life.entityId==position.questId and life.revision==position.revision
                and PositionState.selected(runtime.saveData,'host')==position.window then
                pendingState.handoff={window=position.window,elapsed=0}
                if pendingState.scene then pendingState.scene.handoff=pendingState.handoff end
            end
        end
        if not CoopProgression.allowed(runtime,"lastStand.advance") then
            if runtime.lastStand then
                neutralizeShooter(runtime.lastStand)
                if runtime.lastStand.shootout then runtime.lastStand.shootout.effectsPaused=true end
            end
            return self:isCapturing()
        end
        if runtime.state~="game" or not runtime.saveData then
            runtime.lastStand=nil
            releaseResources()
            return false
        end
        local quest=ensureQuest(runtime.saveData)
        local state=runtime.lastStand
        if not state then
            releaseResources()
            if quest.state=="complete" then return false end
            if quest.state=="escort" or quest.state=="backyard" or quest.state=="interior"
                or quest.state=="shootout" or quest.state=="aftermath" or quest.state=="returning" then
                state=restore(quest)
            elseif canOffer(quest) then
                beginApproach(quest)
                state=runtime.lastStand
                state.manualOffer=quest.state=="declined" or quest.state=="paused"
                if sharedCommands() and quest.lifecycle.mode=='offer' then state.mode='offer'; state.capture=true; state.offerPage=1; state.arrival=1 end
            else
                return false
            end
        end
        pollController(dt)
        state=runtime.lastStand
        if not state then return false end
        if state.treatment and state.treatment.command and not sharedCommands() then state.treatment=nil end
        resourcesActive=true
        local privatePaused=hostInputPaused(state)
        if privatePaused then neutralizeShooter(state,true) end
        local sharedFight=sharedCommands() and state.mode=='shootout'
        if state.paused and not sharedFight then
            if state.shootout then state.shootout.effectsPaused=true end
            return true
        end
        if sharedFight and (runtime.session and runtime.session.checkpointPending
            or context.globalSimulationBlocked and context.globalSimulationBlocked()) then
            neutralizeShooter(state); state.shootout.effectsPaused=true; return true
        end
        if sharedFight then
            state.positionReadyRetry=math.max(0,(state.positionReadyRetry or 0)-dt)
            local status=context.positionStatus and context.positionStatus('host')
            if not status then
                neutralizeShooter(state)
                if not privatePaused and state.positionReadyRetry<=0 and not state.shootout.result then
                    local life=state.quest.lifecycle; local window=PositionState.selected(runtime.saveData,'host')
                    if not window then
                        if not PositionState.owner(runtime.saveData,'wide') then window='wide'
                        elseif not PositionState.owner(runtime.saveData,'tall') then window='tall' end
                    end
                    if window then
                        context.submit('lastStand.position',{questId=life.entityId,revision=life.revision,
                            action='ready',window=window,phaseRevision=state.quest.combat.phaseRevision})
                        state.positionReadyRetry=.6
                    end
                end
            end
        elseif privatePaused then return true end
        state.clock=(state.clock or 0)+dt
        state.woundFlash=math.max(0,(state.woundFlash or 0)-dt)
        if state.treatment then
            finishTreatment(state,FirstAid.update(state.treatment,dt))
            return true
        end
        if state.notice then
            state.notice.timer=state.notice.timer-dt
            if state.notice.timer<=0 then state.notice=nil end
        end

        if state.mode=="approach" then
            if runtime.scene~="stop" or runtime.state~="game" then runtime.lastStand=nil; releaseResources(); return false end
            if busy() then return false end
            local player=runtime.player
            local dx,dy=(player.x or 0)-state.scout.x,(player.y or 0)-state.scout.y
            local distance=math.sqrt(dx*dx+dy*dy)
            if distance>82 then
                local step=math.min(distance-82,86*dt)
                state.scout.x=state.scout.x+dx/distance*step
                state.scout.y=state.scout.y+dy/distance*step
                state.walkDistance=(state.walkDistance or 0)+step
                state.arrival=0
            else
                state.arrival=(state.arrival or 0)+dt
                if state.arrival>=.55 and not state.manualOffer then showOffer(state) end
            end
            return state.capture
        end
        if state.mode=="offer" then return true end
        if state.mode=="escort" then
            if state.clock>=8 then enterScene(state,"backyard") end
            return true
        end
        if state.mode=="backyard" or state.mode=="interior" then
            if runtime.saveData.players then Life.bind(state.scene.player,runtime.saveData,'host') end
            state.scene.reducedMotion=Accessibility.ensure(runtime.saveData) and Accessibility.ensure(runtime.saveData).reducedMotion==true
            state.scene.reducedFlashes=Accessibility.ensure(runtime.saveData) and Accessibility.ensure(runtime.saveData).reducedFlashes==true
            local mobileX,mobileY=mobileMovement()
            local sprinting=love.keyboard.isDown("lshift","rshift") or controlBindings:actionDown("sprint") or mobileSprinting()
            local reports=Scene.update(state.scene,dt,{
                mobileX=mobileX,mobileY=mobileY,sprinting=sprinting,
                speed=runtime.player and runtime.player.speed or 185,
                profile=CharacterMotion.profileFor(runtime.saveData.character),
            })
            if reports>0 and not state.quest.victory then FirstPerson.playReport("frontier-22-lever-rifle",Catalog,runtime.saveData,true) end
            if state.handoff then
                state.handoff.elapsed=state.handoff.elapsed+dt
                if state.handoff.elapsed>=.75 then beginShootout(state,state.handoff.window) end
            end
            return true
        end
        if state.mode=="shootout" then
            local ids
            if sharedFight then
                ids={}; local seen={}
                for _,id in ipairs(context.participants and context.participants() or {}) do
                    if not seen[id] and (id~='host' or not privatePaused) then ids[#ids+1]=id; seen[id]=true end
                end
                if #ids==0 and not state.shootout.result then state.shootout.effectsPaused=true; return true end
            end
            state.shootout.effectsPaused=false
            if state.aimPad and state.aimTouchSession~=state.shootout then state.aimPad:cancel() end
            if state.aimPad and not privatePaused then
                local settings=Accessibility.aimSettings(runtime.saveData)
                local x,y=state.aimPad:step(dt,state.shootout.gun,width,height,nil,
                    settings,settings.aimAssist>0 and state.aimPad.aimTouch and AimTargets.lastStand(state.shootout,width,height))
                if x then Shootout.setAim(state.shootout,x,y) end
            end
            local healthBefore=runtime.saveData.health
            local companionBefore=runtime.saveData.players and runtime.saveData.players.companion and runtime.saveData.players.companion.health
            local result=Shootout.update(state.shootout,dt,runtime.saveData,Catalog,width,height,ids)
            local companionAfter=runtime.saveData.players and runtime.saveData.players.companion and runtime.saveData.players.companion.health
            if runtime.saveData.health~=healthBefore or companionAfter~=companionBefore then save() end
            if privatePaused and sharedFight then
                state.saveTimer=(state.saveTimer or 0)+dt
                if state.saveTimer>=5 then state.saveTimer=0; save() end
                return true
            end
            if result=="intermission" then
                if transition(state,'lastStand.advance',{action='result'}) then return true end
                local phase=state.shootout.stage
                state.quest.intermission=phase
                enterScene(state,"interior")
                state.notice={text=Tuning.phases[phase].line,timer=8}
                state.shootout=nil
            elseif result=="retreat" then
                if transition(state,'lastStand.advance',{action='result'}) then return true end
                local wounded=state.shootout.retreatReason=="wounded"
                if wounded then state.woundFlash=.45 end
                Shootout.retry(state.shootout)
                enterScene(state,"interior")
                state.quest.intermission=Tuning.phase(state.quest.holdElapsed)
                state.notice={text=wounded
                    and "Guard Fox pulls you below the window, badly wounded. Your health is still low. Return to the train to heal before trying again."
                    or "The defenders pull you back. The current phase will restart; earlier progress and eliminations are safe.",timer=7}
                state.shootout=nil
                save()
            elseif result=="victory" then
                if transition(state,'lastStand.advance',{action='result'}) then return true end
                state.quest.victory=true
                require('game.coop_shooter_sessions').reset(state.quest)
                enterScene(state,"interior")
                state.notice={text="Enemies retreating. Check on a resident, then return to Guard Fox.",timer=8}
                state.shootout=nil
                save()
            end
            state.saveTimer=(state.saveTimer or 0)+dt
            if state.saveTimer>=5 then state.saveTimer=0; save() end
            return true
        end
        if state.mode=="aftermath" then return true end
        if state.mode=="returning" then
            if state.clock>=5 then completeReturn(state); return self:isCapturing() end
            return true
        end
        return state.capture==true
    end

    function service:keypressed(key)
        local state=runtime.lastStand
        if not state then return false end
        if context.inputPaused and context.inputPaused() then neutralizeShooter(state); return state.capture==true end
        if runtime.session and runtime.session.checkpointPending then return state.capture==true end
        if state.capture and key=="p" then
            if sharedCommands() and state.treatment and state.treatment.command then finishTreatment(state,'cancelled') end
            state.paused=not state.paused; save(); return true
        end
        if state.paused then
            if key=="escape" or key=="return" then state.paused=false end
            return true
        end
        if state.treatment then finishTreatment(state,FirstAid.keypressed(state.treatment,key)); return true end
        if state.handoff then
            if key=="escape" then state.handoff=nil; state.scene.handoff=nil; state.notice=nil end
            return true
        end
        if state.mode=="approach" then
            if key=="e" and state.arrival and state.arrival>0 and not busy() then
                if context.ui and context.ui.interaction then return false end
                if state.quest.state=="paused" then enterScene(state,"backyard") else showOffer(state) end
                return true
            end
            return false
        end
        if state.mode=="offer" then
            if key=="n" or key=="escape" then decline(state)
            elseif key=="y" then accept(state)
            elseif key=="q" then state.offerPage=4
            elseif key=="f" then state.offerPage=5
            elseif key=="return" or key=="space" then
                if not CoopProgression.allowed(runtime,"lastStand.advance") then return true end
                if state.offerPage<#OFFER_LINES then state.offerPage=state.offerPage+1 else accept(state) end
            end
            return true
        end
        if state.mode=="escort" or state.mode=="returning" then
            if key=="space" or key=="return" then
                if state.mode=="escort" then enterScene(state,"backyard") else completeReturn(state) end
            end
            return true
        end
        if state.mode=="backyard" or state.mode=="interior" then
            if key=="e" or key=="return" then handleSceneAction(state)
            elseif key=="escape" then
                state.notice={text="The pinned-down critters are counting on you. The back door remains open.",timer=2.5}
            end
            return true
        end
        if state.mode=="shootout" then
            if key=="v" then Shootout.cycleFireMode(state.shootout); return true end
            if key=="escape" then
                if not CoopProgression.allowed(runtime,"lastStand.withdraw") then return true end
                if transition(state,'lastStand.withdraw') then return true end
                enterScene(state,"interior")
            elseif key=="r" then Shootout.reload(state.shootout,runtime.saveData)
            elseif key=="l" then Shootout.supply(state.shootout,runtime.saveData,Catalog)
            elseif key=="tab" then Shootout.cycleWeapon(state.shootout,runtime.saveData,Catalog)
            elseif key=="c" then Shootout.setCover(state.shootout,not state.shootout.ducking)
            elseif key=="return" and state.shootout.result=="retreat" then
                if CoopProgression.allowed(runtime,"lastStand.retry") and not transition(state,'lastStand.retry') then Shootout.retry(state.shootout) end
            elseif key=="space" then Shootout.setFireHeld(state.shootout,"keyboard",true,runtime.saveData,width,height,Catalog)
            end
            return true
        end
        if state.mode=="aftermath" and (key=="return" or key=="space" or key=="e") then
            beginReturn(state)
            return true
        end
        if state.mode=="aftermath" and (key=="t" or key=="escape") then enterScene(state,"interior"); return true end
        return state.capture==true
    end

    function service:keyreleased(key)
        local state=runtime.lastStand
        if state and state.mode=="shootout" and key=="space" then
            Shootout.setFireHeld(state.shootout,"keyboard",false)
        end
        return runtime.lastStand and runtime.lastStand.capture==true or false
    end

    function service:mousepressed(x,y,button,istouch,touchId)
        local state=runtime.lastStand
        if not state then return false end
        if context.inputPaused and context.inputPaused() then neutralizeShooter(state); return state.capture==true end
        if runtime.session and runtime.session.checkpointPending then return state.capture==true end
        if state.mode=="approach" and button==1 and state.arrival and state.arrival>0 and not busy() then
            x,y=WorldView.toWorld(x,y)
            if math.abs(x-state.scout.x)<95 and math.abs(y-state.scout.y+60)<100 then return self:keypressed("e") end
        end
        if not state.capture then return false end
        if state.paused then state.paused=false; return true end
        if state.treatment then finishTreatment(state,FirstAid.mousepressed(state.treatment,x,y)); return true end
        if state.handoff then return true end
        if state.mode=="offer" and button==1 then
            local ax,ay,aw,ah,dx,dy,dw,dh=offerButtons(width,height)
            if pointIn(x,y,ax,ay,aw,ah) then accept(state)
            elseif pointIn(x,y,dx,dy,dw,dh) then decline(state)
            elseif pointIn(x,y,ax,ay-58,aw,44) then state.offerPage=4
            elseif pointIn(x,y,dx,dy-58,dw,44) then state.offerPage=5
            else state.offerPage=math.min(#OFFER_LINES,state.offerPage+1) end
            return true
        end
        if (state.mode=="backyard" or state.mode=="interior") and button==1 then
            local px,py,pw,ph=Scene.pauseRect(width,height)
            if pointIn(x,y,px,py,pw,ph) then state.paused=true; return true end
            local rx,ry,rw,rh=Scene.actionRect(height)
            if pointIn(x,y,rx,ry,rw,rh) and handleSceneAction(state) then return true end
            Scene.setDestination(state.scene,WorldView.toWorld(x,y))
            return true
        end
        if state.mode=="shootout" then
            if sharedCommands() and state.shootout.result=='retreat' then
                local rx,ry,rw,rh=Shootout.retryRect(width,height)
                if button==1 and pointIn(x,y,rx,ry,rw,rh) then transition(state,'lastStand.retry') end
                return true
            end
            if istouch then
                if state.shootout.result=="retreat" and not CoopProgression.allowed(runtime,"lastStand.retry") then return true end
                local action=Shootout.touchAction(x,y,width,height)
                if action then
                    if action=="fire" then
                        state.fireTouchSources=state.fireTouchSources or {}
                        local fireId=touchId or "touch-action"
                        state.fireTouchSources[fireId]=true
                        Shootout.setFireHeld(state.shootout,"touch:"..tostring(fireId),true,runtime.saveData,width,height,Catalog)
                    elseif action=="ads" then Shootout.setADS(state.shootout,not state.shootout.gun.ads)
                    else self:keypressed(action) end
                    return true
                end
                if state.shootout.result=="retreat" or Shootout.needsSupply(state.shootout,runtime.saveData) then
                    return Shootout.mousepressed(state.shootout,x,y,1,runtime.saveData,Catalog,width,height)
                end
                Shootout.setTouchAim(state.shootout,x,y,width,height)
                return true
            end
            if state.shootout.result=="retreat" and not CoopProgression.allowed(runtime,"lastStand.retry") then return true end
            Shootout.setAim(state.shootout,x,y)
            return Shootout.mousepressed(state.shootout,x,y,button,runtime.saveData,Catalog,width,height)
        end
        if state.mode=="aftermath" and button==1 then
            local rx,ry,rw,rh=mainButton(width,height)
            if pointIn(x,y,rx,ry,rw,rh) then beginReturn(state) end
            if pointIn(x,y,rx,ry-58,rw,44) then enterScene(state,"interior") end
            return true
        end
        if (state.mode=="escort" or state.mode=="returning") and button==1 then return self:keypressed("space") end
        return true
    end

    function service:mousemoved(x,y)
        local state=runtime.lastStand
        if not state or not state.capture then return false end
        if state.paused then return true end
        if state.treatment then finishTreatment(state,FirstAid.mousemoved(state.treatment,x,y)); return true end
        if state.mode=="shootout" then Shootout.setAim(state.shootout,x,y) end
        return true
    end

    function service:mousereleased(x,y,button)
        local state=runtime.lastStand
        if not state or not state.capture then return false end
        if state.treatment then FirstAid.mousereleased(state.treatment,x,y); return true end
        if state.mode=="shootout" then return Shootout.mousereleased(state.shootout,button) end
        return true
    end

    function service:wheelmoved()
        return runtime.lastStand and runtime.lastStand.capture==true or false
    end

    function service:positionCommandState(id)
        if id~='host' and id~='companion' then return nil end
        local state=runtime.lastStand
        local combat=runtime.saveData and runtime.saveData.lastStand and runtime.saveData.lastStand.combat
        local owners=require('game.coop_last_stand_state')
        if not state or state.mode~='shootout' or not state.shootout or not combat
            or state.quest~=runtime.saveData.lastStand or owners.campaignOf(state.shootout)~=runtime.saveData
            or owners.record(state.shootout)~=combat then return nil end
        return {active=state.capture==true,paused=(id=='host' and (hostInputPaused(state) or state.treatment~=nil or state.handoff~=nil
                or state.pendingPosition~=nil)) or context.globalSimulationBlocked and context.globalSimulationBlocked() or false,
            encounterId=combat.entityId,phaseRevision=combat.phaseRevision}
    end
    function service:effectState()
        local state=runtime.lastStand; local data=runtime.saveData
        if not state or not data or state.quest~=data.lastStand or state.mode~='shootout' or not state.shootout
            or require('game.coop_last_stand_state').campaignOf(state.shootout)~=data then return nil end
        local result=Shootout.effectState(state.shootout); if not result then return nil end
        result.paused=result.paused or runtime.session and runtime.session.checkpointPending
            or context.globalSimulationBlocked and context.globalSimulationBlocked() or false
        return result
    end
    function service:stageState()
        local state=runtime.lastStand; local data=runtime.saveData
        local life=state and state.quest and state.quest.lifecycle
        if not state or state.capture~=true or not data or runtime.state~='game' or runtime.scene~='stop' or runtime.session
            and runtime.session.networkMode=='client' or state.quest~=data.lastStand or not life
            or state.mode~=life.mode or not ({offer=true,escort=true,aftermath=true,returning=true})[state.mode] then return nil end
        local result={questId=life.entityId,lifeRevision=life.revision,mode=state.mode,clock=state.clock or 0,
            paused=state.paused==true or context.inputPaused and context.inputPaused()
                or runtime.session and runtime.session.checkpointPending
                or context.globalSimulationBlocked and context.globalSimulationBlocked() or false}
        if state.mode=='offer' then
            local page=offerPage(state.offerPage or 1); if not page then return nil end
            result.offerPage=page.page
        end
        if state.scout then
            result.scout={x=state.scout.x,y=state.scout.y,walkDistance=state.walkDistance or 0,arrival=state.arrival or 0}
        end
        -- Only farmhouse scene poses use the logical stage viewport. Ordinary
        -- stop coordinates can lie outside it and are not needed by these
        -- passive cinematic views.
        local pose=state.scene and state.scene.player
        if pose then result.hostPose={x=pose.x,y=pose.y,facing=pose.facing==-1 and -1 or 1} end
        return result
    end
    function service:commandState(id)
        local result=self:positionCommandState(id); if not result then return nil end
        if id=='host' and sharedCommands() then
            local status=context.positionStatus and context.positionStatus(id)
            local owner=runtime.saveData.lastStand.combat.defenders[id]
            if not status or not owner or status.windowId~=owner.windowId
                or PositionState.selected(runtime.saveData,id)~=owner.windowId
                or (status.phaseRevision or status.domain and status.domain.phaseRevision)~=result.phaseRevision then return nil end
            result.windowId=status.windowId; result.leaseId=status.leaseId or status.id
        end
        return result
    end

    function service:progressionState()
        local state=runtime.lastStand
        local data=runtime.saveData
        local life=state and state.quest and state.quest.lifecycle
        if not data or not life or state.quest~=data.lastStand then return nil end
        local point=state.scene and state.scene.player
        local action=state.scene and Scene.action(state.scene,needsLoan(state.quest))
        local player=runtime.player
        local scoutReady=state.arrival and state.arrival>0 and player and state.scout
            and ((player.x-state.scout.x)^2+(player.y-state.scout.y)^2)<=10000
        return {active=true,questId=life.entityId,revision=life.revision,mode=state.mode,
            treatmentLeaseId=state.treatment and state.treatment.leaseId,
            personalPaused=state.paused==true or context.inputPaused and context.inputPaused() or false,
            paused=state.paused==true or state.treatment~=nil or context.inputPaused and context.inputPaused() or false,
            blocked=runtime.battle~=nil and runtime.battle~=false or runtime.encounter~=nil and runtime.encounter~=false
                or runtime.sleeping==true or runtime.firstAid~=nil and runtime.firstAid~=false
                or runtime.shootingRange~=nil and runtime.shootingRange~=false or runtime.outfitCraftingOpen==true
                or runtime.trainAmbush and runtime.trainAmbush.phase~='complete' or false,
            x=point and point.x,y=point and point.y,action=action and action.id,scoutReady=scoutReady==true,
            handoffWindow=state.handoff and state.handoff.window,handoffElapsed=state.handoff and state.handoff.elapsed}
    end
    function service:movementActor()
        local state=runtime.lastStand; local data=runtime.saveData
        if not sharedCommands() or not state or not state.scene or not data or state.quest~=data.lastStand
            or not Life.walking(data) or state.mode~=data.lastStand.lifecycle.mode then return nil end
        Life.bind(state.scene.player,data,'host',true)
        return state.scene.player
    end

    function service:isCapturing()
        return runtime.lastStand and runtime.lastStand.capture==true or false
    end

    function service:zoomField(x,y)
        local state=runtime.lastStand
        if not state or not state.capture then return nil end
        if state.mode=="shootout" and not state.paused and not state.treatment and not state.handoff
            and state.shootout.result~="retreat" and not Shootout.needsSupply(state.shootout,runtime.saveData) then
            if ShooterPad.hit(x,y,width,height) or Shootout.touchAction(x,y,width,height) then return nil end
            return state.shootout,true
        end
        return state,false
    end

    function service:touchpressed(id,x,y)
        local state=runtime.lastStand
        if not state then return false end
        if context.inputPaused and context.inputPaused() then neutralizeShooter(state); return state.capture==true end
        if runtime.session and runtime.session.checkpointPending then return state.capture==true end
        state.touchControls=true
        if state.mode=="shootout" then
            state.shootout.touchControls=true
            if state.aimTouchSession~=state.shootout then
                if state.aimPad then state.aimPad:cancel() end
                state.aimTouch=nil; state.aimTouchSession=state.shootout
            end
            state.aimPad=state.aimPad or ShooterPad.new()
            if not state.paused and not state.treatment and not state.handoff and not state.shootout.result
                and not Shootout.needsSupply(state.shootout,runtime.saveData) then
                local padAction=state.aimPad:press(id,x,y,width,height)
                if padAction then
                    if padAction=='aim' then state.aimTouch=id; state.shootout.gun.touchAim=nil
                    elseif padAction=='fire' then Shootout.setFireHeld(state.shootout,'pad',true,runtime.saveData,width,height,Catalog) end
                    return true
                end
            end
            if not state.paused and not state.treatment and not state.handoff
                and not Shootout.touchAction(x,y,width,height) and state.shootout.result~="retreat"
                and not Shootout.needsSupply(state.shootout,runtime.saveData) then
                if state.aimTouch then
                    if state.aimTouch~=id then
                        state.fireTouchSources=state.fireTouchSources or {}
                        state.fireTouchSources[id]=true
                        Shootout.setFireHeld(state.shootout,"touch:"..tostring(id),true,runtime.saveData,width,height,Catalog)
                    end
                else
                    state.aimTouch=id
                    Shootout.setTouchAim(state.shootout,x,y,width,height)
                end
                return true
            end
        end
        return self:mousepressed(x,y,1,true,id)
    end

    function service:touchmoved(id,x,y)
        local state=runtime.lastStand
        if not state or not state.capture then return false end
        if state.mode=="shootout" and not state.treatment then
            if state.aimPad and state.aimPad:move(id,x,y,width,height) then return true end
            if not state.paused and state.aimTouch==id and state.aimTouchSession==state.shootout then
                Shootout.setTouchAim(state.shootout,x,y,width,height)
            end
            return true
        end
        return self:mousemoved(x,y)
    end

    function service:touchreleased(id,x,y)
        local state=runtime.lastStand
        if not state then return false end
        local padAction=state.aimPad and state.aimPad:release(id)
        if padAction then
            if padAction=='fire' and state.shootout then Shootout.setFireHeld(state.shootout,'pad',false) end
            if state.aimTouch==id then state.aimTouch=nil end
            return true
        end
        if state.fireTouchSources and state.fireTouchSources[id] then
            state.fireTouchSources[id]=nil
            Shootout.setFireHeld(state.shootout,"touch:"..tostring(id),false)
        end
        if state.aimTouch==id then state.aimTouch=nil end
        return self:mousereleased(x,y,1)
    end

    function service:focus(focused)
        if not focused and runtime.lastStand and runtime.lastStand.capture then
            if runtime.lastStand.aimPad then runtime.lastStand.aimPad:cancel() end
            runtime.lastStand.aimTouch=nil
            if runtime.lastStand.shootout then
                runtime.lastStand.shootout.fireHeldSources={}
                runtime.lastStand.shootout.gun.fireHeld=false
            end
            runtime.lastStand.paused=true
            save()
        end
    end

    local function drawNotice(state)
        if not state.notice then return end
        love.graphics.setColor(.055,.035,.020,.94)
        love.graphics.rectangle("fill",width/2-285,height-126,570,48,8,8)
        love.graphics.setColor(.96,.84,.63,1)
        love.graphics.printf(state.notice.text,width/2-270,height-110,540,"center")
    end

    local function drawState()
        local state=runtime.lastStand
        if not state then return end
        if mobileEnabled() then
            state.touchControls=true
            if state.shootout then state.shootout.touchControls=true end
        end
        if state.mode=="approach" then Scene.drawApproach(state); return end
        if state.mode=="offer" then
            Scene.drawApproach(state)
            modalPanel("A LIGHT IN THE WINDOWS",OFFER_LINES[state.offerPage],width,height)
            local ax,ay,aw,ah,dx,dy,dw,dh=offerButtons(width,height)
            love.graphics.setColor(.46,.25,.10,1)
            love.graphics.rectangle("fill",ax,ay,aw,ah,8,8)
            love.graphics.setColor(.27,.20,.16,1)
            love.graphics.rectangle("fill",dx,dy,dw,dh,8,8)
            love.graphics.setColor(1,.88,.64,1)
            love.graphics.printf("ACCEPT  [Y]",ax,ay+17,aw,"center")
            love.graphics.printf("NOT NOW  [N]",dx,dy+17,dw,"center")
            love.graphics.setColor(.18,.12,.075,1)
            love.graphics.rectangle("fill",ax,ay-58,aw,44,8,8)
            love.graphics.rectangle("fill",dx,dy-58,dw,44,8,8)
            love.graphics.setColor(1,.88,.64,1)
            love.graphics.printf("DEFENSE OBJECTIVE  [Q]",ax,ay-43,aw,"center")
            love.graphics.printf("WEAPON SUPPLIES  [F]",dx,dy-43,dw,"center")
            love.graphics.setColor(.82,.70,.52,1)
            love.graphics.printf("Page "..state.offerPage.." / "..#OFFER_LINES,width/2-80,height/2+116,160,"center")
            return
        end
        if state.mode=="escort" then Scene.drawTransition(state,width,height,false,playerVisual()); return end
        if state.mode=="backyard" or state.mode=="interior" then
            local companion=context.companionSceneActor and context.companionSceneActor()
            Scene.draw(state.scene,width,height,playerVisual(),needsLoan(state.quest),state.touchControls,not state.paused,companion and {companion})
            drawNotice(state)
            if state.treatment then
                local assets={}
                local firstAid=context.scenery and context.scenery.firstAidAssets or {}
                for _,name in ipairs({"wound","disinfectant","rag","swab","gauze","bandage","bandageStrips"}) do
                    assets[name]=firstAid[name]
                end
                assets.npc=context.npcImages and context.npcImages["guard-fox.png"]
                FirstAid.draw(state.treatment,{},assets)
            end
            return
        end
        if state.mode=="shootout" then
            Shootout.draw(state.shootout,runtime.saveData,width,height)
            if state.touchControls and not state.paused and not state.shootout.result
                and not Shootout.needsSupply(state.shootout,runtime.saveData) then
                state.aimPad=state.aimPad or ShooterPad.new()
                state.aimPad:draw(width,height)
            end
            return
        end
        if state.mode=="aftermath" then
            Scene.draw(state.scene,width,height,playerVisual(),false)
            modalPanel(
                "THE RELAY GOES QUIET",
                "The gang has withdrawn. The defenders lower their weapons one by one. Reward: "..(state.quest.rewardScrap or 28).." scrap, 3 goodwill, and 2 food.",
                width,height,.64
            )
            local rx,ry,rw,rh=mainButton(width,height)
            love.graphics.setColor(.48,.26,.10,1)
            love.graphics.rectangle("fill",rx,ry,rw,rh,8,8)
            love.graphics.setColor(1,.88,.64,1)
            love.graphics.printf("RETURN TO THE STOP  [E]",rx,ry+17,rw,"center")
            love.graphics.setColor(.27,.20,.16,1)
            love.graphics.rectangle("fill",rx,ry-58,rw,44,8,8)
            love.graphics.setColor(1,.88,.64,1)
            love.graphics.printf("STAY A LITTLE LONGER  [T]",rx,ry-43,rw,"center")
            return
        end
        if state.mode=="returning" then Scene.drawTransition(state,width,height,true,playerVisual()) end
    end

    function service:draw()
        drawState()
        local state=runtime.lastStand
        local accessibility=runtime.saveData and Accessibility.ensure(runtime.saveData)
        if state and (state.woundFlash or 0)>0
            and not (accessibility and (accessibility.reducedFlashes or accessibility.reducedMotion)) then
            love.graphics.push("all")
            love.graphics.setColor(.76,.045,.025,.27*state.woundFlash/.45)
            love.graphics.rectangle("fill",0,0,width,height)
            love.graphics.pop()
        end
        if runtime.lastStand and runtime.lastStand.paused then
            modalPanel("PAUSED","Press P, Enter, or tap to return to the defense.",width,height)
        end
    end

    return service
end

return {new=Quest.new,version=VERSION,offerPage=offerPage,aftermathSummary=aftermathSummary}
