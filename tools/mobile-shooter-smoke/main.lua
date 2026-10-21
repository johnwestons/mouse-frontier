io.stdout:setvbuf('no')
local app,c,stage,finished,advance
local checks=0
local ShooterPad=require('game.mobile_shooter_controls')
local Accessibility=require('game.accessibility')
local function check(value,message) checks=checks+1; assert(value,message) end
local function protect(fn)
    local ok,err=xpcall(fn,debug.traceback)
    if not ok then print('MOBILE_SHOOTER_FAIL '..tostring(err)); finished=true; love.event.quit(1) end
end
local function touch(event,id,x,y)
    local ox,oy,sx,sy=require('game.viewport').transform(960,720)
    app[event](id,ox+x*sx,oy+y*sy,0,0,1)
end
local function padTouch(event,id,dx,dy)
    local p=ShooterPad.layout(960,720)
    local x,y,r=p.x,p.y,p.r
    if id=='fire' then x,y,r=p.fireX,p.fireY,p.fireR end
    touch(event,id,x+(dx or 0)*r,y+(dy or 0)*r)
end
local function tick() app.update(.02) end
local function guardedTouches(s)
    local p=ShooterPad.layout(960,720)
    local controls=c.getMobileControls()
    local gx,gy=p.aimRight-2,p.guardTop+2
    check((gx-p.x)^2+(gy-p.y)^2>p.r^2,'guard test must begin outside the visible stick')
    local x,y=s.aimX,s.aimY
    touch('touchpressed','guard-aim',gx,gy)
    check(controls.rangePad.aimTouch=='guard-aim' and s.aimX==x and s.aimY==y,'near-stick touch became direct aiming')
    touch('touchpressed','guard-blocked',p.x,p.y)
    touch('touchmoved','guard-blocked',640,280)
    check(controls.rangePad.aimTouch=='guard-aim' and s.aimX==x and s.aimY==y,'second stick touch stole aim')
    touch('touchpressed','guard-fire',p.fireLeft+2,gy)
    check(controls.rangePad.fireTouch=='guard-fire','near-FIRE touch was not reserved for the button')
    touch('touchmoved','guard-aim',400,300)
    touch('touchmoved','guard-fire',600,250); tick()
    check(controls.rangePad.aimTouch=='guard-aim' and s.touchAim==nil,'dragging the stick into the field changed touch ownership')
    check(c.presentationRuntime.getZoom()==1,'guarded thumb touches triggered pinch zoom')
    touch('touchreleased','guard-aim',400,300)
    touch('touchreleased','guard-fire',600,250)
    touch('touchreleased','guard-blocked',640,280)
    x,y=s.aimX,s.aimY; tick()
    check(s.aimX==x and s.aimY==y and not s.fireHeld,'guard touch release left aiming or firing active')
end
local function assistedAiming(s)
    local access=Accessibility.ensure(c.runtime.saveData)
    local previousAssist,previousSpeed=access.aimAssist,access.aimSensitivity
    local tx,ty=516,306
    local function trial(strength)
        access.aimAssist=strength; access.aimSensitivity=1
        s.aimX,s.aimY,s.touchAim=480,330,nil
        s.targets={{x=tx,y=ty,radius=16,material='paper',points=100,impacts={},age=1,life=30,velocity=0,sprite=1,scale=.22}}
        s.nextSpawn=999
        padTouch('touchpressed','aim',.25,0)
        for _=1,4 do tick() end
        local x,y=s.aimX,s.aimY
        padTouch('touchreleased','aim',.25,0); tick()
        check(s.aimX==x and s.aimY==y,'aim assist drifted after thumb release')
        return math.sqrt((tx-x)^2+(ty-y)^2),x,y
    end
    local offDistance,_,offY=trial(0)
    local onDistance,_,onY=trial(1)
    check(offY==330,'OFF added automatic vertical aiming')
    check(onY<offY and onDistance<offDistance-1,'ON did not pull the actual range reticle toward the nearby target')
    local x,y=s.aimX,s.aimY
    padTouch('touchpressed','aim'); tick()
    check(s.aimX==x and s.aimY==y,'resting thumb triggered automatic aiming')
    padTouch('touchmoved','aim',.25,0)
    c.ui.escMenuOpen=true; tick()
    check(s.aimX==x and s.aimY==y and not c.getMobileControls().rangePad.aimTouch,'pause did not neutralize aiming')
    padTouch('touchmoved','aim',1,0); tick()
    check(s.aimX==x and s.aimY==y,'paused touch movement moved the reticle')
    padTouch('touchreleased','aim',1,0)
    c.ui.escMenuOpen=false; tick()
    check(s.aimX==x and s.aimY==y,'resuming restored a stale thumb hold')
    access.aimAssist,access.aimSensitivity=previousAssist,previousSpeed
end
local function range()
    local Range=require('game.shooting_range'); local data=c.runtime.saveData
    local s=assert(Range.new(data,{preferences={},highScores={}},c.catalog))
    assert(Range.keypressed(s,'return',data,c.catalog)=='start'); c.runtime.shootingRange=s
    c.presentationRuntime.resetCamera()
    padTouch('touchpressed','aim')
    local x,y=s.aimX,s.aimY; tick()
    check(s.aimX==x and s.aimY==y,'touching stick center jumped the reticle')
    padTouch('touchmoved','aim',1,0); tick()
    check(s.aimX>x and s.aimY==y,'source range joystick did not move aim')
    x=s.aimX; local sx,sy=Range.sway(s,c.catalog)
    s.targets={{x=x+sx,y=y+sy,radius=16,material='paper',points=100,impacts={},age=0,life=30,velocity=0,sprite=1,scale=.22}}
    padTouch('touchpressed','fire')
    check(s.shots==1 and s.hits==1 and s.aimX==x,'right FIRE did not shoot existing aim')
    padTouch('touchmoved','fire',.58,.42); tick()
    check(s.aimX>x,'second thumb stole the aiming stick')
    check(c.presentationRuntime.getZoom()==1,'two-thumb controls triggered pinch zoom')
    padTouch('touchreleased','fire',.58,.42)
    padTouch('touchreleased','aim',1,0); x=s.aimX; tick()
    check(s.aimX==x and not s.fireHeld,'release left aim or fire stuck')
    guardedTouches(s)
    assistedAiming(s)
    padTouch('touchpressed','aim',.47,-.28)
end
local function settings()
    c.runtime.lastStand=nil; c.runtime.saveData.lastStand=nil
    c.ui.escMenuOpen=false; c.ui.optionsOpen=true; c.runtime.optionsPage='accessibility'
    tick()
end
local function settingsControls()
    local access=Accessibility.ensure(c.runtime.saveData)
    local function press(name)
        local r=c.ui[name]
        check(r and r.w>=44 and r.h>=44,'missing or undersized aiming setting: '..name)
        local x,y=r.x+r.w/2,r.y+r.h/2
        touch('touchpressed','settings',x,y); touch('touchreleased','settings',x,y)
    end
    local assist,speed=access.aimAssist,access.aimSensitivity
    press('accessAimAssistUp')
    check(math.abs(access.aimAssist-assist-.05)<.001,'host aim-assist increase button failed')
    press('accessAimAssistDown')
    check(math.abs(access.aimAssist-assist)<.001,'host aim-assist decrease button failed')
    press('accessAimSensitivityUp')
    check(math.abs(access.aimSensitivity-speed-.1)<.001,'host aim-speed increase button failed')
    press('accessAimSensitivityDown')
    check(math.abs(access.aimSensitivity-speed)<.001,'host aim-speed decrease button failed')
end
local function ambush()
    padTouch('touchreleased','aim',.47,-.28); c.runtime.shootingRange=nil
    local data=c.runtime.saveData; data.scene='train'; c.runtime.scene='train'
    local rules=require('game.train_ambush_rules'); local s=rules.start(data); s.phase='combat'
    for _,v in ipairs(s.vehicles) do
        if v.active then v.motion.phase='matched'; v.motion.clock=0 end
        for _,crew in ipairs(v.crew) do crew.phase='hidden'; crew.timer=999 end
    end
    tick()
    local Shooting=require('game.first_person_shooting'); local original=Shooting.setAim; local aimed
    Shooting.setAim=function(gun,x,y) aimed=gun; original(gun,x,y) end
    padTouch('touchpressed','aim',1,0); tick()
    Shooting.setAim=original
    check(aimed and aimed.aimX>480 and s.shots==0,'native ambush joystick did not move independently')
    padTouch('touchreleased','aim',1,0)
    local x=aimed.aimX; tick(); check(aimed.aimX==x,'native ambush stick drifted after release')
end
local function defense()
    c.runtime.saveData.trainAmbush.active=false; c.runtime.trainAmbush=nil
    c.runtime.scene='stop'; c.runtime.saveData.scene='stop'
    local q={state='shootout',holdElapsed=0,kills=0,enemyMorale=100,positionIntegrity=100,loanAmmo=48,loanActive=true}
    c.runtime.saveData.lastStand=q
    local battle=require('game.last_stand_shootout').new(q,c.runtime.saveData,c.catalog,'wide',960,720)
    c.runtime.lastStand={quest=q,mode='shootout',capture=true,shootout=battle,touchControls=true,clock=0}
    padTouch('touchpressed','aim',1,0); local x=battle.gun.aimX; tick()
    check(battle.gun.aimX>x,'native Last Stand joystick did not move aim')
    padTouch('touchpressed','fire')
    check(battle.fireHeldSources.pad,'native Last Stand FIRE did not hold')
    padTouch('touchreleased','aim',1,0); padTouch('touchreleased','fire')
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
            padTouch('touchreleased','aim',.47,-.28)
            love.window.setMode(1440,720,{vsync=0}); range()
        elseif stage==2 then ambush()
        elseif stage==3 then defense()
        elseif stage==4 then settings()
        else
            settingsControls()
            print('MOBILE_SHOOTER_OK checks='..checks..' sourceApplication=true twoThumbs=true guardCapture=true aimAssist=true pauseNeutral=true settingsButtons=true screenshots=5')
            finished=true; love.event.quit(0)
        end
        stage=stage+1; advance=false
    end)
end
function love.draw()
    if finished or advance then return end
    protect(function()
        app.draw()
        local names={'01-range-tablet.png','02-range-phone.png','03-ambush-phone.png','04-last-stand-phone.png','05-aim-settings-phone.png'}
        love.graphics.captureScreenshot(names[stage]); advance=true
    end)
end
