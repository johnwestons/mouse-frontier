-- Two production applications and real ENet. Only a normal new save is seeded;
-- every settings/map/journal/pose action below enters the root input callbacks.
-- Native desktop/touch callback evidence is not physical Android verification.
local Helpers={}
function Helpers.ready(lp)
    local v=lp.clientView;local f=lp.motionFrame;local n=lp.network
    local data=v and v.runtime.saveData;local replica=lp.replica and lp.replica.data
    return n and n.status=='ready' and not n.closed and v and v.ready and not v.paused
        and data and replica and data.scene==replica.scene and data.location==replica.location
        and data.coop.sceneEpoch==v.epoch and replica.coop.sceneEpoch==v.epoch
        and f and f.ready and not f.paused and f.sessionId==n.sessionId
        and f.sceneEpoch==v.epoch and f.motionId==v.motionId and f.serial==v.lastSerial and f.domain==v.modalDomain
        and not v.prediction:stale()
end
function Helpers.target(settings,id)
    for _,target in ipairs(settings.controls)do if target.id==id then return target.rect,target.enabled end end
end
function Helpers.pose(frame,id,stance,serial)
    local actor=frame and frame[id]
    return actor and actor.stance==stance and type(actor.poseSerial)=='number' and actor.poseSerial>serial
        and actor.useRemainingMs==0
end
function Helpers.use(frame,id,serial)
    local actor=frame and frame[id]
    return actor and actor.stance=='idle' and type(actor.poseSerial)=='number' and actor.poseSerial>serial
        and type(actor.useRemainingMs)=='number' and actor.useRemainingMs>0 and actor.useRemainingMs<=450
end
function Helpers.actionReady(now,last) return now-last>=.65 end
function Helpers.publicHash(data,hash)
    local campaign=require('game.coop_players').campaignOf(data)
    local public=require('game.replica_ownership').isReplica(campaign) and campaign
        or assert(require('game.net.game_state').project(campaign)).view
    local Records=require('game.net.state_records')
    local record=assert(Records.encode(public,Records.budget()))
    return hash(assert(require('game.net.codec').encode(record,
        {maxBytes=524288,maxDepth=32,maxEntries=200000,maxStringBytes=8192})))
end
function Helpers.reportData(lp,data)
    return lp.clientView and lp.replica and lp.replica.data or data
end
if rawget(_G,'DEVICE_CONTROLS_FIXTURE_HELPERS') then return Helpers end

io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save');local Viewport=require('game.viewport');local Codec=require('game.net.codec')
local Preferences=require('game.local_preferences');local Bindings=require('game.control_bindings')
local Layout=require('game.control_layout');local State=require('game.net.game_state')
local app,c,stage,started,finished,lastInput= nil,nil,nil,nil,false,0
local capture,capturePending;local captured={};local facts={};local settingsBefore,layoutBefore
local poseSerial,requestId,useSerial,useSeenAt,baselineDisk,baselineHostPose,oldHostUseSerial
local lastReport=0;local journeyCloseCount=0
local limits={maxBytes=524288,maxDepth=24,maxEntries=200000,maxStringBytes=4096}
local function check(value,message)assert(value,message)end
local function file(name,value)
    local f=io.open(root..'/'..name,value~=nil and 'wb' or 'rb');if not f then return nil end
    local result=value~=nil and f:write(tostring(value)) or f:read('*a');f:close();return result
end
local function hash(bytes)return love.data.encode('string','hex',love.data.hash('sha256',assert(bytes)))end
local function saveHash()return hash(love.filesystem.read(Save.path(99)))end
local function report(name)
    app.draw();local stats=love.graphics.getStats()
    local lp=c.ui.localPlay;local runtime=lp.clientView and lp.clientView.runtime or c.runtime
    local data=runtime.saveData
    local result={role=role,stage=stage,state=runtime.state,scene=runtime.scene,
        texturememory=stats.texturememory,images=stats.images,drawcalls=stats.drawcalls,
        sessionId=lp.network and lp.network.sessionId,epoch=lp.clientView and lp.clientView.epoch,
        motionId=lp.clientView and lp.clientView.motionId,location=data and data.location,
        physicalAndroid=false,touchCallbacks=touch}
    local publicData=Helpers.reportData(lp,data)
    if publicData then result.publicHash=Helpers.publicHash(publicData,hash)end
    file(role..'.'..name..'.json',assert(Codec.encode(result,limits)))
end
local function key(token)app.keypressed(token);app.keyreleased(token);lastInput=love.timer.getTime()end
local function coords(x,y)local ox,oy,sx,sy=Viewport.transform(960,720);return ox+x*sx,oy+y*sy end
local function press(rect)
    check(rect and rect.enabled~=false,'missing production control at '..tostring(stage))
    local x,y=coords(rect.x+rect.w/2,rect.y+rect.h/2)
    if touch then app.touchpressed('device-control',x,y);app.touchreleased('device-control',x,y)
    else app.mousepressed(x,y,1,false);app.mousereleased(x,y,1,false)end
    lastInput=love.timer.getTime()
end
local function menu()if not c.ui.localPlay.menuOpen then key('f8')end end
local function click(name,text)
    app.draw();press(c.ui.localPlayControls[name])
    if text then app.textinput(text);key('return')end
end
local function back()if c.ui.localPlay.menuOpen then click('close')end end
local function setting(id)
    app.draw();local rect,enabled=Helpers.target(c.ui.localPlay.clientView.settings,id)
    check(enabled~=false,'disabled device control '..id);press(rect)
end
local function photo(name)check(not capture and not capturePending,'overlapping device captures');capture=name end
local function finish()
    if finished then return end;finished=true;check(app.quit()~=true,'device-controls quit cancelled')
    print('LAN_SMOKE_OK role='..role..' application=true deviceControls=true settingsPersisted=true'
        ..' remapInventory=true privateTouchLayout=true mapJournal=true actorPoses=true hostOnlyStory=true'
        ..' physicalAndroid=false input='..(touch and 'touch' or 'desktop'));love.event.quit(0)
end
local function load()
    started=love.timer.getTime();lastReport=started
    require('game.smoke_playthrough').install=function(value)c=value end
    app=require('game.application_composition').new({engine=love});app.installSmoke();app.load()
    report('title')
    local lp=c.ui.localPlay;lp.context.bind='127.0.0.1'
    if role=='host' then
        Save.remove(99);c.runtime.selectedSlot=99
        check(c.enterGame(c.newSave(c.characters[1])),'ordinary new-save train failed')
        check(c.runtime.saveData.location==1 and c.runtime.scene=='train','fixture altered new journey')
        menu();click('port',port);click('host');check(lp.network,'hosting failed '..tostring(lp.error))
        stage='hosting';print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots';menu();click('address','127.0.0.1:'..port)
        click('name','Device controls companion');click('join');stage='joining'
    end
end
local function hostPose(control)
    app.draw()
    if not c.ui.pose and touch then
        local mobile=c.getMobileControls();press(require('game.ui_layout').transformRectFor('mobileControls',mobile:uiBounds(),mobile.menu));app.draw()
    end
    press(c.ui.pose);check(c.runtime.poseMenu,'Source pose menu did not open');app.draw();press(c.ui[control])
    check(not c.runtime.poseMenu,'Source pose selection did not close')
end
local function hostUpdate()
    local lp=c.ui.localPlay
    if lp:pending()then menu();click('approve');check(not lp.error,'admission failed '..tostring(lp.error));back()end
    if stage=='hosting' and file('guest.connected')then
        back();baselineDisk=saveHash();file('host.baseline.disk',baselineDisk)
        baselineHostPose=c.runtime.playerPose;report('connected');stage='private-settings';file('host.settings.ready',true)
    elseif stage=='private-settings' and file('guest.private.complete')then
        check(saveHash()==baselineDisk,'private device settings/map/journal wrote host save')
        check(not c.runtime.mapOpen and not c.runtime.journeyLogOpen and not c.runtime.inventoryOpen,'guest private UI opened host UI')
        check(c.runtime.playerPose==baselineHostPose and c.runtime.scene=='train' and c.runtime.saveData.location==1,'private guest UI changed host story/pose')
        facts.privateHostSaveUnchanged=true;file('host.private.verified',true);stage='guest-sit'
    elseif stage=='guest-sit' then
        local p=lp.context.commands.poseState('companion')
        if p and p.pose=='sit'then facts.guestSit=p.serial;file('host.guest.sit',p.serial);stage='guest-use'end
    elseif stage=='guest-use' then
        local p=lp.context.commands.poseState('companion')
        if p and p.pose=='idle' and p.useMs>0 then
            check(p.serial>facts.guestSit,'guest USE reused SIT serial');facts.guestUse=p.serial
            file('host.guest.use',p.serial);stage='guest-story'
        end
    elseif stage=='guest-story' and file('guest.story.denied') and Helpers.actionReady(love.timer.getTime(),lastInput)then
        check(c.runtime.scene=='train' and c.runtime.saveData.location==1,'guest story probe changed scene')
        hostPose('poseSit');local p=lp.context.commands.poseState('host')
        check(p and p.pose=='sit','actual host Source pose click not shared');facts.hostSit=p.serial
        file('host.own.sit',p.serial);stage='host-sit'
    elseif stage=='host-sit' and file('guest.host.sit') and Helpers.actionReady(love.timer.getTime(),lastInput)then
        hostPose('poseAction');local p=lp.context.commands.poseState('host')
        check(p and p.useMs>0 and p.serial>facts.hostSit,'host Source USE timer missing');facts.hostUse=p.serial
        file('host.own.use',p.serial);stage='host-use'
    elseif stage=='host-use' and file('guest.host.use')then
        file('host.controls.complete',true);stage='ending'
    elseif stage=='ending' and file('guest.returned')then
        menu();click('stop');report('return');file('host.facts.json',assert(Codec.encode(facts,limits)));finish()
    end
end
local function guestUpdate()
    local lp=c.ui.localPlay;local v=lp.clientView;local f=lp.motionFrame;local now=love.timer.getTime()
    if stage=='joining' and Helpers.ready(lp)then
        back();report('connected');file('guest.connected',true);stage='settings-start'
    elseif stage=='settings-start' and file('host.settings.ready') and Helpers.ready(lp)then
        menu();click('settings');check(v.settings.opened,'real Device settings button did not open')
        settingsBefore=Preferences.view(v.runtime.saveData).audio.musicVolume
        setting('musicVolume+');check(math.abs(Preferences.view(v.runtime.saveData).audio.musicVolume-settingsBefore-.05)<.00001,'personal music button failed')
        photo('guest-device-settings-audio.png');stage='audio-capture'
    elseif stage=='audio-capture' and captured['guest-device-settings-audio.png']then
        setting('controls');stage='key-find'
    elseif stage=='key-find' then
        app.draw()
        if Helpers.target(v.settings,'bind-inventory')then setting('bind-inventory');check(v.settings.bindings:isCapturing(),'actual keyboard capture did not start')
            key('z');check(not v.settings.bindings:isCapturing(),'raw Z did not complete capture');stage='touch-layout'
        else setting('down')end
    elseif stage=='touch-layout'then
        setting('device-touch');layoutBefore=Layout.load(love.filesystem) or v.settings:touchLayout()
        facts.layoutXBefore=layoutBefore.joystick.x;setting('right')
        local stored=assert(Layout.load(love.filesystem));check(math.abs(stored.joystick.x-facts.layoutXBefore-.02)<.000001,'touch position did not persist')
        facts.layoutXAfter=stored.joystick.x;check(not v.settings.layoutDirty,'touch layout persistence not acknowledged')
        photo('guest-device-settings-touch-layout.png');stage='layout-capture'
    elseif stage=='layout-capture' and captured['guest-device-settings-touch-layout.png']then
        local fresh=Preferences.new(love.filesystem);check(math.abs(fresh.values.audio.musicVolume-settingsBefore-.05)<.000001,'music setting not persisted')
        local binding=Bindings.new(love.filesystem);local token= binding:translateKey('z')
        check(token=='i','fresh binding file did not translate Z');local old,known=binding:translateKey('i')
        check(not old and known,'old physical I still bound to inventory')
        facts.preferencesHash=hash(love.filesystem.read(Preferences.PATH));facts.bindingsHash=hash(love.filesystem.read(Bindings.PATH))
        facts.layoutHash=hash(love.filesystem.read('control-layout.txt'))
        setting('close');check(not v.settings.opened and lp.menuOpen,'settings Back did not return to Local Play');back();stage='pack'
    elseif stage=='pack' and Helpers.ready(lp)then
        key('i');check(not v.runtime.inventoryOpen,'old I still opens guest pack')
        key('z');check(v.runtime.inventoryOpen,'mapped Z did not reach root guest inventory input')
        photo('guest-mapped-z-backpack.png');stage='pack-capture'
    elseif stage=='pack-capture' and captured['guest-mapped-z-backpack.png']then
        key('z');check(not v.runtime.inventoryOpen,'mapped Z did not close pack');stage='map'
    elseif stage=='map' and Helpers.ready(lp)then
        if touch then app.draw();press(v.ui.guestMap)else key('m')end
        check(v.journey.opened and v.journey.kind=='map','production MAP did not open');app.draw()
        check(#v.journey.model.points==1 and v.journey.model.points[1].stop==1,'new journey map reveals future stops')
        check(not v:inputAllowed(),'guest can move behind private map');photo('guest-private-map.png');stage='map-capture'
    elseif stage=='map-capture' and captured['guest-private-map.png']then
        app.draw();press(v.journey.controls.map);check(not v.journey.opened,'actual CLOSE MAP failed');stage='journal'
    elseif stage=='journal' and Helpers.ready(lp)then
        if touch then app.draw();press(v.ui.guestJournal)else key('j')end
        check(v.journey.opened and v.journey.kind=='journal','production JOURNAL did not open');app.draw()
        check(#v.journey.model.rows==0,'normal new journey contains invented accepted tasks')
        photo('guest-private-journal.png');stage='journal-capture'
    elseif stage=='journal-capture' and captured['guest-private-journal.png']then
        app.draw();press(v.journey.controls.journeyLogClose);check(not v.journey.opened,'actual CLOSE JOURNAL failed')
        file('guest.private.complete',true);stage='pose-open'
    elseif stage=='pose-open' and file('host.private.verified') and Helpers.ready(lp) and Helpers.actionReady(now,lastInput)then
        poseSerial=f.companion.poseSerial;app.draw();press(v.ui.guestPose)
        check(v.poses.opened,'actual guest pose button did not open');photo('guest-pose-menu.png');stage='pose-neutral'
    elseif stage=='pose-neutral' and captured['guest-pose-menu.png'] and f.ack>=(v.poses.neutralSequence or 0) and not f.companion.moving then
        press(v.poses:targets()[2].rect);check(v.poses.pending,'actual SIT did not submit after neutral acknowledgment');stage='sit'
    elseif stage=='sit' and Helpers.ready(lp) and Helpers.pose(f,'companion','sit',poseSerial) and not v.poses.opened and file('host.guest.sit')then
        photo('guest-shared-sit.png');poseSerial=f.companion.poseSerial;stage='sit-capture'
    elseif stage=='sit-capture' and captured['guest-shared-sit.png'] and Helpers.actionReady(now,lastInput)then
        app.draw();press(v.ui.guestPose);check(v.poses.opened,'guest USE menu unavailable')
        press(v.poses:targets()[4].rect);check(v.poses.pending,'actual USE did not submit');stage='use'
    elseif stage=='use' and Helpers.ready(lp) and Helpers.use(f,'companion',poseSerial) and not v.poses.opened then
        useSerial=f.companion.poseSerial;useSeenAt=now;facts.guestUse=useSerial;photo('guest-shared-use.png');stage='use-expire'
    elseif stage=='use-expire' and captured['guest-shared-use.png'] and file('host.guest.use') and f.companion.poseSerial==useSerial
        and f.companion.useRemainingMs==0 and now-useSeenAt>.45 and Helpers.actionReady(now,lastInput)then
        check(not v.poses.opened and not lp.network.pendingCommand,'guest USE receipt not settled')
        requestId=assert(lp.network:submitCommand('scene.leaveTrain',{},v.epoch,{party=v.runtime.saveData.coop.revisions.party or 0}))
        stage='story'
    elseif stage=='story'then
        local result=lp.network.lastCommandResult
        if result and result.requestId==requestId then
            check(not result.ok and result.reason=='host_only','guest can progress host story')
            check(v.runtime.scene=='train' and v.runtime.saveData.location==1,'story denial changed journey')
            facts.hostOnlyReason=result.reason;oldHostUseSerial=f.host.poseSerial;file('guest.story.denied',true);stage='host-sit'
        end
    elseif stage=='host-sit' and file('host.own.sit') and Helpers.ready(lp) and Helpers.pose(f,'host','sit',oldHostUseSerial)then
        oldHostUseSerial=f.host.poseSerial;photo('guest-sees-host-source-sit.png');file('guest.host.sit',true);stage='host-use'
    elseif stage=='host-use' and Helpers.ready(lp) and Helpers.use(f,'host',oldHostUseSerial)then
        facts.hostUse=f.host.poseSerial;file('guest.host.use',true);stage='leave'
    elseif stage=='leave' and file('host.controls.complete') and captured['guest-sees-host-source-sit.png'] and not capture and not capturePending then
        menu();click('leave');check(not lp.clientView and not lp.network and c.runtime.state=='slots','real Leave failed ownership restoration')
        report('return');file('guest.facts.json',assert(Codec.encode(facts,limits)));file('guest.returned',true);finish()
    end
end
local function update(dt)
    if finished then return end
    local v=c.ui.localPlay.clientView
    if v and not v.journey.fixtureObserved then
        v.journey.fixtureObserved=true
        local close=v.journey.close
        v.journey.close=function(panel,...)
            if panel.opened then
                journeyCloseCount=journeyCloseCount+1
                local lp=c.ui.localPlay;local f=lp.motionFrame
                local observed={stage=stage,kind=panel.kind,domain=panel:domain(),
                    openIdentity=panel.openIdentity,identity=panel:identity(),
                    stale=v.prediction:stale(),focused=v.focused,paused=v.paused,
                    serial=v.lastSerial,frameSerial=f and f.serial,menu=lp.menuOpen,
                    pending=lp.network and lp.network.pendingCommand~=nil,
                    motionAge=v.prediction.lastFrame and love.timer.getTime()-v.prediction.lastFrame,
                    stack=debug.traceback('journey close')}
                local d=v.runtime.saveData;local replica=lp.replica and lp.replica.data
                observed.gates={ready=v.ready,network=lp.network.status,closed=not not lp.network.closed,
                    replicaScene=replica and replica.scene,scene=d.scene,runtimeScene=v.runtime.scene,
                    replicaLocation=replica and replica.location,location=d.location,
                    epoch=v.epoch,epochData=d.coop.sceneEpoch,epochReplica=replica and replica.coop.sceneEpoch,
                    frameReady=f and f.ready,framePaused=f and f.paused,
                    frameSession=f and f.sessionId,networkSession=lp.network.sessionId,
                    frameEpoch=f and f.sceneEpoch,frameMotion=f and f.motionId,motion=v.motionId,
                    frameDomain=f and f.domain,domain=v.modalDomain,
                    savePending=not not lp.network.savePending,saving=not not v.runtime.saving,
                    carRequest=not not v.carRequest,carTransition=not not v.carTransition,
                    battle=not not v.runtime.battle,tactical=not not d.tacticalBattle,
                    roaming=not not d.roamingEncounter,lastStand=not not require('game.coop_last_stand_lifecycle').active(d),
                    ambushActive=not not(d.trainAmbush and d.trainAmbush.active),event=not not(d.events and d.events.current),
                    inventory=not not v.runtime.inventoryOpen,trade=not not v.runtime.tradeOpen,
                    upgrades=not not v.runtime.trainUpgradeOpen,people=not not v.runtime.peopleOpen,
                    activities=not not v.runtime.guestActivityOpen,objects=v:objectsOpen(),activityBusy=v:activityBusy(),
                    controllerFocus=not not v.controllerFocus,
                    rangeAvailable=not not(v.range and v.range:available()),
                    ambushAvailable=not not(v.ambush and v.ambush:available()),
                    lastStandAvailable=not not(v.lastStand and v.lastStand:available())}
                for _,name in ipairs({'poses','inventory','trade','train','objects','people'})do
                    local p=v[name];observed.gates[name..'Busy']=not not(p and(p.pending or p.opened))
                end
                file('guest.journey-close-'..journeyCloseCount..'.json',assert(Codec.encode(observed,limits)))
            end
            return close(panel,...)
        end
    end
    if c.ui.localPlay.focused==false then app.focus(true)end
    app.update(math.min(.05,dt));if role=='host'then hostUpdate()else guestUpdate()end
    if love.timer.getTime()-lastReport>5 then
        lastReport=love.timer.getTime();local lp=c.ui.localPlay
        print('LAN_DEVICE_STAGE role='..role..' stage='..tostring(stage)..' error='..tostring(lp.error)..' phase='..tostring(lp.phase))
    end
    check(love.timer.getTime()-started<120,'device-controls deadline at '..tostring(stage))
end
local function guarded(fn,...)
    local args={...};local ok,reason=xpcall(function()return fn(unpack(args))end,debug.traceback)
    if not ok then print('LAN_SMOKE_FAIL role='..role..' stage='..tostring(stage)..' '..tostring(reason));finished=true;love.event.quit(1)end
end
function love.load()guarded(load)end
function love.update(dt)guarded(update,dt)end
function love.draw()
    if finished or not app then return end
    guarded(function()
        app.draw()
        if capture and not capturePending then
            local name=capture;capture=nil;capturePending=true
            love.graphics.captureScreenshot(function(pixels)guarded(function()
                local png=pixels:encode('png');check(file(name,png:getString()),'device PNG write failed')
                check(#assert(file(name))>0,'device PNG empty');captured[name]=true;capturePending=false
            end)end)
        end
    end)
end
function love.focus(focused)if app then app.focus(focused)end end
