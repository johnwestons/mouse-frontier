-- Render the real title UI to deterministic PNGs without loading game saves.
io.stdout:setvbuf('no')
local root=assert(os.getenv('MOUSE_FRONTIER_PROJECT_ROOT')):gsub('\\','/')
local output=assert(os.getenv('MOUSE_FRONTIER_TITLE_PREVIEW')):gsub('\\','/')
local assetRoot=(os.getenv('MOUSE_FRONTIER_TITLE_ASSET_ROOT') or root):gsub('\\','/')
package.path=root..'/?.lua;'..package.path
local function fileData(path)
    local file=assert(io.open(assetRoot..'/'..path,'rb'));local bytes=file:read('*a');file:close()
    return love.filesystem.newFileData(bytes,path)
end
local function image(path)
    local bytes=fileData(path);local result=love.graphics.newImage(bytes);bytes:release()
    result:setFilter('nearest','nearest');return result
end
local function run()
    local Config=require('game.config')
    local runtime={state='slots',animationClock=8}
    local ui={menuFrames={}};local scenery={}
    for name,path in pairs({titleImage='assets/sprites/ui/title/title-option-3.png',
        titleHeaderBackdrop='assets/sprites/ui/title/title-header-backdrop-v1.png',
        titleFooterBackdrop='assets/sprites/ui/title/title-footer-backdrop-v1.png',
        introBackground='assets/backgrounds/intro/train-journey-sunrise.png',
        introLocomotiveSheet='assets/sprites/train/cinematic-locomotive-run-10-v2.png',
        introCars='assets/sprites/train/cinematic-five-car-consist.png'})do scenery[name]=image(path)end
    scenery.titleSnapshotSprites={}
    local Snapshots=require('game.title_snapshots')
    for side=0,1 do
        local id=Snapshots.playback(runtime.animationClock,side).id
        scenery.titleSnapshotSprites[id]=image('assets/sprites/ui/title/snapshots/'..id..'.png')
    end
    local buttonImage=image('assets/sprites/ui/train-button-frame-v1.png')
    local frame={image=buttonImage,w=buttonImage:getWidth(),h=buttonImage:getHeight(),quads={}}
    local sx,sy=math.floor(frame.w*.22),math.floor(frame.h*.28)
    local xs,ys={0,sx,frame.w-sx,frame.w},{0,sy,frame.h-sy,frame.h}
    for row=1,3 do frame.quads[row]={};for col=1,3 do
        frame.quads[row][col]=love.graphics.newQuad(xs[col],ys[row],xs[col+1]-xs[col],ys[row+1]-ys[row],frame.w,frame.h)
    end end
    ui.menuFrames[4]=frame
    local fontData=fileData('assets/fonts/CourierPrime-Regular.ttf')
    local font=love.graphics.newFont(fontData,20);font:setLineHeight(1.08);love.graphics.setFont(font);fontData:release()
    local mobile=false
    local saves={{character='mail-mouse.png',location=10},{character='ferret-medic.png',location=2},{character='ferret-engineer.png',location=1}}
    local context={runtime=runtime,width=960,height=720,ui=ui,colors=Config.colors,scenery=scenery,
        characters={},characterImages={},npcImages={},util=require('game.util'),catalog=require('game.catalog'),
        readSave=function(i)return saves[i]end,mobileEnabled=function()return mobile end,
        screenToGame=function(x,y)return x,y end,getCharacterAnimations=function()return {}end}
    for _,name in ipairs({'inventory','eventUI','engineUpgrades','trainUpgradeBalance','playerProgression',
        'stopHelpProgression','npcRelationships','merchantTrade','finaleProgression','maintenance'})do context[name]={}end
    for _,name in ipairs({'canChooseEvent','writeSave','ensureStopLayout','currentTradeSource','drawLandscape',
        'drawTracks','drawLocomotive','drawTrainCar','drawAnimatedCharacter','isWeapon','travelCost','repairStatus','questSummary'})do context[name]=function()end end
    require('game.screen_ui').new(context)
    local canvas=love.graphics.newCanvas(960,720)
    local function capture(name,slot,elapsed)
        ui.resetSlotTrains();ui.keyboardFocusVisible=true;ui.keyboardFocusScreen='title-slots'
        ui.keyboardFocusId='slot.'..slot..'.continue';ui.updateSlots(0)
        ui.titleSlotTrains.rows[slot].elapsed=elapsed;ui.titleSlotTrains.rows[slot].amount=1
        love.graphics.setCanvas(canvas);ui.drawSlots();love.graphics.setCanvas()
        local pixels=canvas:newImageData();local png=pixels:encode('png')
        local file=assert(io.open(output..'/'..name..'.png','wb'));file:write(png:getString());file:close()
        pixels:release();png:release()
    end
    capture('desktop-start',1,0);capture('desktop-moving',1,1.0)
    capture('desktop-slot-two',2,.7);capture('desktop-slot-three',3,1.3)
    mobile=true;capture('mobile-moving',2,1)
    saves[3]=nil;capture('mobile-empty-slot',3,.5)
    -- Capture actual idle updates with no pointer/keyboard/selected save.
    -- Unfocused train pixels must remain still across real UI updates.
    mobile=true;ui.resetSlotTrains();ui.keyboardFocusVisible=false
    local previousMouse=love.mouse.getPosition
    love.mouse.getPosition=function()return -1000,-1000 end
    for _,seconds in ipairs({.10,.35})do
        ui.updateSlots(seconds==.10 and .10 or .1)
        if seconds==.35 then ui.updateSlots(.1);ui.updateSlots(.05)end
        love.graphics.setCanvas(canvas);ui.drawSlots();love.graphics.setCanvas()
        local pixels=canvas:newImageData();local png=pixels:encode('png')
        local file=assert(io.open(output..'/mobile-idle-'..tostring(seconds)..'.png','wb'));file:write(png:getString());file:close()
        pixels:release();png:release()
    end
    -- The phone's framebuffer pixels and graphics coordinates use different
    -- units. Render equal physical viewports at two DPI scales to exercise the
    -- real shader rather than only its identity-transform desktop preview.
    saves[3]={character='ferret-engineer.png',location=1}
    local function phoneCapture(name,dpi)
        local target=love.graphics.newCanvas(2340/dpi,1080/dpi,{dpiscale=dpi})
        love.graphics.push('all');love.graphics.setCanvas(target);love.graphics.origin()
        love.graphics.translate(450/dpi,0);love.graphics.scale(1.5/dpi)
        ui.drawSlots()
        love.graphics.setCanvas();love.graphics.pop()
        local pixels=target:newImageData();local png=pixels:encode('png')
        local file=assert(io.open(output..'/'..name..'.png','wb'));file:write(png:getString());file:close()
        png:release();target:release()
        return pixels
    end
    local reference=phoneCapture('mobile-phone-reference',1)
    local highDPI=phoneCapture('mobile-phone-hidpi',3)
    for slot,top in ipairs({322,547,772})do
        local changed=0
        for y=top,top+188 do for x=585,1754 do
            local r,g,b=reference:getPixel(x,y)
            local rr,gg,bb=highDPI:getPixel(x,y)
            if math.max(math.abs(r-rr),math.abs(g-gg),math.abs(b-bb))>3/255 then changed=changed+1 end
        end end
        assert(changed<100,'DPI clipping moved save '..slot..' artwork: '..changed..' mismatched pixels')
        print('TITLE_TRAIN_DPI_OK slot='..slot..' changed='..changed)
    end
    reference:release();highDPI:release()
    ui.keyboardFocusVisible=true;ui.keyboardFocusScreen='title-slots';ui.keyboardFocusId='slot.2.continue'
    ui.updateSlots(0);ui.titleSlotTrains.rows[2].elapsed=.7;ui.titleSlotTrains.rows[2].amount=1
    phoneCapture('mobile-phone-focused',3):release()
    love.mouse.getPosition=previousMouse
    if os.getenv('MOUSE_FRONTIER_TITLE_ANIMATION')=='1' then
        mobile=false;saves[3]={character='ferret-engineer.png',location=1}
        for index=0,67 do capture(string.format('animation-%03d',index),1,index*.08)end
    end
    print('TITLE_TRAIN_PREVIEW_OK screenshots=11')
end
function love.load()
    local ok,err=xpcall(run,debug.traceback);if not ok then print(err)end
    love.event.quit(ok and 0 or 1)
end
