local sourceBase=love.filesystem.getSourceBaseDirectory()
local repoRoot=sourceBase:gsub("/%./tools$","")
package.path=sourceBase.."/../?.lua;"..sourceBase.."/../?/init.lua;"..package.path

local Area
local session
local crowImage
local playerImage
local caravanAssets
local captureQueued=false
local captureComplete=false
local captureIndex=0
local previewMode=os.getenv("CARAVAN_PREVIEW_MODE") or "still"
local animated=previewMode=="animation" or previewMode=="cloth"
local assetRoot=os.getenv("CARAVAN_PREVIEW_ASSET_ROOT") or repoRoot
local capturePrefix=os.getenv("CARAVAN_PREVIEW_PREFIX") or "crow-caravan-campsite-v2"
local captureCount=animated and 40 or 1

local function loadImage(path)
    local file=io.open(assetRoot.."/"..path,"rb") or io.open(repoRoot.."/"..path,"rb")
    if not file then return nil end
    local bytes=file:read("*a")
    file:close()
    local data=love.filesystem.newFileData(bytes,path)
    local image=love.graphics.newImage(data)
    image:setFilter("nearest","nearest")
    return image
end

local function drawCharacter(image,x,y,maxW,maxH,facing)
    if not image then return false end
    local width,height=image:getDimensions()
    local scale=math.min(maxW/width,maxH/height)
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,x,y,0,scale*(facing or 1),scale,width/2,height)
    return true
end

local function loadGridAtlas(path,columns,rows)
    local image=assert(loadImage(path),"missing preview atlas: "..path)
    local width,height=image:getDimensions()
    assert(width%columns==0 and height%rows==0,"preview atlas grid must divide evenly")
    local atlas={image=image,count=columns*rows,w=width/columns,h=height/rows,columns=columns,rows=rows,quads={}}
    for index=1,atlas.count do
        local column,row=(index-1)%columns,math.floor((index-1)/columns)
        atlas.quads[index]=love.graphics.newQuad(column*atlas.w,row*atlas.h,atlas.w,atlas.h,width,height)
    end
    return atlas
end

local function initialize()
    love.filesystem.setIdentity("mouse-frontier-caravan-preview")
    love.window.setMode(960,720,{resizable=false,vsync=0})
    love.graphics.setDefaultFilter("nearest","nearest")
    if animated then assert(love.filesystem.createDirectory(capturePrefix.."-"..previewMode)) end
    Area=require("game.crow_caravan_area")
    session=assert(Area.new({stop=30}))
    session.clock=0
    session.data={accessibility={reducedMotion=os.getenv("CARAVAN_PREVIEW_REDUCED_MOTION")=="1"}}
    crowImage=loadImage("assets/sprites/NPCS/crow-merchant.png")
    playerImage=loadImage("assets/sprites/MainCharacters/mail-mouse.png")
    local root="assets/sprites/caravans/rookery/"
    caravanAssets={
        background=assert(loadImage("assets/backgrounds/crow-caravan-campsite-v1.png")),
        wagonBody=assert(loadImage(root.."wagon-body-v1.png")),
        wheel=assert(loadImage(root.."wagon-wheel-v1.png")),
        stallBody=assert(loadImage(root.."merchant-stall-body-v2.png")),
        stallBreeze=require("game.crow_caravan_art").stallAtlas(
            assert(loadImage(root.."animations/merchant-stall-breeze-4-v1.png")),love.graphics.newQuad),
        tent=assert(loadImage(root.."patched-tent-v1.png")),
        cargo=assert(loadImage(root.."cargo-cluster-v1.png")),
        banner=assert(loadImage(root.."crow-banner-v1.png")),
        campfire=loadGridAtlas(root.."animations/campfire-idle-4-v1.png",4,1),
    }
    local art=Area.validateAssets(caravanAssets)
    assert(art.ready,table.concat(art.errors,"; "))
    love.graphics.setBackgroundColor(.035,.045,.028,1)
end

function love.load()
    local ok,errorMessage=xpcall(initialize,debug.traceback)
    if not ok then
        io.stderr:write("PREVIEW_ERROR="..tostring(errorMessage).."\n")
        io.stderr:flush()
        love.event.quit(1)
    end
end

function love.update()
    if captureComplete then
        captureComplete=false
        captureQueued=false
        captureIndex=captureIndex+1
    end
    if captureIndex>=captureCount then
        local output=animated and (capturePrefix.."-"..previewMode) or (capturePrefix..".png")
        print("CARAVAN_PREVIEW="..love.filesystem.getSaveDirectory().."/"..output)
        love.event.quit(0)
    end
    session.clock=animated and captureIndex/20 or .4
end

local function render()
    if not session or captureIndex>=captureCount then return end
    if previewMode=="cloth" then
        Area.drawStall(caravanAssets,{graphics=love.graphics,x=480,y=655,maxW=880,maxH=600,
            clock=session.clock,reducedMotion=session.data.accessibility.reducedMotion})
    else
    Area.draw(session,{
        caravanAssets=caravanAssets,
        characterImages={["crow-merchant.png"]=crowImage},
        drawPlayer=function()
            drawCharacter(playerImage,480,650,70,88,1)
        end,
        drawOverlay=function()
            love.graphics.setColor(1,.80,.22,.88)
            love.graphics.circle("line",480,660,34)
            love.graphics.printf("RETURN TO STOP",390,682,180,"center",0,.72,.72)
        end,
    })
    end

    if not captureQueued then
        captureQueued=true
        local output=animated and string.format("%s-%s/frame-%03d.png",capturePrefix,previewMode,captureIndex)
            or (capturePrefix..".png")
        love.graphics.captureScreenshot(function(data)
            data:encode("png",output)
            captureComplete=true
        end)
    end
end

function love.draw()
    local ok,errorMessage=xpcall(render,debug.traceback)
    if not ok then
        io.stderr:write("PREVIEW_ERROR="..tostring(errorMessage).."\n")
        io.stderr:flush()
        love.event.quit(1)
    end
end
