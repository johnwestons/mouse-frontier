local WideLayout={}

function WideLayout.measure(width,height,windowWidth,windowHeight)
    local scale=math.min(windowWidth/width,windowHeight/height)
    local visibleWidth=windowWidth/scale
    local left=(width-visibleWidth)/2
    local right=left+visibleWidth
    local gutter=math.min(-left,right-width)
    -- 16:9 launches provide about 160 logical pixels on either side of the
    -- 960x720 stage. Use those gutters too, instead of falling back to the
    -- overlay HUD at common desktop and tablet resolutions.
    local sidePanels=gutter>=150
    return {
        visibleWidth=visibleWidth,left=left,right=right,gutter=gutter,
        sidePanels=sidePanels,
        leftX=left+10,rightX=width+10,
        panelWidth=sidePanels and math.min(180,gutter-20) or 0,
    }
end

return WideLayout
