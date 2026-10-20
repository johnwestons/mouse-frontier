-- Real LÖVE decoder, quads and production renderer, with an isolated identity.
local root=assert(os.getenv('CHARACTER_ACTION_SMOKE_ROOT')):gsub('\\','/')
local output=assert(os.getenv('CHARACTER_ACTION_SMOKE_OUTPUT')):gsub('\\','/')
package.path=root..'/?.lua;'..package.path
local prefix=os.getenv('MOUSE_FRONTIER_MOBILE')=='1' and 'mobile' or 'desktop'
local A,profiles,manager,names
local actions={'sit','lay','melee','ranged','use','hit','death','unconscious'}
local checks,finished=0,false
local function check(value,message) assert(value,message); checks=checks+1 end
local function capture(name)
    local done=false
    love.graphics.captureScreenshot(function(data)
        local encoded=data:encode('png')
        local file=assert(io.open(output..'/'..prefix..'-'..name..'.png','wb'))
        file:write(encoded:getString()); file:close(); encoded:release(); data:release(); done=true
    end)
    love.graphics.present(); check(done,'screenshot did not finish')
end
local function phase(animation,index)
    local p=animation.playback
    if p.introFrames then
        if index<=p.introFrames then return (index-.8)/p.fps end
        return p.introFrames/p.fps+(index-p.loopStart+.2)/p.holdFps
    end
    return p.duration and (index-.8)*p.duration/animation.count or (index-.8)/(p.fps or 6)
end
local function page(start)
    local g=love.graphics
    local screenW,screenH=g.getDimensions()
    g.clear(.08,.10,.13,1); g.push(); g.scale(screenW/1280,screenH/720)
    for column=0,1 do
        local file=names[start+column]
        if file then
            local set=manager[file]
            g.setColor(1,1,1); g.print(file,column*640+12,5)
            for row,action in ipairs(actions) do
                local animation=set[action]
                check(animation and animation.count==6 and animation.playback,'new action was not loaded: '..file..'/'..action)
                check(animation.w==animation.h*2,'action canvas was split incorrectly')
                local y=24+(row-1)*86
                if row%2==1 then g.setColor(.94,.92,.87,1) else g.setColor(.07,.12,.17,1) end
                g.rectangle('fill',column*640,y,640,84)
                g.setColor(row%2==1 and 0 or 1,row%2==1 and 0 or 1,row%2==1 and 0 or 1,1)
                g.print(action,column*640+4,y+2)
                for index=1,6 do
                    local elapsed=phase(animation,index)
                    check(A.actionFrame(animation,elapsed)==index,'wrong action frame')
                    check(A.draw(manager,file,action,column*640+(index-.5)*106.6,y+81,82,104,1,elapsed,elapsed),
                        'production draw failed')
                end
            end
        end
    end
    g.pop(); capture(string.format('actions-%02d',math.floor((start+1)/2)))
end
local function viewer()
    local noop=function() end
    local targets={}
    for _,name in ipairs({'ui','scenery','characters','characterImages','npcImages','mobImages','mobFiles',
        'characterWalkImages','npcWalkImages','characterActionImages','mobAttackImages','mobIdleImages',
        'mobHitImages','mobDeathImages','mobWalkImages','mobRangedImages','backgroundImages','familyImages','itemIdleImages'}) do targets[name]={} end
    require('game.assets').load(targets)
    local runtime={state='characters',characterScroll=0,animationClock=0}
    local context={runtime=runtime,width=960,height=720,ui=targets.ui,scenery=targets.scenery,
        characters=targets.characters,characterImages=targets.characterImages,npcImages=targets.npcImages,
        colors={cream={.96,.91,.79},brass={.63,.39,.17},panel={.17,.11,.08}},
        util=require('game.util'),catalog=require('game.catalog'),
        screenToGame=function(x,y)return x,y end,mobileEnabled=function()return prefix=='mobile' end,
        getCharacterAnimations=function()return manager end,
        drawAnimatedCharacter=function(file,action,x,y,w,h,facing,phase,motion)
            return A.draw(manager,file,action,x,y,w,h,facing,phase,runtime.animationClock,motion)
        end}
    for _,name in ipairs({'inventory','eventUI','engineUpgrades','trainUpgradeBalance','playerProgression',
        'stopHelpProgression','npcRelationships','merchantTrade','finaleProgression','maintenance'}) do context[name]={} end
    for _,name in ipairs({'readSave','canChooseEvent','writeSave','ensureStopLayout','currentTradeSource','drawLandscape',
        'drawTracks','drawLocomotive','drawTrainCar','isWeapon','travelCost','repairStatus','questSummary'}) do context[name]=noop end
    require('game.screen_ui').new(context)
    local ui=targets.ui
    local function draw()
        local w,h=love.graphics.getDimensions();local scale=math.min(w/960,h/720)
        love.graphics.origin();love.graphics.push();love.graphics.translate((w-960*scale)/2,(h-720*scale)/2);love.graphics.scale(scale)
        ui.drawCharacterSelect();love.graphics.pop()
    end
    for _,file in ipairs(names) do
        A.retain(manager,{[file]=true});runtime.characterPreviewFile=file
        for _,chore in ipairs({'sweep','carry','tend'}) do
            runtime.characterPreviewAction=chore;runtime.characterPreviewDirection='W'
            runtime.animationClock=runtime.animationClock+2;draw()
            check(#ui.characterPoseActions==12,'viewer omitted applicable actions: '..file)
            local listed={}
            for _,entry in ipairs(ui.characterPoseActions) do
                listed[entry.id]=true;local r=entry.control
                check(r.x>=205 and r.x+r.w<=756 and r.y>=444 and r.y+r.h<=556,'pose control outside modal')
            end
            for _,action in ipairs(actions) do check(listed[action],'viewer omitted '..action) end
            check(listed.sweep and listed.carry and listed.tend and listed.swing,'viewer omitted a chore or swing')
            check(runtime.characterPreviewDirection=='E' and not ui.characterDirections.W.active,'chore preview mirrored authored tools')
        end
    end
    local file='conductor-cat.png';A.retain(manager,{[file]=true});runtime.characterPreviewFile=file
    for _,action in ipairs({'sweep','carry','tend','death','unconscious'}) do
        runtime.characterPreviewAction=action;runtime.characterPreviewDirection='E'
        runtime.animationClock=runtime.animationClock+2;draw()
        runtime.animationClock=runtime.animationClock+.65;draw();capture('viewer-'..action)
    end
    -- Exercise overflow with real drawable strips, including future actions.
    local set=manager[file]
    for i=1,5 do set['extra_'..i]=set.use end
    runtime.characterPreviewPage=2;draw()
    check(ui.characterPosePageCount==2 and #ui.characterPoseActions==5,'viewer lost overflow actions')
    check(ui.characterPosePrev.y>=556 and ui.characterPoseNext.y+ui.characterPoseNext.h<ui.characterConfirm.y,'pagination overlaps profile or confirmation')
    capture('viewer-overflow')
    for i=1,5 do set['extra_'..i]=nil end
end
local function run()
    for start=1,#names,2 do
        local keep={[names[start]]=true}; if names[start+1] then keep[names[start+1]]=true end
        A.retain(manager,keep); page(start)
    end
    -- Enter, hold, cancel, rise and collapse through real draw calls as well.
    local file=names[1]; A.retain(manager,{[file]=true})
    local actor={intentX=1,intentY=0,moving=false}
    local set=manager[file]
    for _,action in ipairs({'sit','idle','lay','idle','unconscious'}) do
        for tick=0,100 do
            local clock=checks*.05
            check(A.draw(manager,file,action,100,200,82,104,1,tick*.05,clock,actor),'transition draw failed')
        end
    end
    viewer()
    A.retain(manager,{})
    check(next(manager.sets)==nil,'last scene retained character image allocations')
end
local function report(ok,message)
    local summary='SUMMARY status='..(ok and 'passed' or 'failed')..' characters='..tostring(names and #names or 0)..' checks='..checks..' errors='..(ok and 0 or 1)
    local file=assert(io.open(output..'/'..prefix..'-report.txt','wb'))
    file:write(summary..'\n'..(ok and '' or tostring(message)));file:close();print(summary);io.stdout:flush()
end
function love.load()
    local ok,message=xpcall(function()
        A=require('game.character_animation'); profiles=require('game.character_action_profiles')
        manager=A.load('assets/sprites/character-animations',function(path)
            if love.filesystem.getInfo(path) then local im=love.graphics.newImage(path);im:setFilter('nearest','nearest');return im end
        end)
        names={};for file in pairs(profiles.characters) do names[#names+1]=file end;table.sort(names)
        check(#names>0,'no reviewed characters installed')
    end,debug.traceback)
    if not ok then finished=true;report(false,message);love.event.quit(1) end
end
function love.update()
    if finished then return end; finished=true
    local ok,message=xpcall(run,debug.traceback);report(ok,message);love.event.quit(ok and 0 or 1)
end
function love.draw() end
function love.errorhandler(message)
    pcall(report,false,debug.traceback(tostring(message),2));return function() return 1 end
end
