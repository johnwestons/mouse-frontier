-- Desktop measurements of the actual game draw path. Synchronous batch
-- readback includes submitted GPU work; CPU percentiles exclude that readback.
-- These measurements do not stand in for physical Android frame pacing.
local Native=require('game.battle_native_ui')
local Field=require('game.battle_field')
local Fog=require('game.battle_fog')
local Graphics=require('game.battle_graphics')
local Profile={}
local function json(value)
    if type(value)=='number'or type(value)=='boolean'then return tostring(value)end
    if type(value)=='string'then return'"'..value:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n')..'"'end
    local parts={};if #value>0 then for _,item in ipairs(value)do parts[#parts+1]=json(item)end;return'['..table.concat(parts,',')..']'end
    local keys={};for key in pairs(value)do keys[#keys+1]=key end;table.sort(keys)
    for _,key in ipairs(keys)do parts[#parts+1]=json(key)..':'..json(value[key])end
    return'{'..table.concat(parts,',')..'}'
end
local function summary(samples)
    table.sort(samples);local total=0;for _,n in ipairs(samples)do total=total+n end
    return{meanMs=total/#samples,medianMs=samples[math.ceil(#samples*.5)],p95Ms=samples[math.ceil(#samples*.95)],maxMs=samples[#samples]}
end
function Profile.run(context)
    local g,b,ui=love.graphics,context.runtime.battle,context.ui;local c=Native.camera(ui,b);local data=context.runtime.saveData
    local timer=love.timer.getTime;local result={kind='native-battle-desktop-profile',version=1,cases={}}
    context.app.update(0) -- Apply the normal scene asset-retention pass.
    result.textureStages=context.memory;result.textureStages.afterRetention=g.getStats().texturememory or 0
    local renderer,version,vendor,device=g.getRendererInfo()
    result.renderer={name=renderer,version=version,vendor=vendor,device=device}
    result.simulatedMobile=os.getenv('MOUSE_FRONTIER_MOBILE')=='1'
    local access=require('game.accessibility').ensure(data);access.textSize=1;access.highContrast=false
    ui.nativeBattle.panel=nil;b.projectile=nil
    local function frame()
        g.setCanvas({context.canvas,stencil=true});g.origin();context.app.draw();g.setCanvas()
    end
    local function settle()
        for i=1,100 do frame();if ui.nativeBattle.renderer.stats.pendingChunks==0 then return i end end
        error('terrain streaming did not settle')
    end
    local generations={};for i=1,24 do
        local start=timer();local f=Field.generate(1847+i*1729,i%4+1,'hard')
        generations[#generations+1]=(timer()-start)*1000;assert(f.columns*f.rows==2880)
    end
    result.generation=summary(generations)
    b.fog={version=Fog.VERSION,explored=string.rep('f',b.field.columns*b.field.rows/4)}
    local party=b.units[1];party.q,party.r=35,20
    local visibility={}
    for i=1,24 do
        party.q=30+i%8;local start=timer();Fog.update(b);visibility[#visibility+1]=(timer()-start)*1000
    end
    result.visibility=summary(visibility);party.q=35;Fog.update(b)
    for _,distance in ipairs({10,14,28})do for _,zoom in ipairs({1,.18})do
        Graphics.values(data).renderDistance=distance;c:focus(party.q,party.r,Field.cellHeight(b.field,party.q,party.r));c:setZoom(zoom)
        ui.nativeBattle.renderer:releaseWorld()
        local cold,builds={},0
        for i=1,100 do
            local start=timer();frame();cold[#cold+1]=(timer()-start)*1000
            local stats=ui.nativeBattle.renderer.stats;builds=builds+stats.builtChunks
            assert(stats.builtChunks<=(result.simulatedMobile and 2 or 3),'scenery build budget was exceeded')
            if stats.pendingChunks==0 then break end
        end
        assert(ui.nativeBattle.renderer.stats.pendingChunks==0)
        settle();collectgarbage('collect')
        local samples={};local started=timer()
        for _=1,90 do local start=timer();frame();samples[#samples+1]=(timer()-start)*1000 end
        local image=context.canvas:newImageData();image:release()
        local complete=timer()-started;local stats=ui.nativeBattle.renderer.stats
        collectgarbage('collect');local graphics=g.getStats()
        result.cases[#result.cases+1]={distance=distance,zoom=zoom,quality=ui.nativeBattle.renderer.quality,
            coldFrames=#cold,cold=summary(cold),builtChunks=builds,cpuSubmission=summary(samples),
            batchWithReadbackMs=complete*1000/#samples,visibleChunks=stats.visibleChunks,cachedChunks=stats.cachedChunks,
            submittedTriangles=stats.visibleTriangles,drawCalls=stats.drawCalls,meshBytes=stats.triangles*3*48,
            luaHeapKB=collectgarbage('count'),textureBytes=graphics.texturememory or 0}
    end end
    Graphics.values(data).renderDistance=10;c:setZoom(.30)
    local maximum=0;local heap={}
    for _,q in ipairs({6,18,30,42,54,66,54,42,30,18,6,66})do
        party.q=q;Fog.update(b);c:focus(q,20,Field.cellHeight(b.field,q,20));settle()
        local stats=ui.nativeBattle.renderer.stats;local limit=result.simulatedMobile and 28 or 40
        assert(stats.cachedChunks<=math.max(limit,stats.visibleChunks),'terrain cache leaked during pan')
        maximum=math.max(maximum,stats.cachedChunks);collectgarbage('collect');heap[#heap+1]=collectgarbage('count')
    end
    result.pan={maxCachedChunks=maximum,finalLuaHeapKB=heap[#heap],firstLuaHeapKB=heap[1]}
    assert(love.filesystem.write('production-profile.json',json(result)))
    print('BATTLE_PROFILE_OK generationP95Ms='..string.format('%.3f',result.generation.p95Ms)..' maxCachedChunks='..maximum)
end
return Profile
