io.stdout:setvbuf('no')
local app,c,stage,finished,advance
local checks=0
local function check(value,message) checks=checks+1; assert(value,message) end
local function protect(fn)
    local ok,err=xpcall(fn,debug.traceback)
    if not ok then print('MOBILE_SHOOTER_FAIL '..tostring(err)); finished=true; love.event.quit(1) end
end
local function touch(event,id,x,y)
    local ox,oy,sx,sy=require('game.viewport').transform(960,720)
    app[event](id,ox+x*sx,oy+y*sy,0,0,1)
end
local function tick() app.update(.02) end
local function range()
    local Range=require('game.shooting_range'); local data=c.runtime.saveData
    local s=assert(Range.new(data,{preferences={},highScores={}},c.catalog))
    assert(Range.keypressed(s,'return',data,c.catalog)=='start'); c.runtime.shootingRange=s
    c.presentationRuntime.resetCamera()
    touch('touchpressed','aim',112,500)
    local x,y=s.aimX,s.aimY; tick()
    check(s.aimX==x and s.aimY==y,'touching stick center jumped the reticle')
    touch('touchmoved','aim',176,500); tick()
    check(s.aimX>x and s.aimY==y,'source range joystick did not move aim')
    x=s.aimX; local sx,sy=Range.sway(s,c.catalog)
    s.targets={{x=x+sx,y=y+sy,radius=16,material='paper',points=100,impacts={},age=0,life=30,velocity=0,sprite=1,scale=.22}}
    touch('touchpressed','fire',852,500)
    check(s.shots==1 and s.hits==1 and s.aimX==x,'right FIRE did not shoot existing aim')
    touch('touchmoved','fire',880,520); tick()
    check(s.aimX>x,'second thumb stole the aiming stick')
    check(c.presentationRuntime.getZoom()==1,'two-thumb controls triggered pinch zoom')
    touch('touchreleased','fire',880,520)
    touch('touchreleased','aim',176,500); x=s.aimX; tick()
    check(s.aimX==x and not s.fireHeld,'release left aim or fire stuck')
    touch('touchpressed','aim',142,482)
end
local function ambush()
    touch('touchreleased','aim',142,482); c.runtime.shootingRange=nil
    local data=c.runtime.saveData; data.scene='train'; c.runtime.scene='train'
    local rules=require('game.train_ambush_rules'); local s=rules.start(data); s.phase='combat'
    for _,v in ipairs(s.vehicles) do
        if v.active then v.motion.phase='matched'; v.motion.clock=0 end
        for _,crew in ipairs(v.crew) do crew.phase='hidden'; crew.timer=999 end
    end
    tick()
    local Shooting=require('game.first_person_shooting'); local original=Shooting.setAim; local aimed
    Shooting.setAim=function(gun,x,y) aimed=gun; original(gun,x,y) end
    touch('touchpressed','aim',176,500); tick()
    Shooting.setAim=original
    check(aimed and aimed.aimX>480 and s.shots==0,'native ambush joystick did not move independently')
    touch('touchreleased','aim',176,500)
    local x=aimed.aimX; tick(); check(aimed.aimX==x,'native ambush stick drifted after release')
end
local function defense()
    c.runtime.saveData.trainAmbush.active=false; c.runtime.trainAmbush=nil
    c.runtime.scene='stop'; c.runtime.saveData.scene='stop'
    local q={state='shootout',holdElapsed=0,kills=0,enemyMorale=100,positionIntegrity=100,loanAmmo=48,loanActive=true}
    c.runtime.saveData.lastStand=q
    local battle=require('game.last_stand_shootout').new(q,c.runtime.saveData,c.catalog,'wide',960,720)
    c.runtime.lastStand={quest=q,mode='shootout',capture=true,shootout=battle,touchControls=true,clock=0}
    touch('touchpressed','aim',176,500); local x=battle.gun.aimX; tick()
    check(battle.gun.aimX>x,'native Last Stand joystick did not move aim')
    touch('touchpressed','fire',852,500)
    check(battle.fireHeldSources.pad,'native Last Stand FIRE did not hold')
    touch('touchreleased','aim',176,500); touch('touchreleased','fire',852,500)
    check(not battle.fireHeldSources.pad,'native Last Stand FIRE stayed held')
    x=battle.gun.aimX; tick(); check(battle.gun.aimX==x,'native Last Stand drifted')
end
function love.load()
    protect(function()
        require('game.smoke_playthrough').install=function(value) c=value end
        app=require('game.application_composition').new({engine=love}); app.installSmoke(); app.load()
        c.runtime.selectedSlot=99
        local data=c.newSave(c.characters[1]); data.homeStop=nil; data.location=2; data.scene='train'; data.passengers={}
        local entered,reason=c.enterGame(data)
        check(entered,'fixture campaign failed: '..tostring(reason))
        c.runtime.scene='stop'; c.runtime.saveData.scene='stop'; c.runtime.saveData.stopped=true
        require('game.item_instances').write(c.runtime.saveData,nil,{kind='equipment',index=2},'frontier-sr22-pistol')
        c.runtime.saveData.ammo['22lr']=100
        check(c.getMobileControls():isEnabled(),'mobile preview must be enabled')
        range(); stage=1
    end)
end
function love.update()
    if finished or not advance then return end
    protect(function()
        if stage==1 then
            touch('touchreleased','aim',142,482)
            love.window.setMode(1440,720,{vsync=0}); range()
        elseif stage==2 then ambush()
        elseif stage==3 then defense()
        else
            print('MOBILE_SHOOTER_OK checks='..checks..' sourceApplication=true twoThumbs=true screenshots=4')
            finished=true; love.event.quit(0)
        end
        stage=stage+1; advance=false
    end)
end
function love.draw()
    if finished or advance then return end
    protect(function()
        app.draw()
        local names={'01-range-tablet.png','02-range-phone.png','03-ambush-phone.png','04-last-stand-phone.png'}
        love.graphics.captureScreenshot(names[stage]); advance=true
    end)
end
