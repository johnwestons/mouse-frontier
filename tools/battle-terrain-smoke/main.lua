-- Native renderer acceptance fixture. It never opens or writes campaign saves.
io.stdout:setvbuf('no')
local root=assert(os.getenv('MOUSE_FRONTIER_PROJECT_ROOT')):gsub('\\','/')
package.path=root..'/?.lua;'..package.path
local Field=require('game.battle_field')
local Renderer=require('game.battle_renderer3d')
local renderer,battle,canvas,images,checks
local function expect(value,message)assert(value,message);checks=checks+1 end
local function image(path)
    local f=assert(io.open(root..'/'..path,'rb'));local bytes=f:read('*a');f:close()
    local fd=love.filesystem.newFileData(bytes,path);local result=love.graphics.newImage(fd,{mipmaps=true});fd:release()
    result:setFilter('nearest','nearest');return result
end
local function capture(name)
    local data=canvas:newImageData();local png=data:encode('png')
    local f=assert(io.open(root..'/output/battle-terrain/'..name..'.png','wb'));f:write(png:getString());f:close();data:release();png:release()
end
local directions={'idle','idle_southeast','idle_south','idle_southwest','idle_west','idle_northwest','idle_north','idle_northeast'}
local function actors(r)
    for i,unit in ipairs(battle.units)do
        local index=((2-math.floor((unit.heading-r.camera.yaw*math.pi/180)/(math.pi/4)+.5))%8)+1
        local im=images[unit.file][index];local iw,ih=im:getDimensions()
        local quad=love.graphics.newQuad(0,0,iw/2,ih,iw,ih)
        r:drawSprite(im,quad,unit.q+.5,Field.cellHeight(battle.field,unit.q,unit.r)+.02,unit.r-.5,1.35,1.6)
        quad:release()
    end
end
local function draw(name)
    love.graphics.setCanvas(canvas);love.graphics.origin();love.graphics.clear(.08,.07,.05,1)
    local stats=renderer:render(battle,{x=0,y=48,w=1280,h=688},actors)
    expect(love.graphics.getCanvas()==canvas,'3D pass failed to restore caller canvas')
    love.graphics.setColor(.94,.86,.67,1)
    love.graphics.print('MOUSE FRONTIER  /  NATIVE LARGE BATTLEFIELD',20,16)
    love.graphics.print((battle.field.columns*battle.field.rows)..' spaces  /  '..Field.playableCount(battle.field,battle.obstacles)..' playable  /  '..stats.triangles..' cached triangles',20,751)
    love.graphics.print('Yaw '..renderer.camera.yaw..'  Tilt '..renderer.camera.tilt..'  Zoom '..string.format('%.2f',renderer.camera.zoom)..'  Draws '..stats.drawCalls,20,775)
    love.graphics.setCanvas();capture(name)
    expect(love.graphics.getShader()==nil,'3D shader leaked')
    expect(love.graphics.getStackDepth()==0,'3D graphics stack leaked')
    expect(stats.drawCalls<355,'unbounded full-map reference draw calls')
    local snapshot={};for k,v in pairs(stats)do snapshot[k]=v end;return snapshot
end
local function run()
    checks=0;local field,tiles,variants,obstacles=Field.generate(1847,1,'hard')
    battle={field=field,tiles=tiles,tileVariants=variants,obstacles=obstacles,units={
        {file='trail-fox',q=2,r=10,heading=math.pi/2},{file='watch-raccoon',q=3,r=11,heading=math.pi/2},
        {file='botanist-frog',q=4,r=9,heading=math.pi/2}}}
    images={};for _,name in ipairs({'trail-fox','watch-raccoon','botanist-frog'})do
        images[name]={};for _,direction in ipairs(directions)do images[name][#images[name]+1]=image('assets/sprites/character-animations/'..name..'/'..direction..'.png')end
    end
    renderer=Renderer.new({quality='high',imageLoader=image});renderer.fogEnabled=false
    renderer.maxBuildsPerFrame=math.huge;renderer.buildBudgetSeconds=math.huge;renderer:setBattle(battle)
    canvas=love.graphics.newCanvas(1280,800,{format='rgba8'})
    renderer.camera:configure({x=0,y=48,w=1280,h=688});renderer.camera:frame(field.columns,field.rows)
    local high=draw('native-overview');expect(high.triangles>60000,'rich scenery missing on fourfold map')
    local original=renderer.chunks[1].ground
    local copy={};for k,v in pairs(field)do copy[k]=v end
    local obstacleCopy={};for k,v in pairs(obstacles)do obstacleCopy[k]={q=v.q,r=v.r,kind=v.kind}end
    battle.field=copy;battle.obstacles=obstacleCopy
    expect(renderer:setBattle(battle)==false and renderer.chunks[1].ground==original,'co-op table replacement rebuilt unchanged GPU geometry')
    field=copy
    renderer.camera:focus(3,10,Field.cellHeight(field,3,10));renderer.camera:setZoom(1)
    draw('native-entry-detail')
    for _,yaw in ipairs({0,90,180,270,359})do
        renderer.camera.yaw=yaw;draw('native-angle-'..yaw)
        local q,r=2,10;local sx,sy=renderer.camera:project(q+.5,Field.cellHeight(field,q,r),r-.5)
        local a,b=renderer:pick(sx,sy);expect(a==q and b==r,'native camera/picking mismatch at '..yaw)
    end
    renderer.camera:pan(-960,-100);draw('native-pan')
    renderer.camera:frame(field.columns,field.rows)
    renderer:setBattle(battle,'low');local low=draw('native-low-detail')
    expect(low.triangles<high.triangles*.5,'mobile quality did not substantially reduce geometry')
    local data=canvas:newImageData();local p={data:getPixel(640,400)};data:release()
    expect(p[4]==1,'scene output is unexpectedly transparent')
    for biome=1,4 do
        local f,t,v,o=Field.generate(1847,biome,'hard')
        battle.field,battle.tiles,battle.tileVariants,battle.obstacles=f,t,v,o
        for i,u in ipairs(battle.units)do u.q,u.r=31+i,21+i%2;o[u.q..':'..u.r]=nil end
        renderer:setBattle(battle,'high');renderer.camera.yaw=45;renderer.camera.tilt=55
        renderer.camera:focus(33,20,Field.cellHeight(f,33,20));renderer.camera:setZoom(.8)
        draw('native-biome-'..biome)
    end
    local out=assert(io.open(root..'/output/battle-terrain/native-result.txt','w'))
    out:write('BATTLE_TERRAIN_SMOKE_OK checks='..checks..' highTriangles='..high.triangles..' lowTriangles='..low.triangles..'\n');out:close()
    print('BATTLE_TERRAIN_SMOKE_OK checks='..checks..' highTriangles='..high.triangles..' lowTriangles='..low.triangles)
    renderer:release();canvas:release()
end
function love.load()
    local ok,err=xpcall(run,debug.traceback);if not ok then print(err)end;love.event.quit(ok and 0 or 1)
end
