-- Real UDP discovery and ENet joins through two isolated full applications.
io.stdout:setvbuf('no')
local role=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROLE'))
local port=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_PORT'))
local discoveryPort=assert(tonumber(os.getenv('MOUSE_FRONTIER_LAN_DISCOVERY_PORT')))
local root=assert(os.getenv('MOUSE_FRONTIER_LAN_SMOKE_ROOT'))
local touch=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
local Save=require('game.save'); local Viewport=require('game.viewport')
local Schema=require('game.save_schema')
local app,c,stage,started,finished,capture,seenAt,identity,hostItem,hostX,hostY,initialNetwork
local captures={}; local connections=0; local generation; local dropped=false; local sawReconnect=false; local guestKit
local function check(value,message) assert(value,message) end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for key,value in pairs(a) do if not equal(value,b[key]) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
end
local function kit(actor) return {inventory=actor.inventory,itemSlots=actor.itemSlots,ammo=actor.ammo} end
local function marker(name,value) local f=assert(io.open(root..'/'..name,'w')); f:write(tostring(value or true)); f:close() end
local function read(name) local f=io.open(root..'/'..name,'r'); if not f then return nil end; local value=f:read('*a'); f:close(); return value end
local function button(key) app.keypressed(key); app.keyreleased(key) end
local function press(rect)
    check(rect,'missing discovery control at '..tostring(stage))
    local ox,oy,sx,sy=Viewport.transform(960,720)
    local x,y=ox+(rect.x+rect.w/2)*sx,oy+(rect.y+rect.h/2)*sy
    if touch then app.touchpressed('discovery-button',x,y); app.touchreleased('discovery-button',x,y)
    else app.mousepressed(x,y,1,false); app.mousereleased(x,y,1,false) end
end
local function menu() if not c.ui.localPlay.menuOpen then button('f8') end; app.draw() end
local function click(name,text)
    app.draw(); press(c.ui.localPlayControls[name])
    if text then app.textinput(text); button('return') end
end
local function finish()
    if finished then return end; finished=true
    check(app.quit()~=true,'quit was cancelled')
    print('LAN_SMOKE_OK role='..role..' discovery=true realUdp=true autoSearch=true autoConnect=true modes=true reconnect=true input='..(touch and 'touch' or 'desktop'))
    love.event.quit(0)
end
local function load()
    started=love.timer.getTime(); love.math.setRandomSeed(10122026)
    require('game.smoke_playthrough').install=function(value) c=value end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    local lp=c.ui.localPlay; lp.context.bind='127.0.0.1'
    local Interfaces=require('game.net.interface_addresses')
    for index=1,3 do
        local entries=Interfaces.enumerate()
        check(type(entries)=='table','native adapter refresh failed on pass '..index)
        print('LAN_NATIVE_ADAPTERS role='..role..' pass='..index..' count='..#entries)
    end
    -- Real sockets on an isolated port. Loopback adapter metadata is a fixture,
    -- not a claim that physical Wi-Fi or tether hardware has been tested.
    lp.context.addressDetector=function() return {{address='127.0.0.1',prefixLength=8,isUsb=false}} end
    lp.discovery=require('game.net.lan_discovery').new({clock=lp.context.clock,port=discoveryPort,
        queryTargets={'127.0.0.1'},addressDetector=lp.context.addressDetector})
    lp:setAutoJoin(false)
    if role=='host' then
        c.runtime.selectedSlot=99; Save.remove(99)
        check(c.enterGame(c.newSave(c.characters[1])),'fixture campaign failed')
        hostItem=c.runtime.saveData.players.host.itemSlots.equipment[1].id
        hostX,hostY=c.runtime.player.x,c.runtime.player.y
        menu(); click('port',port); click('host'); check(lp.network,'hosting failed: '..tostring(lp.error))
        menu(); capture='host-menu.png'; stage='hosting'; print('LAN_SMOKE_LISTENING')
    else
        c.runtime.state='slots'; c.runtime.selectedSlot=nil
        menu(); click('name','Discovery friend'); click('connection_wifi'); stage='wifi-search'
    end
end
local function hostUpdate(lp)
    if lp:pending() then
        capture='host-approval.png'
        if captures['host-approval.png'] then click('approve'); check(not lp.error,'approval failed: '..tostring(lp.error)) end
    end
    local link=lp.network and lp.network.link
    if link and link.admitted and generation~=link.generation then
        generation=link.generation; connections=connections+1
        if connections==1 then
            identity=c.runtime.saveData.players.companion.id
            guestKit=assert(Schema.copy(kit(c.runtime.saveData.players.companion)))
            marker('host.connected',generation)
        end
        check(c.runtime.saveData.players.companion.id==identity,'reconnect replaced companion')
        check(equal(kit(c.runtime.saveData.players.companion),guestKit),'reconnect changed or duplicated guest kit')
        if connections==2 then marker('host.reconnected',generation) end
    end
    if connections==1 and read('guest.ready') and not dropped then
        lp.network:_drop('fixture_link_interrupted'); dropped=true; marker('host.dropped')
    end
    if connections==2 and read('guest.reconnected') then
        local disk=assert(Save.read(99)); check(disk.players.companion.id==identity,'restored companion changed')
        check(equal(kit(disk.players.companion),guestKit),'restored guest kit changed or duplicated')
        check(disk.players.host.itemSlots.equipment[1].id==hostItem,'discovery changed host gear')
        check(c.runtime.player.x==hostX and c.runtime.player.y==hostY,'discovery moved host')
        check(disk.players.host.playerX==hostX and disk.players.host.playerY==hostY,'restored host pose changed')
        marker('host.done'); stage='done'
    end
    if stage=='done' and read('guest.done') then finish() end
end
local function guestUpdate(lp)
    local now=love.timer.getTime(); local hosts=lp:discoveredHosts()
    if stage=='wifi-search' and #hosts==1 then
        check(hosts[1].address=='127.0.0.1' and hosts[1].port==tonumber(port),'wrong discovered endpoint')
        capture='guest-wifi.png'; stage='wifi-capture'
    elseif stage=='wifi-capture' and captures['guest-wifi.png'] then
        click('connection_usb'); check(#lp:discoveredHosts()==0,'USB filter included Wi-Fi host')
        capture='guest-usb.png'; stage='usb-capture'
    elseif stage=='usb-capture' and captures['guest-usb.png'] then
        click('manual'); click('address','127.0.0.1:1'); click('autoJoin')
        check(lp.autoJoin and lp.manualEntry,'manual entry did not suppress auto-connect')
        capture='guest-manual.png'; seenAt=now; stage='manual-wait'
    elseif stage=='manual-wait' and now-seenAt>2 then
        check(not lp.network and lp.phase=='idle','auto-connect bypassed manual entry')
        click('connection_auto'); capture='guest-auto.png'; stage='auto-search'
    elseif stage=='auto-search' and lp.network then
        check(lp.address=='127.0.0.1:'..port,'auto-connect used typed manual endpoint')
        capture='guest-connecting.png'; stage='joining'
    elseif stage=='joining' and lp.clientView and lp.clientView.ready and lp.network.status=='ready' then
        identity=lp.replica.data.players.companion.id
        initialNetwork=lp.network
        check(c.runtime.saveData==nil or c.runtime.saveData==false,'guest received writable campaign')
        marker('guest.ready'); stage='reconnect'
    elseif stage=='reconnect' then
        if lp:reconnectStatus().active then sawReconnect=true; capture='guest-reconnect.png' end
        -- The drop marker can reach this process before ENet's disconnect
        -- event. An old ready link cannot prove that reconnect completed.
        local resumedGeneration=tonumber(read('host.reconnected'))
        if read('host.dropped') and resumedGeneration and lp.network and lp.network~=initialNetwork
            and lp.clientView and lp.clientView.ready and lp.network.status=='ready' then
            local firstGeneration=tonumber(read('host.connected'))
            check(firstGeneration and resumedGeneration>firstGeneration,'reconnect did not admit a new host generation')
            check(sawReconnect and lp.replica.data.players.companion.id==identity,'auto-reconnect did not resume companion')
            marker('guest.reconnected'); stage='done'
        end
    elseif stage=='done' and read('host.done') then
        lp:setAutoJoin(false); lp:stop('fixture_complete'); marker('guest.done'); finish()
    end
end
local function update(dt)
    if finished or not app then return end
    if c.ui.localPlay.focused==false then app.focus(true) end
    app.update(math.min(.05,dt)); local lp=c.ui.localPlay
    if role=='host' then hostUpdate(lp) else guestUpdate(lp) end
    check(love.timer.getTime()-started<100,'discovery fixture timed out at '..tostring(stage)..' error='..tostring(lp.error)..' search='..tostring(lp:discoveryStatus()))
end
local function guarded(fn,...)
    local ok,reason=pcall(fn,...)
    if not ok then print('LAN_SMOKE_FAIL role='..role..' stage='..tostring(stage)..' reason='..tostring(reason)); finished=true; love.event.quit(1) end
end
function love.load() guarded(load) end
function love.update(dt) guarded(update,dt) end
function love.draw()
    if finished or not app then return end
    guarded(function()
        app.draw()
        if capture and not captures[capture] then
            local name=capture
            love.graphics.captureScreenshot(function(pixels)
                local f=assert(io.open(root..'/'..name,'wb')); f:write(pixels:encode('png'):getString()); f:close()
            end)
            captures[name]=true
        end
        capture=nil
    end)
end
