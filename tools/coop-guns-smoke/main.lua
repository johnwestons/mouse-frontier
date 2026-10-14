-- One full source app, real PNG collision masks and isolated disk checkpoints.
-- This does not claim a network guest capture or physical-device acceptance.
io.stdout:setvbuf('no')
local Save=require('game.save'); local Schema=require('game.save_schema')
local Items=require('game.item_instances'); local Rules=require('game.train_ambush_rules')
local Scene=require('game.train_ambush_scene'); local Viewport=require('game.viewport')
local app,c,authority,originalWrite,capture,finished,waitClock
local checks=0
local function check(value,message) checks=checks+1; assert(value,message) end
local function guard(fn,...)
    local ok,reason=pcall(fn,...)
    if not ok then
        if originalWrite then love.filesystem.write=originalWrite; originalWrite=nil end
        print('COOP_GUNS_FAIL '..tostring(reason)); finished=true; love.event.quit(1)
    end
end
local function press(x,y)
    local ox,oy,sx,sy=Viewport.transform(960,720)
    app.mousemoved(ox+x*sx,oy+y*sy,0,0,false)
    app.mousepressed(ox+x*sx,oy+y*sy,1,false); app.mousereleased(ox+x*sx,oy+y*sy,1,false)
end
local function load()
    require('game.smoke_playthrough').install=function(value) c=value end
    local Guns=require('game.coop_guns'); local install=Guns.install
    Guns.install=function(service,context) authority=service; return install(service,context) end
    app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
    c.runtime.selectedSlot=99
    local data=c.newSave(c.characters[1]); data.location=2; data.scene='train'; data.passengers={}
    check(c.enterGame(data),'fixture campaign failed'); data=c.runtime.saveData
    Items.write(data,nil,{kind='equipment',index=2},'frontier-22-lever-rifle'); data.ammo['22lr']=40
    local state=Rules.start(data); state.phase='combat'
    for _,vehicle in ipairs(state.vehicles) do
        if vehicle.active then vehicle.motion.phase='matched'; vehicle.motion.clock=0 end
        for _,crew in ipairs(vehicle.crew) do crew.phase='hidden'; crew.timer=999 end
    end
    app.update(.01)
    local x,y,target
    for py=170,455,3 do
        for px=170,800,3 do
            local candidate=Scene.target(state,960,720,px,py)
            local solid=candidate and candidate.kind=='hull' and candidate.vehicle=='pickup'
            if solid then
                for _,offset in ipairs({{-2,0},{2,0},{0,-2},{0,2}}) do
                    local neighbor=Scene.target(state,960,720,px+offset[1],py+offset[2])
                    if not neighbor or neighbor.kind~='hull' or neighbor.vehicle~='pickup' then solid=false; break end
                end
            end
            if solid then x,y,target=px,py,candidate; break end
        end
        if target then break end
    end
    check(target,'no real pickup pixel inside the carriage window')
    local pickup=Rules.vehicle(state,'pickup'); local before=pickup.hull
    press(x,y)
    check(authority and authority.handlers['gun.fire'],'production gun authority was not installed')
    check(data.ammo['22lr']==39 and pickup.hull<before and state.shots==1,'native host shot failed')
    check(not authority.pendingSave,'host shot checkpoint did not finish')
    local id=state.weaponSession.itemId
    local disk=assert(Save.read(99)); check(disk.ammo['22lr']==39 and disk.trainAmbush.weaponSession.itemId==id,'disk shot identity/cost mismatch')
    check(not disk.trainAmbush.weaponSession.aimX and not disk.trainAmbush.weaponSession.ads,'private input leaked into disk save')
    for _=1,12 do app.update(.1) end
    originalWrite=love.filesystem.write
    love.filesystem.write=function(path,...)
        if path=='saves/slot99.lua.tmp' then return false,'native fixture save failure' end
        return originalWrite(path,...)
    end
    before=pickup.hull; press(x,y)
    check(authority.pendingSave and data.ammo['22lr']==38 and pickup.hull<before and state.shots==2,'failed save did not retain one shot')
    local requestId=authority.requests.host.high; local cached=authority.requests.host.cache[requestId]
    check(cached.response.ok and cached.response.savePending and not cached.response.durable,'pending receipt claimed durability')
    local request=assert(require('game.net.codec').decode(cached.fingerprint,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128}))
    check(request.command=='gun.fire','native input bypassed the strict shot command')
    local hp=pickup.hull; check(authority:execute('host',0,request).ok and pickup.hull==hp and data.ammo['22lr']==38,'shot replay charged twice')
    love.filesystem.write=originalWrite; originalWrite=nil
    check(authority:retryCheckpoint(),'real disk retry failed'); app.update(.01)
    check(authority:execute('host',0,request).durable and state.shots==2,'retried shot receipt failed')
    app.keypressed('r'); app.keyreleased('r')
    check(state.weaponSession.reloadTimer>0,'native reload did not use the owned gun')
    app.keypressed('c'); app.keyreleased('c')
    check(state.cover,'native cover command failed')
    disk=assert(Save.read(99))
    check(disk.ammo['22lr']==38 and disk.trainAmbush.shots==2 and disk.trainAmbush.cover,'saved retry/reload/cover mismatch')
    check(disk.trainAmbush.weaponSession.reloadTimer==state.weaponSession.reloadTimer and Schema.validate(disk),'saved reload stage failed')
    capture=true; waitClock=0
end
function love.load() guard(load) end
function love.update(dt)
    if finished then return end
    if capture=='cover' then
        guard(function()
            app.update(.1); app.update(.1)
            check(c.runtime.saveData.trainAmbush.coverProgress==1,'full native cover transition failed')
            capture='draw-cover'
        end)
    end
    if capture==false then
        waitClock=waitClock+dt
        if waitClock>.4 then
            guard(function()
                check(app.quit()~=true,'quit cancelled')
                print('COOP_GUNS_OK checks='..checks..' application=true pngCollision=true hostCommands=true diskRetry=true guestNetwork=false')
                finished=true; love.event.quit(0)
            end)
        end
    end
end
function love.draw()
    if finished or not capture then return end
    if capture=='cover' then return end
    guard(function()
        app.draw()
        if capture==true then love.graphics.captureScreenshot('01-native-host-cover.png'); capture='cover'
        else love.graphics.captureScreenshot('02-native-host-full-cover.png'); capture=false end
    end)
end
