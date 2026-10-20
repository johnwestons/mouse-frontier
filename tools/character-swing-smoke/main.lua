local root=assert(os.getenv('CHARACTER_ACTION_SMOKE_ROOT')):gsub('\\','/')
local output=assert(os.getenv('CHARACTER_ACTION_SMOKE_OUTPUT')):gsub('\\','/')
package.path=root..'/?.lua;'..package.path
local prefix=os.getenv('MOUSE_FRONTIER_MOBILE')=='1' and 'mobile' or 'desktop'
local A,W,manager,names,ui,grips
local checks,finished=0,false
local function check(ok,msg)assert(ok,msg);checks=checks+1 end
local function capture(name)
    local done=false
    love.graphics.captureScreenshot(function(data)
        local encoded=data:encode('png');local file=assert(io.open(output..'/'..prefix..'-'..name..'.png','wb'))
        file:write(encoded:getString());file:close();encoded:release();data:release();done=true
    end)
    love.graphics.present();check(done,'capture did not finish')
end
local function render(file,weapon,frame,x,y,facing)
    local a=manager[file].swing;local phase=(frame-.5)*.35/6
    check(a and a.count==6 and a.w==a.h*2 and #a.handPoints==6,'incomplete swing: '..file)
    check(A.actionFrame(a,phase)==frame,'body skipped frame')
    check(A.draw(manager,file,'swing',x,y,100,128,facing,phase,phase),'body draw failed')
    check(W.draw(manager,file,weapon,W.itemSprite(ui,weapon),x,y,100,128,facing,phase,'swing',{}),'weapon attachment failed: '..weapon)
end
local function page(start,weaponPage)
    local g=love.graphics;local width,height=g.getDimensions()
    g.origin();g.clear(.08,.10,.13,1);g.push();g.scale(width/1280,height/720)
    for row=0,2 do
        local file=weaponPage and names[1] or names[start+row]
        local weapon=weaponPage and grips[start+row] or ({'train-wrench','frontier-short-sword','scrap-hatchet','rail-spike-spear'})[row+1]
        if file and weapon then
            A.retain(manager,{[file]=true})
            local y=row*240
            if row%2==0 then g.setColor(.94,.92,.87,1) else g.setColor(.07,.12,.17,1) end
            g.rectangle('fill',0,y,1280,240)
            g.setColor(row%2==0 and 0 or 1,row%2==0 and 0 or 1,row%2==0 and 0 or 1,1)
            g.print(file..' / '..weapon..(row%2==0 and ' / east' or ' / west'),10,y+5)
            for frame=1,6 do render(file,weapon,frame,(frame-.5)*213,y+167,row%2==0 and 1 or -1) end
        end
    end
    g.pop();capture((weaponPage and 'weapons-' or 'roster-')..string.format('%02d',math.floor((start+2)/3)))
end
local function run()
    A.retain(manager,{['botanist-frog.png']=true})
    for frame=1,6 do
        local g=love.graphics;g.origin();g.clear(.94,.92,.87,1)
        render('botanist-frog.png','train-wrench',frame,240,240,1)
        capture('frog-frame-'..frame)
    end
    for start=1,#names,3 do page(start,false) end
    for start=1,#grips,3 do page(start,true) end
    -- Every character and every equipped item resolve both reflected poses.
    for _,file in ipairs(names) do
        A.retain(manager,{[file]=true});local set=manager[file]
        local _,poses=A.previewActions(set);local found=false
        for _,action in ipairs(poses) do if action=='swing' then found=true end end
        check(found,'viewer omits swing')
        for _,weapon in ipairs(grips) do for _,facing in ipairs({-1,1}) do for frame=1,6 do
            render(file,weapon,frame,200,200,facing)
        end end end
    end
    A.retain(manager,{});check(next(manager.sets)==nil,'streamer did not release characters')
end
local function report(ok,msg)
    local summary='SUMMARY status='..(ok and 'passed' or 'failed')..' characters='..tostring(names and #names or 0)..' checks='..checks..' errors='..(ok and 0 or 1)
    local file=assert(io.open(output..'/'..prefix..'-report.txt','wb'));file:write(summary..'\n'..(ok and '' or tostring(msg)));file:close();print(summary);io.stdout:flush()
end
function love.load()
    local ok,msg=xpcall(function()
        A=require('game.character_animation');W=require('game.weapon_attachment')
        manager=A.load('assets/sprites/character-animations',function(path)
            if love.filesystem.getInfo(path) then local im=love.graphics.newImage(path);im:setFilter('nearest','nearest');return im end
        end)
        names={};for file in pairs(require('game.character_swing_profiles').characters) do names[#names+1]=file end;table.sort(names)
        grips={};for weapon in pairs(require('game.melee_weapon_grips'))do grips[#grips+1]=weapon end;table.sort(grips)
        check(#names==55,'incomplete reviewed swing roster')
        local targets={}
        for _,name in ipairs({'ui','scenery','characters','characterImages','npcImages','mobImages','mobFiles','characterWalkImages',
            'npcWalkImages','characterActionImages','mobAttackImages','mobIdleImages','mobHitImages','mobDeathImages','mobWalkImages',
            'mobRangedImages','backgroundImages','familyImages','itemIdleImages'})do targets[name]={}end
        require('game.assets').load(targets);ui=targets.ui
    end,debug.traceback)
    if not ok then finished=true;report(false,msg);love.event.quit(1)end
end
function love.update()
    if finished then return end;finished=true
    local ok,msg=xpcall(run,debug.traceback);report(ok,msg);love.event.quit(ok and 0 or 1)
end
function love.draw()end
function love.errorhandler(msg)pcall(report,false,debug.traceback(tostring(msg),2));return function()return 1 end end
