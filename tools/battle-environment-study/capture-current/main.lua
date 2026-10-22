-- Production BattleUI with in-memory fixtures only. No save API is called.
io.stdout:setvbuf('no')
local root=assert(os.getenv('MOUSE_FRONTIER_PROJECT_ROOT')):gsub('\\','/')
package.path=root..'/?.lua;'..package.path
local function fileData(path)
    local f=assert(io.open(root..'/'..path,'rb'));local bytes=f:read('*a');f:close()
    return love.filesystem.newFileData(bytes,path)
end
local function image(path)
    local d=fileData(path);local im=love.graphics.newImage(d);d:release()
    im:setFilter('nearest','nearest');return im
end
local function atlas(path,generated)
    local im
    if generated then
        local fd=fileData(path);local d=love.image.newImageData(fd);fd:release()
        d:mapPixel(function(_,_,r,g,b,a)
            if math.max(r,g,b)-math.min(r,g,b)<.035 and math.min(r,g,b)>.82 then return r,g,b,0 end
            return r,g,b,a
        end)
        im=love.graphics.newImage(d);d:release();im:setFilter('nearest','nearest')
    else im=image(path) end
    local w,h=im:getDimensions();local out={image=im,cw=w/3,ch=h/2,quads={},name='Wasteland'}
    for i=1,6 do out.quads[i]=love.graphics.newQuad(((i-1)%3)*out.cw,math.floor((i-1)/3)*out.ch,out.cw,out.ch,w,h) end
    return out
end
local function run()
    local UI=require('game.battle_ui')
    local Grid=require('game.battle_grid')
    local data=require('game.save_schema').migrate({character='trail-fox.png',equipment={},traitBaselineApplied=true})
    local noop=function()end
    local font=fileData('assets/fonts/CourierPrime-Regular.ttf')
    love.graphics.setFont(love.graphics.newFont(font,20));font:release()
    local ctx={W=960,H=720,saveData=data,ui={playSfx=noop},scenery={},colors=require('game.config').colors,
        animationClock=0,playerProgression=require('game.player_progression'),drawAnimatedCharacter=noop,
        pointerPosition=function()return -1000,-1000 end,screenToGame=function(x,y)return x,y end,
        drawLandscape=function()love.graphics.clear(.20,.16,.11,1)end,drawGround=noop,
        button=function(label,x,y,w,h,enabled)
            love.graphics.setColor(.2,.14,.08,1);love.graphics.rectangle('fill',x,y,w,h,4,4)
            love.graphics.setColor(.96,.88,.68,1);love.graphics.printf(label,x+3,y+8,w-6,'center',0,.65,.65)
            return{x=x,y=y,w=w,h=h}
        end}
    for _,name in ipairs({'characterImages','npcImages','mobImages','characterWalkImages','npcWalkImages',
        'mobAttackImages','mobIdleImages','mobHitImages','mobDeathImages','mobWalkImages','mobRangedImages','characterAnimations'})do ctx[name]={}end
    ctx.characterImages['trail-fox.png']=image('assets/sprites/MainCharacters/trail-fox.png')
    ctx.mobImages['mouse-bandit.png']=image('assets/sprites/Mobs/mouse-bandit.png')
    ctx.scenery.battleAtlases={atlas('assets/sprites/battle-maps/wasteland-tiles-v2.png')}
    ctx.scenery.battleVariations={atlas('assets/sprites/battle-maps/wasteland-tiles-v3.png')}
    ctx.scenery.battleAccents={atlas('assets/sprites/battle-maps/wasteland-tiles-v4.png',true)}
    ctx.scenery.battleObstacles=atlas('assets/sprites/battle-maps/battle-obstacles-v1.png',true)
    local ally={id='player',team='ally',name='Trail Fox',file='trail-fox.png',q=1,r=3,hp=20,maxHP=20,move=3,armor=2}
    local enemy={id='enemy1',team='enemy',name='Mouse Bandit',file='mouse-bandit.png',q=8,r=3,hp=20,maxHP=20,move=2,armor=1}
    ctx.battle={encounter={},active=1,selected=1,round=1,phase='select',units={ally,enemy},tiles={},tileVariants={},
        obstacles=Grid.generateObstacles(14,'medium',function(low)return low end),abilitiesUsed={},
        objective='Defeat all threats',message='',log={}}
    for q=0,Grid.COLS do ctx.battle.tiles[q]={};ctx.battle.tileVariants[q]={}
        for r=1,Grid.ROWS do ctx.battle.tiles[q][r]=((q+r*3)%6)+1;ctx.battle.tileVariants[q][r]=((q*3+r)%3)+1 end
    end
    local canvas=love.graphics.newCanvas(960,720)
    love.graphics.setCanvas(canvas);UI.draw(ctx);love.graphics.setCanvas()
    local d=canvas:newImageData();local png=d:encode('png')
    local f=assert(io.open(root..'/docs/concepts/battle-environment-study/current-layout-fixture.png','wb'));f:write(png:getString());f:close()
    print('CURRENT_LAYOUT_CAPTURE_OK in-memory fixture, no campaign saves accessed')
end
function love.load()
    local ok,err=xpcall(run,debug.traceback);if not ok then print(err)end;love.event.quit(ok and 0 or 1)
end
