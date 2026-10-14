-- Two ordinary Source applications and real ENet; private fixture saves only.
-- Desktop/mobile callback acceptance is not physical Android verification.
local Helpers={}
function Helpers.canonical(value)
    if type(value)~='table'then return type(value)..':'..tostring(value)end
    local keys={};for key in pairs(value)do keys[#keys+1]=key end
    table.sort(keys,function(a,b)return type(a)..tostring(a)<type(b)..tostring(b)end)
    local out={'{'};for _,key in ipairs(keys)do
        out[#out+1]=Helpers.canonical(key)..'='..Helpers.canonical(value[key])..';'
    end;out[#out+1]='}';return table.concat(out)
end
function Helpers.costEqual(a,b)
    for _,key in ipairs({'from','to','food','water','coal','terrain','sourceRevision','passengers',
        'passengerLoad','maintenanceCoal','navigatorSaved','affordable'})do if a[key]~=b[key]then return false end end
    return Helpers.canonical(a.available)==Helpers.canonical(b.available)
        and Helpers.canonical(a.missing)==Helpers.canonical(b.missing)
end
function Helpers.ready(lp)
    local v=lp.clientView;local n=lp.network;local f=lp.motionFrame
    return v and n and not n.closed and n.status=='ready' and v.ready and not v.paused
        and f and f.ready and not f.paused and f.sessionId==n.sessionId and f.sceneEpoch==v.epoch
        and f.motionId==v.motionId and f.serial==v.lastSerial and f.domain==v.modalDomain
        and not v.prediction:stale()
end
function Helpers.diffPaths(a,b)
    local paths={}
    local function walk(left,right,path,depth)
        if #paths>=256 then return end
        if type(left)~=type(right) or type(left)~='table'then
            if left~=right then paths[#paths+1]=path end;return
        end
        if depth>=40 then paths[#paths+1]=path;return end
        local keys={};for key in pairs(left)do keys[key]=true end;for key in pairs(right)do keys[key]=true end
        local sorted={};for key in pairs(keys)do sorted[#sorted+1]=key end
        table.sort(sorted,function(x,y)return type(x)..tostring(x)<type(y)..tostring(y)end)
        for _,key in ipairs(sorted)do walk(left[key],right[key],path..'.'..tostring(key),depth+1)end
    end
    walk(a,b,'campaign',0);return paths
end
function Helpers.hostSettled(lp)
    local n=lp.network;local m=lp.motion;local a=lp.authority;local link=n and n.link
    return a and not a.pendingSave and link and link.admitted and link.phase=='ready'
        and a.bindings.companion==link.generation and m and m.generation==link.generation
        and m.readyEpoch==a.campaign.coop.sceneEpoch and m.actor and not m.actor.moving
        and (not m.input or m.input.x==0 and m.input.y==0)
end
function Helpers.wireReady(now,last)return last==nil or now-last>=.6 end
if rawget(_G,'TRAVEL_FIXTURE_HELPERS')then return Helpers end
io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save');local Codec=require('game.net.codec');local P=require('game.net.protocol')
local Viewport=require('game.viewport');local Requests=require('game.coop_travel_requests')
local app,c,stage,started,finished,capture,capturePending,baseline,quote,requestBytes,requestId,serial
local captured={};local facts={physicalAndroid=false,touchCallbacks=touch};local writes=0
local lastReport=0;local moveAt,moveX,movementHeld,departAt
local keyboardQuery
local lastWireAt
local baselineCampaign,settling,settlingCampaign,stableAt,commandCount= nil,nil,nil,nil,0
local writeEvents={};local focusEvents={}
local limits={maxBytes=524288,maxDepth=32,maxEntries=200000,maxStringBytes=8192}
local function check(value,message)assert(value,message)end
local function file(name,value)
    local f=io.open(root..'/'..name,value~=nil and 'wb' or 'rb');if not f then return nil end
    local result=value~=nil and f:write(tostring(value)) or f:read('*a');f:close();return result
end
local function json(name,value)file(name,assert(Codec.encode(value,limits)))end
local function readJson(name)local bytes=file(name);return bytes and assert(Codec.decode(bytes,limits))end
local function hash(bytes)return love.data.encode('string','hex',love.data.hash('sha256',assert(bytes)))end
local function snapshot()
    local lp=c.ui.localPlay;local d=c.runtime.saveData;local a=assert(lp.authority,'missing live host authority')
    return {campaignHash=hash(Helpers.canonical(d)),diskHash=hash(love.filesystem.read(Save.path(99))),
        revision=d.coop.revision,epoch=d.coop.sceneEpoch,rngHash=hash(Helpers.canonical(d.coop.randomState)),
        randomSeed=a.randomSeed,resources=require('game.save_schema').copy(d.resources),writes=writes}
end
local function unchanged()
    local current=snapshot()
    if Helpers.canonical(current)~=Helpers.canonical(baseline)then
        json('host.mutation-diagnostic.json',{stage=stage,before=baseline,after=current,
            changedPaths=Helpers.diffPaths(baselineCampaign,c.runtime.saveData),writeEvents=writeEvents,focusEvents=focusEvents})
        print('LAN_TRAVEL_CHANGED_PATHS '..table.concat(Helpers.diffPaths(baselineCampaign,c.runtime.saveData),','))
    end
    check(Helpers.canonical(current)==Helpers.canonical(baseline),
        'inspection/request/dismiss/replay mutated campaign, RNG, resources, revision, epoch or disk')
end
local function coords(x,y)local ox,oy,sx,sy=Viewport.transform(960,720);return ox+x*sx,oy+y*sy end
local function key(value)app.keypressed(value);app.keyreleased(value)end
local function press(rect)
    check(rect and rect.enabled~=false,'missing/disabled production control '..tostring(stage))
    local x,y=coords(rect.x+rect.w/2,rect.y+rect.h/2)
    if touch then app.touchpressed('travel-control',x,y);app.touchreleased('travel-control',x,y)
    else app.mousepressed(x,y,1,false);app.mousereleased(x,y,1,false)end
end
local function menu()if not c.ui.localPlay.menuOpen then key('f8')end end
local function click(name,text)
    app.draw();press(c.ui.localPlayControls[name]);if text then app.textinput(text);key('return')end
end
local function back()if c.ui.localPlay.menuOpen then click('close')end end
local function photo(name)check(not capture and not capturePending,'overlapping travel captures');capture=name end
local function finish()
    if finished then return end;json(role..'.facts.json',facts)
    if keyboardQuery then love.keyboard.isDown=keyboardQuery;keyboardQuery=nil end
    check(app.quit()~=true,'travel fixture quit cancelled');finished=true
    print('LAN_SMOKE_OK role='..role..' application=true travel=true inspection=true request=true'
        ..' replay=true cooldown=true hostOnlyStory=true departure=true movementRecovered=true'
        ..' physicalAndroid=false input='..(touch and 'touch' or 'desktop'));love.event.quit(0)
end
local function load()
    started=love.timer.getTime();lastReport=started
    require('game.smoke_playthrough').install=function(value)c=value end
    app=require('game.application_composition').new({engine=love});app.installSmoke();app.load()
    local originalFocus=app.focus
    app.focus=function(focused,...)
        focusEvents[#focusEvents+1]={focused=focused==true,stage=stage or 'load',at=love.timer.getTime()-started}
        return originalFocus(focused,...)
    end
    -- Root key callbacks do not synthesize the OS polling state. Supply only
    -- our owned held key; gameplay still uses its real readiness/input gates.
    keyboardQuery=love.keyboard.isDown
    love.keyboard.isDown=function(...)
        if role=='guest' and not touch and movementHeld then
            for _,value in ipairs({...})do if value=='d'then return true end end
        end
        return keyboardQuery(...)
    end
    local lp=c.ui.localPlay;lp.context.bind='127.0.0.1'
    if role=='host'then
        Save.remove(99);c.runtime.selectedSlot=99
        check(c.enterGame(c.newSave(c.characters[1])),'ordinary new-save failed')
        check(c.runtime.saveData.location==1 and c.runtime.scene=='train','fixture changed normal first stop')
        menu();click('port',port);click('host');check(lp.network,'hosting failed '..tostring(lp.error))
        local command=lp.network.context.command
        lp.network.context.command=function(...)
            local before=snapshot();local campaign=assert(require('game.save_schema').copy(c.runtime.saveData))
            local reply=command(...);commandCount=commandCount+1
            local after=snapshot();local paths=Helpers.diffPaths(campaign,c.runtime.saveData)
            json('host.command-'..commandCount..'.json',{stage=stage,before=before,after=after,
                changedPaths=paths,ok=reply and reply.ok==true,reason=reply and reply.reason,
                requestId=reply and reply.requestId})
            check(Helpers.canonical(before)==Helpers.canonical(after),
                'actual synchronous guest command changed host campaign, RNG, revision, resources or save')
            return reply
        end
        stage='hosting';print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots';menu();click('address','127.0.0.1:'..port)
        click('name','Travel companion');click('join');stage='joining'
    end
end
local function hostUpdate(now)
    local lp=c.ui.localPlay;local commands=lp.context.commands
    if lp:pending()then menu();click('approve');check(not lp.error,'admission failed '..tostring(lp.error));back()end
    if stage=='hosting' and file('guest.connected')then
        back();stage='settling'
    elseif stage=='settling' and Helpers.hostSettled(lp)then
        local current=snapshot()
        if not settling or Helpers.canonical(current)~=Helpers.canonical(settling)then
            if settlingCampaign then
                json('host.background-settling.json',{before=settling,after=current,
                    changedPaths=Helpers.diffPaths(settlingCampaign,c.runtime.saveData),writeEvents=writeEvents,focusEvents=focusEvents})
            end
            settling=current;settlingCampaign=assert(require('game.save_schema').copy(c.runtime.saveData));stableAt=now
        elseif now-stableAt>=.5 then
        baseline=current;baselineCampaign=assert(require('game.save_schema').copy(c.runtime.saveData));quote=Requests.inspect(c.runtime.saveData,c.catalog)
        check(quote.affordable,'ordinary starter supplies cannot cover first leg')
        json('host.baseline.json',baseline);json('host.quote.json',quote);file('host.ready',true);stage='inspection'
        end
    elseif stage=='settling'then settling=nil;settlingCampaign=nil;stableAt=nil
    elseif stage=='inspection' and file('guest.inspected')then
        unchanged();facts.inspectionUnchanged=true;file('host.inspection.verified',true);stage='request'
    elseif stage=='request' and file('guest.requested')then
        local notice=commands.travelRequest()
        if notice then
            unchanged();serial=notice.serial;check(Helpers.costEqual(notice,quote),'host banner costs differ from real inspection')
            file('host.notice',serial);stage='same-pending'
        end
    elseif stage=='same-pending' and file('guest.same-pending')then
        unchanged();local a=commands.authority();local store=a.activityState.travelRequests
        check(store.pending and store.pending.serial==serial and store.nextSerial==serial+1,'duplicate created another banner')
        app.draw();press({x=706,y=84,w=28,h=28});check(not commands.travelRequest(),'actual dismiss did not clear banner')
        unchanged();file('host.dismissed',true);stage='cooldown'
    elseif stage=='cooldown' and file('guest.cooldown')then
        unchanged();check(not commands.travelRequest(),'replay resurrected dismissed banner')
        facts.requestReplayDismissUnchanged=true;facts.oneSerialForDuplicate=true;facts.cooldown=true
        file('host.replay.verified',true);stage='second-notice'
    elseif stage=='second-notice' and file('guest.second-request')then
        local notice=commands.travelRequest()
        if notice then
            unchanged();check(notice.serial==serial+1,'fresh request did not create one new serial')
            photo('host-travel-request.png');stage='banner-capture'
        end
    elseif stage=='banner-capture' and captured['host-travel-request.png'] and file('guest.panel-captured')then
        unchanged();file('host.probe.ready',true);stage='story-denial'
    elseif stage=='story-denial' and file('guest.story-denied')then
        unchanged();app.draw()
        if touch and not c.ui.travel then
            local mobile=c.getMobileControls();press(require('game.ui_layout').transformRectFor('mobileControls',mobile:uiBounds(),mobile.menu));app.draw()
        end
        press(c.ui.travel);check(c.runtime.travelConfirm,'actual host travel button did not open confirmation')
        photo('host-travel-confirmation.png');stage='confirm'
    elseif stage=='confirm' and captured['host-travel-confirmation.png']then
        unchanged();app.draw();press(c.ui.travelYes)
        local d=c.runtime.saveData;check(d.coop.journey and d.coop.journey.phase=='departed','actual host confirmation failed')
        check(d.coop.sceneEpoch==baseline.epoch+1,'departure epoch not committed exactly once')
        for _,name in ipairs({'food','water','coal'})do check(d.resources[name]==baseline.resources[name]-quote[name],'departure payment mismatch '..name)end
        check(writes==baseline.writes+1,'departure did not checkpoint exactly once')
        check(not commands.travelRequest(),'departure retained stale request')
        local paid=require('game.save_schema').copy(d.resources);json('host.departed.json',{epoch=d.coop.sceneEpoch,resources=paid})
        file('host.departed',true);departAt=now;facts.hostDeparturePaidOnce=true;stage='arrival'
    elseif stage=='arrival' and c.runtime.saveData.location==2 and not c.runtime.saveData.coop.journey and not c.runtime.travelTransition then
        local d=c.runtime.saveData;local paid=readJson('host.departed.json')
        for _,name in ipairs({'food','water','coal'})do check(d.resources[name]==paid.resources[name],'arrival paid departure again '..name)end
        facts.partyArrived=true;file('host.arrived',true);stage='movement'
    elseif stage=='movement' and file('guest.moved')then
        local marker=readJson('guest.moved');local actor=lp.motion and lp.motion.actor
        if actor and math.abs(actor.x-marker.startX)>.5 then
            check(c.runtime.saveData.location==2,'guest movement advanced story');facts.guestMovementRecovered=true
            file('host.movement.verified',true);stage='ending'
        end
    elseif stage=='ending' and file('guest.returned')then menu();click('stop');finish()end
end
local function openTravel(v)
    app.draw();if touch then press(v.ui.guestTravel)else key('v')end
    check(v.travel.opened and v.travel.pending,'actual guest travel input did not inspect')
    lastWireAt=love.timer.getTime()
end
local function requestTravel(v)
    app.draw();if touch then press(v.travel.controls[1])else key('return')end
    check(v.travel.pending and v.travel.pending.action=='depart','actual request input did not submit')
    local pending=c.ui.localPlay.network.pendingCommand
    lastWireAt=love.timer.getTime()
    return pending.requestId,pending.bytes
end
local function response(n,id)return n.lastCommandResult and n.lastCommandResult.requestId==id and n.lastCommandResult end
local function guestUpdate(now)
    local lp=c.ui.localPlay;local v=lp.clientView;local n=lp.network
    if stage=='joining' and Helpers.ready(lp)then
        back();file('guest.connected',true);stage='open'
    elseif stage=='open' and file('host.ready') and Helpers.ready(lp) and v:inputAllowed()then
        quote=readJson('host.quote.json');openTravel(v);stage='inspect'
    elseif stage=='inspect' and v.travel.model and not v.travel.pending then
        check(Helpers.costEqual(v.travel.model,quote),'guest received incorrect host travel cost')
        check(not v:inputAllowed(),'open private travel panel allowed world movement')
        file('guest.inspected',true);stage='request'
    elseif stage=='request' and file('host.inspection.verified') and Helpers.ready(lp) and v.travel:domain(false)
        and Helpers.wireReady(now,lastWireAt)then
        requestId,requestBytes=requestTravel(v);stage='requested'
    elseif stage=='requested' and response(n,requestId) and not v.travel.pending then
        local result=response(n,requestId);check(result.ok and not result.durable and result.details.requested,'request failed '..tostring(result.reason))
        serial=result.details.serial;stage='first-replay'
    elseif stage=='first-replay' and Helpers.wireReady(now,lastWireAt)then
        check(n.transport:sendToServer(requestBytes,P.CONTROL,true),'exact duplicate ENet send failed')
        lastWireAt=now
        file('guest.requested',true);stage='same-pending'
    elseif stage=='same-pending' and file('host.notice') and Helpers.ready(lp) and v.travel:domain(false)
        and Helpers.wireReady(now,lastWireAt)then
        requestId=requestTravel(v);stage='same-result'
    elseif stage=='same-result' and response(n,requestId) and not v.travel.pending then
        local result=response(n,requestId);check(result.ok and result.details.already and result.details.serial==serial,'same pending request created new notice')
        file('guest.same-pending',true);stage='dismissed'
    elseif stage=='dismissed' and file('host.dismissed') and Helpers.ready(lp) and v.travel:domain(false)
        and Helpers.wireReady(now,lastWireAt)then
        check(n.transport:sendToServer(requestBytes,P.CONTROL,true),'dismissed exact replay send failed')
        lastWireAt=now;stage='cooldown-ready'
    elseif stage=='cooldown-ready' and Helpers.ready(lp) and v.travel:domain(false)
        and Helpers.wireReady(now,lastWireAt)then
        requestId=requestTravel(v);stage='cooldown-result'
    elseif stage=='cooldown-result' and response(n,requestId) and not v.travel.pending then
        local result=response(n,requestId);check(not result.ok and result.reason=='request_cooldown','fresh dismissed request bypassed cooldown '..tostring(result.reason))
        file('guest.cooldown',true);stage='cooldown-wait';moveAt=now
    elseif stage=='cooldown-wait' and file('host.replay.verified') and now-moveAt>Requests.COOLDOWN+.2
        and Helpers.ready(lp) and v.travel:domain(false)then
        requestId=requestTravel(v);stage='second-result'
    elseif stage=='second-result' and response(n,requestId) and not v.travel.pending then
        check(response(n,requestId).ok,'request after cooldown failed');file('guest.second-request',true)
        photo('guest-travel-inspection-request.png');stage='panel-capture'
    elseif stage=='panel-capture' and captured['guest-travel-inspection-request.png']then
        file('guest.panel-captured',true);stage='story-probe'
    elseif stage=='story-probe' and file('host.probe.ready') and Helpers.ready(lp)then
        requestId=assert(n:submitCommand('travel.depart',{},v.epoch,{['world:scene']=v.runtime.saveData.coop.revisions['world:scene'] or 0}))
        stage='story-result'
    elseif stage=='story-result' and response(n,requestId)then
        check(not response(n,requestId).ok and response(n,requestId).reason=='host_only','guest departure was not host-only')
        facts.hostOnlyStory=true;stage='reopen'
    elseif stage=='reopen' and Helpers.ready(lp) and v:inputAllowed()then
        openTravel(v);stage='reinspect'
    elseif stage=='reinspect' and v.travel.model and not v.travel.pending then
        check(v.travel.opened,'private inspection was not restored before host departure')
        file('guest.story-denied',true);stage='departed'
    elseif stage=='departed' and file('host.departed')then
        local departed=readJson('host.departed.json')
        if v.epoch>=departed.epoch then
            check(not v.travel.opened,'host departure retained private travel panel');facts.privatePanelClosed=true;stage='arrived'
        end
    elseif stage=='arrived' and file('host.arrived') and Helpers.ready(lp) and v:inputAllowed() and v.runtime.saveData.location==2 then
        app.draw();photo('guest-travel-arrived.png');moveX=lp.motionFrame.companion.x/1000;moveAt=now
        if touch then
            local mobile=v.mobile;local r=mobile.joystick
            local point=require('game.ui_layout').transformRectFor('mobileControls',mobile:uiBounds(),{x=r.x+r.radius*.65,y=r.y,w=0,h=0})
            local x,y=coords(point.x,point.y)
            app.touchpressed('travel-move',x,y);movementHeld=true
        else app.keypressed('d');movementHeld=true end
        stage='moving'
    elseif stage=='moving' and now-moveAt>.35 then
        if movementHeld then
            if touch then app.touchreleased('travel-move',0,0)else app.keyreleased('d')end;movementHeld=false
        end
        if lp.motionFrame and math.abs(lp.motionFrame.companion.x/1000-moveX)>.5 then
            json('guest.moved',{startX=moveX,endX=lp.motionFrame.companion.x/1000});stage='movement-proof'
        end
    elseif stage=='movement-proof' and file('host.movement.verified') and captured['guest-travel-arrived.png']then
        facts.guestMovementRecovered=true;menu();click('leave');file('guest.returned',true);finish()
    end
end
local function update(dt)
    if finished then return end
    if c.ui.localPlay.focused==false then app.focus(true)end
    app.update(math.min(.05,dt));local now=love.timer.getTime()
    if role=='host'then hostUpdate(now)else guestUpdate(now)end
    if now-lastReport>5 then lastReport=now;print('LAN_TRAVEL_STAGE role='..role..' stage='..tostring(stage)..' error='..tostring(c.ui.localPlay.error))end
    check(now-started<120,'travel fixture deadline at '..tostring(stage))
end
local function guarded(fn,...)
    local args={...};local ok,reason=xpcall(function()return fn(unpack(args))end,debug.traceback)
    if not ok then
        if keyboardQuery then love.keyboard.isDown=keyboardQuery;keyboardQuery=nil end
        print('LAN_SMOKE_FAIL role='..role..' stage='..tostring(stage)..' '..tostring(reason));finished=true;love.event.quit(1)
    end
end
function love.load()guarded(function()
    local original=Save.write
    Save.write=function(...)
        writes=writes+1;writeEvents[#writeEvents+1]={stage=stage or 'load',at=started and love.timer.getTime()-started or 0,number=writes}
        return original(...)
    end -- Observe; always execute the real writer.
    load()
end)end
function love.update(dt)guarded(update,dt)end
function love.draw()
    if finished or not app then return end
    guarded(function()
        app.draw()
        if capture and not capturePending then
            local name=capture;capture=nil;capturePending=true
            love.graphics.captureScreenshot(function(pixels)guarded(function()
                local png=pixels:encode('png');check(file(name,png:getString()),'travel PNG write failed')
                check(#assert(file(name))>0,'empty travel PNG');captured[name]=true;capturePending=false
            end)end)
        end
    end)
end
function love.focus(focused)if app then app.focus(focused)end end
