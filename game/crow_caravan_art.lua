-- Authored source rectangles and attachment pins for the Rookery cloth sprites.
-- This sheet is packed artwork, not a uniform grid: the strong-gust canopy
-- uses the spare gutter beside the fourth pose. Quads isolate every piece.
local Art={sourceWidth=1536,sourceHeight=1024}

Art.stallFrames={
    {
        canopy={x=0,y=0,w=768,h=344,leftPin={162,44},rightPin={610,60}},
        drape={x=0,y=344,w=768,h=168,leftPin={267,349},rightPin={443,358}},
    },
    {
        canopy={x=768,y=0,w=768,h=344,leftPin={914,44},rightPin={1379,60}},
        drape={x=768,y=344,w=768,h=168,leftPin={1027,345},rightPin={1216,356}},
    },
    {
        canopy={x=0,y=512,w=816,h=344,leftPin={148,554},rightPin={611,572}},
        drape={x=0,y=856,w=768,h=168,leftPin={276,862},rightPin={478,864}},
    },
    {
        canopy={x=816,y=512,w=720,h=344,leftPin={914,554},rightPin={1377,572}},
        drape={x=768,y=856,w=768,h=168,leftPin={1025,858},rightPin={1230,857}},
    },
}

function Art.stallAtlas(image,newQuad)
    assert(image,"Rookery cloth image is required")
    local width,height=image:getDimensions()
    local sx,sy=width/Art.sourceWidth,height/Art.sourceHeight
    local atlas={image=image,count=#Art.stallFrames,frames={}}
    for index,definition in ipairs(Art.stallFrames) do
        local frame={}
        for _,name in ipairs({"canopy","drape"}) do
            local part=definition[name]
            frame[name]={
                quad=newQuad(part.x*sx,part.y*sy,part.w*sx,part.h*sy,width,height),
                w=part.w*sx,h=part.h*sy,
                leftPin={x=(part.leftPin[1]-part.x)*sx,y=(part.leftPin[2]-part.y)*sy},
                rightPin={x=(part.rightPin[1]-part.x)*sx,y=(part.rightPin[2]-part.y)*sy},
            }
        end
        atlas.frames[index]=frame
    end
    return atlas
end

return Art
