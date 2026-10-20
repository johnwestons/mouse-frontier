io.stdout:setvbuf('no')
local Scenario=require('scenario')
local Save=require('game.save')
local Crypto=require('game.net.crypto')
local Session=require('game.net.session')
local Viewport=require('game.viewport')
local scenario,finished,finishedAt
local native={deferredCalls=0,deferredSuccess=0}
local function guard(fn,...)
    local ok,reason=pcall(fn,...)
    if not ok then
        if scenario then pcall(scenario.guest.stop,scenario.guest);pcall(scenario.host.stop,scenario.host)end
        print('COOP_COMPANION_MANAGEMENT_FAIL '..tostring(reason));finished=true;love.event.quit(1)
    end
end
local function filesystem(prefix)
    assert(love.filesystem.createDirectory(prefix))
    local result={}
    for _,name in ipairs({'getInfo','createDirectory','write','read','load','remove'})do
        local method=name;result[method]=function(path,...)return love.filesystem[method](prefix..'/'..path,...)end
    end
    return result
end
function love.load()
    guard(function()
        assert(type(require('enet').host_create)=='function','real ENet unavailable')
        assert(type(require('socket').udp)=='function','real UDP discovery unavailable')
        local compatibility=assert(require('game.net.compatibility').compute(love.filesystem,Crypto.hash))
        local network={join=Session.join,host=function(context)
            local host,reason=Session.host(context);if not host then return nil,reason end
            local original=host.transport.disconnectLater
            host.transport.disconnectLater=function(transport,peer,code)
                native.deferredCalls=native.deferredCalls+1
                local ok,errorMessage=original(transport,peer,code)
                if ok then native.deferredSuccess=native.deferredSuccess+1 end
                native.peerState=peer:state();return ok,errorMessage
            end
            return host
        end}
        scenario=Scenario.new({clock=love.timer.getTime,hash=Crypto.hash,token=Crypto.token,compatibility=compatibility,
            hostFilesystem=filesystem('host'),guestFilesystem=filesystem('guest'),network=network,
            port=tonumber(os.getenv('MOUSE_FRONTIER_MANAGEMENT_PORT')) or 23124,
            discoveryPort=tonumber(os.getenv('MOUSE_FRONTIER_MANAGEMENT_DISCOVERY_PORT')) or 23125,
            checkpoint=function(value)return Save.write(98,value)end,readCheckpoint=function()return Save.read(98)end,
            capture=function(path)love.graphics.captureScreenshot(path)end,
            screenToGame=function(x,y)return Viewport.toGame(x,y,960,720)end,
            toScreen=function(x,y)local ox,oy,sx,sy=Viewport.transform(960,720);return ox+x*sx,oy+y*sy end,
            log=function(message)print('COOP_COMPANION_MANAGEMENT '..message)end})
        print('COOP_COMPANION_MANAGEMENT_BUILD '..compatibility.build)
    end)
end
function love.update(dt)
    if finished or not scenario then return end
    guard(function()
        if not scenario.finished then scenario:update(dt);return end
        finishedAt=finishedAt or love.timer.getTime()
        if love.timer.getTime()-finishedAt<.3 then return end
        assert(native.deferredCalls==1 and native.deferredSuccess==1,'real disconnect_later path did not complete once')
        for _,name in ipairs(Scenario.images)do assert(love.filesystem.getInfo(name),'missing screenshot '..name)end
        local result='COOP_COMPANION_MANAGEMENT_OK checks='..scenario.checks..' writes='..scenario.writes
            ..' joins='..scenario.joins..' screenshots='..#scenario.captures
            ..' actualENet=true actualUDPDiscovery=true durableKick=true saveRetry=true replacementKitIDs=true'
            ..' nativeDeferred='..native.deferredSuccess..' peerState='..tostring(native.peerState)
        assert(love.filesystem.write('result.rpt',result..'\n'));print(result)
        finished=true;love.event.quit(0)
    end)
end
function love.draw()
    if finished or not scenario or scenario.finished then return end
    guard(scenario.draw,scenario)
end
function love.quit()
    if scenario then scenario.guest:stop();scenario.host:stop()end
end
