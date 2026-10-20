local Rules=require("game.train_ambush_rules")
local CoopProgression=require("game.coop_progression")
local Scene=require("game.train_ambush_scene")
local Shooting=require("game.first_person_shooting")
local Sessions=require('game.coop_shooter_sessions')
local GunCommands=require('game.coop_guns')
local ActorState=require('game.coop_ambush_state')
local Players=require('game.coop_players')
local WorldPause=require('game.world_pause')
local Typography=require("game.typography")
local Accessibility=require("game.accessibility")
local ShooterPad=require("game.mobile_shooter_controls")
local Ambush={}

function Ambush.new(context)
    local runtime,catalog=context.runtime,context.catalog
    local w,h=context.width,context.height
    local save=context.writeSave
    local service={}
    local bound,gun,data,impact,encounterId
    local held,touches={},{}
    local aimPad=ShooterPad.new()
    local touchControls=false
    local paused=false
    local saveClock=0
    local settlementPending=false
    local controllerFire,controllerADS=false,false
    local controllerReady=false
    local controllerPressed={}
    local controllerDomain
    local actions={
        {label="FIRE\nLMB / SPACE",key="space"},{label="AIM\nRMB",key="aim"},{label="RELOAD\nR",key="r"},
        {label="COVER\nC",key="c"},{label="WEAPON\nTAB",key="tab"},{label="MODE\nV",key="v"},
        {label="WITHDRAW\nX",key="withdraw"},{label="PAUSE\nP",key="p"},
    }
    local function rect(index)
        local width=(w-40)/#actions
        return {x=20+(index-1)*width,y=h-76,w=width-5,h=56}
    end
    local function inside(r,x,y) return x>=r.x and y>=r.y and x<=r.x+r.w and y<=r.y+r.h end
    local function label(text,x,y,width,height,scale)
        Typography.drawText(love.graphics,text,x,y,width,height,{scale=(scale or .8)*Accessibility.textScale(data),minScale=.7,align="center",valign="center"})
    end
    function service:isCapturing()
        local state=runtime.saveData and runtime.saveData.trainAmbush
        return runtime.state=="game" and type(state)=="table" and state.active==true
    end
    function service:suspend(preserveButtons)
        aimPad:cancel()
        held={}; touches={}; controllerFire=false; controllerADS=false; controllerReady=false
        if not preserveButtons then controllerPressed={} end
        if gun then Shooting.setADS(gun,false) end
    end
    local function localPaused() return paused or context.inputPaused and context.inputPaused() or false end
    function service:commandState(id)
        local current=runtime.saveData and runtime.saveData.trainAmbush
        if not self:isCapturing() or bound~=current then return nil end
        if id=='companion' then
            local ready=false
            for _,participant in ipairs(context.participants and context.participants() or {}) do if participant==id then ready=true end end
            if not ready then return nil end
        end
        return {active=true,encounterId=current.entityId,
            paused=settlementPending or (id=='companion' and not WorldPause.isSharedHost(runtime)) or (id~='companion' and localPaused())}
    end
    local function bind()
        if not service:isCapturing() then return false end
        if settlementPending then
            if not context.checkpointPending or context.checkpointPending() then return false end
            settlementPending=false
        end
        data=runtime.saveData
        local state=Rules.start(data)
        if bound~=state then
            if context.submit then
                local reply=context.submit('ambush.start',{encounterId=state.entityId})
                if not reply or not reply.ok or reply.savePending then service:suspend(); return false end
            end
            service:suspend()
            bound=state
            gun=Shooting.new(data,catalog,state,w,h)
            if encounterId~=state.entityId then paused=false end
            encounterId=state.entityId; saveClock=0; impact=nil
            runtime.dialogue=nil
        end
        runtime.trainAmbush=state
        local domain=tostring(state.entityId)..':'..state.phase
        if controllerDomain and controllerDomain~=domain then service:suspend() end
        controllerDomain=domain
        return true
    end
    local function aim(x,y,touch)
        if not gun then return end
        if touch then Shooting.setTouchAim(gun,x,y,w,h)
        else Shooting.setAim(gun,math.max(0,math.min(w,x)),math.max(0,math.min(h,y))) end
    end
    local function command(name,args)
        if not context.submit then return nil end
        args=args or {}; args.mode='ambush'; args.encounterId=bound.entityId
        if name~='gun.cover' then args.weaponId=args.weaponId or gun.itemId end
        local reply=context.submit(name,args)
        if reply.ok and bound.weaponSession and Sessions.record(gun)~=bound.weaponSession then
            local x,y,ads=gun.aimX,gun.aimY,gun.ads
            gun=Sessions.view(bound.weaponSession,w,h)
            Shooting.setAim(gun,x,y); Shooting.setADS(gun,ads)
        end
        return reply
    end
    local function fire()
        if localPaused() or bound.phase~="combat" or bound.cover or bound.coverProgress>0 then return end
        if not Scene.pointOpen(bound,w,h,gun.aimX,gun.aimY) then return end
        if context.submit then
            local reply=command('gun.fire',{x=math.floor(gun.aimX/w*GunCommands.POINT+.5),y=math.floor(gun.aimY/h*GunCommands.POINT+.5)})
            if not reply.ok then
                if reply.reason=='reload' then command('gun.reload') end
                return
            end
            if reply.result.hit then impact={x=gun.aimX,y=gun.aimY,time=.22} end
            if reply.durable then Shooting.playReport(gun.weapon,catalog,data) end
            return
        end
        local fired,reason=Shooting.fire(gun,data,bound)
        if not fired then
            if reason=="reload" then Shooting.reload(gun,data,bound); save() end
            return
        end
        bound.shots=bound.shots+1
        Shooting.playReport(gun.weapon,catalog,data)
        local target=Scene.target(bound,w,h,gun.aimX,gun.aimY)
        if Rules.hit(data,bound,target,gun) then impact={x=gun.aimX,y=gun.aimY,time=.22} end
        save()
    end
    local function fireHeld(source,down)
        local previous=held[source]
        held[source]=down or nil
        if down and not previous then fire() end
    end
    local function cycleWeapon()
        local options={}
        for _,entry in ipairs(Shooting.weaponOptions(data,catalog)) do
            if not entry.borrowed then options[#options+1]=entry end
        end
        if #options==0 then return end
        local selected=0
        for i,entry in ipairs(options) do if entry.name==gun.weapon and entry.itemId==gun.itemId then selected=i; break end end
        service:suspend()
        if context.submit then command('gun.select',{weaponId=options[selected%#options+1].itemId})
        else gun=Shooting.chooseWeapon(gun,options[selected%#options+1],data,catalog,bound); save() end
    end
    local function continueJourney()
        if not CoopProgression.allowed(runtime,"ambush.continue") then return false,"host_only" end
        if context.submit then
            local reply=context.submit('ambush.continue',{encounterId=bound.entityId})
            if not reply or not reply.ok then return false,reply and reply.reason or 'ambush_unavailable' end
            service:suspend()
            if not reply.savePending then bound=nil; gun=nil; runtime.trainAmbush=nil; Scene.release(); Shooting.release() end
            return true
        end
        bound.active=false
        runtime.trainAmbush=nil
        service:suspend()
        bound=nil; gun=nil
        Scene.release(); Shooting.release()
        context.enterStop()
        save()
    end
    local function action(key)
        if key=="kpenter" then key="return" end
        if key=="p" then paused=not paused; service:suspend(); save(); return end
        if paused then
            if key=="return" or key=="space" then paused=false; service:suspend() end
            return
        end
        if bound.phase=="result" then
            if key=="return" then continueJourney() end
            return
        end
        if key=="withdraw" or key=="x" then
            if not CoopProgression.allowed(runtime,"ambush.withdraw") then return false,"host_only" end
            if context.submit then
                local reply=context.submit('ambush.withdraw',{encounterId=bound.entityId})
                if reply and reply.ok then service:suspend() end
                return reply and reply.ok or false,reply and reply.reason
            end
            if Rules.withdraw(data,bound) then service:suspend(); save() end
        elseif key=="c" then
            service:suspend()
            if context.submit then command('gun.cover',{cover=not bound.cover}) else bound.cover=not bound.cover; save() end
        elseif key=="r" then
            if context.submit then command('gun.reload') else Shooting.reload(gun,data,bound); save() end
        elseif key=="tab" then cycleWeapon()
        elseif key=="v" then
            if context.submit then service:suspend(); command('gun.mode') else Shooting.cycleFireMode(gun); save() end
        elseif key=="aim" and not bound.cover then Shooting.setADS(gun,not gun.ads)
        elseif key=="space" then fireHeld("keyboard",true) end
    end
    function service:keypressed(key,_,isrepeat)
        if not bind() then return false end
        if not isrepeat then action(key) end
        return true
    end
    function service:keyreleased(key)
        if not self:isCapturing() then return false end
        if key=="space" then fireHeld("keyboard",false) end
        return true
    end
    function service:mousepressed(x,y,button,istouch)
        if not bind() then return false end
        if istouch then return true end
        if button==1 then
            if bound.phase=="result" then
                if inside({x=w/2-130,y=h*.61,w=260,h=58},x,y) then continueJourney() end
                return true
            end
            if paused then action("return"); return true end
            for i,item in ipairs(actions) do
                if inside(rect(i),x,y) then
                    if item.key=="space" then fireHeld("mouse",true) else action(item.key) end
                    return true
                end
            end
            aim(x,y); fireHeld("mouse",true)
        elseif button==2 and not paused and not bound.cover then aim(x,y); Shooting.setADS(gun,true) end
        return true
    end
    function service:mousemoved(x,y,_,_,istouch)
        if not bind() then return false end
        if not istouch and not paused and y<h-100 then aim(x,y) end
        return true
    end
    function service:mousereleased(_,_,button)
        if not self:isCapturing() then return false end
        if button==1 then fireHeld("mouse",false)
        elseif button==2 and gun then Shooting.setADS(gun,false) end
        return true
    end
    function service:touchpressed(id,x,y)
        if not bind() then return false end
        if context.inputPaused and context.inputPaused() then self:suspend(); return true end
        touchControls=true
        if paused or bound.phase=="result" then return self:mousepressed(x,y,1,false) end
        local padAction=aimPad:press(id,x,y,w,h)
        if padAction then
            if padAction=='aim' then gun.touchAim=nil
            elseif padAction=='fire' then fireHeld('pad',true) end
            return true
        end
        for i,item in ipairs(actions) do
            if inside(rect(i),x,y) then
                touches[id]=item.key
                if item.key=="space" then fireHeld("touch:"..tostring(id),true) else action(item.key) end
                return true
            end
        end
        touches[id]="aimdrag"; aim(x,y,true)
        return true
    end
    function service:touchmoved(id,x,y)
        if not self:isCapturing() then return false end
        if aimPad:move(id,x,y,w,h) then return true end
        if touches[id]=="aimdrag" and not paused then aim(x,y,true) end
        return true
    end
    function service:touchreleased(id)
        if not self:isCapturing() then return false end
        local padAction=aimPad:release(id)
        if padAction then if padAction=='fire' then fireHeld('pad',false) end; return true end
        if touches[id]=="space" then fireHeld("touch:"..tostring(id),false) end
        touches[id]=nil
        return true
    end
    function service:gamepadpressed(_,button)
        if not bind() then return false end
        if controllerPressed[button] or context.inputPaused and context.inputPaused() then return true end
        local key,id=context.controlBindings:translateButton(button,"last_stand_shootout")
        if id~='ls_pause' and (bound.phase=='result' or paused) then
            key=context.controlBindings:translateButton(button,'menu')
            if key~='return' then key=nil end
        elseif key=='escape' then key='withdraw' end
        if not key then return true end
        local domain=controllerDomain
        if key=='space' then fireHeld('gamepad:'..button,true) else action(key) end
        -- Actions can suspend or replace the scene. Never retain a hold from
        -- an obsolete encounter; pause still requires release before toggling.
        if bound and controllerDomain==domain then controllerPressed[button]={key=key,domain=domain} end
        return true
    end
    function service:gamepadreleased(_,button)
        if not self:isCapturing() then return false end
        local previous=controllerPressed[button]; controllerPressed[button]=nil
        if previous and previous.key=='space' then fireHeld('gamepad:'..button,false) end
        return true
    end
    function service:focus(focused)
        if not focused and self:isCapturing() then paused=true; self:suspend(); save() end
    end
    function service:update(dt)
        if not CoopProgression.allowed(runtime,"ambush.continue") then return self:isCapturing() end
        if not bind() then
            if bound then self:suspend(); bound=nil; gun=nil; runtime.trainAmbush=nil; Scene.release(); Shooting.release() end
            return false
        end
        dt=math.min(dt,.1)
        local shared=WorldPause.isSharedHost(runtime)
        local inputPaused=localPaused()
        if inputPaused then self:suspend(paused and not (context.inputPaused and context.inputPaused())) end
        if not shared and inputPaused or bound.phase=="result" then return true end
        local ids=context.participants and context.participants() or {'host'}
        if shared then
            local readyIds={}
            for _,id in ipairs(ids) do
                if id~='host' or not inputPaused then readyIds[#readyIds+1]=id end
            end
            ids=readyIds
            -- A private host menu must leave a ready friend playing, while
            -- admission/restart with nobody ready must not consume the convoy
            -- or its personal timers behind inaccessible controls.
            if #ids==0 then self:suspend(); return true end
        end
        for _,id in ipairs(ids) do
            if id=='companion' and data.players and data.players.companion then
                ActorState.owner(bound,id,true)
                local own=Players.forActor(data,id); local scope=Sessions.scope(own,bound)
                if not scope.weaponSession then Shooting.new(own,catalog,bound,w,h) end
            end
        end
        local bindings=context.controlBindings
        if not inputPaused then
            local x,y=aimPad:step(dt,gun,w,h)
            if x then aim(x,y) end
        end
        local dx,dy=0,0
        if not inputPaused then dx,dy=bindings:axisValue("aim_x"),bindings:axisValue("aim_y") end
        if dx~=0 or dy~=0 then aim(gun.aimX+dx*340*dt,gun.aimY+dy*340*dt) end
        local firing,ads=false,false
        if not inputPaused then firing,ads=bindings:axisValue("fire")>.4,bindings:axisValue("ads")>.4 end
        if not firing and not ads then controllerReady=true end
        if controllerReady then
            if firing~=controllerFire then fireHeld("controller",firing) end
            if ads~=controllerADS and not bound.cover then Shooting.setADS(gun,ads) end
            controllerFire,controllerADS=firing,ads
        end
        if data.players then ActorState.updateGuns(data,bound,dt,w,h) else Shooting.update(gun,dt,data,bound,w,h) end
        if gun.fireMode=="auto" and next(held) then fire() end
        if impact then impact.time=impact.time-dt end
        local previousOutcome=bound.outcome
        local changed=Rules.update(data,bound,dt,function()
            Shooting.playReport("frontier-22-lever-rifle",catalog,data,true)
        end,ids)
        if not previousOutcome and bound.outcome and context.checkpointSettlement then
            settlementPending=context.checkpointSettlement()~=true
            self:suspend()
            if settlementPending then return true end
        end
        saveClock=saveClock+dt
        if changed or saveClock>=1 then saveClock=0; save() end
        return true
    end
    function service:draw()
        if not bind() then return false end
        local g=love.graphics
        g.push("all")
        g.setFont(Typography.font(g))
        Scene.draw(bound,w,h,Accessibility.ensure(data),impact)
        if bound.coverProgress==0 and bound.phase~="result" then
            Shooting.draw(gun,w,h)
            if not gun.ads then
                g.setColor(1,.94,.75,1)
                local x,y=gun.aimX,gun.aimY
                g.line(x-9,y,x-3,y); g.line(x+3,y,x+9,y); g.line(x,y-9,x,y-3); g.line(x,y+3,x,y+9)
            end
        end
        -- All interface elements are drawn after the window and weapon art.
        g.setColor(.035,.025,.02,.94); g.rectangle("fill",16,12,w-32,54,6,6)
        g.setColor(1,.89,.68,1)
        label("HEALTH "..math.ceil(data.health or 20).." / "..(data.maxHealth or 20),22,17,205,42)
        label("CARRIAGE "..bound.protection.." / "..bound.maxProtection,232,17,235,42)
        local hull,maxHull=Rules.hullTotal(bound)
        label("CONVOY "..math.ceil(hull).." / "..maxHull,480,17,235,42)
        label("BANDITS "..Rules.crewTotal(bound),730,17,w-750,42)
        g.setColor(.035,.025,.02,.94); g.rectangle("fill",0,h-143,w,143)
        g.setColor(1,.89,.68,1)
        local name=(gun.weapon or "No firearm"):gsub("%-"," "):upper()
        local status=gun.reloadTimer>0 and "RELOADING" or gun.fireMode or ""
        label(name.."   "..(gun.magazine or 0).." / "..Shooting.rounds(gun,data,bound).." ROUNDS   "..status:upper(),25,h-141,w-50,29,.77)
        local hint=bound.phase=="approach" and "The bandit convoy is pulling alongside."
            or bound.phase=="depart" and "The bandit convoy is falling behind."
            or bound.cover and "IN COVER - the carriage is still taking fire."
            or "Disable the convoy or stop its bandits. Withdrawal costs 6 train condition."
        if bound.phase=="combat" and not Shooting.hasUsableFirearm(data,catalog) then hint="No ammunition remaining. Switch weapons or withdraw." end
        label(hint,30,h-111,w-60,30,.72)
        for i,item in ipairs(actions) do
            local r=rect(i)
            g.setColor(.12,.075,.035,.96); g.rectangle("fill",r.x,r.y,r.w,r.h,5,5)
            g.setColor(.73,.49,.22,1); g.rectangle("line",r.x,r.y,r.w,r.h,5,5)
            g.setColor(1,.89,.68,1); label(item.label,r.x+2,r.y+2,r.w-4,r.h-4,.69)
        end
        if not paused and bound.phase~='result' and (touchControls or context.mobileEnabled and context.mobileEnabled()) then aimPad:draw(w,h) end
        if paused or bound.phase=="result" then
            g.setColor(0,0,0,.8); g.rectangle("fill",0,0,w,h)
            g.setColor(1,.89,.68,1)
            if paused then
                label("PAUSED",100,h*.3,w-200,60,1.3)
                label(WorldPause.isSharedHost(runtime) and "Your controls are paused. Your friend can keep playing.\nP / START to resume. Tap to resume."
                    or "P / START to resume. Tap to resume.",100,h*.45,w-200,55)
            else
                local won=bound.outcome=="disabled" or bound.outcome=="crew"
                label(won and "BANDITS DRIVEN OFF" or "ENCOUNTER ENDED",90,h*.27,w-180,60,1.25)
                local text=string.format("Salvage: %d scrap\nHealth lost: %d   Train condition lost: %d\nShots fired: %d",bound.reward or 0,bound.playerDamage,bound.trainDamage,bound.shots)
                label(text,120,h*.37,w-240,120,.95)
                g.setColor(.22,.13,.06,1); g.rectangle("fill",w/2-130,h*.61,260,58,6,6)
                g.setColor(1,.89,.68,1); label("CONTINUE  [ENTER / A]",w/2-125,h*.61,250,58,.85)
            end
        end
        g.pop()
        return true
    end
    return service
end
return Ambush
