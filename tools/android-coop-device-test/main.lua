-- One actual packaged desktop application, one physical Android guest.
-- Never creates a test client/peer or modifies either actor's starter kit.
io.stdout:setvbuf('no')
local root=assert(os.getenv('MOUSE_FRONTIER_DEVICE_TEST_ROOT'))
local resume=os.getenv('MOUSE_FRONTIER_DEVICE_TEST_RESUME')=='1'
local Save=require('game.save');local Viewport=require('game.viewport')
local app,c,capture,capturePending,finished,lastStatus,lastActionId,approvalPhoto
local approved,connected,remoteCount,denied=0,0,0,0
local commands={};local seenGeneration;local companionId;local observationNetwork
local function check(value,message)assert(value,message)end
local function json(value)
    if value==nil then return 'null' end
    if type(value)=='boolean' or type(value)=='number' then return tostring(value) end
    if type(value)=='string' then
        return '"'..value:gsub('[%z\1-\31\\"]',function(char)
            if char=='\\' then return '\\\\' elseif char=='"'then return '\\"'end
            return string.format('\\u%04x',char:byte())end)..'"'
    end
    check(type(value)=='table','unsupported status value')
    local result={};local array=#value>0
    if array then for i=1,#value do result[#result+1]=json(value[i])end
    else for k,v in pairs(value)do result[#result+1]=json(tostring(k))..':'..json(v)end;table.sort(result)end
    return (array and '[' or '{')..table.concat(result,',')..(array and ']' or '}')
end
local function file(name,value)
    local stream=io.open(root..'/'..name,value~=nil and 'wb' or 'rb');if not stream then return nil end
    local result=value~=nil and stream:write(tostring(value)) or stream:read('*a');stream:close();return result
end
local function savedKit(actor)
    local function copy(value)
        if type(value)~='table' then return value end
        local result={};for k,v in pairs(value)do result[tostring(k)]=copy(v)end;return result
    end
    return copy({id=actor.id,inventory=actor.inventory,equipment=actor.equipment,itemSlots=actor.itemSlots,
        ammo=actor.ammo,health=actor.health,stats=actor.stats,weaponDurability=actor.weaponDurability,
        weaponProficiency=actor.weaponProficiency})
end
local function key(value) local result=app.keypressed(value);app.keyreleased(value);return result end
local function press(rect)
    check(rect and rect.enabled~=false,'actual desktop control unavailable')
    local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    local result=app.mousepressed(x,y,1,false);app.mousereleased(x,y,1,false);return result
end
local function menu()if not c.ui.localPlay.menuOpen then key('f8')end;app.draw()end
local function click(name)app.draw();return press(c.ui.localPlayControls[name])end
local function closeMenu()if c.ui.localPlay.menuOpen then click('close')end end
local function photo(name)
    check(not capture and not capturePending,'capture is already pending');capture=name
end
local function observe()
    local lp=c.ui.localPlay
    if not lp.network or lp.network==observationNetwork then return end
    observationNetwork=lp.network
    local original=lp.network.context.command
    lp.network.context.command=function(generation,request)
        local reply=original(generation,request)
        remoteCount=remoteCount+1
        if reply and not reply.ok then denied=denied+1 end
        commands[#commands+1]={number=remoteCount,generation=generation,requestId=request.requestId,
            command=request.command,ok=reply and reply.ok==true,reason=reply and reply.reason,
            savePending=reply and reply.savePending==true,durable=reply and reply.durable==true}
        if #commands>16 then table.remove(commands,1)end
        print('ANDROID_PEER_COMMAND number='..remoteCount..' command='..request.command..' ok='..tostring(reply and reply.ok)
            ..' reason='..tostring(reply and reply.reason)..' durable='..tostring(reply and reply.durable))
        return reply
    end
end
local function hostSaved()
    local lp=c.ui.localPlay;lp.port='22124'
    c.runtime.state='slots';menu();click('host')
    check(lp.hostingIntent=='selecting' and not lp.menuOpen,'actual saved-host selection missing')
    app.draw();press(c.ui.slots[1]);check(lp.network and c.session.networkMode=='host','saved-slot host failed: '..tostring(lp.error))
    closeMenu();observe();print('ANDROID_DESKTOP_LISTENING port=22124 discovery=22125 actualApplication=true')
end
local function writeStatus()
    local lp=c.ui.localPlay;local r=c.runtime;local d=r.saveData
    local guest=d and d.players.companion;local host=d and d.players.host
    local motion=lp.motion;local actor=motion and motion.actor
    local link=lp.network and lp.network.link
    local status={screen=r.state,scene=r.scene,location=d and d.location,hostMode=c.session.networkMode,
        phase=lp.phase,error=lp.error,menu=lp.menuOpen,pendingApproval=lp:pending()~=nil,
        addresses=lp:localInterfaces(),localAddress=lp.localAddress,approved=approved,connections=connected,
        generation=link and link.generation,peerPhase=link and link.phase,admitted=link and link.admitted==true,
        readyEpoch=motion and motion.readyEpoch,epoch=d and d.coop.sceneEpoch,motionId=motion and motion.motionId,
        checkpointPending=c.session.checkpointPending,remoteCommands=remoteCount,deniedCommands=denied,lastCommands=commands,
        host={id=host and host.id,x=r.player and r.player.x,y=r.player and r.player.y,health=host and host.health},
        companion={id=guest and guest.id,x=actor and actor.x,y=actor and actor.y,health=guest and guest.health},
        resources=d and d.resources,scrap=d and d.scrap}
    file('status.json',json(status))
end
local function action()
    local bytes=file('action.txt');if not bytes or #bytes>1024 then return end
    local id,actionName,argument=bytes:match('^(%d+)%s+([%w]+)%s*([%w_-]*)%s*$')
    local value={id=tonumber(id),action=actionName,control=argument,key=argument}
    if not value.id or value.id<=(lastActionId or -1) then return end
    lastActionId=value.id;local ok,reason=pcall(function()
        if value.action=='capture' then photo('desktop-action-'..value.id..'.png')
        elseif value.action=='menu' then menu()
        elseif value.action=='close' then closeMenu()
        elseif value.action=='stop' then menu();click('stop');closeMenu()
        elseif value.action=='rehost' then
            if c.ui.localPlay.network then menu();click('stop');closeMenu()end
            hostSaved()
        elseif value.action=='control' and type(value.control)=='string' then
            app.draw();press(c.ui[value.control])
        elseif value.action=='key' and type(value.key)=='string' and #value.key<=16 then key(value.key)
        elseif value.action=='quit' then
            check(app.quit()~=true,'actual quit cancelled');finished=true;love.event.quit(0)
        else error('unsupported device-test action')end
    end)
    file('action-result.json',json({id=value.id,ok=ok,reason=not ok and tostring(reason) or nil}))
    print('ANDROID_DESKTOP_ACTION id='..value.id..' action='..tostring(value.action)..' ok='..tostring(ok))
end
local function load()
    require('game.smoke_playthrough').install=function(value)c=value end
    app=require('game.application_composition').new({engine=love});app.installSmoke();app.load()
    local expectedKit
    if resume then
        -- Read and validate the actual saved campaign before real slot entry.
        -- No newSave, enterGame or write runs on this resume path.
        local saved=assert(Save.read(1),'isolated saved slot1 missing or invalid')
        check(saved.players and saved.players.companion,'physical companion absent from saved checkpoint')
        companionId=saved.players.companion.id
        expectedKit=json(savedKit(saved.players.companion))
        -- A previous process's quit/rehost trigger must never replay at boot.
        local previous=file('action.txt');lastActionId=previous and tonumber(previous:match('^(%d+)%s')) or nil
        print('ANDROID_DESKTOP_RESUME existingSlot=1 companionId='..companionId..' location='..saved.location..' scene='..saved.scene)
    else
        -- First stop, original new-save gear/resources, normal companion placement.
        c.runtime.selectedSlot=1;check(c.enterGame(c.newSave(c.characters[1])),'normal initial campaign failed')
        check(c.runtime.saveData.location==1 and c.runtime.scene=='train','expected ordinary first-stop train')
        check(Save.write(1,c.runtime.saveData),'isolated initial checkpoint failed')
        c.runtime.saveData=nil;c.runtime.selectedSlot=nil
    end
    hostSaved();lastStatus=0
    if expectedKit then
        check(json(savedKit(c.runtime.saveData.players.companion))==expectedKit,'saved-slot host entry changed physical companion kit')
        file('resume-checkpoint.json',json({savedSlot=1,exactCompanionKit=true,companion=savedKit(c.runtime.saveData.players.companion)}))
    end
    file('ready.txt','actualApplication=true port=22124 discovery=22125 savedSlot=1')
    photo('desktop-host-start.png')
end
local function update(dt)
    if finished then return end
    app.update(dt);local lp=c.ui.localPlay
    if lp.focused==false then app.focus(true)end
    observe()
    local pending=lp:pending()
    if pending and not capture and not capturePending then
        if not approvalPhoto then menu();photo('desktop-approval-pending-'..(approved+1)..'.png');approvalPhoto=true
        else menu();click('approve');check(not lp.error,'actual Android approval failed: '..tostring(lp.error))
            approved=approved+1;closeMenu();approvalPhoto=nil end
    end
    local link=lp.network and lp.network.link
    if link and link.admitted and seenGeneration~=link.generation then
        seenGeneration=link.generation;connected=connected+1
        local id=c.runtime.saveData.players.companion.id
        check(not companionId or id==companionId,'physical reconnect replaced companion identity');companionId=id
        print('ANDROID_PEER_CONNECTED count='..connected..' generation='..link.generation)
    end
    if not capture and not capturePending then action()end
    if love.timer.getTime()-lastStatus>=1 then lastStatus=love.timer.getTime();writeStatus()end
end
local function draw()
    if finished or not app then return end;app.draw()
    if capture then
        local name=capture;capture=nil;capturePending=true
        love.graphics.captureScreenshot(function(pixels)
            local bytes=pixels:encode('png');check(file(name,bytes:getString()),'actual PNG write failed');capturePending=false
            print('ANDROID_DESKTOP_PNG '..name)
        end)
    end
end
local function guarded(fn,...)
    local args={...};local ok,reason=xpcall(function()fn(unpack(args))end,debug.traceback)
    if not ok then print('ANDROID_DESKTOP_FAILED '..tostring(reason));file('failure.txt',reason);finished=true;love.event.quit(1)end
end
function love.load()guarded(load)end
function love.update(dt)guarded(update,dt)end
function love.draw()guarded(draw)end
function love.focus(value)if app then app.focus(value)end end
