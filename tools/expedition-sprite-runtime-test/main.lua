local repoRoot=os.getenv("EXPEDITION_SPRITE_ROOT") or love.filesystem.getSourceBaseDirectory().."/.."
package.path=repoRoot.."/?.lua;"..package.path
local Sprites=require("game.expedition_sprites")
local Roaming=require("game.roaming_mobs")
local output=os.getenv("EXPEDITION_SPRITE_REPORT_DIR") or love.filesystem.getSaveDirectory()

local function readImageData(path)
    local file=assert(io.open(repoRoot.."/"..path,"rb"))
    local contents=file:read("*a"); file:close()
    local fileData=love.filesystem.newFileData(contents,path)
    local imageData=love.image.newImageData(fileData); fileData:release()
    return imageData
end

local function png(canvas,name)
    local data=canvas:newImageData()
    local encoded=data:encode("png")
    local file=assert(io.open(output.."/"..name,"wb"))
    file:write(encoded:getString()); file:close()
    encoded:release(); data:release()
end

local function strip(images,name)
    local canvas=love.graphics.newCanvas(#images*512,512)
    love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear(0,0,0,0)
    love.graphics.setColor(1,1,1,1)
    for index,image in ipairs(images) do love.graphics.draw(image,(index-1)*512,0) end
    love.graphics.setCanvas(); love.graphics.pop()
    png(canvas,name); canvas:release()
end

local function cleanMatteTest()
    local data=love.image.newImageData(40,40)
    data:mapPixel(function(x,y)
        if x>=8 and x<=31 and y>=8 and y<=31 then
            if x>=13 and x<=26 and y>=13 and y<=26 then return 1,1,1,1 end
            return .03,.03,.03,1
        end
        local shade=math.floor(x/4)%2==math.floor(y/4)%2 and .82 or 1
        return shade,shade,shade,1
    end)
    Sprites.cleanMatte(data)
    local _,_,_,outside=data:getPixel(1,1)
    local r,g,b,inside=data:getPixel(19,19)
    assert(outside==0 and inside==1 and r==1 and g==1 and b==1,"matte cleanup erased an enclosed white highlight")
    data:release()
    data=love.image.newImageData(40,40)
    data:mapPixel(function(x,y)
        if x>=8 and x<=31 and y>=8 and y<=31 then
            if y>=13 and y<=26 and ((x>=11 and x<=16) or (x>=23 and x<=28)) then return 1,1,1,1 end
            return .03,.03,.03,1
        end
        return 1,1,1,1
    end)
    Sprites.cleanMatte(data,{{13,16}})
    local _,_,_,pocket=data:getPixel(13,16)
    local _,_,_,highlight=data:getPixel(25,16)
    assert(pocket==0 and highlight==1,"reviewed pocket seed escaped into a separate white highlight")
    data:release()
end

local function rendererTest(asset)
    local sys=Roaming.new()
    local ctx={area={id="test",mobs={{id="m",file="test.png",name="Test"}}},
        areaState={mobs={m={x=100,y=200,hp=20,maxHp=20}}},assets={["test.png"]=asset},clock=0}
    local images,scales={},{}
    local original=love.graphics.draw
    local originalCircle=love.graphics.circle
    love.graphics.draw=function(image,x,y,angle,scaleX,...) images[#images+1]=image; scales[#scales+1]=scaleX end
    local ok,message=xpcall(function()
        Roaming.draw(sys,ctx)
        sys.transient.test.m.animationDistance=asset.pixelsPerFrame*2
        Roaming.draw(sys,ctx)
        Roaming.draw(sys,ctx)
        assert(images[1]==asset.actions[1],"stopped enemy did not use idle")
        assert(images[2]==asset.walkFrames[3],"walk did not follow resolved distance")
        assert(images[3]==asset.actions[1],"blocked enemy walked in place")
        assert((scales[1]>0)==((asset.baseFacing or 1)>0),"native sprite facing was not applied consistently")
        local radii={}
        love.graphics.circle=function(mode,x,y,radius) radii[#radii+1]=radius end
        sys.transient.test.m.state="windup"
        Roaming.draw(sys,ctx)
        ctx.area.mobs[1].boss=true; ctx.area.mobs[1].reach=112
        Roaming.draw(sys,ctx)
        assert(radii[1]==90 and radii[2]==132,"windup ring did not match actual enemy hit reach")
        love.graphics.circle=originalCircle
        images={}
        ctx.area.mobs={{id="back",file="test.png"},{id="front",file="test.png"}}
        ctx.areaState.mobs={back={x=100,y=100,hp=20,maxHp=20},front={x=100,y=300,hp=20,maxHp=20}}
        ctx.player={x=100,y=200}
        Roaming.draw(sys,ctx,function() images[#images+1]="player" end)
        assert(#images==3 and images[2]=="player","player was not inserted between mob foot depths")
        images={}; ctx.area.mobs={}
        Roaming.draw(sys,ctx,function() images[#images+1]="player" end)
        assert(#images==1 and images[1]=="player","player disappeared in an empty area")
    end,debug.traceback)
    love.graphics.draw=original
    love.graphics.circle=originalCircle
    assert(ok,message)
end

local function drawRow(asset,images,label,y)
    love.graphics.setColor(1,.89,.69,1); love.graphics.print(label,20,y)
    local cell=1240/#images
    for index,image in ipairs(images) do
        local x=20+(index-1)*cell
        love.graphics.setColor(.13,.15,.17,1); love.graphics.rectangle("fill",x+2,y+22,cell-4,181)
        love.graphics.setColor(.28,.39,.29,1); love.graphics.line(x+5,y+192,x+cell-5,y+192)
        love.graphics.setColor(1,1,1,1)
        local scale=math.min((cell-8)/512,.35)
        love.graphics.draw(image,x+cell/2,y+192,0,scale,scale,256,492)
        love.graphics.setColor(.65,.72,.75,1); love.graphics.print(tostring(index),x+6,y+26)
    end
end

local function run()
    cleanMatteTest()
    local before=love.graphics.getStats().texturememory
    local assets={}
    local report={"Expedition sprite runtime audit","Border/reviewed-pocket connected matte; shared ground baseline y492.",
        "Bandit V5 / boss V4: repaired opposite-foot half steps and host limb identities; single authored camera view only."}
    for _,entry in ipairs({{id="sludge-bandit",boss=false,walkVersion=5},{id="sludge-badger-boss",boss=true,walkVersion=4}}) do
        local root="assets/sprites/Mobs/expedition/"..entry.id
        local asset=Sprites.load({actionPath=root.."-action-atlas.png",walkPath=root.."-walk-v"..entry.walkVersion..".png",boss=entry.boss,readImageData=readImageData})
        assert(#asset.actions==6 and #asset.walkFrames==8,"unexpected sprite frame count")
        for _,metrics in ipairs({asset.audit.actionFrames,asset.audit.walkFrames}) do
            for _,metric in ipairs(metrics) do
                assert(metric.normalizedBounds.bottom==492,"unstable ground baseline")
                assert(metric.normalizedBounds.left>0 and metric.normalizedBounds.right<511,"clipped normalized silhouette")
            end
        end
        rendererTest(asset)
        strip(asset.actions,entry.id.."-actions.png")
        strip(asset.walkFrames,entry.id.."-walk.png")
        strip({asset.actions[1]},entry.id.."-idle.png")
        local retained,edge=0,0
        for _,metric in ipairs(asset.audit.actionFrames) do retained=retained+metric.retainedNeutralPixels; edge=edge+(metric.sourceEdgeContact and 1 or 0) end
        for _,metric in ipairs(asset.audit.walkFrames) do retained=retained+metric.retainedNeutralPixels; edge=edge+(metric.sourceEdgeContact and 1 or 0) end
        report[#report+1]=string.format("%s: 6 actions,8 walk; referenceHeight=%.2f; scales action=%.4f/walk=%.4f; retained enclosed neutral pixels=%d; source-edge frames=%d",entry.id,asset.referenceHeight,asset.audit.actionScale,asset.audit.walkScale,retained,edge)
        for action,metrics in pairs({actions=asset.audit.actionFrames,walk=asset.audit.walkFrames}) do
            for index,metric in ipairs(metrics) do
                if metric.sourceEdgeContact then
                    local b=metric.bounds
                    report[#report+1]=string.format("%s %s %d SOURCE EDGE CONTACT bounds(%d,%d)-(%d,%d)",entry.id,action,index,b.left,b.top,b.right,b.bottom)
                end
                for _,component in ipairs(metric.enclosedNeutralComponents) do
                    report[#report+1]=string.format("%s %s %d neutral component %dpx seed(%d,%d) bounds(%d,%d)-(%d,%d)",entry.id,action,index,component.pixels,component.seedX,component.seedY,component.left,component.top,component.right,component.bottom)
                end
            end
        end
        assets[#assets+1]=asset
    end
    local canvas=love.graphics.newCanvas(1280,960)
    love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear(.065,.075,.085,1)
    drawRow(assets[1],assets[1].actions,"SLUDGE-TAKEN BANDIT / original actions",12)
    drawRow(assets[1],assets[1].walkFrames,"BANDIT / generated side-view pilot walk",233)
    drawRow(assets[2],assets[2].actions,"THE BURIED HOST / original actions",454)
    drawRow(assets[2],assets[2].walkFrames,"BURIED HOST / generated side-view pilot walk",675)
    love.graphics.setColor(.85,.75,.58,1)
    love.graphics.print("Bandit V5 / boss V4 repaired two-step cycles. Single-view sheets; full eight-direction coverage is not claimed.",20,920)
    love.graphics.setCanvas(); love.graphics.pop()
    png(canvas,"runtime-contact-sheet.png"); canvas:release()
    local peak=love.graphics.getStats().texturememory
    for _,asset in ipairs(assets) do Sprites.release(asset); Sprites.release(asset) end
    collectgarbage("collect")
    local after=love.graphics.getStats().texturememory
    assert(peak-after>=28*512*512*4,"normalized GPU images were not released")
    report[#report+1]=string.format("GPU texture bytes before=%d peak=%d after release=%d",before,peak,after)
    report[#report+1]="PASS: highlight preservation, frame counts, exact baseline, distance-driven walk, stopped idle, native facing, player depth, true hit-radius telegraph, idempotent GPU release."
    local file=assert(io.open(output.."/runtime-report.txt","wb")); file:write(table.concat(report,"\n").."\n"); file:close()
    io.stdout:write(table.concat(report,"\n").."\n"); io.stdout:flush()
end

function love.load()
    local ok,message=xpcall(run,debug.traceback)
    if not ok then io.stderr:write(message.."\n"); io.stderr:flush() end
    love.event.quit(ok and 0 or 1)
end
