-- The home yard and its parked train use one authored scene image.
-- Keep its large background resident only while the prologue is on screen.
local Home=require("game.home_stop")
local Art={}
local images={}
local path="assets/sprites/stops/home-yard-v3.png"

local function sceneImage(file)
    file=file or path
    if not images[file] and love.filesystem.getInfo(file) then
        images[file]=love.graphics.newImage(file)
        images[file]:setFilter("linear","linear")
    end
    return images[file]
end

function Art.release()
    for _,image in pairs(images) do image:release() end
    images={}
end

function Art.draw(scenery,width,height,data)
    local image=sceneImage()
    love.graphics.setColor(1,1,1,1)
    if image then
        love.graphics.draw(image,0,0,0,width/image:getWidth(),height/image:getHeight())
    else
        love.graphics.clear(.39,.40,.32)
        love.graphics.setColor(.45,.39,.28,1)
        love.graphics.rectangle("fill",0,height*.55,width,height*.45)
    end
    local office=sceneImage("assets/sprites/stops/home-office-exterior-v2.png")
    if office then
        local scale=math.min(360/office:getWidth(),280/office:getHeight())
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(office,210,390,0,scale,scale,office:getWidth()/2,office:getHeight())
    end
    local target=Home.target(data)
    if target then
        local g=love.graphics
        local lineWidth=g.getLineWidth()
        g.setLineWidth(2)
        g.setColor(1,.73,.29,.70)
        g.ellipse("line",target.x,target.y+(target.action=="talk" and 28 or 2),25,11)
        g.setLineWidth(lineWidth)
    end
end

function Art.drawOffice(width,height)
    local image=sceneImage("assets/sprites/interiors/home-train-office-v1.png")
    love.graphics.setColor(.07,.05,.035,1)
    love.graphics.rectangle("fill",0,0,width,height)
    love.graphics.setColor(1,1,1,1)
    local view=Home.officeView
    if image then love.graphics.draw(image,view.x,view.y,0,width*view.scale/image:getWidth(),height*view.scale/image:getHeight())
    else love.graphics.clear(.22,.16,.10) end
end

return Art
