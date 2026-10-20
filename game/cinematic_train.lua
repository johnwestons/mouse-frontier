-- Shared authored train artwork for the intro and title save windows.
local Train={railRatio=750/1086}
local consistBaselineRatio=584/724
local consistWidth=2172
-- The locomotive sheet has measured, nonuniform frame rectangles.
local frames={
    {x=0,y=0,w=371,h=443,rear=358,bodyWidth=350,baseline=344},
    {x=371,y=0,w=368,h=443,rear=363,bodyWidth=352,baseline=345},
    {x=739,y=0,w=339,h=443,rear=335,bodyWidth=331,baseline=345},
    {x=1078,y=0,w=336,h=443,rear=334,bodyWidth=332,baseline=345},
    {x=1414,y=0,w=360,h=443,rear=345,bodyWidth=345,baseline=345},
    {x=0,y=443,w=364,h=444,rear=360,bodyWidth=352,baseline=221},
    {x=364,y=443,w=365,h=444,rear=355,bodyWidth=352,baseline=221},
    {x=729,y=443,w=353,h=444,rear=350,bodyWidth=341,baseline=221},
    {x=1082,y=443,w=340,h=444,rear=336,bodyWidth=335,baseline=221},
    {x=1422,y=443,w=352,h=444,rear=339,bodyWidth=337,baseline=221},
}
local quads=setmetatable({},{__mode='k'})

function Train.rearExtent(scale)
    return (257+consistWidth*.12)*scale
end

function Train.draw(scenery,couplerX,railY,scale,clock,alpha)
    love.graphics.setColor(1,1,1,alpha or 1)
    local cars=scenery.introCars
    if cars then
        local carScale=.24*scale*consistWidth/cars:getWidth()
        love.graphics.draw(cars,couplerX+257*scale,railY,0,carScale,carScale,
            cars:getWidth()/2,cars:getHeight()*consistBaselineRatio)
    end
    local sheet=scenery.introLocomotiveSheet
    if sheet then
        local atlas=quads[sheet]
        if not atlas then
            atlas={}
            for index,frame in ipairs(frames)do
                atlas[index]=love.graphics.newQuad(frame.x,frame.y,frame.w,frame.h,sheet:getDimensions())
            end
            quads[sheet]=atlas
        end
        local index=(math.floor((clock or 0)*12)%#frames)+1
        local frame=frames[index]
        love.graphics.draw(sheet,atlas[index],couplerX,railY,0,.72*(355/frame.bodyWidth)*scale,
            .52*scale,frame.rear,frame.baseline)
    elseif scenery.introLocomotive then
        love.graphics.draw(scenery.introLocomotive,couplerX,railY,0,.15*scale,.15*scale,1741,782)
    end
end

return Train
