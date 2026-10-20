io.stdout:setvbuf('no')
local app,c,stage,advance,finished
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
local function protect(fn)
    local ok,message=xpcall(fn,debug.traceback)
    if not ok then print('ACTION_MENU_FAIL '..message);finished=true;love.event.quit(1) end
end
local function target(id)
    local menu=assert(c.ui.actionMenu)
    for _,t in ipairs(menu.targets) do if t.id==id then
        local r=t.rect
        for row=1,9 do for col=1,9 do local x,y=r.x+r.w*col/10,r.y+r.h*row/10
            if r:contains(x,y) then return x,y end
        end end
    end end
    error('missing target '..id)
end
local function touch(event,id,x,y)
    local ox,oy,sx,sy=require('game.viewport').transform(960,720)
    app[event](id,ox+x*sx,oy+y*sy,0,0,1)
end
local function tap(id)
    local x,y=target(id);touch('touchpressed','test',x,y);touch('touchreleased','test',x,y)
end
function love.load()
    protect(function()
        require('game.smoke_playthrough').install=function(value)c=value end
        app=require('game.application_composition').new({engine=love});app.installSmoke();app.load()
        c.runtime.selectedSlot=99
        local data=c.newSave(c.characters[1]);data.homeStop=nil;data.location=2;data.scene='train';data.passengers={};data.stopped=true
        check(c.enterGame(data),'fixture could not enter game')
        c.runtime.dialogue=nil;c.runtime.saveData.resources={food=10,water=10,coal=10,oil=10}
        stage=1
    end)
end
local names={'01-dock','02-pose-wheel','03-radial','04-drawer','05-editor','06-small-phone','07-launcher'}
function love.update()
    if finished or not advance then return end
    protect(function()
        local Style=require('game.ui_layout');local manager=Style.manager();local menu=c.ui.actionMenu
        if stage==1 then
            local x,y=target('poses');touch('touchpressed','test',x,y)
            check(not menu.page,'control fired on press instead of release')
            touch('touchreleased','test',x,y);check(menu.page=='poses','pose shortcut failed')
        elseif stage==2 then
            tap('sit');check(c.runtime.playerPose=='sit','pose action did not reach gameplay')
            manager:setMenuLayout('radial');menu.lastLayout='radial';menu:setPage('main')
        elseif stage==3 then
            c.runtime.saveData.stopped=false
            tap('leave');check(c.runtime.scene=='train','disabled departure was dispatched')
            check(menu.notice~=nil,'disabled departure has no explanation');c.runtime.saveData.stopped=true
            manager:setMenuLayout('drawer');menu.lastLayout='drawer';menu:setPage('main')
        elseif stage==4 then
            tap('travel');check(c.runtime.travelConfirm==true,'travel did not open confirmation')
            check(c.runtime.travelTransition==nil,'travel departed without confirmation')
            c.runtime.travelConfirm=false
            c.ui.openGuiEditor();c.ui.actionMenuPreview='main'
            manager:set('actions_drawer_main_travel',{x=-40,y=20,scale=1.15,rotation=15})
        elseif stage==5 then
            app.keypressed('f2');app.keyreleased('f2')
            manager:setMenuLayout('dock');love.window.setMode(960,540,{vsync=0})
        elseif stage==6 then
            check(manager:save(),'GUI settings did not save')
            local loaded=Style.new({filesystem=love.filesystem,screen=function()return 'game_train'end})
            check(loaded:menuLayout()=='dock','base layout did not persist')
            check(loaded:get('actions_drawer_main_travel').rotation==15,'individual edit did not persist')
            love.window.setMode(1440,720,{vsync=0});c.ui.openDebugActivities()
        else
            local entries=c.ui.debugActivities:entries()
            if stage>7 then
                local previous=entries[stage-7]
                local r=c.runtime
                if previous.id=='range' then check(r.shootingRange~=nil,'range not visible')
                elseif previous.id=='ambush' then check(r.trainAmbush~=nil,'ambush not visible')
                elseif previous.id=='lastStand' then check(r.lastStand and r.lastStand.mode=='backyard','backyard not visible')
                elseif previous.id=='shootout' then check(r.lastStand and r.lastStand.mode=='shootout','shootout not visible')
                elseif previous.id=='firstAid' then check(r.firstAid and r.firstAid.debugPractice,'first aid not visible')
                elseif previous.id=='maintenance' then check(c.maintenanceSession.open,'maintenance not visible')
                elseif previous.id=='sewing' then check(r.outfitCraftingOpen,'sewing not visible')
                elseif previous.id=='repair' then check(r.weaponRepairOpen,'repair not visible')
                elseif previous.id=='battle' then check(r.state=='battle','battle not visible')
                elseif previous.area then check(r.scene=='expedition' and r.saveData.activeExpeditionArea==previous.area,'area not visible') end
                check(c.persistenceRuntime.checkpoint(),'activity checkpoint failed: '..previous.id)
                local restored,saveError=c.save.read(99);check(restored,previous.id..' invalid save: '..tostring(saveError))
                if previous.id=='firstAid' then
                    check(c.adventureComposition.journeyRules.resolveFirstAid('cancelled'),'practice exit failed');check(not r.firstAid,'practice retained modal')
                elseif previous.id=='sewing' then
                    app.keypressed('space');app.keyreleased('space')
                    check(require('game.outfit_crafting').project(r.saveData)~=nil,'sewing could not start with supplied materials')
                elseif previous.id=='repair' then
                    check(require('game.loot_progression').repairStatus(r.saveData,c.catalog,r.weaponRepairSelected).needed,'worn test weapon was not selected')
                end
                print('ACTIVITY_OK '..previous.id)
            else touch('touchpressed','launch',200,264);touch('touchreleased','launch',200,264) end
            local entry=entries[stage-6]
            if not entry then print('ACTION_MENU_OK checks='..checks..' activities='..#entries);finished=true;love.event.quit(0);return end
            if stage==7 then check(c.runtime.shootingRange~=nil,'Cheats button did not launch the range')
            else local ok,reason=c.ui.debugActivities:launch(entry.id,true);check(ok,entry.id..': '..tostring(reason)) end
            names[stage+1]=string.format('%02d-',stage+1)..entry.id:gsub(':','-')
        end
        app.update(.02);stage=stage+1;advance=false
    end)
end
function love.draw()
    if finished or advance then return end
    protect(function()
        app.draw()
        love.graphics.captureScreenshot(names[stage]..'.png')
        advance=true
    end)
end
