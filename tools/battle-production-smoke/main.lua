io.stdout:setvbuf('no')
local Field=require('game.battle_field')
local Native=require('game.battle_native_ui')
local Viewport=require('game.viewport')
local checks=0
local function expect(value,message)assert(value,message);checks=checks+1 end
local function run()
    love.math.setRandomSeed(1859)
    local c
    require('game.smoke_playthrough').install=function(context)c=context end
    local app=require('game.application_composition').new({engine=love});app.installSmoke();app.load()
    local memory={afterLoad=love.graphics.getStats().texturememory or 0}
    local g,ui=c.runtime,c.ui
    g.selectedSlot=99
    local data=c.newSave('trail-fox.png');local home=require('game.home_stop')
    assert(home.advance(data,'enterOffice'))
    for _=1,6 do assert(home.advance(data,'talk'))end
    assert(home.advance(data,'exitOffice'));assert(home.advance(data,'supplies'));assert(home.advance(data,'repair'))
    assert(home.advance(data,'enterOffice'));assert(home.advance(data,'talk'));assert(home.advance(data,'talk'))
    assert(home.advance(data,'exitOffice'));assert(home.depart(data))
    data.location=5;data.scene='train';data.passengers={}
    local entered,reason=c.enterGame(data)
    expect(entered,'could not enter isolated campaign: '..tostring(reason));data=g.saveData;g.dialogue=nil
    memory.afterEnterGame=love.graphics.getStats().texturememory or 0
    local files=c.catalog.mobTiers.easy
    local encounter={rolled=true,hasMob=true,resolved=false,tier='easy',mobFiles={files[1],files[2]or files[1],files[3]or files[1]}}
    data.encounters['5']=encounter;expect(require('game.coop_entities').ensure(data),'encounter identity failed')
    expect(c.beginEncounter(encounter),'large encounter did not start')
    local b=g.battle;b.intro=nil
    local width,height=love.graphics.getDimensions();local canvas=love.graphics.newCanvas(width,height,{format='rgba8'})
    local function draw(name)
        local w,h=love.graphics.getDimensions()
        if canvas:getWidth()~=w or canvas:getHeight()~=h then canvas:release();canvas=love.graphics.newCanvas(w,h,{format='rgba8'})end
        local attempts=0
        repeat
            love.graphics.setCanvas({canvas,stencil=true});love.graphics.origin();app.draw();love.graphics.setCanvas()
            attempts=attempts+1
        until not name or not ui.nativeBattle or(ui.nativeBattle.renderer.stats.pendingChunks or 0)==0 or attempts>=84
        expect(love.graphics.getStackDepth()==0,'production draw leaked a graphics transform')
        if name then
            local image=canvas:newImageData();image:encode('png',name..'.png');image:release()
        end
    end
    local function pointer(x,y,button)
        local ox,oy,sx,sy=Viewport.transform(960,720);x,y=ox+x*sx,oy+y*sy
        app.mousepressed(x,y,button);app.mousereleased(x,y,button)
    end
    draw('production-default')
    memory.afterBattleDraw=love.graphics.getStats().texturememory or 0
    local camera=Native.camera(ui,b);expect(camera and b.field,'production renderer not integrated')
    expect(b.field.columns==72 and b.field.rows==40 and Field.playableCount(b.field,b.obstacles)>=2400,'fourfold field lost its playable area')
    expect(ui.nativeBattle.renderer.stats.cachedChunks<16,'initial fog eagerly built the entire map')
    expect(camera.viewport.w==1560,'widescreen battlefield retained 4:3 side bars')
    local revision=data.coop.revision;local q,r=b.units[1].q,b.units[1].r
    if os.getenv('MOUSE_FRONTIER_MOBILE')=='1'then
        local zoom=camera.zoom
        app.touchpressed('fog-a',780,360);app.touchpressed('fog-b',900,360)
        app.touchmoved('fog-b',1020,360,120,0)
        expect(camera.zoom>zoom,'battle pinch did not zoom the native camera')
        app.touchreleased('fog-b',1020,360);app.touchreleased('fog-a',780,360)
        expect(data.coop.revision==revision and b.units[1].q==q and b.units[1].r==r,'battle pinch submitted a unit action')
    end
    app.keypressed('q');app.keypressed(']');app.keypressed('+');app.keypressed('o');draw('production-overview')
    expect(camera.yaw~=45 and camera.tilt~=55,'camera keys did not orbit and tilt')
    expect(data.coop.revision==revision and b.units[1].q==q and b.units[1].r==r,'camera keys changed authoritative battle state')
    app.keypressed('home');draw()
    local x,y=Native.project({ui=ui,battle=b},q,r)
    local pickedQ,pickedR=ui.nativeBattle.renderer:pick(x,y)
    expect(pickedQ==q and pickedR==r,'production projection and picking disagree')
    local ox,oy,sx,sy=Viewport.transform(960,720);local px,py=ox+x*sx,oy+y*sy
    app.mousepressed(px,py,2);app.mousemoved(px+120,py+30,120,30);app.mousereleased(px+120,py+30,2)
    draw('production-orbit')
    expect(math.abs(camera.yaw-30)>10,'right drag did not rotate')
    local before=camera.targetX;app.mousepressed(px,py,3);app.mousemoved(px+80,py+10,80,10);app.mousereleased(px+80,py+10,3)
    expect(camera.targetX~=before,'middle drag did not pan')
    draw('production-pan')
    local opts=ui.battleCameraButtons
    for _,item in ipairs(opts)do if item.action=='overview'then pointer(item.rect.x+item.rect.w/2,item.rect.y+item.rect.h/2,1)end end
    draw()
    expect(data.coop.revision==revision,'camera toolbar submitted a network command')
    local sourceData=b.field.elevationData
    for _,zoom in ipairs({.12,.6,1.2,3.5})do
        camera:setZoom(zoom);draw()
        expect(ui.nativeBattle.renderer.stats.drawCalls<110,'native battle has excessive draw submissions')
    end
    expect(b.field.elevationData==sourceData,'camera changed canonical geometry')
    local Fog=require('game.battle_fog');local Graphics=require('game.battle_graphics')
    ui.optionsOpen=true;g.optionsPage='graphics';draw('production-fog-options')
    expect(ui.battleDistanceUp and ui.battleDistanceDown,'draw distance missing from Options')
    for _=1,4 do local rect=ui.battleDistanceUp;pointer(rect.x+rect.w/2,rect.y+rect.h/2,1);draw()end
    expect(Graphics.distance(data,false)==28,'Options did not adjust local draw distance')
    local persisted=require('game.local_preferences').new(love.filesystem)
    expect(persisted.values.graphics.renderDistance==28,'draw distance did not survive preferences reload')
    expect(data.coop.revision==revision and not data.graphics,'graphics option changed campaign state')
    ui.optionsOpen=false
    local party=b.units[1];local path={}
    for col=party.q,35 do path[#path+1]={q=col,r=3}end
    party.q,party.r=35,3;Fog.update(b,party,path);party.moveAnim=nil
    camera:focus(party.q,party.r,Field.cellHeight(b.field,party.q,party.r));camera:setZoom(.25)
    draw('production-fog-explored')
    expect(Fog.explored(b,15,3)and not Fog.visible(b,15,3),'exploration memory did not outlast sight')
    local far=ui.nativeBattle.renderer.stats.visibleChunks
    while Graphics.distance(data,false)>10 do Graphics.adjust(data,-1)end
    draw('production-fog-short')
    local near=ui.nativeBattle.renderer.stats.visibleChunks
    expect(near<far,'short draw distance did not cull additional terrain chunks')
    local enemy
    for _,u in ipairs(b.units)do if u.team=='enemy'then enemy=u;break end end
    enemy.q,enemy.r=party.q+2,party.r
    draw('production-fog-contact');local shown=false
    for _,label in ipairs(ui.nativeBattle.labels)do if label.unit==enemy then shown=true end end
    expect(shown,'enemy within party sight was not drawn')
    enemy.q=60;draw();shown=false
    for _,label in ipairs(ui.nativeBattle.labels)do if label.unit==enemy then shown=true end end
    expect(not shown,'enemy outside sight leaked through actor labels')
    camera:frame(b.field.columns,b.field.rows);draw('production-fog-overview')
    expect(ui.nativeBattle.renderer.stats.cachedChunks<=40,'terrain cache grew without a bound')
    print('BATTLE_FOG_RENDER longChunks='..far..' shortChunks='..near..' cachedChunks='..ui.nativeBattle.renderer.stats.cachedChunks)
    camera:focus(party.q,party.r,Field.cellHeight(b.field,party.q,party.r));camera:setZoom(1)
    enemy.q,enemy.r=party.q+2,party.r
    party.guarding=true;party.regenRounds=2;enemy.bleedRounds=2;b.selected=party.id
    b.projectile={fromQ=party.q,fromR=party.r,toQ=enemy.q,toR=enemy.r,ammo='arrows',t=.5,duration=1}
    draw('production-projectile-status')
    expect(ui.nativeBattle.renderer.stats.projectiles==1,'authored projectile did not render')
    Native.cameraAction(ui,b,'info');draw('production-unit-info')
    expect(ui.nativeBattle.panelRect and ui.nativeBattle.panel=='info','unit inspection panel missing')
    local rect=ui.nativeBattle.panelRect;pointer(rect.x+30,rect.y+80,1)
    expect(data.coop.revision==revision and party.q==35,'inspection panel clicked through to the battlefield')
    Native.cameraAction(ui,b,'log');draw('production-history')
    expect(ui.nativeBattle.panel=='log'and ui.nativeBattle.panelRect,'battle history missing')
    Native.cameraAction(ui,b,'panelClose');expect(not ui.nativeBattle.panel,'panel close failed')
    enemy.q=60;b.selected=enemy.id;Native.cameraAction(ui,b,'focus')
    expect(camera.targetX==party.q+.5,'focus revealed a hidden enemy position')
    b.projectile=nil;b.selected=party.id
    local access=require('game.accessibility').ensure(data);access.textSize=3;access.highContrast=true
    for _,w in ipairs({960,1280,1560})do
        love.window.setMode(w,720,{vsync=0});draw('production-accessible-'..w)
        for _,item in ipairs(ui.battleOptions)do
            expect(item.rect.y+item.rect.h<=720,'large-text action clipped below the screen')
        end
        Native.cameraAction(ui,b,'info');draw('production-accessible-info-'..w);Native.cameraAction(ui,b,'panelClose')
    end
    if os.getenv('MOUSE_FRONTIER_BATTLE_PROFILE')=='1'then require('profile').run({runtime=g,ui=ui,app=app,canvas=canvas,memory=memory})end
    Native.release(ui);expect(not ui.nativeBattle,'leaving battle retained renderer resources')
    print('BATTLE_PRODUCTION_SMOKE_OK checks='..checks..' saveDirectory='..love.filesystem.getSaveDirectory())
end
function love.load()
    local ok,err=xpcall(run,debug.traceback);if not ok then print(err)end;love.event.quit(ok and 0 or 1)
end
