-- Render every reviewed enemy combat frame through the production BattleUI.
-- This harness uses in-memory fixtures and never reads/writes campaign saves.
io.stdout:setvbuf('no')
local root=assert(os.getenv('MOUSE_FRONTIER_PROJECT_ROOT')):gsub('\\','/')
local assets=(os.getenv('MOUSE_FRONTIER_MOB_ASSET_ROOT') or root):gsub('\\','/')
local output=root..'/output/mob-combat'
package.path=root..'/?.lua;'..package.path
local function fileData(path)
    local file=assert(io.open(assets..'/'..path,'rb'));local bytes=file:read('*a');file:close()
    return love.filesystem.newFileData(bytes,path)
end
local function image(path)
    local data=fileData(path);local result=love.graphics.newImage(data);data:release()
    result:setFilter('nearest','nearest');return result
end
local function capture(canvas,name)
    local data=canvas:newImageData();local png=data:encode('png')
    local file=assert(io.open(output..'/'..name..'.png','wb'));file:write(png:getString());file:close()
    data:release();png:release()
end
local function run()
    local UI=require('game.battle_ui')
    local Mob=require('game.mob_combat_animation')
    local Catalog=require('game.catalog')
    local Grid=require('game.battle_grid')
    local data=require('game.save_schema').migrate({character='mouse-engineer.png',equipment={'frontier-short-sword'},traitBaselineApplied=true})
    local noop=function()end
    local font=fileData('assets/fonts/CourierPrime-Regular.ttf')
    love.graphics.setFont(love.graphics.newFont(font,20));font:release()
    local ctx={W=960,H=720,saveData=data,ui={playSfx=noop},scenery={},colors=require('game.config').colors,
        animationClock=0,playerProgression=require('game.player_progression'),drawAnimatedCharacter=noop,
        pointerPosition=function()return -1000,-1000 end,screenToGame=function(x,y)return x,y end,
        drawLandscape=function()love.graphics.clear(.15,.12,.08,1)end,drawGround=noop,
        button=function(label,x,y,w,h,enabled)
            love.graphics.setColor(.2,.14,.08,1);love.graphics.rectangle('fill',x,y,w,h,4,4)
            love.graphics.setColor(1,.85,.5,1);love.graphics.printf(label,x,y+8,w,'center',0,.65,.65)
            return{x=x,y=y,w=w,h=h}
        end}
    for _,name in ipairs({'characterImages','npcImages','mobImages','characterWalkImages','npcWalkImages',
        'mobAttackImages','mobIdleImages','mobHitImages','mobDeathImages','mobWalkImages','mobRangedImages','characterAnimations'})do ctx[name]={}end
    local ally={id='player',team='ally',name='Player',file='mouse-engineer.png',q=1,r=3,hp=20,maxHP=20,move=2,armor=2}
    local enemy={id='enemy1',team='enemy',name='Enemy',q=5,r=2,hp=20,maxHP=20,move=2,armor=1}
    ctx.battle={encounterId='mob-combat-audit',active=2,selected=2,round=1,phase='select',units={ally,enemy},
        tiles={},tileVariants={},obstacles={},abilitiesUsed={}}
    local canvas=love.graphics.newCanvas(960,720)
    local names={};for file in pairs(Mob.profiles)do names[#names+1]=file end;table.sort(names)
    local sourcePaths=setmetatable({},{__mode='k'})
    local draw=love.graphics.draw
    local last
    love.graphics.draw=function(img,quad,...)
        if sourcePaths[img]then last={path=sourcePaths[img],quad=quad}end
        return draw(img,quad,...)
    end
    local count,clock=0,0
    local collections={melee='mobAttackImages',ranged='mobRangedImages',hit='mobHitImages',death='mobDeathImages'}
    for _,mobile in ipairs({false,true})do
        ctx.mobileEnabled=mobile
        for _,file in ipairs(names)do
            enemy.file=file;enemy.name=file:gsub('%.png$','')
            for _,action in ipairs({'melee','ranged','hit','death'})do
                local path=Mob.profiles[file].paths[action]
                local sprite=image(path);sourcePaths[sprite]=path
                local iw,ih=sprite:getDimensions()
                ctx[collections[action]][file..'@combat']=sprite
                local start=clock
                for frame=1,6 do
                    enemy.hp=action=='death' and 0 or 20
                    enemy.action=action=='ranged' and 'ranged' or 'melee'
                    enemy.actionTimer=(action=='melee' or action=='ranged') and .68*(1-(frame-1)/6) or 0
                    enemy.hitTimer=action=='hit' and .58*(1-(frame-1)/6) or 0
                    ctx.animationClock=start+(frame-1)*(action=='death' and .85 or .68)/6
                    last=nil;love.graphics.setCanvas(canvas);UI.draw(ctx);love.graphics.setCanvas()
                    assert(last and last.path==path,file..'/'..action..' did not reach the production battle renderer')
                    local qx,_,qw,qh=last.quad:getViewport()
                    assert(math.abs(qx-(frame-1)*iw/6)<.01 and qw==iw/6 and qh==ih,file..'/'..action..' wrong frame '..frame)
                    count=count+1
                    if file=='sludge-crawler.png' and action=='melee' and frame==4 then
                        capture(canvas,mobile and 'battle-mobile-sludge' or 'battle-desktop-sludge')
                    elseif file=='attacking-eagle.png' and action=='death' and frame==6 and not mobile then
                        capture(canvas,'battle-desktop-eagle-death')
                    end
                end
                clock=start+1.5
                if action=='death'then
                    ctx.animationClock=clock+3;last=nil
                    love.graphics.setCanvas(canvas);UI.draw(ctx);love.graphics.setCanvas()
                    assert(select(1,last.quad:getViewport())==5*iw/6,'death did not hold its last frame')
                    -- A new encounter must not inherit an earlier collapse.
                    ctx.battle.encounterId=ctx.battle.encounterId..'n'
                end
                ctx[collections[action]][file..'@combat']=nil;sprite:release()
            end
        end
    end
    love.graphics.draw=draw
    print('MOB_COMBAT_RENDER_OK frames='..count..' suites='..#names..' desktop=true mobile=true deathHold=true')
end
function love.load()
    local ok,message=xpcall(run,debug.traceback);if not ok then print(message)end
    love.event.quit(ok and 0 or 1)
end
