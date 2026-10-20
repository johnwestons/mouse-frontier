-- Real application updates/rendering; the unslotted QA journey cannot write a
-- campaign or touch the user's game identity.
local root=assert(os.getenv('NPC_LIFE_SMOKE_ROOT')):gsub('\\','/')
local output=assert(os.getenv('NPC_LIFE_SMOKE_OUTPUT')):gsub('\\','/')
package.path=root..'/?.lua;'..package.path
local prefix=os.getenv('MOUSE_FRONTIER_MOBILE')=='1' and 'mobile' or 'desktop'
local captureOnly=os.getenv('NPC_LIFE_CAPTURE_ONLY')=='1'
local app,ctx,game,commands
local checks,clock,finished=0,0,false
local function check(value,message) assert(value,message); checks=checks+1 end
local function update()
    clock=clock+.05; app.update(.05)
    check(game.state=='game' and game.selectedSlot==nil,'QA journey left its gameplay boundary')
end
local function capture(name)
    love.graphics.clear(0,0,0,1); app.draw()
    local complete=false
    love.graphics.captureScreenshot(function(data)
        local encoded=data:encode('png'); local file=assert(io.open(output..'/'..prefix..'-'..name..'.png','wb'))
        file:write(encoded:getString()); file:close(); encoded:release(); data:release(); complete=true
    end)
    love.graphics.present(); check(complete,'screenshot failed '..name)
end
local function report(ok,message)
    local text='SUMMARY status='..(ok and 'passed' or 'failed')..' checks='..checks..' errors='..(ok and 0 or 1)
    if not ok then text=text..'\n'..tostring(message) end
    local file=assert(io.open(output..'/'..prefix..'-report.txt','wb')); file:write(text..'\n'); file:close()
    print(text); io.stdout:flush()
end
local function run()
    local NPCs=require('game.scene_npcs'); local Settlements=require('game.settlements')
    update()
    local layout=game.saveData.stopLayouts['5']
    check(#layout.residentKeys==4,'fixture needs four assigned residents')
    local seen,shots,transfers={},{},{}
    for _,key in ipairs(layout.residentKeys) do
        local actor=game.saveData.npcStates[key]
        seen[actor.file]={}; transfers[actor.file]={scene=actor.scene,enter=false,exit=false}
    end
    local complete=false
    -- Independent chores and longer rests need several different outings,
    -- rather than the old short cycle containing every chore in a fixed order.
    for i=1,(captureOnly and 0 or 30000) do
        update()
        local all=true
        for _,key in ipairs(layout.residentKeys) do
            local actor=game.saveData.npcStates[key]
            local state=transfers[actor.file]
            if state.scene~=actor.scene then
                state[actor.scene=='house' and 'enter' or 'exit']=true; state.scene=actor.scene
            end
            if actor.routineAction then seen[actor.file][actor.routineAction]=true end
            if actor.scene=='stop' then
                check(Settlements.isWalkable(5,actor.x,actor.y),'resident walked off the authored floor')
                check(NPCs.find(game.saveData,actor.file,'house',actor.homeDoor)==nil,'resident cloned indoors')
                local shot=actor.routineAction
                if shot=='carry' and actor.moving then shot='carry-walking' end
                local name=shot and actor.file:gsub('%.png$','')..'-'..shot
                local visiblePhase=actor.moving or (actor.routineClock or 0)>=.4
                if name and visiblePhase and not shots[name] then capture(name); shots[name]=true; shots[shot]=true end
            else check(NPCs.find(game.saveData,actor.file,'stop')==nil,'resident cloned outside') end
            local actions=seen[actor.file]
            all=all and actions.sweep and actions.carry and actions.tend and state.enter and state.exit
        end
        if #(game.npcActors or {})>=3 and not shots.population then capture('residents-outside'); shots.population=true end
        if all then complete=true; break end
    end
    if not captureOnly then
        check(complete,'one or more residents failed a full home/chore cycle')
        check(shots['carry-walking'],'carrying never used real walking')
    end
    -- Enter a home through the real scene transaction at its authored doorway.
    local resident
    for _=1,2000 do
        for _,key in ipairs(layout.residentKeys) do
            local actor=game.saveData.npcStates[key]
            if actor.scene=='house' then resident=actor; break end
        end
        if resident then break end
        update()
    end
    check(resident~=nil,'no resident returned home')
    local file,door=resident.file,resident.homeDoor
    game.player.x,game.player.y=Settlements.doorPoint(5,door)
    local reply=commands.submit('scene.enterHouse',{door=door})
    check(reply.ok,'house entry rejected: '..tostring(reply.reason))
    check(game.scene=='house' and game.saveData.activeHouseDoor==door,'house transaction did not change scene')
    check(NPCs.find(game.saveData,file,'house',door)~=nil,'home occupant disappeared at entry')
    capture('resident-home')
    local actor=NPCs.find(game.saveData,file,'house',door)
    game.player.x,game.player.y=actor.x+20,actor.y
    NPCs.refresh(game)
    game.tradeOpen=true
    local selected=game.saveData.currentNPC; local x,y=game.npcActor.x,game.npcActor.y
    for _=1,40 do update() end
    check(game.saveData.currentNPC==selected and game.npcActor.x==x and game.npcActor.y==y,'open panel changed its resident')
    game.tradeOpen=false
    for _=1,40 do update() end
    local storage
    for _,item in ipairs(game.saveData.droppedItems) do
        if item.houseStorageHotspot and item.scene=='house' and item.location==5 and item.houseDoor==door then storage=item; break end
    end
    check(storage~=nil,'furnished house is missing its fixed storage target')
    game.player.x,game.player.y=require('game.util').clampHouseFloor(storage.x-45,storage.y+25)
    local px,py=require('game.world_view').toScreen(storage.x,storage.y)
    local ox,oy,sx,sy=require('game.viewport').transform(960,720)
    love.mouse.getPosition=function() return ox+px*sx,oy+py*sy end
    update(); capture('house-storage-marker')
    check(ctx.state.ui.interaction and ctx.state.ui.interaction.houseStorageHotspot,'fixed storage was not selected')
    if os.getenv('MOUSE_FRONTIER_MOBILE')=='1' then
        app.touchpressed('storage-tap',ox+px*sx,oy+py*sy)
        app.touchreleased('storage-tap',ox+px*sx,oy+py*sy)
    else app.keypressed('e') end
    check(game.inventoryOpen and game.chestOpen and game.activeChest==storage,'fixed storage did not open normally')
    capture('house-storage-open')
end
function love.load()
    local ok,message=xpcall(function()
        love.filesystem.setSymlinksEnabled(true)
        if not love.filesystem.getInfo('assets') then love.filesystem.mount(root,'',true) end
        love.math.setRandomSeed(10172026)
        love.keyboard.isDown=function() return false end
        local Systems=require('game.systems'); local original=Systems.smokeComposition.new
        Systems.smokeComposition.new=function(context) ctx=context; return original(context) end
        local Commands=require('game.coop_inventory_runtime'); local originalCommands=Commands.new
        Commands.new=function(context)
            local detached={}; for key,value in pairs(context) do detached[key]=value end
            detached.checkpoint=nil; detached.clock=function() return clock end
            commands=originalCommands(detached); return commands
        end
        app=require('game.application_composition').new({engine=love})
        Commands.new=originalCommands; Systems.smokeComposition.new=original
        app.load(); game=ctx.state.runtime
        local data=ctx.services.sessionBootstrap.newSave('mail-mouse.png')
        data.homeStop={version=require('game.home_stop').VERSION,stage='departed',suppliesCollected=true,repairComplete=true}
        data.location=5; data.scene='stop'; data.playerX,data.playerY=870,600
        data.npcRoster={'botanist-frog.png','conductor-cat.png','cook-frog.png','cook-mouse.png'}
        data.events['5']={id='resolved'}
        data.audio.musicVolume=0; data.audio.sfxVolume=0; data.audio.rainVolume=0
        check(ctx.services.sessionBootstrap.enterGame(data),'could not enter QA journey')
        check(love.filesystem.getIdentity()=='mouse-frontier-npc-life-qa','QA identity changed')
    end,debug.traceback)
    if not ok then finished=true; report(false,message); love.event.quit(1) end
end
function love.update()
    if finished then return end; finished=true
    local ok,message=xpcall(run,debug.traceback)
    report(ok,message)
    if ok then app.quit() end
    love.event.quit(ok and 0 or 1)
end
function love.draw() end
function love.errorhandler(message)
    pcall(report,false,debug.traceback(tostring(message),2))
    return function() return 1 end
end
